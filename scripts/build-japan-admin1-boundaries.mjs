#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const englishPrefectureNames = {
  "01": "Hokkaido",
  "02": "Aomori",
  "03": "Iwate",
  "04": "Miyagi",
  "05": "Akita",
  "06": "Yamagata",
  "07": "Fukushima",
  "08": "Ibaraki",
  "09": "Tochigi",
  "10": "Gunma",
  "11": "Saitama",
  "12": "Chiba",
  "13": "Tokyo",
  "14": "Kanagawa",
  "15": "Niigata",
  "16": "Toyama",
  "17": "Ishikawa",
  "18": "Fukui",
  "19": "Yamanashi",
  "20": "Nagano",
  "21": "Gifu",
  "22": "Shizuoka",
  "23": "Aichi",
  "24": "Mie",
  "25": "Shiga",
  "26": "Kyoto",
  "27": "Osaka",
  "28": "Hyogo",
  "29": "Nara",
  "30": "Wakayama",
  "31": "Tottori",
  "32": "Shimane",
  "33": "Okayama",
  "34": "Hiroshima",
  "35": "Yamaguchi",
  "36": "Tokushima",
  "37": "Kagawa",
  "38": "Ehime",
  "39": "Kochi",
  "40": "Fukuoka",
  "41": "Saga",
  "42": "Nagasaki",
  "43": "Kumamoto",
  "44": "Oita",
  "45": "Miyazaki",
  "46": "Kagoshima",
  "47": "Okinawa"
};

const [, , inputPath, outputPath] = process.argv;

if (!inputPath || !outputPath) {
  console.error("Usage: node scripts/build-japan-admin1-boundaries.mjs <N03 prefecture GeoJSON> <output GeoJSON>");
  process.exit(2);
}

const simplifyPercent = process.env.JAPAN_ADMIN1_SIMPLIFY ?? "0.1%";
const minimumIslandArea = process.env.JAPAN_ADMIN1_MIN_ISLAND_AREA ?? "5km2";
const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "footprint-japan-admin1-"));
const dissolvedPath = path.join(temporaryDirectory, "japan-admin1.geojson");

const mapshaper = spawnSync(
  "npx",
  [
    "-y",
    "mapshaper",
    inputPath,
    "-filter",
    "!!N03_007 && !!N03_001",
    "-dissolve",
    "N03_007",
    "copy-fields=N03_001",
    "-filter-islands",
    `min-area=${minimumIslandArea}`,
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
const japanFeatures = (dissolved.features ?? [])
  .map(japanAdmin1Feature)
  .sort((lhs, rhs) => lhs.properties.region_id.localeCompare(rhs.properties.region_id));

validatePrefectureSet(japanFeatures);

const existing = fs.existsSync(outputPath)
  ? JSON.parse(fs.readFileSync(outputPath, "utf8"))
  : { type: "FeatureCollection", features: [] };
const preservedFeatures = (existing.features ?? []).filter((feature) => {
  const regionId = String(feature.properties?.region_id ?? feature.properties?.regionId ?? feature.properties?.id ?? "");
  return !regionId.startsWith("JP-");
});

const collection = {
  type: "FeatureCollection",
  features: [
    ...preservedFeatures,
    ...japanFeatures
  ]
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(collection)}\n`);

const totalPolygons = japanFeatures.reduce((sum, feature) => sum + polygonCount(feature.geometry), 0);
const totalCoordinates = japanFeatures.reduce((sum, feature) => sum + countCoordinates(feature.geometry), 0);
console.log(
  `wrote ${japanFeatures.length} Japan admin1 boundaries `
    + `(${totalPolygons} polygons, ${totalCoordinates} coordinates) to ${outputPath}`
);

function japanAdmin1Feature(feature) {
  const properties = feature.properties ?? {};
  const prefectureCode = prefectureCodeFromN03(properties.N03_007);
  const name = String(properties.N03_001 ?? "").trim();
  const englishName = englishPrefectureNames[prefectureCode] ?? name;
  const regionId = `JP-${prefectureCode}`;

  return {
    type: "Feature",
    properties: {
      id: `jp-${prefectureCode}`,
      region_id: regionId,
      level: "admin1",
      parent_id: "JP",
      countryCode: "jp",
      countryName: "日本",
      adminArea: name,
      cityName: name,
      nameZh: name,
      nameEn: englishName,
      cityKey: `jp|${name}|${name}`,
      aliases: aliasesForPrefecture(prefectureCode, name, englishName),
      source: "MLIT KSJ N03-2024",
      sourceYear: 2024,
      license: "CC-BY-4.0",
      mapCluster: "japan-admin1"
    },
    geometry: normalizeGeometry(feature.geometry)
  };
}

function prefectureCodeFromN03(value) {
  const raw = String(value ?? "").trim();
  if (!/^\d{5}$/.test(raw) || !raw.endsWith("000")) {
    throw new Error(`Invalid N03 prefecture code: ${raw}`);
  }
  return raw.slice(0, 2);
}

function aliasesForPrefecture(code, name, englishName) {
  const lowerEnglish = englishName.toLowerCase();
  const aliases = [
    `jp|${name}|${name}`,
    `jp|${lowerEnglish}|${lowerEnglish}`,
    `jp|${lowerEnglish}|${name}`
  ];

  if (code === "13") {
    aliases.push("jp|tokyo|tokyo", "jp|tokyo|東京都", "jp|东京|東京都", "jp|东京都|東京都");
  }

  return [...new Set(aliases)];
}

function normalizeGeometry(geometry) {
  if (!geometry) {
    throw new Error("Missing geometry");
  }

  const polygons = [];
  if (geometry.type === "Polygon") {
    polygons.push(roundPolygon(geometry.coordinates));
  } else if (geometry.type === "MultiPolygon") {
    polygons.push(...geometry.coordinates.map(roundPolygon));
  } else {
    throw new Error(`Unsupported geometry type: ${geometry.type}`);
  }

  const sortedPolygons = polygons
    .filter((polygon) => polygon.length > 0 && polygon[0].length >= 4)
    .sort((lhs, rhs) => polygonBBoxArea(rhs) - polygonBBoxArea(lhs));

  if (sortedPolygons.length === 0) {
    throw new Error("Geometry lost all polygons");
  }
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

function polygonCount(geometry) {
  return geometry.type === "Polygon" ? 1 : geometry.coordinates.length;
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

function validatePrefectureSet(features) {
  const actual = new Set(features.map((feature) => feature.properties.region_id));
  const expected = new Set(
    Array.from({ length: 47 }, (_, index) => `JP-${String(index + 1).padStart(2, "0")}`)
  );

  for (const regionId of expected) {
    if (!actual.has(regionId)) {
      throw new Error(`Missing prefecture ${regionId}`);
    }
  }
  if (actual.size !== expected.size) {
    throw new Error(`Expected 47 prefectures, got ${actual.size}`);
  }
}
