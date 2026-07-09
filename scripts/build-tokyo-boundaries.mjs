#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [, , inputPath, outputPath] = process.argv;

if (!inputPath || !outputPath) {
  console.error("Usage: node scripts/build-tokyo-boundaries.mjs <N03 Tokyo GeoJSON> <output GeoJSON>");
  process.exit(2);
}

const simplifyPercent = process.env.TOKYO_ADMIN1_SIMPLIFY ?? "1%";
const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "footprint-tokyo-admin1-"));
const dissolvedPath = path.join(temporaryDirectory, "tokyo-admin1.geojson");

const mapshaper = spawnSync(
  "npx",
  [
    "-y",
    "mapshaper",
    inputPath,
    "-filter",
    'N03_007 && N03_007 != "13000"',
    "-dissolve",
    "-simplify",
    simplifyPercent,
    "keep-shapes",
    "-o",
    "format=geojson",
    dissolvedPath
  ],
  { encoding: "utf8" }
);

if (mapshaper.status !== 0) {
  process.stderr.write(mapshaper.stdout);
  process.stderr.write(mapshaper.stderr);
  process.exit(mapshaper.status ?? 1);
}

const dissolved = JSON.parse(fs.readFileSync(dissolvedPath, "utf8"));
const tokyoGeometry = normalizeGeometryCollection(dissolved);
const existing = fs.existsSync(outputPath)
  ? JSON.parse(fs.readFileSync(outputPath, "utf8"))
  : { type: "FeatureCollection", features: [] };
const preservedFeatures = (existing.features ?? []).filter((feature) => {
  const regionId = String(feature.properties?.region_id ?? feature.properties?.regionId ?? feature.properties?.id ?? "");
  return !regionId.startsWith("JP-13");
});

const collection = {
  type: "FeatureCollection",
  features: [
    ...preservedFeatures,
    {
      type: "Feature",
      properties: {
        id: "jp-13-tokyo",
        region_id: "JP-13",
        level: "admin1",
        parent_id: "JP",
        countryCode: "jp",
        countryName: "日本",
        adminArea: "東京都",
        cityName: "東京都",
        nameZh: "東京都",
        nameEn: "Tokyo",
        cityKey: "jp|東京都|東京都",
        aliases: [
          "jp|tokyo|tokyo",
          "jp|tokyo|東京都",
          "jp|东京|東京都",
          "jp|東京都|東京都"
        ],
        source: "MLIT KSJ N03-2024",
        sourceYear: 2024,
        license: "CC-BY-4.0",
        mapCluster: "tokyo-admin1"
      },
      geometry: tokyoGeometry
    }
  ]
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(collection)}\n`);

const polygons = tokyoGeometry.type === "Polygon" ? 1 : tokyoGeometry.coordinates.length;
const coordinates = countCoordinates(tokyoGeometry);
console.log(`wrote Tokyo admin1 boundary (${polygons} polygons, ${coordinates} coordinates) to ${outputPath}`);

function normalizeGeometryCollection(root) {
  const geometries = root.type === "GeometryCollection"
    ? root.geometries
    : (root.features ?? []).map((feature) => feature.geometry);
  const polygons = [];
  for (const geometry of geometries) {
    if (!geometry) {
      continue;
    }
    if (geometry.type === "Polygon") {
      polygons.push(roundPolygon(geometry.coordinates));
    } else if (geometry.type === "MultiPolygon") {
      polygons.push(...geometry.coordinates.map(roundPolygon));
    }
  }

  const sortedPolygons = polygons
    .filter((polygon) => polygon.length > 0 && polygon[0].length >= 4)
    .sort((lhs, rhs) => polygonBBoxArea(rhs) - polygonBBoxArea(lhs));

  if (sortedPolygons.length === 1) {
    return { type: "Polygon", coordinates: sortedPolygons[0] };
  }
  return { type: "MultiPolygon", coordinates: sortedPolygons };
}

function roundPolygon(polygon) {
  return polygon.map((ring) => ring.map(([longitude, latitude]) => [
    Number(longitude.toFixed(6)),
    Number(latitude.toFixed(6))
  ]));
}

function countCoordinates(geometry) {
  const polygons = geometry.type === "Polygon" ? [geometry.coordinates] : geometry.coordinates;
  let count = 0;
  for (const polygon of polygons) {
    for (const ring of polygon) {
      count += ring.length;
    }
  }
  return count;
}

function polygonBBoxArea(polygon) {
  const exterior = polygon[0] ?? [];
  if (!exterior.length) {
    return 0;
  }
  const longitudes = exterior.map(([longitude]) => longitude);
  const latitudes = exterior.map(([, latitude]) => latitude);
  return (Math.max(...longitudes) - Math.min(...longitudes))
    * (Math.max(...latitudes) - Math.min(...latitudes));
}
