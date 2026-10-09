<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const reasons = computed(() => [
    { icon: 'ph:apple-logo-fill', title: t('native_title'), text: t('native_text') },
    { icon: 'ph:graph', title: t('schema_title'), text: t('schema_text') },
    { icon: 'ph:shield-check-fill', title: t('safe_title'), text: t('safe_text') },
  ])
</script>

<template>
  <PageSection name="why" tone="light">
    <Reveal>
      <p class="type-eyebrow">{{ t('eyebrow') }}</p>
    </Reveal>
    <div
      class="mt-4 text-[clamp(1.75rem,4vw,3rem)] leading-[1.15] font-semibold tracking-[-0.035em]">
      <ScrollText :text="t('story')" />
    </div>

    <div class="mt-24 grid items-center gap-10 lg:grid-cols-[1fr_1.1fr]">
      <Reveal>
        <h3 class="type-title text-3xl text-balance sm:text-4xl">{{ t('compare_title') }}</h3>
        <p class="type-lead mt-4">{{ t('compare_lead') }}</p>
      </Reveal>
      <Reveal :delay="0.1">
        <DemoWorkflow />
      </Reveal>
    </div>

    <div class="mt-24 grid gap-5 md:grid-cols-3">
      <Reveal
        v-for="(reason, index) in reasons"
        :key="reason.title"
        :delay="index * 0.08"
        class="card p-8">
        <Icon :name="reason.icon" class="text-3xl text-accent" />
        <h3 class="type-title mt-6 text-2xl">{{ reason.title }}</h3>
        <p class="mt-3 text-muted">{{ reason.text }}</p>
      </Reveal>
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "eyebrow": "Why it exists",
    "story": "LDAP Studio started at CBPF, the Brazilian research center where its author works. The only real LDAP client available was LDAP Admin: Windows-only and not updated in years, and every lookup meant booting a virtual machine just to open it. So its author built a native one for macOS.",
    "compare_title": "From five steps to two.",
    "compare_lead": "Flip between before and after to see what editing a single entry used to take.",
    "native_title": "Native, not ported",
    "native_text": "SwiftUI windows, the macOS menu bar, a shortcut for every action and passwords kept in the Keychain.",
    "schema_title": "Reads your schema",
    "schema_text": "Attribute names and object classes autocomplete from the server's own schema, with superior-class inheritance resolved.",
    "safe_title": "Careful with your data",
    "safe_text": "Read-only mode per connection, passwords hashed before they leave your Mac, and a count of affected entries before any recursive delete."
  },
  "pt": {
    "eyebrow": "Por que ele existe",
    "story": "O LDAP Studio começou no CBPF, o centro de pesquisa onde seu autor trabalha. O único cliente LDAP de verdade disponível era o LDAP Admin: só para Windows e sem atualização há anos, então cada consulta exigia ligar uma máquina virtual só para abri-lo. Por isso o autor fez o seu próprio, nativo para macOS.",
    "compare_title": "De cinco passos para dois.",
    "compare_lead": "Alterne entre antes e depois para ver o que editar uma única entrada exigia.",
    "native_title": "Nativo, não adaptado",
    "native_text": "Janelas em SwiftUI, a barra de menus do macOS, um atalho para cada ação e senhas guardadas no Keychain.",
    "schema_title": "Lê o seu schema",
    "schema_text": "Nomes de atributos e object classes são sugeridos a partir do schema do próprio servidor, com a herança de classes resolvida.",
    "safe_title": "Cuidadoso com seus dados",
    "safe_text": "Modo somente leitura por conexão, senhas com hash antes de sair do seu Mac e a contagem de entradas afetadas antes de qualquer exclusão recursiva."
  }
}
</i18n>
