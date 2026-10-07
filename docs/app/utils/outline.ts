interface Branch {
  id: string
  entries: string[]
}

const ROOT_RDN = 'dc=ldap-studio'

const OUTLINE: Branch[] = [
  { id: 'why', entries: [] },
  { id: 'inside', entries: ['swiftui', 'core', 'openldap'] },
  {
    id: 'features',
    entries: [
      'browse',
      'search',
      'edit',
      'passwords',
      'ldif',
      'schema',
      'connections',
      'photos',
      'server',
    ],
  },
  { id: 'playground', entries: ['filter', 'password', 'tree'] },
  { id: 'install', entries: ['download', 'move', 'allow', 'unblock'] },
  { id: 'guide', entries: ['connect', 'shortcuts'] },
  { id: 'faq', entries: [] },
]

function dnOf(branchId: string | null, entryId: string | null = null): string[] {
  const branch = OUTLINE.find((item) => item.id === branchId)
  if (!branch) return [ROOT_RDN]

  const path = [`ou=${branch.id}`, ROOT_RDN]
  if (entryId && branch.entries.includes(entryId)) path.unshift(`cn=${entryId}`)

  return path
}

export type { Branch }
export { dnOf, OUTLINE, ROOT_RDN }
