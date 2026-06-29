import type { Feature, FeatureCollection, LineString } from 'geojson';

import {
  transformLineString,
  type CoordinateSystem,
  type LngLat,
} from '../services/CoordinateService';
import type { TrackPoint } from '../services/TrackDataSource';

const LEGACY_SEGMENT_KEY = 'legacy';

export type TrackFeatureOptions = {
  /** Coordinate system the map provider expects render coordinates in. */
  targetSystem: CoordinateSystem;
  /** Map provider id, attached to feature properties for debugging. */
  providerId: string;
};

/**
 * Group accepted track points into per-segment GeoJSON LineStrings. Points with
 * no `segmentId` (legacy rows recorded before F0's session model) collapse into
 * one `legacy` segment so they still draw as a single line, not isolated dots.
 *
 * Segments with fewer than two points are dropped — a LineString needs ≥2
 * coordinates to render.
 */
export function buildTrackFeatureCollection(
  points: readonly TrackPoint[],
  options: TrackFeatureOptions,
): FeatureCollection<LineString> {
  const segments: Array<{ key: string; points: TrackPoint[] }> = [];
  const segmentIndex = new globalThis.Map<string, TrackPoint[]>();

  for (const point of points) {
    const key =
      point.segmentId !== null && point.segmentId !== undefined
        ? `segment-${point.segmentId}`
        : LEGACY_SEGMENT_KEY;
    let segment = segmentIndex.get(key);
    if (!segment) {
      segment = [];
      segmentIndex.set(key, segment);
      segments.push({ key, points: segment });
    }
    segment.push(point);
  }

  const features = segments
    .map<Feature<LineString> | null>((segment) => {
      if (segment.points.length < 2) {
        return null;
      }
      const rawCoords = segment.points.map<LngLat>((point) => [
        point.longitude,
        point.latitude,
      ]);
      const renderCoords = transformLineString(
        rawCoords,
        'WGS84',
        options.targetSystem,
      );
      return {
        type: 'Feature',
        properties: {
          id: segment.key,
          provider: options.providerId,
          points: segment.points.length,
        },
        geometry: { type: 'LineString', coordinates: renderCoords },
      };
    })
    .filter((feature): feature is Feature<LineString> => feature !== null);

  return { type: 'FeatureCollection', features };
}

/** Pick a stable-ish camera center: the midpoint coordinate of all features. */
export function featureCollectionCenter(
  collection: FeatureCollection<LineString>,
  fallback: LngLat,
): LngLat {
  const coords = collection.features.flatMap(
    (feature) => feature.geometry.coordinates as LngLat[],
  );
  return coords[Math.floor(coords.length / 2)] ?? fallback;
}
