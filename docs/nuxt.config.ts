import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  modules: [
    '@nuxt/image',
    '@nuxtjs/seo',
    '@nuxtjs/i18n',
    '@vueuse/nuxt',
    'nuxt-security',
    '@nuxt/a11y',
    '@nuxt/hints',
    '@nuxt/fonts',
    '@nuxt/icon',
    'reka-ui/nuxt',
    'motion-v/nuxt',
  ],
  devtools: { enabled: true },
  app: {
    head: {
      templateParams: { separator: '•' },
      meta: [{ name: 'theme-color', content: '#000000' }],
    },
  },
  css: ['~/assets/main.css'],
  site: {
    name: 'LDAP Studio',
    description: 'A native macOS LDAP client for browsing, searching and editing LDAP directories.',
  },
  compatibilityDate: '2026-09-30',
  vite: {
    plugins: [tailwindcss()],
  },
  fonts: {
    families: [
      { name: 'Inter', provider: 'google', weights: ['400 700'], subsets: ['latin', 'latin-ext'] },
      { name: 'JetBrains Mono', provider: 'google', weights: ['400 600'], subsets: ['latin'] },
    ],
  },
  i18n: {
    defaultLocale: 'en',
    locales: [
      { code: 'en', language: 'en-US', name: 'English (US)' },
      { code: 'pt', language: 'pt-BR', name: 'Português (BR)' },
    ],
  },
  icon: {
    serverBundle: { collections: ['ph', 'simple-icons'] },
  },
  linkChecker: { enabled: false },
  security: {
    headers: {
      contentSecurityPolicy: {
        'img-src': ["'self'", 'data:', 'blob:', 'https:'],
        'script-src': [
          "'self'",
          'https:',
          "'unsafe-inline'",
          "'strict-dynamic'",
          "'nonce-{{nonce}}'",
          "'wasm-unsafe-eval'",
        ],
        'worker-src': ["'self'", 'blob:'],
        'frame-src': ["'self'"],
        'object-src': ["'self'"],
      },
      crossOriginEmbedderPolicy: false,
    },
  },
})
