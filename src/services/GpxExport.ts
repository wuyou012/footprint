import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';

import type { TrackPoint } from './TrackDataSource';

const GPX_MIME_TYPE = 'application/gpx+xml';
const GPX_UTI = 'com.topografix.gpx';

function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function isValidTrackPoint(point: TrackPoint): boolean {
  return (
    Number.isFinite(point.longitude) &&
    Number.isFinite(point.latitude) &&
    Math.abs(point.longitude) <= 180 &&
    Math.abs(point.latitude) <= 90 &&
    Number.isFinite(point.timestamp)
  );
}

function toIsoTime(timestamp: number): string {
  return new Date(timestamp).toISOString();
}

function createGpxFileName(points: readonly TrackPoint[]): string {
  const firstTimestamp = points[0]?.timestamp ?? Date.now();
  const stamp = toIsoTime(firstTimestamp).replace(/[:.]/g, '-');
  return `footprint-${stamp}.gpx`;
}

function getSegmentKey(point: TrackPoint): string {
  return point.segmentId !== null && point.segmentId !== undefined
    ? `segment-${point.segmentId}`
    : 'legacy';
}

function groupTrackSegments(points: readonly TrackPoint[]): TrackPoint[][] {
  const segments: TrackPoint[][] = [];
  const segmentIndex = new Map<string, TrackPoint[]>();

  points.forEach((point) => {
    const key = getSegmentKey(point);
    let segment = segmentIndex.get(key);
    if (!segment) {
      segment = [];
      segmentIndex.set(key, segment);
      segments.push(segment);
    }
    segment.push(point);
  });

  return segments;
}

function pointExtensions(point: TrackPoint): string {
  const fields: string[] = [];
  if (point.sessionId !== null && point.sessionId !== undefined) {
    fields.push(`          <footprint:sessionId>${point.sessionId}</footprint:sessionId>`);
  }
  if (point.segmentId !== null && point.segmentId !== undefined) {
    fields.push(`          <footprint:segmentId>${point.segmentId}</footprint:segmentId>`);
  }
  if (point.profile) {
    fields.push(`          <footprint:profile>${escapeXml(point.profile)}</footprint:profile>`);
  }
  if (point.source) {
    fields.push(`          <footprint:source>${escapeXml(point.source)}</footprint:source>`);
  }
  if (point.localDayKey) {
    fields.push(`          <footprint:localDayKey>${escapeXml(point.localDayKey)}</footprint:localDayKey>`);
  }
  if (point.accuracy !== null && point.accuracy !== undefined) {
    fields.push(`          <footprint:accuracyMeters>${point.accuracy.toFixed(2)}</footprint:accuracyMeters>`);
  }

  return fields.length > 0
    ? `\n        <extensions>\n${fields.join('\n')}\n        </extensions>`
    : '';
}

function trackPointToGpx(point: TrackPoint): string {
  const lat = point.latitude.toFixed(7);
  const lon = point.longitude.toFixed(7);
  const time = toIsoTime(point.timestamp);
  const ele =
    typeof point.altitude === 'number' && Number.isFinite(point.altitude)
      ? `\n        <ele>${point.altitude.toFixed(2)}</ele>`
      : '';
  const extensions = pointExtensions(point);
  return `      <trkpt lat="${lat}" lon="${lon}">${ele}\n        <time>${time}</time>${extensions}\n      </trkpt>`;
}

export function trackPointsToGpx(points: readonly TrackPoint[]): string {
  const validPoints = points.filter(isValidTrackPoint);
  const createdAt = toIsoTime(Date.now());
  const name = escapeXml(`footprint ${createdAt}`);
  const trackSegments = groupTrackSegments(validPoints)
    .map((segment) =>
      [
        '    <trkseg>',
        segment.map(trackPointToGpx).join('\n'),
        '    </trkseg>',
      ].join('\n'),
    )
    .join('\n');

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<gpx',
    '  version="1.1"',
    '  creator="footprint"',
    '  xmlns="http://www.topografix.com/GPX/1/1"',
    '  xmlns:footprint="https://github.com/wuyou012/footprint/gpx/1"',
    '  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"',
    '  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd"',
    '>',
    '  <metadata>',
    `    <name>${name}</name>`,
    `    <time>${createdAt}</time>`,
    '  </metadata>',
    '  <trk>',
    `    <name>${name}</name>`,
    trackSegments,
    '  </trk>',
    '</gpx>',
    '',
  ].join('\n');
}

export async function exportTrackAsGpx(
  points: readonly TrackPoint[],
): Promise<void> {
  const validPoints = points.filter(isValidTrackPoint);
  if (validPoints.length === 0) {
    throw new Error('No valid track points to export');
  }

  if (!(await Sharing.isAvailableAsync())) {
    throw new Error('Sharing is not available on this device');
  }

  const file = new File(Paths.document, createGpxFileName(validPoints));
  file.create({ intermediates: true, overwrite: true });
  file.write(trackPointsToGpx(validPoints), { encoding: 'utf8' });

  await Sharing.shareAsync(file.uri, {
    mimeType: GPX_MIME_TYPE,
    UTI: GPX_UTI,
    dialogTitle: 'Export GPX',
  });
}
