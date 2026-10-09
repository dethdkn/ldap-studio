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
  <div class="card p-6 sm:p-8">
    <div class="flex flex-wrap items-center justify-between gap-4">
      <p class="text-sm font-semibold">{{ t('title') }}</p>
      <Segmented v-model="mode" :items="modes" :label="t('title')" />
    </div>

    <div class="mt-6 min-h-[17.5rem]">
      <AnimatePresence mode="wait" :initial="false">
        <Motion
          :key="mode"
          as="ol"
          class="space-y-2"
          :initial="{ opacity: 0 }"
          :animate="{ opacity: 1 }"
          :exit="{ opacity: 0 }"
          :transition="{ duration: 0.18 }">
          <Motion
            v-for="(step, index) in steps"
            :key="step.text"
            as="li"
            class="flex items-center gap-4 rounded-2xl bg-surface-solid px-4 py-3.5"
            :initial="{ opacity: 0, y: 10 }"
            :animate="{ opacity: 1, y: 0 }"
            :transition="{ type: 'spring', bounce: 0, duration: 0.5, delay: index * 0.06 }">
            <span class="w-4 text-xs text-muted tabular-nums">{{ index + 1 }}</span>
            <Icon
              :name="step.icon"
              class="text-xl"
              :class="mode === 'now' ? 'text-accent' : 'text-muted'" />
            <span class="text-[0.95rem]">{{ step.text }}</span>
          </Motion>
        </Motion>
      </AnimatePresence>
    </div>
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
