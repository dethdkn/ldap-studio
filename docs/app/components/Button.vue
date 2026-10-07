<script setup lang="ts">
  import type { RouteLocationRaw } from 'vue-router'

  defineProps({
    to: { type: [String, Object] as PropType<RouteLocationRaw>, required: true },
    icon: { type: String, default: '' },
    variant: { type: String as PropType<'primary' | 'ghost'>, default: 'primary' },
    external: { type: Boolean, default: false },
  })
</script>

<template>
  <NuxtLink
    :to="to"
    :external="external"
    :target="external ? '_blank' : undefined"
    class="inline-flex h-12 items-center justify-center gap-2 rounded-full px-6 text-[0.95rem] font-semibold transition duration-150 ease-out active:scale-[0.97]"
    :class="
      variant === 'primary'
        ? 'bg-accent text-white shadow-[0_10px_30px_-10px_var(--accent)] hover:brightness-110'
        : 'glass text-fg hover:border-accent/40'
    ">
    <Icon v-if="icon" :name="icon" class="text-lg" />
    <slot />
  </NuxtLink>
</template>
