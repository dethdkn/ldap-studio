import { DirectionalLight, NeutralToneMapping, PMREMGenerator, Scene, WebGLRenderer } from 'three'
import type { Camera, Object3D, Texture } from 'three'
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js'

interface Layer {
  add: (...objects: Object3D[]) => void
  resize: (width: number, height: number) => void
  render: (camera: Camera) => void
  dispose: () => void
}

const ENVIRONMENT_INTENSITY = 0.45

function createRenderer(canvas: HTMLCanvasElement): WebGLRenderer {
  const renderer = new WebGLRenderer({
    canvas,
    antialias: true,
    alpha: true,
    powerPreference: 'high-performance',
  })
  renderer.setPixelRatio(Math.min(globalThis.devicePixelRatio, 2))
  renderer.toneMapping = NeutralToneMapping

  return renderer
}

function createEnvironment(renderer: WebGLRenderer): Texture {
  const generator = new PMREMGenerator(renderer)
  const { texture } = generator.fromScene(new RoomEnvironment(), 0.04)
  generator.dispose()

  return texture
}

function createKeyLight(): DirectionalLight {
  const light = new DirectionalLight('#ffffff', 2.2)
  light.position.set(-2.5, 5, 5)

  return light
}

function createLayer(canvas: HTMLCanvasElement): Layer {
  const renderer = createRenderer(canvas)
  const environment = createEnvironment(renderer)
  const scene = new Scene()

  scene.environment = environment
  scene.environmentIntensity = ENVIRONMENT_INTENSITY
  scene.add(createKeyLight())

  function add(...objects: Object3D[]): void {
    scene.add(...objects)
  }

  function resize(width: number, height: number): void {
    renderer.setSize(width, height, false)
  }

  function render(camera: Camera): void {
    renderer.render(scene, camera)
  }

  function dispose(): void {
    environment.dispose()
    renderer.dispose()
  }

  return { add, resize, render, dispose }
}

export type { Layer }
export { createLayer }
