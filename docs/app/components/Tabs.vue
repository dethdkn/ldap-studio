<script setup lang="ts">
  interface TabItem {
    label: string
    value: string
    icon: string
  }

  defineProps({
    items: { type: Array as PropType<TabItem[]>, required: true },
  })

  const model = defineModel<string>({ required: true })
</script>

<template>
  <TabsRoot v-model="model">
    <div class="flex justify-center">
      <TabsList
        class="relative flex max-w-full gap-1 overflow-x-auto rounded-full bg-fg/[0.07] p-1">
        <TabsIndicator
          class="absolute inset-y-1 left-0 w-(--reka-tabs-indicator-size) translate-x-(--reka-tabs-indicator-position) rounded-full bg-thumb shadow-[0_2px_8px_rgb(0_0_0/0.12)] transition-[width,translate] duration-400 ease-apple" />
        <TabsTrigger
          v-for="item in items"
          :key="item.value"
          :value="item.value"
          class="relative z-10 flex shrink-0 items-center gap-2 rounded-full px-5 py-2.5 text-sm font-medium whitespace-nowrap text-fg/60 transition-colors duration-300 hover:text-fg data-[state=active]:text-fg">
          <Icon :name="item.icon" class="text-base" />
          {{ item.label }}
        </TabsTrigger>
      </TabsList>
    </div>

    <TabsContent
      v-for="item in items"
      :key="item.value"
      :value="item.value"
      class="mt-10 outline-none">
      <Motion
        :initial="{ opacity: 0, y: 12 }"
        :animate="{ opacity: 1, y: 0 }"
        :transition="{ type: 'spring', bounce: 0, duration: 0.5 }">
        <slot :name="item.value" />
      </Motion>
    </TabsContent>
  </TabsRoot>
</template>
