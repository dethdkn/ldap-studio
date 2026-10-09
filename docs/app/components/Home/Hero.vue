<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const { scrollToSection } = useSectionScroll()
  const reducedMotion = useReducedMotion()

  const section = useTemplateRef<HTMLElement>('section')
  const stage = useTemplateRef<HTMLElement>('stage')
  useSectionAnchor('top', section)

  const { scrollYProgress } = useScroll({ target: stage, offset: ['start end', 'start 0.25'] })
  const rotateX = useTransform(scrollYProgress, [0, 1], [28, 0])
  const scale = useTransform(scrollYProgress, [0, 1], [0.84, 1])
  const glow = useTransform(scrollYProgress, [0, 1], [0.25, 0.9])

  const windowStyle = computed(() =>
    reducedMotion.value ? {} : { rotateX, scale, transformPerspective: 1600 },
  )

  function enter(delay: number): Record<string, unknown> {
    return {
      initial: { opacity: 0, y: 24 },
      animate: { opacity: 1, y: 0 },
      transition: { type: 'spring', bounce: 0, duration: 1.1, delay },
    }
  }
</script>

<template>
  <section
    ref="section"
    data-tone="dark"
    class="tone-dark relative overflow-hidden bg-bg pt-32 pb-24 text-fg sm:pt-40">
    <div class="mx-auto flex max-w-[64rem] flex-col items-center px-5 text-center sm:px-8">
      <Motion
        :initial="{ opacity: 0, scale: 0.8 }"
        :animate="{ opacity: 1, scale: 1 }"
        :transition="{ type: 'spring', bounce: 0.25, duration: 1.2 }">
        <Logo :size="108" class="drop-shadow-[0_18px_40px_rgb(41_151_255/0.35)]" />
      </Motion>

      <Motion as="p" v-bind="enter(0.1)" class="type-eyebrow mt-8">LDAP Studio</Motion>

      <Motion as="h1" v-bind="enter(0.18)" class="type-hero mt-3 max-w-4xl text-balance">
        {{ t('title_start') }}
        <span class="text-gradient">{{ t('title_accent') }}</span>
        {{ t('title_end') }}
      </Motion>

      <Motion as="p" v-bind="enter(0.28)" class="type-lead mt-6 max-w-2xl">
        {{ t('lead') }}
      </Motion>

      <Motion
        v-bind="enter(0.36)"
        class="mt-9 flex flex-wrap items-center justify-center gap-x-6 gap-y-3">
        <DownloadButton>{{ t('download') }}</DownloadButton>
        <Button :to="LINKS.repo" external variant="link">{{ t('source') }}</Button>
      </Motion>

      <Motion as="p" v-bind="enter(0.44)" class="mt-6 text-xs text-muted">
        {{ t('requirements') }}
      </Motion>
    </div>

    <div ref="stage" class="relative mx-auto mt-20 max-w-[60rem] px-3 sm:px-8">
      <Motion
        aria-hidden="true"
        :style="reducedMotion ? { opacity: 0.8 } : { opacity: glow }"
        class="pointer-events-none absolute inset-x-[10%] top-[8%] bottom-0 rounded-full bg-[radial-gradient(closest-side,rgb(41_151_255/0.55),rgb(122_108_255/0.25)_55%,transparent)] blur-3xl" />
      <Motion :style="windowStyle" class="relative origin-top will-change-transform">
        <AppWindow :title="t('window_title')">
          <DemoTree />
        </AppWindow>
      </Motion>
      <p class="mt-6 flex items-center justify-center gap-2 text-xs text-muted">
        <Icon name="ph:cursor-click" class="text-sm" />
        {{ t('hint') }}
      </p>
    </div>

    <div class="mt-16 flex justify-center">
      <button
        type="button"
        class="flex items-center gap-1.5 text-sm text-accent-ink transition hover:underline"
        @click="scrollToSection('why')">
        {{ t('more') }}
        <Icon name="ph:caret-down-bold" class="text-xs" />
      </button>
    </div>
  </section>
</template>

<i18n lang="json">
{
  "en": {
    "title_start": "LDAP, finally",
    "title_accent": "native",
    "title_end": "on the Mac.",
    "lead": "Browse, search and edit any LDAP directory in a fast SwiftUI app built on OpenLDAP. No Java runtime, no Windows VM, no ldapsearch one-liners.",
    "download": "Download for macOS",
    "source": "Source on GitHub",
    "requirements": "macOS 26 or later · Apple Silicon · free and open source (MIT)",
    "window_title": "LDAP Studio — Example Research Lab",
    "hint": "This window works. Expand the tree, pick an entry, search.",
    "more": "Why it exists"
  },
  "pt": {
    "title_start": "LDAP, finalmente",
    "title_accent": "nativo",
    "title_end": "no Mac.",
    "lead": "Navegue, pesquise e edite qualquer diretório LDAP num app SwiftUI rápido, construído sobre o OpenLDAP. Sem runtime Java, sem VM com Windows, sem decorar comandos do ldapsearch.",
    "download": "Baixar para macOS",
    "source": "Código no GitHub",
    "requirements": "macOS 26 ou superior · Apple Silicon · gratuito e open source (MIT)",
    "window_title": "LDAP Studio — Example Research Lab",
    "hint": "Esta janela funciona. Abra a árvore, escolha uma entrada, pesquise.",
    "more": "Por que ele existe"
  }
}
</i18n>
