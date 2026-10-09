<script setup lang="ts">
  defineProps({
    title: { type: String, default: 'LDAP Studio' },
  })
</script>

<template>
  <div
    class="tone-dark overflow-hidden rounded-[0.9rem] bg-[#1e1e22] text-fg shadow-[0_0_0_1px_rgb(255_255_255/0.12),0_40px_120px_-20px_rgb(0_0_0/0.65)]">
    <div class="relative flex h-11 items-center border-b border-black/40 bg-[#26262b] px-4">
      <div aria-hidden="true" class="flex gap-2">
        <span class="size-3 rounded-full bg-[#ff5f57]" />
        <span class="size-3 rounded-full bg-[#febc2e]" />
        <span class="size-3 rounded-full bg-[#28c840]" />
      </div>
      <p class="absolute inset-x-24 truncate text-center text-[0.8rem] font-semibold text-fg/80">
        {{ title }}
      </p>
    </div>
    <slot />
  </div>
</template>
