<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
</script>

<template>
  <PageSection name="contributors" tone="light">
    <SectionHeading center :eyebrow="t('eyebrow')" :title="t('title')" :lead="t('lead')" />

    <ul class="mt-16 flex flex-wrap justify-center gap-5">
      <Reveal
        v-for="(contributor, index) in CONTRIBUTORS"
        :key="contributor.login"
        as="li"
        :delay="index * 0.06"
        class="w-44">
        <NuxtLink
          :to="contributor.url"
          external
          target="_blank"
          class="group card flex h-full flex-col items-center p-6 text-center transition duration-500 ease-apple hover:-translate-y-1">
          <img
            :src="`${contributor.avatar}&s=192`"
            :alt="contributor.login"
            width="96"
            height="96"
            loading="lazy"
            class="size-24 rounded-full bg-bg-deep shadow-[0_8px_24px_-8px_rgb(0_0_0/0.3)] transition duration-500 ease-apple group-hover:scale-105" />
          <p class="mt-4 font-semibold">{{ contributor.login }}</p>
          <p class="mt-0.5 text-xs text-muted">{{ t('commits', contributor.contributions) }}</p>
        </NuxtLink>
      </Reveal>
      <Reveal as="li" :delay="CONTRIBUTORS.length * 0.06" class="w-44">
        <NuxtLink
          :to="LINKS.repo"
          external
          target="_blank"
          class="group flex h-full flex-col items-center rounded-[1.75rem] border-2 border-dashed border-line p-6 text-center text-muted transition duration-500 ease-apple hover:border-accent hover:text-fg">
          <span
            class="grid size-24 place-items-center rounded-full bg-accent-soft text-accent-ink transition duration-500 ease-apple group-hover:scale-105">
            <Icon name="ph:plus-bold" class="text-3xl" />
          </span>
          <p class="mt-4 font-semibold">{{ t('you') }}</p>
          <p class="mt-0.5 text-xs">{{ t('you_hint') }}</p>
        </NuxtLink>
      </Reveal>
    </ul>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "eyebrow": "Contributors",
    "title": "Made in the open.",
    "lead": "LDAP Studio is built by the people below. Bug fixes, features and translations are welcome.",
    "commits": "no commits | 1 commit | {n} commits",
    "you": "You?",
    "you_hint": "open a pull request"
  },
  "pt": {
    "eyebrow": "Contribuidores",
    "title": "Feito em público.",
    "lead": "O LDAP Studio é construído pelas pessoas abaixo. Correções, novas funções e traduções são bem-vindas.",
    "commits": "nenhum commit | 1 commit | {n} commits",
    "you": "Você?",
    "you_hint": "abra um pull request"
  }
}
</i18n>
