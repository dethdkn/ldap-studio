interface Sections {
  activeBranch: Ref<string | null>
  focusedEntry: Ref<string | null>
  dn: ComputedRef<string[]>
  focusEntry: (entryId: string | null) => void
}

const READING_LINE = 0.45

function useSections(): Sections {
  const activeBranch = useState<string | null>('active-branch', () => null)
  const focusedEntry = useState<string | null>('focused-entry', () => null)

  const dn = computed(() => dnOf(activeBranch.value, focusedEntry.value))

  function focusEntry(entryId: string | null): void {
    focusedEntry.value = entryId
  }

  return { activeBranch, focusedEntry, dn, focusEntry }
}

function findActiveSection(): HTMLElement | null {
  const line = window.innerHeight * READING_LINE
  const sections = [...document.querySelectorAll<HTMLElement>('[data-branch]')]

  return sections.findLast((section) => section.getBoundingClientRect().top <= line) ?? null
}

function useSectionTracking(): void {
  const { activeBranch, focusedEntry } = useSections()

  function update(): void {
    const branch = findActiveSection()?.dataset.branch ?? null
    if (branch === activeBranch.value) return

    activeBranch.value = branch
    focusedEntry.value = null
  }

  useEventListener('scroll', useThrottleFn(update, 80, true), { passive: true })
  onMounted(update)
}

export { useSections, useSectionTracking }
