<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const tone = useHeaderTone()
  const { scrollToSection } = useSectionScroll()
  const { latestRelease } = useGitHub()

  const sections = computed<{ name: SectionName; label: string }[]>(() => [
    { name: 'features', label: t('features') },
    { name: 'playground', label: t('playground') },
    { name: 'install', label: t('install') },
  ])
</script>

<template>
  <header
    class="material fixed inset-x-0 top-0 z-50 bg-bg/75 text-fg transition-colors duration-500 ease-apple"
    :class="tone === 'dark' ? 'tone-dark' : tone === 'gray' ? 'tone-gray' : 'tone-light'">
    <div class="mx-auto flex h-13 max-w-[64rem] items-center gap-1 px-5 sm:px-8">
      <button
        type="button"
        class="mr-auto flex shrink-0 items-center gap-2 text-[1.3rem] font-semibold tracking-[-0.02em]"
        :aria-label="t('home')"
        @click="scrollToSection('top')">
        <Logo :size="26" />
        <span class="hidden sm:inline">LDAP Studio</span>
      </button>

      <nav :aria-label="t('sections')" class="mr-2 hidden items-center gap-5 text-xs md:flex">
        <button
          v-for="section in sections"
          :key="section.name"
          type="button"
          class="text-fg/80 transition hover:text-fg"
          @click="scrollToSection(section.name)">
          {{ section.label }}
        </button>
        <NuxtLinkLocale
          to="/changelog"
          class="text-fg/80 transition hover:text-fg"
          active-class="!text-fg">
          {{ t('changelog') }}
        </NuxtLinkLocale>
      </nav>

      <LocaleButton />
      <StarButton />
      <NuxtLink
        :to="LINKS.sponsor"
        external
        target="_blank"
        :aria-label="t('sponsor')"
        class="grid size-8 shrink-0 place-items-center rounded-full text-fg/70 transition hover:text-[#db61a2] active:scale-90">
        <Icon name="ph:heart-fill" class="text-base" />
      </NuxtLink>
      <NuxtLink
        :to="latestRelease?.file?.url ?? LINKS.download"
        external
        target="_blank"
        class="ml-1 flex h-7 shrink-0 items-center rounded-full bg-accent px-3.5 text-xs text-white transition hover:bg-[#0077ed] active:scale-95">
        {{ t('download') }}
      </NuxtLink>
    </div>
    <div aria-hidden="true" class="h-px bg-line" />
  </header>
</template>

<i18n lang="json">
{
  "en": {
    "home": "LDAP Studio, back to top",
    "sections": "Sections",
    "features": "Features",
    "playground": "Try it",
    "install": "Install",
    "changelog": "Changelog",
    "sponsor": "Sponsor LDAP Studio on GitHub",
    "download": "Download"
  },
  "pt": {
    "home": "LDAP Studio, voltar ao topo",
    "sections": "Seções",
    "features": "Recursos",
    "playground": "Experimente",
    "install": "Instalar",
    "changelog": "Changelog",
    "sponsor": "Patrocinar o LDAP Studio no GitHub",
    "download": "Baixar"
  }
}
</i18n>
