<script setup lang="ts">
  defineProps({
    title: { type: String, default: 'LDAP Studio' },
  })

  const ICONS: Record<EntryKind, string> = {
    domain: 'ph:globe-fill',
    unit: 'ph:folder-fill',
    person: 'ph:user-fill',
    group: 'ph:users-three-fill',
    service: 'ph:gear-six-fill',
  }

  const SIDEBAR_TOOLS = [
    'ph:plus',
    'ph:tray-arrow-down',
    'ph:export',
    'ph:copy',
    'ph:trash',
    'ph:article',
    'ph:brackets-curly',
    'ph:table',
  ]

  const DETAIL_TOOLS = [
    ['ph:plus', 'ph:pencil-simple', 'ph:trash'],
    ['ph:arrow-bend-up-right', 'ph:copy', 'ph:export', 'ph:clipboard-text', 'ph:bookmark-simple'],
    ['ph:clock-counter-clockwise', 'ph:arrow-clockwise'],
  ]

  const { t } = useI18n({ useScope: 'local' })

  const root = SAMPLE_DIRECTORY
  const query = ref('')
  const attributeQuery = ref('')
  const selected = ref<SampleEntry>(root.children[0]?.children[0] ?? root)
  const expanded = ref<string[]>([root.dn, ...root.children.slice(0, 1).map((child) => child.dn)])
  const operations = ref(3)

  const items = computed<SampleEntry[]>(() => {
    if (!query.value) return [root]

    const children = root.children
      .map((child) => filterDirectory(child, query.value))
      .filter((child): child is SampleEntry => child !== null)

    return [{ ...root, children }]
  })

  const attributes = computed(() => {
    const needle = attributeQuery.value.toLowerCase()

    return selected.value.attributes
      .filter(([name, value]) => !needle || `${name} ${value}`.toLowerCase().includes(needle))
      .toSorted(([a], [b]) => a.localeCompare(b, 'en', { sensitivity: 'base' }))
  })

  watch(query, () => {
    if (query.value) expanded.value = items.value.flatMap(collectDns)
  })

  function childrenOf(entry: SampleEntry): SampleEntry[] | undefined {
    return entry.children.length > 0 ? entry.children : undefined
  }

  function isContainer(entry: SampleEntry): boolean {
    return entry.kind === 'domain' || entry.kind === 'unit'
  }

  function photoStyle(photo: SamplePhoto): Record<string, string> {
    return {
      background: `linear-gradient(135deg, oklch(0.72 0.13 ${photo.hue}), oklch(0.5 0.15 ${photo.hue + 40}))`,
    }
  }

  function selectEntry(value: unknown): void {
    if (!value || value === selected.value) return

    selected.value = value as SampleEntry
    attributeQuery.value = ''
    operations.value += 1
  }
</script>

<template>
  <AppWindow :title="title" class="h-[26rem] text-left sm:h-[32rem]">
    <template #sidebar>
      <div class="flex shrink-0 items-center gap-2 px-3 pb-2 text-[0.8rem] text-fg/70">
        <div aria-hidden="true" class="hidden items-center gap-2 sm:flex">
          <Icon v-for="icon in SIDEBAR_TOOLS" :key="icon" :name="icon" class="shrink-0" />
        </div>
        <label class="relative block min-w-[5rem] flex-1">
          <span class="sr-only">{{ t('filter') }}</span>
          <input
            v-model="query"
            type="search"
            :placeholder="t('filter')"
            class="h-6 w-full rounded-md bg-white/10 px-2 text-[0.75rem] text-fg placeholder:text-fg/45 focus-visible:outline-accent" />
        </label>
        <span aria-hidden="true" class="hidden sm:flex">
          <Icon name="ph:sliders-horizontal" />
        </span>
      </div>

      <TreeRoot
        v-slot="{ flattenItems }"
        v-model:expanded="expanded"
        :model-value="selected"
        :items="items"
        :get-key="(entry) => entry.dn"
        :get-children="childrenOf"
        class="min-h-0 flex-1 overflow-y-auto px-1.5 pb-1.5 text-[0.8rem]"
        @update:model-value="selectEntry">
        <TreeItem
          v-for="item in flattenItems"
          :key="item._id"
          v-slot="{ isExpanded }"
          v-bind="item.bind"
          :style="{ paddingLeft: `${0.4 + item.level * 0.85}rem` }"
          class="flex cursor-default items-center gap-1.5 rounded-md py-[0.32rem] pr-2 font-medium outline-none focus-visible:ring-2 focus-visible:ring-accent data-[selected]:bg-white/[0.12]">
          <Icon
            name="ph:caret-right-bold"
            class="shrink-0 text-[0.6rem] text-fg/55 transition-transform duration-200 ease-apple"
            :class="[isExpanded && 'rotate-90', !item.hasChildren && 'invisible']" />
          <Icon :name="ICONS[item.value.kind]" class="shrink-0 text-[1rem] text-[#3b8cff]" />
          <span class="truncate">
            {{ item.value.rdn }}
            <template v-if="isContainer(item.value)">({{ item.value.children.length }})</template>
          </span>
        </TreeItem>
      </TreeRoot>
    </template>

    <div class="flex items-center gap-3 border-b border-white/[0.08] px-4 pb-3.5 sm:px-5">
      <AnimatePresence mode="wait" :initial="false">
        <Motion
          :key="selected.dn"
          class="flex min-w-0 items-center gap-3"
          :initial="{ opacity: 0, x: 6 }"
          :animate="{ opacity: 1, x: 0 }"
          :exit="{ opacity: 0 }"
          :transition="{ type: 'spring', bounce: 0, duration: 0.25 }">
          <span
            v-if="selected.photo"
            aria-hidden="true"
            class="grid size-9 shrink-0 place-items-center rounded-full text-[0.8rem] font-semibold text-white"
            :style="photoStyle(selected.photo)">
            {{ selected.photo.initials }}
          </span>
          <span v-else class="grid size-9 shrink-0 place-items-center text-[1.9rem] text-[#3b8cff]">
            <Icon :name="ICONS[selected.kind]" />
          </span>
          <span class="min-w-0">
            <span class="block truncate text-lg leading-tight font-bold">{{ selected.rdn }}</span>
            <span class="block truncate text-[0.7rem] text-fg/50">{{ selected.dn }}</span>
          </span>
        </Motion>
      </AnimatePresence>
    </div>

    <div class="flex items-center gap-3 border-b border-white/[0.08] px-4 py-2 sm:px-5">
      <div aria-hidden="true" class="flex items-center gap-3.5 text-[0.95rem] text-fg/55">
        <span
          v-for="(group, index) in DETAIL_TOOLS"
          :key="index"
          class="items-center gap-3.5"
          :class="index > 0 ? 'hidden sm:flex' : 'flex'">
          <span v-if="index > 0" class="h-4 w-px bg-white/10" />
          <Icon v-for="icon in group" :key="icon" :name="icon" class="shrink-0" />
        </span>
      </div>
      <label class="ml-auto block w-full max-w-[11rem] min-w-0">
        <span class="sr-only">{{ t('search_attributes') }}</span>
        <input
          v-model="attributeQuery"
          type="search"
          :placeholder="t('filter')"
          class="h-6 w-full rounded-md bg-white/[0.08] px-2 text-[0.75rem] text-fg placeholder:text-fg/45 focus-visible:outline-accent" />
      </label>
    </div>

    <div class="min-h-0 flex-1 overflow-y-auto px-1.5 pb-2 sm:px-2">
      <table class="w-full table-fixed text-left text-[0.8rem]">
        <thead>
          <tr class="border-b border-white/[0.08] text-xs text-fg/75">
            <th class="w-2/5 border-r border-white/[0.08] px-2 py-1.5 font-semibold">
              <span class="flex items-center justify-between">
                {{ t('attribute') }}
                <Icon aria-hidden="true" name="ph:caret-up" class="text-fg/50" />
              </span>
            </th>
            <th class="px-2 py-1.5 font-semibold">{{ t('value') }}</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="([name, value], index) in attributes"
            :key="`${selected.dn}-${name}-${index}`"
            class="even:bg-white/[0.05]">
            <td class="truncate rounded-l-md px-2 py-1.5">{{ name }}</td>
            <td class="truncate rounded-r-md px-2 py-1.5 text-fg/85">
              <span
                v-if="name === 'jpegPhoto' && selected.photo"
                role="img"
                :aria-label="value"
                class="my-0.5 grid size-14 place-items-center rounded-md text-base font-semibold text-white"
                :style="photoStyle(selected.photo)">
                {{ selected.photo.initials }}
              </span>
              <template v-else>{{ value }}</template>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <template #footer>
      <div
        class="flex h-8 shrink-0 items-center gap-2 border-t border-white/[0.08] px-3 text-[0.7rem] text-fg/55">
        <Icon aria-hidden="true" name="ph:caret-right-bold" class="shrink-0 text-[0.55rem]" />
        <Icon aria-hidden="true" name="ph:list-bullets" class="shrink-0 text-[0.85rem]" />
        <span class="shrink-0 font-semibold text-fg/85">{{ t('operation_log') }}</span>
        <span
          class="shrink-0 rounded-full bg-white/10 px-1.5 text-[0.65rem] text-fg/80 tabular-nums">
          {{ operations }}
        </span>
        <span class="hidden min-w-0 truncate sm:block">· search {{ selected.dn }}</span>
        <span class="ml-auto hidden shrink-0 sm:block">⇧⌘Y</span>
      </div>
    </template>
  </AppWindow>
</template>

<i18n lang="json">
{
  "en": {
    "filter": "Search",
    "search_attributes": "Search attributes",
    "attribute": "Attribute",
    "value": "Value",
    "operation_log": "Operation Log"
  },
  "pt": {
    "filter": "Buscar",
    "search_attributes": "Buscar atributos",
    "attribute": "Atributo",
    "value": "Valor",
    "operation_log": "Log de operações"
  }
}
</i18n>
