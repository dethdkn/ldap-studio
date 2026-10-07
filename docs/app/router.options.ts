/* oxlint-disable no-restricted-globals, typescript/no-explicit-any avoid-new explicit-function-return-type */
import type { RouterConfig } from '@nuxt/schema'

export default {
  scrollBehavior(to, from, savedPosition) {
    const nuxtApp = useNuxtApp()

    if (savedPosition) {
      return new Promise((resolve) => {
        nuxtApp.hooks.hookOnce('page:finish', () => {
          setTimeout(() => {
            resolve(savedPosition)
          }, 50)
        })
      })
    }

    if (to.hash) {
      setTimeout(() => {
        let heading = document.querySelector(`[id="${to.hash.replace('#', '')}"]`)
        heading ??= document.querySelector(`[href$="${to.hash}"]`)
        if (!heading || !('offsetTop' in heading) || typeof heading.offsetTop !== 'number') return
        window.scrollTo({ top: heading.offsetTop, behavior: 'smooth' })
      }, 0)

      return false
    }

    if (from.path !== to.path) {
      window.scrollTo({ top: 0, behavior: 'smooth' })
      return false
    }

    return { top: 0 }
  },
} satisfies RouterConfig
