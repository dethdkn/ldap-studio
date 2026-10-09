<script setup lang="ts">
  const { t, locale } = useI18n({ useScope: 'local' })
</script>

<template>
  <NuxtLink
    :to="LINKS.repo"
    external
    target="_blank"
    :aria-label="t('star', { count: STARS })"
    class="flex h-8 shrink-0 items-center gap-1.5 rounded-full px-2 text-xs text-fg/70 transition hover:text-fg active:scale-95">
    <Icon name="ph:github-logo-fill" class="text-base" />
    <span class="flex items-center gap-0.5 tabular-nums">
      <Icon name="ph:star-fill" class="text-[0.7rem] text-[#e3b341]" />
      {{ formatCount(STARS, locale) }}
    </span>
  </NuxtLink>
</template>

<i18n lang="json">
{
  "en": {
    "star": "Star LDAP Studio on GitHub, {count} stars"
  },
  "pt": {
    "star": "Dar uma estrela ao LDAP Studio no GitHub, {count} estrelas"
  }
}
</i18n>
