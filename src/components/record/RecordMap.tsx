import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import { useMemo } from 'react';
import { StyleSheet } from 'react-native';

import type { LngLat } from '../../services/CoordinateService';
import { getMapProvider } from '../../services/MapProvider';
import type { TrackPoint } from '../../services/TrackDataSource';
import {
  buildTrackFeatureCollection,
  featureCollectionCenter,
} from '../../utils/trackGeoJson';

const mapProvider = getMapProvider();
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];
const TRACK_ZOOM = 14;

type RecordMapProps = {
  points: readonly TrackPoint[];
};

/**
 * Renders persisted track points as per-segment polylines. Memoised on
 * `points` so the unrelated 1s stats tick never re-builds the GeoJSON.
 */
export function RecordMap({ points }: RecordMapProps) {
  const routeFeature = useMemo(
    () =>
      buildTrackFeatureCollection(points, {
        targetSystem: mapProvider.coordinateSystem,
        providerId: mapProvider.id,
      }),
    [points],
  );
  const center = useMemo(
    () => featureCollectionCenter(routeFeature, FALLBACK_CENTER),
    [routeFeature],
  );
  const hasTrack = routeFeature.features.length > 0;

  return (
    <Map style={styles.map} mapStyle={mapProvider.buildingStyles['2d']}>
      <Camera center={center} zoom={TRACK_ZOOM} />
      {hasTrack && (
        <GeoJSONSource id="track-source" data={routeFeature}>
          <Layer
            id="track-line"
            source="track-source"
            type="line"
            layout={{ 'line-cap': 'round', 'line-join': 'round' }}
            paint={{
              'line-color': '#0F766E',
              'line-opacity': 0.9,
              'line-width': 4,
            }}
          />
        </GeoJSONSource>
      )}
    </Map>
  );
}

const styles = StyleSheet.create({
  map: {
    flex: 1,
  },
});
