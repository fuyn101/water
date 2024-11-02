<template>
  <div>
    <div>
      对地图的操作： <button>放大</button>
      <button>缩小</button>
      <button>拖动</button>
    </div>
    前端增加:
    <div><button>投点</button> <button>新建物联网接口流程(仅做页面)</button></div>
  </div>

  <div id="map-container">
    <div id="map" class="map"></div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import 'ol/ol.css';
import Map from 'ol/Map';
import View from 'ol/View';
import VectorLayer from 'ol/layer/Vector';
import VectorSource from 'ol/source/Vector';
import GeoJSON from 'ol/format/GeoJSON';
import Feature from 'ol/Feature';
import LineString from 'ol/geom/LineString';
import { fromLonLat } from 'ol/proj';
import { Stroke, Style } from 'ol/style';

const json = ref('');

// Fetch GeoJSON data from server
async function fetchGeoJSON() {
  try {
    const response = await fetch('./map/焦作市.json');
    const data = await response.json();
    return data;
  } catch (error) {
    console.error('Error fetching GeoJSON data:', error);
  }
}

// Fetch line data from API and create features
async function fetchJsonLine() {
  try {
    const response = await fetch('http://127.0.0.1:8000/api/lines');
    const Linedata = await response.json();
    return Linedata.map(
      (line) =>
        new Feature({
          geometry: new LineString(line.geometry.coordinates.map((coord) => fromLonLat(coord))),
          properties: {
            color: line.properties.color,
            name: line.properties.name,
          },
        }),
    );
  } catch (error) {
    console.error('Error fetching line data:', error);
  }
}

onMounted(async () => {
  // Load GeoJSON data
  const geojsonData = await fetchGeoJSON();

  // Create GeoJSON layer
  const geojsonLayer = new VectorLayer({
    source: new VectorSource({
      features: new GeoJSON().readFeatures(geojsonData, { featureProjection: 'EPSG:3857' }),
    }),
    style: new Style({
      stroke: new Stroke({
        color: 'red',
        width: 2,
      }),
    }),
  });

  // Load line features from JSON data
  const lineFeatures = await fetchJsonLine();
  const lineLayer = new VectorLayer({
    source: new VectorSource({
      features: lineFeatures,
    }),
    style: function (feature) {
      return new Style({
        stroke: new Stroke({
          color: feature.get('color') || 'black',
          width: 3,
        }),
      });
    },
  });

  // Initialize map
  new Map({
    target: 'map',
    layers: [geojsonLayer, lineLayer],
    view: new View({
      center: fromLonLat([113.2418, 35.2159]),
      zoom: 6,
      extent: [...fromLonLat([110.35, 31.38]), ...fromLonLat([116.65, 36.22])],
    }),
  });
});
</script>

<style>
#map-container {
  display: flex;
  flex-direction: column;
  align-items: center;
}

#map {
  width: 600px;
  height: 400px;
  margin-bottom: 20px;
}

.logo {
  margin-top: 20px;
}
</style>
