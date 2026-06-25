import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';

import { shouldAcceptPoint } from './LocationFilter';
import { locationToTrackPoint } from './LocationPoint';
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

type BackgroundLocationTaskData = {
  locations?: Location.LocationObject[];
};

let activeProfile: RecordingProfile = DEFAULT_RECORDING_PROFILE;
let activeProfileConfig: RecordingProfileConfig =
  RECORDING_PROFILES[DEFAULT_RECORDING_PROFILE];

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

if (!TaskManager.isTaskDefined(BACKGROUND_LOCATION_TASK)) {
  TaskManager.defineTask<BackgroundLocationTaskData>(
    BACKGROUND_LOCATION_TASK,
    async ({ data, error }) => {
      if (error) {
        await recordBackgroundLocationError(error.message);
        return;
      }

      try {
        const locations = getLocations(data);
        if (locations.length === 0) {
          return;
        }

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
            await recordBackgroundLocationRejected(
              candidate,
              decision.reason,
            );
            continue;
          }

          await appendTrackPoint(candidate, {
            profile: activeProfile,
            source: 'gps',
          });
          await recordBackgroundLocationAccepted(candidate);
          prevAccepted = candidate;
        }
      } catch (e) {
        await recordBackgroundLocationError(
          e instanceof Error ? e.message : String(e),
        );
      }
    },
  );
}

export async function isBackgroundRecording(): Promise<boolean> {
  return Location.hasStartedLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
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

export async function stopBackgroundRecording(): Promise<void> {
  if (await isBackgroundRecording()) {
    await Location.stopLocationUpdatesAsync(BACKGROUND_LOCATION_TASK);
  }
}
