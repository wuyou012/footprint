import { useCallback, useState } from 'react';
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import { LowPowerView } from '../components/record/LowPowerView';
import { ModeSelector } from '../components/record/ModeSelector';
import { RecordMap } from '../components/record/RecordMap';
import { RecordStatusBar } from '../components/record/RecordStatusBar';
import { useForegroundRecording } from '../hooks/useForegroundRecording';
import { exportTrackAsGpx } from '../services/GpxExport';
import {
  DEFAULT_RECORDING_PROFILE,
  RECORDING_PROFILES,
  type RecordingProfile,
} from '../services/RecordingProfile';

const SCREEN_ON_HINT =
  'Screen-on recording: this is an active, screen-awake session. ' +
  'Locking the screen may pause GPS. All-day background recording comes later.';

/**
 * F2 product home: a foreground recording screen built from the F0/F1 logic.
 * No mock seeding, no debug probes, no city-jump/test buttons — just record,
 * see your track, switch modes, drop into a low-power view, and export.
 */
export function RecordScreen() {
  const rec = useForegroundRecording();
  const [profile, setProfile] = useState<RecordingProfile>(
    DEFAULT_RECORDING_PROFILE,
  );
  const [lowPower, setLowPower] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [exportError, setExportError] = useState<string | null>(null);

  const config = RECORDING_PROFILES[profile];

  const handleStart = useCallback(() => {
    setExportError(null);
    void rec.start(profile);
  }, [profile, rec]);

  const handleStop = useCallback(() => {
    setLowPower(false);
    void rec.stop();
  }, [rec]);

  const exportGpx = useCallback(async () => {
    if (exporting || rec.recording || rec.points.length === 0) {
      return;
    }
    setExporting(true);
    setExportError(null);
    try {
      await exportTrackAsGpx(rec.points);
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      setExportError(
        /another share|being processed/i.test(message)
          ? 'A share is still open — close it, then tap Export again'
          : message,
      );
    } finally {
      setExporting(false);
    }
  }, [exporting, rec.recording, rec.points]);

  if (rec.recording && lowPower) {
    return (
      <LowPowerView
        stats={rec.stats}
        modeLabel={config.label}
        onStop={handleStop}
        onShowMap={() => setLowPower(false)}
      />
    );
  }

  const badge =
    rec.error ?? exportError ?? `${rec.points.length.toLocaleString()} points`;

  return (
    <View style={styles.container}>
      <RecordMap points={rec.points} />

      <View style={styles.topOverlay} pointerEvents="box-none">
        <View style={styles.badge}>
          <Text style={styles.badgeText} numberOfLines={2}>
            {rec.busy ? 'Loading…' : badge}
          </Text>
        </View>
      </View>

      <View style={styles.bottomOverlay} pointerEvents="box-none">
        {rec.recording ? (
          <>
            <RecordStatusBar stats={rec.stats} modeLabel={config.label} />
            <View style={styles.buttonRow}>
              <TouchableOpacity
                style={[styles.primaryButton, styles.stopButton]}
                onPress={handleStop}
              >
                <Text style={styles.primaryText}>Stop</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.secondaryButton}
                onPress={() => setLowPower(true)}
              >
                <Text style={styles.secondaryText}>Low power</Text>
              </TouchableOpacity>
            </View>
          </>
        ) : (
          <>
            <ModeSelector
              value={profile}
              onChange={setProfile}
              disabled={rec.busy}
            />
            <TouchableOpacity
              style={[styles.primaryButton, rec.busy && styles.buttonDisabled]}
              disabled={rec.busy}
              onPress={handleStart}
            >
              <Text style={styles.primaryText}>Start recording</Text>
            </TouchableOpacity>
            {rec.points.length > 0 && (
              <TouchableOpacity
                style={[styles.secondaryButton, styles.fullWidth]}
                disabled={exporting}
                onPress={() => {
                  void exportGpx();
                }}
              >
                <Text style={styles.secondaryText}>
                  {exporting ? 'Exporting…' : 'Export GPX'}
                </Text>
              </TouchableOpacity>
            )}
            <Text style={styles.hint}>{SCREEN_ON_HINT}</Text>
          </>
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0B0B0F',
  },
  topOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    paddingTop: 52,
    paddingHorizontal: 16,
    alignItems: 'flex-start',
  },
  badge: {
    backgroundColor: 'rgba(17, 24, 39, 0.82)',
    borderRadius: 10,
    paddingVertical: 6,
    paddingHorizontal: 12,
    maxWidth: '100%',
  },
  badgeText: {
    color: '#F9FAFB',
    fontSize: 13,
    fontWeight: '600',
  },
  bottomOverlay: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    paddingBottom: 32,
    paddingHorizontal: 16,
    gap: 12,
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 12,
  },
  primaryButton: {
    flex: 1,
    backgroundColor: '#0F766E',
    paddingVertical: 16,
    borderRadius: 14,
    alignItems: 'center',
  },
  stopButton: {
    backgroundColor: '#DC2626',
  },
  primaryText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '700',
  },
  secondaryButton: {
    backgroundColor: 'rgba(17, 24, 39, 0.82)',
    paddingVertical: 16,
    paddingHorizontal: 20,
    borderRadius: 14,
    alignItems: 'center',
  },
  fullWidth: {
    width: '100%',
  },
  secondaryText: {
    color: '#E5E7EB',
    fontSize: 16,
    fontWeight: '600',
  },
  buttonDisabled: {
    opacity: 0.5,
  },
  hint: {
    color: '#9CA3AF',
    fontSize: 12,
    lineHeight: 17,
    textAlign: 'center',
    paddingHorizontal: 8,
  },
});
