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

export function trackPointsToGpx(points: readonly TrackPoint[]): string {
  const validPoints = points.filter(isValidTrackPoint);
  const createdAt = toIsoTime(Date.now());
  const name = escapeXml(`footprint ${createdAt}`);
  const trackPoints = validPoints
    .map((point) => {
      const lat = point.latitude.toFixed(7);
      const lon = point.longitude.toFixed(7);
      const time = toIsoTime(point.timestamp);
      return `      <trkpt lat="${lat}" lon="${lon}">\n        <time>${time}</time>\n      </trkpt>`;
    })
    .join('\n');

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<gpx',
    '  version="1.1"',
    '  creator="footprint"',
    '  xmlns="http://www.topografix.com/GPX/1/1"',
    '  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"',
    '  xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd"',
    '>',
    '  <metadata>',
    `    <name>${name}</name>`,
    `    <time>${createdAt}</time>`,
    '  </metadata>',
    '  <trk>',
    `    <name>${name}</name>`,
    '    <trkseg>',
    trackPoints,
    '    </trkseg>',
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
