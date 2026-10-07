<script setup lang="ts" generic="T extends string">
  interface SegmentedItem {
    label: string
    value: T
  }

  defineProps({
    items: { type: Array as PropType<SegmentedItem[]>, required: true },
    label: { type: String, required: true },
  })

  const model = defineModel<T>({ required: true })

  function select(value: unknown): void {
    if (typeof value === 'string' && value) model.value = value as T
  }
</script>

<template>
  <ToggleGroupRoot
    :model-value="model"
    type="single"
    :aria-label="label"
    class="inline-flex flex-wrap gap-1 rounded-2xl border border-line bg-bg-deep/60 p-1"
    @update:model-value="select">
    <ToggleGroupItem
      v-for="item in items"
      :key="item.value"
      :value="item.value"
      class="rounded-xl px-3.5 py-2 text-sm font-medium text-muted transition duration-200 hover:text-fg active:scale-[0.97] data-[state=on]:bg-surface-solid data-[state=on]:text-fg data-[state=on]:shadow-sm">
      {{ item.label }}
    </ToggleGroupItem>
  </ToggleGroupRoot>
</template>
