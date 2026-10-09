type EntryKind = 'domain' | 'unit' | 'person' | 'group' | 'service'

interface SamplePhoto {
  initials: string
  hue: number
}

interface SampleEntry {
  rdn: string
  dn: string
  kind: EntryKind
  attributes: [string, string][]
  photo?: SamplePhoto
  children: SampleEntry[]
}

type EntrySeed = Omit<SampleEntry, 'dn' | 'children'> & { children?: EntrySeed[] }

const BASE = 'dc=example,dc=org'

function person(uid: string, name: string, title: string, hue: number): EntrySeed {
  const [givenName = name, ...rest] = name.split(' ')
  const sn = rest.at(-1) ?? name

  return {
    rdn: `uid=${uid}`,
    kind: 'person',
    attributes: [
      ['objectClass', 'inetOrgPerson'],
      ['cn', name],
      ['displayName', name],
      ['givenName', givenName],
      ['sn', sn],
      ['title', title],
      ['mail', `${uid}@example.org`],
      ['uid', uid],
      ['jpegPhoto', 'JPEG image'],
      ['userPassword', '{PBKDF2-SHA512}100000$…'],
    ],
    photo: { initials: `${givenName[0] ?? ''}${sn[0] ?? ''}`, hue },
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
      person('ada', 'Ada Lovelace', 'Analyst', 330),
      person('alan', 'Alan Turing', 'Researcher', 200),
      person('grace', 'Grace Hopper', 'Engineer', 150),
      person('katherine', 'Katherine Johnson', 'Mathematician', 30),
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

function flatten(entry: SampleEntry): SampleEntry[] {
  return [entry, ...entry.children.flatMap(flatten)]
}

// Mirror every group's member values as memberOf on the people, like the server does
function withMemberOf(root: SampleEntry): SampleEntry {
  const entries = flatten(root)
  const groupEntries = entries.filter((entry) => entry.kind === 'group')

  for (const entry of entries) {
    for (const groupEntry of groupEntries) {
      if (groupEntry.attributes.some(([name, value]) => name === 'member' && value === entry.dn)) {
        entry.attributes.push(['memberOf', groupEntry.dn])
      }
    }
  }

  return root
}

const SAMPLE_DIRECTORY: SampleEntry = withMemberOf(withDn(SEED, null))

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

export type { EntryKind, SampleEntry, SamplePhoto }
export { collectDns, filterDirectory, SAMPLE_DIRECTORY }
