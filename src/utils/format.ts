/**
 * Pure formatting helpers shared by the record UI. Kept free of React/Expo
 * imports so the recording logic chain can be reasoned about (and unit-tested)
 * in isolation.
 */

export function formatClock(timestamp: number | null | undefined): string {
  if (!timestamp) {
    return 'never';
  }
  return new Date(timestamp).toLocaleTimeString();
}

export function formatAccuracy(accuracy: number | null | undefined): string {
  return typeof accuracy === 'number' && Number.isFinite(accuracy)
    ? `${Math.round(accuracy)}m`
    : 'n/a';
}

/** Human distance: `<1km` shows whole metres, otherwise 2-dp kilometres. */
export function formatDistance(meters: number | null | undefined): string {
  if (typeof meters !== 'number' || !Number.isFinite(meters) || meters < 0) {
    return '0 m';
  }
  if (meters < 1000) {
    return `${Math.round(meters)} m`;
  }
  return `${(meters / 1000).toFixed(2)} km`;
}

/** Elapsed clock: `m:ss`, or `h:mm:ss` once it crosses an hour. */
export function formatDuration(ms: number | null | undefined): string {
  if (typeof ms !== 'number' || !Number.isFinite(ms) || ms < 0) {
    return '0:00';
  }
  const totalSeconds = Math.floor(ms / 1000);
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  const ss = seconds.toString().padStart(2, '0');
  if (hours > 0) {
    const mm = minutes.toString().padStart(2, '0');
    return `${hours}:${mm}:${ss}`;
  }
  return `${minutes}:${ss}`;
}

/** "10s ago" / "3m ago" / "2h ago", used by the low-power last-fix line. */
export function formatRelativeTime(
  timestamp: number | null | undefined,
  now: number = Date.now(),
): string {
  if (!timestamp) {
    return 'never';
  }
  const deltaMs = now - timestamp;
  if (deltaMs < 1000) {
    return 'just now';
  }
  const seconds = Math.floor(deltaMs / 1000);
  if (seconds < 60) {
    return `${seconds}s ago`;
  }
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) {
    return `${minutes}m ago`;
  }
  const hours = Math.floor(minutes / 60);
  return `${hours}h ago`;
}
