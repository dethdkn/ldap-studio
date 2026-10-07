import {
  BufferAttribute,
  Color,
  ExtrudeGeometry,
  Group,
  Mesh,
  MeshBasicMaterial,
  MeshPhysicalMaterial,
  Shape,
  Vector2,
} from 'three'
import type { Material, ShapePath } from 'three'
import { SVGLoader } from 'three/addons/loaders/SVGLoader.js'

import { GLYPH } from './glyph'
import { createBaseHighlight, createGlyphHighlight } from './highlight'
import { withRimLight } from './rim'
import { createGlyphShadow } from './shadow'

interface Icon {
  group: Group
  dispose: () => void
}

const SIZE = 2
const DEPTH = 0.2
const BEVEL = 0.07
const SQUIRCLE_POWER = 5
const SQUIRCLE_POINTS = 160
const GLYPH_HEIGHT = 1.33
const TOP_COLOR = '#4794ff'
const BOTTOM_COLOR = '#005ee7'
const GLYPH_Z = 0.23
const FRONT_Z = DEPTH / 2 + BEVEL
const SHADOW_Z = FRONT_Z + 0.002
const GLYPH_DEPTH = 1.4
const GLYPH_BEVEL = 1.1

function squirclePoints(radius: number): Vector2[] {
  return Array.from({ length: SQUIRCLE_POINTS }, (_, index) => {
    const angle = (index / SQUIRCLE_POINTS) * Math.PI * 2
    const x = Math.sign(Math.cos(angle)) * Math.abs(Math.cos(angle)) ** (2 / SQUIRCLE_POWER)
    const y = Math.sign(Math.sin(angle)) * Math.abs(Math.sin(angle)) ** (2 / SQUIRCLE_POWER)

    return new Vector2(x * radius, y * radius)
  })
}

function createGradientSquircle(): ExtrudeGeometry {
  const geometry = new ExtrudeGeometry(new Shape(squirclePoints(SIZE / 2 - BEVEL)), {
    depth: DEPTH,
    bevelEnabled: true,
    bevelThickness: BEVEL,
    bevelSize: BEVEL,
    bevelSegments: 8,
  })
  geometry.translate(0, 0, -DEPTH / 2)
  const position = geometry.getAttribute('position')
  const colors = new Float32Array(position.count * 3)
  const top = new Color(TOP_COLOR)
  const bottom = new Color(BOTTOM_COLOR)
  const color = new Color()

  for (let index = 0; index < position.count; index += 1) {
    color
      .copy(bottom)
      .lerp(top, position.getY(index) / SIZE + 0.5)
      .toArray(colors, index * 3)
  }

  geometry.setAttribute('color', new BufferAttribute(colors, 3))

  return geometry
}

function createBaseMaterial(): MeshPhysicalMaterial {
  const material = new MeshPhysicalMaterial({
    vertexColors: true,
    roughness: 0.4,
    clearcoat: 0.6,
    clearcoatRoughness: 0.2,
  })

  return withRimLight(material, { color: '#dbe8ff', power: 6, intensity: 0.7 })
}

function createGlassMaterial(): MeshPhysicalMaterial {
  const material = new MeshPhysicalMaterial({
    color: '#ffffff',
    emissive: '#ffffff',
    emissiveIntensity: 0.52,
    transmission: 0.8,
    thickness: 0.9,
    roughness: 0.3,
    ior: 1.5,
    dispersion: 4,
    clearcoat: 1,
    clearcoatRoughness: 0.02,
    envMapIntensity: 2.2,
  })

  return withRimLight(material, { color: '#ffffff', power: 1.2, intensity: 1 })
}

interface GlyphLayer {
  layer: Mesh
  highlight: Mesh
}

function createGlyphLayer(
  path: ShapePath,
  svgPath: string,
  material: MeshPhysicalMaterial,
): GlyphLayer {
  const geometry = new ExtrudeGeometry(path.toShapes(), {
    depth: GLYPH_DEPTH,
    bevelEnabled: true,
    bevelThickness: GLYPH_BEVEL,
    bevelSize: 0.32,
    bevelSegments: 12,
    curveSegments: 24,
  })
  geometry.computeBoundingBox()
  const bounds = {
    top: geometry.boundingBox?.min.y ?? 0,
    bottom: geometry.boundingBox?.max.y ?? GLYPH.height,
  }
  geometry.translate(-GLYPH.width / 2, -GLYPH.height / 2, 0)

  const scale = GLYPH_HEIGHT / GLYPH.height
  const layer = new Mesh(geometry, material)
  const highlight = createGlyphHighlight(svgPath, GLYPH.width, GLYPH.height, bounds)
  highlight.position.z = GLYPH_DEPTH + GLYPH_BEVEL + 0.05
  layer.scale.set(scale, -scale, scale)
  layer.position.z = GLYPH_Z
  layer.add(highlight)

  return { layer, highlight }
}

function createGlyphLayers(material: MeshPhysicalMaterial): GlyphLayer[] {
  const markup = `<svg xmlns="http://www.w3.org/2000/svg">${GLYPH.paths.map((path) => `<path d="${path}"/>`).join('')}</svg>`
  const { paths } = new SVGLoader().parse(markup)

  return paths.map((path, index) => createGlyphLayer(path, GLYPH.paths[index] ?? '', material))
}

function disposeMesh(mesh: Mesh): void {
  const materials: Material[] = Array.isArray(mesh.material) ? mesh.material : [mesh.material]
  mesh.geometry.dispose()

  for (const material of materials) {
    if (material instanceof MeshBasicMaterial) material.map?.dispose()
    material.dispose()
  }
}

function createIcon(): Icon {
  const group = new Group()
  const baseMaterial = createBaseMaterial()
  const glassMaterial = createGlassMaterial()
  const base = new Mesh(createGradientSquircle(), baseMaterial)
  const glyphLayers = createGlyphLayers(glassMaterial)
  const layers = glyphLayers.map(({ layer }) => layer)
  const baseHighlight = createBaseHighlight(squirclePoints(SIZE / 2), SIZE)
  baseHighlight.position.z = FRONT_Z + 0.004
  base.add(baseHighlight)

  const shadow = createGlyphShadow(SIZE, GLYPH_HEIGHT)
  shadow.position.z = SHADOW_Z

  group.add(base, shadow, ...layers)

  function dispose(): void {
    const highlights = glyphLayers.map(({ highlight }) => highlight)
    for (const mesh of [base, baseHighlight, shadow, ...layers, ...highlights]) disposeMesh(mesh)
  }

  return { group, dispose }
}

export type { Icon }
export { createIcon }
