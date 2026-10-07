<script setup lang="ts">
  const props = defineProps({
    text: { type: String, required: true },
  })

  const { t } = useI18n({ useScope: 'local' })
  const { copy, copied } = useClipboard({ copiedDuring: 1600 })

  function onCopy(): void {
    void copy(props.text)
  }
</script>

<template>
  <button
    type="button"
    :aria-label="copied ? t('copied') : t('copy')"
    class="grid size-9 shrink-0 place-items-center rounded-lg text-muted transition hover:bg-accent-soft hover:text-accent-ink active:scale-90"
    @click="onCopy">
    <Icon
      :name="copied ? 'ph:check-bold' : 'ph:copy'"
      class="text-lg"
      :class="copied && 'text-ok'" />
  </button>
</template>

<i18n lang="json">
{
  "en": {
    "copy": "Copy",
    "copied": "Copied"
  },
  "pt": {
    "copy": "Copiar",
    "copied": "Copiado"
  }
}
</i18n>
