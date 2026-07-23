# Review Request: F003 Global Admin1 Award Boundaries

Review-Target-ID: f003
Branch: `feat/f003-award-integration`
Code Head: `220c8b6`
Worktree: `/Users/wuyou/Documents/APP_Project/footprint-f003-award-integration`

## What

Extended F003 award overlays from the previously verified Japan admin1 catalog to global first-level boundaries:

- Regenerated `footprint/Data/city_boundaries.geojson` to include 4,482 global admin1 regions across 240 countries/regions.
- Preserved the existing Japan MLIT prefecture catalog (`JP-01`...`JP-47`) and the San Francisco city demo feature.
- Added `scripts/build-global-admin1-boundaries.mjs` to rebuild the global catalog from Natural Earth Admin 1 States/Provinces data.
- Updated `BundledRegionDataProvider` to cache decoded boundary data and fingerprint together.
- Updated `RegionAchievementService` legacy-geocoder fallback de-dupe from Japan-only admin1 keys to generic ISO admin1 keys.
- Expanded F001 verification to cover representative points in US, Canada, Australia, Brazil, China, India, Japan, and ocean miss behavior.

## Why

co-creator is continuing F002 real-device dogfood separately and asked to proceed with F003 award development in simulator. The award map should no longer be Japan-only; it needs global first-level boundaries so main-screen award overlay and unlocks work worldwide.

## Original Requirements

> 现在进行f003对award开发，使用虚拟机完成，这个可以同步进行并轻易合并  
> award功能需要实现全球的第一级边界线，之前只实现并验证了日本的

- Source: thread `thread_mrf0m4q6dbosnc13`, co-creator messages `0001784798701522-000313-85a35a99` and `0001784797151988-000306-e414b65f`.
- Existing F003 spec source: `main:docs/features/F003-award-integration.md` (current feature branch was based on F002 and does not contain the main-only spec commit).
- Please review against both the F003 integration goals and the new global-admin1 expansion requirement.

## Tradeoff

- Source: Natural Earth Admin 1 States/Provinces 10m v5.1.1, public domain, de facto boundaries.
- Kept Japan on the existing MLIT N03-2024 source because that path was already verified and keeps Japanese names/aliases stable.
- Used `2%` mapshaper simplification. `0.1%` was too coarse and caused a Sydney point-in-polygon miss for `AU-NSW`; `2%` preserves representative matcher checks while keeping the catalog about 4.4 MB.
- Did not filter islands by default. A trial island-area filter produced null geometries and dropped legitimate island admin1 regions.
- This is a first-level boundary visual/achievement dataset, not a legal boundary authority. Natural Earth publishes generalized de facto boundaries; reviewer should treat disputed/precision-sensitive boundary semantics accordingly.

Source links:
- Natural Earth Admin 1 States/Provinces: https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-admin-1-states-provinces/
- Natural Earth project/license overview: https://www.naturalearthdata.com/
- Natural Earth terms/caveats: https://www.naturalearthdata.com/about/terms-of-use/

## Architecture Ownership

Architecture cell: footprint iOS awards / region catalog / local SQLite achievements
Map delta: none
Why: Extends the existing F003 award region data-provider/service path and keeps storage/local matching boundaries intact; no new parallel Store, Queue, Router, Adapter, Dispatcher, or Binding was introduced.

Reviewer focus:
- `BundledRegionDataProvider` cache correctness and thread safety.
- Data-generation script reproducibility, source metadata, and preservation of Japan/SF records.
- `RegionAchievementService` de-dupe logic for global ISO admin1 IDs.
- Runtime/performance impact of a 4.4 MB global boundary bundle in simulator and app launch.

## Open Questions

### Technical OQ

- Is Natural Earth 10m `2%` simplification the right default quality/size balance for on-device overlay and point matching?
- Should the global catalog keep every Natural Earth admin1 feature, or should a later pass define a curated display subset per zoom/region?
- Are the source metadata fields sufficient for future provenance debugging (`source`, `sourceVersion`, `sourceYear`, `license`, `boundaryPolicy`, `mapCluster`)?

### Value OQ

None for this review. Dataset policy caveat is documented; global admin1 support is the requested direction.

## Fresh-Context Findings

Agent: `[gpt/gpt-5.5🐾]`
SHA scanned: `220c8b6`
Total findings: 0 (0 P1, 0 P2, 0 P3)

Author scan notes:
- Rechecked global catalog counts and representative point matches.
- Rechecked cache path does not keep raw 4.4 MB `Data` in memory after decode.
- Rechecked root media/design artifact gates are clean.

## Next Action

`@opus48` please cross-review this branch before merge-gate. This is not a self-review; I authored the implementation and am requesting independent review of data source, geometry quality, caching, and simulator behavior.

## Review Sandbox

- Path: `/tmp/cat-cafe-review/f003/opus48`
- Start Command: no server; open the Xcode project or use the validation commands below.
- Ports: none.

Suggested reviewer bootstrap:

```bash
git clone https://github.com/wuyou012/footprint.git /tmp/cat-cafe-review/f003/opus48
cd /tmp/cat-cafe-review/f003/opus48
git checkout feat/f003-award-integration
```

## Self-Check Evidence

### Spec Compliance

- F003 AC-1: F001 award + F002 persistent recording remain in one build; Debug/Release simulator builds passed.
- F003 AC-2: Prior review passed migration merge; this patch does not change schema migrations.
- F003 AC-3: Main map award overlay still launches in simulator; screenshot captured.
- F003 AC-4: Award data service still consumes `track_points`; this patch expands boundaries and fallback de-dupe only.
- F003 AC-5: iPhone 17 simulator app launch screenshot exists at `/tmp/footprint-f003-global-admin1-final.png`.
- New global-admin1 requirement: verifier confirms 4,482 admin1 regions / 240 countries, preserves 47 Japan prefectures, and matches representative global points.

### Design / Artifact Hygiene

```bash
git status --short | rg '^.. [^/]+\.(png|jpe?g|webp|gif|webm|mp4|mov|wav|pdf|pen)$' || true
# no output

git diff --name-only origin/main...HEAD | rg '^[^/]+\.(png|jpe?g|webp|gif|webm|mp4|mov|wav|pdf|pen)$' || true
# no output

find designs -name '*.pen' -print 2>/dev/null || true
# no output
```

### Dogfood

- Simulator device: booted iPhone 17, iOS 26.5.
- App install: `xcrun simctl install booted /tmp/footprint-f003-dd-debug/Build/Products/Debug-iphonesimulator/footprint.app` -> exit 0.
- App launch: `xcrun simctl launch booted com.wuyou.footprint` -> PID `60319`.
- Screenshot: `/tmp/footprint-f003-global-admin1-final.png`; main map rendered, UI controls visible, no crash/blank screen.

### Validation Commands

```bash
./scripts/run-logic-tests.sh
# FootprintLogicTests passed

swiftc -D DEBUG \
  footprint/Models/RegionModels.swift \
  footprint/Models/RegionAchievementModels.swift \
  footprint/Models/RegionAchievementMapModels.swift \
  footprint/Services/ChinaGeo.swift \
  footprint/Services/RegionMatcher.swift \
  footprint/Services/BundledRegionDataProvider.swift \
  footprint/Services/CityBoundaryCatalog.swift \
  footprint/Services/RegionAchievementDemoSeeds.swift \
  scripts/verify-f001-region-lighting.swift \
  -o .build/verify-f001-region-lighting && .build/verify-f001-region-lighting
# F001 verification passed

git diff --check
# exit 0

xcodebuild -project footprint.xcodeproj \
  -scheme footprint \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /tmp/footprint-f003-dd-debug build
# ** BUILD SUCCEEDED **

xcodebuild -project footprint.xcodeproj \
  -scheme footprint \
  -configuration Release \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -derivedDataPath /tmp/footprint-f003-dd-release build
# ** BUILD SUCCEEDED **
```

Warnings observed:
- Existing `CLGeocoder` deprecation warning in `RegionAchievementService` legacy path.
- AppIntents metadata warning about no AppShortcuts; not new and not functional.

## Related Docs

- Feature spec: `main:docs/features/F003-award-integration.md`
- Architecture reference: `docs/ARCHITECTURE.md`
- Code commit: `220c8b64f8b3f2fcb9d717aa6bce660e7f7d36fb`
