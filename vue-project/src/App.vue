<script setup>
import HelloWorld from './components/HelloWorld.vue'

</script>

<template>
  <header>


    <div class="wrapper">
      <HelloWorld/>
    </div>
  </header>

  <main>

    <div>
  对地图的操作： <button>放大</button>
  <button>缩小</button>
  <button>拖动</button>
</div>
<br/>
  前端增加<button>投点</button>、
  
 
  <button> 新建物联网接口流程(仅做页面)</button>
  </main>
</template>

<style scoped>
header {
  line-height: 1.5;
}

.logo {
  display: block;
  margin: 0 auto 2rem;
}

@media (min-width: 1024px) {
  header {
    display: flex;
    place-items: center;
    padding-right: calc(var(--section-gap) / 2);
  }

  .logo {
    margin: 0 2rem 0 0;
  }

  header .wrapper {
    display: flex;
    place-items: flex-start;
    flex-wrap: wrap;
  }
}
</style>
