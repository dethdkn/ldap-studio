<script setup lang="ts">
  import type { MotionValue } from 'motion-v'

  const props = defineProps({
    progress: { type: Object as PropType<MotionValue<number>>, required: true },
    index: { type: Number, required: true },
    icon: { type: String, required: true },
    fill: { type: String, required: true },
  })

  const SPREAD = 128
  const reducedMotion = useReducedMotion()
  const y = useTransform(props.progress, [0, 1], [props.index * -14, props.index * -SPREAD])

  const style = computed(() => ({
    y: reducedMotion.value ? props.index * -SPREAD : y,
    zIndex: props.index,
  }))
</script>

<template>
  <Motion :style="style" class="absolute inset-x-0 bottom-0 flex justify-center">
    <div
      class="grid aspect-square w-[min(15rem,56vw)] [transform:rotateX(58deg)_rotateZ(-42deg)] place-items-center rounded-[2.2rem] shadow-[0_30px_60px_-20px_rgb(0_0_0/0.8),inset_0_1px_0_rgb(255_255_255/0.25)] ring-1 ring-white/15"
      :class="fill">
      <Icon :name="icon" class="[transform:rotateZ(42deg)] text-5xl text-white/90" />
    </div>
  </Motion>
</template>
