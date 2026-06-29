import { StyleSheet, Text, View } from 'react-native';

import type { RecordingStats } from '../../hooks/recordingStats';
import { formatDistance, formatDuration } from '../../utils/format';

type RecordStatusBarProps = {
  stats: RecordingStats;
  modeLabel: string;
};

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.value}>{value}</Text>
      <Text style={styles.label}>{label}</Text>
    </View>
  );
}

/** Compact live readout shown over the map while a session is recording. */
export function RecordStatusBar({ stats, modeLabel }: RecordStatusBarProps) {
  return (
    <View style={styles.bar}>
      <Stat label="Time" value={formatDuration(stats.durationMs)} />
      <Stat label="Distance" value={formatDistance(stats.distanceMeters)} />
      <Stat label="Points" value={stats.acceptedCount.toLocaleString()} />
      <Stat label="Mode" value={modeLabel} />
    </View>
  );
}

const styles = StyleSheet.create({
  bar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    backgroundColor: 'rgba(17, 24, 39, 0.82)',
    borderRadius: 14,
    paddingVertical: 10,
    paddingHorizontal: 14,
  },
  stat: {
    alignItems: 'center',
    flex: 1,
  },
  value: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
  },
  label: {
    color: '#94A3B8',
    fontSize: 11,
    marginTop: 2,
    textTransform: 'uppercase',
    letterSpacing: 0.5,
  },
});
