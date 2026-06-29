import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';

import { RecordMap } from '../components/record/RecordMap';
import {
  deleteDay,
  getSessionsForDay,
  getTrackPointsForDay,
  type DaySession,
} from '../services/DayHistory';
import { exportTrackAsGpx } from '../services/GpxExport';
import type { TrackPoint } from '../services/TrackDataSource';
import {
  formatClockRange,
  formatDayKey,
  formatDistance,
  formatError,
} from '../utils/format';

type DayDetailScreenProps = {
  dayKey: string;
  onBack: () => void;
  onDeleted: () => void;
};

function SessionRow({ session }: { session: DaySession }) {
  return (
    <View style={styles.sessionRow}>
      <View style={styles.sessionHeader}>
        <Text style={styles.sessionTime}>
          {formatClockRange(session.startTs, session.endTs)}
        </Text>
        <Text style={styles.sessionMode}>{session.profile ?? 'unknown'}</Text>
      </View>
      <Text style={styles.sessionMeta}>
        {session.pointCount.toLocaleString()} points -{' '}
        {formatDistance(session.distanceMeters)}
      </Text>
    </View>
  );
}

export function DayDetailScreen({
  dayKey,
  onBack,
  onDeleted,
}: DayDetailScreenProps) {
  const [sessions, setSessions] = useState<DaySession[]>([]);
  const [points, setPoints] = useState<TrackPoint[]>([]);
  const [loading, setLoading] = useState(true);
  const [exporting, setExporting] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [loadedSessions, loadedPoints] = await Promise.all([
        getSessionsForDay(dayKey),
        getTrackPointsForDay(dayKey),
      ]);
      setSessions(loadedSessions);
      setPoints(loadedPoints);
    } catch (e) {
      setError(formatError(e));
    } finally {
      setLoading(false);
    }
  }, [dayKey]);

  useEffect(() => {
    void load();
  }, [load]);

  const exportDay = useCallback(async () => {
    if (loading || exporting || deleting || points.length === 0) {
      return;
    }
    setExporting(true);
    setError(null);
    try {
      await exportTrackAsGpx(points);
    } catch (e) {
      const message = formatError(e);
      setError(
        /another share|being processed/i.test(message)
          ? 'A share is still open - close it, then tap Export again'
          : message,
      );
    } finally {
      setExporting(false);
    }
  }, [deleting, exporting, loading, points]);

  const confirmDelete = useCallback(() => {
    if (loading || exporting || deleting) {
      return;
    }
    Alert.alert(
      'Delete this day?',
      'This removes this day from local history. Other days are not touched.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: () => {
            void (async () => {
              setDeleting(true);
              setError(null);
              try {
                await deleteDay(dayKey);
                onDeleted();
              } catch (e) {
                setError(formatError(e));
                setDeleting(false);
              }
            })();
          },
        },
      ],
    );
  }, [dayKey, deleting, exporting, loading, onDeleted]);

  const totalDistance = sessions.reduce(
    (sum, session) => sum + session.distanceMeters,
    0,
  );
  const actionDisabled = loading || exporting || deleting;

  return (
    <View style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.navButton} onPress={onBack}>
          <Text style={styles.navText}>Back</Text>
        </TouchableOpacity>
        <View style={styles.titleWrap}>
          <Text style={styles.title}>{formatDayKey(dayKey)}</Text>
          <Text style={styles.subtitle}>
            {sessions.length.toLocaleString()} sessions -{' '}
            {points.length.toLocaleString()} points -{' '}
            {formatDistance(totalDistance)}
          </Text>
        </View>
      </View>

      {loading ? (
        <View style={styles.center}>
          <ActivityIndicator color="#0F766E" />
          <Text style={styles.centerText}>Loading day</Text>
        </View>
      ) : (
        <ScrollView contentContainerStyle={styles.content}>
          <View style={styles.mapFrame}>
            <RecordMap points={points} />
          </View>

          <View style={styles.actionRow}>
            <TouchableOpacity
              style={[styles.actionButton, actionDisabled && styles.disabled]}
              disabled={actionDisabled || points.length === 0}
              onPress={() => void exportDay()}
            >
              <Text style={styles.actionText}>
                {exporting ? 'Exporting' : 'Export GPX'}
              </Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={[
                styles.actionButton,
                styles.deleteButton,
                actionDisabled && styles.disabled,
              ]}
              disabled={actionDisabled}
              onPress={confirmDelete}
            >
              <Text style={styles.actionText}>
                {deleting ? 'Deleting' : 'Delete day'}
              </Text>
            </TouchableOpacity>
          </View>

          <View style={styles.section}>
            <Text style={styles.sectionTitle}>Sessions</Text>
            {sessions.length === 0 ? (
              <Text style={styles.centerText}>No sessions for this day.</Text>
            ) : (
              sessions.map((session) => (
                <SessionRow key={session.id} session={session} />
              ))
            )}
          </View>
        </ScrollView>
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
    gap: 12,
    paddingHorizontal: 16,
    paddingBottom: 12,
  },
  navButton: {
    borderRadius: 10,
    backgroundColor: 'rgba(17, 24, 39, 0.92)',
    paddingVertical: 9,
    paddingHorizontal: 12,
  },
  navText: {
    color: '#F9FAFB',
    fontSize: 13,
    fontWeight: '700',
  },
  titleWrap: {
    flex: 1,
  },
  title: {
    color: '#FFFFFF',
    fontSize: 20,
    fontWeight: '800',
  },
  subtitle: {
    color: '#CBD5E1',
    fontSize: 12,
    marginTop: 2,
  },
  content: {
    paddingHorizontal: 16,
    paddingBottom: 32,
    gap: 14,
  },
  mapFrame: {
    height: 280,
    overflow: 'hidden',
    borderRadius: 14,
    backgroundColor: '#111827',
  },
  actionRow: {
    flexDirection: 'row',
    gap: 12,
  },
  actionButton: {
    flex: 1,
    alignItems: 'center',
    borderRadius: 12,
    backgroundColor: '#0F766E',
    paddingVertical: 14,
  },
  deleteButton: {
    backgroundColor: '#DC2626',
  },
  disabled: {
    opacity: 0.5,
  },
  actionText: {
    color: '#FFFFFF',
    fontSize: 15,
    fontWeight: '800',
  },
  section: {
    gap: 10,
  },
  sectionTitle: {
    color: '#F9FAFB',
    fontSize: 18,
    fontWeight: '800',
  },
  sessionRow: {
    borderRadius: 12,
    backgroundColor: 'rgba(17, 24, 39, 0.92)',
    padding: 14,
    gap: 6,
  },
  sessionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    gap: 8,
  },
  sessionTime: {
    color: '#F9FAFB',
    flex: 1,
    fontSize: 14,
    fontWeight: '700',
  },
  sessionMode: {
    color: '#5EEAD4',
    fontSize: 13,
    fontWeight: '800',
    textTransform: 'uppercase',
  },
  sessionMeta: {
    color: '#CBD5E1',
    fontSize: 13,
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 32,
    gap: 10,
  },
  centerText: {
    color: '#9CA3AF',
    fontSize: 14,
    textAlign: 'center',
  },
  errorText: {
    color: '#FCA5A5',
    fontSize: 13,
    paddingHorizontal: 16,
    paddingBottom: 16,
    textAlign: 'center',
  },
});
