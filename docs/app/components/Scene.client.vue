<script setup lang="ts">
  import { createStage } from '~/lib/three/stage'
  import type { Stage } from '~/lib/three/stage'
  import type { TreePalette } from '~/lib/three/tree'

  const ready = useSceneReady()
  const { activeBranch, focusedEntry } = useSections()
  const reducedMotion = usePreferredReducedMotion()
  const dark = usePreferredDark()
  const canvas = useTemplateRef<HTMLCanvasElement>('canvas')
  const canvasKey = ref(0)
  let stage: Stage | null = null

  function readPalette(): TreePalette {
    const style = getComputedStyle(document.documentElement)
    const token = (name: string): string => style.getPropertyValue(name).trim()

    return {
      label: token('--muted'),
      line: token('--muted'),
      accent: token('--accent'),
      node: dark.value ? '#c9d5f5' : '#ffffff',
    }
  }

  async function mount(): Promise<void> {
    await document.fonts.load('500 44px "Martian Mono"')
    if (!canvas.value) return

    try {
      stage = createStage(canvas.value, {
        outline: OUTLINE,
        rootRdn: ROOT_RDN,
        palette: readPalette(),
        animate: reducedMotion.value !== 'reduce',
        onReady: () => (ready.value = true),
      })
      stage.focus(activeBranch.value, focusedEntry.value)
    } catch {
      ready.value = false
    }
  }

  function followLastSection(): void {
    const top = document.querySelector('#download')?.getBoundingClientRect().top ?? 0
    stage?.setScrollShift(Math.min(top, 0))
  }

  async function remount(): Promise<void> {
    stage?.dispose()
    stage = null
    canvasKey.value += 1
    await nextTick()
    await mount()
  }

  useEventListener('scroll', followLastSection, { passive: true })
  onMounted(mount)
  onBeforeUnmount(() => stage?.dispose())
  watch([dark, reducedMotion], remount)
  watch([activeBranch, focusedEntry], ([branch, entry]) => stage?.focus(branch, entry))
</script>

<template>
  <canvas
    ref="canvas"
    :key="canvasKey"
    aria-hidden="true"
    class="pointer-events-none fixed inset-0 z-0 size-full transition-opacity duration-1000"
    :class="ready ? 'opacity-100' : 'opacity-0'" />
</template>
