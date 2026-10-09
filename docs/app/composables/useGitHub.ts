interface GitHub {
  releases: ComputedRef<Release[]>
  latestRelease: ComputedRef<Release | null>
  contributors: ComputedRef<Contributor[]>
  stars: ComputedRef<number>
}

export default function useGitHub(): GitHub {
  const { data } = useFetch('/api/github', { key: 'github' })

  const releases = computed(() => data.value?.releases ?? [])
  const latestRelease = computed(() => releases.value[0] ?? null)
  const contributors = computed(() => data.value?.contributors ?? [])
  const stars = computed(() => data.value?.stars ?? 0)

  return { releases, latestRelease, contributors, stars }
}
