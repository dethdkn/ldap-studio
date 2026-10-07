<script setup lang="ts">
  const ICONS: Record<EntryKind, string> = {
    domain: 'ph:globe-hemisphere-west',
    unit: 'ph:folder-simple-fill',
    person: 'ph:user-fill',
    group: 'ph:users-three-fill',
    service: 'ph:gear-six-fill',
  }

  const { t } = useI18n({ useScope: 'local' })

  const root = SAMPLE_DIRECTORY
  const query = ref('')
  const selected = ref<SampleEntry>(root.children[0]?.children[0] ?? root)
  const expanded = ref<string[]>([root.dn, ...root.children.slice(0, 1).map((child) => child.dn)])

  const items = computed<SampleEntry[]>(() => {
    if (!query.value) return [root]

    const children = root.children
      .map((child) => filterDirectory(child, query.value))
      .filter((child): child is SampleEntry => child !== null)

    return [{ ...root, children }]
  })

  watch(query, () => {
    if (query.value) expanded.value = items.value.flatMap(collectDns)
  })

  function childrenOf(entry: SampleEntry): SampleEntry[] | undefined {
    return entry.children.length > 0 ? entry.children : undefined
  }

  function selectEntry(value: unknown): void {
    if (value) selected.value = value as SampleEntry
  }
</script>

<template>
  <div class="glass grid grid-cols-1 overflow-hidden rounded-3xl md:grid-cols-[19rem_1fr]">
    <div class="border-b border-line p-4 md:border-r md:border-b-0">
      <div class="relative">
        <Icon
          name="ph:magnifying-glass"
          class="absolute top-1/2 left-3 -translate-y-1/2 text-muted" />
        <input
          v-model="query"
          type="search"
          :aria-label="t('filter')"
          :placeholder="t('filter')"
          class="h-10 w-full rounded-xl border border-line bg-surface-solid pr-3 pl-9 text-sm transition placeholder:text-muted/70 hover:border-accent/50" />
      </div>

      <TreeRoot
        v-slot="{ flattenItems }"
        v-model:expanded="expanded"
        :model-value="selected"
        :items="items"
        :get-key="(entry) => entry.dn"
        :get-children="childrenOf"
        class="mt-3 max-h-80 overflow-y-auto text-sm"
        @update:model-value="selectEntry">
        <TreeItem
          v-for="item in flattenItems"
          :key="item._id"
          v-slot="{ isExpanded, isSelected }"
          v-bind="item.bind"
          :style="{ paddingLeft: `${item.level * 0.85}rem` }"
          class="flex cursor-pointer items-center gap-2 rounded-lg py-1.5 pr-2 outline-none hover:bg-accent-soft focus-visible:ring-2 focus-visible:ring-accent data-[selected]:bg-accent data-[selected]:text-white">
          <Icon
            name="ph:caret-right-bold"
            class="shrink-0 text-xs transition-transform"
            :class="[isExpanded && 'rotate-90', !item.hasChildren && 'invisible']" />
          <Icon
            :name="ICONS[item.value.kind]"
            class="shrink-0"
            :class="!isSelected && 'text-accent'" />
          <span class="truncate font-mono text-xs">{{ item.value.rdn }}</span>
          <span v-if="item.hasChildren" class="ml-auto font-mono text-[0.65rem] opacity-60">
            {{ item.value.children.length }}
          </span>
        </TreeItem>
      </TreeRoot>
    </div>

    <div class="min-w-0 p-5 sm:p-7">
      <div class="flex items-center gap-4">
        <span
          class="grid size-12 shrink-0 place-items-center rounded-2xl bg-accent text-2xl text-white">
          <Icon :name="ICONS[selected.kind]" />
        </span>
        <div class="min-w-0">
          <p class="truncate text-xl font-semibold">{{ selected.rdn }}</p>
          <p class="truncate font-mono text-xs text-muted">{{ selected.dn }}</p>
        </div>
      </div>

      <table class="mt-6 w-full text-left text-sm">
        <thead>
          <tr class="border-b border-line text-xs text-muted">
            <th class="py-2 pr-4 font-medium">{{ t('attribute') }}</th>
            <th class="py-2 font-medium">{{ t('value') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="([name, value], index) in selected.attributes"
            :key="index"
            class="even:bg-bg-deep/50">
            <td class="py-2 pr-4 font-mono text-xs text-accent-ink">{{ name }}</td>
            <td class="py-2 font-mono text-xs break-all">{{ value }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "filter": "Filter the tree",
    "attribute": "Attribute",
    "value": "Value"
  },
  "pt": {
    "filter": "Filtrar a árvore",
    "attribute": "Atributo",
    "value": "Valor"
  }
}
</i18n>
