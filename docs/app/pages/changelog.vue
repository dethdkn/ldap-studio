<script setup lang="ts">
  const { t, locale } = useI18n({ useScope: 'local' })

  useHead({ title: t('title') })
  useSeoMeta({ description: t('description') })
  defineOgImage('Model.takumi', { title: t('title'), description: t('description') })

  useSectionTracking()
</script>

<template>
  <PageSection id="changelog">
    <SectionHeading as="h1" rdn="ou=changelog" :title="t('title')" :lead="t('lead')" />

    <ol class="relative mt-14 max-w-3xl space-y-6">
      <Reveal v-for="(release, index) in RELEASES" :key="release.version" as="li">
        <article :id="release.version" class="glass scroll-mt-24 rounded-3xl p-6 sm:p-8">
          <header class="flex flex-wrap items-center gap-3">
            <h2 class="type-title text-3xl">{{ release.version }}</h2>
            <span
              v-if="index === 0"
              class="rounded-full bg-accent px-2.5 py-0.5 font-mono text-[0.7rem] text-white">
              {{ t('latest') }}
            </span>
            <time :datetime="release.date" class="ml-auto font-mono text-xs text-muted">
              {{ formatDate(release.date, locale) }}
            </time>
          </header>

          <!-- body_html is rendered and sanitized by GitHub -->
          <!-- oxlint-disable-next-line vue/no-v-html -->
          <div v-if="release.notes" class="release-notes mt-5" v-html="release.notes" />
          <p v-else class="mt-5 text-muted">{{ t('no_notes') }}</p>

          <footer class="mt-6 flex flex-wrap items-center gap-3 border-t border-line pt-5">
            <Button
              v-if="release.file"
              :to="release.file.url"
              external
              icon="ph:download-simple-bold"
              :variant="index === 0 ? 'primary' : 'ghost'">
              {{ t('download') }}
              <span class="font-mono text-xs font-medium opacity-70">
                {{ formatSize(release.file.size) }}
              </span>
            </Button>
            <NuxtLink
              :to="release.url"
              external
              target="_blank"
              class="inline-flex items-center gap-1.5 text-sm font-semibold text-muted transition hover:text-fg">
              <Icon name="ph:github-logo" />
              {{ t('on_github') }}
            </NuxtLink>
          </footer>
        </article>
      </Reveal>
    </ol>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Changelog",
    "description": "Every LDAP Studio release and what changed in it.",
    "lead": "Every release of LDAP Studio, newest first, straight from GitHub Releases.",
    "latest": "latest",
    "download": "Download",
    "on_github": "View on GitHub",
    "no_notes": "No notes for this release."
  },
  "pt": {
    "title": "Changelog",
    "description": "Todas as versões do LDAP Studio e o que mudou em cada uma.",
    "lead": "Todas as versões do LDAP Studio, da mais nova para a mais antiga, direto do GitHub Releases.",
    "latest": "atual",
    "download": "Baixar",
    "on_github": "Ver no GitHub",
    "no_notes": "Sem notas para esta versão."
  }
}
</i18n>
