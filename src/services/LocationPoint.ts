import * as Location from 'expo-location';

import type { TrackPoint } from './TrackDataSource';

export function finiteOrNull(value: number | null | undefined): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

export function locationToTrackPoint(
  location: Location.LocationObject,
): TrackPoint {
  const { longitude, latitude, accuracy, speed, altitude, heading } =
    location.coords;

  return {
    longitude,
    latitude,
    timestamp: location.timestamp,
    accuracy: finiteOrNull(accuracy),
    speed: finiteOrNull(speed),
    altitude: finiteOrNull(altitude),
    heading: finiteOrNull(heading),
  };
}
