import type { LngLat } from './CoordinateService';

/**
 * P1 track data source.
 *
 * Produces raw WGS-84 track points in memory. The `TrackPoint` shape is
 * aligned with the future P2 SQLite `track_points` table (lng / lat /
 * timestamp) so swapping this mock for a SQLite-backed source will not change
 * the render path in MapTestScreen.
 */
export type TrackPoint = {
  longitude: number;
  latitude: number;
  timestamp: number;
};

export type TrackDataSource = {
  getPoints(count: number): TrackPoint[];
};

const DEFAULT_ORIGIN: LngLat = [-122.4194, 37.7749];

/**
 * In-memory mock track source: a wandering walk from `origin`, roughly
 * 10-15 m per step with sinusoidal wobble so the rendered line looks like a
 * real footpath rather than a straight ruler. All output is raw WGS-84;
 * coordinate-system conversion happens later at render time, never here.
 */
export function createMockTrackDataSource(
  origin: LngLat = DEFAULT_ORIGIN,
): TrackDataSource {
  const [originLng, originLat] = origin;

  return {
    getPoints(count: number): TrackPoint[] {
      const points: TrackPoint[] = [];
      const startTime = Date.now() - count * 1000;

      for (let i = 0; i < count; i++) {
        const wobbleLng = Math.sin(i / 8) * 0.0006;
        const wobbleLat = Math.cos(i / 11) * 0.0004;
        points.push({
          longitude: originLng + i * 0.00012 + wobbleLng,
          latitude: originLat + i * 0.00009 + wobbleLat,
          timestamp: startTime + i * 1000,
        });
      }

      return points;
    },
  };
}

export function trackPointsToLngLat(points: readonly TrackPoint[]): LngLat[] {
  return points.map((point) => [point.longitude, point.latitude]);
}
