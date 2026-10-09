<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const main = useTemplateRef<HTMLElement>('main')

  function skipToContent(): void {
    main.value?.focus()
  }
</script>

<template>
  <MotionConfig reduced-motion="user">
    <TooltipProvider>
      <button
        type="button"
        class="sr-only z-70 rounded-full bg-accent px-4 py-2 text-sm text-white focus:not-sr-only focus:fixed focus:top-3 focus:left-3"
        @click="skipToContent">
        {{ t('skip') }}
      </button>
      <Header />
      <main ref="main" tabindex="-1" class="outline-none">
        <slot />
      </main>
      <Footer />
    </TooltipProvider>
  </MotionConfig>
</template>

<i18n lang="json">
{
  "en": { "skip": "Skip to content" },
  "pt": { "skip": "Pular para o conteúdo" }
}
</i18n>
