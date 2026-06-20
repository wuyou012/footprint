import type { CoordinateSystem } from './CoordinateService';

export enum MapProviderId {
  MapLibreWgs84 = 'maplibre_wgs84',
  AmapGcj02 = 'amap_gcj02',
  TencentGcj02 = 'tencent_gcj02',
  BaiduBd09 = 'baidu_bd09',
}

type ProviderStatus = 'implemented' | 'reserved';

export type MapProvider = {
  id: MapProviderId;
  displayName: string;
  coordinateSystem: CoordinateSystem;
  status: ProviderStatus;
  mapStyle?: string;
};

export type ImplementedMapProvider = MapProvider & {
  status: 'implemented';
  mapStyle: string;
};

export const MAP_PROVIDERS: Record<MapProviderId, MapProvider> = {
  [MapProviderId.MapLibreWgs84]: {
    id: MapProviderId.MapLibreWgs84,
    displayName: 'MapLibre Demo Tiles',
    coordinateSystem: 'WGS84',
    status: 'implemented',
    mapStyle: 'https://demotiles.maplibre.org/style.json',
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

  if (provider.status === 'implemented' && provider.mapStyle) {
    return provider as ImplementedMapProvider;
  }

  throw new Error(`Map provider is reserved for a later phase: ${providerId}`);
}
