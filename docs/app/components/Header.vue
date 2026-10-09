<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const localePath = useLocalePath()
</script>

<template>
  <header class="fixed inset-x-0 top-0 z-50 px-3 pt-3">
    <div
      class="glass mx-auto flex h-14 max-w-7xl items-center gap-2 rounded-2xl pr-2 pl-3 sm:gap-3">
      <NuxtLink
        :to="localePath({ path: '/', hash: '#top' })"
        class="flex shrink-0 items-center gap-2.5 font-semibold"
        :aria-label="t('home')">
        <Logo :size="28" />
        <span class="hidden sm:inline">LDAP Studio</span>
      </NuxtLink>

      <span class="hidden h-5 w-px bg-line md:block" />
      <DnTrail class="hidden flex-1 md:flex" />
      <span class="flex-1 md:hidden" />

      <NuxtLinkLocale
        to="/changelog"
        class="hidden h-9 items-center rounded-full px-3 text-sm font-semibold text-muted transition hover:bg-accent-soft hover:text-fg sm:flex"
        active-class="text-fg">
        {{ t('changelog') }}
      </NuxtLinkLocale>
      <LocaleButton />
      <StarButton />
      <NuxtLink
        :to="LINKS.sponsor"
        external
        target="_blank"
        :aria-label="t('sponsor')"
        class="grid size-9 shrink-0 place-items-center rounded-full text-muted transition hover:bg-[#db61a2]/10 hover:text-[#db61a2] active:scale-95">
        <Icon name="ph:heart-fill" class="text-lg" />
      </NuxtLink>
      <NuxtLink
        :to="LATEST_RELEASE?.file?.url ?? LINKS.download"
        external
        target="_blank"
        class="flex h-9 shrink-0 items-center gap-1.5 rounded-full bg-accent px-4 text-sm font-semibold text-white transition hover:brightness-110 active:scale-95">
        <Icon name="ph:download-simple-bold" />
        {{ t('download') }}
      </NuxtLink>
    </div>
  </header>
</template>

<i18n lang="json">
{
  "en": {
    "home": "LDAP Studio, back to top",
    "changelog": "Changelog",
    "sponsor": "Sponsor LDAP Studio on GitHub",
    "download": "Download"
  },
  "pt": {
    "home": "LDAP Studio, voltar ao topo",
    "changelog": "Changelog",
    "sponsor": "Patrocinar o LDAP Studio no GitHub",
    "download": "Baixar"
  }
}
</i18n>
