<script setup lang="ts">
  const WIDE = new Set(['browse', 'connections', 'server'])

  const { t } = useI18n({ useScope: 'local' })

  const features = computed(() => [
    {
      entry: 'browse',
      icon: 'ph:tree-structure',
      title: t('browse_title'),
      text: t('browse_text'),
      points: [t('browse_p1'), t('browse_p2'), t('browse_p3')],
      example: 'dc=example,dc=org\n└─ ou=people  (128)\n   └─ uid=alice',
    },
    {
      entry: 'search',
      icon: 'ph:magnifying-glass',
      title: t('search_title'),
      text: t('search_text'),
      points: [t('search_p1'), t('search_p2'), t('search_p3')],
      example: '(&(objectClass=inetOrgPerson)\n  (mail=*@example.org))',
    },
    {
      entry: 'edit',
      icon: 'ph:pencil-simple-line',
      title: t('edit_title'),
      text: t('edit_text'),
      points: [t('edit_p1'), t('edit_p2'), t('edit_p3')],
      example: '  mail: alice@example.org\n+ telephoneNumber: +55 21 5555-0100',
    },
    {
      entry: 'passwords',
      icon: 'ph:key',
      title: t('passwords_title'),
      text: t('passwords_text'),
      points: [t('passwords_p1'), t('passwords_p2'), t('passwords_p3')],
      example: 'userPassword:\n  {PBKDF2-SHA512}100000$Zk3q…$9xQe…',
    },
    {
      entry: 'ldif',
      icon: 'ph:file-text',
      title: t('ldif_title'),
      text: t('ldif_text'),
      points: [t('ldif_p1'), t('ldif_p2'), t('ldif_p3')],
      example:
        'dn: uid=alice,ou=people,dc=example,dc=org\nchangetype: modify\nreplace: title\ntitle: Directory admin',
    },
    {
      entry: 'schema',
      icon: 'ph:graph',
      title: t('schema_title'),
      text: t('schema_text'),
      points: [t('schema_p1'), t('schema_p2')],
      example: 'inetOrgPerson\n→ organizationalPerson → person → top',
    },
    {
      entry: 'connections',
      icon: 'ph:plugs-connected',
      title: t('connections_title'),
      text: t('connections_text'),
      points: [t('connections_p1'), t('connections_p2'), t('connections_p3')],
      example: 'ldaps://ldap.example.org:636\nbind: cn=admin,dc=example,dc=org',
    },
    {
      entry: 'photos',
      icon: 'ph:user-square',
      title: t('photos_title'),
      text: t('photos_text'),
      points: [t('photos_p1')],
      example: 'photo.png  1920×1080\n→ jpegPhoto  300×300 JPEG',
    },
    {
      entry: 'server',
      icon: 'ph:hard-drives',
      title: t('server_title'),
      text: t('server_text'),
      points: [t('server_p1'), t('server_p2'), t('server_p3')],
      example: 'supportedLDAPVersion: 3\nsupportedControl: 1.2.840.113556.1.4.319',
    },
  ])
</script>

<template>
  <PageSection name="features" tone="gray">
    <SectionHeading :eyebrow="t('eyebrow')" :title="t('title')" :lead="t('lead')" />

    <div class="mt-16 grid gap-5 md:grid-cols-2 lg:grid-cols-3">
      <Reveal
        v-for="(feature, index) in features"
        :key="feature.entry"
        :delay="(index % 3) * 0.08"
        :class="WIDE.has(feature.entry) && 'lg:col-span-2'">
        <FeatureCard
          :icon="feature.icon"
          :title="feature.title"
          :text="feature.text"
          :points="feature.points"
          :example="feature.example" />
      </Reveal>
    </div>
  </PageSection>
</template>

<i18n lang="json">
{
  "en": {
    "eyebrow": "Features",
    "title": "Everything you do in a directory, in one window.",
    "lead": "From a quick lookup to moving whole subtrees, without leaving the keyboard.",
    "browse_title": "Browse the tree",
    "browse_text": "Expand any branch, filter it as you type and see how many children each container holds.",
    "browse_p1": "Jump straight to any DN",
    "browse_p2": "Bookmarks for each connection",
    "browse_p3": "Multi-select and drag to move",
    "search_title": "Search with real filters",
    "search_text": "Write RFC 4515 filters by hand or build them visually, then pin the ones you use every day.",
    "search_p1": "Visual filter builder",
    "search_p2": "Pinned filters and search history",
    "search_p3": "Search scoped to a branch",
    "edit_title": "Edit entries",
    "edit_text": "Add, edit and delete attributes, binary values included, with names suggested by the server's schema.",
    "edit_p1": "Guided new entry",
    "edit_p2": "Group membership editor",
    "edit_p3": "Move, copy and rename whole subtrees",
    "passwords_title": "Hash passwords locally",
    "passwords_text": "userPassword is hashed on your Mac. The plaintext is never stored or sent as is.",
    "passwords_p1": "PBKDF2-SHA512 by default",
    "passwords_p2": "SSHA, SMD5, SHA1 and MD5",
    "passwords_p3": "Unix, MD5, SHA-256 and SHA-512 crypt",
    "ldif_title": "Speak LDIF",
    "ldif_text": "Import and export LDIF files, or write and run LDIF in an editor with syntax highlighting.",
    "ldif_p1": "Export a whole subtree",
    "ldif_p2": "Copy any entry as LDIF",
    "ldif_p3": "Run LDIF against the server",
    "schema_title": "Read the schema",
    "schema_text": "Browse object classes and attributes, with superior-class inheritance resolved for you.",
    "schema_p1": "Jump from an attribute to its definition",
    "schema_p2": "Autocomplete driven by the schema",
    "connections_title": "Every server at hand",
    "connections_text": "Save connections with SSL or StartTLS, trust certificates per server and keep passwords in the Keychain.",
    "connections_p1": "Favorites and read-only mode",
    "connections_p2": "Import from LDAP Admin (.lcf)",
    "connections_p3": "Import and export as JSON",
    "photos_title": "Set photos",
    "photos_text": "Set jpegPhoto from any image. It is resized and center-cropped to 300×300 for you.",
    "photos_p1": "Shown in the entry header",
    "server_title": "Know your server",
    "server_text": "Check what the server supports, test credentials and follow every operation as it runs.",
    "server_p1": "Server info panel",
    "server_p2": "Test Bind and password-policy card",
    "server_p3": "Operation log"
  },
  "pt": {
    "eyebrow": "Recursos",
    "title": "Tudo o que você faz num diretório, numa janela só.",
    "lead": "De uma consulta rápida até mover subárvores inteiras, sem tirar as mãos do teclado.",
    "browse_title": "Navegue pela árvore",
    "browse_text": "Expanda qualquer ramo, filtre enquanto digita e veja quantos filhos cada contêiner tem.",
    "browse_p1": "Vá direto para qualquer DN",
    "browse_p2": "Favoritos em cada conexão",
    "browse_p3": "Seleção múltipla e arrastar para mover",
    "search_title": "Pesquise com filtros de verdade",
    "search_text": "Escreva filtros RFC 4515 à mão ou monte visualmente, e fixe os que você usa todo dia.",
    "search_p1": "Construtor visual de filtros",
    "search_p2": "Filtros fixados e histórico de buscas",
    "search_p3": "Busca restrita a um ramo",
    "edit_title": "Edite entradas",
    "edit_text": "Adicione, edite e apague atributos, inclusive valores binários, com nomes sugeridos pelo schema do servidor.",
    "edit_p1": "Criação guiada de entradas",
    "edit_p2": "Editor de membros de grupos",
    "edit_p3": "Mova, copie e renomeie subárvores inteiras",
    "passwords_title": "Hash de senha local",
    "passwords_text": "O userPassword recebe o hash no seu Mac. A senha em texto puro nunca é salva nem enviada.",
    "passwords_p1": "PBKDF2-SHA512 por padrão",
    "passwords_p2": "SSHA, SMD5, SHA1 e MD5",
    "passwords_p3": "crypt Unix, MD5, SHA-256 e SHA-512",
    "ldif_title": "Fale LDIF",
    "ldif_text": "Importe e exporte arquivos LDIF, ou escreva e execute LDIF num editor com destaque de sintaxe.",
    "ldif_p1": "Exporte uma subárvore inteira",
    "ldif_p2": "Copie qualquer entrada como LDIF",
    "ldif_p3": "Execute LDIF no servidor",
    "schema_title": "Leia o schema",
    "schema_text": "Navegue por object classes e atributos, com a herança de classes já resolvida.",
    "schema_p1": "Pule de um atributo para a definição dele",
    "schema_p2": "Autocompletar guiado pelo schema",
    "connections_title": "Todos os servidores à mão",
    "connections_text": "Salve conexões com SSL ou StartTLS, confie em certificados por servidor e guarde senhas no Keychain.",
    "connections_p1": "Favoritos e modo somente leitura",
    "connections_p2": "Importação do LDAP Admin (.lcf)",
    "connections_p3": "Importação e exportação em JSON",
    "photos_title": "Defina fotos",
    "photos_text": "Defina o jpegPhoto a partir de qualquer imagem. Ela é redimensionada e recortada no centro em 300×300.",
    "photos_p1": "Exibida no cabeçalho da entrada",
    "server_title": "Conheça seu servidor",
    "server_text": "Veja o que o servidor suporta, teste credenciais e acompanhe cada operação enquanto ela roda.",
    "server_p1": "Painel de informações do servidor",
    "server_p2": "Test Bind e card de política de senha",
    "server_p3": "Log de operações"
  }
}
</i18n>
