<template>
  <div id="map-container">
    <!-- Map container -->
    <div id="map" class="map"></div>

    <img alt="Vue logo" class="logo" src="../assets/logo.svg" width="125" height="125" />

    <div>
      <h1>{{ title }}</h1>
      <p>{{ json }}</p>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import 'ol/ol.css'; // Import OpenLayers default styling
import Map from 'ol/Map';
import View from 'ol/View';
import TileLayer from 'ol/layer/Tile';
import OSM from 'ol/source/OSM';
import { fromLonLat } from 'ol/proj'; // Import projection utility

const title = ref('Hello World');
const json = ref('');


async function fetchData() {
  try {
    const response = await fetch("http://localhost:8000/data");
    const data = await response.json();
    json.value = data;
    console.log(json.value);
  } catch (error) {
    console.error('Error fetching data:', error);
  }
}


const initialCenter = [113.2418, 35.2159]; // Jiaozuo, Henan Province in EPSG:4326 (lon, lat)
const henanExtent = [110.35, 31.38, 116.65, 36.22]; // (minLon, minLat, maxLon, maxLat)
const transformedExtent = [
  ...fromLonLat([henanExtent[0], henanExtent[1]]), // bottom-left
  ...fromLonLat([henanExtent[2], henanExtent[3]]), // top-right
];
onMounted(() => {
  fetchData();

  // Initialize OpenLayers map
  const map = new Map({
    target: 'map',
    layers: [
      new TileLayer({
        source: new OSM(), // Use OpenStreetMap tiles
      }),
    ],
    view: new View({
      center: fromLonLat(initialCenter), // Transform initialCenter to EPSG:3857
      zoom: 8, // Set a more appropriate zoom level
      extent: transformedExtent,
    }),
  });
});

</script>

<style>
/* Style for the map container */
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
