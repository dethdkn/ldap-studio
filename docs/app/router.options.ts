/* oxlint-disable avoid-new */
import type { RouterConfig } from '@nuxt/schema'

type ScrollBehavior = NonNullable<RouterConfig['scrollBehavior']>

export default {
  scrollBehavior(_to, _from, savedPosition): ReturnType<ScrollBehavior> {
    // A section asked to be scrolled into view once the page mounts
    if (usePendingSection().value) return false

    const nuxtApp = useNuxtApp()

    return new Promise((resolve) => {
      nuxtApp.hooks.hookOnce('page:finish', () => {
        resolve(savedPosition ?? { top: 0 })
      })
    })
  },
} satisfies RouterConfig
