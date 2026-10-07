<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const links = computed(() => [
    { label: 'GitHub', to: LINKS.repo },
    { label: t('releases'), to: LINKS.download },
    { label: t('issues'), to: LINKS.issues },
    { label: t('sponsor'), to: LINKS.sponsor },
    { label: t('license'), to: LINKS.license },
  ])
</script>

<template>
  <footer class="relative z-10 border-t border-line">
    <div
      class="mx-auto flex max-w-7xl flex-col gap-8 px-4 py-12 sm:px-8 md:flex-row md:items-center md:justify-between">
      <div class="flex items-center gap-3">
        <Logo :size="36" />
        <div>
          <p class="font-semibold">LDAP Studio</p>
          <p class="text-sm text-muted">{{ t('tagline') }}</p>
        </div>
      </div>

      <nav :aria-label="t('links')" class="flex flex-wrap gap-x-6 gap-y-2 text-sm text-muted">
        <NuxtLink
          v-for="link in links"
          :key="link.to"
          :to="link.to"
          external
          target="_blank"
          class="transition hover:text-fg">
          {{ link.label }}
        </NuxtLink>
      </nav>
    </div>

    <div class="mx-auto max-w-7xl px-4 pb-10 font-mono text-xs text-muted sm:px-8">
      © 2026
      <NuxtLink :to="LINKS.author" external target="_blank" class="hover:text-fg"
        >Gabriel Rosa</NuxtLink
      >
      · {{ t('open_source') }}
    </div>
  </footer>
</template>

<i18n lang="json">
{
  "en": {
    "tagline": "A native macOS LDAP client",
    "links": "Project links",
    "releases": "Releases",
    "issues": "Report a bug",
    "sponsor": "Sponsor",
    "license": "MIT License",
    "open_source": "free and open source"
  },
  "pt": {
    "tagline": "Um cliente LDAP nativo para macOS",
    "links": "Links do projeto",
    "releases": "Versões",
    "issues": "Reportar um bug",
    "sponsor": "Patrocinar",
    "license": "Licença MIT",
    "open_source": "gratuito e open source"
  }
}
</i18n>
