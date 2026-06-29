import { activateKeepAwakeAsync, deactivateKeepAwake } from 'expo-keep-awake';
import * as Location from 'expo-location';
import { useCallback, useEffect, useRef, useState } from 'react';

import { stopBackgroundRecording } from '../services/BackgroundLocation';
import { shouldAcceptPoint } from '../services/LocationFilter';
import { locationToTrackPoint } from '../services/LocationPoint';
import {
  RECORDING_PROFILES,
  type RecordingProfile,
} from '../services/RecordingProfile';
import {
  createSqliteTrackDataSource,
  type TrackPoint,
} from '../services/TrackDataSource';
import {
  appendTrackPoint,
  finishRecordingSession,
  getLocalDayKey,
  getTimezoneOffsetMin,
  interruptOpenForegroundRecordingSessions,
  startRecordingSession,
  startTrackSegment,
} from '../services/TrackStore';
import { formatError } from '../utils/format';
import {
  requestForegroundPermission,
  type ActiveSession,
} from './recordingSession';
import { IDLE_STATS, type RecordingStats } from './recordingStats';

const trackSource = createSqliteTrackDataSource();
const LOAD_CAP = 20000;
const KEEP_AWAKE_TAG = 'footprint-foreground-recording';
const STATS_TICK_MS = 1000;

export type UseForegroundRecording = {
  recording: boolean;
  busy: boolean;
  error: string | null;
  status: string;
  points: TrackPoint[];
  stats: RecordingStats;
  start: (profile: RecordingProfile) => Promise<void>;
  stop: () => Promise<void>;
  reload: () => Promise<void>;
};

/**
 * Owns the foreground recording lifecycle: GPS subscription, session/segment
 * creation, point filtering + append, keep-awake, and live stats. This is the
 * F0/F1 product path only — no background tasks, no diagnostics probes. Start
 * never clears history; it appends a brand-new session (F0 invariant).
 */
export function useForegroundRecording(): UseForegroundRecording {
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [recording, setRecording] = useState(false);
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('Idle');
  const [stats, setStats] = useState<RecordingStats>(IDLE_STATS);

  const mountedRef = useRef(true);
  const busyRef = useRef(false);
  const sessionRef = useRef<ActiveSession | null>(null);
  const subscriptionRef = useRef<Location.LocationSubscription | null>(null);
  const writeQueueRef = useRef<Promise<void>>(Promise.resolve());

  const loadPoints = useCallback(async (): Promise<void> => {
    const loaded = await trackSource.getPoints(LOAD_CAP);
    if (mountedRef.current) {
      setPoints(loaded);
    }
  }, []);

  const refreshStats = useCallback((): void => {
    const session = sessionRef.current;
    if (!session) {
      setStats(IDLE_STATS);
      return;
    }
    setStats({
      startedAt: session.startedAt,
      durationMs: Date.now() - session.startedAt,
      distanceMeters: session.distanceMeters,
      acceptedCount: session.acceptedCount,
      receivedCount: session.receivedCount,
      lastFixTs: session.lastAccepted?.timestamp ?? null,
      lastAccuracy: session.lastAccepted?.accuracy ?? null,
    });
  }, []);

  // Initial load + recover any session left open by a crash/kill (F0).
  useEffect(() => {
    mountedRef.current = true;
    busyRef.current = true;
    void (async () => {
      try {
        await stopBackgroundRecording();
        await interruptOpenForegroundRecordingSessions('replaced');
        await loadPoints();
      } catch (e) {
        if (mountedRef.current) {
          setError(formatError(e));
        }
      } finally {
        busyRef.current = false;
        if (mountedRef.current) {
          setBusy(false);
        }
      }
    })();
    return () => {
      mountedRef.current = false;
      subscriptionRef.current?.remove();
      subscriptionRef.current = null;
      void deactivateKeepAwake(KEEP_AWAKE_TAG);
    };
  }, [loadPoints]);

  // Tick live duration while recording so the timer advances without new fixes.
  useEffect(() => {
    if (!recording) {
      return undefined;
    }
    const id = setInterval(refreshStats, STATS_TICK_MS);
    return () => clearInterval(id);
  }, [recording, refreshStats]);

  const handleLocation = useCallback(
    async (location: Location.LocationObject): Promise<void> => {
      const session = sessionRef.current;
      if (!session) {
        return;
      }
      const localDayKey = getLocalDayKey(location.timestamp);
      const candidate: TrackPoint = {
        ...locationToTrackPoint(location),
        sessionId: session.sessionId,
        segmentId: session.segmentId,
        source: 'gps',
        profile: session.profile,
        localDayKey,
      };
      session.receivedCount += 1;

      const decision = shouldAcceptPoint(
        session.lastAccepted,
        candidate,
        session.config,
      );
      if (!decision.accept) {
        session.rejectedCount += 1;
        refreshStats();
        return;
      }

      await appendTrackPoint(candidate, {
        sessionId: session.sessionId,
        segmentId: session.segmentId,
        source: 'gps',
        profile: session.profile,
        localDayKey,
      });
      session.acceptedCount += 1;
      session.distanceMeters += decision.distanceMeters ?? 0;
      session.lastAccepted = candidate;
      await loadPoints();
      refreshStats();
    },
    [loadPoints, refreshStats],
  );

  const enqueueLocation = useCallback(
    (location: Location.LocationObject): void => {
      writeQueueRef.current = writeQueueRef.current
        .then(() => handleLocation(location))
        .catch((e) => {
          if (mountedRef.current) {
            setError(formatError(e));
            setStatus('GPS write failed');
          }
        });
    },
    [handleLocation],
  );

  const start = useCallback(
    async (profile: RecordingProfile): Promise<void> => {
      if (busyRef.current || sessionRef.current) {
        return;
      }
      const config = RECORDING_PROFILES[profile];
      busyRef.current = true;
      setBusy(true);
      setError(null);
      setStatus(`Checking ${config.label} GPS…`);

      let sessionId: number | null = null;
      let segmentId: number | null = null;
      try {
        await requestForegroundPermission();
        const startedAt = Date.now();
        const localDayKey = getLocalDayKey(startedAt);
        const timezoneOffsetMin = getTimezoneOffsetMin(startedAt);
        sessionId = await startRecordingSession({
          profile,
          source: 'foreground',
          startTs: startedAt,
          localDayKey,
          timezoneOffsetMin,
        });
        segmentId = await startTrackSegment({
          sessionId,
          startTs: startedAt,
          localDayKey,
        });
        sessionRef.current = {
          sessionId,
          segmentId,
          profile,
          config,
          startedAt,
          receivedCount: 0,
          acceptedCount: 0,
          rejectedCount: 0,
          distanceMeters: 0,
          lastAccepted: null,
        };
        await activateKeepAwakeAsync(KEEP_AWAKE_TAG);
        const subscription = await Location.watchPositionAsync(
          {
            accuracy: config.accuracy,
            timeInterval: config.timeInterval,
            distanceInterval: config.distanceInterval,
          },
          enqueueLocation,
          (reason) => {
            if (mountedRef.current) {
              setError(reason);
              setStatus('GPS error');
            }
          },
        );
        subscriptionRef.current = subscription;
        if (mountedRef.current) {
          setRecording(true);
          setStatus(`${config.label} recording`);
          refreshStats();
        }
      } catch (e) {
        subscriptionRef.current?.remove();
        subscriptionRef.current = null;
        await deactivateKeepAwake(KEEP_AWAKE_TAG);
        if (sessionId !== null) {
          await finishRecordingSession({
            sessionId,
            segmentId,
            endTs: Date.now(),
            status: 'start_failed',
            stopReason: 'start_failed',
          });
        }
        sessionRef.current = null;
        if (mountedRef.current) {
          setRecording(false);
          setError(formatError(e));
          setStatus('GPS unavailable');
        }
      } finally {
        busyRef.current = false;
        if (mountedRef.current) {
          setBusy(false);
        }
      }
    },
    [enqueueLocation, refreshStats],
  );

  const stop = useCallback(async (): Promise<void> => {
    if (busyRef.current) {
      return;
    }
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      subscriptionRef.current?.remove();
      subscriptionRef.current = null;
      await writeQueueRef.current;

      const session = sessionRef.current;
      if (session) {
        await finishRecordingSession({
          sessionId: session.sessionId,
          segmentId: session.segmentId,
          endTs: Date.now(),
          status: 'completed',
          stopReason: 'stopped',
          receivedCount: session.receivedCount,
          rejectedCount: session.rejectedCount,
          distanceMeters: session.distanceMeters,
        });
      }
      await deactivateKeepAwake(KEEP_AWAKE_TAG);
      sessionRef.current = null;
      await loadPoints();
      if (mountedRef.current) {
        setRecording(false);
        setStatus('Stopped');
        setStats(IDLE_STATS);
      }
    } catch (e) {
      if (mountedRef.current) {
        setError(formatError(e));
        setStatus('Stop failed');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }, [loadPoints]);

  return {
    recording,
    busy,
    error,
    status,
    points,
    stats,
    start,
    stop,
    reload: loadPoints,
  };
}
