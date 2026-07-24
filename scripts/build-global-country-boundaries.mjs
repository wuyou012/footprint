#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [, , admin0InputPath, policyAdmin1CatalogPath, outputPath] = process.argv;

if (!admin0InputPath || !policyAdmin1CatalogPath || !outputPath) {
  console.error(
    "Usage: node scripts/build-global-country-boundaries.mjs "
      + "<Natural Earth Admin 0 zip-or-shp> <policy admin1 GeoJSON> <output GeoJSON>"
  );
  process.exit(2);
}

const naturalEarthSourceVersion = "5.1.1";
const naturalEarthSourceYear = 2022;
const mapshaperPackage = "mapshaper@0.7.47";
const simplifyPercent = process.env.GLOBAL_COUNTRY_SIMPLIFY ?? "2%";
const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "footprint-global-country-"));
const { shapefilePath, sourceVersion } = prepareShapefile(admin0InputPath, temporaryDirectory);
validateNaturalEarthVersion(sourceVersion);

const policyAdmin1Catalog = JSON.parse(fs.readFileSync(policyAdmin1CatalogPath, "utf8"));
const derivedCountries = deriveCountriesFromPolicyAdmin1(policyAdmin1Catalog.features ?? []);
const derivedCountryIds = new Set(derivedCountries.map(canonicalCountryId));
const naturalEarthAdmin0 = loadNaturalEarthAdmin0(shapefilePath);
const supplementalAdmin0Countries = (naturalEarthAdmin0.features ?? [])
  .map(naturalEarthAdmin0Feature)
  .flatMap((feature) => feature ? [feature] : [])
  .filter((feature) => !derivedCountryIds.has(canonicalCountryId(feature)));

const countries = [
  ...derivedCountries,
  ...supplementalAdmin0Countries
].sort((lhs, rhs) => canonicalCountryId(lhs).localeCompare(canonicalCountryId(rhs)));

validateUniqueCountryIds(countries);
validateCountryCoverage(countries);
validateChinaPolicy(countries);

const collection = {
  type: "FeatureCollection",
  features: countries
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(collection)}\n`);

const derivedCount = derivedCountries.length;
const supplementalCount = supplementalAdmin0Countries.length;
console.log(
  `wrote ${countries.length} country boundaries `
    + `(${derivedCount} policy-admin1 dissolved, ${supplementalCount} admin0 supplemental) to ${outputPath}`
);

function prepareShapefile(sourcePath, workingDirectory) {
  if (sourcePath.toLowerCase().endsWith(".shp")) {
    return {
      shapefilePath: sourcePath,
      sourceVersion: readAdjacentVersionFile(sourcePath)
    };
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
  return {
    shapefilePath: shapefiles[0],
    sourceVersion: readVersionFile(extractDirectory)
  };
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

function readAdjacentVersionFile(shapefilePath) {
  return readVersionFile(path.dirname(shapefilePath));
}

function readVersionFile(directory) {
  const versionFiles = findFiles(directory, (filePath) => filePath.endsWith(".VERSION.txt"));
  if (versionFiles.length !== 1) {
    throw new Error(`Expected one Natural Earth VERSION.txt file near input, found ${versionFiles.length}`);
  }
  return fs.readFileSync(versionFiles[0], "utf8").trim();
}

function validateNaturalEarthVersion(actualVersion) {
  if (actualVersion !== naturalEarthSourceVersion) {
    throw new Error(
      `Expected Natural Earth Admin 0 version ${naturalEarthSourceVersion}, got ${actualVersion}`
    );
  }
}

function loadNaturalEarthAdmin0(shapefilePath) {
  const admin0Path = path.join(temporaryDirectory, "natural-earth-admin0.geojson");
  const mapshaper = spawnSync(
    "npx",
    [
      "-y",
      mapshaperPackage,
      shapefilePath,
      "-filter",
      "!!ADM0_A3 && !!NAME",
      "-simplify",
      simplifyPercent,
      "keep-shapes",
      "-o",
      "format=geojson",
      admin0Path
    ],
    { encoding: "utf8" }
  );
  if (mapshaper.status !== 0) {
    process.stderr.write(mapshaper.stdout);
    process.stderr.write(mapshaper.stderr);
    process.exit(mapshaper.status ?? 1);
  }
  return JSON.parse(fs.readFileSync(admin0Path, "utf8"));
}

function deriveCountriesFromPolicyAdmin1(features) {
  const admin1Features = features.filter((feature) => {
    const properties = feature.properties ?? {};
    return String(properties.level ?? "").toLowerCase() === "admin1"
      && clean(properties.countryCode);
  });

  const groups = new Map();
  const dissolveInputFeatures = [];
  for (const feature of admin1Features) {
    const countryId = clean(feature.properties?.countryCode).toUpperCase();
    const current = groups.get(countryId) ?? {
      countryId,
      countryName: clean(feature.properties?.countryName) || countryId,
      componentRegionIds: [],
      boundaryPolicies: new Set()
    };
    current.componentRegionIds.push(canonicalRegionId(feature));
    const boundaryPolicy = clean(feature.properties?.boundaryPolicy);
    if (boundaryPolicy) {
      current.boundaryPolicies.add(boundaryPolicy);
    }
    groups.set(countryId, current);

    for (const [polygonIndex, coordinates] of geometryToPolygons(feature.geometry).entries()) {
      dissolveInputFeatures.push({
        type: "Feature",
        properties: {
          country_id: countryId,
          source_region_id: canonicalRegionId(feature),
          source_polygon_index: polygonIndex
        },
        geometry: {
          type: "Polygon",
          coordinates
        }
      });
    }
  }

  if (dissolveInputFeatures.length === 0) {
    throw new Error("Policy admin1 catalog has no drawable admin1 geometry");
  }

  const inputPath = path.join(temporaryDirectory, "policy-admin1-country-input.geojson");
  const outputPath = path.join(temporaryDirectory, "policy-admin1-country-dissolved.geojson");
  fs.writeFileSync(inputPath, JSON.stringify({
    type: "FeatureCollection",
    features: dissolveInputFeatures
  }));

  const dissolve = spawnSync(
    "npx",
    [
      "-y",
      mapshaperPackage,
      inputPath,
      "-dissolve",
      "country_id",
      "-o",
      "format=geojson",
      outputPath
    ],
    { encoding: "utf8" }
  );
  if (dissolve.status !== 0) {
    process.stderr.write(dissolve.stdout);
    process.stderr.write(dissolve.stderr);
    process.exit(dissolve.status ?? 1);
  }

  const dissolved = JSON.parse(fs.readFileSync(outputPath, "utf8"));
  return (dissolved.features ?? []).map((feature) => {
    const countryId = clean(feature.properties?.country_id).toUpperCase();
    const group = groups.get(countryId);
    if (!group) {
      throw new Error(`Dissolved country missing group metadata: ${countryId}`);
    }
    const componentRegionIds = [...new Set(group.componentRegionIds)].sort();
    const boundaryPolicy = countryId === "CN" || group.boundaryPolicies.has("china-policy-override")
      ? "china-policy-override"
      : "de facto";

    return {
      type: "Feature",
      properties: {
        id: countryId.toLowerCase(),
        country_id: countryId,
        level: "country",
        countryCode: countryId.toLowerCase(),
        countryName: group.countryName,
        nameZh: group.countryName,
        nameEn: group.countryName,
        source: "Natural Earth Admin 1 States/Provinces dissolved to countries + Footprint policy overrides",
        sourceVersion: naturalEarthSourceVersion,
        sourceYear: naturalEarthSourceYear,
        license: "Public Domain",
        boundaryPolicy,
        mapCluster: "global-country",
        sourceSimplification: simplifyPercent,
        sourceMapshaperPackage: mapshaperPackage,
        sourceComponentCountryIds: [countryId],
        sourceComponentRegionIds: componentRegionIds
      },
      geometry: normalizeGeometry(feature.geometry)
    };
  });
}

function naturalEarthAdmin0Feature(feature) {
  const properties = feature.properties ?? {};
  if (shouldSkipChinaViewpointSupplement(properties)) {
    return null;
  }

  const countryId = countryIdForAdmin0(properties);
  if (!countryId) {
    return null;
  }

  const countryName = clean(properties.ADMIN)
    || clean(properties.NAME_EN)
    || clean(properties.NAME)
    || countryId;
  return {
    type: "Feature",
    properties: {
      id: countryId.toLowerCase(),
      country_id: countryId,
      level: "country",
      countryCode: countryId.toLowerCase(),
      countryName,
      nameZh: clean(properties.NAME_ZH) || countryName,
      nameEn: clean(properties.NAME_EN) || countryName,
      source: "Natural Earth Admin 0 Countries",
      sourceVersion: naturalEarthSourceVersion,
      sourceYear: naturalEarthSourceYear,
      license: "Public Domain",
      boundaryPolicy: "de facto",
      mapCluster: "global-country",
      sourceSimplification: simplifyPercent,
      sourceMapshaperPackage: mapshaperPackage,
      sourceComponentCountryIds: [clean(properties.ADM0_A3) || countryId],
      sourceComponentRegionIds: []
    },
    geometry: normalizeGeometry(feature.geometry)
  };
}

function shouldSkipChinaViewpointSupplement(properties) {
  const adm0 = clean(properties.ADM0_A3).toUpperCase();
  const chinaViewpointAdm0 = clean(properties.ADM0_A3_CN).toUpperCase();
  if (adm0 === "TWN") {
    return true;
  }
  return chinaViewpointAdm0 === "CHN" && adm0 !== "CHN";
}

function countryIdForAdmin0(properties) {
  const isoA2 = clean(properties.ISO_A2).toUpperCase();
  if (/^[A-Z]{2}$/.test(isoA2)) {
    return isoA2;
  }

  const adm0 = clean(properties.ADM0_A3).toUpperCase();
  if (/^[A-Z0-9]{3}$/.test(adm0)) {
    return adm0;
  }
  return "";
}

function geometryToPolygons(geometry) {
  if (!geometry) {
    throw new Error("Missing geometry");
  }
  if (geometry.type === "Polygon") {
    return [geometry.coordinates];
  }
  if (geometry.type === "MultiPolygon") {
    return geometry.coordinates;
  }
  throw new Error(`Unsupported geometry type: ${geometry.type}`);
}

function normalizeGeometry(geometry) {
  const polygons = geometryToPolygons(geometry)
    .map(roundPolygon)
    .filter((polygon) => polygon.length > 0 && polygon[0].length >= 4)
    .sort((lhs, rhs) => polygonBBoxArea(rhs) - polygonBBoxArea(lhs));

  if (polygons.length === 0) {
    throw new Error("Geometry lost all polygons");
  }
  if (polygons.length === 1) {
    return { type: "Polygon", coordinates: polygons[0] };
  }
  return { type: "MultiPolygon", coordinates: polygons };
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

function canonicalCountryId(feature) {
  return clean(feature.properties?.country_id ?? feature.properties?.countryId ?? feature.properties?.id)
    .replaceAll("_", "-")
    .toUpperCase();
}

function canonicalRegionId(feature) {
  return clean(feature.properties?.region_id ?? feature.properties?.regionId ?? feature.properties?.id)
    .replaceAll("_", "-")
    .toUpperCase();
}

function clean(value) {
  return String(value ?? "").trim();
}

function validateUniqueCountryIds(features) {
  const seen = new Set();
  for (const feature of features) {
    const countryId = canonicalCountryId(feature);
    if (!countryId) {
      throw new Error("Country boundary missing country_id");
    }
    if (seen.has(countryId)) {
      throw new Error(`Duplicate country_id ${countryId}`);
    }
    seen.add(countryId);
  }
}

function validateCountryCoverage(features) {
  if (features.length < 200) {
    throw new Error(`Expected at least 200 country boundaries, got ${features.length}`);
  }
  const ids = new Set(features.map(canonicalCountryId));
  for (const countryId of ["CN", "IN", "US", "JP", "GB", "AU", "BR", "CA"]) {
    if (!ids.has(countryId)) {
      throw new Error(`Missing required country boundary ${countryId}`);
    }
  }
}

function validateChinaPolicy(features) {
  const countryIds = new Set(features.map(canonicalCountryId));
  if (!countryIds.has("CN")) {
    throw new Error("Missing China country boundary");
  }
  for (const invalidCountryId of ["TW", "TWN", "CN-TW"]) {
    if (countryIds.has(invalidCountryId)) {
      throw new Error(`Taiwan must not render as separate country boundary: ${invalidCountryId}`);
    }
  }

  const china = features.find((feature) => canonicalCountryId(feature) === "CN");
  const chinaRegions = china?.properties?.sourceComponentRegionIds ?? [];
  if (!Array.isArray(chinaRegions) || !chinaRegions.includes("CN-TW")) {
    throw new Error("China country boundary must include CN-TW source region");
  }
  if (!Array.isArray(chinaRegions) || !chinaRegions.includes("CN-XZ")) {
    throw new Error("China country boundary must include CN-XZ source region");
  }
  if (String(china?.properties?.boundaryPolicy ?? "") !== "china-policy-override") {
    throw new Error("China country boundary must carry china-policy-override metadata");
  }

  const india = features.find((feature) => canonicalCountryId(feature) === "IN");
  const indiaRegions = india?.properties?.sourceComponentRegionIds ?? [];
  if (Array.isArray(indiaRegions) && indiaRegions.includes("IN-AR")) {
    throw new Error("India country boundary must not keep IN-AR after China policy override");
  }
}
