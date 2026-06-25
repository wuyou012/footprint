import * as Location from 'expo-location';

import type { TrackPointFilterProfile } from './LocationFilter';

export type RecordingProfile = 'high' | 'daily' | 'eco';

export type RecordingProfileConfig = TrackPointFilterProfile & {
  label: string;
  /** Short product-facing copy shown on the mode-selection card. */
  description: string;
  accuracy: Location.LocationAccuracy;
  timeInterval: number;
  distanceInterval: number;
};

export const DEFAULT_RECORDING_PROFILE: RecordingProfile = 'daily';
export const RECORDING_PROFILE_ORDER = ['high', 'daily', 'eco'] as const;

export const RECORDING_PROFILES: Record<
  RecordingProfile,
  RecordingProfileConfig
> = {
  high: {
    label: 'High',
    description: 'Finer track, higher battery. Best for short walks.',
    accuracy: Location.Accuracy.High,
    timeInterval: 2000,
    distanceInterval: 10,
    maxAcceptedAccuracyMeters: 100,
    minDistanceMeters: 8,
    minIntervalMs: 1000,
    maxSpeedMetersPerSecond: 70,
  },
  daily: {
    label: 'Daily',
    description: 'Balanced for city walks & commutes. Recommended.',
    accuracy: Location.Accuracy.Balanced,
    timeInterval: 15000,
    distanceInterval: 25,
    maxAcceptedAccuracyMeters: 200,
    minDistanceMeters: 25,
    minIntervalMs: 10000,
    maxSpeedMetersPerSecond: 70,
  },
  eco: {
    label: 'Eco',
    description: 'Saves battery, coarser track. May skip small turns.',
    accuracy: Location.Accuracy.Balanced,
    timeInterval: 45000,
    distanceInterval: 80,
    maxAcceptedAccuracyMeters: 300,
    minDistanceMeters: 70,
    minIntervalMs: 30000,
    maxSpeedMetersPerSecond: 70,
  },
};
