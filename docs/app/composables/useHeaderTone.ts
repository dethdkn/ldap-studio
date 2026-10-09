type SectionTone = 'light' | 'gray' | 'dark'

const HEADER_PROBE = 26

function readTone(): SectionTone {
  const sections = [...document.querySelectorAll<HTMLElement>('[data-tone]')]
  const below = sections.findLast((section) => section.getBoundingClientRect().top <= HEADER_PROBE)
  const tone = below?.dataset.tone

  return tone === 'dark' || tone === 'gray' ? tone : 'light'
}

function useHeaderTone(): Ref<SectionTone> {
  const tone = ref<SectionTone>('dark')
  const route = useRoute()

  function update(): void {
    tone.value = readTone()
  }

  useEventListener('scroll', update, { passive: true })
  onMounted(update)
  watch(
    () => route.fullPath,
    () => nextTick(update),
  )

  return tone
}

export type { SectionTone }
export { useHeaderTone }
