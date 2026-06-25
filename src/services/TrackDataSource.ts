import type { LngLat } from './CoordinateService';
import { getTrackPoints } from './TrackStore';

/**
 * Track point shape, matching the SQLite `track_points` table. Coordinates are
 * always raw WGS-84; coordinate-system conversion happens at render time.
 */
export type TrackPoint = {
  longitude: number;
  latitude: number;
  timestamp: number;
  accuracy?: number | null;
  speed?: number | null;
  altitude?: number | null;
  heading?: number | null;
  sessionId?: number | null;
  segmentId?: number | null;
  sourceId?: number | null;
  source?: string | null;
  profile?: string | null;
  localDayKey?: string | null;
};

/**
 * P2: the source is async because its backing store (SQLite) is async. This
 * replaces P1's synchronous `getPoints(): TrackPoint[]`.
 */
export type TrackDataSource = {
  getPoints(count: number): Promise<TrackPoint[]>;
};

const DEFAULT_ORIGIN: LngLat = [-122.4194, 37.7749];

/**
 * Pure generator: a wandering walk from `origin`, ~10-15 m per step with
 * sinusoidal wobble. Kept for later P3.6-D stress tests, not for production
 * cold-start seeding.
 */
export function generateMockWalk(
  count: number,
  origin: LngLat = DEFAULT_ORIGIN,
): TrackPoint[] {
  const [originLng, originLat] = origin;
  const points: TrackPoint[] = [];
  const startTime = Date.now() - count * 1000;

  for (let i = 0; i < count; i++) {
    points.push({
      longitude: originLng + i * 0.00012 + Math.sin(i / 8) * 0.0006,
      latitude: originLat + i * 0.00009 + Math.cos(i / 11) * 0.0004,
      timestamp: startTime + i * 1000,
      source: 'mock',
    });
  }

  return points;
}

/**
 * P2 source: reads persisted raw WGS-84 points from SQLite. Because reads come
 * from the DB, the rendered track survives an app restart.
 */
export function createSqliteTrackDataSource(): TrackDataSource {
  return {
    getPoints: (count: number) => getTrackPoints(count),
  };
}

export function trackPointsToLngLat(points: readonly TrackPoint[]): LngLat[] {
  return points.map((point) => [point.longitude, point.latitude]);
}
