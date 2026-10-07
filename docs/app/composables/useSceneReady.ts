function useSceneReady(): Ref<boolean> {
  return useState<boolean>('scene-ready', () => false)
}

export { useSceneReady }
