import { Color } from 'three'
import type { MeshPhysicalMaterial } from 'three'

interface RimLight {
  color: string
  power: number
  intensity: number
}

const RIM_UNIFORMS = `#include <common>
uniform vec3 rimColor;
uniform float rimPower;
uniform float rimIntensity;`

const RIM_EMISSION = `#include <emissivemap_fragment>
float facing = abs(dot(normal, normalize(vViewPosition)));
float fromAbove = 0.12 + 0.88 * clamp(normal.y * 0.5 + 0.5, 0.0, 1.0);
totalEmissiveRadiance += rimColor * rimIntensity * fromAbove * pow(1.0 - facing, rimPower);`

function withRimLight(material: MeshPhysicalMaterial, rim: RimLight): MeshPhysicalMaterial {
  material.onBeforeCompile = (shader): void => {
    shader.uniforms.rimColor = { value: new Color(rim.color) }
    shader.uniforms.rimPower = { value: rim.power }
    shader.uniforms.rimIntensity = { value: rim.intensity }
    shader.fragmentShader = shader.fragmentShader
      .replace('#include <common>', RIM_UNIFORMS)
      .replace('#include <emissivemap_fragment>', RIM_EMISSION)
  }

  return material
}

export { withRimLight }
