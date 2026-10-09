type HashScheme = 'PBKDF2-SHA512' | 'SSHA' | 'SHA'

const HASH_SCHEMES: HashScheme[] = ['PBKDF2-SHA512', 'SSHA', 'SHA']

const PBKDF2_ITERATIONS = 100_000
const PBKDF2_SALT_LENGTH = 16
const SIMPLE_SALT_LENGTH = 8

function toBase64(bytes: Uint8Array): string {
  return btoa(String.fromCodePoint(...bytes))
}

function randomBytes(length: number): Uint8Array<ArrayBuffer> {
  return crypto.getRandomValues(new Uint8Array(length))
}

function concat(first: Uint8Array, second: Uint8Array): Uint8Array<ArrayBuffer> {
  const joined = new Uint8Array(first.length + second.length)
  joined.set(first)
  joined.set(second, first.length)

  return joined
}

async function sha1(bytes: Uint8Array<ArrayBuffer>): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest('SHA-1', bytes))
}

async function hashPbkdf2(password: string): Promise<string> {
  const salt = randomBytes(PBKDF2_SALT_LENGTH)
  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  )
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-512', salt, iterations: PBKDF2_ITERATIONS },
    key,
    512,
  )

  return `{PBKDF2-SHA512}${PBKDF2_ITERATIONS}$${toBase64(salt)}$${toBase64(new Uint8Array(bits))}`
}

async function hashSsha(password: string): Promise<string> {
  const salt = randomBytes(SIMPLE_SALT_LENGTH)
  const digest = await sha1(concat(new TextEncoder().encode(password), salt))

  return `{SSHA}${toBase64(concat(digest, salt))}`
}

async function hashSha(password: string): Promise<string> {
  return `{SHA}${toBase64(await sha1(new TextEncoder().encode(password)))}`
}

const HASHERS: Record<HashScheme, (password: string) => Promise<string>> = {
  'PBKDF2-SHA512': hashPbkdf2,
  SSHA: hashSsha,
  SHA: hashSha,
}

function hashPassword(password: string, scheme: HashScheme): Promise<string> {
  return HASHERS[scheme](password)
}

export type { HashScheme }
export { HASH_SCHEMES, hashPassword }
