<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const { focusEntry } = useSections()

  const tips = computed(() => [
    { icon: 'ph:cursor-click', text: t('tip_open') },
    { icon: 'ph:mouse-right-click', text: t('tip_menu') },
    { icon: 'ph:arrows-out-cardinal', text: t('tip_drag') },
  ])
</script>

<template>
  <PageSection id="guide">
    <SectionHeading rdn="ou=guide" :title="t('title')" :lead="t('lead')" />

    <Reveal
      :delay="0.15"
      class="mt-12"
      @pointerenter="focusEntry('connect')"
      @pointerleave="focusEntry(null)">
      <DemoConnection />
    </Reveal>

    <ul class="mt-6 grid gap-4 md:grid-cols-3">
      <Reveal
        v-for="(tip, index) in tips"
        :key="tip.icon"
        as="li"
        :delay="index * 0.08"
        class="glass flex gap-4 rounded-3xl p-6">
        <Icon :name="tip.icon" class="shrink-0 text-2xl text-accent" />
        <p class="leading-relaxed text-muted">{{ tip.text }}</p>
      </Reveal>
    </ul>

    <div class="mt-24" @pointerenter="focusEntry('shortcuts')" @pointerleave="focusEntry(null)">
      <Reveal>
        <h3 class="type-title text-3xl sm:text-4xl">{{ t('shortcuts_title') }}</h3>
        <p class="mt-4 max-w-xl text-lg text-muted">{{ t('shortcuts_lead') }}</p>
      </Reveal>
      <ShortcutList class="mt-10" />
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Your first connection.",
    "lead": "On the home window, click Add Connection…, fill in the fields and press Test before saving.",
    "tip_open": "Double-click a saved connection to open its directory in a new window.",
    "tip_menu": "Right-click any entry in the tree for every action you can take on it.",
    "tip_drag": "Select several entries and drag them onto another branch to move them.",
    "shortcuts_title": "Keep your hands on the keyboard.",
    "shortcuts_lead": "Every action lives in the menu bar, and most have a shortcut."
  },
  "pt": {
    "title": "Sua primeira conexão.",
    "lead": "Na janela inicial, clique em Add Connection…, preencha os campos e use Test antes de salvar.",
    "tip_open": "Dê dois cliques numa conexão salva para abrir o diretório numa nova janela.",
    "tip_menu": "Clique com o botão direito em qualquer entrada da árvore para ver tudo o que dá para fazer com ela.",
    "tip_drag": "Selecione várias entradas e arraste para outro ramo para movê-las.",
    "shortcuts_title": "Mãos no teclado.",
    "shortcuts_lead": "Toda ação está na barra de menus, e a maioria tem um atalho."
  }
}
</i18n>
