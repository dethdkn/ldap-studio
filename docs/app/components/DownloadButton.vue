<script setup lang="ts">
  defineProps({
    icon: { type: String, default: 'ph:apple-logo-fill' },
  })
</script>

<template>
  <Button :to="LATEST_RELEASE?.file?.url ?? LINKS.download" external :icon="icon">
    <slot />
    <span
      v-if="LATEST_RELEASE"
      class="rounded-full bg-white/20 px-2 py-0.5 font-mono text-[0.7rem] font-medium">
      {{ LATEST_RELEASE.version }}
    </span>
  </Button>
</template>
