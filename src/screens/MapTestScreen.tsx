import {
  Camera,
  GeoJSONSource,
  Layer,
  Map,
} from '@maplibre/maplibre-react-native';
import type { Feature, LineString } from 'geojson';
import { StyleSheet, View } from 'react-native';

import {
  transformLineString,
  type LngLat,
} from '../services/CoordinateService';
import { getMapProvider } from '../services/MapProvider';

const mapProvider = getMapProvider();

const DEMO_ROUTE_WGS84: LngLat[] = [
  [-122.4194, 37.7749],
  [-122.4169, 37.7773],
  [-122.4143, 37.7794],
  [-122.4108, 37.7812],
];

const demoRoute: Feature<LineString> = {
  type: 'Feature',
  properties: {
    id: 'p0-a-demo-route',
    provider: mapProvider.id,
  },
  geometry: {
    type: 'LineString',
    coordinates: transformLineString(DEMO_ROUTE_WGS84, 'WGS84', 'WGS84'),
  },
};

export function MapTestScreen() {
  return (
    <View style={styles.container}>
      <Map style={styles.map} mapStyle={mapProvider.mapStyle}>
        <Camera center={DEMO_ROUTE_WGS84[1]} zoom={14} />
        <GeoJSONSource id="demo-route-source" data={demoRoute}>
          <Layer
            id="demo-route-line"
            source="demo-route-source"
            type="line"
            layout={{
              'line-cap': 'round',
              'line-join': 'round',
            }}
            paint={{
              'line-color': '#0F766E',
              'line-opacity': 0.9,
              'line-width': 6,
            }}
          />
        </GeoJSONSource>
      </Map>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#F8FAFC',
  },
  map: {
    flex: 1,
  },
});
