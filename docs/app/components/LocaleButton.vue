<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const { locale, locales, setLocale, setLocaleCookie } = useI18n()

  async function changeLocale(value: unknown): Promise<void> {
    if ((value !== 'en' && value !== 'pt') || value === locale.value) return

    setLocaleCookie(value)
    await setLocale(value)
  }
</script>

<template>
  <DropdownMenuRoot :modal="false">
    <DropdownMenuTrigger
      :aria-label="t('language')"
      class="flex h-8 shrink-0 items-center gap-1 rounded-full px-2 text-xs text-fg/70 transition outline-none hover:text-fg focus-visible:ring-2 focus-visible:ring-accent active:scale-95 data-[state=open]:text-fg">
      <Icon name="ph:globe-simple" class="text-base" />
      {{ locale.toUpperCase() }}
      <Icon name="ph:caret-down-bold" class="text-[0.6rem]" />
    </DropdownMenuTrigger>

    <DropdownMenuContent
      align="end"
      :side-offset="8"
      class="material z-50 min-w-44 rounded-xl border border-line bg-bg/85 p-1 text-sm text-fg shadow-[0_16px_40px_-12px_rgb(0_0_0/0.35)]">
      <DropdownMenuRadioGroup :model-value="locale" @update:model-value="changeLocale">
        <DropdownMenuRadioItem
          v-for="item in locales"
          :key="item.code"
          :value="item.code"
          class="flex cursor-default items-center justify-between gap-3 rounded-lg px-3 py-2 outline-none data-[highlighted]:bg-fg/[0.07]">
          {{ item.name }}
          <DropdownMenuItemIndicator>
            <Icon name="ph:check-bold" class="text-xs text-accent" />
          </DropdownMenuItemIndicator>
        </DropdownMenuRadioItem>
      </DropdownMenuRadioGroup>
    </DropdownMenuContent>
  </DropdownMenuRoot>
</template>

<i18n lang="json">
{
  "en": {
    "language": "Language"
  },
  "pt": {
    "language": "Idioma"
  }
}
</i18n>
