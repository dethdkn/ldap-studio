<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const mode = ref('before')

  const modes = computed(() => [
    { label: t('before'), value: 'before' },
    { label: t('now'), value: 'now' },
  ])

  const steps = computed(() =>
    mode.value === 'before'
      ? [
          { icon: 'ph:desktop-tower', text: t('before_boot') },
          { icon: 'ph:hourglass-medium', text: t('before_wait') },
          { icon: 'ph:windows-logo', text: t('before_open') },
          { icon: 'ph:pencil-simple-line', text: t('edit') },
          { icon: 'ph:clipboard-text', text: t('before_copy') },
        ]
      : [
          { icon: 'ph:rocket-launch', text: t('now_open') },
          { icon: 'ph:cursor-click', text: t('now_connect') },
          { icon: 'ph:pencil-simple-line', text: t('edit') },
        ],
  )
</script>

<template>
  <div class="glass rounded-3xl p-5 sm:p-7">
    <div class="flex flex-wrap items-center justify-between gap-4">
      <p class="font-mono text-xs text-muted">{{ t('title') }}</p>
      <Segmented v-model="mode" :items="modes" :label="t('title')" />
    </div>

    <ol class="mt-6 space-y-2">
      <AnimatePresence mode="popLayout" :initial="false">
        <Motion
          v-for="(step, index) in steps"
          :key="mode + step.text"
          as="li"
          layout
          class="flex items-center gap-4 rounded-2xl border border-line bg-surface-solid/60 px-4 py-3.5"
          :initial="{ opacity: 0, x: mode === 'now' ? 24 : -24 }"
          :animate="{ opacity: 1, x: 0 }"
          :exit="{ opacity: 0, scale: 0.96 }"
          :transition="{ type: 'spring', bounce: 0, duration: 0.5, delay: index * 0.05 }">
          <span class="w-5 font-mono text-xs text-muted">{{ index + 1 }}</span>
          <Icon
            :name="step.icon"
            class="text-xl"
            :class="mode === 'now' ? 'text-accent' : 'text-muted'" />
          <span class="text-[0.95rem]">{{ step.text }}</span>
        </Motion>
      </AnimatePresence>
    </ol>
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Editing one entry",
    "before": "Before",
    "now": "With LDAP Studio",
    "before_boot": "Boot the Windows virtual machine",
    "before_wait": "Wait for Windows to start and log in",
    "before_open": "Open LDAP Admin and connect",
    "edit": "Find the entry and edit it",
    "before_copy": "Copy the result back to the Mac",
    "now_open": "Open LDAP Studio",
    "now_connect": "Double-click a saved connection"
  },
  "pt": {
    "title": "Editando uma entrada",
    "before": "Antes",
    "now": "Com o LDAP Studio",
    "before_boot": "Ligar a máquina virtual com Windows",
    "before_wait": "Esperar o Windows iniciar e fazer login",
    "before_open": "Abrir o LDAP Admin e conectar",
    "edit": "Encontrar a entrada e editar",
    "before_copy": "Copiar o resultado de volta para o Mac",
    "now_open": "Abrir o LDAP Studio",
    "now_connect": "Dar dois cliques numa conexão salva"
  }
}
</i18n>
