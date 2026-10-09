<script setup lang="ts">
  const props = defineProps({
    name: { type: String as PropType<SectionName>, required: true },
    tone: { type: String as PropType<SectionTone>, default: 'light' },
  })

  const section = useTemplateRef<HTMLElement>('section')
  useSectionAnchor(props.name, section)
</script>

<template>
  <section ref="section" :data-tone="tone" :class="`tone-${tone}`" class="relative bg-bg text-fg">
    <div class="mx-auto w-full max-w-[64rem] px-5 py-28 sm:px-8 lg:py-40">
      <slot />
    </div>
  </section>
</template>
