<script setup lang="ts">
  defineProps({
    command: { type: String, required: true },
  })
</script>

<template>
  <div
    class="flex items-center gap-2 rounded-2xl border border-line bg-bg-deep/70 py-1.5 pr-1.5 pl-4">
    <span class="font-mono text-xs text-accent-ink select-none">$</span>
    <code class="min-w-0 flex-1 overflow-x-auto py-2 font-mono text-xs whitespace-nowrap">{{
      command
    }}</code>
    <CopyButton :text="command" />
  </div>
</template>
