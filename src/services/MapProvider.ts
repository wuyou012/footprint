import type { CoordinateSystem } from './CoordinateService';

export enum MapProviderId {
  MapLibreWgs84 = 'maplibre_wgs84',
  AmapGcj02 = 'amap_gcj02',
  TencentGcj02 = 'tencent_gcj02',
  BaiduBd09 = 'baidu_bd09',
}

type ProviderStatus = 'implemented' | 'reserved';

export type BuildingStyleMode = '2d' | '3d';

export type MapProvider = {
  id: MapProviderId;
  displayName: string;
  coordinateSystem: CoordinateSystem;
  status: ProviderStatus;
  // Single source of truth for the map style URLs (W4). 2D = flat building
  // footprints (Positron, no fill-extrusion); 3D = building-3d extrusion
  // (Liberty). The screen selects by building mode — it must NOT hold its own
  // style URLs, or the active style diverges from this provider (砚砚 review #1).
  buildingStyles?: Record<BuildingStyleMode, string>;
};

export type ImplementedMapProvider = MapProvider & {
  status: 'implemented';
  buildingStyles: Record<BuildingStyleMode, string>;
};

export const MAP_PROVIDERS: Record<MapProviderId, MapProvider> = {
  [MapProviderId.MapLibreWgs84]: {
    id: MapProviderId.MapLibreWgs84,
    displayName: 'OpenFreeMap (2D Positron / 3D Liberty)',
    coordinateSystem: 'WGS84',
    status: 'implemented',
    buildingStyles: {
      '2d': 'https://tiles.openfreemap.org/styles/positron',
      '3d': 'https://tiles.openfreemap.org/styles/liberty',
    },
  },
  [MapProviderId.AmapGcj02]: {
    id: MapProviderId.AmapGcj02,
    displayName: 'Amap',
    coordinateSystem: 'GCJ02',
    status: 'reserved',
  },
  [MapProviderId.TencentGcj02]: {
    id: MapProviderId.TencentGcj02,
    displayName: 'Tencent Map',
    coordinateSystem: 'GCJ02',
    status: 'reserved',
  },
  [MapProviderId.BaiduBd09]: {
    id: MapProviderId.BaiduBd09,
    displayName: 'Baidu Map',
    coordinateSystem: 'BD09',
    status: 'reserved',
  },
};

export const ACTIVE_MAP_PROVIDER_ID = MapProviderId.MapLibreWgs84;

export function getMapProvider(
  providerId: MapProviderId = ACTIVE_MAP_PROVIDER_ID,
): ImplementedMapProvider {
  const provider = MAP_PROVIDERS[providerId];

  if (provider.status === 'implemented' && provider.buildingStyles) {
    return provider as ImplementedMapProvider;
  }

  throw new Error(`Map provider is reserved for a later phase: ${providerId}`);
}
