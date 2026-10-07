<script setup lang="ts">
  const { finalizePendingLocaleChange } = useI18n()

  async function onBeforeEnter(): Promise<void> {
    globalThis.scrollTo({ top: 0, left: 0, behavior: 'instant' })
    await finalizePendingLocaleChange()
  }
</script>

<template>
  <NuxtRouteAnnouncer />
  <NuxtLoadingIndicator color="var(--accent)" :height="2" />
  <NuxtLayout>
    <NuxtPage :transition="{ name: 'page', mode: 'out-in', onBeforeEnter }" />
  </NuxtLayout>
</template>
