import type { TrackPoint } from './TrackDataSource';

export type TrackPointRejectReason =
  | 'invalid'
  | 'accuracy'
  | 'too_close'
  | 'too_soon'
  | 'jump';

export type TrackPointFilterProfile = {
  maxAcceptedAccuracyMeters: number;
  minDistanceMeters: number;
  minIntervalMs: number;
  maxSpeedMetersPerSecond: number;
};

export type TrackPointAcceptance =
  | {
      accept: true;
      distanceMeters: number | null;
      elapsedMs: number | null;
    }
  | {
      accept: false;
      reason: TrackPointRejectReason;
      distanceMeters: number | null;
      elapsedMs: number | null;
    };

const EARTH_RADIUS_METERS = 6371008.8;

function toRadians(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

export function distanceMeters(a: TrackPoint, b: TrackPoint): number {
  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);
  const deltaLat = toRadians(b.latitude - a.latitude);
  const deltaLng = toRadians(b.longitude - a.longitude);

  const sinLat = Math.sin(deltaLat / 2);
  const sinLng = Math.sin(deltaLng / 2);
  const h =
    sinLat * sinLat +
    Math.cos(lat1) * Math.cos(lat2) * sinLng * sinLng;
  const clamped = Math.min(1, Math.max(0, h));

  return (
    2 *
    EARTH_RADIUS_METERS *
    Math.atan2(Math.sqrt(clamped), Math.sqrt(1 - clamped))
  );
}

function hasValidPosition(point: TrackPoint): boolean {
  return (
    Number.isFinite(point.longitude) &&
    Number.isFinite(point.latitude) &&
    Math.abs(point.longitude) <= 180 &&
    Math.abs(point.latitude) <= 90 &&
    Number.isFinite(point.timestamp) &&
    point.timestamp > 0
  );
}

export function shouldAcceptPoint(
  prevAccepted: TrackPoint | null,
  candidate: TrackPoint,
  profile: TrackPointFilterProfile,
): TrackPointAcceptance {
  if (!hasValidPosition(candidate)) {
    return { accept: false, reason: 'invalid', distanceMeters: null, elapsedMs: null };
  }

  if (
    candidate.accuracy !== null &&
    candidate.accuracy !== undefined &&
    (!Number.isFinite(candidate.accuracy) ||
      candidate.accuracy > profile.maxAcceptedAccuracyMeters)
  ) {
    return { accept: false, reason: 'accuracy', distanceMeters: null, elapsedMs: null };
  }

  if (!prevAccepted) {
    return { accept: true, distanceMeters: null, elapsedMs: null };
  }

  const elapsedMs = candidate.timestamp - prevAccepted.timestamp;
  if (!Number.isFinite(elapsedMs) || elapsedMs < 0) {
    return { accept: false, reason: 'invalid', distanceMeters: null, elapsedMs: null };
  }

  const distance = distanceMeters(prevAccepted, candidate);
  if (!Number.isFinite(distance)) {
    return { accept: false, reason: 'invalid', distanceMeters: null, elapsedMs };
  }

  if (elapsedMs < profile.minIntervalMs) {
    return { accept: false, reason: 'too_soon', distanceMeters: distance, elapsedMs };
  }

  if (distance < profile.minDistanceMeters) {
    return { accept: false, reason: 'too_close', distanceMeters: distance, elapsedMs };
  }

  const elapsedSeconds = elapsedMs / 1000;
  if (
    elapsedSeconds > 0 &&
    distance / elapsedSeconds > profile.maxSpeedMetersPerSecond
  ) {
    return { accept: false, reason: 'jump', distanceMeters: distance, elapsedMs };
  }

  return { accept: true, distanceMeters: distance, elapsedMs };
}
