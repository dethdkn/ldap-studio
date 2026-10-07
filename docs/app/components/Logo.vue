<script setup lang="ts">
  defineProps({
    size: { type: Number, default: 32 },
  })
</script>

<template>
  <NuxtImg
    src="/logo.svg"
    alt=""
    :width="size"
    :height="size"
    class="shrink-0 drop-shadow-[0_4px_10px_rgb(0_107_255/0.35)]" />
</template>
