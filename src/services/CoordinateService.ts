export type CoordinateSystem = 'WGS84' | 'GCJ02' | 'BD09';

export type LngLat = [longitude: number, latitude: number];

export type CoordinateTransform = {
  coordinate: LngLat;
  from: CoordinateSystem;
  to: CoordinateSystem;
};

export function transformCoordinate({
  coordinate,
  from,
  to,
}: CoordinateTransform): LngLat {
  if (from === 'WGS84' && to === 'WGS84') {
    return [coordinate[0], coordinate[1]];
  }

  // GCJ-02 / BD-09 conversion must use a mature library such as gcoord.
  // Do not hand-roll datum conversion logic in this app.
  throw new Error(`Unsupported coordinate transform: ${from} -> ${to}`);
}

export function transformLineString(
  coordinates: readonly LngLat[],
  from: CoordinateSystem,
  to: CoordinateSystem,
): LngLat[] {
  return coordinates.map((coordinate) =>
    transformCoordinate({ coordinate, from, to }),
  );
}
