import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import type { Feature, LineString } from 'geojson';
import { useEffect, useMemo, useState } from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import {
  transformLineString,
  type LngLat,
} from '../services/CoordinateService';
import { getMapProvider } from '../services/MapProvider';
import {
  createSqliteTrackDataSource,
  generateMockWalk,
  trackPointsToLngLat,
  type TrackPoint,
} from '../services/TrackDataSource';
import { countTrackPoints, replaceTrackPoints } from '../services/TrackStore';

const mapProvider = getMapProvider();
const trackSource = createSqliteTrackDataSource();

const POINT_COUNTS = [100, 1000, 10000] as const;
const SEED_COUNT = POINT_COUNTS[0];
const LOAD_CAP = 20000;
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];

export function MapTestScreen() {
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [busy, setBusy] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  // Mount: on first launch (empty DB) seed a default walk so there is a visible
  // track, then load whatever is persisted in SQLite. The track is rendered
  // from the DB, so it survives an app restart — the P2 acceptance bar.
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        if ((await countTrackPoints()) === 0) {
          await replaceTrackPoints(generateMockWalk(SEED_COUNT));
        }
        const loaded = await trackSource.getPoints(LOAD_CAP);
        if (alive) {
          setPoints(loaded);
        }
      } catch (e) {
        if (alive) {
          setError(e instanceof Error ? e.message : String(e));
        }
      } finally {
        if (alive) {
          setBusy(false);
        }
      }
    })();
    return () => {
      alive = false;
    };
  }, []);

  // Perf buttons re-seed N points into SQLite, then read them back — this
  // exercises the real write + read path at 100 / 1,000 / 10,000 scale, and
  // changes the persisted state so a restart shows the last seeded count.
  async function seed(count: number): Promise<void> {
    setBusy(true);
    setError(null);
    try {
      await replaceTrackPoints(generateMockWalk(count));
      setPoints(await trackSource.getPoints(LOAD_CAP));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  // P2 seam (unchanged from P1): raw WGS-84 from SQLite is converted to the
  // active provider's coordinate system at render time — we never persist
  // pre-transformed coordinates.
  const routeFeature = useMemo<Feature<LineString>>(() => {
    const rawPoints = trackPointsToLngLat(points);
    const renderCoords = transformLineString(
      rawPoints,
      'WGS84',
      mapProvider.coordinateSystem,
    );
    return {
      type: 'Feature',
      properties: {
        id: 'p2-track',
        provider: mapProvider.id,
        points: points.length,
      },
      geometry: { type: 'LineString', coordinates: renderCoords },
    };
  }, [points]);

  const center = useMemo<LngLat>(() => {
    const coords = routeFeature.geometry.coordinates as LngLat[];
    return coords[Math.floor(coords.length / 2)] ?? FALLBACK_CENTER;
  }, [routeFeature]);

  // A GeoJSON LineString needs >= 2 points; rendering an empty one throws
  // "A line string must have two or more coordinate points" in MapLibre and
  // breaks the source. Guard it: draw the layer only once data has loaded.
  const hasTrack = points.length >= 2;

  return (
    <View style={styles.container}>
      <Map style={styles.map} mapStyle={mapProvider.mapStyle}>
        <Camera center={center} zoom={12} />
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

      <View style={styles.badge}>
        <Text style={styles.badgeText}>
          {error
            ? `⚠ ${error}`
            : busy
              ? 'Loading…'
              : `${points.length.toLocaleString()} pts · SQLite`}
        </Text>
      </View>

      <View style={styles.controls}>
        {POINT_COUNTS.map((count) => {
          const active = points.length === count;
          return (
            <TouchableOpacity
              key={count}
              disabled={busy}
              style={[styles.button, active && styles.buttonActive]}
              onPress={() => {
                void seed(count);
              }}
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
  badge: {
    position: 'absolute',
    top: 56,
    alignSelf: 'center',
    backgroundColor: 'rgba(15,23,42,0.85)',
    borderRadius: 16,
    paddingVertical: 6,
    paddingHorizontal: 14,
  },
  badgeText: {
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '600',
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
