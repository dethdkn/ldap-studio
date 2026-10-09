function formatSize(bytes: number): string {
  return `${(bytes / 1_000_000).toFixed(1)} MB`
}

function formatDate(date: string, locale: string): string {
  return new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }).format(new Date(date))
}

function formatCount(count: number, locale: string): string {
  return new Intl.NumberFormat(locale, { notation: 'compact' }).format(count)
}

export { formatCount, formatDate, formatSize }
