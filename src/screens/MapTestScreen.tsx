import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import type { Feature, LineString } from 'geojson';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Text, TouchableOpacity, View } from 'react-native';

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
import { styles } from './MapTestScreen.styles';

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
  // `busy` state is async, so it can't hard-block a fast double-tap. busyRef is
  // a synchronous lock: only one seed/load runs at a time (砚砚 review P1/P2).
  // mountedRef stops setState after unmount-during-write.
  const busyRef = useRef(false);
  const mountedRef = useRef(true);

  // Mount: on first launch (empty DB) seed a default walk so there is a visible
  // track, then load whatever is persisted in SQLite. The track is rendered
  // from the DB, so it survives an app restart — the P2 acceptance bar.
  useEffect(() => {
    mountedRef.current = true;
    busyRef.current = true;
    (async () => {
      try {
        if ((await countTrackPoints()) === 0) {
          await replaceTrackPoints(generateMockWalk(SEED_COUNT));
        }
        const loaded = await trackSource.getPoints(LOAD_CAP);
        if (mountedRef.current) {
          setPoints(loaded);
        }
      } catch (e) {
        if (mountedRef.current) {
          setError(e instanceof Error ? e.message : String(e));
        }
      } finally {
        busyRef.current = false;
        if (mountedRef.current) {
          setBusy(false);
        }
      }
    })();
    return () => {
      mountedRef.current = false;
    };
  }, []);

  // Perf buttons re-seed N points into SQLite, then read them back — this
  // exercises the real write + read path at 100 / 1,000 / 10,000 scale, and
  // changes the persisted state so a restart shows the last seeded count.
  async function seed(count: number): Promise<void> {
    // Synchronous re-entry guard: reject a tap while another seed/load is in
    // flight (disabled={busy} lags one render behind, so it isn't a hard lock).
    if (busyRef.current) {
      return;
    }
    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      await replaceTrackPoints(generateMockWalk(count));
      const loaded = await trackSource.getPoints(LOAD_CAP);
      if (mountedRef.current) {
        setPoints(loaded);
      }
    } catch (e) {
      if (mountedRef.current) {
        setError(e instanceof Error ? e.message : String(e));
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
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
