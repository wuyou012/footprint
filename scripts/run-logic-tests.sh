#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build"
OUT="$BUILD_DIR/footprint-logic-tests"

mkdir -p "$BUILD_DIR"

swiftc \
  "$ROOT/footprint/Models/RegionModels.swift" \
  "$ROOT/footprint/Models/RegionAchievementModels.swift" \
  "$ROOT/footprint/Models/RegionAchievementMapModels.swift" \
  "$ROOT/footprint/Models/TrackModels.swift" \
  "$ROOT/footprint/Utilities/Formatters.swift" \
  "$ROOT/footprint/Services/LocationFilter.swift" \
  "$ROOT/footprint/Services/MotionGate.swift" \
  "$ROOT/footprint/Services/PersistentLocationCoordinator.swift" \
  "$ROOT/footprint/Services/SessionSegmenter.swift" \
  "$ROOT/footprint/Services/TrackDatabase.swift" \
  "$ROOT/footprint/Services/CityBoundaryCatalog.swift" \
  "$ROOT/Tests/FootprintLogicTests.swift" \
  -lsqlite3 \
  -o "$OUT"

"$OUT"
