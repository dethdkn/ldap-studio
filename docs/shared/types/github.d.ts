interface ReleaseFile {
  name: string
  size: number
  url: string
}

interface Release {
  version: string
  url: string
  date: string
  notes: string
  file: ReleaseFile | null
}

interface Contributor {
  login: string
  avatar: string
  url: string
  contributions: number
}

interface GitHubData {
  stars: number
  releases: Release[]
  contributors: Contributor[]
}

interface GitHubRepo {
  stargazers_count: number
}

interface GitHubAsset {
  name: string
  size: number
  browser_download_url: string
}

interface GitHubRelease {
  tag_name: string
  html_url: string
  published_at: string
  body_html?: string
  draft: boolean
  assets: GitHubAsset[]
}

interface GitHubContributor {
  login: string
  avatar_url: string
  html_url: string
  contributions: number
}
