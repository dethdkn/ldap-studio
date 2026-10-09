<script setup lang="ts">
  defineProps({
    as: { type: String as PropType<'div' | 'li'>, default: 'div' },
    delay: { type: Number, default: 0 },
  })
</script>

<template>
  <Motion
    :as="as"
    :initial="{ opacity: 0, y: 32 }"
    :while-in-view="{ opacity: 1, y: 0 }"
    :in-view-options="{ once: true, margin: '0px 0px -12% 0px' }"
    :transition="{ type: 'spring', bounce: 0, duration: 1, delay }">
    <slot />
  </Motion>
</template>
