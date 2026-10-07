<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const { focusEntry } = useSections()

  const layers = computed(() => [
    {
      entry: 'swiftui',
      icon: 'ph:app-window',
      name: 'SwiftUI',
      role: t('swiftui_role'),
      text: t('swiftui_text'),
    },
    {
      entry: 'core',
      icon: 'ph:cpu',
      name: 'libldapstudio',
      role: t('core_role'),
      text: t('core_text'),
    },
    {
      entry: 'openldap',
      icon: 'ph:stack',
      name: 'OpenLDAP · OpenSSL · libxcrypt',
      role: t('openldap_role'),
      text: t('openldap_text'),
    },
  ])
</script>

<template>
  <PageSection id="inside">
    <div class="lg:w-1/2">
      <SectionHeading rdn="ou=inside" :title="t('title')" :lead="t('lead')" />

      <ol
        class="relative mt-12 space-y-4 before:absolute before:top-8 before:bottom-8 before:left-[2.1rem] before:w-px before:bg-line">
        <Reveal v-for="(layer, index) in layers" :key="layer.entry" as="li" :delay="index * 0.1">
          <div
            class="glass relative flex gap-5 rounded-3xl p-5 transition duration-300 hover:border-accent/40"
            @pointerenter="focusEntry(layer.entry)"
            @pointerleave="focusEntry(null)">
            <span
              class="relative z-10 grid size-11 shrink-0 place-items-center rounded-2xl bg-accent text-white shadow-lg shadow-accent/30">
              <Icon :name="layer.icon" class="text-xl" />
            </span>
            <div>
              <p class="font-mono text-[0.7rem] text-accent-ink">{{ layer.role }}</p>
              <h3 class="mt-1 text-lg font-semibold">{{ layer.name }}</h3>
              <p class="mt-2 leading-relaxed text-muted">{{ layer.text }}</p>
            </div>
          </div>
        </Reveal>
      </ol>
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Native from the window down to the wire.",
    "lead": "No JVM, no Electron. Three layers, each one doing the job it is best at.",
    "swiftui_role": "the interface",
    "swiftui_text": "Windows, sheets, menus and shortcuts written in SwiftUI, with connection passwords stored in the macOS Keychain.",
    "core_role": "the C core",
    "core_text": "A small C library that runs every LDAP operation, parses the schema, resizes photos and hashes passwords.",
    "openldap_role": "the foundations",
    "openldap_text": "Proven libraries for the LDAP protocol, TLS, and the crypt(3) password formats."
  },
  "pt": {
    "title": "Nativo da janela até a rede.",
    "lead": "Sem JVM, sem Electron. Três camadas, cada uma fazendo o que faz de melhor.",
    "swiftui_role": "a interface",
    "swiftui_text": "Janelas, painéis, menus e atalhos escritos em SwiftUI, com as senhas das conexões guardadas no Keychain do macOS.",
    "core_role": "o núcleo em C",
    "core_text": "Uma pequena biblioteca em C que executa cada operação LDAP, interpreta o schema, redimensiona fotos e gera hashes de senha.",
    "openldap_role": "a fundação",
    "openldap_text": "Bibliotecas consagradas para o protocolo LDAP, para TLS e para os formatos de senha do crypt(3)."
  }
}
</i18n>
