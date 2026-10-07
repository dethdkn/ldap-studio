import { CanvasTexture, SRGBColorSpace, Sprite, SpriteMaterial } from 'three'

const FONT_SIZE = 44
const PADDING = 8
const WORLD_HEIGHT = 0.2

function drawText(text: string, color: string): HTMLCanvasElement {
  const canvas = document.createElement('canvas')
  const context = canvas.getContext('2d')
  if (!context) return canvas

  const font = `500 ${FONT_SIZE}px "Martian Mono", ui-monospace, monospace`
  context.font = font
  canvas.width = Math.ceil(context.measureText(text).width) + PADDING * 2
  canvas.height = FONT_SIZE + PADDING * 2

  context.font = font
  context.fillStyle = color
  context.textBaseline = 'middle'
  context.fillText(text, PADDING, canvas.height / 2)

  return canvas
}

function createLabel(text: string, color: string): Sprite {
  const canvas = drawText(text, color)
  const texture = new CanvasTexture(canvas)
  texture.colorSpace = SRGBColorSpace
  texture.anisotropy = 4

  const material = new SpriteMaterial({ map: texture, transparent: true, depthWrite: false })
  const sprite = new Sprite(material)
  sprite.center.set(0, 0.5)
  sprite.scale.set((canvas.width / canvas.height) * WORLD_HEIGHT, WORLD_HEIGHT, 1)

  return sprite
}

function disposeLabel(sprite: Sprite): void {
  sprite.material.map?.dispose()
  sprite.material.dispose()
}

export { createLabel, disposeLabel }
