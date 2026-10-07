import { CanvasTexture, Mesh, MeshBasicMaterial, PlaneGeometry, SRGBColorSpace } from 'three'
import type { Vector2 } from 'three'

const PIXELS_PER_UNIT = 28
const BASE_TEXTURE_SIZE = 1024

interface Bounds {
  top: number
  bottom: number
}

function edgeGradient(
  context: CanvasRenderingContext2D,
  top: number,
  bottom: number,
  strength: number,
): CanvasGradient {
  const gradient = context.createLinearGradient(0, top, 0, bottom)
  gradient.addColorStop(0, `rgb(255 255 255 / ${strength})`)
  gradient.addColorStop(0.45, `rgb(255 255 255 / ${strength * 0.25})`)
  gradient.addColorStop(1, `rgb(255 255 255 / ${strength * 0.45})`)

  return gradient
}

function strokeInside(
  context: CanvasRenderingContext2D,
  shape: Path2D,
  width: number,
  blur: number,
): void {
  context.save()
  context.clip(shape)
  context.lineWidth = width
  context.filter = blur > 0 ? `blur(${blur}px)` : 'none'
  context.stroke(shape)
  context.restore()
}

function fillSheen(context: CanvasRenderingContext2D, shape: Path2D, bounds: Bounds): void {
  const gradient = context.createLinearGradient(0, bounds.top, 0, bounds.bottom)
  gradient.addColorStop(0, 'rgb(255 255 255 / 0.32)')
  gradient.addColorStop(0.55, 'rgb(255 255 255 / 0)')

  context.save()
  context.clip(shape)
  context.fillStyle = gradient
  context.fillRect(0, bounds.top, context.canvas.width, bounds.bottom - bounds.top)
  context.restore()
}

function createOverlay(
  canvas: HTMLCanvasElement,
  width: number,
  height: number,
  flip: boolean,
): Mesh<PlaneGeometry, MeshBasicMaterial> {
  const texture = new CanvasTexture(canvas)
  texture.colorSpace = SRGBColorSpace
  texture.flipY = !flip

  const material = new MeshBasicMaterial({ map: texture, transparent: true, depthWrite: false })

  return new Mesh(new PlaneGeometry(width, height), material)
}

function createGlyphHighlight(
  path: string,
  width: number,
  height: number,
  bounds: Bounds,
): Mesh<PlaneGeometry, MeshBasicMaterial> {
  const canvas = document.createElement('canvas')
  canvas.width = Math.ceil(width * PIXELS_PER_UNIT)
  canvas.height = Math.ceil(height * PIXELS_PER_UNIT)

  const context = canvas.getContext('2d')
  if (context) {
    const shape = new Path2D(path)
    context.scale(PIXELS_PER_UNIT, PIXELS_PER_UNIT)
    fillSheen(context, shape, bounds)
    context.strokeStyle = edgeGradient(context, bounds.top, bounds.bottom, 0.95)
    strokeInside(context, shape, 0.32, 0)
    context.strokeStyle = edgeGradient(context, bounds.top, bounds.bottom, 0.35)
    strokeInside(context, shape, 1.4, 6)
  }

  return createOverlay(canvas, width, height, true)
}

function createBaseHighlight(
  points: Vector2[],
  size: number,
): Mesh<PlaneGeometry, MeshBasicMaterial> {
  const canvas = document.createElement('canvas')
  canvas.width = BASE_TEXTURE_SIZE
  canvas.height = BASE_TEXTURE_SIZE

  const context = canvas.getContext('2d')
  if (context) {
    const scale = BASE_TEXTURE_SIZE / size
    const shape = new Path2D()
    for (const point of points) {
      shape.lineTo((point.x + size / 2) * scale, (size / 2 - point.y) * scale)
    }
    shape.closePath()

    context.strokeStyle = edgeGradient(context, 0, BASE_TEXTURE_SIZE, 0.75)
    strokeInside(context, shape, 7, 0)
    context.strokeStyle = edgeGradient(context, 0, BASE_TEXTURE_SIZE, 0.25)
    strokeInside(context, shape, 40, 14)
  }

  return createOverlay(canvas, size, size, false)
}

export { createBaseHighlight, createGlyphHighlight }
