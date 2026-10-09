<script setup lang="ts">
  type Field =
    | 'name'
    | 'host'
    | 'port'
    | 'encryption'
    | 'base'
    | 'bind'
    | 'password'
    | 'readonly'
    | 'test'
  type Encryption = 'None' | 'SSL' | 'StartTLS'

  const HOST = 'ldap.example.org'
  const BASE_DN = 'dc=example,dc=org'
  const BIND_DN = 'cn=admin,dc=example,dc=org'
  const ENCRYPTIONS: Encryption[] = ['None', 'SSL', 'StartTLS']

  const { t } = useI18n({ useScope: 'local' })

  const active = ref<Field>('host')
  const encryption = ref<Encryption>('SSL')
  const readOnly = ref(true)

  const port = computed(() => (encryption.value === 'SSL' ? '636' : '389'))
  const scheme = computed(() => (encryption.value === 'SSL' ? 'ldaps' : 'ldap'))
  const encryptions = ENCRYPTIONS.map((value) => ({ label: value, value }))

  const rows = computed<{ field: Field; label: string; value: string }[]>(() => [
    { field: 'name', label: 'Name', value: 'Research directory' },
    { field: 'host', label: 'Host', value: HOST },
    { field: 'port', label: 'Port', value: port.value },
    { field: 'base', label: 'Base DN', value: BASE_DN },
    { field: 'bind', label: 'Bind DN', value: BIND_DN },
    { field: 'password', label: 'Password', value: '••••••••••' },
  ])

  function highlight(field: Field): string {
    return active.value === field ? 'rounded bg-accent px-1 text-white' : 'text-fg'
  }
</script>

<template>
  <div class="grid grid-cols-1 gap-4 lg:grid-cols-[1.15fr_0.85fr]">
    <div class="card overflow-hidden">
      <p class="border-b border-line py-4 text-center text-sm font-semibold">New Connection</p>

      <div class="space-y-1 p-3">
        <button
          v-for="row in rows"
          :key="row.field"
          type="button"
          class="flex w-full items-center justify-between gap-4 rounded-xl px-3 py-2.5 text-left text-sm transition"
          :class="active === row.field ? 'bg-accent-soft' : 'hover:bg-fg/5'"
          @pointerenter="active = row.field"
          @focus="active = row.field">
          <span>{{ row.label }}</span>
          <span class="truncate font-mono text-xs text-muted">{{ row.value }}</span>
        </button>

        <div
          class="flex flex-wrap items-center justify-between gap-3 rounded-xl px-3 py-2 text-sm transition"
          :class="active === 'encryption' ? 'bg-accent-soft' : ''"
          @pointerenter="active = 'encryption'"
          @focusin="active = 'encryption'">
          <span>Encryption</span>
          <Segmented v-model="encryption" :items="encryptions" label="Encryption" />
        </div>

        <div
          class="flex items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-sm transition"
          :class="active === 'readonly' ? 'bg-accent-soft' : ''"
          @pointerenter="active = 'readonly'"
          @focusin="active = 'readonly'">
          <span>Read-only (block all writes)</span>
          <Switch v-model="readOnly" label="Read-only" />
        </div>
      </div>

      <div class="flex justify-end gap-2 border-t border-line p-3">
        <span class="rounded-lg bg-fg/[0.07] px-4 py-1.5 text-sm">Cancel</span>
        <button
          type="button"
          class="rounded-lg px-4 py-1.5 text-sm transition"
          :class="active === 'test' ? 'bg-accent-soft text-accent-ink' : 'bg-fg/[0.07]'"
          @pointerenter="active = 'test'"
          @focus="active = 'test'">
          Test
        </button>
        <span class="rounded-lg bg-accent px-4 py-1.5 text-sm font-medium text-white">Add</span>
      </div>
    </div>

    <div class="card flex min-h-56 flex-col gap-8 p-8">
      <AnimatePresence mode="wait" :initial="false">
        <Motion
          :key="active"
          :initial="{ opacity: 0, y: 10 }"
          :animate="{ opacity: 1, y: 0 }"
          :exit="{ opacity: 0, y: -10 }"
          :transition="{ type: 'spring', bounce: 0, duration: 0.3 }"
          aria-live="polite">
          <p class="text-sm font-semibold text-accent-ink">{{ t('tip') }}</p>
          <p class="type-title mt-3 text-2xl">{{ t(`${active}_title`) }}</p>
          <p class="mt-3 leading-relaxed text-muted">{{ t(`${active}_text`) }}</p>
        </Motion>
      </AnimatePresence>

      <div class="well mt-auto p-4 font-mono text-xs leading-loose">
        <p class="text-muted">{{ t('url') }}</p>
        <p class="break-all">
          <span class="transition" :class="highlight('encryption')">{{ scheme }}</span>
          <span class="text-muted">://</span>
          <span class="transition" :class="highlight('host')">{{ HOST }}</span>
          <span class="text-muted">:</span>
          <span class="transition" :class="highlight('port')">{{ port }}</span>
          <span class="text-muted">/</span>
          <span class="transition" :class="highlight('base')">{{ BASE_DN }}</span>
        </p>
        <p class="text-muted">
          bind
          <span class="transition" :class="highlight('bind')">{{ BIND_DN }}</span>
        </p>
      </div>
    </div>
  </div>
</template>

<i18n lang="json">
{
  "en": {
    "tip": "Point at a field",
    "url": "Connection as an LDAP URL",
    "name_title": "Name",
    "name_text": "Any label you like. It is how the connection shows up on the home window.",
    "host_title": "Host",
    "host_text": "The hostname or IP address of your LDAP server.",
    "port_title": "Port",
    "port_text": "389 for plain LDAP and StartTLS, 636 for SSL. Try switching the encryption to see it change.",
    "encryption_title": "Encryption",
    "encryption_text": "None, SSL or StartTLS. If the server uses a certificate your Mac does not trust, the app asks before trusting it for this server only.",
    "base_title": "Base DN",
    "base_text": "Where browsing starts. Usually the root of your directory, like dc=example,dc=org.",
    "bind_title": "Bind DN",
    "bind_text": "Who you log in as. Leave it empty for an anonymous connection.",
    "password_title": "Password",
    "password_text": "Saved in the macOS Keychain, never in a plain file.",
    "readonly_title": "Read-only",
    "readonly_text": "Blocks every write on this connection. A good default for production servers.",
    "test_title": "Test",
    "test_text": "Connects and binds with these settings without saving anything, so you know they work before you add them."
  },
  "pt": {
    "tip": "Aponte para um campo",
    "url": "A conexão como URL LDAP",
    "name_title": "Nome",
    "name_text": "Qualquer nome que você quiser. É assim que a conexão aparece na janela inicial.",
    "host_title": "Host",
    "host_text": "O hostname ou endereço IP do seu servidor LDAP.",
    "port_title": "Porta",
    "port_text": "389 para LDAP simples e StartTLS, 636 para SSL. Troque a criptografia para ver a porta mudar.",
    "encryption_title": "Criptografia",
    "encryption_text": "None, SSL ou StartTLS. Se o servidor usar um certificado em que seu Mac não confia, o app pergunta antes de confiar nele só para esse servidor.",
    "base_title": "Base DN",
    "base_text": "Onde a navegação começa. Normalmente a raiz do diretório, como dc=example,dc=org.",
    "bind_title": "Bind DN",
    "bind_text": "Com quem você faz login. Deixe vazio para uma conexão anônima.",
    "password_title": "Senha",
    "password_text": "Guardada no Keychain do macOS, nunca num arquivo de texto.",
    "readonly_title": "Somente leitura",
    "readonly_text": "Bloqueia qualquer escrita nesta conexão. Um bom padrão para servidores de produção.",
    "test_title": "Test",
    "test_text": "Conecta e faz o bind com essas configurações sem salvar nada, para você saber que funcionam antes de adicionar."
  }
}
</i18n>
