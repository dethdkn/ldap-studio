<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })

  const reasons = computed(() => [
    { icon: 'ph:apple-logo', title: t('native_title'), text: t('native_text') },
    { icon: 'ph:graph', title: t('schema_title'), text: t('schema_text') },
    { icon: 'ph:shield-check', title: t('safe_title'), text: t('safe_text') },
  ])
</script>

<template>
  <PageSection id="why">
    <SectionHeading rdn="ou=why" :title="t('title')" :lead="t('lead')" />
    <Reveal :delay="0.15" class="mt-10 max-w-xl">
      <DemoWorkflow />
    </Reveal>

    <div class="mt-20 grid gap-4 md:grid-cols-3">
      <Reveal v-for="(reason, index) in reasons" :key="reason.title" :delay="index * 0.08">
        <TiltCard>
          <div class="p-7">
            <span
              class="grid size-11 place-items-center rounded-2xl bg-accent-soft text-accent-ink">
              <Icon :name="reason.icon" class="text-xl" />
            </span>
            <h3 class="type-title mt-6 text-xl">{{ reason.title }}</h3>
            <p class="mt-3 leading-relaxed text-muted">{{ reason.text }}</p>
          </div>
        </TiltCard>
      </Reveal>
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Built because the alternative was a Windows VM.",
    "lead": "LDAP Studio started at CBPF, the Brazilian research center where its author works. The only client that handled their directory well was LDAP Admin: Windows-only and not updated in years. Every lookup meant booting a virtual machine.",
    "native_title": "Native, not ported",
    "native_text": "SwiftUI windows, the macOS menu bar, a shortcut for every action and passwords kept in the Keychain.",
    "schema_title": "Reads your schema",
    "schema_text": "Attribute names and object classes autocomplete from the server's own schema, with superior-class inheritance resolved.",
    "safe_title": "Careful with your data",
    "safe_text": "Read-only mode per connection, passwords hashed before they leave your Mac, and a count of affected entries before any recursive delete."
  },
  "pt": {
    "title": "Nasceu porque a alternativa era uma VM com Windows.",
    "lead": "O LDAP Studio começou no CBPF, o centro de pesquisa onde seu autor trabalha. O único cliente que dava conta do diretório de lá era o LDAP Admin: só para Windows e sem atualização há anos. Cada consulta exigia ligar uma máquina virtual.",
    "native_title": "Nativo, não adaptado",
    "native_text": "Janelas em SwiftUI, a barra de menus do macOS, um atalho para cada ação e senhas guardadas no Keychain.",
    "schema_title": "Lê o seu schema",
    "schema_text": "Nomes de atributos e object classes são sugeridos a partir do schema do próprio servidor, com a herança de classes resolvida.",
    "safe_title": "Cuidadoso com seus dados",
    "safe_text": "Modo somente leitura por conexão, senhas com hash antes de sair do seu Mac e a contagem de entradas afetadas antes de qualquer exclusão recursiva."
  }
}
</i18n>
