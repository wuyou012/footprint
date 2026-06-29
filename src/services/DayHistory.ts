import type { TrackPoint } from './TrackDataSource';
import { getDatabase } from './TrackStore';

const MAX_DAY_POINTS = 50000;

/**
 * Only foreground product sessions that carry a local day and actually got past
 * the start gate. Pre-F0 sessions may have NULL status, so treat NULL as valid.
 */
const PRODUCT_SESSION_FILTER =
  "source = 'foreground' AND local_day_key IS NOT NULL " +
  "AND (status IS NULL OR status != 'start_failed')";

/** One row per local day for the History list. */
export type DaySummary = {
  dayKey: string;
  sessionCount: number;
  pointCount: number;
  distanceMeters: number;
  durationSeconds: number;
  firstStartedAt: number | null;
  lastEndedAt: number | null;
};

/** One recording session within a day, for the Day Detail list. */
export type DaySession = {
  id: number;
  profile: string | null;
  startTs: number | null;
  endTs: number | null;
  pointCount: number;
  distanceMeters: number;
};

type DaySummaryRow = {
  local_day_key: string;
  session_count: number;
  point_count: number | null;
  distance_meters: number | null;
  duration_ms: number | null;
  first_started_at: number | null;
  last_ended_at: number | null;
};

type DaySessionRow = {
  id: number;
  profile: string | null;
  start_ts: number | null;
  end_ts: number | null;
  accepted_count: number | null;
  distance_meters: number | null;
};

type TrackPointRow = {
  lng: number;
  lat: number;
  ts: number;
  accuracy: number | null;
  speed: number | null;
  altitude: number | null;
  heading: number | null;
  session_id: number | null;
  segment_id: number | null;
  source_id: number | null;
  source: string | null;
  profile: string | null;
  local_day_key: string | null;
};

/** Days that have recordings, newest first. Backed by idx_recording_sessions_local_day. */
export async function getDaySummaries(): Promise<DaySummary[]> {
  const db = await getDatabase();
  const rows = await db.getAllAsync<DaySummaryRow>(
    `SELECT
       local_day_key,
       COUNT(*) AS session_count,
       SUM(accepted_count) AS point_count,
       SUM(distance_meters) AS distance_meters,
       SUM(CASE WHEN end_ts IS NOT NULL AND start_ts IS NOT NULL
             THEN end_ts - start_ts ELSE 0 END) AS duration_ms,
       MIN(start_ts) AS first_started_at,
       MAX(end_ts) AS last_ended_at
     FROM recording_sessions
     WHERE ${PRODUCT_SESSION_FILTER}
     GROUP BY local_day_key
     ORDER BY local_day_key DESC`,
  );
  return rows.map((r) => ({
    dayKey: r.local_day_key,
    sessionCount: r.session_count,
    pointCount: r.point_count ?? 0,
    distanceMeters: r.distance_meters ?? 0,
    durationSeconds: Math.round((r.duration_ms ?? 0) / 1000),
    firstStartedAt: r.first_started_at,
    lastEndedAt: r.last_ended_at,
  }));
}

/** Sessions recorded on a given local day, earliest first. */
export async function getSessionsForDay(dayKey: string): Promise<DaySession[]> {
  const db = await getDatabase();
  const rows = await db.getAllAsync<DaySessionRow>(
    `SELECT id, profile, start_ts, end_ts, accepted_count, distance_meters
     FROM recording_sessions
     WHERE local_day_key = ? AND ${PRODUCT_SESSION_FILTER}
     ORDER BY start_ts ASC`,
    [dayKey],
  );
  return rows.map((r) => ({
    id: r.id,
    profile: r.profile,
    startTs: r.start_ts,
    endTs: r.end_ts,
    pointCount: r.accepted_count ?? 0,
    distanceMeters: r.distance_meters ?? 0,
  }));
}

/**
 * All accepted points belonging to a day's sessions (for the Day Detail map),
 * oldest first. Keyed by session-start day (via session_id), NOT by each
 * point's own day, so a session crossing local midnight stays whole and matches
 * getSessionsForDay / export / deleteDay exactly.
 */
export async function getTrackPointsForDay(
  dayKey: string,
): Promise<TrackPoint[]> {
  const db = await getDatabase();
  const rows = await db.getAllAsync<TrackPointRow>(
    `SELECT lng, lat, ts, accuracy, speed, altitude, heading,
       session_id, segment_id, source_id, source, profile, local_day_key
     FROM track_points
     WHERE session_id IN (
       SELECT id FROM recording_sessions
       WHERE local_day_key = ? AND ${PRODUCT_SESSION_FILTER}
     )
     ORDER BY ts ASC
     LIMIT ?`,
    [dayKey, MAX_DAY_POINTS],
  );
  return rows.map((r) => ({
    longitude: r.lng,
    latitude: r.lat,
    timestamp: r.ts,
    accuracy: r.accuracy,
    speed: r.speed,
    altitude: r.altitude,
    heading: r.heading,
    sessionId: r.session_id,
    segmentId: r.segment_id,
    sourceId: r.source_id,
    source: r.source,
    profile: r.profile,
    localDayKey: r.local_day_key,
  }));
}

/**
 * Delete one local day's recordings — the points, segments, and sessions of
 * every foreground session whose START day is `dayKey`. The ONLY sanctioned
 * deletion path, strictly user-initiated (the UI must confirm first). Wrapped
 * in a transaction so it is all-or-nothing, and scoped by session id so a
 * session crossing local midnight is deleted as one unit (no orphaned
 * after-midnight points). Other days — and legacy points with no session — are
 * untouched.
 */
export async function deleteDay(dayKey: string): Promise<void> {
  const db = await getDatabase();
  const daySessionIds = `SELECT id FROM recording_sessions
       WHERE local_day_key = ? AND ${PRODUCT_SESSION_FILTER}`;
  await db.withTransactionAsync(async () => {
    await db.runAsync(
      `DELETE FROM track_points WHERE session_id IN (${daySessionIds})`,
      [dayKey],
    );
    await db.runAsync(
      `DELETE FROM track_segments WHERE session_id IN (${daySessionIds})`,
      [dayKey],
    );
    await db.runAsync(
      `DELETE FROM recording_sessions
       WHERE local_day_key = ? AND ${PRODUCT_SESSION_FILTER}`,
      [dayKey],
    );
  });
}
