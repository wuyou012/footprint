#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const [, , inputPath, outputPath] = process.argv;

if (!inputPath || !outputPath) {
  console.error("Usage: node scripts/build-tokyo-boundaries.mjs <N03 Tokyo GeoJSON> <output GeoJSON>");
  process.exit(2);
}

const tolerance = Number(process.env.TOKYO_BOUNDARY_TOLERANCE ?? "0.00035");
const minimumPolygonBBoxArea = Number(process.env.TOKYO_MIN_POLYGON_BBOX_AREA ?? "0.000001");
const n03 = JSON.parse(fs.readFileSync(inputPath, "utf8"));
const existing = fs.existsSync(outputPath)
  ? JSON.parse(fs.readFileSync(outputPath, "utf8"))
  : { type: "FeatureCollection", features: [] };

const preservedFeatures = (existing.features ?? []).filter((feature) => {
  const regionId = String(feature.properties?.region_id ?? feature.properties?.regionId ?? feature.properties?.id ?? "");
  return !regionId.startsWith("JP-13");
});

const groups = new Map();
for (const feature of n03.features ?? []) {
  const properties = feature.properties ?? {};
  const code = String(properties.N03_007 ?? "");
  if (!/^13\d{3}$/.test(code) || code === "13000") {
    continue;
  }

  const cityName = properties.N03_004;
  if (!cityName) {
    continue;
  }

  const group = groups.get(code) ?? {
    code,
    cityName,
    districtName: properties.N03_003,
    polygons: []
  };
  group.polygons.push(...geometryPolygons(feature.geometry));
  groups.set(code, group);
}

const tokyoFeatures = [...groups.values()]
  .sort((lhs, rhs) => lhs.code.localeCompare(rhs.code))
  .map((group) => tokyoFeature(group));

const collection = {
  type: "FeatureCollection",
  features: [...preservedFeatures, ...tokyoFeatures]
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${JSON.stringify(collection)}\n`);

const specialWardCount = tokyoFeatures.filter((feature) => /^JP-131\d\d$/.test(feature.properties.region_id)).length;
console.log(`wrote ${tokyoFeatures.length} Tokyo municipality features (${specialWardCount} special wards) to ${outputPath}`);

function tokyoFeature(group) {
  const retainedSourcePolygons = retainDisplayPolygons(group.polygons);
  const polygons = retainedSourcePolygons
    .map((polygon) => polygon.map((ring) => simplifyRing(ring, tolerance)).filter((ring) => ring.length >= 4))
    .filter((polygon) => polygon.length > 0 && polygon[0].length >= 4)
    .sort((lhs, rhs) => polygonBBoxArea(rhs) - polygonBBoxArea(lhs));

  const regionId = `JP-${group.code}`;
  const aliases = [
    `jp|東京都|${group.cityName}`,
    `jp|东京|${group.cityName}`,
    `jp|tokyo|${group.cityName}`
  ];
  if (group.code === "13104") {
    aliases.push("jp|tokyo|shinjuku");
  }

  return {
    type: "Feature",
    properties: {
      id: `jp-${group.code}`,
      region_id: regionId,
      level: "city",
      parent_id: "JP-13",
      countryCode: "jp",
      countryName: "日本",
      adminArea: "東京都",
      cityName: group.cityName,
      nameZh: group.cityName,
      nameEn: group.cityName,
      cityKey: `jp|東京都|${group.cityName}`,
      aliases: [...new Set(aliases)],
      source: "MLIT KSJ N03-2024",
      sourceYear: 2024,
      license: "CC-BY-4.0",
      mapCluster: isTokyoIslandCode(group.code) ? "tokyo-islands" : "tokyo-mainland"
    },
    geometry: polygons.length === 1
      ? { type: "Polygon", coordinates: polygons[0] }
      : { type: "MultiPolygon", coordinates: polygons }
  };
}

function geometryPolygons(geometry) {
  if (!geometry) {
    return [];
  }
  if (geometry.type === "Polygon") {
    return [geometry.coordinates];
  }
  if (geometry.type === "MultiPolygon") {
    return geometry.coordinates;
  }
  return [];
}

function simplifyRing(ring, epsilon) {
  const openRing = withoutClosingPoint(removeConsecutiveDuplicates(ring));
  if (openRing.length < 3) {
    return closeRing(roundRing(openRing));
  }

  const simplified = douglasPeucker([...openRing, openRing[0]], epsilon);
  const simplifiedOpenRing = withoutClosingPoint(removeConsecutiveDuplicates(simplified));
  const finalOpenRing = simplifiedOpenRing.length >= 3 ? simplifiedOpenRing : openRing;
  return closeRing(roundRing(finalOpenRing));
}

function douglasPeucker(points, epsilon) {
  if (points.length <= 2) {
    return points;
  }

  let maxDistance = 0;
  let splitIndex = 0;
  const start = points[0];
  const end = points[points.length - 1];

  for (let index = 1; index < points.length - 1; index += 1) {
    const distance = perpendicularDistance(points[index], start, end);
    if (distance > maxDistance) {
      maxDistance = distance;
      splitIndex = index;
    }
  }

  if (maxDistance <= epsilon) {
    return [start, end];
  }

  const left = douglasPeucker(points.slice(0, splitIndex + 1), epsilon);
  const right = douglasPeucker(points.slice(splitIndex), epsilon);
  return [...left.slice(0, -1), ...right];
}

function perpendicularDistance(point, start, end) {
  const [x, y] = point;
  const [x1, y1] = start;
  const [x2, y2] = end;
  const dx = x2 - x1;
  const dy = y2 - y1;
  if (dx === 0 && dy === 0) {
    return Math.hypot(x - x1, y - y1);
  }
  return Math.abs(dy * x - dx * y + x2 * y1 - y2 * x1) / Math.hypot(dx, dy);
}

function removeConsecutiveDuplicates(ring) {
  const result = [];
  for (const point of ring) {
    if (!result.length || !samePoint(result[result.length - 1], point)) {
      result.push(point);
    }
  }
  return result;
}

function withoutClosingPoint(ring) {
  if (ring.length > 1 && samePoint(ring[0], ring[ring.length - 1])) {
    return ring.slice(0, -1);
  }
  return ring;
}

function closeRing(ring) {
  if (!ring.length) {
    return ring;
  }
  return samePoint(ring[0], ring[ring.length - 1]) ? ring : [...ring, ring[0]];
}

function roundRing(ring) {
  return ring.map(([longitude, latitude]) => [
    Number(longitude.toFixed(6)),
    Number(latitude.toFixed(6))
  ]);
}

function samePoint(lhs, rhs) {
  return lhs?.[0] === rhs?.[0] && lhs?.[1] === rhs?.[1];
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

function retainDisplayPolygons(polygons) {
  const withArea = polygons
    .map((polygon) => ({ polygon, area: polygonBBoxArea(polygon) }))
    .sort((lhs, rhs) => rhs.area - lhs.area);
  const retained = withArea
    .filter((entry) => entry.area >= minimumPolygonBBoxArea)
    .map((entry) => entry.polygon);
  return retained.length > 0 ? retained : withArea.slice(0, 1).map((entry) => entry.polygon);
}

function isTokyoIslandCode(code) {
  return new Set([
    "13361",
    "13362",
    "13363",
    "13364",
    "13381",
    "13382",
    "13401",
    "13402",
    "13421"
  ]).has(code);
}
