<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const links = computed(() => [
    { label: 'GitHub', to: LINKS.repo },
    { label: t('releases'), to: LINKS.releases },
    { label: t('issues'), to: LINKS.issues },
    { label: t('sponsor'), to: LINKS.sponsor },
    { label: t('license'), to: LINKS.license },
  ])
</script>

<template>
  <footer class="tone-gray bg-bg text-xs leading-relaxed text-muted" data-tone="gray">
    <div class="mx-auto max-w-[64rem] px-5 py-10 sm:px-8">
      <div class="flex items-center gap-2.5 border-b border-line pb-5">
        <Logo :size="22" />
        <p>
          <span class="font-semibold text-fg">LDAP Studio</span>
          · {{ t('tagline') }}
        </p>
      </div>

      <div class="flex flex-col gap-4 pt-5 sm:flex-row sm:items-center sm:justify-between sm:gap-8">
        <p>© 2026 LDAP Studio · {{ t('open_source') }}</p>

        <nav :aria-label="t('links')" class="flex flex-wrap gap-x-5 gap-y-1">
          <NuxtLinkLocale to="/changelog" class="text-fg/80 hover:underline">
            {{ t('changelog') }}
          </NuxtLinkLocale>
          <NuxtLink
            v-for="link in links"
            :key="link.label"
            :to="link.to"
            external
            target="_blank"
            class="text-fg/80 hover:underline">
            {{ link.label }}
          </NuxtLink>
        </nav>
      </div>
    </div>
  </footer>
</template>

<i18n lang="json">
{
  "en": {
    "tagline": "A native macOS LDAP client",
    "links": "Project links",
    "changelog": "Changelog",
    "releases": "Releases",
    "issues": "Report a bug",
    "sponsor": "Sponsor",
    "license": "MIT License",
    "open_source": "free and open source"
  },
  "pt": {
    "tagline": "Um cliente LDAP nativo para macOS",
    "links": "Links do projeto",
    "changelog": "Changelog",
    "releases": "Versões",
    "issues": "Reportar um bug",
    "sponsor": "Patrocinar",
    "license": "Licença MIT",
    "open_source": "gratuito e open source"
  }
}
</i18n>
