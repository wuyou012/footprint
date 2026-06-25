import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import * as Location from 'expo-location';
import type { Feature, LineString } from 'geojson';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AppState, Text, TouchableOpacity, View } from 'react-native';

import {
  getActiveBackgroundMode,
  isBackgroundRecording,
  requestBackgroundRecordingPermissions,
  startBackgroundProbe as startBackgroundProbeTask,
  startBackgroundRecording,
  stopBackgroundProbe as stopBackgroundProbeTask,
  stopBackgroundRecording,
} from '../services/BackgroundLocation';
import {
  transformLineString,
  type LngLat,
} from '../services/CoordinateService';
import { exportTrackAsGpx } from '../services/GpxExport';
import {
  endProbeSession,
  exportProbeLog,
  getProbeSummary,
  recordRawLocationEvent,
  startProbeSession,
  type ProbeSessionSummary,
} from '../services/RawLocationStore';
import {
  getMapProvider,
  type BuildingStyleMode,
} from '../services/MapProvider';
import {
  DEFAULT_RECORDING_PROFILE,
  RECORDING_PROFILE_ORDER,
  RECORDING_PROFILES,
  type RecordingProfile,
} from '../services/RecordingProfile';
import {
  createSqliteTrackDataSource,
  trackPointsToLngLat,
  type TrackPoint,
} from '../services/TrackDataSource';
import {
  getLocationDiagnostics,
  replaceTrackPoints,
  resetBackgroundDiagnostics,
  type LocationDiagnosticSnapshot,
} from '../services/TrackStore';
import { styles } from './MapTestScreen.styles';

const mapProvider = getMapProvider();
const trackSource = createSqliteTrackDataSource();

const LOAD_CAP = 20000;
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];
const TRACK_ZOOM = 14;
const ACTIVE_REFRESH_INTERVAL_MS = 8000;
const FOREGROUND_PROBE_INTERVAL_MS = 5000;

const EMPTY_DIAGNOSTICS: LocationDiagnosticSnapshot = {
  backgroundReceivedCount: 0,
  backgroundAcceptedCount: 0,
  backgroundRejectedCount: 0,
  backgroundLastFixTs: null,
  backgroundLastAcceptedTs: null,
  backgroundLastRejectReason: null,
  backgroundLastError: null,
  rawReceivedCount: 0,
  rawLastFixTs: null,
  rawLastAccuracy: null,
  rawLastLongitude: null,
  rawLastLatitude: null,
  rawLastError: null,
  updatedTs: null,
};

function formatLocationError(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function formatClock(timestamp: number | null | undefined): string {
  if (!timestamp) {
    return 'never';
  }
  return new Date(timestamp).toLocaleTimeString();
}

function formatAccuracy(accuracy: number | null | undefined): string {
  return typeof accuracy === 'number' && Number.isFinite(accuracy)
    ? `${Math.round(accuracy)}m`
    : 'n/a';
}

function formatDelay(delayMs: number | null | undefined): string {
  return typeof delayMs === 'number' && Number.isFinite(delayMs)
    ? `${Math.round(delayMs / 1000)}s`
    : 'n/a';
}

function formatProbeLine(summary: ProbeSessionSummary | null): string {
  if (!summary) {
    return 'Probe: no session';
  }

  return `Probe #${summary.id} ${summary.mode} raw ${summary.rawCount} task ${summary.taskInvokedCount} last ${formatClock(summary.lastReceivedAt)} delay ${formatDelay(summary.lastDeliveryDelayMs)} acc ${formatAccuracy(summary.lastAccuracy)}`;
}

export function MapTestScreen() {
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [diagnostics, setDiagnostics] =
    useState<LocationDiagnosticSnapshot>(EMPTY_DIAGNOSTICS);
  const [probeSummary, setProbeSummary] =
    useState<ProbeSessionSummary | null>(null);
  const [busy, setBusy] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [recording, setRecording] = useState(false);
  const [recordingStatus, setRecordingStatus] = useState('GPS idle');
  const [foregroundProbeRunning, setForegroundProbeRunning] = useState(false);
  const [backgroundProbeRunning, setBackgroundProbeRunning] = useState(false);
  const [probeStatus, setProbeStatus] = useState('Probe idle');
  const [exporting, setExporting] = useState(false);
  const [exportingProbe, setExportingProbe] = useState(false);
  const busyRef = useRef(false);
  const exportingRef = useRef(false);
  const recordingRef = useRef(false);
  const foregroundProbeRef = useRef(false);
  const backgroundProbeRef = useRef(false);
  const probeSessionIdRef = useRef<number | null>(null);
  const foregroundProbeSubscriptionRef =
    useRef<Location.LocationSubscription | null>(null);
  const [buildingMode, setBuildingMode] = useState<BuildingStyleMode>('2d');
  const [recordingProfile, setRecordingProfile] =
    useState<RecordingProfile>(DEFAULT_RECORDING_PROFILE);
  const mountedRef = useRef(true);
  const recordingProfileConfig = RECORDING_PROFILES[recordingProfile];

  const loadPoints = useCallback(async (): Promise<void> => {
    const loaded = await trackSource.getPoints(LOAD_CAP);
    if (mountedRef.current) {
      setPoints(loaded);
    }
  }, []);

  const loadDiagnostics = useCallback(async (): Promise<void> => {
    const loaded = await getLocationDiagnostics();
    if (mountedRef.current) {
      setDiagnostics(loaded);
    }
  }, []);

  const loadProbeSummary = useCallback(async (): Promise<void> => {
    const loaded = await getProbeSummary(probeSessionIdRef.current);
    if (mountedRef.current) {
      setProbeSummary(loaded);
      if (loaded && probeSessionIdRef.current === null) {
        probeSessionIdRef.current = loaded.id;
      }
    }
  }, []);

  const refreshVisibleData = useCallback(async (): Promise<void> => {
    await Promise.all([loadPoints(), loadDiagnostics(), loadProbeSummary()]);
  }, [loadDiagnostics, loadPoints, loadProbeSummary]);

  const syncBackgroundState = useCallback(async (): Promise<void> => {
    const mode = await getActiveBackgroundMode();
    recordingRef.current = mode === 'record';
    backgroundProbeRef.current = mode === 'probe';
    if (mountedRef.current) {
      setRecording(mode === 'record');
      setBackgroundProbeRunning(mode === 'probe');
      setRecordingStatus((current) => {
        if (
          mode === 'record' &&
          (current === 'GPS idle' || current === 'GPS stopped')
        ) {
          return `Background ${recordingProfileConfig.label} recording`;
        }
        if (mode !== 'record' && current.startsWith('Background ')) {
          return 'GPS idle';
        }
        return current;
      });
      if (mode === 'probe') {
        setProbeStatus('Background probe recording');
      } else if (!foregroundProbeRef.current) {
        setProbeStatus((current) =>
          current === 'Background probe recording' ? 'Probe idle' : current,
        );
      }
    }
  }, [recordingProfileConfig.label]);

  useEffect(() => {
    mountedRef.current = true;
    busyRef.current = true;
    (async () => {
      try {
        await refreshVisibleData();
        await syncBackgroundState();
      } catch (e) {
        if (mountedRef.current) {
          setError(formatLocationError(e));
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
      foregroundProbeSubscriptionRef.current?.remove();
      foregroundProbeSubscriptionRef.current = null;
    };
  }, [refreshVisibleData, syncBackgroundState]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void refreshVisibleData();
        void syncBackgroundState();
      }
    });

    return () => {
      subscription.remove();
    };
  }, [refreshVisibleData, syncBackgroundState]);

  useEffect(() => {
    if (!recording && !foregroundProbeRunning && !backgroundProbeRunning) {
      return undefined;
    }

    const intervalId = setInterval(() => {
      void refreshVisibleData();
      void syncBackgroundState();
    }, ACTIVE_REFRESH_INTERVAL_MS);

    return () => {
      clearInterval(intervalId);
    };
  }, [
    backgroundProbeRunning,
    foregroundProbeRunning,
    recording,
    refreshVisibleData,
    syncBackgroundState,
  ]);

  async function stopRecording(): Promise<void> {
    if (busyRef.current || exportingRef.current) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      await stopBackgroundRecording();
      recordingRef.current = false;
      await refreshVisibleData();
      if (mountedRef.current) {
        setRecording(false);
        setRecordingStatus('GPS stopped');
      }
    } catch (e) {
      if (mountedRef.current) {
        setError(formatLocationError(e));
        setRecordingStatus('GPS stop failed');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }

  async function startRecording(): Promise<void> {
    if (
      busyRef.current ||
      recordingRef.current ||
      exportingRef.current ||
      foregroundProbeRef.current ||
      backgroundProbeRef.current
    ) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    setRecordingStatus(`Checking ${recordingProfileConfig.label} GPS...`);

    try {
      await requestBackgroundRecordingPermissions();
      await stopBackgroundRecording();
      await resetBackgroundDiagnostics();
      await replaceTrackPoints([]);
      if (mountedRef.current) {
        setPoints([]);
        setRecordingStatus('Starting background GPS...');
      }

      await startBackgroundRecording(recordingProfile, recordingProfileConfig, {
        permissionsGranted: true,
      });
      recordingRef.current = true;
      await refreshVisibleData();
      if (mountedRef.current) {
        setRecording(true);
        setRecordingStatus(
          `Background ${recordingProfileConfig.label} recording`,
        );
      }
    } catch (e) {
      recordingRef.current = false;
      if (mountedRef.current) {
        setRecording(false);
        setError(formatLocationError(e));
        setRecordingStatus('GPS unavailable');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }

  async function startForegroundProbe(): Promise<void> {
    if (
      busyRef.current ||
      recordingRef.current ||
      exportingRef.current ||
      foregroundProbeRef.current ||
      backgroundProbeRef.current
    ) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    setProbeStatus('Checking foreground probe...');

    let sessionId: number | null = null;
    try {
      if (!(await Location.hasServicesEnabledAsync())) {
        throw new Error('Location services are disabled');
      }

      const permission = await Location.requestForegroundPermissionsAsync();
      if (!permission.granted) {
        throw new Error('Foreground location permission denied');
      }

      sessionId = await startProbeSession('foreground', 'probe_static');
      probeSessionIdRef.current = sessionId;
      const subscription = await Location.watchPositionAsync(
        {
          accuracy: Location.Accuracy.Balanced,
          timeInterval: FOREGROUND_PROBE_INTERVAL_MS,
          distanceInterval: 0,
        },
        (location) => {
          void (async () => {
            try {
              await recordRawLocationEvent({
                probeSessionId: sessionId,
                source: 'foreground_watch',
                appState: 'foreground',
                profile: 'probe_static',
                taskInvokedAt: null,
                locationCountInBatch: 1,
                location,
              });
              await loadProbeSummary();
              if (mountedRef.current) {
                setProbeStatus('Foreground probe receiving');
              }
            } catch (e) {
              if (mountedRef.current) {
                setError(formatLocationError(e));
                setProbeStatus('Foreground probe write failed');
              }
            }
          })();
        },
        (reason) => {
          if (mountedRef.current) {
            setError(reason);
            setProbeStatus('Foreground probe error');
          }
        },
      );

      foregroundProbeSubscriptionRef.current = subscription;
      foregroundProbeRef.current = true;
      await loadProbeSummary();
      if (mountedRef.current) {
        setForegroundProbeRunning(true);
        setProbeStatus('Foreground probe waiting');
      }
    } catch (e) {
      foregroundProbeSubscriptionRef.current?.remove();
      foregroundProbeSubscriptionRef.current = null;
      if (sessionId !== null) {
        await endProbeSession(sessionId, 'start_failed');
      }
      probeSessionIdRef.current = null;
      foregroundProbeRef.current = false;
      if (mountedRef.current) {
        setForegroundProbeRunning(false);
        setError(formatLocationError(e));
        setProbeStatus('Foreground probe unavailable');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }

  async function startBackgroundProbe(): Promise<void> {
    if (
      busyRef.current ||
      recordingRef.current ||
      exportingRef.current ||
      foregroundProbeRef.current ||
      backgroundProbeRef.current
    ) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    setProbeStatus('Checking background probe...');

    try {
      await requestBackgroundRecordingPermissions();
      const sessionId = await startBackgroundProbeTask({
        permissionsGranted: true,
      });
      probeSessionIdRef.current = sessionId;
      backgroundProbeRef.current = true;
      await loadProbeSummary();
      if (mountedRef.current) {
        setBackgroundProbeRunning(true);
        setProbeStatus('Background probe recording');
      }
    } catch (e) {
      probeSessionIdRef.current = null;
      backgroundProbeRef.current = false;
      if (mountedRef.current) {
        setBackgroundProbeRunning(false);
        setError(formatLocationError(e));
        setProbeStatus('Background probe unavailable');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }

  async function stopProbe(): Promise<void> {
    if (busyRef.current || exportingRef.current) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);

    try {
      foregroundProbeSubscriptionRef.current?.remove();
      foregroundProbeSubscriptionRef.current = null;
      if (backgroundProbeRef.current || (await isBackgroundRecording())) {
        await stopBackgroundProbeTask();
      }
      if (foregroundProbeRef.current) {
        await endProbeSession(probeSessionIdRef.current, 'stopped');
      }
      foregroundProbeRef.current = false;
      backgroundProbeRef.current = false;
      await refreshVisibleData();
      if (mountedRef.current) {
        setForegroundProbeRunning(false);
        setBackgroundProbeRunning(false);
        setProbeStatus('Probe stopped');
      }
    } catch (e) {
      if (mountedRef.current) {
        setError(formatLocationError(e));
        setProbeStatus('Probe stop failed');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }

  async function exportGpx(): Promise<void> {
    if (busyRef.current || recordingRef.current || exportingRef.current) {
      return;
    }

    exportingRef.current = true;
    setExporting(true);
    setError(null);
    try {
      await exportTrackAsGpx(points);
    } catch (e) {
      if (mountedRef.current) {
        const message = formatLocationError(e);
        setError(
          /another share|being processed/i.test(message)
            ? 'A share is still open - close it, then tap Export again'
            : message,
        );
      }
    } finally {
      exportingRef.current = false;
      if (mountedRef.current) {
        setExporting(false);
      }
    }
  }

  async function exportProbe(): Promise<void> {
    if (busyRef.current || exportingRef.current || exportingProbe) {
      return;
    }

    setExportingProbe(true);
    setError(null);
    try {
      await exportProbeLog(probeSessionIdRef.current ?? probeSummary?.id);
    } catch (e) {
      if (mountedRef.current) {
        const message = formatLocationError(e);
        setError(
          /another share|being processed/i.test(message)
            ? 'A share is still open - close it, then tap Export Probe again'
            : message,
        );
      }
    } finally {
      if (mountedRef.current) {
        setExportingProbe(false);
      }
    }
  }

  const routeFeature = useMemo<Feature<LineString>>(() => {
    const rawPoints = trackPointsToLngLat(points);
    const renderCoords = transformLineString(
      rawPoints,
      'WGS84',
      mapProvider.coordinateSystem,
    );
    return {
      type: 'Feature',
      properties: {
        id: 'p4-track',
        provider: mapProvider.id,
        points: points.length,
      },
      geometry: { type: 'LineString', coordinates: renderCoords },
    };
  }, [points]);

  const cameraCenter = useMemo<LngLat>(() => {
    const coords = routeFeature.geometry.coordinates as LngLat[];
    return coords[Math.floor(coords.length / 2)] ?? FALLBACK_CENTER;
  }, [routeFeature]);

  const backgroundLine = useMemo(() => {
    const last =
      diagnostics.backgroundLastAcceptedTs ??
      diagnostics.backgroundLastFixTs;
    const errorText = diagnostics.backgroundLastError
      ? ` err ${diagnostics.backgroundLastError}`
      : '';
    const rejectText = diagnostics.backgroundLastRejectReason
      ? ` reject ${diagnostics.backgroundLastRejectReason}`
      : '';
    return `Record ${diagnostics.backgroundAcceptedCount}/${diagnostics.backgroundReceivedCount} accepted - last ${formatClock(last)}${rejectText}${errorText}`;
  }, [diagnostics]);

  const probeLine = useMemo(() => formatProbeLine(probeSummary), [probeSummary]);

  const hasTrack = points.length >= 2;
  const probeRunning = foregroundProbeRunning || backgroundProbeRunning;
  const recordingButtonDisabled = (busy && !recording) || probeRunning;
  const probeStartDisabled = busy || recording || exporting || probeRunning;
  const probeStopDisabled = busy || !probeRunning;
  const exportDisabled = busy || recording || exporting || points.length === 0;
  const exportProbeDisabled =
    busy || exportingProbe || probeSummary === null || probeRunning;
  const profileSwitchDisabled = busy || recording || exporting || probeRunning;

  return (
    <View style={styles.container}>
      <Map
        style={styles.map}
        mapStyle={mapProvider.buildingStyles[buildingMode]}
      >
        <Camera center={cameraCenter} zoom={TRACK_ZOOM} />
        {hasTrack && (
          <GeoJSONSource id="track-source" data={routeFeature}>
            <Layer
              id="track-line"
              source="track-source"
              type="line"
              layout={{ 'line-cap': 'round', 'line-join': 'round' }}
              paint={{
                'line-color': '#0F766E',
                'line-opacity': 0.9,
                'line-width': 4,
              }}
            />
          </GeoJSONSource>
        )}
      </Map>

      <View style={styles.badge}>
        <Text style={styles.badgeText}>
          {error
            ? `! ${error}`
            : busy
              ? 'Loading...'
              : `${points.length.toLocaleString()} pts - ${
                  recording ? 'BG GPS' : 'SQLite'
                }`}
        </Text>
      </View>

      <View style={styles.recordingPanel}>
        <TouchableOpacity
          disabled={recordingButtonDisabled}
          style={[
            styles.recordButton,
            recording && styles.recordButtonActive,
            recordingButtonDisabled && styles.recordButtonDisabled,
          ]}
          onPress={() => {
            if (recording) {
              void stopRecording();
            } else {
              void startRecording();
            }
          }}
        >
          <Text style={styles.recordButtonText}>
            {recording ? 'Stop GPS' : 'Start GPS'}
          </Text>
        </TouchableOpacity>
        <Text style={styles.recordingStatusText}>{recordingStatus}</Text>
      </View>

      <View style={styles.validationPanel}>
        <Text style={styles.validationLabel}>{backgroundLine}</Text>
        <Text style={styles.validationLabel}>{probeLine}</Text>
        <Text style={styles.validationLabel}>{probeStatus}</Text>
        <View style={styles.zoomRow}>
          {RECORDING_PROFILE_ORDER.map((profile) => {
            const active = recordingProfile === profile;
            return (
              <TouchableOpacity
                key={profile}
                disabled={profileSwitchDisabled}
                style={[
                  styles.zoomButton,
                  active && styles.zoomButtonActive,
                  profileSwitchDisabled && styles.buttonDisabled,
                ]}
                onPress={() => {
                  if (
                    !busyRef.current &&
                    !recordingRef.current &&
                    !exportingRef.current &&
                    !foregroundProbeRef.current &&
                    !backgroundProbeRef.current
                  ) {
                    setRecordingProfile(profile);
                  }
                }}
              >
                <Text
                  style={[
                    styles.zoomButtonText,
                    active && styles.zoomButtonTextActive,
                  ]}
                >
                  {RECORDING_PROFILES[profile].label}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>
        <View style={styles.zoomRow}>
          {(['2d', '3d'] as const).map((mode) => {
            const active = buildingMode === mode;
            return (
              <TouchableOpacity
                key={mode}
                style={[styles.zoomButton, active && styles.zoomButtonActive]}
                onPress={() => {
                  setBuildingMode(mode);
                }}
              >
                <Text
                  style={[
                    styles.zoomButtonText,
                    active && styles.zoomButtonTextActive,
                  ]}
                >
                  {mode.toUpperCase()}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>
        <View style={styles.zoomRow}>
          <TouchableOpacity
            disabled={probeStartDisabled}
            style={[styles.zoomButton, probeStartDisabled && styles.buttonDisabled]}
            onPress={() => {
              void startForegroundProbe();
            }}
          >
            <Text style={styles.zoomButtonText}>FG Probe</Text>
          </TouchableOpacity>
          <TouchableOpacity
            disabled={probeStartDisabled}
            style={[styles.zoomButton, probeStartDisabled && styles.buttonDisabled]}
            onPress={() => {
              void startBackgroundProbe();
            }}
          >
            <Text style={styles.zoomButtonText}>BG Probe</Text>
          </TouchableOpacity>
          <TouchableOpacity
            disabled={probeStopDisabled}
            style={[styles.zoomButton, probeStopDisabled && styles.buttonDisabled]}
            onPress={() => {
              void stopProbe();
            }}
          >
            <Text style={styles.zoomButtonText}>Stop Probe</Text>
          </TouchableOpacity>
        </View>
      </View>

      <View style={styles.controls}>
        <TouchableOpacity
          disabled={exportProbeDisabled}
          style={[styles.button, exportProbeDisabled && styles.buttonDisabled]}
          onPress={() => {
            void exportProbe();
          }}
        >
          <Text style={styles.buttonText}>
            {exportingProbe ? 'Exporting Probe' : 'Export Probe'}
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          disabled={exportDisabled}
          style={[styles.button, exportDisabled && styles.buttonDisabled]}
          onPress={() => {
            void exportGpx();
          }}
        >
          <Text style={styles.buttonText}>
            {exporting ? 'Exporting' : 'Export GPX'}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}
