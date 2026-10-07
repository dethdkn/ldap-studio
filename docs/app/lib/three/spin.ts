const TURN = Math.PI * 2
const PROJECTION = 0.5
const STIFFNESS = 30
const DAMPING = 8.5

const spin = { dragging: false, angle: 0, velocity: 0, target: 0 }

function grabSpin(): void {
  spin.dragging = true
  spin.velocity = 0
}

function dragSpin(deltaAngle: number, deltaTime: number): void {
  spin.angle += deltaAngle
  if (deltaTime > 0) spin.velocity = spin.velocity * 0.6 + (deltaAngle / deltaTime) * 0.4
}

function releaseSpin(): void {
  const projected = spin.angle + spin.velocity * PROJECTION
  spin.target = Math.round(projected / TURN) * TURN
  spin.dragging = false
}

function nudgeSpin(direction: 1 | -1): void {
  spin.velocity += direction * 9
  releaseSpin()
}

function stepSpin(deltaTime: number): void {
  if (spin.dragging) return

  const acceleration = -STIFFNESS * (spin.angle - spin.target) - DAMPING * spin.velocity
  spin.velocity += acceleration * deltaTime
  spin.angle += spin.velocity * deltaTime
}

export { dragSpin, grabSpin, nudgeSpin, releaseSpin, spin, stepSpin }
