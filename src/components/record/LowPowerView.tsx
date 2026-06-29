import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import type { RecordingStats } from '../../hooks/recordingStats';
import {
  formatAccuracy,
  formatDistance,
  formatDuration,
  formatRelativeTime,
} from '../../utils/format';

type LowPowerViewProps = {
  stats: RecordingStats;
  modeLabel: string;
  onStop: () => void;
  onShowMap: () => void;
};

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metric}>
      <Text style={styles.metricValue}>{value}</Text>
      <Text style={styles.metricLabel}>{label}</Text>
    </View>
  );
}

/**
 * Minimal dark recording screen. Intentionally renders no map so the GPU/screen
 * draw cost stays low during long screen-on sessions (world-2 §5). Re-renders
 * are driven by the hook's 1s stats tick, which keeps "last fix … ago" live.
 */
export function LowPowerView({
  stats,
  modeLabel,
  onStop,
  onShowMap,
}: LowPowerViewProps) {
  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <View style={styles.dot} />
        <Text style={styles.headerText}>Recording · {modeLabel}</Text>
      </View>

      <Text style={styles.timer}>{formatDuration(stats.durationMs)}</Text>

      <View style={styles.metrics}>
        <Metric label="Distance" value={formatDistance(stats.distanceMeters)} />
        <Metric label="Points" value={stats.acceptedCount.toLocaleString()} />
      </View>

      <Text style={styles.lastFix}>
        {`Last fix ${formatRelativeTime(stats.lastFixTs)} · ${formatAccuracy(
          stats.lastAccuracy,
        )}`}
      </Text>

      <View style={styles.actions}>
        <TouchableOpacity style={styles.stopButton} onPress={onStop}>
          <Text style={styles.stopText}>Stop</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.mapButton} onPress={onShowMap}>
          <Text style={styles.mapText}>View map</Text>
        </TouchableOpacity>
      </View>

      <Text style={styles.hint}>
        Screen-on recording. Keep this screen open; locking may pause GPS.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0B0B0F',
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 28,
    gap: 22,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  dot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    backgroundColor: '#EF4444',
  },
  headerText: {
    color: '#9CA3AF',
    fontSize: 15,
    letterSpacing: 0.5,
  },
  timer: {
    color: '#F9FAFB',
    fontSize: 64,
    fontWeight: '200',
    fontVariant: ['tabular-nums'],
  },
  metrics: {
    flexDirection: 'row',
    gap: 48,
  },
  metric: {
    alignItems: 'center',
  },
  metricValue: {
    color: '#E5E7EB',
    fontSize: 26,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  metricLabel: {
    color: '#6B7280',
    fontSize: 12,
    marginTop: 4,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  lastFix: {
    color: '#6B7280',
    fontSize: 13,
  },
  actions: {
    flexDirection: 'row',
    gap: 14,
    marginTop: 6,
  },
  stopButton: {
    backgroundColor: '#DC2626',
    paddingVertical: 14,
    paddingHorizontal: 40,
    borderRadius: 12,
  },
  stopText: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '700',
  },
  mapButton: {
    borderColor: '#374151',
    borderWidth: 1,
    paddingVertical: 14,
    paddingHorizontal: 28,
    borderRadius: 12,
  },
  mapText: {
    color: '#D1D5DB',
    fontSize: 16,
    fontWeight: '600',
  },
  hint: {
    color: '#4B5563',
    fontSize: 12,
    textAlign: 'center',
    lineHeight: 17,
  },
});
