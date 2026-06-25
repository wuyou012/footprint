import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';

import { shouldAcceptPoint } from './LocationFilter';
import { locationToTrackPoint } from './LocationPoint';
import {
  endProbeSession,
  getOpenProbeSessionId,
  incrementProbeTaskInvocation,
  recordProbeError,
  recordRawLocationEvent,
  startProbeSession,
} from './RawLocationStore';
import {
  DEFAULT_RECORDING_PROFILE,
  RECORDING_PROFILES,
  type RecordingProfile,
  type RecordingProfileConfig,
} from './RecordingProfile';
import type { TrackPoint } from './TrackDataSource';
import {
  appendTrackPoint,
  getLastTrackPoint,
  recordBackgroundLocationAccepted,
  recordBackgroundLocationError,
  recordBackgroundLocationReceived,
  recordBackgroundLocationRejected,
} from './TrackStore';

export const BACKGROUND_LOCATION_TASK = 'footprint-background-location';

const PROBE_PROFILE = 'probe_bg';
const PROBE_TIME_INTERVAL_MS = 10000;

type BackgroundLocationTaskData = {
  locations?: Location.LocationObject[];
};

export type ActiveBackgroundMode = 'idle' | 'record' | 'probe';

let activeMode: Exclude<ActiveBackgroundMode, 'idle'> = 'record';
let activeProfile: RecordingProfile = DEFAULT_RECORDING_PROFILE;
let activeProfileConfig: RecordingProfileConfig =
  RECORDING_PROFILES[DEFAULT_RECORDING_PROFILE];
let activeProbeSessionId: number | null = null;

function setActiveProfile(
  profile: RecordingProfile,
  config: RecordingProfileConfig,
): void {
  activeProfile = profile;
  activeProfileConfig = config;
}

function getLocations(data: BackgroundLocationTaskData | undefined): Location.LocationObject[] {
  return Array.isArray(data?.locations) ? data.locations : [];
}

async function resolveTaskMode(): Promise<{
  mode: Exclude<ActiveBackgroundMode, 'idle'>;
  probeSessionId: number | null;
}> {
  const openProbeSessionId =
    activeProbeSessionId ?? (await getOpenProbeSessionId('background'));

  if (activeMode === 'probe' || openProbeSessionId !== null) {
    activeMode = 'probe';
    activeProbeSessionId = openProbeSessionId;
    return { mode: 'probe', probeSessionId: openProbeSessionId };
  }

  return { mode: 'record', probeSessionId: null };
}

async function handleProbeLocations(
  locations: Location.LocationObject[],
  probeSessionId: number | null,
): Promise<void> {
  const taskInvokedAt = Date.now();
  await incrementProbeTaskInvocation(probeSessionId);

  for (const location of locations) {
    await recordRawLocationEvent({
      probeSessionId,
      source: 'background_task',
      appState: 'background',
      profile: PROBE_PROFILE,
      taskInvokedAt,
      locationCountInBatch: locations.length,
      location,
    });
  }
}

async function handleRecordLocations(
  locations: Location.LocationObject[],
): Promise<void> {
  let prevAccepted = await getLastTrackPoint();
  for (const location of locations) {
    const candidate: TrackPoint = {
      ...locationToTrackPoint(location),
      profile: activeProfile,
      source: 'gps',
    };
    await recordBackgroundLocationReceived(candidate);

    const decision = shouldAcceptPoint(
      prevAccepted,
      candidate,
      activeProfileConfig,
    );
    if (!decision.accept) {
      await recordBackgroundLocationRejected(candidate, decision.reason);
      continue;
    }

    await appendTrackPoint(candidate, {
      profile: activeProfile,
      source: 'gps',
    });
    await recordBackgroundLocationAccepted(candidate);
    prevAccepted = candidate;
  }
}

if (!TaskManager.isTaskDefined(BACKGROUND_LOCATION_TASK)) {
  TaskManager.defineTask<BackgroundLocationTaskData>(
    BACKGROUND_LOCATION_TASK,
    async ({ data, error }) => {
      const { mode, probeSessionId } = await resolveTaskMode();

      if (error) {
        if (mode === 'probe') {
          await recordProbeError(probeSessionId, error.message);
        } else {
          await recordBackgroundLocationError(error.message);
        }
        return;
      }

      try {
        const locations = getLocations(data);
        if (locations.length === 0) {
          return;
        }

        if (mode === 'probe') {
          await handleProbeLocations(locations, probeSessionId);
        } else {
          await handleRecordLocations(locations);
        }
      } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        if (mode === 'probe') {
          await recordProbeError(probeSessionId, message);
        } else {
          await recordBackgroundLocationError(message);
        }
      }
    },
  );
}

export async function isBackgroundRecording(): Promise<boolean> {
  return Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
}

export async function getActiveBackgroundMode(): Promise<ActiveBackgroundMode> {
  if (!(await isBackgroundRecording())) {
    return 'idle';
  }

  if (
    activeMode === 'probe' ||
    activeProbeSessionId !== null ||
    (await getOpenProbeSessionId('background')) !== null
  ) {
    return 'probe';
  }

  return 'record';
}

export async function requestBackgroundRecordingPermissions(): Promise<void> {
  if (!(await Location.hasServicesEnabledAsync())) {
    throw new Error('Location services are disabled');
  }

  const foregroundPermission =
    await Location.requestForegroundPermissionsAsync();
  if (!foregroundPermission.granted) {
    throw new Error('Foreground location permission denied');
  }

  const backgroundPermission =
    await Location.requestBackgroundPermissionsAsync();
  if (!backgroundPermission.granted) {
    throw new Error('Background location permission denied - choose Always Allow');
  }
}

export async function startBackgroundRecording(
  profile: RecordingProfile,
  config: RecordingProfileConfig,
  options: { permissionsGranted?: boolean } = {},
): Promise<void> {
  if (!options.permissionsGranted) {
    await requestBackgroundRecordingPermissions();
  }

  const openProbeSessionId =
    activeProbeSessionId ?? (await getOpenProbeSessionId('background'));
  if (openProbeSessionId !== null) {
    await endProbeSession(openProbeSessionId, 'record_started');
  }
  activeProbeSessionId = null;
  activeMode = 'record';
  setActiveProfile(profile, config);

  if (await isBackgroundRecording()) {
    await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  }

  await Location.startLocationUpdatesAsync(BACKGROUND_LOCATION_TASK, {
    accuracy: config.accuracy,
    timeInterval: config.timeInterval,
    distanceInterval: config.distanceInterval,
    pausesUpdatesAutomatically: false,
    foregroundService: {
      notificationTitle: 'footprint is recording',
      notificationBody: 'Tap to return to the app',
      notificationColor: '#0F766E',
    },
  });
}

export async function startBackgroundProbe(
  options: { permissionsGranted?: boolean } = {},
): Promise<number> {
  if (!options.permissionsGranted) {
    await requestBackgroundRecordingPermissions();
  }

  const openProbeSessionId =
    activeProbeSessionId ?? (await getOpenProbeSessionId('background'));
  if (openProbeSessionId !== null) {
    await endProbeSession(openProbeSessionId, 'replaced');
  }

  if (await isBackgroundRecording()) {
    await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  }

  const sessionId = await startProbeSession('background', PROBE_PROFILE);
  activeMode = 'probe';
  activeProbeSessionId = sessionId;

  try {
    await Location.startLocationUpdatesAsync(BACKGROUND_LOCATION_TASK, {
      accuracy: Location.Accuracy.Balanced,
      timeInterval: PROBE_TIME_INTERVAL_MS,
      distanceInterval: 0,
      pausesUpdatesAutomatically: false,
      foregroundService: {
        notificationTitle: 'footprint probe is recording',
        notificationBody: 'Collecting raw background GPS diagnostics',
        notificationColor: '#0F766E',
      },
    });
  } catch (e) {
    await endProbeSession(sessionId, 'start_failed');
    activeProbeSessionId = null;
    activeMode = 'record';
    throw e;
  }

  return sessionId;
}

export async function stopBackgroundProbe(): Promise<void> {
  const sessionId =
    activeProbeSessionId ?? (await getOpenProbeSessionId('background'));
  if (await isBackgroundRecording()) {
    await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  }
  await endProbeSession(sessionId, 'stopped');
  activeProbeSessionId = null;
  activeMode = 'record';
}

export async function stopBackgroundRecording(): Promise<void> {
  if (await isBackgroundRecording()) {
    await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  }
  activeMode = 'record';
}
