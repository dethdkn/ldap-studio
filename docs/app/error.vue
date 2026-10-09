<script setup lang="ts">
  import type { NuxtError } from '#app'

  const props = defineProps({
    error: { type: Object as PropType<NuxtError>, required: true },
  })

  const { t } = useI18n({ useScope: 'local' })

  const notFound = computed(() => props.error.statusCode === 404)

  useHead({ title: notFound.value ? t('not_found') : t('failed') })
</script>

<template>
  <NuxtLayout>
    <section data-tone="dark" class="tone-dark bg-bg text-fg">
      <div
        class="mx-auto flex min-h-svh max-w-2xl flex-col items-center justify-center px-5 py-32 text-center sm:px-8">
        <p class="font-mono text-xs text-signal">
          ldap_result: {{ notFound ? '32 noSuchObject' : '80 other' }}
        </p>
        <h1 class="type-hero mt-6">{{ notFound ? t('not_found') : t('failed') }}</h1>
        <p class="type-lead mt-6">{{ notFound ? t('not_found_text') : t('failed_text') }}</p>
        <Button to="/" variant="link" class="mt-8">{{ t('back') }}</Button>
      </div>
    </section>
  </NuxtLayout>
</template>

<i18n lang="json">
{
  "en": {
    "not_found": "No such object.",
    "not_found_text": "This page does not exist in the directory. It may have moved, or the link has a typo.",
    "failed": "Something broke.",
    "failed_text": "The page could not be loaded. Try again in a moment.",
    "back": "Back to LDAP Studio"
  },
  "pt": {
    "not_found": "Objeto não encontrado.",
    "not_found_text": "Esta página não existe no diretório. Ela pode ter mudado de lugar, ou o link tem um erro de digitação.",
    "failed": "Algo quebrou.",
    "failed_text": "Não foi possível carregar a página. Tente de novo daqui a pouco.",
    "back": "Voltar para o LDAP Studio"
  }
}
</i18n>
