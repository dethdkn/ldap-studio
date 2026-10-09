<script setup lang="ts">
  defineProps({
    size: { type: Number, default: 32 },
  })
</script>

<template>
  <NuxtImg src="/logo.png" alt="" :width="size" :height="size" class="shrink-0" />
</template>
