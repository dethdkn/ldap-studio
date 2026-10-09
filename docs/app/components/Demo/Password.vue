<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const password = ref('correct horse battery staple')
  const scheme = ref<HashScheme>('PBKDF2-SHA512')
  const hash = ref('')
  const hashing = ref(false)
  let run = 0

  const schemes = HASH_SCHEMES.map((value) => ({ label: value, value }))

  const parts = computed(() => {
    const end = hash.value.indexOf('}') + 1

    return { scheme: hash.value.slice(0, end), value: hash.value.slice(end) }
  })

  async function refresh(): Promise<void> {
    run += 1
    const current = run
    hashing.value = true
    const result = await hashPassword(password.value, scheme.value)
    if (current !== run) return

    hash.value = result
    hashing.value = false
  }

  watchDebounced([password, scheme], refresh, { debounce: 200 })
  onMounted(refresh)
</script>

<template>
  <div class="card p-6 sm:p-9">
    <label class="block">
      <span class="text-sm font-semibold">{{ t('password') }}</span>
      <input
        v-model="password"
        type="text"
        spellcheck="false"
        autocomplete="off"
        class="mt-3 h-12 w-full rounded-xl border border-line bg-surface-solid px-4 font-mono text-sm transition hover:border-accent/50" />
    </label>

    <div class="mt-6 flex flex-wrap items-center justify-between gap-4">
      <p class="text-sm font-semibold">{{ t('scheme') }}</p>
      <Segmented v-model="scheme" :items="schemes" :label="t('scheme')" />
    </div>

    <div class="well mt-6 p-4">
      <div class="flex items-center justify-between gap-3">
        <p class="font-mono text-xs text-muted">userPassword</p>
        <div class="flex items-center gap-1">
          <button
            type="button"
            :aria-label="t('again')"
            class="grid size-9 place-items-center rounded-lg text-muted transition hover:bg-accent-soft hover:text-accent-ink active:scale-90"
            @click="refresh">
            <Icon name="ph:arrow-clockwise" class="text-lg" :class="hashing && 'animate-spin'" />
          </button>
          <CopyButton :text="hash" />
        </div>
      </div>
      <code
        class="mt-2 block font-mono text-sm leading-relaxed break-all transition-opacity"
        :class="hashing && 'opacity-50'">
        <span class="font-semibold text-accent-ink">{{ parts.scheme }}</span>
        <span>{{ parts.value }}</span>
      </code>
    </div>

    <p class="mt-4 flex gap-2 text-sm text-muted">
      <Icon name="ph:lock-simple" class="mt-0.5 shrink-0 text-accent" />
      {{ t('note') }}
    </p>
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "password": "Type a password",
    "scheme": "Scheme",
    "again": "Hash again with a new salt",
    "note": "Hashed right here in your browser, in the same format the app writes. Salted schemes give a new result every time."
  },
  "pt": {
    "password": "Digite uma senha",
    "scheme": "Esquema",
    "again": "Gerar de novo com outro salt",
    "note": "O hash é gerado aqui mesmo no seu navegador, no mesmo formato que o app grava. Esquemas com salt dão um resultado diferente a cada vez."
  }
}
</i18n>
