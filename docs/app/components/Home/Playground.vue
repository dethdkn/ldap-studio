<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const { activeBranch, focusEntry } = useSections()

  const tab = ref('filter')

  const tabs = computed(() => [
    { value: 'filter', label: t('filter'), icon: 'ph:funnel' },
    { value: 'password', label: t('password'), icon: 'ph:key' },
    { value: 'tree', label: t('tree'), icon: 'ph:tree-structure' },
  ])

  watch([tab, activeBranch], () => {
    if (activeBranch.value === 'playground') focusEntry(tab.value)
  })
</script>

<template>
  <PageSection id="playground">
    <SectionHeading rdn="ou=playground" :title="t('title')" :lead="t('lead')" />

    <Reveal :delay="0.15" class="mt-12 max-w-4xl">
      <Tabs v-model="tab" :items="tabs">
        <template #filter>
          <DemoFilter />
        </template>
        <template #password>
          <DemoPassword />
        </template>
        <template #tree>
          <DemoTree />
        </template>
      </Tabs>
    </Reveal>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Try it in your browser.",
    "lead": "Three parts of the app, rebuilt for this page. Nothing you type here leaves your browser.",
    "filter": "Filter builder",
    "password": "Password hashing",
    "tree": "Directory tree"
  },
  "pt": {
    "title": "Experimente no navegador.",
    "lead": "Três partes do app, recriadas para esta página. Nada do que você digita aqui sai do seu navegador.",
    "filter": "Construtor de filtros",
    "password": "Hash de senha",
    "tree": "Árvore do diretório"
  }
}
</i18n>
