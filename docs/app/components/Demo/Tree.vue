<script setup lang="ts">
  const ICONS: Record<EntryKind, string> = {
    domain: 'ph:globe-simple',
    unit: 'ph:folder-simple-fill',
    person: 'ph:user-circle-fill',
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
  <div
    class="grid h-[26rem] grid-cols-[10.5rem_1fr] text-left sm:h-[30rem] sm:grid-cols-[16rem_1fr]">
    <div class="flex min-h-0 flex-col border-r border-black/40 bg-[#24243a]/60 p-2.5">
      <label class="relative block">
        <span class="sr-only">{{ t('filter') }}</span>
        <Icon
          name="ph:magnifying-glass"
          class="absolute top-1/2 left-2.5 -translate-y-1/2 text-sm text-fg/50" />
        <input
          v-model="query"
          type="search"
          :placeholder="t('filter')"
          class="h-7 w-full rounded-md bg-white/10 pr-2 pl-8 text-[0.8rem] text-fg placeholder:text-fg/45 focus-visible:outline-accent" />
      </label>

      <TreeRoot
        v-slot="{ flattenItems }"
        v-model:expanded="expanded"
        :model-value="selected"
        :items="items"
        :get-key="(entry) => entry.dn"
        :get-children="childrenOf"
        class="mt-2 min-h-0 flex-1 overflow-y-auto text-[0.8rem]"
        @update:model-value="selectEntry">
        <TreeItem
          v-for="item in flattenItems"
          :key="item._id"
          v-slot="{ isExpanded }"
          v-bind="item.bind"
          :style="{ paddingLeft: `${item.level * 0.75}rem` }"
          class="flex cursor-default items-center gap-1.5 rounded-md py-[0.3rem] pr-2 outline-none focus-visible:ring-2 focus-visible:ring-accent data-[selected]:bg-[#0a5fdb] data-[selected]:text-white">
          <Icon
            name="ph:caret-right-bold"
            class="shrink-0 text-[0.6rem] text-fg/60 transition-transform duration-200 ease-apple"
            :class="[isExpanded && 'rotate-90', !item.hasChildren && 'invisible']" />
          <Icon :name="ICONS[item.value.kind]" class="shrink-0 text-[0.95rem]" />
          <span class="truncate">{{ item.value.rdn }}</span>
        </TreeItem>
      </TreeRoot>
    </div>

    <div class="flex min-w-0 flex-col">
      <div class="flex items-center gap-3 border-b border-black/40 px-4 py-3.5 sm:px-5">
        <span class="grid size-10 shrink-0 place-items-center text-[2.1rem] text-[#3b8cff]">
          <Icon :name="ICONS[selected.kind]" />
        </span>
        <AnimatePresence mode="wait" :initial="false">
          <Motion
            :key="selected.dn"
            class="min-w-0"
            :initial="{ opacity: 0, x: 6 }"
            :animate="{ opacity: 1, x: 0 }"
            :exit="{ opacity: 0 }"
            :transition="{ type: 'spring', bounce: 0, duration: 0.25 }">
            <p class="truncate text-lg font-semibold">{{ selected.rdn }}</p>
            <p class="truncate text-xs text-fg/50">{{ selected.dn }}</p>
          </Motion>
        </AnimatePresence>
      </div>

      <div
        aria-hidden="true"
        class="flex items-center gap-4 border-b border-black/40 px-4 py-2 text-base text-fg/55 sm:px-5">
        <Icon name="ph:plus" />
        <Icon name="ph:pencil-simple" />
        <Icon name="ph:trash" />
        <span class="h-4 w-px bg-white/10" />
        <Icon name="ph:arrow-bend-up-right" />
        <Icon name="ph:copy" />
        <Icon name="ph:export" />
        <span class="h-4 w-px bg-white/10" />
        <Icon name="ph:arrow-clockwise" />
      </div>

      <div class="min-h-0 flex-1 overflow-y-auto px-2 py-2 sm:px-3">
        <table class="w-full table-fixed text-left text-[0.8rem]">
          <thead>
            <tr class="text-xs text-fg/60">
              <th class="w-2/5 px-2 py-1.5 font-semibold">{{ t('attribute') }}</th>
              <th class="px-2 py-1.5 font-semibold">{{ t('value') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="([name, value], index) in selected.attributes"
              :key="`${selected.dn}-${index}`"
              class="even:bg-white/[0.04]">
              <td class="truncate rounded-l-md px-2 py-1.5">{{ name }}</td>
              <td class="truncate rounded-r-md px-2 py-1.5 text-fg/85">{{ value }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "filter": "Search",
    "attribute": "Attribute",
    "value": "Value"
  },
  "pt": {
    "filter": "Buscar",
    "attribute": "Atributo",
    "value": "Valor"
  }
}
</i18n>
