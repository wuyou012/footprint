import { File, Paths } from 'expo-file-system';
import * as Location from 'expo-location';
import * as Sharing from 'expo-sharing';

import { getDatabase } from './TrackStore';

export type ProbeMode = 'foreground' | 'background';
export type RawLocationSource = 'foreground_watch' | 'background_task';
export type RawLocationAppState = 'foreground' | 'background' | 'locked_unknown';

export type ProbeSessionSummary = {
  id: number;
  mode: ProbeMode;
  profile: string | null;
  startTs: number;
  endTs: number | null;
  taskInvokedCount: number;
  rawCount: number;
  errorCount: number;
  lastReceivedAt: number | null;
  lastLocationTimestamp: number | null;
  lastDeliveryDelayMs: number | null;
  lastAccuracy: number | null;
  lastLatitude: number | null;
  lastLongitude: number | null;
  lastError: string | null;
  stopReason: string | null;
};

export type RawLocationEvent = {
  id: number;
  probeSessionId: number | null;
  source: RawLocationSource;
  appState: RawLocationAppState | null;
  profile: string | null;
  taskInvokedAt: number | null;
  receivedAt: number;
  locationTimestamp: number | null;
  deliveryDelayMs: number | null;
  locationCountInBatch: number;
  latitude: number | null;
  longitude: number | null;
  accuracy: number | null;
  altitude: number | null;
  speed: number | null;
  heading: number | null;
  isMocked: boolean | null;
  providerStatusJson: string | null;
  rawPayloadJson: string | null;
};

type ProbeSessionRow = {
  id: number;
  mode: string;
  profile: string | null;
  start_ts: number;
  end_ts: number | null;
  task_invoked_count: number;
  raw_count: number;
  error_count: number;
  last_received_at: number | null;
  last_location_timestamp: number | null;
  last_delivery_delay_ms: number | null;
  last_accuracy: number | null;
  last_lat: number | null;
  last_lng: number | null;
  last_error: string | null;
  stop_reason: string | null;
};

type RawLocationEventRow = {
  id: number;
  probe_session_id: number | null;
  source: string;
  app_state: string | null;
  profile: string | null;
  task_invoked_at: number | null;
  received_at: number;
  location_timestamp: number | null;
  delivery_delay_ms: number | null;
  location_count_in_batch: number;
  latitude: number | null;
  longitude: number | null;
  accuracy: number | null;
  altitude: number | null;
  speed: number | null;
  heading: number | null;
  is_mocked: number | null;
  provider_status_json: string | null;
  raw_payload_json: string | null;
};

export type RecordRawLocationEventInput = {
  probeSessionId: number | null;
  source: RawLocationSource;
  appState: RawLocationAppState;
  profile?: string | null;
  taskInvokedAt?: number | null;
  locationCountInBatch: number;
  location: Location.LocationObject;
  providerStatus?: unknown;
};

const PROBE_LOG_MIME_TYPE = 'application/json';

function finiteOrNull(value: number | null | undefined): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function safeJson(value: unknown): string | null {
  if (value === undefined || value === null) {
    return null;
  }
  try {
    return JSON.stringify(value);
  } catch {
    return null;
  }
}

function probeRowToSummary(row: ProbeSessionRow): ProbeSessionSummary {
  return {
    id: row.id,
    mode: row.mode === 'background' ? 'background' : 'foreground',
    profile: row.profile,
    startTs: row.start_ts,
    endTs: row.end_ts,
    taskInvokedCount: row.task_invoked_count,
    rawCount: row.raw_count,
    errorCount: row.error_count,
    lastReceivedAt: row.last_received_at,
    lastLocationTimestamp: row.last_location_timestamp,
    lastDeliveryDelayMs: row.last_delivery_delay_ms,
    lastAccuracy: row.last_accuracy,
    lastLatitude: row.last_lat,
    lastLongitude: row.last_lng,
    lastError: row.last_error,
    stopReason: row.stop_reason,
  };
}

function eventRowToEvent(row: RawLocationEventRow): RawLocationEvent {
  return {
    id: row.id,
    probeSessionId: row.probe_session_id,
    source:
      row.source === 'background_task' ? 'background_task' : 'foreground_watch',
    appState:
      row.app_state === 'background' ||
      row.app_state === 'locked_unknown' ||
      row.app_state === 'foreground'
        ? row.app_state
        : null,
    profile: row.profile,
    taskInvokedAt: row.task_invoked_at,
    receivedAt: row.received_at,
    locationTimestamp: row.location_timestamp,
    deliveryDelayMs: row.delivery_delay_ms,
    locationCountInBatch: row.location_count_in_batch,
    latitude: row.latitude,
    longitude: row.longitude,
    accuracy: row.accuracy,
    altitude: row.altitude,
    speed: row.speed,
    heading: row.heading,
    isMocked: row.is_mocked === null ? null : row.is_mocked === 1,
    providerStatusJson: row.provider_status_json,
    rawPayloadJson: row.raw_payload_json,
  };
}

export async function startProbeSession(
  mode: ProbeMode,
  profile: string | null = null,
): Promise<number> {
  const db = await getDatabase();
  const now = Date.now();
  const result = await db.runAsync(
    `INSERT INTO probe_sessions (
      mode, profile, start_ts, created_at
    ) VALUES (?, ?, ?, ?)`,
    [mode, profile, now, now],
  );
  return result.lastInsertRowId;
}

export async function endProbeSession(
  sessionId: number | null,
  stopReason = 'stopped',
): Promise<void> {
  if (sessionId === null) {
    return;
  }

  const db = await getDatabase();
  await db.runAsync(
    `UPDATE probe_sessions
     SET end_ts = ?,
       stop_reason = ?
     WHERE id = ? AND end_ts IS NULL`,
    [Date.now(), stopReason, sessionId],
  );
}

export async function getOpenProbeSessionId(
  mode: ProbeMode,
): Promise<number | null> {
  const db = await getDatabase();
  const row = await db.getFirstAsync<{ id: number }>(
    `SELECT id
     FROM probe_sessions
     WHERE mode = ? AND end_ts IS NULL
     ORDER BY start_ts DESC
     LIMIT 1`,
    [mode],
  );
  return row?.id ?? null;
}

export async function incrementProbeTaskInvocation(
  sessionId: number | null,
): Promise<void> {
  if (sessionId === null) {
    return;
  }

  const db = await getDatabase();
  await db.runAsync(
    `UPDATE probe_sessions
     SET task_invoked_count = task_invoked_count + 1
     WHERE id = ?`,
    [sessionId],
  );
}

export async function recordProbeError(
  sessionId: number | null,
  message: string,
): Promise<void> {
  if (sessionId === null) {
    return;
  }

  const db = await getDatabase();
  await db.runAsync(
    `UPDATE probe_sessions
     SET error_count = error_count + 1,
       last_error = ?
     WHERE id = ?`,
    [message, sessionId],
  );
}

export async function recordRawLocationEvent(
  input: RecordRawLocationEventInput,
): Promise<void> {
  const db = await getDatabase();
  const receivedAt = Date.now();
  const locationTimestamp = Number.isFinite(input.location.timestamp)
    ? input.location.timestamp
    : null;
  const deliveryDelayMs =
    locationTimestamp === null ? null : receivedAt - locationTimestamp;
  const { coords } = input.location;

  await db.withExclusiveTransactionAsync(async (txn) => {
    await txn.runAsync(
      `INSERT INTO raw_location_events (
        probe_session_id,
        source,
        app_state,
        profile,
        task_invoked_at,
        received_at,
        location_timestamp,
        delivery_delay_ms,
        location_count_in_batch,
        latitude,
        longitude,
        accuracy,
        altitude,
        speed,
        heading,
        is_mocked,
        provider_status_json,
        raw_payload_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        input.probeSessionId,
        input.source,
        input.appState,
        input.profile ?? null,
        input.taskInvokedAt ?? null,
        receivedAt,
        locationTimestamp,
        deliveryDelayMs,
        input.locationCountInBatch,
        finiteOrNull(coords.latitude),
        finiteOrNull(coords.longitude),
        finiteOrNull(coords.accuracy),
        finiteOrNull(coords.altitude),
        finiteOrNull(coords.speed),
        finiteOrNull(coords.heading),
        input.location.mocked === undefined
          ? null
          : input.location.mocked
            ? 1
            : 0,
        safeJson(input.providerStatus),
        safeJson(input.location),
        receivedAt,
      ],
    );

    if (input.probeSessionId !== null) {
      await txn.runAsync(
        `UPDATE probe_sessions
         SET raw_count = raw_count + 1,
           last_received_at = ?,
           last_location_timestamp = ?,
           last_delivery_delay_ms = ?,
           last_accuracy = ?,
           last_lat = ?,
           last_lng = ?,
           last_error = NULL
         WHERE id = ?`,
        [
          receivedAt,
          locationTimestamp,
          deliveryDelayMs,
          finiteOrNull(coords.accuracy),
          finiteOrNull(coords.latitude),
          finiteOrNull(coords.longitude),
          input.probeSessionId,
        ],
      );
    }
  });
}

export async function getProbeSummary(
  sessionId?: number | null,
): Promise<ProbeSessionSummary | null> {
  const db = await getDatabase();
  const row =
    sessionId === undefined || sessionId === null
      ? await db.getFirstAsync<ProbeSessionRow>(
          `SELECT *
           FROM probe_sessions
           ORDER BY start_ts DESC
           LIMIT 1`,
          [],
        )
      : await db.getFirstAsync<ProbeSessionRow>(
          `SELECT *
           FROM probe_sessions
           WHERE id = ?
           LIMIT 1`,
          [sessionId],
        );
  return row ? probeRowToSummary(row) : null;
}

export async function getRawEvents(
  sessionId: number,
  limit = 10000,
): Promise<RawLocationEvent[]> {
  const safeLimit = Number.isFinite(limit)
    ? Math.max(0, Math.min(50000, Math.floor(limit)))
    : 0;
  const db = await getDatabase();
  const rows = await db.getAllAsync<RawLocationEventRow>(
    `SELECT *
     FROM raw_location_events
     WHERE probe_session_id = ?
     ORDER BY received_at ASC
     LIMIT ?`,
    [sessionId, safeLimit],
  );
  return rows.map(eventRowToEvent);
}

function probeLogName(sessionId: number): string {
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  return `footprint-probe-${sessionId}-${stamp}.json`;
}

export async function exportProbeLog(sessionId?: number | null): Promise<void> {
  const summary = await getProbeSummary(sessionId);
  if (!summary) {
    throw new Error('No probe session to export');
  }

  if (!(await Sharing.isAvailableAsync())) {
    throw new Error('Sharing is not available on this device');
  }

  const events = await getRawEvents(summary.id);
  const file = new File(Paths.document, probeLogName(summary.id));
  file.create({ intermediates: true, overwrite: true });
  file.write(JSON.stringify({ summary, events }, null, 2), {
    encoding: 'utf8',
  });

  await Sharing.shareAsync(file.uri, {
    mimeType: PROBE_LOG_MIME_TYPE,
    dialogTitle: 'Export Probe Log',
  });
}
