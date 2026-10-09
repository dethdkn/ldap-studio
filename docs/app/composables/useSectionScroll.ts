type SectionName =
  | 'top'
  | 'why'
  | 'inside'
  | 'features'
  | 'playground'
  | 'install'
  | 'guide'
  | 'faq'
  | 'contributors'
  | 'download'
  | 'changelog'

const sections = new Map<SectionName, HTMLElement>()

interface SectionScroll {
  scrollToSection: (name: SectionName) => Promise<void>
}

function usePendingSection(): Ref<SectionName | null> {
  return useState<SectionName | null>('pending-section', () => null)
}

function scrollBehavior(): ScrollBehavior {
  return globalThis.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth'
}

function useSectionScroll(): SectionScroll {
  const pending = usePendingSection()
  const localePath = useLocalePath()

  async function scrollToSection(name: SectionName): Promise<void> {
    const element = sections.get(name)

    if (element) {
      element.scrollIntoView({ behavior: scrollBehavior() })
      return
    }

    pending.value = name
    await navigateTo(localePath('/'))
  }

  return { scrollToSection }
}

function useSectionAnchor(name: SectionName, element: Readonly<Ref<HTMLElement | null>>): void {
  const pending = usePendingSection()

  onMounted(() => {
    if (!element.value) return

    sections.set(name, element.value)
    if (pending.value !== name) return

    pending.value = null
    element.value.scrollIntoView({ behavior: 'instant' })
  })

  onBeforeUnmount(() => {
    if (sections.get(name) === element.value) sections.delete(name)
  })
}

export type { SectionName }
export { usePendingSection, useSectionAnchor, useSectionScroll }
