import * as Location from 'expo-location';

import type { TrackPointFilterProfile } from './LocationFilter';

export type RecordingProfile = 'daily' | 'eco';

export type RecordingProfileConfig = TrackPointFilterProfile & {
  label: string;
  accuracy: Location.LocationAccuracy;
  timeInterval: number;
  distanceInterval: number;
};

export const DEFAULT_RECORDING_PROFILE: RecordingProfile = 'daily';
export const RECORDING_PROFILE_ORDER = ['daily', 'eco'] as const;

export const RECORDING_PROFILES: Record<
  RecordingProfile,
  RecordingProfileConfig
> = {
  daily: {
    label: 'Daily',
    accuracy: Location.Accuracy.Balanced,
    timeInterval: 30000,
    distanceInterval: 50,
    maxAcceptedAccuracyMeters: 200,
    minDistanceMeters: 30,
    minIntervalMs: 20000,
    maxSpeedMetersPerSecond: 70,
  },
  eco: {
    label: 'Eco',
    // TODO(P3.6): compare Balanced vs Low on the P30 before lowering accuracy.
    accuracy: Location.Accuracy.Balanced,
    timeInterval: 60000,
    distanceInterval: 100,
    maxAcceptedAccuracyMeters: 300,
    minDistanceMeters: 80,
    minIntervalMs: 60000,
    maxSpeedMetersPerSecond: 70,
  },
};
