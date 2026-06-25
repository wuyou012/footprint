import * as SQLite from 'expo-sqlite';

import type { TrackPoint } from './TrackDataSource';

/**
 * SQLite store for raw WGS-84 track points.
 *
 * Data safety rule: migrations are additive and preserve existing user points.
 * Never drop or recreate `track_points` in a local migration.
 */
const DB_NAME = 'footprint.db';
const SCHEMA_VERSION = 4;

let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;

async function getUserVersion(db: SQLite.SQLiteDatabase): Promise<number> {
  const row = await db.getFirstAsync<{ user_version: number }>(
    'PRAGMA user_version',
  );
  return row?.user_version ?? 0;
}

async function migrateToV1(db: SQLite.SQLiteDatabase): Promise<void> {
  await db.execAsync(`
    CREATE TABLE IF NOT EXISTS track_points (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lng REAL NOT NULL,
      lat REAL NOT NULL,
      ts INTEGER NOT NULL,
      accuracy REAL,
      speed REAL,
      altitude REAL,
      segment_id INTEGER,
      source_id INTEGER
    );
    CREATE INDEX IF NOT EXISTS idx_track_points_ts ON track_points (ts);
    CREATE TABLE IF NOT EXISTS source (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      created_ts INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS footprint_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      kind TEXT NOT NULL,
      lng REAL,
      lat REAL,
      ts INTEGER,
      meta TEXT
    );
    CREATE TABLE IF NOT EXISTS place_stats (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      scope TEXT NOT NULL,
      name TEXT NOT NULL,
      point_count INTEGER NOT NULL DEFAULT 0,
      updated_ts INTEGER
    );
    PRAGMA user_version = 1;
  `);
}

async function hasColumn(
  db: SQLite.SQLiteDatabase,
  tableName: string,
  columnName: string,
): Promise<boolean> {
  const rows = await db.getAllAsync<{ name: string }>(
    `PRAGMA table_info(${tableName})`,
  );
  return rows.some((row) => row.name === columnName);
}

async function addColumnIfMissing(
  db: SQLite.SQLiteDatabase,
  tableName: string,
  columnName: string,
  definition: string,
): Promise<void> {
  if (!(await hasColumn(db, tableName, columnName))) {
    await db.execAsync(`ALTER TABLE ${tableName} ADD COLUMN ${definition}`);
  }
}

async function migrateToV2(db: SQLite.SQLiteDatabase): Promise<void> {
  await addColumnIfMissing(db, 'track_points', 'heading', 'heading REAL');
  await addColumnIfMissing(db, 'track_points', 'profile', 'profile TEXT');
  await addColumnIfMissing(db, 'track_points', 'source', 'source TEXT');

  await db.execAsync(`
    CREATE TABLE IF NOT EXISTS recording_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      profile TEXT,
      start_ts INTEGER,
      end_ts INTEGER,
      received_count INTEGER NOT NULL DEFAULT 0,
      accepted_count INTEGER NOT NULL DEFAULT 0,
      rejected_count INTEGER NOT NULL DEFAULT 0,
      reject_accuracy_count INTEGER NOT NULL DEFAULT 0,
      reject_too_close_count INTEGER NOT NULL DEFAULT 0,
      reject_too_soon_count INTEGER NOT NULL DEFAULT 0,
      reject_invalid_count INTEGER NOT NULL DEFAULT 0,
      reject_jump_count INTEGER NOT NULL DEFAULT 0,
      battery_start REAL,
      battery_end REAL,
      db_size_start INTEGER,
      db_size_end INTEGER,
      distance_meters REAL,
      gpx_size_bytes INTEGER,
      stop_reason TEXT,
      created_ts INTEGER
    );
    CREATE TABLE IF NOT EXISTS track_segments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      session_id INTEGER,
      start_ts INTEGER,
      end_ts INTEGER,
      point_count INTEGER NOT NULL DEFAULT 0
    );
    CREATE INDEX IF NOT EXISTS idx_track_points_lat_lng
      ON track_points (lat, lng);
    CREATE INDEX IF NOT EXISTS idx_track_points_segment_ts
      ON track_points (segment_id, ts);
    PRAGMA user_version = 2;
  `);
}

async function migrateToV3(db: SQLite.SQLiteDatabase): Promise<void> {
  await db.execAsync(`
    CREATE TABLE IF NOT EXISTS location_diagnostics (
      id INTEGER PRIMARY KEY CHECK (id = 1),
      background_received_count INTEGER NOT NULL DEFAULT 0,
      background_accepted_count INTEGER NOT NULL DEFAULT 0,
      background_rejected_count INTEGER NOT NULL DEFAULT 0,
      background_last_fix_ts INTEGER,
      background_last_accepted_ts INTEGER,
      background_last_reject_reason TEXT,
      background_last_error TEXT,
      raw_received_count INTEGER NOT NULL DEFAULT 0,
      raw_last_fix_ts INTEGER,
      raw_last_accuracy REAL,
      raw_last_lng REAL,
      raw_last_lat REAL,
      raw_last_error TEXT,
      updated_ts INTEGER
    );
    INSERT OR IGNORE INTO location_diagnostics (id, updated_ts)
      VALUES (1, CAST(strftime('%s', 'now') AS INTEGER) * 1000);
    PRAGMA user_version = 3;
  `);
}

async function migrateToV4(db: SQLite.SQLiteDatabase): Promise<void> {
  await db.execAsync(`
    CREATE TABLE IF NOT EXISTS probe_sessions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      mode TEXT NOT NULL,
      profile TEXT,
      start_ts INTEGER NOT NULL,
      end_ts INTEGER,
      task_invoked_count INTEGER NOT NULL DEFAULT 0,
      raw_count INTEGER NOT NULL DEFAULT 0,
      error_count INTEGER NOT NULL DEFAULT 0,
      last_received_at INTEGER,
      last_location_timestamp INTEGER,
      last_delivery_delay_ms INTEGER,
      last_accuracy REAL,
      last_lat REAL,
      last_lng REAL,
      last_error TEXT,
      stop_reason TEXT,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS raw_location_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      probe_session_id INTEGER,
      source TEXT NOT NULL,
      app_state TEXT,
      profile TEXT,
      task_invoked_at INTEGER,
      received_at INTEGER NOT NULL,
      location_timestamp INTEGER,
      delivery_delay_ms INTEGER,
      location_count_in_batch INTEGER NOT NULL DEFAULT 1,
      latitude REAL,
      longitude REAL,
      accuracy REAL,
      altitude REAL,
      speed REAL,
      heading REAL,
      is_mocked INTEGER,
      provider_status_json TEXT,
      raw_payload_json TEXT,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_probe_sessions_start_ts
      ON probe_sessions (start_ts);
    CREATE INDEX IF NOT EXISTS idx_raw_location_events_session
      ON raw_location_events (probe_session_id, received_at);
    CREATE INDEX IF NOT EXISTS idx_raw_location_events_received_at
      ON raw_location_events (received_at);
    PRAGMA user_version = 4;
  `);
}

async function migrate(db: SQLite.SQLiteDatabase): Promise<void> {
  await db.execAsync('PRAGMA journal_mode = WAL');

  const version = await getUserVersion(db);
  if (version < 1) {
    await migrateToV1(db);
  }
  if (version < 2) {
    await migrateToV2(db);
  }
  if (version < 3) {
    await migrateToV3(db);
  }
  if (version < 4) {
    await migrateToV4(db);
  }
}

export async function getDatabase(): Promise<SQLite.SQLiteDatabase> {
  if (!dbPromise) {
    dbPromise = (async () => {
      const db = await SQLite.openDatabaseAsync(DB_NAME);
      await migrate(db);
      await db.execAsync('PRAGMA wal_checkpoint(TRUNCATE)');
      return db;
    })();
  }
  return dbPromise;
}

export async function countTrackPoints(): Promise<number> {
  const db = await getDatabase();
  const row = await db.getFirstAsync<{ c: number }>(
    'SELECT COUNT(*) AS c FROM track_points',
  );
  return row?.c ?? 0;
}

export type LocationDiagnosticSnapshot = {
  backgroundReceivedCount: number;
  backgroundAcceptedCount: number;
  backgroundRejectedCount: number;
  backgroundLastFixTs: number | null;
  backgroundLastAcceptedTs: number | null;
  backgroundLastRejectReason: string | null;
  backgroundLastError: string | null;
  rawReceivedCount: number;
  rawLastFixTs: number | null;
  rawLastAccuracy: number | null;
  rawLastLongitude: number | null;
  rawLastLatitude: number | null;
  rawLastError: string | null;
  updatedTs: number | null;
};

type LocationDiagnosticRow = {
  background_received_count: number;
  background_accepted_count: number;
  background_rejected_count: number;
  background_last_fix_ts: number | null;
  background_last_accepted_ts: number | null;
  background_last_reject_reason: string | null;
  background_last_error: string | null;
  raw_received_count: number;
  raw_last_fix_ts: number | null;
  raw_last_accuracy: number | null;
  raw_last_lng: number | null;
  raw_last_lat: number | null;
  raw_last_error: string | null;
  updated_ts: number | null;
};

function diagnosticRowToSnapshot(
  row: LocationDiagnosticRow,
): LocationDiagnosticSnapshot {
  return {
    backgroundReceivedCount: row.background_received_count,
    backgroundAcceptedCount: row.background_accepted_count,
    backgroundRejectedCount: row.background_rejected_count,
    backgroundLastFixTs: row.background_last_fix_ts,
    backgroundLastAcceptedTs: row.background_last_accepted_ts,
    backgroundLastRejectReason: row.background_last_reject_reason,
    backgroundLastError: row.background_last_error,
    rawReceivedCount: row.raw_received_count,
    rawLastFixTs: row.raw_last_fix_ts,
    rawLastAccuracy: row.raw_last_accuracy,
    rawLastLongitude: row.raw_last_lng,
    rawLastLatitude: row.raw_last_lat,
    rawLastError: row.raw_last_error,
    updatedTs: row.updated_ts,
  };
}

export async function getLocationDiagnostics(): Promise<LocationDiagnosticSnapshot> {
  const db = await getDatabase();
  const row = await db.getFirstAsync<LocationDiagnosticRow>(
    `SELECT
      background_received_count,
      background_accepted_count,
      background_rejected_count,
      background_last_fix_ts,
      background_last_accepted_ts,
      background_last_reject_reason,
      background_last_error,
      raw_received_count,
      raw_last_fix_ts,
      raw_last_accuracy,
      raw_last_lng,
      raw_last_lat,
      raw_last_error,
      updated_ts
     FROM location_diagnostics
     WHERE id = 1`,
  );

  return diagnosticRowToSnapshot(
    row ?? {
      background_received_count: 0,
      background_accepted_count: 0,
      background_rejected_count: 0,
      background_last_fix_ts: null,
      background_last_accepted_ts: null,
      background_last_reject_reason: null,
      background_last_error: null,
      raw_received_count: 0,
      raw_last_fix_ts: null,
      raw_last_accuracy: null,
      raw_last_lng: null,
      raw_last_lat: null,
      raw_last_error: null,
      updated_ts: null,
    },
  );
}

export async function resetBackgroundDiagnostics(): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET background_received_count = 0,
       background_accepted_count = 0,
       background_rejected_count = 0,
       background_last_fix_ts = NULL,
       background_last_accepted_ts = NULL,
       background_last_reject_reason = NULL,
       background_last_error = NULL,
       updated_ts = ?
     WHERE id = 1`,
    [Date.now()],
  );
}

export async function resetRawDiagnostics(): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET raw_received_count = 0,
       raw_last_fix_ts = NULL,
       raw_last_accuracy = NULL,
       raw_last_lng = NULL,
       raw_last_lat = NULL,
       raw_last_error = NULL,
       updated_ts = ?
     WHERE id = 1`,
    [Date.now()],
  );
}

export async function recordBackgroundLocationReceived(
  point: TrackPoint,
): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET background_received_count = background_received_count + 1,
       background_last_fix_ts = ?,
       background_last_error = NULL,
       updated_ts = ?
     WHERE id = 1`,
    [point.timestamp, Date.now()],
  );
}

export async function recordBackgroundLocationAccepted(
  point: TrackPoint,
): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET background_accepted_count = background_accepted_count + 1,
       background_last_accepted_ts = ?,
       background_last_reject_reason = NULL,
       background_last_error = NULL,
       updated_ts = ?
     WHERE id = 1`,
    [point.timestamp, Date.now()],
  );
}

export async function recordBackgroundLocationRejected(
  point: TrackPoint,
  reason: string,
): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET background_rejected_count = background_rejected_count + 1,
       background_last_reject_reason = ?,
       background_last_fix_ts = ?,
       updated_ts = ?
     WHERE id = 1`,
    [reason, point.timestamp, Date.now()],
  );
}

export async function recordBackgroundLocationError(
  message: string,
): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET background_last_error = ?,
       updated_ts = ?
     WHERE id = 1`,
    [message, Date.now()],
  );
}

export async function recordRawLocationDiagnostic(
  point: TrackPoint,
): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET raw_received_count = raw_received_count + 1,
       raw_last_fix_ts = ?,
       raw_last_accuracy = ?,
       raw_last_lng = ?,
       raw_last_lat = ?,
       raw_last_error = NULL,
       updated_ts = ?
     WHERE id = 1`,
    [
      point.timestamp,
      point.accuracy ?? null,
      point.longitude,
      point.latitude,
      Date.now(),
    ],
  );
}

export async function recordRawLocationError(message: string): Promise<void> {
  const db = await getDatabase();
  await db.runAsync(
    `UPDATE location_diagnostics
     SET raw_last_error = ?,
       updated_ts = ?
     WHERE id = 1`,
    [message, Date.now()],
  );
}

type TrackPointRow = {
  lng: number;
  lat: number;
  ts: number;
  accuracy: number | null;
  speed: number | null;
  altitude: number | null;
  heading: number | null;
  segment_id: number | null;
  source_id: number | null;
  source: string | null;
  profile: string | null;
};

export const MAX_TRACK_QUERY = 20000;

export async function getTrackPoints(limit: number): Promise<TrackPoint[]> {
  const safeLimit = Number.isFinite(limit)
    ? Math.max(0, Math.min(MAX_TRACK_QUERY, Math.floor(limit)))
    : 0;
  const db = await getDatabase();
  const rows = await db.getAllAsync<TrackPointRow>(
    `SELECT lng, lat, ts, accuracy, speed, altitude, heading,
      segment_id, source_id, source, profile
     FROM track_points
     ORDER BY ts ASC
     LIMIT ?`,
    [safeLimit],
  );
  return rows.map((r) => ({
    longitude: r.lng,
    latitude: r.lat,
    timestamp: r.ts,
    accuracy: r.accuracy,
    speed: r.speed,
    altitude: r.altitude,
    heading: r.heading,
    segmentId: r.segment_id,
    sourceId: r.source_id,
    source: r.source,
    profile: r.profile,
  }));
}

function rowToTrackPoint(r: TrackPointRow): TrackPoint {
  return {
    longitude: r.lng,
    latitude: r.lat,
    timestamp: r.ts,
    accuracy: r.accuracy,
    speed: r.speed,
    altitude: r.altitude,
    heading: r.heading,
    segmentId: r.segment_id,
    sourceId: r.source_id,
    source: r.source,
    profile: r.profile,
  };
}

export async function getLastTrackPoint(): Promise<TrackPoint | null> {
  const db = await getDatabase();
  const row = await db.getFirstAsync<TrackPointRow>(
    `SELECT lng, lat, ts, accuracy, speed, altitude, heading,
      segment_id, source_id, source, profile
     FROM track_points
     ORDER BY ts DESC
     LIMIT 1`,
  );
  return row ? rowToTrackPoint(row) : null;
}

export type AppendTrackPointOptions = {
  profile?: string | null;
  source?: string | null;
  segmentId?: number | null;
  sourceId?: number | null;
};

export async function appendTrackPoint(
  point: TrackPoint,
  options: AppendTrackPointOptions = {},
): Promise<void> {
  const db = await getDatabase();
  await db.withExclusiveTransactionAsync(async (txn) => {
    await txn.runAsync(
      `INSERT INTO track_points (
        lng, lat, ts, accuracy, speed, altitude, heading,
        segment_id, source_id, source, profile
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        point.longitude,
        point.latitude,
        point.timestamp,
        point.accuracy ?? null,
        point.speed ?? null,
        point.altitude ?? null,
        point.heading ?? null,
        options.segmentId ?? point.segmentId ?? null,
        options.sourceId ?? point.sourceId ?? null,
        options.source ?? point.source ?? 'gps',
        options.profile ?? point.profile ?? null,
      ],
    );
  });
}

const COLUMNS_PER_ROW = 3;
const ROWS_PER_INSERT = Math.floor(900 / COLUMNS_PER_ROW);

/**
 * Replace all stored points with `points`, in a single exclusive transaction.
 * Used for explicit reset/stress-test paths only. Existing user data is not
 * touched by migrations.
 */
export async function replaceTrackPoints(
  points: readonly TrackPoint[],
): Promise<void> {
  const db = await getDatabase();
  await db.withExclusiveTransactionAsync(async (txn) => {
    await txn.execAsync('DELETE FROM track_points');
    for (let i = 0; i < points.length; i += ROWS_PER_INSERT) {
      const chunk = points.slice(i, i + ROWS_PER_INSERT);
      const placeholders = chunk.map(() => '(?, ?, ?)').join(', ');
      const params: number[] = [];
      for (const p of chunk) {
        params.push(p.longitude, p.latitude, p.timestamp);
      }
      await txn.runAsync(
        `INSERT INTO track_points (lng, lat, ts) VALUES ${placeholders}`,
        params,
      );
    }
  });
}
