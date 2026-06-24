import * as SQLite from 'expo-sqlite';

import type { TrackPoint } from './TrackDataSource';

/**
 * SQLite store for raw WGS-84 track points.
 *
 * Data safety rule: migrations are additive and preserve existing user points.
 * Never drop or recreate `track_points` in a local migration.
 */
const DB_NAME = 'footprint.db';
const SCHEMA_VERSION = 2;

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

async function migrate(db: SQLite.SQLiteDatabase): Promise<void> {
  await db.execAsync('PRAGMA journal_mode = WAL');

  const version = await getUserVersion(db);
  if (version < 1) {
    await migrateToV1(db);
  }
  if (version < 2) {
    await migrateToV2(db);
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
