<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
</script>

<template>
  <header class="fixed inset-x-0 top-0 z-50 px-3 pt-3">
    <div class="glass mx-auto flex h-14 max-w-7xl items-center gap-4 rounded-2xl pr-2 pl-3">
      <NuxtLink
        :to="{ hash: '#top' }"
        class="flex shrink-0 items-center gap-2.5 font-semibold"
        :aria-label="t('home')">
        <Logo :size="28" />
        <span class="hidden sm:inline">LDAP Studio</span>
      </NuxtLink>

      <span class="hidden h-5 w-px bg-line md:block" />
      <DnTrail class="hidden flex-1 md:flex" />
      <span class="flex-1 md:hidden" />

      <LocaleButton />
      <NuxtLink
        :to="LINKS.repo"
        external
        target="_blank"
        :aria-label="t('github')"
        class="grid size-9 place-items-center rounded-full text-muted transition hover:bg-accent-soft hover:text-fg">
        <Icon name="ph:github-logo" class="text-lg" />
      </NuxtLink>
      <NuxtLink
        :to="LINKS.download"
        external
        target="_blank"
        class="flex h-9 items-center gap-1.5 rounded-full bg-accent px-4 text-sm font-semibold text-white transition hover:brightness-110 active:scale-95">
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
    "github": "Source code on GitHub",
    "download": "Download"
  },
  "pt": {
    "home": "LDAP Studio, voltar ao topo",
    "github": "Código-fonte no GitHub",
    "download": "Baixar"
  }
}
</i18n>
