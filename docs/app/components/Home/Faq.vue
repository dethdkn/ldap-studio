<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const questions = computed(() =>
    ['free', 'unsigned', 'intel', 'servers', 'passwords', 'migrate', 'readonly', 'bugs'].map(
      (value) => ({
        value,
        title: t(`${value}_q`),
        body: t(`${value}_a`),
      }),
    ),
  )
</script>

<template>
  <PageSection id="faq">
    <div class="grid grid-cols-1 gap-12 lg:grid-cols-[0.8fr_1.2fr]">
      <SectionHeading rdn="ou=faq" :title="t('title')" />
      <Reveal :delay="0.1" class="glass rounded-3xl px-6 sm:px-8">
        <Accordion :items="questions" />
      </Reveal>
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Questions, answered.",
    "free_q": "Is it free?",
    "free_a": "Yes. LDAP Studio is open source under the MIT license. If it saves you time, you can sponsor its development on GitHub.",
    "unsigned_q": "Why does macOS say the app is from an unidentified developer?",
    "unsigned_a": "Releases are not signed with a paid Apple Developer account. Follow step 3 of the install guide once and macOS remembers your choice.",
    "intel_q": "Does it run on Intel Macs?",
    "intel_a": "Not yet. Releases are built for Apple Silicon (arm64) only.",
    "servers_q": "Which LDAP servers does it work with?",
    "servers_a": "It speaks standard LDAPv3 through the OpenLDAP client library, so it should work with any LDAPv3 server, such as OpenLDAP or 389 Directory Server.",
    "passwords_q": "Where are my passwords stored?",
    "passwords_a": "Connection passwords live in the macOS Keychain. Exported connection files only include a password if you ask for it, and even then it is obscured.",
    "migrate_q": "Can I bring my connections from LDAP Admin?",
    "migrate_a": "Yes. Choose Import Connection… and pick your LDAP Admin .lcf file.",
    "readonly_q": "Can I browse production without risk?",
    "readonly_a": "Turn on Read-only when you create the connection and every write is blocked.",
    "bugs_q": "Found a bug or missing a feature?",
    "bugs_a": "Open an issue on GitHub. Include your macOS version and, if you can, what the operation log shows."
  },
  "pt": {
    "title": "Perguntas, respondidas.",
    "free_q": "É gratuito?",
    "free_a": "Sim. O LDAP Studio é open source sob a licença MIT. Se ele economiza seu tempo, você pode patrocinar o desenvolvimento no GitHub.",
    "unsigned_q": "Por que o macOS diz que o app é de um desenvolvedor não identificado?",
    "unsigned_a": "As versões não são assinadas com uma conta paga de Apple Developer. Siga o passo 3 da instalação uma vez e o macOS lembra da sua escolha.",
    "intel_q": "Funciona em Macs com Intel?",
    "intel_a": "Ainda não. As versões são compiladas apenas para Apple Silicon (arm64).",
    "servers_q": "Com quais servidores LDAP ele funciona?",
    "servers_a": "Ele fala LDAPv3 padrão pela biblioteca cliente do OpenLDAP, então deve funcionar com qualquer servidor LDAPv3, como OpenLDAP ou 389 Directory Server.",
    "passwords_q": "Onde minhas senhas ficam guardadas?",
    "passwords_a": "As senhas das conexões ficam no Keychain do macOS. Arquivos de conexão exportados só incluem a senha se você pedir, e mesmo assim ofuscada.",
    "migrate_q": "Dá para trazer minhas conexões do LDAP Admin?",
    "migrate_a": "Sim. Escolha Import Connection… e selecione o arquivo .lcf do LDAP Admin.",
    "readonly_q": "Dá para navegar em produção sem risco?",
    "readonly_a": "Ative o Read-only ao criar a conexão e toda escrita fica bloqueada.",
    "bugs_q": "Achou um bug ou sentiu falta de algo?",
    "bugs_a": "Abra uma issue no GitHub. Inclua a versão do macOS e, se puder, o que aparece no log de operações."
  }
}
</i18n>
