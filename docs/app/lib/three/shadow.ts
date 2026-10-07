import { CanvasTexture, Mesh, MeshBasicMaterial, PlaneGeometry, SRGBColorSpace } from 'three'

import { GLYPH } from './glyph'

const TEXTURE_SIZE = 512
const BLUR = 18
const OFFSET_Y = 14
const COLOR = 'rgb(0 24 90 / 0.6)'

function createCanvas(): HTMLCanvasElement {
  const canvas = document.createElement('canvas')
  canvas.width = TEXTURE_SIZE
  canvas.height = TEXTURE_SIZE

  return canvas
}

function drawSilhouette(glyphRatio: number): HTMLCanvasElement {
  const canvas = createCanvas()
  const context = canvas.getContext('2d')
  if (!context) return canvas

  const scale = (TEXTURE_SIZE * glyphRatio) / GLYPH.height
  const glyph = new Path2D()
  for (const path of GLYPH.paths) glyph.addPath(new Path2D(path))

  context.translate(TEXTURE_SIZE / 2, TEXTURE_SIZE / 2 + OFFSET_Y)
  context.scale(scale, scale)
  context.translate(-GLYPH.width / 2, -GLYPH.height / 2)
  context.clip(glyph)
  context.fillStyle = COLOR
  context.fillRect(0, 0, GLYPH.width, GLYPH.height)

  return canvas
}

function drawShadow(glyphRatio: number): HTMLCanvasElement {
  const canvas = createCanvas()
  const context = canvas.getContext('2d')
  if (!context) return canvas

  context.filter = `blur(${BLUR}px)`
  context.drawImage(drawSilhouette(glyphRatio), 0, 0)

  return canvas
}

function createGlyphShadow(
  size: number,
  glyphHeight: number,
): Mesh<PlaneGeometry, MeshBasicMaterial> {
  const texture = new CanvasTexture(drawShadow(glyphHeight / size))
  texture.colorSpace = SRGBColorSpace

  const material = new MeshBasicMaterial({ map: texture, transparent: true, depthWrite: false })

  return new Mesh(new PlaneGeometry(size, size), material)
}

export { createGlyphShadow }
