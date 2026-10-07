<script setup lang="ts">
  defineProps({
    label: { type: String, required: true },
  })

  const model = defineModel<boolean>({ default: false })
</script>

<template>
  <SwitchRoot
    v-model="model"
    :aria-label="label"
    class="relative h-6 w-10 shrink-0 rounded-full bg-line transition-colors duration-200 data-[state=checked]:bg-accent">
    <SwitchThumb
      class="block size-5 translate-x-0.5 rounded-full bg-white shadow transition-transform duration-200 data-[state=checked]:translate-x-[1.125rem]" />
  </SwitchRoot>
</template>
