<script setup lang="ts">
  defineProps({
    eyebrow: { type: String, default: '' },
    title: { type: String, required: true },
    lead: { type: String, default: '' },
    as: { type: String as PropType<'h1' | 'h2'>, default: 'h2' },
    center: { type: Boolean, default: false },
  })
</script>

<template>
  <div :class="center ? 'mx-auto max-w-3xl text-center' : 'max-w-3xl'">
    <Reveal v-if="eyebrow">
      <p class="type-eyebrow mb-3">{{ eyebrow }}</p>
    </Reveal>

    <Reveal :delay="0.05">
      <component :is="as" class="type-display text-balance">{{ title }}</component>
    </Reveal>

    <Reveal v-if="lead" :delay="0.1">
      <p class="type-lead mt-6" :class="center && 'mx-auto max-w-2xl'">{{ lead }}</p>
    </Reveal>
  </div>
</template>
