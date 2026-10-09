<script setup lang="ts">
  interface AccordionItem {
    value: string
    title: string
    body: string
  }

  defineProps({
    items: { type: Array as PropType<AccordionItem[]>, required: true },
  })
</script>

<template>
  <AccordionRoot type="single" collapsible class="divide-y divide-line">
    <AccordionItem v-for="item in items" :key="item.value" :value="item.value">
      <AccordionHeader>
        <AccordionTrigger
          class="group flex w-full items-center justify-between gap-6 py-6 text-left text-lg font-semibold tracking-[-0.02em] transition-colors hover:text-accent-ink">
          {{ item.title }}
          <span
            class="grid size-7 shrink-0 place-items-center rounded-full bg-fg/[0.07] text-sm transition duration-300 ease-apple group-data-[state=open]:rotate-45 group-data-[state=open]:bg-accent group-data-[state=open]:text-white">
            <Icon name="ph:plus" />
          </span>
        </AccordionTrigger>
      </AccordionHeader>
      <AccordionContent
        class="overflow-hidden data-[state=closed]:animate-[collapse_250ms_ease-out] data-[state=open]:animate-[expand_300ms_ease-out]">
        <p class="max-w-2xl pb-6 text-muted">{{ item.body }}</p>
      </AccordionContent>
    </AccordionItem>
  </AccordionRoot>
</template>
