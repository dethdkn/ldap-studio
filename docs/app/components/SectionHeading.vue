<script setup lang="ts">
  defineProps({
    rdn: { type: String, required: true },
    title: { type: String, required: true },
    lead: { type: String, default: '' },
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
      <h2 class="type-title text-4xl text-balance sm:text-5xl lg:text-6xl">{{ title }}</h2>
    </Reveal>

    <Reveal v-if="lead" :delay="0.1">
      <p class="mt-6 text-lg leading-relaxed text-pretty text-muted">{{ lead }}</p>
    </Reveal>
  </div>
</template>
