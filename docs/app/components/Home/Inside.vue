<script setup lang="ts">
  const { t } = useI18n({ useScope: 'local' })
  const visual = useTemplateRef<HTMLElement>('visual')
  const { scrollYProgress } = useScroll({ target: visual, offset: ['start 0.95', 'center 0.5'] })

  const layers = computed(() => [
    {
      icon: 'ph:stack-fill',
      name: 'OpenLDAP · OpenSSL · libxcrypt',
      role: t('openldap_role'),
      text: t('openldap_text'),
      fill: 'bg-linear-to-br from-[#3a3a3e] to-[#1c1c1e]',
    },
    {
      icon: 'ph:cpu-fill',
      name: 'libldapstudio',
      role: t('core_role'),
      text: t('core_text'),
      fill: 'bg-linear-to-br from-[#5e5ce6] to-[#2c2a8c]',
    },
    {
      icon: 'ph:app-window-fill',
      name: 'SwiftUI',
      role: t('swiftui_role'),
      text: t('swiftui_text'),
      fill: 'bg-linear-to-br from-[#2997ff] to-[#0050c8]',
    },
  ])
</script>

<template>
  <PageSection name="inside" tone="dark">
    <SectionHeading center :eyebrow="t('eyebrow')" :title="t('title')" :lead="t('lead')" />

    <div class="mt-20 grid items-center gap-16 lg:grid-cols-2">
      <div ref="visual" aria-hidden="true" class="relative h-[30rem] [perspective:1400px]">
        <div class="absolute inset-x-[15%] bottom-0 h-24 rounded-full bg-[#2997ff]/25 blur-3xl" />
        <LayerPlate
          v-for="(layer, index) in layers"
          :key="layer.name"
          :progress="scrollYProgress"
          :index="index"
          :icon="layer.icon"
          :fill="layer.fill" />
      </div>

      <ol class="space-y-8">
        <Reveal
          v-for="(layer, index) in [...layers].reverse()"
          :key="layer.name"
          as="li"
          :delay="index * 0.1"
          class="border-l-2 border-line pl-6 transition-colors duration-300 hover:border-accent">
          <p class="text-sm font-semibold text-accent-ink">{{ layer.role }}</p>
          <h3 class="type-title mt-1 text-2xl">{{ layer.name }}</h3>
          <p class="mt-2 text-muted">{{ layer.text }}</p>
        </Reveal>
      </ol>
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "eyebrow": "Under the hood",
    "title": "Native from the window down to the wire.",
    "lead": "No JVM, no Electron. Three layers, each one doing the job it is best at.",
    "swiftui_role": "The interface",
    "swiftui_text": "Windows, sheets, menus and shortcuts written in SwiftUI, with connection passwords stored in the macOS Keychain.",
    "core_role": "The C core",
    "core_text": "A small C library that runs every LDAP operation, parses the schema, resizes photos and hashes passwords.",
    "openldap_role": "The foundations",
    "openldap_text": "Proven libraries for the LDAP protocol, TLS, and the crypt(3) password formats."
  },
  "pt": {
    "eyebrow": "Por dentro",
    "title": "Nativo da janela até a rede.",
    "lead": "Sem JVM, sem Electron. Três camadas, cada uma fazendo o que faz de melhor.",
    "swiftui_role": "A interface",
    "swiftui_text": "Janelas, painéis, menus e atalhos escritos em SwiftUI, com as senhas das conexões guardadas no Keychain do macOS.",
    "core_role": "O núcleo em C",
    "core_text": "Uma pequena biblioteca em C que executa cada operação LDAP, interpreta o schema, redimensiona fotos e gera hashes de senha.",
    "openldap_role": "A fundação",
    "openldap_text": "Bibliotecas consagradas para o protocolo LDAP, para TLS e para os formatos de senha do crypt(3)."
  }
}
</i18n>
