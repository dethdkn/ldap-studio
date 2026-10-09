import github from '~/data/github.json'

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

const RELEASES: Release[] = github.releases
const LATEST_RELEASE: Release | null = RELEASES[0] ?? null
const CONTRIBUTORS: Contributor[] = github.contributors
const STARS: number = github.stars

export type { Contributor, Release, ReleaseFile }
export { CONTRIBUTORS, LATEST_RELEASE, RELEASES, STARS }
