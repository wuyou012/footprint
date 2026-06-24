import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import type { Feature, LineString } from 'geojson';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { AppState, Text, TouchableOpacity, View } from 'react-native';

import {
  isBackgroundRecording,
  requestBackgroundRecordingPermissions,
  startBackgroundRecording,
  stopBackgroundRecording,
} from '../services/BackgroundLocation';
import {
  transformLineString,
  type LngLat,
} from '../services/CoordinateService';
import { exportTrackAsGpx } from '../services/GpxExport';
import {
  getMapProvider,
  type BuildingStyleMode,
} from '../services/MapProvider';
import {
  DEFAULT_RECORDING_PROFILE,
  RECORDING_PROFILE_ORDER,
  RECORDING_PROFILES,
  type RecordingProfile,
} from '../services/RecordingProfile';
import {
  createSqliteTrackDataSource,
  trackPointsToLngLat,
  type TrackPoint,
} from '../services/TrackDataSource';
import { replaceTrackPoints } from '../services/TrackStore';
import { styles } from './MapTestScreen.styles';

const mapProvider = getMapProvider();
const trackSource = createSqliteTrackDataSource();

const LOAD_CAP = 20000;
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];
const TRACK_ZOOM = 14;
const ACTIVE_REFRESH_INTERVAL_MS = 8000;

function formatLocationError(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

export function MapTestScreen() {
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [busy, setBusy] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [recording, setRecording] = useState(false);
  const [recordingStatus, setRecordingStatus] = useState('GPS idle');
  const [exporting, setExporting] = useState(false);
  const busyRef = useRef(false);
  const exportingRef = useRef(false);
  const recordingRef = useRef(false);
  const [buildingMode, setBuildingMode] = useState<BuildingStyleMode>('2d');
  const [recordingProfile, setRecordingProfile] =
    useState<RecordingProfile>(DEFAULT_RECORDING_PROFILE);
  const mountedRef = useRef(true);
  const recordingProfileConfig = RECORDING_PROFILES[recordingProfile];

  const loadPoints = useCallback(async (): Promise<void> => {
    const loaded = await trackSource.getPoints(LOAD_CAP);
    if (mountedRef.current) {
      setPoints(loaded);
    }
  }, []);

  const syncBackgroundState = useCallback(async (): Promise<boolean> => {
    const active = await isBackgroundRecording();
    recordingRef.current = active;
    if (mountedRef.current) {
      setRecording(active);
      setRecordingStatus((current) => {
        if (active && (current === 'GPS idle' || current === 'GPS stopped')) {
          return `Background ${recordingProfileConfig.label} recording`;
        }
        if (!active && current.startsWith('Background ')) {
          return 'GPS idle';
        }
        return current;
      });
    }
    return active;
  }, [recordingProfileConfig.label]);

  useEffect(() => {
    mountedRef.current = true;
    busyRef.current = true;
    (async () => {
      try {
        await loadPoints();
        await syncBackgroundState();
      } catch (e) {
        if (mountedRef.current) {
          setError(formatLocationError(e));
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
  }, [loadPoints, syncBackgroundState]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void loadPoints();
        void syncBackgroundState();
      }
    });

    return () => {
      subscription.remove();
    };
  }, [loadPoints, syncBackgroundState]);

  useEffect(() => {
    if (!recording) {
      return undefined;
    }

    const intervalId = setInterval(() => {
      void loadPoints();
      void syncBackgroundState();
    }, ACTIVE_REFRESH_INTERVAL_MS);

    return () => {
      clearInterval(intervalId);
    };
  }, [loadPoints, recording, syncBackgroundState]);

  async function stopRecording(): Promise<void> {
    if (busyRef.current || exportingRef.current) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    try {
      await stopBackgroundRecording();
      recordingRef.current = false;
      await loadPoints();
      if (mountedRef.current) {
        setRecording(false);
        setRecordingStatus('GPS stopped');
      }
    } catch (e) {
      if (mountedRef.current) {
        setError(formatLocationError(e));
        setRecordingStatus('GPS stop failed');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }

  async function startRecording(): Promise<void> {
    if (busyRef.current || recordingRef.current || exportingRef.current) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    setRecordingStatus(`Checking ${recordingProfileConfig.label} GPS...`);

    try {
      await requestBackgroundRecordingPermissions();
      await stopBackgroundRecording();
      await replaceTrackPoints([]);
      if (mountedRef.current) {
        setPoints([]);
        setRecordingStatus('Starting background GPS...');
      }

      await startBackgroundRecording(recordingProfile, recordingProfileConfig, {
        permissionsGranted: true,
      });
      recordingRef.current = true;
      if (mountedRef.current) {
        setRecording(true);
        setRecordingStatus(
          `Background ${recordingProfileConfig.label} recording`,
        );
      }
    } catch (e) {
      recordingRef.current = false;
      if (mountedRef.current) {
        setRecording(false);
        setError(formatLocationError(e));
        setRecordingStatus('GPS unavailable');
      }
    } finally {
      busyRef.current = false;
      if (mountedRef.current) {
        setBusy(false);
      }
    }
  }

  async function exportGpx(): Promise<void> {
    if (busyRef.current || recordingRef.current || exportingRef.current) {
      return;
    }

    exportingRef.current = true;
    setExporting(true);
    setError(null);
    try {
      await exportTrackAsGpx(points);
    } catch (e) {
      if (mountedRef.current) {
        const message = formatLocationError(e);
        setError(
          /another share|being processed/i.test(message)
            ? 'A share is still open - close it, then tap Export again'
            : message,
        );
      }
    } finally {
      exportingRef.current = false;
      if (mountedRef.current) {
        setExporting(false);
      }
    }
  }

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
        id: 'p4-track',
        provider: mapProvider.id,
        points: points.length,
      },
      geometry: { type: 'LineString', coordinates: renderCoords },
    };
  }, [points]);

  const cameraCenter = useMemo<LngLat>(() => {
    const coords = routeFeature.geometry.coordinates as LngLat[];
    return coords[Math.floor(coords.length / 2)] ?? FALLBACK_CENTER;
  }, [routeFeature]);

  const hasTrack = points.length >= 2;
  const recordingButtonDisabled = busy && !recording;
  const exportDisabled = busy || recording || exporting || points.length === 0;
  const profileSwitchDisabled = busy || recording || exporting;

  return (
    <View style={styles.container}>
      <Map
        style={styles.map}
        mapStyle={mapProvider.buildingStyles[buildingMode]}
      >
        <Camera center={cameraCenter} zoom={TRACK_ZOOM} />
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
            ? `! ${error}`
            : busy
              ? 'Loading...'
              : `${points.length.toLocaleString()} pts - ${
                  recording ? 'BG GPS' : 'SQLite'
                }`}
        </Text>
      </View>

      <View style={styles.recordingPanel}>
        <TouchableOpacity
          disabled={recordingButtonDisabled}
          style={[
            styles.recordButton,
            recording && styles.recordButtonActive,
            recordingButtonDisabled && styles.recordButtonDisabled,
          ]}
          onPress={() => {
            if (recording) {
              void stopRecording();
            } else {
              void startRecording();
            }
          }}
        >
          <Text style={styles.recordButtonText}>
            {recording ? 'Stop GPS' : 'Start GPS'}
          </Text>
        </TouchableOpacity>
        <Text style={styles.recordingStatusText}>{recordingStatus}</Text>
      </View>

      <View style={styles.validationPanel}>
        <View style={styles.zoomRow}>
          {RECORDING_PROFILE_ORDER.map((profile) => {
            const active = recordingProfile === profile;
            return (
              <TouchableOpacity
                key={profile}
                disabled={profileSwitchDisabled}
                style={[
                  styles.zoomButton,
                  active && styles.zoomButtonActive,
                  profileSwitchDisabled && styles.buttonDisabled,
                ]}
                onPress={() => {
                  if (
                    !busyRef.current &&
                    !recordingRef.current &&
                    !exportingRef.current
                  ) {
                    setRecordingProfile(profile);
                  }
                }}
              >
                <Text
                  style={[
                    styles.zoomButtonText,
                    active && styles.zoomButtonTextActive,
                  ]}
                >
                  {RECORDING_PROFILES[profile].label}
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
        <TouchableOpacity
          disabled={exportDisabled}
          style={[styles.button, exportDisabled && styles.buttonDisabled]}
          onPress={() => {
            void exportGpx();
          }}
        >
          <Text style={styles.buttonText}>
            {exporting ? 'Exporting' : 'Export'}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}
