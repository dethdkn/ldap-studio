const REPO = 'dethdkn/ldap-studio'
const API_URL = `https://api.github.com/repos/${REPO}`
const PER_PAGE = 100
const RECENT_RELEASES = 10
const MAX_CONTRIBUTORS = 20

function toRelease(release: GitHubRelease): Release {
  const file = release.assets.find((asset) => asset.name.endsWith('.zip'))

  return {
    version: release.tag_name,
    url: release.html_url,
    date: release.published_at,
    notes: release.body_html ?? '',
    file: file ? { name: file.name, size: file.size, url: file.browser_download_url } : null,
  }
}

function mergeReleases(recent: Release[], previous: Release[]): Release[] {
  const versions = new Set(recent.map((release) => release.version))
  const oldest = recent.at(-1)?.date

  const older = previous.filter(
    (release) => !versions.has(release.version) && (!oldest || release.date < oldest),
  )

  return [...recent, ...older]
}

export default defineTask({
  meta: {
    name: 'github:sync',
    description: 'Fetch stars, releases and contributors from GitHub and save them on KV',
  },
  async run() {
    const { githubToken } = useRuntimeConfig()

    const api = $fetch.create({
      baseURL: API_URL,
      headers: {
        Accept: 'application/vnd.github.html+json',
        'User-Agent': 'ldap-studio',
        'X-GitHub-Api-Version': '2022-11-28',
        ...(githubToken ? { Authorization: `Bearer ${githubToken}` } : {}),
      },
    })

    const previous = await readKV<GitHubData>('github').catch(() => null)

    const pageSize = previous ? RECENT_RELEASES : PER_PAGE

    const [repo, latest, contributors] = await Promise.all([
      api<GitHubRepo>(''),
      api<GitHubRelease[]>('/releases', { query: { per_page: pageSize } }),
      api<GitHubContributor[]>('/contributors', { query: { per_page: MAX_CONTRIBUTORS } }),
    ])

    const fetched = [...latest]

    if (!previous) {
      let page = 1
      let batch = latest

      while (batch.length === PER_PAGE) {
        page += 1
        // oxlint-disable-next-line no-await-in-loop
        batch = await api<GitHubRelease[]>('/releases', { query: { per_page: PER_PAGE, page } })
        fetched.push(...batch)
      }
    }

    const recent = fetched.filter((release) => !release.draft).map((release) => toRelease(release))

    const complete = !previous || latest.length < pageSize

    const data: GitHubData = {
      stars: repo.stargazers_count,
      releases: complete ? recent : mergeReleases(recent, previous.releases),
      contributors: contributors.map((contributor) => ({
        login: contributor.login,
        avatar: contributor.avatar_url,
        url: contributor.html_url,
        contributions: contributor.contributions,
      })),
    }

    await writeKV('github', data)

    return { result: 'success' }
  },
})
