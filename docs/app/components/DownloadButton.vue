<script setup lang="ts">
  defineProps({
    icon: { type: String, default: 'ph:apple-logo-fill' },
  })

  const { latestRelease } = useGitHub()
</script>

<template>
  <Button :to="latestRelease?.file?.url ?? LINKS.download" external :icon="icon">
    <slot />
    <span
      v-if="latestRelease"
      class="rounded-full bg-white/20 px-2 py-0.5 font-mono text-[0.7rem] font-medium">
      {{ latestRelease.version }}
    </span>
  </Button>
</template>
