<script setup lang="ts">
  const { t, locale, setLocale, setLocaleCookie } = useI18n({ useScope: 'local' })

  const next = computed(() => (locale.value === 'en' ? 'pt' : 'en'))

  async function toggleLocale(): Promise<void> {
    setLocaleCookie(next.value)
    await setLocale(next.value)
  }
</script>

<template>
  <button
    type="button"
    :aria-label="t('switch')"
    class="flex h-8 shrink-0 items-center gap-1 rounded-full px-2 text-xs text-fg/70 transition hover:text-fg active:scale-95"
    @click="toggleLocale">
    <Icon name="ph:globe-simple" class="text-base" />
    {{ next.toUpperCase() }}
  </button>
</template>

<i18n lang="json">
{
  "en": {
    "switch": "Ler em português"
  },
  "pt": {
    "switch": "Read in English"
  }
}
</i18n>
