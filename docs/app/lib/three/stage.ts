import { MathUtils, PerspectiveCamera, Vector2, Vector3 } from 'three'

import type { Branch } from '~/utils/outline'

import { createIcon } from './icon'
import { createLayer } from './layer'
import { dampPose, poseFor } from './poses'
import type { Pose } from './poses'
import { spin, stepSpin } from './spin'
import { createTree } from './tree'
import type { TreePalette } from './tree'

interface StageOptions {
  outline: Branch[]
  rootRdn: string
  palette: TreePalette
  animate: boolean
  onReady: () => void
}

interface Stage {
  focus: (branchId: string | null, entryId: string | null) => void
  setScrollShift: (pixels: number) => void
  dispose: () => void
}

const FOV = 30
const CAMERA_Z = 12
const NARROW_WIDTH = 900
const CONTENT_WIDTH = 1280
const POSE_SPEED = 3.2
const POINTER_SPEED = 4
const MAX_DELTA = 0.05
const HIDDEN_SCALE = 0.02

function createStage(canvas: HTMLCanvasElement, options: StageOptions): Stage {
  const layer = createLayer(canvas)
  const camera = new PerspectiveCamera(FOV, 1, 0.1, 100)
  const icon = createIcon()
  const tree = createTree(options.outline, options.rootRdn, options.palette)
  const viewport = new Vector2()
  let contentWidth = 0
  const pointer = new Vector2()
  const pointerTarget = new Vector2()
  const treePosition = new Vector3()
  let branch: string | null = 'top'
  let narrow = false
  let target = poseFor(branch, narrow)
  const pose = { ...target }
  let scrollShift = 0
  let lastTime = 0
  let frameId = 0
  let ready = false

  camera.position.z = CAMERA_Z
  layer.add(icon.group, tree.group)

  function resize(): void {
    const { innerWidth, innerHeight } = globalThis
    layer.resize(innerWidth, innerHeight)
    camera.aspect = innerWidth / innerHeight
    camera.updateProjectionMatrix()

    viewport.y = 2 * CAMERA_Z * Math.tan(MathUtils.degToRad(FOV / 2))
    viewport.x = viewport.y * camera.aspect
    contentWidth = viewport.x * Math.min(1, CONTENT_WIDTH / innerWidth)
    narrow = innerWidth < NARROW_WIDTH
    target = poseFor(branch, narrow)
  }

  function onPointerMove(event: PointerEvent): void {
    if (!options.animate) return

    pointerTarget.set(
      (event.clientX / globalThis.innerWidth) * 2 - 1,
      1 - (event.clientY / globalThis.innerHeight) * 2,
    )
  }

  function placeIcon(time: number): void {
    const float = options.animate ? Math.sin(time * 0.9) * 0.06 : 0
    const shift = (-scrollShift / globalThis.innerHeight) * viewport.y
    const pitch = -pointer.y * 0.2
    const yaw = spin.angle + pointer.x * 0.3

    icon.group.visible = pose.iconScale > HIDDEN_SCALE
    icon.group.position.set(pose.iconX * contentWidth, pose.iconY * viewport.y + float + shift, 0)
    icon.group.scale.setScalar(Math.max(pose.iconScale, 0.001))
    icon.group.rotation.set(pitch, yaw, 0)
  }

  function placeTree(time: number, delta: number): void {
    const sway = options.animate ? Math.sin(time * 0.12) * 0.2 : 0
    tree.pivot.rotation.set(0.32 - pointer.y * 0.05, sway + pointer.x * 0.12, 0)

    const anchor = tree.focusPoint().applyEuler(tree.pivot.rotation).multiplyScalar(pose.treeScale)
    treePosition.x = MathUtils.damp(
      treePosition.x,
      pose.treeX * contentWidth - anchor.x,
      POSE_SPEED,
      delta,
    )
    treePosition.y = MathUtils.damp(
      treePosition.y,
      pose.treeY * viewport.y - anchor.y,
      POSE_SPEED,
      delta,
    )
    treePosition.z = MathUtils.damp(treePosition.z, -anchor.z, POSE_SPEED, delta)

    tree.group.position.copy(treePosition)
    tree.group.scale.setScalar(pose.treeScale)
    tree.update(delta, time, pose.treeOpacity, options.animate)
  }

  function iconTarget(): Pose {
    if (target.iconScale > 0) return target

    return { ...target, iconX: pose.iconX, iconY: pose.iconY }
  }

  function snapHiddenIcon(): void {
    if (pose.iconScale >= HIDDEN_SCALE) return

    pose.iconX = target.iconX
    pose.iconY = target.iconY
  }

  function frame(now: number): void {
    frameId = requestAnimationFrame(frame)
    const time = now / 1000
    const delta = Math.min(time - lastTime, MAX_DELTA)
    lastTime = time

    stepSpin(delta)
    pointer.x = MathUtils.damp(pointer.x, pointerTarget.x, POINTER_SPEED, delta)
    pointer.y = MathUtils.damp(pointer.y, pointerTarget.y, POINTER_SPEED, delta)
    dampPose(pose, iconTarget(), POSE_SPEED, delta)
    snapHiddenIcon()
    placeIcon(time)
    placeTree(time, delta)
    layer.render(camera)

    if (ready) return
    ready = true
    options.onReady()
  }

  function focus(branchId: string | null, entryId: string | null): void {
    branch = branchId
    target = poseFor(branch, narrow)
    tree.focus(branchId, entryId)
  }

  function setScrollShift(pixels: number): void {
    scrollShift = pixels
  }

  function dispose(): void {
    cancelAnimationFrame(frameId)
    globalThis.removeEventListener('resize', resize)
    globalThis.removeEventListener('pointermove', onPointerMove)
    icon.dispose()
    tree.dispose()
    layer.dispose()
  }

  resize()
  globalThis.addEventListener('resize', resize)
  globalThis.addEventListener('pointermove', onPointerMove, { passive: true })
  frameId = requestAnimationFrame(frame)

  return { focus, setScrollShift, dispose }
}

export type { Stage, StageOptions }
export { createStage }
