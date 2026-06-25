/**
 * Public live-stats shape for a foreground recording session. Lives apart from
 * the hook so view components can depend on the data contract without importing
 * the recording implementation.
 */
export type RecordingStats = {
  startedAt: number | null;
  durationMs: number;
  distanceMeters: number;
  acceptedCount: number;
  receivedCount: number;
  lastFixTs: number | null;
  lastAccuracy: number | null;
};

export const IDLE_STATS: RecordingStats = {
  startedAt: null,
  durationMs: 0,
  distanceMeters: 0,
  acceptedCount: 0,
  receivedCount: 0,
  lastFixTs: null,
  lastAccuracy: null,
};
