<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
</script>

<template>
  <section
    id="download"
    data-branch="download"
    class="relative mx-auto flex min-h-svh max-w-3xl flex-col items-center justify-end px-4 pt-[42svh] pb-24 text-center sm:px-8">
    <Reveal>
      <h2 class="type-display text-[clamp(3rem,7vw,6rem)]">{{ t('title') }}</h2>
    </Reveal>
    <Reveal :delay="0.1">
      <p class="mx-auto mt-6 max-w-lg text-lg text-pretty text-muted">{{ t('lead') }}</p>
    </Reveal>
    <Reveal :delay="0.2" class="mt-10 flex flex-wrap justify-center gap-3">
      <Button :to="LINKS.download" external icon="ph:apple-logo-fill">{{ t('download') }}</Button>
      <Button :to="LINKS.sponsor" external icon="ph:heart" variant="ghost">{{
        t('sponsor')
      }}</Button>
    </Reveal>
  </section>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Open your directory.",
    "lead": "Free, open source and made for the Mac. Download LDAP Studio and connect to your first server.",
    "download": "Download for macOS",
    "sponsor": "Sponsor the project"
  },
  "pt": {
    "title": "Abra seu diretório.",
    "lead": "Gratuito, open source e feito para o Mac. Baixe o LDAP Studio e conecte ao seu primeiro servidor.",
    "download": "Baixar para macOS",
    "sponsor": "Patrocinar o projeto"
  }
}
</i18n>
