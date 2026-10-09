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
  const group = useId()

  function select(value: unknown): void {
    if (typeof value === 'string' && value) model.value = value as T
  }
</script>

<template>
  <ToggleGroupRoot
    :model-value="model"
    type="single"
    :aria-label="label"
    class="inline-flex flex-wrap gap-0.5 rounded-[0.6rem] bg-fg/[0.07] p-0.5"
    @update:model-value="select">
    <ToggleGroupItem
      v-for="item in items"
      :key="item.value"
      :value="item.value"
      class="relative rounded-lg px-3 py-1 text-[0.8rem] font-medium text-fg/70 transition-colors duration-200 hover:text-fg data-[state=on]:text-fg">
      <Motion
        v-if="model === item.value"
        :layout-id="`segment-${group}`"
        class="absolute inset-0 rounded-[0.45rem] bg-thumb shadow-[0_1px_3px_rgb(0_0_0/0.12),0_0_0_0.5px_rgb(0_0_0/0.04)]"
        :transition="{ type: 'spring', bounce: 0, duration: 0.35 }" />
      <span class="relative">{{ item.label }}</span>
    </ToggleGroupItem>
  </ToggleGroupRoot>
</template>
