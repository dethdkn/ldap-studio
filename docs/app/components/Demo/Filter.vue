<script setup lang="ts">
  const ATTRIBUTES = [
    'objectClass',
    'uid',
    'cn',
    'sn',
    'mail',
    'title',
    'memberOf',
    'employeeNumber',
  ]

  const { t } = useI18n({ useScope: 'local' })

  const join = ref<FilterJoin>('&')
  const conditions = ref<FilterCondition[]>([
    { id: 1, attribute: 'objectClass', operator: 'equals', value: 'inetOrgPerson' },
    { id: 2, attribute: 'mail', operator: 'ends', value: 'example.org' },
  ])
  let nextId = conditions.value.length + 1

  const filter = computed(() => buildFilter(conditions.value, join.value))
  const attributes = ATTRIBUTES.map((attribute) => ({ label: attribute, value: attribute }))

  const joins = computed<{ label: string; value: FilterJoin }[]>(() => [
    { label: t('join_all'), value: '&' },
    { label: t('join_any'), value: '|' },
  ])

  const operators = computed<{ label: string; value: FilterOperator }[]>(() => [
    { label: t('op_equals'), value: 'equals' },
    { label: t('op_not'), value: 'not' },
    { label: t('op_contains'), value: 'contains' },
    { label: t('op_starts'), value: 'starts' },
    { label: t('op_ends'), value: 'ends' },
    { label: t('op_present'), value: 'present' },
    { label: t('op_gte'), value: 'gte' },
    { label: t('op_lte'), value: 'lte' },
  ])

  function addCondition(): void {
    conditions.value.push({ id: nextId, attribute: 'cn', operator: 'contains', value: '' })
    nextId += 1
  }

  function removeCondition(id: number): void {
    conditions.value = conditions.value.filter((condition) => condition.id !== id)
  }
</script>

<template>
  <div class="card p-6 sm:p-9">
    <div class="flex flex-wrap items-center justify-between gap-4">
      <p class="text-sm font-semibold">{{ t('match') }}</p>
      <Segmented v-model="join" :items="joins" :label="t('match')" />
    </div>

    <ul class="mt-6 space-y-2">
      <AnimatePresence :initial="false">
        <Motion
          v-for="condition in conditions"
          :key="condition.id"
          as="li"
          layout
          class="grid grid-cols-2 gap-2 sm:grid-cols-[1fr_1fr_1.4fr_auto]"
          :initial="{ opacity: 0, y: -8 }"
          :animate="{ opacity: 1, y: 0 }"
          :exit="{ opacity: 0, scale: 0.97 }"
          :transition="{ type: 'spring', bounce: 0, duration: 0.35 }">
          <SelectField
            v-model="condition.attribute"
            :options="attributes"
            :label="t('attribute')" />
          <SelectField v-model="condition.operator" :options="operators" :label="t('operator')" />
          <TextField
            v-model="condition.value"
            :label="t('value')"
            :placeholder="t('value')"
            :disabled="condition.operator === 'present'" />
          <button
            type="button"
            :aria-label="t('remove')"
            class="grid h-10 place-items-center rounded-xl text-muted transition hover:bg-fg/5 hover:text-signal active:scale-90 sm:w-10"
            @click="removeCondition(condition.id)">
            <Icon name="ph:x" />
          </button>
        </Motion>
      </AnimatePresence>
    </ul>

    <button
      type="button"
      class="mt-3 flex items-center gap-2 rounded-xl px-3 py-2 text-sm font-medium text-accent-ink transition hover:bg-accent-soft active:scale-[0.97]"
      @click="addCondition">
      <Icon name="ph:plus" />
      {{ t('add') }}
    </button>

    <div class="well mt-6 flex items-start gap-3 p-4">
      <FilterText :filter="filter" class="min-w-0 flex-1 pt-1.5" />
      <CopyButton :text="filter" />
    </div>
    <p class="mt-4 text-sm text-muted">{{ t('note') }}</p>
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "match": "Entries must match",
    "join_all": "all conditions",
    "join_any": "any condition",
    "attribute": "Attribute",
    "operator": "Comparison",
    "value": "Value",
    "remove": "Remove condition",
    "add": "Add condition",
    "op_equals": "is",
    "op_not": "is not",
    "op_contains": "contains",
    "op_starts": "starts with",
    "op_ends": "ends with",
    "op_present": "is present",
    "op_gte": "greater or equal",
    "op_lte": "less or equal",
    "note": "Special characters are escaped for you. In the app, Advanced Search runs the filter and you can pin it for later."
  },
  "pt": {
    "match": "As entradas devem atender a",
    "join_all": "todas as condições",
    "join_any": "qualquer condição",
    "attribute": "Atributo",
    "operator": "Comparação",
    "value": "Valor",
    "remove": "Remover condição",
    "add": "Adicionar condição",
    "op_equals": "é",
    "op_not": "não é",
    "op_contains": "contém",
    "op_starts": "começa com",
    "op_ends": "termina com",
    "op_present": "existe",
    "op_gte": "maior ou igual",
    "op_lte": "menor ou igual",
    "note": "Caracteres especiais são escapados para você. No app, a Advanced Search executa o filtro e você pode fixá-lo para depois."
  }
}
</i18n>
