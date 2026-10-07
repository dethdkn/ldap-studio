<script setup lang="ts">
  const props = defineProps({
    entry: { type: String, required: true },
    icon: { type: String, required: true },
    title: { type: String, required: true },
    text: { type: String, required: true },
    points: { type: Array as PropType<string[]>, default: () => [] },
  })

  const { focusEntry } = useSections()
</script>

<template>
  <TiltCard @pointerenter="focusEntry(props.entry)" @pointerleave="focusEntry(null)">
    <article class="flex h-full flex-col p-7">
      <div class="flex items-center justify-between">
        <span class="grid size-11 place-items-center rounded-2xl bg-accent-soft text-accent-ink">
          <Icon :name="icon" class="text-xl" />
        </span>
        <span class="font-mono text-[0.7rem] text-muted">cn={{ entry }}</span>
      </div>

      <h3 class="type-title mt-6 text-xl">{{ title }}</h3>
      <p class="mt-3 mb-6 leading-relaxed text-muted">{{ text }}</p>

      <ul class="mt-auto space-y-2 border-t border-line pt-5">
        <li v-for="point in points" :key="point" class="flex items-start gap-2.5 text-sm">
          <Icon name="ph:check-circle-fill" class="mt-0.5 shrink-0 text-accent" />
          {{ point }}
        </li>
      </ul>
    </article>
  </TiltCard>
</template>
