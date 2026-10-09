import type { KVNamespace } from '@cloudflare/workers-types'

declare global {
  var KV: KVNamespace | undefined
  // oxlint-disable-next-line no-underscore-dangle
  var __env__: { KV: KVNamespace | undefined } | undefined
}
