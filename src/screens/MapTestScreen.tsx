import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import type { Feature, LineString } from 'geojson';
import { useMemo, useState } from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import {
  transformLineString,
  type LngLat,
} from '../services/CoordinateService';
import { getMapProvider } from '../services/MapProvider';
import {
  createMockTrackDataSource,
  trackPointsToLngLat,
} from '../services/TrackDataSource';

const mapProvider = getMapProvider();
const trackSource = createMockTrackDataSource();

const POINT_COUNTS = [100, 1000, 10000] as const;
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];

export function MapTestScreen() {
  const [pointCount, setPointCount] = useState<number>(POINT_COUNTS[0]);

  // P1 seam: raw WGS-84 (mock source today, SQLite in P2) is converted to the
  // active provider's coordinate system at render time — we never store
  // pre-transformed coordinates. Phase 1 provider is WGS-84 so this is a
  // passthrough, but the seam is real and ready for GCJ-02 / BD-09 later.
  const routeFeature = useMemo<Feature<LineString>>(() => {
    const rawPoints = trackPointsToLngLat(trackSource.getPoints(pointCount));
    const renderCoords = transformLineString(
      rawPoints,
      'WGS84',
      mapProvider.coordinateSystem,
    );
    return {
      type: 'Feature',
      properties: {
        id: 'p1-track',
        provider: mapProvider.id,
        points: pointCount,
      },
      geometry: { type: 'LineString', coordinates: renderCoords },
    };
  }, [pointCount]);

  const center = useMemo<LngLat>(() => {
    const coords = routeFeature.geometry.coordinates as LngLat[];
    return coords[Math.floor(coords.length / 2)] ?? FALLBACK_CENTER;
  }, [routeFeature]);

  return (
    <View style={styles.container}>
      <Map style={styles.map} mapStyle={mapProvider.mapStyle}>
        <Camera center={center} zoom={12} />
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
      </Map>

      <View style={styles.controls}>
        {POINT_COUNTS.map((count) => {
          const active = pointCount === count;
          return (
            <TouchableOpacity
              key={count}
              style={[styles.button, active && styles.buttonActive]}
              onPress={() => setPointCount(count)}
            >
              <Text
                style={[styles.buttonText, active && styles.buttonTextActive]}
              >
                {count.toLocaleString()}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F8FAFC',
  },
  map: {
    flex: 1,
  },
  controls: {
    position: 'absolute',
    bottom: 40,
    alignSelf: 'center',
    flexDirection: 'row',
    backgroundColor: 'rgba(15,23,42,0.85)',
    borderRadius: 24,
    padding: 4,
  },
  button: {
    paddingVertical: 8,
    paddingHorizontal: 18,
    borderRadius: 20,
  },
  buttonActive: {
    backgroundColor: '#0F766E',
  },
  buttonText: {
    color: '#CBD5E1',
    fontSize: 13,
    fontWeight: '600',
  },
  buttonTextActive: {
    color: '#FFFFFF',
  },
});
