import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import * as Location from 'expo-location';
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
import { locationToTrackPoint } from '../services/LocationPoint';
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
import {
  getLocationDiagnostics,
  recordRawLocationDiagnostic,
  recordRawLocationError,
  replaceTrackPoints,
  resetBackgroundDiagnostics,
  resetRawDiagnostics,
  type LocationDiagnosticSnapshot,
} from '../services/TrackStore';
import { styles } from './MapTestScreen.styles';

const mapProvider = getMapProvider();
const trackSource = createSqliteTrackDataSource();

const LOAD_CAP = 20000;
const FALLBACK_CENTER: LngLat = [-122.4194, 37.7749];
const TRACK_ZOOM = 14;
const ACTIVE_REFRESH_INTERVAL_MS = 8000;
const RAW_DIAGNOSTIC_INTERVAL_MS = 5000;

const EMPTY_DIAGNOSTICS: LocationDiagnosticSnapshot = {
  backgroundReceivedCount: 0,
  backgroundAcceptedCount: 0,
  backgroundRejectedCount: 0,
  backgroundLastFixTs: null,
  backgroundLastAcceptedTs: null,
  backgroundLastRejectReason: null,
  backgroundLastError: null,
  rawReceivedCount: 0,
  rawLastFixTs: null,
  rawLastAccuracy: null,
  rawLastLongitude: null,
  rawLastLatitude: null,
  rawLastError: null,
  updatedTs: null,
};

function formatLocationError(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

function formatClock(timestamp: number | null): string {
  if (!timestamp) {
    return 'never';
  }
  return new Date(timestamp).toLocaleTimeString();
}

function formatAccuracy(accuracy: number | null): string {
  return typeof accuracy === 'number' && Number.isFinite(accuracy)
    ? `${Math.round(accuracy)}m`
    : 'n/a';
}

function formatRawStatus(point: TrackPoint): string {
  return `Raw fix ${formatClock(point.timestamp)} acc ${formatAccuracy(
    point.accuracy ?? null,
  )}`;
}

export function MapTestScreen() {
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [diagnostics, setDiagnostics] =
    useState<LocationDiagnosticSnapshot>(EMPTY_DIAGNOSTICS);
  const [busy, setBusy] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);
  const [recording, setRecording] = useState(false);
  const [recordingStatus, setRecordingStatus] = useState('GPS idle');
  const [rawRunning, setRawRunning] = useState(false);
  const [rawStatus, setRawStatus] = useState('Raw idle');
  const [exporting, setExporting] = useState(false);
  const busyRef = useRef(false);
  const exportingRef = useRef(false);
  const recordingRef = useRef(false);
  const rawRef = useRef(false);
  const rawSubscriptionRef = useRef<Location.LocationSubscription | null>(null);
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

  const loadDiagnostics = useCallback(async (): Promise<void> => {
    const loaded = await getLocationDiagnostics();
    if (mountedRef.current) {
      setDiagnostics(loaded);
    }
  }, []);

  const refreshVisibleData = useCallback(async (): Promise<void> => {
    await Promise.all([loadPoints(), loadDiagnostics()]);
  }, [loadDiagnostics, loadPoints]);

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
        await refreshVisibleData();
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
      rawSubscriptionRef.current?.remove();
      rawSubscriptionRef.current = null;
    };
  }, [refreshVisibleData, syncBackgroundState]);

  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') {
        void refreshVisibleData();
        void syncBackgroundState();
      }
    });

    return () => {
      subscription.remove();
    };
  }, [refreshVisibleData, syncBackgroundState]);

  useEffect(() => {
    if (!recording && !rawRunning) {
      return undefined;
    }

    const intervalId = setInterval(() => {
      void refreshVisibleData();
      void syncBackgroundState();
    }, ACTIVE_REFRESH_INTERVAL_MS);

    return () => {
      clearInterval(intervalId);
    };
  }, [rawRunning, recording, refreshVisibleData, syncBackgroundState]);

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
      await refreshVisibleData();
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
    if (
      busyRef.current ||
      recordingRef.current ||
      exportingRef.current ||
      rawRef.current
    ) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    setRecordingStatus(`Checking ${recordingProfileConfig.label} GPS...`);

    try {
      await requestBackgroundRecordingPermissions();
      await stopBackgroundRecording();
      await resetBackgroundDiagnostics();
      await replaceTrackPoints([]);
      if (mountedRef.current) {
        setPoints([]);
        setRecordingStatus('Starting background GPS...');
      }

      await startBackgroundRecording(recordingProfile, recordingProfileConfig, {
        permissionsGranted: true,
      });
      recordingRef.current = true;
      await loadDiagnostics();
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

  async function stopRawDiagnostic(): Promise<void> {
    rawSubscriptionRef.current?.remove();
    rawSubscriptionRef.current = null;
    rawRef.current = false;
    if (mountedRef.current) {
      setRawRunning(false);
      setRawStatus('Raw stopped');
    }
    await loadDiagnostics();
  }

  async function startRawDiagnostic(): Promise<void> {
    if (
      busyRef.current ||
      recordingRef.current ||
      exportingRef.current ||
      rawRef.current
    ) {
      return;
    }

    busyRef.current = true;
    setBusy(true);
    setError(null);
    setRawStatus('Checking foreground GPS...');

    try {
      if (!(await Location.hasServicesEnabledAsync())) {
        throw new Error('Location services are disabled');
      }

      const permission = await Location.requestForegroundPermissionsAsync();
      if (!permission.granted) {
        throw new Error('Foreground location permission denied');
      }

      await resetRawDiagnostics();
      const subscription = await Location.watchPositionAsync(
        {
          accuracy: Location.Accuracy.Balanced,
          timeInterval: RAW_DIAGNOSTIC_INTERVAL_MS,
          distanceInterval: 0,
        },
        (location) => {
          const point = locationToTrackPoint(location);
          void (async () => {
            try {
              await recordRawLocationDiagnostic(point);
              await loadDiagnostics();
              if (mountedRef.current) {
                setRawStatus(formatRawStatus(point));
              }
            } catch (e) {
              const message = formatLocationError(e);
              await recordRawLocationError(message);
              if (mountedRef.current) {
                setError(message);
                setRawStatus('Raw write failed');
              }
            }
          })();
        },
        (reason) => {
          void recordRawLocationError(reason);
          if (mountedRef.current) {
            setError(reason);
            setRawStatus('Raw GPS error');
          }
        },
      );

      rawSubscriptionRef.current = subscription;
      rawRef.current = true;
      await loadDiagnostics();
      if (mountedRef.current) {
        setRawRunning(true);
        setRawStatus('Raw waiting for fix');
      }
    } catch (e) {
      rawRef.current = false;
      if (mountedRef.current) {
        setRawRunning(false);
        setError(formatLocationError(e));
        setRawStatus('Raw unavailable');
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

  const backgroundLine = useMemo(() => {
    const last =
      diagnostics.backgroundLastAcceptedTs ??
      diagnostics.backgroundLastFixTs;
    const errorText = diagnostics.backgroundLastError
      ? ` err ${diagnostics.backgroundLastError}`
      : '';
    const rejectText = diagnostics.backgroundLastRejectReason
      ? ` last reject ${diagnostics.backgroundLastRejectReason}`
      : '';
    return `BG ${diagnostics.backgroundAcceptedCount}/${diagnostics.backgroundReceivedCount} accepted - last ${formatClock(last)}${rejectText}${errorText}`;
  }, [diagnostics]);

  const rawLine = useMemo(() => {
    const errorText = diagnostics.rawLastError
      ? ` err ${diagnostics.rawLastError}`
      : '';
    return `Raw ${diagnostics.rawReceivedCount} fixes - last ${formatClock(
      diagnostics.rawLastFixTs,
    )} acc ${formatAccuracy(diagnostics.rawLastAccuracy)}${errorText}`;
  }, [diagnostics]);

  const hasTrack = points.length >= 2;
  const recordingButtonDisabled = (busy && !recording) || rawRunning;
  const rawButtonDisabled = (busy && !rawRunning) || recording || exporting;
  const exportDisabled = busy || recording || exporting || points.length === 0;
  const profileSwitchDisabled = busy || recording || exporting || rawRunning;

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
        <Text style={styles.validationLabel}>{backgroundLine}</Text>
        <Text style={styles.validationLabel}>{rawLine}</Text>
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
                    !exportingRef.current &&
                    !rawRef.current
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
          disabled={rawButtonDisabled}
          style={[styles.button, rawButtonDisabled && styles.buttonDisabled]}
          onPress={() => {
            if (rawRunning) {
              void stopRawDiagnostic();
            } else {
              void startRawDiagnostic();
            }
          }}
        >
          <Text style={styles.buttonText}>
            {rawRunning ? 'Stop Raw' : 'Raw'}
          </Text>
        </TouchableOpacity>
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

      {rawRunning && (
        <View style={[styles.badge, { top: 136 }]}>
          <Text style={styles.badgeText}>{rawStatus}</Text>
        </View>
      )}
    </View>
  );
}
