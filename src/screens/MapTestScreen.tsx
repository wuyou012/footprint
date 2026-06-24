import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import * as Location from 'expo-location';
import type { Feature, LineString } from 'geojson';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Text, TouchableOpacity, View } from 'react-native';

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
  createSqliteTrackDataSource,
  trackPointsToLngLat,
  type TrackPoint,
} from '../services/TrackDataSource';
import { appendTrackPoint, replaceTrackPoints } from '../services/TrackStore';
import { styles } from './MapTestScreen.styles';

const mapProvider = getMapProvider();
const trackSource = createSqliteTrackDataSource();

const LOAD_CAP = 20000;
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];
const TRACK_ZOOM = 14;

type RecordingProfile = 'daily' | 'eco';
type RecordingProfileConfig = {
  label: string;
  accuracy: Location.LocationAccuracy;
  timeInterval: number;
  distanceInterval: number;
  maxAcceptedAccuracyMeters: number;
};

const RECORDING_PROFILE_ORDER = ['daily', 'eco'] as const;
const RECORDING_PROFILES: Record<RecordingProfile, RecordingProfileConfig> = {
  daily: {
    label: 'Daily',
    accuracy: Location.Accuracy.Balanced,
    timeInterval: 30000,
    distanceInterval: 50,
    maxAcceptedAccuracyMeters: 200,
  },
  eco: {
    label: 'Eco',
    // TODO(P3.6): compare Balanced vs Low on the P30 before lowering accuracy.
    accuracy: Location.Accuracy.Balanced,
    timeInterval: 60000,
    distanceInterval: 100,
    maxAcceptedAccuracyMeters: 300,
  },
};

function formatLocationError(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function locationToTrackPoint(
  location: Location.LocationObject,
  maxAcceptedAccuracyMeters: number,
): TrackPoint | null {
  const { longitude, latitude, accuracy } = location.coords;

  if (
    !Number.isFinite(longitude) ||
    !Number.isFinite(latitude) ||
    Math.abs(longitude) > 180 ||
    Math.abs(latitude) > 90
  ) {
    return null;
  }

  if (
    accuracy !== null &&
    (!Number.isFinite(accuracy) || accuracy > maxAcceptedAccuracyMeters)
  ) {
    return null;
  }

  return {
    longitude,
    latitude,
    timestamp: Number.isFinite(location.timestamp)
      ? location.timestamp
      : Date.now(),
    accuracy,
  };
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
  const [buildingMode, setBuildingMode] = useState<BuildingStyleMode>('2d');
  const [recordingProfile, setRecordingProfile] =
    useState<RecordingProfile>('daily');
  const mountedRef = useRef(true);
  const recordingRef = useRef(false);
  const locationSubscriptionRef = useRef<Location.LocationSubscription | null>(
    null,
  );
  const locationWriteRef = useRef<Promise<void>>(Promise.resolve());
  const recordingProfileConfig = RECORDING_PROFILES[recordingProfile];

  useEffect(() => {
    mountedRef.current = true;
    busyRef.current = true;
    (async () => {
      try {
        const loaded = await trackSource.getPoints(LOAD_CAP);
        if (mountedRef.current) {
          setPoints(loaded);
        }
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
      recordingRef.current = false;
      locationSubscriptionRef.current?.remove();
      locationSubscriptionRef.current = null;
    };
  }, []);

  function enqueueLocation(location: Location.LocationObject): void {
    if (!recordingRef.current) {
      return;
    }

    const point = locationToTrackPoint(
      location,
      recordingProfileConfig.maxAcceptedAccuracyMeters,
    );
    if (!point) {
      if (mountedRef.current) {
        setRecordingStatus('Ignored low accuracy GPS fix');
      }
      return;
    }

    locationWriteRef.current = locationWriteRef.current
      .catch(() => undefined)
      .then(async () => {
        await appendTrackPoint(point);
        const loaded = await trackSource.getPoints(LOAD_CAP);
        if (mountedRef.current) {
          setPoints(loaded);
          const accuracy =
            typeof point.accuracy === 'number'
              ? `${Math.round(point.accuracy)}m`
              : 'unknown';
          setRecordingStatus(
            `Recording ${recordingProfileConfig.label} - ${loaded.length.toLocaleString()} pts - +/-${accuracy}`,
          );
        }
      })
      .catch((e) => {
        if (mountedRef.current) {
          setError(formatLocationError(e));
          setRecordingStatus('GPS write failed');
        }
      });
  }

  function stopRecording(): void {
    locationSubscriptionRef.current?.remove();
    locationSubscriptionRef.current = null;
    recordingRef.current = false;
    if (mountedRef.current) {
      setRecording(false);
      setRecordingStatus('GPS stopped');
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
      if (!(await Location.hasServicesEnabledAsync())) {
        throw new Error('Location services are disabled');
      }

      const permission = await Location.requestForegroundPermissionsAsync();
      if (!permission.granted) {
        throw new Error('Foreground location permission denied');
      }

      await replaceTrackPoints([]);
      if (mountedRef.current) {
        setPoints([]);
        setRecording(true);
        setRecordingStatus('Waiting for GPS fix...');
      }
      recordingRef.current = true;

      const subscription = await Location.watchPositionAsync(
        {
          accuracy: recordingProfileConfig.accuracy,
          timeInterval: recordingProfileConfig.timeInterval,
          distanceInterval: recordingProfileConfig.distanceInterval,
          mayShowUserSettingsDialog: true,
        },
        enqueueLocation,
        (reason) => {
          if (mountedRef.current) {
            setError(reason);
            setRecordingStatus('GPS error');
          }
        },
      );
      if (!recordingRef.current) {
        subscription.remove();
        return;
      }
      locationSubscriptionRef.current = subscription;
      if (mountedRef.current) {
        setRecordingStatus(`Recording ${recordingProfileConfig.label}`);
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
        // expo-sharing rejects a second share while a previous share sheet is
        // still open at the native layer; surface a friendly retry hint instead
        // of the raw native rejection.
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
        id: 'p3-track',
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
                  recording ? 'GPS' : 'SQLite'
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
              stopRecording();
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
