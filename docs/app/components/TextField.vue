<script setup lang="ts">
  defineProps({
    label: { type: String, required: true },
    placeholder: { type: String, default: '' },
    disabled: { type: Boolean, default: false },
  })

  const model = defineModel<string>({ required: true })
</script>

<template>
  <input
    v-model="model"
    type="text"
    :aria-label="label"
    :placeholder="placeholder"
    :disabled="disabled"
    spellcheck="false"
    autocomplete="off"
    class="h-10 w-full rounded-xl border border-line bg-surface-solid px-3 font-mono text-[0.8rem] text-fg transition placeholder:text-muted/70 hover:border-accent/50 disabled:opacity-40" />
</template>
