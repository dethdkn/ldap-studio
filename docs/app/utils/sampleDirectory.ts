type EntryKind = 'domain' | 'unit' | 'person' | 'group' | 'service'

interface SampleEntry {
  rdn: string
  dn: string
  kind: EntryKind
  attributes: [string, string][]
  children: SampleEntry[]
}

type EntrySeed = Omit<SampleEntry, 'dn' | 'children'> & { children?: EntrySeed[] }

const BASE = 'dc=example,dc=org'

function person(uid: string, name: string, title: string): EntrySeed {
  return {
    rdn: `uid=${uid}`,
    kind: 'person',
    attributes: [
      ['objectClass', 'inetOrgPerson'],
      ['cn', name],
      ['sn', name.split(' ').at(-1) ?? name],
      ['title', title],
      ['mail', `${uid}@example.org`],
      ['userPassword', '{PBKDF2-SHA512}100000$…'],
    ],
  }
}

function group(cn: string, members: string[]): EntrySeed {
  return {
    rdn: `cn=${cn}`,
    kind: 'group',
    attributes: [
      ['objectClass', 'groupOfNames'],
      ['cn', cn],
      ...members.map((uid): [string, string] => ['member', `uid=${uid},ou=people,${BASE}`]),
    ],
  }
}

function service(cn: string, description: string): EntrySeed {
  return {
    rdn: `cn=${cn}`,
    kind: 'service',
    attributes: [
      ['objectClass', 'applicationProcess'],
      ['cn', cn],
      ['description', description],
    ],
  }
}

function unit(ou: string, description: string, children: EntrySeed[]): EntrySeed {
  return {
    rdn: `ou=${ou}`,
    kind: 'unit',
    attributes: [
      ['objectClass', 'organizationalUnit'],
      ['ou', ou],
      ['description', description],
    ],
    children,
  }
}

const SEED: EntrySeed = {
  rdn: BASE,
  kind: 'domain',
  attributes: [
    ['objectClass', 'dcObject'],
    ['objectClass', 'organization'],
    ['dc', 'example'],
    ['o', 'Example Research Lab'],
  ],
  children: [
    unit('people', 'Everyone with an account', [
      person('ada', 'Ada Lovelace', 'Analyst'),
      person('alan', 'Alan Turing', 'Researcher'),
      person('grace', 'Grace Hopper', 'Engineer'),
      person('katherine', 'Katherine Johnson', 'Mathematician'),
    ]),
    unit('groups', 'Access groups for internal tools', [
      group('admins', ['grace']),
      group('researchers', ['alan', 'katherine', 'ada']),
    ]),
    unit('services', 'Bind accounts used by applications', [
      service('mail', 'Mail relay'),
      service('vpn', 'VPN gateway'),
    ]),
  ],
}

function withDn(seed: EntrySeed, parentDn: string | null): SampleEntry {
  const dn = parentDn ? `${seed.rdn},${parentDn}` : seed.rdn

  return { ...seed, dn, children: (seed.children ?? []).map((child) => withDn(child, dn)) }
}

const SAMPLE_DIRECTORY: SampleEntry = withDn(SEED, null)

function filterDirectory(entry: SampleEntry, query: string): SampleEntry | null {
  if (entry.rdn.toLowerCase().includes(query.toLowerCase())) return entry

  const children = entry.children
    .map((child) => filterDirectory(child, query))
    .filter((child): child is SampleEntry => child !== null)

  return children.length > 0 ? { ...entry, children } : null
}

function collectDns(entry: SampleEntry): string[] {
  return [entry.dn, ...entry.children.flatMap(collectDns)]
}

export type { EntryKind, SampleEntry }
export { collectDns, filterDirectory, SAMPLE_DIRECTORY }
