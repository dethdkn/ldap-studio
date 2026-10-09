<script setup lang="ts" generic="T extends string">
  interface SelectOption {
    label: string
    value: T
  }

  defineProps({
    options: { type: Array as PropType<SelectOption[]>, required: true },
    label: { type: String, required: true },
  })

  const model = defineModel<T>({ required: true })
</script>

<template>
  <div class="relative">
    <select
      v-model="model"
      :aria-label="label"
      class="h-10 w-full cursor-pointer appearance-none rounded-xl border border-line bg-surface-solid pr-8 pl-3 font-mono text-[0.8rem] text-fg transition hover:border-accent/50">
      <option v-for="option in options" :key="option.value" :value="option.value">
        {{ option.label }}
      </option>
    </select>
    <Icon
      name="ph:caret-down"
      class="pointer-events-none absolute top-1/2 right-3 -translate-y-1/2 text-muted" />
  </div>
</template>
