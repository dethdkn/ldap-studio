<script setup lang="ts">
  const { t, locale } = useI18n({ useScope: 'local' })
  const reducedMotion = useReducedMotion()

  const section = useTemplateRef<HTMLElement>('section')
  const icon = useTemplateRef<HTMLElement>('icon')
  useSectionAnchor('download', section)

  const { scrollYProgress } = useScroll({ target: icon, offset: ['start end', 'center 0.45'] })
  const iconScale = useTransform(scrollYProgress, [0, 1], [0.55, 1])
  const iconRotate = useTransform(scrollYProgress, [0, 1], [-12, 0])

  const older = RELEASES.slice(1).flatMap(({ version, date, file }) =>
    file ? [{ version, date, file }] : [],
  )
</script>

<template>
  <section ref="section" data-tone="dark" class="tone-dark relative overflow-hidden bg-bg text-fg">
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-x-0 top-0 h-[40rem] bg-[radial-gradient(40rem_24rem_at_50%_30%,rgb(41_151_255/0.22),transparent_70%)]" />

    <div
      class="relative mx-auto flex max-w-3xl flex-col items-center px-5 py-32 text-center sm:px-8 lg:py-44">
      <div ref="icon">
        <Motion
          :style="reducedMotion ? {} : { scale: iconScale, rotate: iconRotate }"
          class="will-change-transform">
          <Logo :size="148" class="drop-shadow-[0_24px_60px_rgb(41_151_255/0.4)]" />
        </Motion>
      </div>

      <Reveal>
        <h2 class="type-hero mt-12">{{ t('title') }}</h2>
      </Reveal>
      <Reveal :delay="0.1">
        <p class="type-lead mx-auto mt-6 max-w-xl">{{ t('lead') }}</p>
      </Reveal>
      <Reveal :delay="0.2" class="mt-10 flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
        <DownloadButton>{{ t('download') }}</DownloadButton>
        <Button :to="LINKS.sponsor" external variant="link">{{ t('sponsor') }}</Button>
      </Reveal>

      <Reveal :delay="0.25">
        <p v-if="LATEST_RELEASE?.file" class="mt-6 text-xs text-muted tabular-nums">
          {{ LATEST_RELEASE.file.name }} · {{ formatSize(LATEST_RELEASE.file.size) }} ·
          {{ formatDate(LATEST_RELEASE.date, locale) }}
        </p>
      </Reveal>

      <Reveal :delay="0.3" class="mt-12 w-full max-w-md">
        <CollapsibleRoot v-if="older.length" class="card text-left">
          <CollapsibleTrigger
            class="group flex w-full items-center justify-between gap-4 px-6 py-4 text-sm font-semibold transition-colors hover:text-accent-ink">
            {{ t('older') }}
            <Icon
              name="ph:caret-down-bold"
              class="text-xs transition duration-300 ease-apple group-data-[state=open]:rotate-180" />
          </CollapsibleTrigger>
          <CollapsibleContent
            class="overflow-hidden data-[state=closed]:animate-[collapse-collapsible_250ms_ease-out] data-[state=open]:animate-[expand-collapsible_300ms_ease-out]">
            <ul class="divide-y divide-line border-t border-line px-2 pb-2">
              <li v-for="release in older" :key="release.version">
                <a
                  :href="release.file.url"
                  class="flex items-center gap-3 rounded-xl px-4 py-3 transition hover:bg-fg/5">
                  <span class="w-16 text-sm font-semibold tabular-nums">{{ release.version }}</span>
                  <span class="flex-1 text-sm text-muted">{{
                    formatDate(release.date, locale)
                  }}</span>
                  <span class="text-xs text-muted tabular-nums">{{
                    formatSize(release.file.size)
                  }}</span>
                  <Icon name="ph:arrow-circle-down-fill" class="text-lg text-accent-ink" />
                </a>
              </li>
            </ul>
          </CollapsibleContent>
        </CollapsibleRoot>
      </Reveal>

      <Reveal :delay="0.35" class="mt-6">
        <NuxtLinkLocale
          to="/changelog"
          class="group inline-flex items-center gap-1 text-sm text-accent-ink hover:underline">
          {{ t('changelog') }}
          <Icon
            name="ph:caret-right-bold"
            class="text-xs transition-transform duration-200 group-hover:translate-x-0.5" />
        </NuxtLinkLocale>
      </Reveal>
    </div>
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
