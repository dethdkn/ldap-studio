<script setup lang="ts">
  defineProps({
    keys: { type: String, required: true },
  })
</script>

<template>
  <kbd class="inline-flex items-center gap-0.5">
    <span
      v-for="(key, index) in [...keys]"
      :key="index"
      class="inline-grid min-w-6 place-items-center rounded-md bg-surface-solid px-1 py-0.5 font-sans text-xs font-medium text-fg shadow-[0_1px_0_rgb(0_0_0/0.12),0_0_0_0.5px_rgb(0_0_0/0.08)]">
      {{ key }}
    </span>
  </kbd>
</template>
