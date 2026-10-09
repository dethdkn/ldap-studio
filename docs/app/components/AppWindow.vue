<script setup lang="ts">
  defineProps({
    title: { type: String, default: 'LDAP Studio' },
  })
</script>

<template>
  <div
    class="tone-dark flex flex-col overflow-hidden rounded-[1rem] bg-[#1e1e20] text-fg shadow-[0_0_0_1px_rgb(255_255_255/0.12),0_40px_120px_-20px_rgb(0_0_0/0.65)]">
    <div class="flex min-h-0 flex-1">
      <aside
        class="m-1.5 mr-0 flex w-[10.5rem] shrink-0 flex-col rounded-[0.8rem] bg-[#2b2b2f] shadow-[0_0_0_1px_rgb(255_255_255/0.06)] sm:w-[20rem]">
        <div class="flex h-11 shrink-0 items-center justify-between pr-1.5 pl-3.5">
          <div aria-hidden="true" class="flex gap-2">
            <span class="size-3 rounded-full bg-[#ff5f57]" />
            <span class="size-3 rounded-full bg-[#febc2e]" />
            <span class="size-3 rounded-full bg-[#28c840]" />
          </div>
          <span
            aria-hidden="true"
            class="grid size-8 place-items-center rounded-full bg-white/[0.08] text-base text-fg/80">
            <Icon name="ph:sidebar-simple" />
          </span>
        </div>
        <slot name="sidebar" />
      </aside>

      <div class="flex min-w-0 flex-1 flex-col">
        <p
          class="flex h-12 shrink-0 items-center truncate px-4 text-[0.9rem] font-semibold sm:px-5">
          {{ title }}
        </p>
        <slot />
      </div>
    </div>

    <slot name="footer" />
  </div>
</template>
