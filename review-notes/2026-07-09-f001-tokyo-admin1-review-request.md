---
feature_ids: [F001]
topics: [review, region-achievement, tokyo, mapkit]
doc_kind: review_request
created: 2026-07-09
review_target_id: f001
branch: feat/f001-tokyo-admin1
head: 7d3672e
---

# Review Request: F001 Tokyo Admin1 Lighting

Review-Target-ID: f001
Branch: `feat/f001-tokyo-admin1`
HEAD: `7d3672e`

## Original Requirements

Spec: `docs/features/F001-region-lighting.md`

Relevant excerpts:
- "用户走过的 GPS 轨迹，通过 point-in-polygon 命中行政区边界 -> 点亮该 region -> 地图上整块填色。"
- "region_id 是主键 ... 不再用 cityKey/name/alias 作为匹配核心。"
- co-creator latest scope: first tag the 62-municipality Tokyo version, then treat the entire Tokyo prefecture as one lit region to reduce rendering pressure.

## What

- Collapsed Tokyo from 62 municipality regions to one admin1 region:
  - `region_id=JP-13`
  - `level=admin1`
  - name `東京都` / `Tokyo`
  - MultiPolygon geometry, 60 polygons / 2,851 coordinates.
- Kept San Francisco demo region unchanged.
- Updated DEBUG seed so the Shinjuku seed lights `JP-13`.
- Removed the per-sample SQLite R*Tree candidate query in `loadTrackRegionPointCounts`; matching now uses the in-memory `RegionMatcher` over the loaded catalog.
- Suppressed legacy CLGeocoder fallback chips covered by the admin1 Tokyo catalog, so map UI shows only `東京都` for Japan.
- Added a Tokyo mainland default camera region so Ogasawara/Izu islands remain in geometry but do not force the initial view to zoom out across the ocean.
- Updated the verifier to assert `JP-13`, Shinjuku/Shibuya/Ogasawara matches, and no ward-level region leaks back into this pack.

## Why

The 62-municipality Tokyo pack worked visually, but co-creator observed that city/ward-level granularity adds rendering pressure and boundary precision tradeoffs that are not needed for the current product feel. Treating Tokyo as one region gives the intended whole-area lighting effect with one map chip and far less overlay pressure.

## Tradeoff

- Parked the detailed Tokyo municipality implementation behind tag `f001-tokyo-ward-level-v1` (`b5526f5`) instead of deleting the path permanently.
- Did not build a UI toggle in this pass; the branch keeps `level` metadata so a future whole-vs-ward data mode can be added cleanly.
- Kept the existing coarse track sample cells for this pass. The precision fix is intentionally deferred with the ward-level work because current admin1 Tokyo does not need sub-ward attribution.
- Used `mapshaper` dissolve/simplify in the generation script instead of maintaining custom geometry union code.

## Open Questions

Technical:
- Is the `JP-13` admin fallback suppression scoped tightly enough, or should it be generalized for future admin1 packs?
- Is the fixed mainland camera (`35.69, 139.50`, span `1.25 x 1.85`) acceptable, or should it come from data metadata later?
- Is `TOKYO_ADMIN1_SIMPLIFY=1%` the right balance for MapKit, given the current 60 polygons / 2,851 coordinates result?

Value:
- None for this review. The product direction was already decided by co-creator: whole Tokyo first, detailed city/ward mode later if needed.

## Architecture Ownership

- Architecture cell: F001 Region Achievement / MapKit boundary rendering in the iOS app.
- Map delta: update required at feature level only; no new ownership cell or parallel runtime subsystem.
- Why: this changes bundled region data shape and existing region achievement service/rendering behavior, not app navigation or storage ownership boundaries.

## Quality Gate

### Spec Alignment

- Whole Tokyo is represented by stable `region_id=JP-13`.
- Matching remains point-in-polygon over WGS-84 geometry.
- The debug Shinjuku coordinate lights Tokyo via the real matcher path.
- Fine-grained ward data is not lost; it is preserved behind tag `f001-tokyo-ward-level-v1`.

### Verification Commands

```bash
swiftc -D DEBUG -parse-as-library scripts/verify-f001-region-lighting.swift \
  footprint/Models/RegionModels.swift \
  footprint/Models/RegionAchievementModels.swift \
  footprint/Models/RegionAchievementMapModels.swift \
  footprint/Services/ChinaGeo.swift \
  footprint/Services/RegionMatcher.swift \
  footprint/Services/BundledRegionDataProvider.swift \
  footprint/Services/RegionAchievementDemoSeeds.swift \
  -o /tmp/f001-admin1-verify && /tmp/f001-admin1-verify
```

Result: `F001 verification passed`

```bash
xcodebuild -project footprint.xcodeproj -scheme footprint \
  -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Result: `** BUILD SUCCEEDED **`

```bash
git diff --check
```

Result: no output.

### Dogfood

Scope verdict: required; this is user-visible map rendering.

Evidence:
- Installed and launched on iPhone 17 simulator with `--region-achievement-map-demo`.
- Screenshot: `/tmp/footprint-f001-admin1-map-final.png`
- Visual result: Japan shows `JP 1/1`, only one `東京都` chip, whole Tokyo rendered as one yellow lit region without internal ward boundaries, with islands retained in geometry.

### Runtime DB Check

Simulator DB after launch:

```text
PRAGMA user_version = 3
regions = 2
region_geometry_index = 61
region_rtree = 61
region_catalog_metadata = city_boundaries | c900222ae5595e45 | 2
```

### Artifact Hygiene

- Root media/design artifact scan: no matches.
- `.pen` design glob: no matches.

## Next Action

Please review `7d3672e` on `feat/f001-tokyo-admin1`, focusing on:

1. `scripts/build-tokyo-boundaries.mjs` dissolve/simplify correctness.
2. `footprint/Data/city_boundaries.geojson` shape and metadata for `JP-13`.
3. `RegionAchievementService` fallback suppression and removal of per-sample DB R*Tree calls.
4. `RegionAchievementMapView` mainland default focus for Tokyo.

If approved, please merge into `feature/city-boundary-achievements` and run the simulator acceptance path for co-creator.
