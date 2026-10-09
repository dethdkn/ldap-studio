export default defineEventHandler(async (event) => {
  const { syncPassword } = useRuntimeConfig(event)
  const { password } = getQuery(event)

  if (!syncPassword || password !== syncPassword) {
    throw createError({ statusCode: 401, statusMessage: 'Unauthorized' })
  }

  const { result } = await runTask('github:sync')

  return { result }
})
