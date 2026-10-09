<script setup lang="ts">
  const { t, locale } = useI18n({ useScope: 'local' })
  const { releases } = useGitHub()

  useHead({ title: t('title') })
  useSeoMeta({ description: t('description') })
  defineOgImage('Model.takumi', { title: t('title'), description: t('description') })
</script>

<template>
  <PageSection name="changelog" tone="light">
    <div class="pt-6">
      <SectionHeading as="h1" :eyebrow="t('eyebrow')" :title="t('title')" :lead="t('lead')" />
    </div>

    <ol class="mt-20 divide-y divide-line border-t border-line">
      <Reveal v-for="(release, index) in releases" :key="release.version" as="li">
        <article class="grid gap-6 py-12 md:grid-cols-[13rem_1fr] md:gap-12">
          <header class="md:sticky md:top-24 md:self-start">
            <div class="flex items-center gap-3">
              <h2 class="type-title text-4xl tabular-nums">{{ release.version }}</h2>
              <span
                v-if="index === 0"
                class="rounded-full bg-accent px-2.5 py-0.5 text-[0.7rem] font-semibold text-white">
                {{ t('latest') }}
              </span>
            </div>
            <time :datetime="release.date" class="mt-2 block text-sm text-muted">
              {{ formatDate(release.date, locale) }}
            </time>
          </header>

          <div class="min-w-0">
            <!-- oxlint-disable-next-line vue/no-v-html -->
            <div v-if="release.notes" class="release-notes" v-html="release.notes" />
            <p v-else class="text-muted">{{ t('no_notes') }}</p>

            <footer class="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
              <Button
                v-if="release.file"
                :to="release.file.url"
                external
                icon="ph:download-simple-bold"
                :variant="index === 0 ? 'primary' : 'ghost'"
                class="!h-10 !px-5 !text-sm">
                {{ t('download') }}
                <span class="text-xs tabular-nums opacity-70">
                  {{ formatSize(release.file.size) }}
                </span>
              </Button>
              <Button :to="release.url" external variant="link" class="!h-10 !text-sm">
                {{ t('on_github') }}
              </Button>
            </footer>
          </div>
        </article>
      </Reveal>
    </ol>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "eyebrow": "LDAP Studio",
    "title": "Changelog",
    "description": "Every LDAP Studio release and what changed in it.",
    "lead": "What changed in each version of LDAP Studio.",
    "latest": "latest",
    "download": "Download",
    "on_github": "View on GitHub",
    "no_notes": "No notes for this release."
  },
  "pt": {
    "eyebrow": "LDAP Studio",
    "title": "Changelog",
    "description": "Todas as versões do LDAP Studio e o que mudou em cada uma.",
    "lead": "O que mudou em cada versão do LDAP Studio.",
    "latest": "atual",
    "download": "Baixar",
    "on_github": "Ver no GitHub",
    "no_notes": "Sem notas para esta versão."
  }
}
</i18n>
