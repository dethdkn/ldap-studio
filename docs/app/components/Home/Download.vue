<script setup lang="ts">
  const { t, locale } = useI18n({ useScope: 'local' })
  const older = RELEASES.slice(1).flatMap(({ version, date, file }) =>
    file ? [{ version, date, file }] : [],
  )
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
      <DownloadButton>{{ t('download') }}</DownloadButton>
      <Button :to="LINKS.sponsor" external icon="ph:heart" variant="ghost">{{
        t('sponsor')
      }}</Button>
    </Reveal>

    <Reveal :delay="0.25">
      <p class="mt-5 min-h-4 font-mono text-xs text-muted">
        <template v-if="LATEST_RELEASE?.file">
          {{ LATEST_RELEASE.file.name }} · {{ formatSize(LATEST_RELEASE.file.size) }} ·
          {{ formatDate(LATEST_RELEASE.date, locale) }}
        </template>
      </p>
    </Reveal>

    <Reveal :delay="0.3" class="mt-6 w-full max-w-md">
      <CollapsibleRoot v-if="older.length" class="glass rounded-3xl text-left">
        <CollapsibleTrigger
          class="group flex w-full items-center justify-between gap-4 px-5 py-4 text-sm font-semibold transition-colors hover:text-accent-ink">
          {{ t('older') }}
          <Icon
            name="ph:caret-down-bold"
            class="transition duration-300 group-data-[state=open]:rotate-180" />
        </CollapsibleTrigger>
        <CollapsibleContent
          class="overflow-hidden data-[state=closed]:animate-[collapse-collapsible_250ms_ease-out] data-[state=open]:animate-[expand-collapsible_300ms_ease-out]">
          <ul class="divide-y divide-line border-t border-line px-2 pb-2">
            <li v-for="release in older" :key="release.version">
              <a
                :href="release.file.url"
                class="flex items-center gap-3 rounded-2xl px-3 py-3 transition hover:bg-accent-soft">
                <span class="w-16 font-mono text-sm font-semibold">{{ release.version }}</span>
                <span class="flex-1 text-sm text-muted">{{
                  formatDate(release.date, locale)
                }}</span>
                <span class="font-mono text-xs text-muted">{{
                  formatSize(release.file.size)
                }}</span>
                <Icon name="ph:download-simple-bold" class="text-accent" />
              </a>
            </li>
          </ul>
        </CollapsibleContent>
      </CollapsibleRoot>
    </Reveal>

    <Reveal :delay="0.35" class="mt-6">
      <NuxtLinkLocale
        to="/changelog"
        class="inline-flex items-center gap-1.5 text-sm font-semibold text-accent-ink transition hover:brightness-125">
        {{ t('changelog') }}
        <Icon name="ph:arrow-right-bold" />
      </NuxtLinkLocale>
    </Reveal>
  </section>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Open your directory.",
    "lead": "Free, open source and made for the Mac. Download LDAP Studio and connect to your first server.",
    "download": "Download for macOS",
    "sponsor": "Sponsor the project",
    "older": "Download other versions",
    "changelog": "See what changed in each version"
  },
  "pt": {
    "title": "Abra seu diretório.",
    "lead": "Gratuito, open source e feito para o Mac. Baixe o LDAP Studio e conecte ao seu primeiro servidor.",
    "download": "Baixar para macOS",
    "sponsor": "Patrocinar o projeto",
    "older": "Baixar outras versões",
    "changelog": "Veja o que mudou em cada versão"
  }
}
</i18n>
