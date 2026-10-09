<script setup lang="ts">
  import type { MotionValue } from 'motion-v'

  const props = defineProps({
    progress: { type: Object as PropType<MotionValue<number>>, required: true },
    start: { type: Number, required: true },
    end: { type: Number, required: true },
  })

  const opacity = useTransform(props.progress, [props.start, props.end], [0.18, 1])
</script>

<template>
  <Motion as="span" :style="{ opacity }">
    <slot />
  </Motion>
</template>
