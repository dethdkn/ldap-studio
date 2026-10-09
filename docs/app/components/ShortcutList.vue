<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const groups = computed(() => [
    {
      title: t('directory'),
      items: [
        { label: 'Go to DN…', keys: '⌘L' },
        { label: 'Refresh', keys: '⌘R' },
        { label: 'Bookmark Entry', keys: '⌘D' },
        { label: 'Advanced Search…', keys: '⇧⌘F' },
        { label: 'Server Info…', keys: '⌘I' },
        { label: 'Run LDIF', keys: '⇧⌘R' },
      ],
    },
    {
      title: t('entries'),
      items: [
        { label: 'New Entry…', keys: '⌘N' },
        { label: 'Edit Entry…', keys: '⌘E' },
        { label: 'Rename…', keys: '⇧⌘E' },
        { label: 'Move to…', keys: '⇧⌘M' },
        { label: 'Copy to…', keys: '⇧⌘D' },
        { label: 'Copy DN', keys: '⇧⌘C' },
        { label: 'Copy as LDIF', keys: '⌥⇧⌘C' },
        { label: 'Delete Entry', keys: '⌘⌫' },
      ],
    },
    {
      title: t('attributes'),
      items: [
        { label: 'Add Attribute…', keys: '⌥⌘O' },
        { label: 'Edit Value…', keys: '⌥⌘E' },
        { label: 'View Value', keys: '⌘J' },
        { label: 'Jump to Schema', keys: '⇧⌘S' },
        { label: 'Set Password…', keys: '⇧⌘K' },
        { label: 'Set Photo…', keys: '⇧⌘I' },
        { label: 'Edit Members…', keys: '⇧⌘U' },
        { label: 'Test Bind…', keys: '⇧⌘B' },
      ],
    },
  ])
</script>

<template>
  <div class="grid gap-4 md:grid-cols-3">
    <Reveal
      v-for="(group, index) in groups"
      :key="group.title"
      :delay="index * 0.08"
      class="card p-7">
      <h3 class="text-sm font-semibold text-accent-ink">{{ group.title }}</h3>
      <ul class="mt-4 divide-y divide-line">
        <li
          v-for="item in group.items"
          :key="item.label"
          class="flex items-center justify-between gap-3 py-2.5 text-sm">
          <span>{{ item.label }}</span>
          <Kbd :keys="item.keys" />
        </li>
      </ul>
    </Reveal>
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "directory": "Directory",
    "entries": "Entries",
    "attributes": "Attributes"
  },
  "pt": {
    "directory": "Diretório",
    "entries": "Entradas",
    "attributes": "Atributos"
  }
}
</i18n>
