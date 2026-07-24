# Review Request: F003 Country Border Overlay

Review-Target-ID: f003
Branch: `feat/f003-award-integration`
Code Head: `cf60dbd`
Worktree: `/Users/wuyou/Documents/APP_Project/footprint-f003-award-integration`

## What

Adds a configurable country-border overlay on top of the F003 award map:

- New bundled `country_boundaries.geojson` with 260 country/SAR boundary features.
- New reproducible generator `scripts/build-global-country-boundaries.mjs`.
- New `CountryBoundaryCatalog`, model, viewport limiter, and line-style defaults.
- Main `TrackMapView` draws country border polylines above award fills/strokes and below the user track.
- Settings now expose country border toggle, RGB color, line width, and line style.

## Why

co-creator accepted country-border option B:

> B是合理的操作

Opus clarified B as China-policy country boundaries: Taiwan not a separate country boundary, Tibet/South Tibet aligned with the existing admin1 override, HK/MO retained as SAR-style units, and South China Sea nine-dash line left as a separate pending sub-item.

## Data Policy / Tradeoff

The country bundle is generated with a hybrid policy path:

- Primary drawable boundaries come from the already-reviewed F003 policy admin1 catalog dissolved by `countryCode`. This keeps Taiwan and South Tibet aligned with the existing admin1 China override.
- Natural Earth Admin 0 Countries v5.1.1 fills countries/units not represented by the admin1 catalog.
- Taiwan is not emitted as `TW`, `TWN`, or `CN-TW` at country level; China includes `CN-TW` and `CN-XZ` in `sourceComponentRegionIds`.
- Nine-dash line is intentionally not included yet. That is still waiting for co-creator's explicit choice.

This avoids a false “admin0-only China override” claim: Natural Earth admin0 does not provide South Tibet as a separable country feature, while the current F003 admin1 bundle already carries the policy-adjusted geometry.

## Architecture Ownership

Architecture cell: footprint iOS awards / boundary catalog / map overlay rendering
Map delta: none
Why: Extends the existing bundle-catalog and `TrackMapView` overlay path; no new storage schema, matcher path, queue, or router.

## Reviewer Focus

- Check whether the hybrid admin1-dissolve + admin0-supplement approach is the right policy/provenance shape.
- Check `CountryBoundaryMapOverlayLimiter`: country borders are viewport-clipped and capped at 320, but unlike admin1 awards they are not dropped at broad zoom.
- Check `TrackMapView` render order and flattening of country polygons into line overlays.
- Check settings persistence keys and whether the defaults are visually reasonable on standard/satellite maps.
- Confirm nine-dash line remains out of scope for this commit.

## Quality Gate Report

### Spec / Feedback Coverage

| Requirement | Status | Evidence |
|---|---|---|
| Add country borders | Done | `CountryBoundaryCatalog`, `country_boundaries.geojson`, `TrackMapView` country polyline layer |
| Configurable line/color | Done | Settings toggle + RGB editor + style picker + width slider |
| China policy B | Done for main boundary body | Tests assert China includes `CN-TW`/`CN-XZ`, Taiwan not separate, India excludes `IN-AR` |
| Keep zoom performance | Done | `CountryBoundaryMapOverlayLimiter` viewport filter + cap 320 |
| Nine-dash line | Not included | Pending co-creator sub-decision |

### Validation Commands

```bash
./scripts/run-logic-tests.sh
# FootprintLogicTests passed

node scripts/build-global-country-boundaries.mjs \
  /tmp/ne_10m_admin_0_countries.zip \
  footprint/Data/city_boundaries.geojson \
  /tmp/footprint-country-boundaries-regen.geojson
cmp -s footprint/Data/country_boundaries.geojson /tmp/footprint-country-boundaries-regen.geojson \
  && echo COUNTRY_REGEN_MATCHES_CURRENT=YES
# COUNTRY_REGEN_MATCHES_CURRENT=YES

node - <<'NODE'
const fs=require('fs');
const fc=JSON.parse(fs.readFileSync('footprint/Data/country_boundaries.geojson','utf8'));
const byId=new Map(fc.features.map(f=>[f.properties.country_id,f]));
const cn=byId.get('CN');
const polyCount = f => f.geometry.type === 'MultiPolygon' ? f.geometry.coordinates.length : 1;
console.log(JSON.stringify({
  total: fc.features.length,
  cnPolygons: polyCount(cn),
  cnBoundaryPolicy: cn.properties.boundaryPolicy,
  cnIncludes: cn.properties.sourceComponentRegionIds.filter(id=>['CN-TW','CN-XZ'].includes(id)),
  hasTW: byId.has('TW'),
  hasTWN: byId.has('TWN'),
  hasHK: byId.has('HK'),
  hasMO: byId.has('MO')
}, null, 2));
NODE
# total=260, cnPolygons=6, cnBoundaryPolicy=china-policy-override,
# cnIncludes=["CN-TW","CN-XZ"], hasTW=false, hasTWN=false, hasHK=true, hasMO=true

git diff --check
# exit 0

xcodebuild -project footprint.xcodeproj -scheme footprint -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# ** BUILD SUCCEEDED **
```

Existing warnings only:

- `CLGeocoder` / `reverseGeocodeLocation` deprecations in `RegionAchievementService`.
- AppIntents metadata warning because the app has no AppIntents dependency.

### Simulator Dogfood

- Installed the Debug build into booted iPhone 17 Pro simulator.
- Granted simulator location permission and launched `com.wuyou.footprint`.
- Inserted a temporary simulator-only Taiwan track into the simulator SQLite DB to force a country-border viewport.
- Screenshot: `/tmp/f003-country-borders-taiwan.png`; map rendered Taiwan with country-border outline, controls usable, no blank/frozen launch.

## Next Action

Review this commit. If accepted, co-creator can interactively verify the new country-border settings in simulator and decide whether to add the South China Sea nine-dash line as a separate follow-up.
