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
      class="inline-grid min-w-6 place-items-center rounded-md border border-line bg-surface-solid px-1 py-0.5 font-sans text-xs font-medium text-fg shadow-[0_1px_0_var(--line)]">
      {{ key }}
    </span>
  </kbd>
</template>
