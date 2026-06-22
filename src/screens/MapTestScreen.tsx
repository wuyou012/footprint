import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import type { Feature, LineString } from 'geojson';
import { useEffect, useMemo, useRef, useState } from 'react';
import { ScrollView, Text, TouchableOpacity, View } from 'react-native';

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

// P2.5: 2D uses OpenFreeMap Positron — flat 2D building footprints only, NO
// fill-extrusion, fewer layers => lighter render + lower memory. 3D uses
// Liberty (has the building-3d extrusion layer). The toggle keeps the 3D
// interface. Both are WGS-84 OpenMapTiles, no API key.
const BUILDING_STYLE_URLS: Record<'2d' | '3d', string> = {
  '2d': 'https://tiles.openfreemap.org/styles/positron',
  '3d': 'https://tiles.openfreemap.org/styles/liberty',
};

const POINT_COUNTS = [100, 1000, 10000] as const;
const SEED_COUNT = POINT_COUNTS[0];
const LOAD_CAP = 20000;
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];
const TRACK_CAMERA_ID = 'track';
const VERIFICATION_CITIES: ReadonlyArray<{
  id: string;
  label: string;
  center: LngLat;
}> = [
  { id: 'shanghai-lujiazui', label: 'Shanghai', center: [121.505, 31.245] },
  { id: 'beijing-guomao', label: 'Beijing', center: [116.461, 39.909] },
  { id: 'new-york-manhattan', label: 'NYC', center: [-73.985, 40.748] },
  { id: 'los-angeles-downtown', label: 'LA', center: [-118.245, 34.052] },
];
const VERIFICATION_ZOOMS = [15, 16, 17] as const;
type VerificationZoom = (typeof VERIFICATION_ZOOMS)[number];

export function MapTestScreen() {
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [busy, setBusy] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  // `busy` state is async, so it can't hard-block a fast double-tap. busyRef is
  // a synchronous lock: only one seed/load runs at a time (砚砚 review P1/P2).
  // mountedRef stops setState after unmount-during-write.
  const busyRef = useRef(false);
  const [cameraTargetId, setCameraTargetId] = useState<string>(TRACK_CAMERA_ID);
  const [verificationZoom, setVerificationZoom] =
    useState<VerificationZoom>(16);
  // P2.5: 2D building footprints by default — lighter to render + lower memory
  // than Liberty's 3D fill-extrusion. '3d' re-enables it. Interface kept (toggle).
  const [buildingMode, setBuildingMode] = useState<'2d' | '3d'>('2d');
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

  // P2.5 validation scaffold: when a city is selected the camera jumps to that
  // city center + chosen zoom (to check building rendering); otherwise it
  // follows the track (P2 behaviour, unchanged). Remove after P2.5 verdict.
  const selectedVerificationCity = useMemo(
    () =>
      VERIFICATION_CITIES.find((city) => city.id === cameraTargetId) ?? null,
    [cameraTargetId],
  );
  const cameraCenter = selectedVerificationCity?.center ?? center;
  const cameraZoom = selectedVerificationCity ? verificationZoom : 12;

  // A GeoJSON LineString needs >= 2 points; rendering an empty one throws
  // "A line string must have two or more coordinate points" in MapLibre and
  // breaks the source. Guard it: draw the layer only once data has loaded.
  // P2.5 note: the map style owns the building layers; this track layer is
  // declared after the style and stays visually above the basemap.
  const hasTrack = points.length >= 2;

  return (
    <View style={styles.container}>
      <Map style={styles.map} mapStyle={BUILDING_STYLE_URLS[buildingMode]}>
        <Camera center={cameraCenter} zoom={cameraZoom} />
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

      <View style={styles.validationPanel}>
        <Text style={styles.validationLabel}>P2.5 validation scaffold</Text>
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.validationRow}
        >
          <TouchableOpacity
            style={[
              styles.validationButton,
              cameraTargetId === TRACK_CAMERA_ID &&
                styles.validationButtonActive,
            ]}
            onPress={() => {
              setCameraTargetId(TRACK_CAMERA_ID);
            }}
          >
            <Text
              style={[
                styles.validationButtonText,
                cameraTargetId === TRACK_CAMERA_ID &&
                  styles.validationButtonTextActive,
              ]}
            >
              Track
            </Text>
          </TouchableOpacity>
          {VERIFICATION_CITIES.map((city) => {
            const active = cameraTargetId === city.id;
            return (
              <TouchableOpacity
                key={city.id}
                style={[
                  styles.validationButton,
                  active && styles.validationButtonActive,
                ]}
                onPress={() => {
                  setCameraTargetId(city.id);
                }}
              >
                <Text
                  style={[
                    styles.validationButtonText,
                    active && styles.validationButtonTextActive,
                  ]}
                >
                  {city.label}
                </Text>
              </TouchableOpacity>
            );
          })}
        </ScrollView>
        <View style={styles.zoomRow}>
          {VERIFICATION_ZOOMS.map((zoom) => {
            const active = verificationZoom === zoom;
            return (
              <TouchableOpacity
                key={zoom}
                style={[styles.zoomButton, active && styles.zoomButtonActive]}
                onPress={() => {
                  setVerificationZoom(zoom);
                }}
              >
                <Text
                  style={[
                    styles.zoomButtonText,
                    active && styles.zoomButtonTextActive,
                  ]}
                >
                  z{zoom}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>
        <View style={styles.zoomRow}>
          {(['2d', '3d'] as const).map((mode) => {
            const active = buildingMode === mode;
            return (
              <TouchableOpacity
                key={mode}
                style={[styles.zoomButton, active && styles.zoomButtonActive]}
                onPress={() => {
                  setBuildingMode(mode);
                }}
              >
                <Text
                  style={[
                    styles.zoomButtonText,
                    active && styles.zoomButtonTextActive,
                  ]}
                >
                  {mode.toUpperCase()}
                </Text>
              </TouchableOpacity>
            );
          })}
        </View>
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
