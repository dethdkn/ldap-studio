<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const tab = ref('filter')

  const tabs = computed(() => [
    { value: 'filter', label: t('filter'), icon: 'ph:funnel-simple' },
    { value: 'password', label: t('password'), icon: 'ph:key' },
  ])
</script>

<template>
  <PageSection name="playground" tone="light">
    <SectionHeading center :eyebrow="t('eyebrow')" :title="t('title')" :lead="t('lead')" />

    <Reveal :delay="0.15" class="mx-auto mt-14 max-w-3xl">
      <Tabs v-model="tab" :items="tabs">
        <template #filter>
          <DemoFilter />
        </template>
        <template #password>
          <DemoPassword />
        </template>
      </Tabs>
    </Reveal>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "eyebrow": "Try it",
    "title": "Play with it right here.",
    "lead": "Two parts of the app, rebuilt for this page. Nothing you type leaves your browser.",
    "filter": "Filter builder",
    "password": "Password hashing"
  },
  "pt": {
    "eyebrow": "Experimente",
    "title": "Brinque com ele aqui mesmo.",
    "lead": "Duas partes do app, recriadas para esta página. Nada do que você digita sai do seu navegador.",
    "filter": "Construtor de filtros",
    "password": "Hash de senha"
  }
}
</i18n>
