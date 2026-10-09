<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  useHead({ title: t('title') })
  useSeoMeta({ description: t('description') })
  defineOgImage('Model.takumi', { title: 'LDAP Studio', description: t('og_description') })

  useSectionTracking()
</script>

<template>
  <div>
    <HomeHero />
    <HomeWhy />
    <HomeInside />
    <HomeFeatures />
    <HomePlayground />
    <HomeInstall />
    <HomeGuide />
    <HomeFaq />
    <HomeContributors />
    <HomeDownload />
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Native macOS LDAP client",
    "description": "A native macOS LDAP client to browse, search and edit LDAP directories. Free and open source.",
    "og_description": "A native macOS LDAP client"
  },
  "pt": {
    "title": "Cliente LDAP nativo para macOS",
    "description": "Um cliente LDAP nativo para macOS para navegar, pesquisar e editar diretórios LDAP. Gratuito e open source.",
    "og_description": "Um cliente LDAP nativo para macOS"
  }
}
</i18n>
