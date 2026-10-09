export default defineEventHandler(async () => {
  if (import.meta.dev) {
    const example = await useStorage('assets:server').getItem<GitHubData>('github.json')

    if (!example) throw createError({ statusCode: 500, statusMessage: 'Example data not found' })

    return example
  }

  const github = await readKV<GitHubData>('github')

  return github
})
