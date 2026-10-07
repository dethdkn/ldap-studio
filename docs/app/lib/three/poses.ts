import { MathUtils } from 'three'

interface Pose {
  iconX: number
  iconY: number
  iconScale: number
  treeX: number
  treeY: number
  treeScale: number
  treeOpacity: number
}

type PoseName = 'top' | 'tree' | 'faq' | 'download'

const POSE_KEYS: (keyof Pose)[] = [
  'iconX',
  'iconY',
  'iconScale',
  'treeX',
  'treeY',
  'treeScale',
  'treeOpacity',
]

const TREE_HIDDEN = { treeX: 0.3, treeY: 0.2, treeScale: 0.55, treeOpacity: 0 }
const ICON_HIDDEN = { iconX: 0, iconY: 0, iconScale: 0 }

const WIDE: Record<PoseName, Pose> = {
  top: { iconX: 0.25, iconY: 0, iconScale: 1, ...TREE_HIDDEN },
  tree: { ...ICON_HIDDEN, treeX: 0.27, treeY: 0.27, treeScale: 0.8, treeOpacity: 0.85 },
  faq: { ...ICON_HIDDEN, treeX: -0.3, treeY: 0.3, treeScale: 0.7, treeOpacity: 0.35 },
  download: { iconX: 0, iconY: 0.2, iconScale: 0.7, ...TREE_HIDDEN },
}

const NARROW: Record<PoseName, Pose> = {
  top: { iconX: 0, iconY: 0.25, iconScale: 0.58, ...TREE_HIDDEN },
  tree: { ...ICON_HIDDEN, treeX: 0, treeY: 0.22, treeScale: 0.55, treeOpacity: 0.35 },
  faq: { ...ICON_HIDDEN, treeX: 0, treeY: 0.3, treeScale: 0.5, treeOpacity: 0.25 },
  download: { iconX: 0, iconY: 0.27, iconScale: 0.5, ...TREE_HIDDEN },
}

const NAMED_POSES: PoseName[] = ['top', 'faq', 'download']

function poseName(branch: string | null): PoseName {
  return NAMED_POSES.find((name) => name === (branch ?? 'top')) ?? 'tree'
}

function poseFor(branch: string | null, narrow: boolean): Pose {
  return (narrow ? NARROW : WIDE)[poseName(branch)]
}

function dampPose(current: Pose, target: Pose, speed: number, delta: number): void {
  for (const key of POSE_KEYS) {
    current[key] = MathUtils.damp(current[key], target[key], speed, delta)
  }
}

export type { Pose }
export { dampPose, poseFor }
