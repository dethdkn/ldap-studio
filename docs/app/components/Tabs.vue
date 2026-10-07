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
    <TabsList class="glass relative flex w-full gap-1 overflow-x-auto rounded-full p-1 sm:w-fit">
      <TabsIndicator
        class="absolute inset-y-1 left-0 w-(--reka-tabs-indicator-size) translate-x-(--reka-tabs-indicator-position) rounded-full bg-fg transition-[width,translate] duration-300 ease-out" />
      <TabsTrigger
        v-for="item in items"
        :key="item.value"
        :value="item.value"
        class="relative z-10 flex shrink-0 items-center gap-2 rounded-full px-4 py-2.5 text-sm font-semibold whitespace-nowrap text-muted transition-colors duration-300 hover:text-fg data-[state=active]:text-bg">
        <Icon :name="item.icon" class="text-base" />
        {{ item.label }}
      </TabsTrigger>
    </TabsList>

    <TabsContent
      v-for="item in items"
      :key="item.value"
      :value="item.value"
      class="mt-8 outline-none">
      <slot :name="item.value" />
    </TabsContent>
  </TabsRoot>
</template>
