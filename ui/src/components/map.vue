<template>
  <div>
    <n-button type="primary" @click="addPoint">投点</n-button>
    <n-button type="primary" @click="createIoTProcess">新建物联网接口流程(仅做页面)</n-button>
  </div>

  <div id="map" class="map"></div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import 'ol/ol.css'
import Map from 'ol/Map'
import View from 'ol/View'
import VectorLayer from 'ol/layer/Vector'
import VectorSource from 'ol/source/Vector'
import GeoJSON from 'ol/format/GeoJSON'
import Feature from 'ol/Feature'
import LineString from 'ol/geom/LineString'
import { fromLonLat } from 'ol/proj'
import { Stroke, Style } from 'ol/style'
import OSM from 'ol/source/OSM'
import TileLayer from 'ol/layer/Tile'

const map = ref(null)

const fetchGeoJSON = async () => {
  try {
    const response = await fetch('http://127.0.0.1:8000/data')
    return await response.json()
  } catch (error) {
    console.error('Error fetching GeoJSON data:', error)
  }
}

const fetchJsonLine = async () => {
  try {
    const response = await fetch('http://127.0.0.1:8000/api/lines')
    const Linedata = await response.json()
    return Linedata.map(
      (line) =>
        new Feature({
          geometry: new LineString(line.geometry.coordinates.map((coord) => fromLonLat(coord))),
          properties: line.properties
        })
    )
  } catch (error) {
    console.error('Error fetching line data:', error)
  }
}

const initializeMap = async () => {
  const geojsonData = await fetchGeoJSON()
  const geojsonLayer = new VectorLayer({
    source: new VectorSource({
      features: new GeoJSON().readFeatures(geojsonData, { featureProjection: 'EPSG:3857' })
    }),
    style: new Style({
      stroke: new Stroke({ color: 'red', width: 2 })
    })
  })

  const lineFeatures = await fetchJsonLine()
  const lineLayer = new VectorLayer({
    source: new VectorSource({ features: lineFeatures }),
    style: new Style({
      stroke: new Stroke({ color: 'black', width: 3 })
    })
  })

  const basemap = new TileLayer({ source: new OSM() })

  map.value = new Map({
    target: 'map',
    layers: [basemap, geojsonLayer, lineLayer],
    view: new View({
      center: fromLonLat([113.238266, 35.23904]),
      zoom: 9,
      extent: [...fromLonLat([110.35, 31.38]), ...fromLonLat([116.65, 36.22])]
    })
  })
}

onMounted(initializeMap)
</script>

<style>
#map {
  width: 80vw;
  /* 80% of the viewport width */
  height: 80vh;
  /* 50% of the viewport height */
  margin-bottom: 2px;
  /* 2% of the viewport height */
}

.logo {
  margin-top: 20px;
}
</style>
