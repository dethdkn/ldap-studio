<script setup lang="ts">
  type Tab = 'server' | 'authentication' | 'network' | 'ssh'
  type Field =
    | 'name'
    | 'host'
    | 'port'
    | 'encryption'
    | 'base'
    | 'readonly'
    | 'method'
    | 'bind'
    | 'password'
    | 'authid'
    | 'realm'
    | 'certificate'
    | 'referrals'
    | 'timeout'
    | 'tunnel'
    | 'ssh_host'
    | 'ssh_user'
    | 'ssh_auth'
    | 'test'
  type Encryption = 'None' | 'LDAPS' | 'StartTLS'
  type Method = 'simple' | 'external' | 'gssapi' | 'digest'
  type SSHAuth = 'password' | 'key'

  const TABS: { id: Tab; label: string; icon: string; title: string; first: Field }[] = [
    {
      id: 'server',
      label: 'Server',
      icon: 'ph:hard-drives',
      title: 'Directory Server',
      first: 'name',
    },
    {
      id: 'authentication',
      label: 'Authentication',
      icon: 'ph:user-gear',
      title: 'Bind & Authentication',
      first: 'method',
    },
    {
      id: 'network',
      label: 'Network',
      icon: 'ph:globe',
      title: 'Connection Behavior',
      first: 'referrals',
    },
    {
      id: 'ssh',
      label: 'SSH Tunnel',
      icon: 'ph:graph',
      title: 'Bastion / Jump Host',
      first: 'tunnel',
    },
  ]

  const ENCRYPTIONS: Encryption[] = ['None', 'LDAPS', 'StartTLS']
  const METHODS: { value: Method; label: string }[] = [
    { value: 'simple', label: 'Simple Bind' },
    { value: 'external', label: 'SASL EXTERNAL' },
    { value: 'gssapi', label: 'SASL GSSAPI / Kerberos' },
    { value: 'digest', label: 'SASL DIGEST-MD5' },
  ]
  const SSH_AUTHS: { value: SSHAuth; label: string }[] = [
    { value: 'password', label: 'Password' },
    { value: 'key', label: 'Private Key' },
  ]

  const INPUT =
    'h-7 w-full min-w-0 rounded-md border border-white/10 bg-white/[0.05] px-2 text-[0.8rem] text-fg placeholder:text-fg/40 focus-visible:outline-2 focus-visible:outline-[#0a84ff] disabled:opacity-40'
  const SELECT =
    'h-6 cursor-pointer rounded-md bg-white/10 pr-1 pl-2 text-[0.8rem] text-fg focus-visible:outline-2 focus-visible:outline-[#0a84ff] disabled:opacity-40'

  const { t } = useI18n({ useScope: 'local' })

  const tab = ref<Tab>('server')
  const active = ref<Field>('host')

  const name = ref('Research directory')
  const host = ref('ldap.example.org')
  const encryption = ref<Encryption>('LDAPS')
  const port = ref(636)
  const baseDn = ref('dc=example,dc=org')
  const readOnly = ref(true)

  const method = ref<Method>('simple')
  const bindDn = ref('cn=admin,dc=example,dc=org')
  const password = ref('correct-horse')
  const authId = ref('')
  const realm = ref('')

  const referrals = ref(false)
  const timeout = ref(15)

  const tunnel = ref(false)
  const sshHost = ref('bastion.example.org')
  const sshPort = ref(22)
  const sshUser = ref('ada')
  const sshAuth = ref<SSHAuth>('password')
  const sshPassword = ref('')

  const current = computed(() => TABS.find((item) => item.id === tab.value))
  const scheme = computed(() => (encryption.value === 'LDAPS' ? 'ldaps' : 'ldap'))
  const conflict = computed(() => {
    if (!tunnel.value) return null
    if (method.value === 'gssapi') return t('conflict_gssapi')
    if (referrals.value) return t('conflict_referrals')

    return null
  })

  watch(encryption, (value) => {
    port.value = value === 'LDAPS' ? 636 : 389
  })

  function track(field: Field): Record<string, () => void> {
    return {
      pointerenter: () => (active.value = field),
      focusin: () => (active.value = field),
    }
  }

  function selectTab(id: Tab): void {
    tab.value = id
    active.value = TABS.find((item) => item.id === id)?.first ?? 'name'
  }

  function stepTimeout(delta: number): void {
    timeout.value = Math.min(300, Math.max(1, timeout.value + delta))
  }

  function highlight(field: Field): string {
    return active.value === field ? 'rounded bg-accent px-1 text-white' : 'text-fg'
  }
</script>

<template>
  <div class="grid grid-cols-1 gap-4 lg:grid-cols-[1.2fr_0.8fr]">
    <div
      class="tone-dark flex flex-col overflow-hidden rounded-[1rem] bg-[#1e1e20] text-left text-fg shadow-[0_0_0_1px_rgb(255_255_255/0.12),0_30px_80px_-30px_rgb(0_0_0/0.6)]">
      <div class="flex items-center gap-3 border-b border-white/[0.08] px-5 py-4">
        <span
          class="grid size-10 shrink-0 place-items-center rounded-lg bg-[#1c2c4a] text-xl text-[#3b8cff]">
          <Icon name="ph:globe-simple" />
        </span>
        <span class="min-w-0">
          <span class="block text-[0.95rem] font-semibold">New Connection</span>
          <span class="block truncate text-[0.7rem] text-fg/60">
            Configure directory access, authentication, and routing.
          </span>
        </span>
      </div>

      <div class="grid min-h-[19rem] flex-1 sm:grid-cols-[10rem_1fr]">
        <div
          role="tablist"
          aria-label="Connection settings"
          class="flex gap-1 overflow-x-auto border-b border-white/[0.08] bg-white/[0.025] p-2 sm:flex-col sm:border-r sm:border-b-0">
          <button
            v-for="item in TABS"
            :key="item.id"
            type="button"
            role="tab"
            :aria-selected="tab === item.id"
            class="flex shrink-0 items-center gap-2 rounded-lg px-2.5 py-1.5 text-[0.8rem] transition"
            :class="tab === item.id ? 'bg-[#1f3256] text-white' : 'text-fg/85 hover:bg-white/5'"
            @click="selectTab(item.id)">
            <Icon :name="item.icon" class="shrink-0 text-[0.95rem]" />
            {{ item.label }}
          </button>
        </div>

        <div class="min-w-0 p-3 sm:p-4">
          <div class="rounded-xl border border-white/[0.08] bg-white/[0.02] p-3.5">
            <p
              class="mb-3 flex items-center gap-2 border-b border-white/[0.08] pb-2.5 text-[0.8rem] font-semibold">
              <Icon v-if="current" :name="current.icon" class="text-[0.95rem]" />
              {{ current?.title }}
            </p>

            <div v-if="tab === 'server'" class="space-y-2.5">
              <div v-on="track('name')">
                <input
                  v-model="name"
                  :class="INPUT"
                  aria-label="Connection name"
                  placeholder="Connection name" />
              </div>
              <div class="flex gap-2">
                <div class="flex-1" v-on="track('host')">
                  <input v-model="host" :class="INPUT" aria-label="Host" placeholder="Host" />
                </div>
                <div class="w-20" v-on="track('port')">
                  <input
                    v-model.number="port"
                    :class="INPUT"
                    aria-label="Port"
                    inputmode="numeric" />
                </div>
              </div>
              <label class="flex items-center gap-2 text-[0.8rem]" v-on="track('encryption')">
                Encryption
                <select v-model="encryption" :class="SELECT">
                  <option v-for="value in ENCRYPTIONS" :key="value" :value="value">
                    {{ value }}
                  </option>
                </select>
              </label>
              <div v-on="track('base')">
                <input
                  v-model="baseDn"
                  :class="INPUT"
                  aria-label="Base DN"
                  placeholder="dc=example,dc=com" />
              </div>
              <label class="flex items-center gap-2 text-[0.8rem]" v-on="track('readonly')">
                <input v-model="readOnly" type="checkbox" class="size-3.5 accent-[#0a84ff]" />
                Read-only — block every write operation
              </label>
            </div>

            <div v-else-if="tab === 'authentication'" class="space-y-2.5">
              <label class="flex items-center gap-2 text-[0.8rem]" v-on="track('method')">
                Method
                <select v-model="method" :class="SELECT">
                  <option v-for="item in METHODS" :key="item.value" :value="item.value">
                    {{ item.label }}
                  </option>
                </select>
              </label>

              <template v-if="method === 'simple'">
                <div v-on="track('bind')">
                  <input
                    v-model="bindDn"
                    :class="INPUT"
                    aria-label="Bind DN"
                    placeholder="Leave empty for anonymous bind" />
                </div>
                <div v-on="track('password')">
                  <input
                    v-model="password"
                    type="password"
                    :class="INPUT"
                    aria-label="Password"
                    placeholder="Password" />
                </div>
              </template>

              <template v-else-if="method === 'external'">
                <p class="text-[0.7rem] text-fg/55">
                  EXTERNAL authenticates with a client certificate during TLS.
                </p>
                <div
                  v-for="label in ['Client certificate', 'Private key']"
                  :key="label"
                  class="flex items-center justify-between gap-2 text-[0.8rem]"
                  v-on="track('certificate')">
                  {{ label }}
                  <span class="rounded-md bg-white/10 px-2 py-0.5 text-[0.75rem]">Choose…</span>
                </div>
              </template>

              <template v-else>
                <div v-on="track('authid')">
                  <input
                    v-model="authId"
                    :class="INPUT"
                    aria-label="Authentication ID"
                    :placeholder="
                      method === 'gssapi' ? 'Kerberos principal (optional)' : 'Username'
                    " />
                </div>
                <div v-on="track('realm')">
                  <input v-model="realm" :class="INPUT" aria-label="Realm" placeholder="Optional" />
                </div>
                <div v-if="method === 'digest'" v-on="track('password')">
                  <input
                    v-model="password"
                    type="password"
                    :class="INPUT"
                    aria-label="Password"
                    placeholder="Password" />
                </div>
                <p v-else class="text-[0.7rem] text-fg/55">
                  Uses the current macOS Kerberos ticket.
                </p>
              </template>
            </div>

            <div v-else-if="tab === 'network'" class="space-y-2.5">
              <div v-on="track('referrals')">
                <label class="flex items-center gap-2 text-[0.8rem]">
                  <input v-model="referrals" type="checkbox" class="size-3.5 accent-[#0a84ff]" />
                  Chase LDAP referrals
                </label>
                <p class="mt-1.5 text-[0.7rem] text-fg/55">
                  Allows the directory to redirect searches to another LDAP server.
                </p>
              </div>
              <div class="flex items-center gap-2 text-[0.8rem]" v-on="track('timeout')">
                <span class="whitespace-nowrap">Operation timeout</span>
                <input
                  v-model.number="timeout"
                  :class="INPUT"
                  class="w-16 text-right"
                  aria-label="Operation timeout in seconds"
                  inputmode="numeric" />
                <span class="text-fg/55">seconds</span>
                <span class="flex flex-col overflow-hidden rounded-md bg-white/10 text-[0.6rem]">
                  <button
                    type="button"
                    aria-label="More seconds"
                    class="px-1 hover:bg-white/10"
                    @click="stepTimeout(1)">
                    <Icon name="ph:caret-up-bold" />
                  </button>
                  <button
                    type="button"
                    aria-label="Fewer seconds"
                    class="px-1 hover:bg-white/10"
                    @click="stepTimeout(-1)">
                    <Icon name="ph:caret-down-bold" />
                  </button>
                </span>
              </div>
            </div>

            <div v-else class="space-y-2.5">
              <label class="flex items-center gap-2 text-[0.8rem]" v-on="track('tunnel')">
                <input v-model="tunnel" type="checkbox" class="size-3.5 accent-[#0a84ff]" />
                Connect through an SSH tunnel
              </label>
              <div class="flex gap-2" v-on="track('ssh_host')">
                <input
                  v-model="sshHost"
                  :disabled="!tunnel"
                  :class="INPUT"
                  class="flex-1"
                  aria-label="SSH host"
                  placeholder="SSH host" />
                <input
                  v-model.number="sshPort"
                  :disabled="!tunnel"
                  :class="INPUT"
                  class="w-20!"
                  aria-label="SSH port"
                  inputmode="numeric" />
              </div>
              <div v-on="track('ssh_user')">
                <input
                  v-model="sshUser"
                  :disabled="!tunnel"
                  :class="INPUT"
                  aria-label="Username"
                  placeholder="Username" />
              </div>
              <label class="flex items-center gap-2 text-[0.8rem]" v-on="track('ssh_auth')">
                Authentication
                <select v-model="sshAuth" :disabled="!tunnel" :class="SELECT">
                  <option v-for="item in SSH_AUTHS" :key="item.value" :value="item.value">
                    {{ item.label }}
                  </option>
                </select>
              </label>
              <div v-if="sshAuth === 'password'" v-on="track('ssh_auth')">
                <input
                  v-model="sshPassword"
                  type="password"
                  :disabled="!tunnel"
                  :class="INPUT"
                  aria-label="SSH password"
                  placeholder="SSH password" />
              </div>
              <div
                v-else
                class="flex items-center justify-between gap-2 text-[0.8rem]"
                :class="!tunnel && 'opacity-40'"
                v-on="track('ssh_auth')">
                Private key
                <span class="rounded-md bg-white/10 px-2 py-0.5 text-[0.75rem]">Choose…</span>
              </div>
              <p class="text-[0.7rem] text-fg/55">
                The tunnel runs inside LDAP Studio; no external ssh process is launched.
              </p>
              <p v-if="conflict" class="flex gap-1.5 text-[0.7rem] text-[#ff9f0a]">
                <Icon name="ph:warning-fill" class="mt-0.5 shrink-0" />
                {{ conflict }}
              </p>
            </div>
          </div>
        </div>
      </div>

      <div
        class="flex justify-end gap-2 border-t border-white/[0.08] px-4 py-3 text-[0.8rem] whitespace-nowrap">
        <span class="rounded-md bg-white/10 px-3 py-1">Cancel</span>
        <button
          type="button"
          class="rounded-md px-3 py-1 transition"
          :class="active === 'test' ? 'bg-[#0a84ff]/30 text-white' : 'bg-white/10'"
          v-on="track('test')">
          Test Connection
        </button>
        <span class="rounded-md bg-[#0a84ff] px-3 py-1 font-medium text-white">Add Connection</span>
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
          <span class="transition" :class="highlight('host')">{{ host }}</span>
          <span class="text-muted">:</span>
          <span class="transition" :class="highlight('port')">{{ port }}</span>
          <span class="text-muted">/</span>
          <span class="transition" :class="highlight('base')">{{ baseDn }}</span>
        </p>
        <p v-if="method === 'simple'" class="break-all text-muted">
          bind
          <span class="transition" :class="highlight('bind')">{{ bindDn || 'anonymous' }}</span>
        </p>
        <p v-else class="text-muted">
          sasl
          <span class="transition" :class="highlight('method')">
            {{ METHODS.find((item) => item.value === method)?.label.replace('SASL ', '') }}
          </span>
        </p>
        <p v-if="tunnel" class="break-all text-muted">
          via
          <span class="transition" :class="highlight('ssh_host')">
            ssh://{{ sshUser }}@{{ sshHost }}:{{ sshPort }}
          </span>
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
    "port_text": "389 for plain LDAP and StartTLS, 636 for LDAPS. Try switching the encryption to see it change.",
    "encryption_title": "Encryption",
    "encryption_text": "None, LDAPS or StartTLS. If the server uses a certificate your Mac does not trust, the app asks before trusting it for this server only.",
    "base_title": "Base DN",
    "base_text": "Where browsing starts. Usually the root of your directory, like dc=example,dc=org.",
    "readonly_title": "Read-only",
    "readonly_text": "Blocks every write on this connection. A good default for production servers.",
    "method_title": "Method",
    "method_text": "Simple Bind logs in with a DN and password. SASL EXTERNAL uses a client certificate, GSSAPI your Kerberos ticket, and DIGEST-MD5 a username and password.",
    "bind_title": "Bind DN",
    "bind_text": "Who you log in as. Leave it empty for an anonymous connection.",
    "password_title": "Password",
    "password_text": "Saved in the macOS Keychain, never in a plain file.",
    "authid_title": "Authentication ID",
    "authid_text": "Your SASL identity: a Kerberos principal for GSSAPI, or a username for DIGEST-MD5.",
    "realm_title": "Realm",
    "realm_text": "The SASL realm, if your server uses one. Usually you can leave it empty.",
    "certificate_title": "Client certificate",
    "certificate_text": "For SASL EXTERNAL: the certificate and private key the app presents during TLS to prove who you are.",
    "referrals_title": "Chase LDAP referrals",
    "referrals_text": "Lets the directory send a search on to another LDAP server. Off by default.",
    "timeout_title": "Operation timeout",
    "timeout_text": "How long a single operation can take before the app gives up, from 1 to 300 seconds.",
    "tunnel_title": "SSH tunnel",
    "tunnel_text": "Reach a server that is only visible from inside your network by going through a bastion host. The tunnel runs inside the app, with no external ssh process.",
    "ssh_host_title": "SSH host",
    "ssh_host_text": "The bastion or jump host and its SSH port, 22 by default.",
    "ssh_user_title": "Username",
    "ssh_user_text": "Your account on the bastion host.",
    "ssh_auth_title": "SSH authentication",
    "ssh_auth_text": "A password or a private key file. The first time you connect, the app shows the host key fingerprint and asks before trusting it.",
    "test_title": "Test Connection",
    "test_text": "Connects and binds with these settings without saving anything, so you know they work before you add them.",
    "conflict_gssapi": "GSSAPI derives its service principal from the direct server endpoint and cannot be combined with a local SSH forward.",
    "conflict_referrals": "Referral targets cannot be safely routed through this single-server SSH tunnel. Turn off referral chasing."
  },
  "pt": {
    "tip": "Aponte para um campo",
    "url": "A conexão como URL LDAP",
    "name_title": "Nome",
    "name_text": "Qualquer nome que você quiser. É assim que a conexão aparece na janela inicial.",
    "host_title": "Host",
    "host_text": "O hostname ou endereço IP do seu servidor LDAP.",
    "port_title": "Porta",
    "port_text": "389 para LDAP simples e StartTLS, 636 para LDAPS. Troque a criptografia para ver a porta mudar.",
    "encryption_title": "Criptografia",
    "encryption_text": "None, LDAPS ou StartTLS. Se o servidor usar um certificado em que seu Mac não confia, o app pergunta antes de confiar nele só para esse servidor.",
    "base_title": "Base DN",
    "base_text": "Onde a navegação começa. Normalmente a raiz do diretório, como dc=example,dc=org.",
    "readonly_title": "Somente leitura",
    "readonly_text": "Bloqueia qualquer escrita nesta conexão. Um bom padrão para servidores de produção.",
    "method_title": "Método",
    "method_text": "Simple Bind entra com um DN e uma senha. SASL EXTERNAL usa um certificado de cliente, GSSAPI o seu ticket Kerberos e DIGEST-MD5 um usuário e uma senha.",
    "bind_title": "Bind DN",
    "bind_text": "Com quem você faz login. Deixe vazio para uma conexão anônima.",
    "password_title": "Senha",
    "password_text": "Guardada no Keychain do macOS, nunca num arquivo de texto.",
    "authid_title": "Authentication ID",
    "authid_text": "Sua identidade SASL: um principal Kerberos no GSSAPI ou um usuário no DIGEST-MD5.",
    "realm_title": "Realm",
    "realm_text": "O realm SASL, se o seu servidor usar um. Normalmente pode ficar vazio.",
    "certificate_title": "Certificado de cliente",
    "certificate_text": "Para SASL EXTERNAL: o certificado e a chave privada que o app apresenta no TLS para provar quem você é.",
    "referrals_title": "Seguir referrals LDAP",
    "referrals_text": "Permite que o diretório encaminhe uma busca para outro servidor LDAP. Desligado por padrão.",
    "timeout_title": "Tempo limite da operação",
    "timeout_text": "Quanto tempo uma operação pode levar antes de o app desistir, de 1 a 300 segundos.",
    "tunnel_title": "Túnel SSH",
    "tunnel_text": "Acesse um servidor que só é visível de dentro da sua rede passando por um bastion host. O túnel roda dentro do app, sem nenhum processo ssh externo.",
    "ssh_host_title": "Host SSH",
    "ssh_host_text": "O bastion ou jump host e a porta SSH dele, 22 por padrão.",
    "ssh_user_title": "Usuário",
    "ssh_user_text": "Sua conta no bastion host.",
    "ssh_auth_title": "Autenticação SSH",
    "ssh_auth_text": "Uma senha ou um arquivo de chave privada. Na primeira conexão, o app mostra a impressão digital da chave do host e pergunta antes de confiar nela.",
    "test_title": "Test Connection",
    "test_text": "Conecta e faz o bind com essas configurações sem salvar nada, para você saber que funcionam antes de adicionar.",
    "conflict_gssapi": "O GSSAPI deriva o principal de serviço do endereço direto do servidor e não pode ser usado com um encaminhamento SSH local.",
    "conflict_referrals": "Os destinos de referral não podem ser roteados com segurança por este túnel SSH de um único servidor. Desligue o seguimento de referrals."
  }
}
</i18n>
