<script setup lang="ts">
  const MAX_TILT = 7

  const reducedMotion = usePreferredReducedMotion()
  const rotateX = useSpring(0, { stiffness: 220, damping: 22 })
  const rotateY = useSpring(0, { stiffness: 220, damping: 22 })
  const glare = ref({ x: 50, y: 0, opacity: 0 })

  function onPointerMove(event: PointerEvent): void {
    if (event.pointerType !== 'mouse' || reducedMotion.value === 'reduce') return

    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect()
    const x = (event.clientX - rect.left) / rect.width
    const y = (event.clientY - rect.top) / rect.height

    rotateY.set((x - 0.5) * MAX_TILT * 2)
    rotateX.set((0.5 - y) * MAX_TILT * 2)
    glare.value = { x: x * 100, y: y * 100, opacity: 1 }
  }

  function onPointerLeave(): void {
    rotateX.set(0)
    rotateY.set(0)
    glare.value = { ...glare.value, opacity: 0 }
  }
</script>

<template>
  <Motion
    :style="{ rotateX, rotateY, transformPerspective: 1000 }"
    class="glass relative h-full overflow-hidden rounded-3xl"
    @pointermove="onPointerMove"
    @pointerleave="onPointerLeave">
    <div
      aria-hidden="true"
      class="pointer-events-none absolute inset-0 transition-opacity duration-300"
      :style="{
        opacity: glare.opacity,
        background: `radial-gradient(28rem circle at ${glare.x}% ${glare.y}%, var(--accent-soft), transparent 60%)`,
      }" />
    <div class="relative h-full">
      <slot />
    </div>
  </Motion>
</template>
