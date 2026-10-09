import tailwindcss from '@tailwindcss/vite'

export default defineNuxtConfig({
  modules: [
    '@nuxt/image',
    '@nuxtjs/seo',
    '@nuxtjs/i18n',
    '@vueuse/nuxt',
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
  runtimeConfig: {
    githubToken: '',
  },
  compatibilityDate: '2026-09-30',
  nitro: {
    preset: 'cloudflare_module',
    experimental: { tasks: true },
    scheduledTasks: {
      '0 */3 * * *': ['github:sync'],
    },
    cloudflare: {
      deployConfig: true,
      nodeCompat: true,
      wrangler: {
        name: 'ldap-studio',
        workers_dev: false,
        kv_namespaces: [{ binding: 'KV', id: '2ad76e1b473f4691ab3cc449fcb7a59c' }],
        triggers: { crons: ['0 */3 * * *'] },
        observability: { logs: { enabled: true, head_sampling_rate: 1, invocation_logs: true } },
      },
    },
    imports: {
      imports: [{ name: 'destr', from: 'destr' }],
    },
  },
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
})
