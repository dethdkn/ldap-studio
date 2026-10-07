<script setup lang="ts">
  const props = defineProps({
    filter: { type: String, required: true },
  })

  const COLORS: Record<FilterTokenKind, string> = {
    paren: 'text-muted',
    logic: 'font-bold text-signal',
    attribute: 'text-accent-ink',
    comparator: 'text-muted',
    value: 'text-fg',
    wildcard: 'font-bold text-signal',
  }

  const tokens = computed(() => tokenizeFilter(props.filter))
</script>

<template>
  <code class="font-mono text-sm leading-relaxed break-all">
    <span v-for="(token, index) in tokens" :key="index" :class="COLORS[token.kind]">{{
      token.text
    }}</span>
  </code>
</template>
