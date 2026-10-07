import {
  Color,
  CubicBezierCurve3,
  CurvePath,
  Group,
  MathUtils,
  Mesh,
  MeshBasicMaterial,
  MeshStandardMaterial,
  SphereGeometry,
  TubeGeometry,
  Vector3,
} from 'three'
import type { BufferGeometry, Sprite } from 'three'
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js'

import type { Branch } from '~/utils/outline'

import { createLabel, disposeLabel } from './label'

interface TreePalette {
  label: string
  node: string
  line: string
  accent: string
}

interface Tree {
  group: Group
  pivot: Group
  focus: (branchId: string | null, entryId: string | null) => void
  focusPoint: () => Vector3
  update: (delta: number, time: number, opacity: number, animate: boolean) => void
  dispose: () => void
}

interface TreeNode {
  key: string
  parent: string | null
  position: Vector3
  material: MeshStandardMaterial
  label: Sprite
  glow: number
}

interface TreeEdge {
  to: string
  curve: CubicBezierCurve3
  material: MeshBasicMaterial
  glow: number
}

interface Pulse {
  mesh: Mesh
  material: MeshBasicMaterial
}

const BRANCH_SPACING = 3.4
const BRANCH_Y = -2.2
const ENTRY_Y = -4.1
const GLOW_SPEED = 6
const PULSE_COUNT = 3
const PULSE_SPEED = 0.22
const LABEL_OFFSET = new Vector3(0.3, 0, 0)

function branchPosition(index: number, count: number): Vector3 {
  return new Vector3((index - (count - 1) / 2) * BRANCH_SPACING, BRANCH_Y, 0)
}

function entryPosition(branch: Vector3, index: number, count: number): Vector3 {
  const angle = (index / count) * Math.PI * 2
  const radius = 0.5 + count * 0.14

  return new Vector3(
    branch.x + Math.cos(angle) * radius,
    ENTRY_Y - (index % 2) * 0.3,
    Math.sin(angle) * radius,
  )
}

function edgeCurve(from: Vector3, to: Vector3): CubicBezierCurve3 {
  const middle = (from.y + to.y) / 2

  return new CubicBezierCurve3(
    from,
    new Vector3(from.x, middle, from.z),
    new Vector3(to.x, middle, to.z),
    to,
  )
}

function pathTo(outline: Branch[], branchId: string | null, entryId: string | null): string[] {
  const branch = outline.find((item) => item.id === branchId)
  if (!branch) return ['root']

  const path = ['root', branch.id]
  if (entryId && branch.entries.includes(entryId)) path.push(`${branch.id}/${entryId}`)

  return path
}

function createTree(outline: Branch[], rootRdn: string, palette: TreePalette): Tree {
  const group = new Group()
  const pivot = new Group()
  const nodeColor = new Color(palette.node)
  const lineColor = new Color(palette.line)
  const accent = new Color(palette.accent)
  const nodes = new Map<string, TreeNode>()
  const edges: TreeEdge[] = []
  const pulses: Pulse[] = []
  const shapes = {
    root: new RoundedBoxGeometry(0.5, 0.5, 0.14, 4, 0.12),
    branch: new RoundedBoxGeometry(0.34, 0.26, 0.12, 4, 0.06),
    entry: new SphereGeometry(0.075, 20, 12),
    pulse: new SphereGeometry(0.05, 12, 8),
  }
  const geometries: BufferGeometry[] = Object.values(shapes)
  let activePath = ['root']
  let pulsePath = new CurvePath<Vector3>()

  group.add(pivot)

  function addEdge(from: Vector3, to: Vector3, key: string): void {
    const curve = edgeCurve(from, to)
    const geometry = new TubeGeometry(curve, 32, 0.008, 6)
    const material = new MeshBasicMaterial({
      color: lineColor,
      transparent: true,
      depthWrite: false,
    })

    geometries.push(geometry)
    pivot.add(new Mesh(geometry, material))
    edges.push({ to: key, curve, material, glow: 0 })
  }

  function addNode(
    key: string,
    parent: string | null,
    position: Vector3,
    text: string,
    shape: BufferGeometry,
  ): void {
    const material = new MeshStandardMaterial({
      color: nodeColor,
      roughness: 0.35,
      metalness: 0.1,
      transparent: true,
    })
    const mesh = new Mesh(shape, material)
    const label = createLabel(text, palette.label)

    mesh.position.copy(position)
    label.position.copy(position).add(LABEL_OFFSET)
    pivot.add(mesh, label)
    nodes.set(key, { key, parent, position, material, label, glow: 0 })

    const parentNode = parent ? nodes.get(parent) : undefined
    if (parentNode) addEdge(parentNode.position, position, key)
  }

  function addPulses(): void {
    for (let index = 0; index < PULSE_COUNT; index += 1) {
      const material = new MeshBasicMaterial({ color: accent, transparent: true })
      const mesh = new Mesh(shapes.pulse, material)
      pulses.push({ mesh, material })
      pivot.add(mesh)
    }
  }

  function build(): void {
    addNode('root', null, new Vector3(), rootRdn, shapes.root)

    for (const [index, branch] of outline.entries()) {
      const position = branchPosition(index, outline.length)
      addNode(branch.id, 'root', position, `ou=${branch.id}`, shapes.branch)

      for (const [entryIndex, entry] of branch.entries.entries()) {
        const entryPoint = entryPosition(position, entryIndex, branch.entries.length)
        addNode(`${branch.id}/${entry}`, branch.id, entryPoint, `cn=${entry}`, shapes.entry)
      }
    }

    addPulses()
  }

  function focus(branchId: string | null, entryId: string | null): void {
    activePath = pathTo(outline, branchId, entryId)
    pulsePath = new CurvePath<Vector3>()

    for (const edge of edges) {
      if (activePath.includes(edge.to)) pulsePath.add(edge.curve)
    }
  }

  function focusPoint(): Vector3 {
    return nodes.get(activePath[1] ?? 'root')?.position.clone() ?? new Vector3()
  }

  function updateNode(node: TreeNode, delta: number, opacity: number): void {
    node.glow = MathUtils.damp(node.glow, activePath.includes(node.key) ? 1 : 0, GLOW_SPEED, delta)
    node.material.color.copy(node.key === 'root' ? accent : nodeColor).lerp(accent, node.glow)
    node.material.emissive.copy(accent).multiplyScalar(node.glow * 0.45)
    node.material.opacity = opacity

    const isEntry = node.key.includes('/')
    const parentGlow = nodes.get(node.parent ?? '')?.glow ?? 1
    const visibility = isEntry ? parentGlow * (0.55 + 0.45 * node.glow) : 0.4 + 0.6 * node.glow
    node.label.material.opacity = opacity * visibility
  }

  function updateEdge(edge: TreeEdge, delta: number, opacity: number): void {
    edge.glow = MathUtils.damp(edge.glow, activePath.includes(edge.to) ? 1 : 0, GLOW_SPEED, delta)
    edge.material.color.copy(lineColor).lerp(accent, edge.glow)
    edge.material.opacity = opacity * (0.18 + 0.82 * edge.glow)
  }

  function updatePulses(time: number, opacity: number, animate: boolean): void {
    const visible = animate && pulsePath.curves.length > 0

    for (const [index, pulse] of pulses.entries()) {
      pulse.mesh.visible = visible

      if (visible) {
        const progress = (time * PULSE_SPEED + index / PULSE_COUNT) % 1
        pulse.mesh.position.copy(pulsePath.getPointAt(progress))
        pulse.material.opacity = opacity * Math.sin(progress * Math.PI)
      }
    }
  }

  function update(delta: number, time: number, opacity: number, animate: boolean): void {
    group.visible = opacity > 0.01
    if (!group.visible) return

    for (const node of nodes.values()) updateNode(node, delta, opacity)
    for (const edge of edges) updateEdge(edge, delta, opacity)
    updatePulses(time, opacity, animate)
  }

  function dispose(): void {
    for (const geometry of geometries) geometry.dispose()
    for (const edge of edges) edge.material.dispose()
    for (const pulse of pulses) pulse.material.dispose()
    for (const node of nodes.values()) {
      node.material.dispose()
      disposeLabel(node.label)
    }
  }

  build()

  return { group, pivot, focus, focusPoint, update, dispose }
}

export type { Tree, TreePalette }
export { createTree }
