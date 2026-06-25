# D0-D1 GPS Probe Drop-in

## Intent

Implement the first slice of the new data-pipeline plan from `world-2.txt`.
This separates raw GPS acquisition from downstream track filtering, rendering,
and GPX export.

The goal is to stop using "track points on map" as the proxy for "background
GPS works". Probe mode records raw location events first, then later D2 can
replay those events into accepted track points.

## Files to apply

Add:

- `src/services/RawLocationStore.ts`

Replace:

- `src/services/TrackStore.ts`
- `src/services/BackgroundLocation.ts`
- `src/screens/MapTestScreen.tsx`

Existing baseline files in this handoff directory should remain from the P4
diagnostic baseline:

- `src/services/LocationPoint.ts`
- `src/services/RecordingProfile.ts`
- `src/services/LocationFilter.ts`
- `src/services/TrackDataSource.ts`
- `src/services/GpxExport.ts`
- `index.ts`

## Schema

`SCHEMA_VERSION = 4`.

The v4 migration only creates new diagnostic tables:

- `probe_sessions`
- `raw_location_events`

It does not drop, rebuild, or alter `track_points`. Existing user track data
survives.

## Probe behavior

Foreground Probe:

- uses foreground `watchPositionAsync`
- `distanceInterval = 0`
- writes `raw_location_events`
- does not clear `track_points`
- does not write `track_points`

Background Probe:

- uses the existing Expo TaskManager task
- `distanceInterval = 0`
- `timeInterval = 10000`
- writes `raw_location_events`
- does not run `shouldAcceptPoint`
- does not write `track_points`
- has its own foreground-service notification

Normal `Start GPS` remains the product recording path and still writes accepted
points through `shouldAcceptPoint`.

## UI

The main screen now has a probe section:

- `FG Probe`
- `BG Probe`
- `Stop Probe`
- `Export Probe`

It displays:

- probe session id
- foreground/background mode
- raw event count
- task invocation count
- last received time
- delivery delay
- accuracy

## Verification

1. `npx tsc --noEmit`
2. Build release APK.
3. Install on P30.
4. Foreground probe:
   - tap `FG Probe`
   - wait near a window/outdoors
   - raw count should increase
   - stop and export probe log
5. Background probe:
   - tap `BG Probe`
   - lock screen for 20-30 minutes
   - unlock
   - raw count / task invocation count / delivery delay should give a clear
     answer:
     - raw grows: background acquisition works
     - task grows but raw does not: task wakeup without payload/provider issue
     - neither grows: background task/foreground-service/OEM restriction
6. Export Probe Log and inspect JSON.

## Not included yet

- D2 replay processor (`raw_location_events` -> `track_points`)
- raw retention policy
- session stats / battery stats
- accepted-only bbox rendering
