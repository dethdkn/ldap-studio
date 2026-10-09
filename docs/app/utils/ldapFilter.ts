type FilterOperator = 'equals' | 'contains' | 'starts' | 'ends' | 'present' | 'not' | 'gte' | 'lte'

type FilterJoin = '&' | '|'

type FilterTokenKind = 'paren' | 'logic' | 'attribute' | 'comparator' | 'value' | 'wildcard'

interface FilterCondition {
  id: number
  attribute: string
  operator: FilterOperator
  value: string
}

interface FilterToken {
  text: string
  kind: FilterTokenKind
}

const FORMATS: Record<FilterOperator, (attribute: string, value: string) => string> = {
  equals: (attribute, value) => `(${attribute}=${value})`,
  contains: (attribute, value) => `(${attribute}=*${value}*)`,
  starts: (attribute, value) => `(${attribute}=${value}*)`,
  ends: (attribute, value) => `(${attribute}=*${value})`,
  present: (attribute) => `(${attribute}=*)`,
  not: (attribute, value) => `(!(${attribute}=${value}))`,
  gte: (attribute, value) => `(${attribute}>=${value})`,
  lte: (attribute, value) => `(${attribute}<=${value})`,
}

const TOKEN_PATTERN =
  /(?<paren>[()])|(?<logic>[&|!])|(?<attribute>[\w.;-]+)(?<comparator>~=|>=|<=|=)(?<value>[^()]*)/gu

function escapeFilterValue(value: string): string {
  return value.replaceAll(
    /[\\*()\0]/gu,
    (char) => `\\${(char.codePointAt(0) ?? 0).toString(16).padStart(2, '0')}`,
  )
}

function buildFilter(conditions: FilterCondition[], join: FilterJoin): string {
  const parts = conditions.map(({ attribute, operator, value }) =>
    FORMATS[operator](attribute, escapeFilterValue(value)),
  )

  if (parts.length === 0) return '(objectClass=*)'
  if (parts.length === 1) return parts[0] ?? ''

  return `(${join}${parts.join('')})`
}

function valueTokens(value: string): FilterToken[] {
  return value
    .split(/(?<wildcard>\*)/u)
    .filter(Boolean)
    .map((text) => ({ text, kind: text === '*' ? 'wildcard' : 'value' }))
}

function tokenizeFilter(filter: string): FilterToken[] {
  const tokens: FilterToken[] = []

  for (const { groups } of filter.matchAll(TOKEN_PATTERN)) {
    if (groups?.paren) tokens.push({ text: groups.paren, kind: 'paren' })
    else if (groups?.logic) tokens.push({ text: groups.logic, kind: 'logic' })
    else {
      tokens.push(
        { text: groups?.attribute ?? '', kind: 'attribute' },
        { text: groups?.comparator ?? '', kind: 'comparator' },
        ...valueTokens(groups?.value ?? ''),
      )
    }
  }

  return tokens
}

export type { FilterCondition, FilterJoin, FilterOperator, FilterToken, FilterTokenKind }
export { buildFilter, escapeFilterValue, tokenizeFilter }
