/* oxlint-disable avoid-new */
import type { RouterConfig } from '@nuxt/schema'

type ScrollBehavior = NonNullable<RouterConfig['scrollBehavior']>

export default {
  // oxlint-disable-next-line typescript/no-deprecated
  scrollBehavior(_to, _from, savedPosition): ReturnType<ScrollBehavior> {
    if (usePendingSection().value) return false

    const nuxtApp = useNuxtApp()

    return new Promise((resolve) => {
      nuxtApp.hooks.hookOnce('page:finish', () => {
        resolve(savedPosition ?? { top: 0 })
      })
    })
  },
} satisfies RouterConfig
