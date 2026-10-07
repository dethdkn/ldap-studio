<script setup lang="ts">
  defineProps({
    id: { type: String, required: true },
  })
</script>

<template>
  <section
    :id="id"
    :data-branch="id"
    class="relative mx-auto w-full max-w-7xl px-4 py-24 sm:px-8 lg:py-36">
    <slot />
  </section>
</template>
