# Review Request: F003 Taiwan Dissolve + Track Map Overlay Limiter

Review-Target-ID: f003
Branch: `feat/f003-award-integration`
Code Head: `a3b8c58`
Worktree: `/Users/wuyou/Documents/APP_Project/footprint-f003-award-integration`

## What

Fixes two co-creator dogfood issues on top of the reviewed F003 global admin1 branch:

- Taiwan no longer renders as 21 county/city components. `CN-TW` geometry is dissolved with the pinned mapshaper pipeline, and the bundled catalog now has 3 polygons for `CN-TW` while preserving 21 source component IDs.
- Main `TrackMapView` no longer feeds every global admin1 boundary into SwiftUI Map overlays. It now derives a visible viewport from the map camera and routes award cities through a viewport/LOD limiter.
- Added logic tests for Taiwan dissolved geometry, viewport clipping, and broad-zoom locked-region dropping.

## Why

Original co-creator feedback:

> 现在缩小地图的时候会出现卡顿，此外，台湾依旧被细分为很多，台湾是否可以调用api然后进行后处理

Root cause confirmed locally:

- Taiwan folding only changed metadata to `CN-TW`; it concatenated county geometries into a 21-part `MultiPolygon` without topological dissolve.
- `TrackMapView` rendered `ForEach(regionAwardCities)` directly, so the global 4k+ admin1 catalog could enter the Map overlay tree during zoom.

## Original Requirements

- F003 spec source: `main:docs/features/F003-award-integration.md`
- Current dogfood feedback source: thread `thread_mrf0m4q6dbosnc13`, co-creator message `0001784898959407-000366-d7133671`
- Prior global-admin1 request source: `review-notes/2026-07-23-f003-global-admin1-review-request.md`

## Tradeoff

- Did not introduce an external Taiwan boundary API. The project already pins Natural Earth + `mapshaper@0.7.47`; dissolving with the same tool keeps the catalog reproducible and avoids a second provenance/compliance track.
- Broad zoom now renders unlocked regions only. This favors interaction performance over showing every locked global boundary at continent/world scale; close zoom still shows viewport-intersecting locked boundaries.

## Architecture Ownership

Architecture cell: footprint iOS awards / region catalog / map overlay rendering
Map delta: none
Why: Extends the existing F003 region catalog generation and `TrackMapView` overlay path; no new Store, Queue, Router, Adapter, Dispatcher, or Binding.

## Fresh-Context Findings

Agent: `[gpt/gpt-5.5🐾]`
SHA scanned: `a3b8c58`
Total findings: 0 (0 P1, 0 P2, 0 P3)

Scan notes:

- Checked `isStationary`/F002 files were untouched.
- Checked `TrackMapView` initializes `visibleAwardViewport` before first render and updates it from `onMapCameraChange(.onEnd)`.
- Checked `CN-TW` metadata stays folded under China while geometry polygon count drops from 21 to 3.

## Reviewer Focus

- Please inspect whether `RegionAchievementMapOverlayLimiter` thresholds are conservative enough for simulator zoom while still showing useful close-range boundaries.
- Please inspect the mapshaper dissolve helper in `scripts/build-global-admin1-boundaries.mjs`. After review, I downloaded the official Natural Earth zip to `/tmp`, reran full generation into `/tmp/footprint-city-boundaries-full-regen.geojson`, and confirmed that the output is byte-identical to the current bundled catalog.
- Subjective pinch/zoom smoothness still needs interactive simulator review; automated injection is limited here, but the app launches and renders after installing the new build.

## Quality Gate Report

### Spec / Feedback Coverage

| Requirement | Status | Evidence |
|---|---|---|
| Taiwan should not display county/city subdivision | Done | `CN-TW` bundled geometry 21 -> 3 polygons; `testTaiwanBoundaryIsDissolvedForMapOverlay` |
| Zoom should not render all global boundaries | Done | `RegionAchievementMapOverlayLimiter`; `TrackMapView` uses viewport state; tests cover close viewport and broad zoom |
| F003/F002 integration should remain intact | Done | Logic tests + Xcode simulator build |

### Design / Artifact Hygiene

```bash
rg --files | rg '(^|/)designs/.*\.pen$|\.pen$'
# no output

git status --short | rg '^.. [^/]+\.(png|jpe?g|webp|gif|webm|mp4|mov|wav|pdf|pen)$' || true
# no output

git diff --name-only origin/main...HEAD | rg '^[^/]+\.(png|jpe?g|webp|gif|webm|mp4|mov|wav|pdf|pen)$' || true
# no output
```

### Dogfood

- Simulator: booted iPhone 17, iOS 26.5.
- Install/launch: `xcrun simctl install booted .../footprint.app && xcrun simctl launch booted com.wuyou.footprint` -> PID `8075`.
- Screenshot: `/tmp/f003-taiwan-dissolve-overlay-limiter.png`; map rendered, controls visible, no blank/frozen launch.

### Validation Commands

```bash
scripts/run-logic-tests.sh
# FootprintLogicTests passed

swiftc -parse-as-library \
  footprint/Models/RegionModels.swift \
  footprint/Models/RegionAchievementModels.swift \
  footprint/Models/RegionAchievementMapModels.swift \
  footprint/Services/ChinaGeo.swift \
  footprint/Services/RegionMatcher.swift \
  footprint/Services/CityBoundaryCatalog.swift \
  footprint/Services/BundledRegionDataProvider.swift \
  scripts/verify-f001-region-lighting.swift \
  -o .build/f001-region-lighting-verifier && .build/f001-region-lighting-verifier
# F001 verification passed

node -e "...inspect CN-TW and catalog counts..."
# {"total":4462,"admin1":4461,"countries":239,"cnTwPolygons":3,"cnTwComponents":21}

curl -L -f -o /tmp/ne_10m_admin_1_states_provinces.zip https://naturalearth.s3.amazonaws.com/10m_cultural/ne_10m_admin_1_states_provinces.zip
cp footprint/Data/city_boundaries.geojson /tmp/footprint-city-boundaries-full-regen.geojson
node scripts/build-global-admin1-boundaries.mjs /tmp/ne_10m_admin_1_states_provinces.zip /tmp/footprint-city-boundaries-full-regen.geojson
cmp -s footprint/Data/city_boundaries.geojson /tmp/footprint-city-boundaries-full-regen.geojson && echo "FULL_REGEN_MATCHES_CURRENT=YES"
# FULL_REGEN_MATCHES_CURRENT=YES

git diff --check
# exit 0

xcodebuild -project footprint.xcodeproj -scheme footprint -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' build
# ** BUILD SUCCEEDED **
```

Warnings observed:

- Existing `CLGeocoder` deprecation warnings in `RegionAchievementService`.
- Existing AppIntents metadata warning about no AppShortcuts.

## Next Action

`@opus48` please cross-review `a3b8c58` before merge-gate.

[gpt/gpt-5.5🐾]
