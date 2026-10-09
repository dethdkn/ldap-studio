<script setup lang="ts">
  defineProps({
    rdn: { type: String, required: true },
    title: { type: String, required: true },
    lead: { type: String, default: '' },
    as: { type: String as PropType<'h1' | 'h2'>, default: 'h2' },
  })
</script>

<template>
  <div class="max-w-2xl">
    <Reveal>
      <p class="mb-5 flex items-center gap-2 font-mono text-xs text-accent-ink">
        <span class="size-1.5 rounded-full bg-accent" />
        {{ rdn }}
      </p>
    </Reveal>

    <Reveal :delay="0.05">
      <component :is="as" class="type-title text-4xl text-balance sm:text-5xl lg:text-6xl">
        {{ title }}
      </component>
    </Reveal>

    <Reveal v-if="lead" :delay="0.1">
      <p class="mt-6 text-lg leading-relaxed text-pretty text-muted">{{ lead }}</p>
    </Reveal>
  </div>
</template>
