<template>
      假设这里是地图<br/>
      
      <img alt="Vue logo" class="logo" src="../assets/logo.svg" width="125" height="125" />
  <div>
    <h1>{{ title }}</h1>
    <p>{{ json }}</p> 

  </div>

</template>

<script setup>
import { ref, onMounted } from 'vue';

const title = ref('Hello World');
const json = ref(''); // Initialize json ref

async function fetchData() {
  try {
    const response = await fetch("http://localhost:8000/data");
    const data = await response.json(); // Use response.json() to parse JSON
    json.value = data; // Assign data to json ref
    console.log(json.value);
  } catch (error) {
    console.error('Error fetching data:', error);
  }
}

onMounted(fetchData);
</script>
