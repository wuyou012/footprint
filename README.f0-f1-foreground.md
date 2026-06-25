# F0/F1 foreground drop-in

Target repo: `C:\Users\admin\Project\footprint`
Base commit: `be8ff38479c0301d1df117039f30332af7590f56`

## Files to apply

- `package.json`
- `package-lock.json`
- `src/services/TrackStore.ts`
- `src/services/TrackDataSource.ts`
- `src/services/RecordingProfile.ts`
- `src/services/GpxExport.ts`
- `src/screens/MapTestScreen.tsx`

## Scope

- F0 data safety:
  - Product Start no longer calls `replaceTrackPoints([])`.
  - Product Start no longer starts background recording.
  - Start creates a foreground `recording_sessions` row and one `track_segments` row.
  - Foreground fixes are filtered with `shouldAcceptPoint`, then appended to `track_points` with `session_id`, `segment_id`, `profile`, `source`, and `local_day_key`.
  - Stop closes the session and segment as `completed`.
  - Previous open foreground sessions are marked `interrupted` before a new session starts.
- F1 modes:
  - Adds `high`.
  - Keeps default `daily`.
  - Tunes `daily` and `eco` for foreground active-session recording.
- GPX:
  - Exports multiple `<trkseg>` groups by `segment_id`.
  - Writes footprint metadata extensions for session, segment, profile, source, local day, and accuracy.

## Data safety notes

- v5 migration is additive only.
- It reuses v2 `recording_sessions` and `track_segments`.
- It adds nullable columns and indexes only:
  - `recording_sessions.source/status/local_day_key/timezone_offset_min`
  - `track_segments.distance_meters/local_day_key`
  - `track_points.session_id/local_day_key`
- No migration `DROP`.
- No migration delete.
- `DELETE FROM track_points` remains only inside the explicit `replaceTrackPoints()` helper; product screen no longer imports or calls that helper.

## Required verification after applying

1. `npm install` or equivalent, so `expo-keep-awake` becomes a top-level installed dependency.
2. `npx tsc --noEmit`
3. `android\gradlew.bat assembleRelease`
4. Install on device.
5. F0 acceptance:
   - Record A with Daily, Stop.
   - Record B with Daily, Stop.
   - Confirm point count increases and A/B both remain rendered/exportable.
   - Kill app, reopen, confirm A/B remain.
   - Start again, confirm old data is not cleared.
6. F1 acceptance:
   - Record short High/Daily/Eco foreground sessions.
   - Confirm all three create sessions, draw segments, and export GPX.

## Local Codex verification

- Could not run project `tsc` in this sandbox: no `node/npm/npx` on PATH, and the only found Cursor `node.exe` exits with `EPERM` while realpathing `C:\Users\admin`.
- Performed static symbol checks and JSON parsing of `package.json` / `package-lock.json`.
