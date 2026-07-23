#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [, , inputPath, outputPath] = process.argv;

if (!inputPath || !outputPath) {
  console.error("Usage: node scripts/build-global-admin1-boundaries.mjs <Natural Earth Admin 1 zip-or-shp> <output GeoJSON>");
  process.exit(2);
}

const simplifyPercent = process.env.GLOBAL_ADMIN1_SIMPLIFY ?? "2%";
const minimumIslandArea = process.env.GLOBAL_ADMIN1_MIN_ISLAND_AREA;
const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "footprint-global-admin1-"));
const shapefilePath = prepareShapefile(inputPath, temporaryDirectory);
const dissolvedPath = path.join(temporaryDirectory, "natural-earth-admin1.geojson");

const mapshaperArguments = [
  "-y",
  "mapshaper",
  shapefilePath,
  "-filter",
  '!!iso_a2 && iso_a2 != "-99" && iso_a2 != "-1" && !!iso_3166_2 && !!name',
  "-dissolve",
  "iso_3166_2",
  "copy-fields=iso_a2,adm1_code,admin,name,name_en,name_zh,name_zht,name_local,type_en,postal"
];

if (minimumIslandArea) {
  mapshaperArguments.push("-filter-islands", `min-area=${minimumIslandArea}`);
}

mapshaperArguments.push(
  "-simplify",
  simplifyPercent,
  "keep-shapes",
  "-o",
  "format=geojson",
  dissolvedPath
);

const mapshaper = spawnSync(
  "npx",
  mapshaperArguments,
  { encoding: "utf8" }
);

if (mapshaper.status !== 0) {
  process.stderr.write(mapshaper.stdout);
  process.stderr.write(mapshaper.stderr);
  process.exit(mapshaper.status ?? 1);
}

const naturalEarth = JSON.parse(fs.readFileSync(dissolvedPath, "utf8"));
const existing = fs.existsSync(outputPath)
  ? JSON.parse(fs.readFileSync(outputPath, "utf8"))
  : { type: "FeatureCollection", features: [] };

const preservedFeatures = (existing.features ?? []).filter(shouldPreserveExistingFeature);
const preservedRegionIds = new Set(preservedFeatures.map(canonicalRegionId));
const globalAdmin1Features = (naturalEarth.features ?? [])
  .map(naturalEarthAdmin1Feature)
  .filter((feature) => !preservedRegionIds.has(canonicalRegionId(feature)))
  .sort((lhs, rhs) => canonicalRegionId(lhs).localeCompare(canonicalRegionId(rhs)));

validateUniqueRegionIds([...preservedFeatures, ...globalAdmin1Features]);
validateGlobalCoverage(globalAdmin1Features);
validatePreservedJapanFeatures(preservedFeatures);
validateRequiredRegionIds([...preservedFeatures, ...globalAdmin1Features]);

const collection = {
  type: "FeatureCollection",
  features: [
    ...preservedFeatures,
    ...globalAdmin1Features
  ]
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(collection)}\n`);

const admin1Features = collection.features.filter((feature) => feature.properties?.level === "admin1");
const countryCount = new Set(admin1Features.map((feature) => String(feature.properties?.countryCode ?? "").toUpperCase())).size;
console.log(
  `wrote ${collection.features.length} total boundaries `
    + `(${admin1Features.length} admin1 across ${countryCount} countries, `
    + `${preservedFeatures.length} preserved custom features) to ${outputPath}`
);

function prepareShapefile(sourcePath, workingDirectory) {
  if (sourcePath.toLowerCase().endsWith(".shp")) {
    return sourcePath;
  }
  if (!sourcePath.toLowerCase().endsWith(".zip")) {
    throw new Error(`Expected .zip or .shp input, got ${sourcePath}`);
  }

  const extractDirectory = path.join(workingDirectory, "input");
  fs.mkdirSync(extractDirectory, { recursive: true });
  const unzip = spawnSync("unzip", ["-oq", sourcePath, "-d", extractDirectory], { encoding: "utf8" });
  if (unzip.status !== 0) {
    process.stderr.write(unzip.stdout);
    process.stderr.write(unzip.stderr);
    process.exit(unzip.status ?? 1);
  }

  const shapefiles = findFiles(extractDirectory, (filePath) => filePath.toLowerCase().endsWith(".shp"));
  if (shapefiles.length !== 1) {
    throw new Error(`Expected one shapefile in ${sourcePath}, found ${shapefiles.length}`);
  }
  return shapefiles[0];
}

function findFiles(directory, predicate) {
  const results = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      results.push(...findFiles(entryPath, predicate));
    } else if (predicate(entryPath)) {
      results.push(entryPath);
    }
  }
  return results;
}

function shouldPreserveExistingFeature(feature) {
  const properties = feature.properties ?? {};
  const level = String(properties.level ?? "").toLowerCase();
  const countryCode = String(properties.countryCode ?? "").toLowerCase();
  return level !== "admin1" || countryCode === "jp";
}

function naturalEarthAdmin1Feature(feature) {
  const properties = feature.properties ?? {};
  const countryCode = clean(properties.iso_a2).toUpperCase();
  const regionId = clean(properties.iso_3166_2).replaceAll("_", "-").toUpperCase();
  const naturalEarthName = clean(properties.name);
  const nameEn = clean(properties.name_en) || naturalEarthName;
  const nameZh = clean(properties.name_zh) || clean(properties.name_zht) || nameEn;
  const localName = clean(properties.name_local);
  const countryName = clean(properties.admin) || countryCode;

  return {
    type: "Feature",
    properties: {
      id: regionId.toLowerCase(),
      region_id: regionId,
      level: "admin1",
      parent_id: countryCode,
      countryCode: countryCode.toLowerCase(),
      countryName,
      adminArea: nameZh,
      cityName: nameZh,
      nameZh,
      nameEn,
      cityKey: cityKey(countryCode, nameZh, nameZh),
      aliases: aliasesForRegion(countryCode, {
        regionId,
        nameZh,
        nameEn,
        naturalEarthName,
        localName,
        postal: clean(properties.postal)
      }),
      source: "Natural Earth Admin 1 States/Provinces",
      sourceVersion: "5.1.1",
      sourceYear: 2022,
      license: "Public Domain",
      boundaryPolicy: "de facto",
      mapCluster: "global-admin1"
    },
    geometry: normalizeGeometry(feature.geometry)
  };
}

function aliasesForRegion(countryCode, values) {
  const aliases = [
    cityKey(countryCode, values.nameZh, values.nameZh),
    cityKey(countryCode, values.nameEn, values.nameEn),
    cityKey(countryCode, values.nameEn, values.nameZh),
    cityKey(countryCode, values.naturalEarthName, values.naturalEarthName),
    cityKey(countryCode, values.localName, values.localName),
    cityKey(countryCode, values.regionId, values.nameEn),
    cityKey(countryCode, values.regionId, values.nameZh),
    cityKey(countryCode, values.postal, values.nameEn),
    cityKey(countryCode, values.postal, values.nameZh)
  ];
  return [...new Set(aliases.filter((alias) => !alias.includes("||")))];
}

function cityKey(countryCode, adminArea, cityName) {
  return [
    normalizeKey(countryCode),
    normalizeKey(adminArea),
    normalizeKey(cityName)
  ].join("|");
}

function clean(value) {
  return String(value ?? "").trim();
}

function normalizeKey(value) {
  return clean(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replaceAll("|", " ");
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
    Number(longitude.toFixed(5)),
    Number(latitude.toFixed(5))
  ]));
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

function canonicalRegionId(feature) {
  return clean(feature.properties?.region_id ?? feature.properties?.regionId ?? feature.properties?.id)
    .replaceAll("_", "-")
    .toUpperCase();
}

function validateUniqueRegionIds(features) {
  const seen = new Set();
  for (const feature of features) {
    const regionId = canonicalRegionId(feature);
    if (!regionId) {
      throw new Error("Feature missing region_id");
    }
    if (seen.has(regionId)) {
      throw new Error(`Duplicate region_id ${regionId}`);
    }
    seen.add(regionId);
  }
}

function validateGlobalCoverage(features) {
  const countries = new Set(features.map((feature) => String(feature.properties.countryCode).toUpperCase()));
  if (features.length < 4_000) {
    throw new Error(`Expected at least 4,000 Natural Earth admin1 features, got ${features.length}`);
  }
  if (countries.size < 180) {
    throw new Error(`Expected admin1 coverage for at least 180 countries, got ${countries.size}`);
  }
}

function validatePreservedJapanFeatures(features) {
  const japanAdmin1 = features.filter((feature) => {
    const properties = feature.properties ?? {};
    return properties.level === "admin1" && String(properties.countryCode ?? "").toLowerCase() === "jp";
  });
  const actual = new Set(japanAdmin1.map(canonicalRegionId));
  const expected = new Set(
    Array.from({ length: 47 }, (_, index) => `JP-${String(index + 1).padStart(2, "0")}`)
  );

  for (const regionId of expected) {
    if (!actual.has(regionId)) {
      throw new Error(`Missing preserved prefecture ${regionId}`);
    }
  }
  if (actual.size !== expected.size) {
    throw new Error(`Expected 47 preserved Japan prefectures, got ${actual.size}`);
  }
}

function validateRequiredRegionIds(features) {
  const regionIds = new Set(features.map(canonicalRegionId));
  for (const regionId of ["US-CA", "CA-ON", "AU-NSW", "BR-SP", "CN-GD", "IN-MH", "JP-13", "US-CA-SF"]) {
    if (!regionIds.has(regionId)) {
      throw new Error(`Missing required region ${regionId}`);
    }
  }
}
