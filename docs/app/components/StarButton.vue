<script setup lang="ts">
  const { t, locale } = useI18n({ useScope: 'local' })
</script>

<template>
  <NuxtLink
    :to="LINKS.repo"
    external
    target="_blank"
    :aria-label="t('star', { count: STARS })"
    class="flex h-9 items-center gap-1.5 rounded-full border border-line px-3 text-sm font-semibold text-muted transition hover:border-accent/40 hover:text-fg active:scale-95">
    <Icon name="ph:github-logo" class="text-lg" />
    <span class="hidden lg:inline">{{ t('label') }}</span>
    <span class="flex items-center gap-1 font-mono text-xs">
      <Icon name="ph:star-fill" class="text-[#e3b341]" />
      {{ formatCount(STARS, locale) }}
    </span>
  </NuxtLink>
</template>

<i18n lang="json">
{
  "en": {
    "label": "Star",
    "star": "Star LDAP Studio on GitHub, {count} stars"
  },
  "pt": {
    "label": "Star",
    "star": "Dar uma estrela ao LDAP Studio no GitHub, {count} estrelas"
  }
}
</i18n>
