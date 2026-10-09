<script setup lang="ts">
  const UNBLOCK_COMMAND = 'xattr -cr /Applications/ldap-studio.app'
  const BUILD_COMMANDS = [
    'git clone https://github.com/dethdkn/ldap-studio && cd ldap-studio',
    'brew bundle',
    './scripts/build.sh',
  ]

  const { t } = useI18n({ useScope: 'local' })
  const { focusEntry } = useSections()

  const steps = computed(() => [
    { entry: 'download', title: t('download_title'), text: t('download_text') },
    { entry: 'move', title: t('move_title'), text: t('move_text') },
    { entry: 'allow', title: t('allow_title'), text: t('allow_text') },
    { entry: 'unblock', title: t('unblock_title'), text: t('unblock_text') },
  ])
</script>

<template>
  <PageSection id="install">
    <SectionHeading rdn="ou=install" :title="t('title')" :lead="t('lead')" />

    <div class="mt-14 grid grid-cols-1 gap-6 lg:grid-cols-[1.35fr_1fr]">
      <ol class="space-y-3">
        <Reveal v-for="(step, index) in steps" :key="step.entry" as="li" :delay="index * 0.08">
          <div
            class="glass flex gap-5 rounded-3xl p-6 transition duration-300 hover:border-accent/40"
            @pointerenter="focusEntry(step.entry)"
            @pointerleave="focusEntry(null)">
            <span class="type-display w-8 shrink-0 text-3xl text-accent">{{ index + 1 }}</span>
            <div class="min-w-0 flex-1">
              <h3 class="text-lg font-semibold">{{ step.title }}</h3>
              <p class="mt-2 leading-relaxed text-muted">{{ step.text }}</p>
              <DownloadButton
                v-if="step.entry === 'download'"
                icon="ph:download-simple-bold"
                class="mt-5">
                {{ t('download_button') }}
              </DownloadButton>
              <CommandLine
                v-if="step.entry === 'unblock'"
                :command="UNBLOCK_COMMAND"
                class="mt-5" />
            </div>
          </div>
        </Reveal>
      </ol>

      <div class="space-y-3">
        <Reveal :delay="0.1" class="glass rounded-3xl p-6">
          <h3 class="flex items-center gap-2 font-semibold">
            <Icon name="ph:laptop" class="text-accent" />
            {{ t('requirements_title') }}
          </h3>
          <ul class="mt-4 space-y-2 text-muted">
            <li>{{ t('requirements_os') }}</li>
            <li>{{ t('requirements_chip') }}</li>
          </ul>
        </Reveal>

        <Reveal :delay="0.15" class="glass rounded-3xl p-6">
          <h3 class="flex items-center gap-2 font-semibold">
            <Icon name="ph:arrows-clockwise" class="text-accent" />
            {{ t('update_title') }}
          </h3>
          <p class="mt-4 leading-relaxed text-muted">{{ t('update_text') }}</p>
        </Reveal>

        <Reveal :delay="0.2" class="glass rounded-3xl p-6">
          <h3 class="flex items-center gap-2 font-semibold">
            <Icon name="ph:hammer" class="text-accent" />
            {{ t('source_title') }}
          </h3>
          <p class="mt-4 leading-relaxed text-muted">{{ t('source_text') }}</p>
          <div class="mt-4 space-y-2">
            <CommandLine v-for="command in BUILD_COMMANDS" :key="command" :command="command" />
          </div>
        </Reveal>
      </div>
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "title": "Install it in four steps.",
    "lead": "LDAP Studio ships as a zipped app on GitHub. No installer, no account.",
    "download_title": "Download the latest release",
    "download_text": "Get the ldap-studio zip file of the latest version, published on GitHub Releases.",
    "download_button": "Download the zip",
    "move_title": "Move it to Applications",
    "move_text": "Unzip the file and drag ldap-studio.app into your Applications folder.",
    "allow_title": "Allow it to open",
    "allow_text": "The app is not signed with a paid Apple Developer account, so macOS blocks the first launch. Open System Settings → Privacy & Security, scroll down and click Open Anyway.",
    "unblock_title": "Still blocked? Clear the quarantine flag",
    "unblock_text": "Run this in Terminal, then open the app again.",
    "requirements_title": "Requirements",
    "requirements_os": "macOS 26 Tahoe or later",
    "requirements_chip": "Apple Silicon (arm64). There is no Intel build yet.",
    "update_title": "Updating",
    "update_text": "The app checks GitHub for a new version when it launches, and you can check any time from the app menu (Check for Updates…). To update, download the new zip and replace the app in Applications.",
    "source_title": "Build from source",
    "source_text": "Needs Xcode and Homebrew. The script builds a Release app and zips it into the dist folder."
  },
  "pt": {
    "title": "Instale em quatro passos.",
    "lead": "O LDAP Studio é distribuído como um app zipado no GitHub. Sem instalador, sem conta.",
    "download_title": "Baixe a versão mais recente",
    "download_text": "Pegue o arquivo zip do ldap-studio da versão mais recente, publicado no GitHub Releases.",
    "download_button": "Baixar o zip",
    "move_title": "Mova para Aplicativos",
    "move_text": "Descompacte o arquivo e arraste o ldap-studio.app para a pasta Aplicativos.",
    "allow_title": "Permita que ele abra",
    "allow_text": "O app não é assinado com uma conta paga de Apple Developer, então o macOS bloqueia a primeira abertura. Abra Ajustes do Sistema → Privacidade e Segurança, role até o fim e clique em Abrir Mesmo Assim.",
    "unblock_title": "Continua bloqueado? Limpe a quarentena",
    "unblock_text": "Rode isto no Terminal e abra o app de novo.",
    "requirements_title": "Requisitos",
    "requirements_os": "macOS 26 Tahoe ou superior",
    "requirements_chip": "Apple Silicon (arm64). Ainda não existe versão para Intel.",
    "update_title": "Atualizando",
    "update_text": "O app procura uma nova versão no GitHub quando abre, e você pode verificar a qualquer momento pelo menu do app (Check for Updates…). Para atualizar, baixe o novo zip e substitua o app em Aplicativos.",
    "source_title": "Compilar do código-fonte",
    "source_text": "Requer Xcode e Homebrew. O script gera o app em modo Release e o compacta na pasta dist."
  }
}
</i18n>
