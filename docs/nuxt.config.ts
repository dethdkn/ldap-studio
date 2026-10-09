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
      meta: [
        { name: 'theme-color', content: '#f2f5fb', media: '(prefers-color-scheme: light)' },
        { name: 'theme-color', content: '#060a17', media: '(prefers-color-scheme: dark)' },
      ],
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
    optimizeDeps: {
      include: [
        'three',
        'three/addons/environments/RoomEnvironment.js',
        'three/addons/geometries/RoundedBoxGeometry.js',
        'three/addons/loaders/SVGLoader.js',
      ],
    },
  },
  nitro: {
    preset: 'cloudflare_module',
    cloudflare: {
      deployConfig: true,
      nodeCompat: true,
      wrangler: {
        name: 'ldap-studio',
        workers_dev: false,
        kv_namespaces: [{ binding: 'KV', id: '2ad76e1b473f4691ab3cc449fcb7a59c' }],
        observability: { logs: { enabled: true, head_sampling_rate: 1, invocation_logs: true } },
      },
    },
    imports: {
      imports: [
        { name: 'destr', from: 'destr' },
      ],
    },
  },
  fonts: {
    families: [
      {
        name: 'Mona Sans',
        provider: 'google',
        weights: ['200 900'],
        styles: ['normal'],
        subsets: ['latin', 'latin-ext'],
        providerOptions: { google: { experimental: { variableAxis: { wdth: [['75', '125']] } } } },
      },
      {
        name: 'Martian Mono',
        provider: 'google',
        weights: ['300 600'],
        styles: ['normal'],
        subsets: ['latin'],
      },
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
