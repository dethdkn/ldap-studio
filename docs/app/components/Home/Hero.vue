<script setup lang="ts">
  import { dragSpin, grabSpin, nudgeSpin, releaseSpin, spin } from '~/lib/three/spin'

  const DRAG_RADIANS_PER_PIXEL = 0.012

  const { t } = useI18n({ useScope: 'local' })
  const sceneReady = useSceneReady()

  const title = computed(() => [
    { text: t('title_start'), accent: false },
    { text: t('title_accent'), accent: true },
    { text: t('title_end'), accent: false },
  ])

  let lastX = 0
  let lastTime = 0

  function onPointerDown(event: PointerEvent): void {
    ;(event.currentTarget as HTMLElement).setPointerCapture(event.pointerId)
    grabSpin()
    lastX = event.clientX
    lastTime = event.timeStamp
  }

  function onPointerMove(event: PointerEvent): void {
    if (!spin.dragging) return

    dragSpin((event.clientX - lastX) * DRAG_RADIANS_PER_PIXEL, (event.timeStamp - lastTime) / 1000)
    lastX = event.clientX
    lastTime = event.timeStamp
  }

  function onKeydown(event: KeyboardEvent): void {
    if (event.key === 'ArrowLeft') nudgeSpin(-1)
    if (event.key === 'ArrowRight') nudgeSpin(1)
  }
</script>

<template>
  <section
    id="top"
    data-branch="top"
    class="relative mx-auto grid min-h-svh w-full max-w-7xl grid-cols-1 items-center gap-8 px-4 pt-24 pb-16 sm:px-8 lg:grid-cols-2">
    <div class="relative z-10 order-2 lg:order-1">
      <Reveal>
        <p
          class="glass mb-8 inline-flex items-center gap-2 rounded-full py-1.5 pr-4 pl-1.5 text-sm text-muted">
          <span
            class="rounded-full bg-accent px-2.5 py-0.5 font-mono text-[0.7rem] whitespace-nowrap text-white"
            >{{ ROOT_RDN }}</span
          >
          {{ t('eyebrow') }}
        </p>
      </Reveal>

      <h1 class="type-display text-[clamp(3rem,min(5.8vw,10.5svh),5.75rem)]">
        <Motion
          v-for="(part, index) in title"
          :key="part.text"
          as="span"
          class="mr-[0.22em] inline-block last:mr-0"
          :class="part.accent && 'text-accent [font-variation-settings:\'wdth\'_125]'"
          :initial="{ opacity: 0, y: '0.5em', filter: 'blur(12px)' }"
          :animate="{ opacity: 1, y: 0, filter: 'blur(0px)' }"
          :transition="{ type: 'spring', bounce: 0, duration: 1, delay: 0.15 + index * 0.12 }">
          {{ part.text }}
        </Motion>
      </h1>

      <Reveal :delay="0.5">
        <p class="mt-8 max-w-xl text-lg leading-relaxed text-pretty text-muted sm:text-xl">
          {{ t('lead') }}
        </p>
      </Reveal>

      <Reveal :delay="0.6" class="mt-10 flex flex-wrap gap-3">
        <Button :to="LINKS.download" external icon="ph:apple-logo-fill">{{ t('download') }}</Button>
        <Button :to="LINKS.repo" external icon="ph:github-logo" variant="ghost">{{
          t('source')
        }}</Button>
      </Reveal>

      <Reveal :delay="0.7">
        <p class="mt-8 font-mono text-xs leading-relaxed text-muted">{{ t('requirements') }}</p>
      </Reveal>
    </div>

    <div class="relative order-1 flex flex-col items-center lg:order-2">
      <div
        role="img"
        tabindex="0"
        :aria-label="t('icon_label')"
        class="grid aspect-square w-[min(70vw,30rem,58svh)] cursor-grab touch-pan-y place-items-center rounded-[4rem] select-none active:cursor-grabbing"
        @pointerdown="onPointerDown"
        @pointermove="onPointerMove"
        @pointerup="releaseSpin"
        @pointercancel="releaseSpin"
        @keydown="onKeydown">
        <Logo
          :size="220"
          class="transition duration-700"
          :class="sceneReady ? 'scale-75 opacity-0' : 'opacity-100'" />
      </div>
      <p
        class="flex items-center gap-2 font-mono text-[0.7rem] text-muted transition-opacity duration-700"
        :class="sceneReady ? 'opacity-100' : 'opacity-0'">
        <Icon name="ph:hand-grabbing" class="text-sm" />
        {{ t('drag_hint') }}
      </p>
    </div>

    <NuxtLink
      :to="{ hash: '#why' }"
      class="absolute bottom-6 left-1/2 hidden -translate-x-1/2 items-center gap-2 font-mono text-xs text-muted transition hover:text-fg lg:flex">
      <Icon name="ph:arrow-down" class="animate-bounce" />
      ou=why
    </NuxtLink>
  </section>
</template>

<i18n lang="json">
{
  "en": {
    "eyebrow": "An LDAP client for directory admins",
    "title_start": "LDAP, finally",
    "title_accent": "native",
    "title_end": "on the Mac.",
    "lead": "Browse, search and edit any LDAP directory in a fast SwiftUI app built on OpenLDAP. No Java runtime, no Windows VM, no ldapsearch one-liners.",
    "download": "Download for macOS",
    "source": "Source on GitHub",
    "requirements": "macOS 26 or later · Apple Silicon · free and open source (MIT)",
    "icon_label": "LDAP Studio app icon. Drag, or use the arrow keys, to spin it.",
    "drag_hint": "drag to spin"
  },
  "pt": {
    "eyebrow": "Um cliente LDAP para quem administra diretórios",
    "title_start": "LDAP, finalmente",
    "title_accent": "nativo",
    "title_end": "no Mac.",
    "lead": "Navegue, pesquise e edite qualquer diretório LDAP num app SwiftUI rápido, construído sobre o OpenLDAP. Sem runtime Java, sem VM com Windows, sem decorar comandos do ldapsearch.",
    "download": "Baixar para macOS",
    "source": "Código no GitHub",
    "requirements": "macOS 26 ou superior · Apple Silicon · gratuito e open source (MIT)",
    "icon_label": "Ícone do app LDAP Studio. Arraste, ou use as setas do teclado, para girar.",
    "drag_hint": "arraste para girar"
  }
}
</i18n>
