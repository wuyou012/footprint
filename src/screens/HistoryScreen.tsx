import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';

import {
  getDaySummaries,
  type DaySummary,
} from '../services/DayHistory';
import {
  formatDayKey,
  formatDistance,
  formatDuration,
  formatError,
} from '../utils/format';

type HistoryScreenProps = {
  onBack: () => void;
  onSelectDay: (dayKey: string) => void;
};

function DayCard({
  summary,
  onPress,
}: {
  summary: DaySummary;
  onPress: () => void;
}) {
  return (
    <TouchableOpacity style={styles.card} onPress={onPress}>
      <View style={styles.cardHeader}>
        <Text style={styles.dateText}>{formatDayKey(summary.dayKey)}</Text>
        <Text style={styles.chevron}>&gt;</Text>
      </View>
      <Text style={styles.metaText}>
        {summary.sessionCount.toLocaleString()} sessions -{' '}
        {summary.pointCount.toLocaleString()} points
      </Text>
      <View style={styles.metricRow}>
        <Text style={styles.metricText}>
          {formatDistance(summary.distanceMeters)}
        </Text>
        <Text style={styles.metricText}>
          {formatDuration(summary.durationSeconds * 1000)}
        </Text>
      </View>
    </TouchableOpacity>
  );
}

export function HistoryScreen({
  onBack,
  onSelectDay,
}: HistoryScreenProps) {
  const [summaries, setSummaries] = useState<DaySummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setSummaries(await getDaySummaries());
    } catch (e) {
      setError(formatError(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.navButton} onPress={onBack}>
          <Text style={styles.navText}>Back</Text>
        </TouchableOpacity>
        <Text style={styles.title}>History</Text>
        <TouchableOpacity style={styles.navButton} onPress={() => void load()}>
          <Text style={styles.navText}>Reload</Text>
        </TouchableOpacity>
      </View>

      {loading ? (
        <View style={styles.center}>
          <ActivityIndicator color="#0F766E" />
          <Text style={styles.centerText}>Loading history</Text>
        </View>
      ) : summaries.length === 0 ? (
        <View style={styles.center}>
          <Text style={styles.emptyTitle}>No recordings yet</Text>
          <Text style={styles.centerText}>
            Start a foreground session and it will appear here by local day.
          </Text>
        </View>
      ) : (
        <FlatList
          contentContainerStyle={styles.listContent}
          data={summaries}
          keyExtractor={(item) => item.dayKey}
          renderItem={({ item }) => (
            <DayCard
              summary={item}
              onPress={() => onSelectDay(item.dayKey)}
            />
          )}
        />
      )}

      {error && <Text style={styles.errorText}>{error}</Text>}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0B0B0F',
    paddingTop: 48,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 12,
  },
  navButton: {
    minWidth: 72,
    borderRadius: 10,
    backgroundColor: 'rgba(17, 24, 39, 0.92)',
    paddingVertical: 9,
    paddingHorizontal: 12,
    alignItems: 'center',
  },
  navText: {
    color: '#F9FAFB',
    fontSize: 13,
    fontWeight: '700',
  },
  title: {
    color: '#FFFFFF',
    fontSize: 22,
    fontWeight: '800',
  },
  listContent: {
    paddingHorizontal: 16,
    paddingBottom: 32,
    gap: 12,
  },
  card: {
    backgroundColor: 'rgba(17, 24, 39, 0.92)',
    borderRadius: 14,
    padding: 16,
    gap: 8,
  },
  cardHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
  },
  dateText: {
    color: '#F9FAFB',
    fontSize: 18,
    fontWeight: '800',
  },
  chevron: {
    color: '#9CA3AF',
    fontSize: 24,
    fontWeight: '600',
  },
  metaText: {
    color: '#CBD5E1',
    fontSize: 13,
  },
  metricRow: {
    flexDirection: 'row',
    gap: 12,
  },
  metricText: {
    color: '#5EEAD4',
    fontSize: 14,
    fontWeight: '700',
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
    gap: 10,
  },
  emptyTitle: {
    color: '#F9FAFB',
    fontSize: 20,
    fontWeight: '800',
  },
  centerText: {
    color: '#9CA3AF',
    fontSize: 14,
    textAlign: 'center',
    lineHeight: 20,
  },
  errorText: {
    color: '#FCA5A5',
    fontSize: 13,
    paddingHorizontal: 16,
    paddingBottom: 16,
    textAlign: 'center',
  },
});
