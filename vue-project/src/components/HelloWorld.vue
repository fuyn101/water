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
      center: [0, 0],
      zoom: 2,
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
  width: 600px; /* Adjust width as needed */
  height: 400px; /* Adjust height as needed */
  margin-bottom: 20px;
}

.logo {
  margin-top: 20px;
}
</style>
