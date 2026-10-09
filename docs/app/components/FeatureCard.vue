<script setup lang="ts">
  defineProps({
    icon: { type: String, required: true },
    title: { type: String, required: true },
    text: { type: String, required: true },
    points: { type: Array as PropType<string[]>, default: () => [] },
    example: { type: String, default: '' },
  })
</script>

<template>
  <article
    class="card flex h-full flex-col p-7 transition duration-500 ease-apple hover:-translate-y-1 hover:shadow-[0_24px_48px_-24px_rgb(0_0_0/0.18)] sm:p-9">
    <Icon :name="icon" class="text-[2rem] text-accent" />
    <h3 class="type-title mt-5 text-[1.6rem]">{{ title }}</h3>
    <p class="mt-3 text-muted">{{ text }}</p>

    <pre
      v-if="example"
      class="well mt-6 px-4 py-3.5 font-mono text-[0.72rem] leading-relaxed [overflow-wrap:anywhere] whitespace-pre-wrap text-fg/80"
      >{{ example }}</pre>

    <ul v-if="points.length" class="mt-auto space-y-2 pt-6 text-sm">
      <li v-for="point in points" :key="point" class="flex items-start gap-2">
        <Icon name="ph:check-bold" class="mt-1 shrink-0 text-xs text-accent" />
        {{ point }}
      </li>
    </ul>
  </article>
</template>
