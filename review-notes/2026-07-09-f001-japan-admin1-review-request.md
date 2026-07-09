---
feature_ids: [F001]
topics: [review, region-achievement, japan, admin1, mapkit]
doc_kind: review_request
created: 2026-07-09
review_target_id: f001
branch: feat/f001-japan-admin1
head: 8af1899
---

# Review Request: F001 Japan Admin1 Overview

Review-Target-ID: f001
Branch: `feat/f001-japan-admin1`
HEAD: `8af1899`

## Original Requirements

Spec: `docs/features/F001-region-lighting.md`

Relevant operator scope:
- First record the whole-Tokyo milestone and parked ward-level tag.
- Then show all of Japan at the same admin1 level as Tokyo: Tokyo remains lit, the remaining prefectures render as faint outlines.
- Keep rendering pressure low; ward/city-level precision remains parked behind `f001-tokyo-ward-level-v1`.

## What

- Replaced Japan catalog data with all 47 prefectures:
  - region IDs: `JP-01` through `JP-47`
  - level: `admin1`
  - source: official MLIT KSJ N03 2024 / CC BY 4.0
  - output: 48 features total including `US-CA-SF`
- Added `scripts/build-japan-admin1-boundaries.mjs` and removed the Tokyo-only generator.
- Kept Tokyo unlocked via existing DEBUG seed (`JP-13`); the other 46 prefectures render locked/faint.
- Added Japan overview focus so the initial JP view fits the main archipelago instead of being stretched by far islands.
- Generalized legacy geocoder fallback suppression from only `JP-13` to all `JP-01..JP-47` admin1 regions, preventing duplicate city chips under prefecture mode.
- Updated F001 docs and BACKLOG from "in progress" to "all-Japan admin1 pending review".

## Why

The whole-Tokyo admin1 version reduced rendering pressure and matched co-creator's product direction. The next requested view is the same granularity for Japan: one region per prefecture, with visited Tokyo lit and all unvisited prefectures visible as faint outlines.

## Tradeoff

- Used the N03 `prefecture.geojson` layer instead of dissolving from municipalities; it already represents prefecture-level geometry and avoids unnecessary processing.
- Applied aggressive lightweight generation: `filter-islands min-area=5km2` + `simplify 0.1% keep-shapes`. This drops micro-islands/rocks but keeps major prefecture shapes, including Tokyo/Okinawa island groups.
- Did not implement whole-vs-ward toggle UI; the ward-level Tokyo implementation remains parked in tag `f001-tokyo-ward-level-v1`.
- Did not clear the legacy CLGeocoder path; this pass only suppresses duplicate map chips for admin1-covered Japanese city fallbacks.

## Open Questions

Technical:
- Are the simplification thresholds acceptable for product visuals and future GPS matching?
- Is fixed Japan overview focus acceptable for now, or should focus metadata be encoded per data pack?
- Should fallback suppression be moved from ad hoc admin key matching into the future P4 geocoder-removal work?

Value:
- None for this review. The co-creator explicitly chose admin1 Japan before returning to ward/city-level detail.

## Architecture Ownership

- Architecture cell: F001 Region Achievement / bundled region catalog + MapKit rendering.
- Map delta: update required at feature level only; no new app subsystem.
- Why: this changes data-pack shape, generation script, map focus behavior, and existing fallback filtering; it does not add a new storage or navigation boundary.

## Quality Gate

### Spec Alignment

- `region_id` remains canonical (`JP-01..JP-47`).
- WGS-84 remains the canonical datum.
- Matching remains point-in-polygon through `RegionMatcher`.
- Map rendering now shows all Japan prefectures at admin1 granularity.

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
  -o /tmp/f001-japan-admin1-verify && /tmp/f001-japan-admin1-verify
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

### Data Shape

```text
city_boundaries.geojson: 333KB
features: 48
polygons: 229
coordinates: 13,876
JP admin1 regions: 47
```

Simulator DB after launch:

```text
PRAGMA user_version = 3
regions = 48
region_geometry_index = 229
region_rtree = 229
region_catalog_metadata = city_boundaries | f7a0a244d95e636b | 48
```

### Dogfood

Scope verdict: required; this is user-visible map rendering.

Evidence:
- Installed and launched on iPhone 17 simulator with `--region-achievement-map-demo`.
- Screenshot: `/tmp/footprint-f001-japan-admin1-map.png`
- Visual result: `JP 1/47`, Tokyo gold/lit, remaining prefectures faint cyan outlines, default view fits Japan main archipelago.

### Artifact Hygiene

- Root media/design artifact scan: no matches.
- `.pen` design glob: no matches.

## Next Action

Please review `8af1899` on `feat/f001-japan-admin1`, focusing on:

1. N03 prefecture data generation and simplification thresholds.
2. `JP-01..JP-47` metadata / region ID correctness.
3. Japan overview focus behavior.
4. Generalized admin1 fallback suppression.

If approved, please merge into `feature/city-boundary-achievements` and run simulator acceptance for co-creator.
