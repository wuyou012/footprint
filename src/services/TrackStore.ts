import * as SQLite from 'expo-sqlite';

import type { TrackPoint } from './TrackDataSource';

/**
 * P2 SQLite store.
 *
 * Persists track points locally so a track survives an app restart (the P2
 * acceptance bar). Coordinates are stored as **raw WGS-84** only — coordinate
 * conversion happens at render time via CoordinateService, never on the way
 * into storage.
 *
 * The schema creates `track_points` (active) plus reserved skeleton tables
 * (`source` / `footprint_events` / `place_stats`) up front so later phases add
 * rows without a migration. expo-sqlite is async, so every accessor is a
 * Promise — this is why the P1 `TrackDataSource` interface becomes async.
 */
const DB_NAME = 'footprint.db';
const SCHEMA_VERSION = 1;

let dbPromise: Promise<SQLite.SQLiteDatabase> | null = null;

async function migrate(db: SQLite.SQLiteDatabase): Promise<void> {
  const row = await db.getFirstAsync<{ user_version: number }>(
    'PRAGMA user_version',
  );
  if ((row?.user_version ?? 0) >= SCHEMA_VERSION) {
    return;
  }

  await db.execAsync(`
    PRAGMA journal_mode = WAL;
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
    PRAGMA user_version = ${SCHEMA_VERSION};
  `);
}

export async function getDatabase(): Promise<SQLite.SQLiteDatabase> {
  if (!dbPromise) {
    dbPromise = (async () => {
      const db = await SQLite.openDatabaseAsync(DB_NAME);
      await migrate(db);
      // Consolidate any WAL accumulated from prior sessions (repeated reseeds
      // can bloat it) so cold-start reads stay fast and the file is bounded.
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

type TrackPointRow = { lng: number; lat: number; ts: number };

export async function getTrackPoints(limit: number): Promise<TrackPoint[]> {
  const db = await getDatabase();
  const rows = await db.getAllAsync<TrackPointRow>(
    'SELECT lng, lat, ts FROM track_points ORDER BY ts ASC LIMIT ?',
    [limit],
  );
  return rows.map((r) => ({
    longitude: r.lng,
    latitude: r.lat,
    timestamp: r.ts,
  }));
}

// Chunked multi-row INSERT: SQLite caps bound params at 999, and 3 columns per
// row means up to 333 rows per statement. 300 keeps headroom while turning a
// 10k insert from ~10k native round-trips into ~34 — the difference between a
// ~20s freeze and a snappy write.
const COLUMNS_PER_ROW = 3;
const ROWS_PER_INSERT = 300;

/**
 * Replace all stored points with `points`, in a single transaction. Used by
 * the P2 perf buttons and the first-launch seed. Stores raw WGS-84 only.
 */
export async function replaceTrackPoints(
  points: readonly TrackPoint[],
): Promise<void> {
  const db = await getDatabase();
  await db.withTransactionAsync(async () => {
    await db.execAsync('DELETE FROM track_points');
    for (let i = 0; i < points.length; i += ROWS_PER_INSERT) {
      const chunk = points.slice(i, i + ROWS_PER_INSERT);
      const placeholders = chunk.map(() => '(?, ?, ?)').join(', ');
      const params: number[] = [];
      for (const p of chunk) {
        params.push(p.longitude, p.latitude, p.timestamp);
      }
      await db.runAsync(
        `INSERT INTO track_points (lng, lat, ts) VALUES ${placeholders}`,
        params,
      );
    }
  });
}
