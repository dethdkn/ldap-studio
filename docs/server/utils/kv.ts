import type { KVNamespace, KVNamespacePutOptions } from '@cloudflare/workers-types'

function getKV(): KVNamespace {
  // oxlint-disable-next-line no-underscore-dangle
  const KV = globalThis.KV ?? globalThis.__env__?.KV

  if (!KV) throw new Error('KV not found')

  return KV
}

export async function readKV<Type>(key: string): Promise<Type> {
  const value = await getKV().get(key)

  if (!value) throw new Error('Key not found')

  return destr<Type>(value)
}

export async function writeKV(
  key: string,
  value: unknown,
  options?: KVNamespacePutOptions,
): Promise<void> {
  await getKV().put(key, typeof value === 'string' ? value : JSON.stringify(value), options)
}
