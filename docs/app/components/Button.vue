<script setup lang="ts">
  import type { RouteLocationRaw } from 'vue-router'

  defineProps({
    to: { type: [String, Object] as PropType<RouteLocationRaw>, required: true },
    icon: { type: String, default: '' },
    variant: { type: String as PropType<'primary' | 'ghost' | 'link'>, default: 'primary' },
    external: { type: Boolean, default: false },
  })

  const VARIANTS = {
    primary: 'h-12 rounded-full bg-accent px-6 text-white hover:bg-[#0077ed]',
    ghost:
      'h-12 rounded-full px-6 text-accent-ink ring-1 ring-accent-ink ring-inset hover:bg-accent-ink hover:text-bg',
    link: 'h-12 text-accent-ink hover:underline',
  }
</script>

<template>
  <NuxtLink
    :to="to"
    :external="external"
    :target="external ? '_blank' : undefined"
    class="group inline-flex items-center justify-center gap-2 text-[1.0625rem] font-normal tracking-[-0.022em] transition duration-200 ease-out select-none active:scale-[0.97]"
    :class="VARIANTS[variant]">
    <Icon v-if="icon" :name="icon" class="text-lg" />
    <slot />
    <Icon
      v-if="variant === 'link'"
      name="ph:caret-right-bold"
      class="text-sm transition-transform duration-200 group-hover:translate-x-0.5" />
  </NuxtLink>
</template>
