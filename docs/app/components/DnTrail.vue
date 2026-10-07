<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const { dn } = useSections()

  function hashOf(rdn: string): string {
    if (rdn.startsWith('ou=')) return `#${rdn.slice(3)}`
    if (rdn.startsWith('cn=')) return ''

    return '#top'
  }
</script>

<template>
  <nav :aria-label="t('label')" class="flex min-w-0 items-center overflow-hidden font-mono text-xs">
    <AnimatePresence mode="popLayout" :initial="false">
      <Motion
        v-for="(rdn, index) in dn"
        :key="rdn"
        layout
        as="span"
        class="flex shrink-0 items-center"
        :initial="{ opacity: 0, y: -10, filter: 'blur(4px)' }"
        :animate="{ opacity: 1, y: 0, filter: 'blur(0px)' }"
        :exit="{ opacity: 0, y: 10, filter: 'blur(4px)' }"
        :transition="{ type: 'spring', bounce: 0, duration: 0.45 }">
        <NuxtLink
          v-if="hashOf(rdn)"
          :to="{ hash: hashOf(rdn) }"
          class="rounded px-0.5 transition-colors hover:text-accent-ink"
          :class="index === 0 ? 'text-fg' : 'text-muted'">
          {{ rdn }}
        </NuxtLink>
        <span v-else class="px-0.5 text-accent-ink">{{ rdn }}</span>
        <span v-if="index < dn.length - 1" class="text-muted/60">,</span>
      </Motion>
    </AnimatePresence>
  </nav>
</template>

<i18n lang="json">
{
  "en": {
    "label": "Where you are on this page"
  },
  "pt": {
    "label": "Onde você está nesta página"
  }
}
</i18n>
