<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
</script>

<template>
  <PageSection id="contributors">
    <SectionHeading rdn="ou=contributors" :title="t('title')" :lead="t('lead')" />

    <ul class="mt-12 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
      <Reveal
        v-for="(contributor, index) in CONTRIBUTORS"
        :key="contributor.login"
        as="li"
        :delay="index * 0.06">
        <NuxtLink
          :to="contributor.url"
          external
          target="_blank"
          class="glass flex h-full flex-col items-center rounded-3xl p-6 text-center transition duration-300 hover:border-accent/40">
          <img
            :src="`${contributor.avatar}&s=192`"
            :alt="contributor.login"
            width="96"
            height="96"
            loading="lazy"
            class="size-24 rounded-full border border-line bg-bg-deep" />
          <p class="mt-4 font-semibold">{{ contributor.login }}</p>
          <p class="mt-1 font-mono text-xs text-muted">
            {{ t('commits', contributor.contributions) }}
          </p>
        </NuxtLink>
      </Reveal>
      <Reveal as="li" :delay="CONTRIBUTORS.length * 0.06">
        <NuxtLink
          :to="LINKS.repo"
          external
          target="_blank"
          class="flex h-full min-h-52 flex-col items-center justify-center rounded-3xl border border-dashed border-line p-6 text-center text-muted transition duration-300 hover:border-accent/60 hover:text-fg">
          <span class="grid size-24 place-items-center rounded-full bg-accent-soft text-accent-ink">
            <Icon name="ph:plus-bold" class="text-3xl" />
          </span>
          <p class="mt-4 font-semibold">{{ t('you') }}</p>
          <p class="mt-1 font-mono text-xs">{{ t('you_hint') }}</p>
        </NuxtLink>
      </Reveal>
    </ul>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Made in the open.",
    "lead": "LDAP Studio is built by the people below. Bug fixes, features and translations are welcome.",
    "commits": "no commits | 1 commit | {n} commits",
    "you": "You?",
    "you_hint": "open a pull request"
  },
  "pt": {
    "title": "Feito em público.",
    "lead": "O LDAP Studio é construído pelas pessoas abaixo. Correções, novas funções e traduções são bem-vindas.",
    "commits": "nenhum commit | 1 commit | {n} commits",
    "you": "Você?",
    "you_hint": "abra um pull request"
  }
}
</i18n>
