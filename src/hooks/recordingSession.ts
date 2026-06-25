import * as Location from 'expo-location';

import type {
  RecordingProfile,
  RecordingProfileConfig,
} from '../services/RecordingProfile';
import type { TrackPoint } from '../services/TrackDataSource';

/**
 * Mutable accumulator for the in-flight foreground recording session. Held in a
 * ref by the hook so location callbacks can update counters without re-renders.
 */
export type ActiveSession = {
  sessionId: number;
  segmentId: number;
  profile: RecordingProfile;
  config: RecordingProfileConfig;
  startedAt: number;
  receivedCount: number;
  acceptedCount: number;
  rejectedCount: number;
  distanceMeters: number;
  lastAccepted: TrackPoint | null;
};

/**
 * Foreground-only permission gate. Throws if location services are off or the
 * foreground permission is denied — never requests background "Always" access.
 */
export async function requestForegroundPermission(): Promise<void> {
  if (!(await Location.hasServicesEnabledAsync())) {
    throw new Error('Location services are disabled');
  }
  const permission = await Location.requestForegroundPermissionsAsync();
  if (!permission.granted) {
    throw new Error('Foreground location permission denied');
  }
}
