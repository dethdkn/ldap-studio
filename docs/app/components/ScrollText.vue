<script setup lang="ts">
  const props = defineProps({
    text: { type: String, required: true },
  })

  const root = useTemplateRef<HTMLElement>('root')
  const reducedMotion = useReducedMotion()
  const { scrollYProgress } = useScroll({ target: root, offset: ['start 0.85', 'end 0.5'] })

  const words = computed(() => props.text.split(' '))
</script>

<template>
  <p ref="root" class="flex flex-wrap gap-x-[0.28em]">
    <span v-if="reducedMotion">{{ text }}</span>
    <template v-else>
      <ScrollWord
        v-for="(word, index) in words"
        :key="index"
        :progress="scrollYProgress"
        :start="index / words.length"
        :end="(index + 1) / words.length">
        {{ word }}
      </ScrollWord>
    </template>
  </p>
</template>
