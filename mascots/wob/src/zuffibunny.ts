import type { CharacterSpec } from '@wobnimo/engine';

/** Zuffi's own bunny: a soft blush-pink rabbit with tall perky ears, little paws and sparkly eyes.
    Built on Wobnimo (MIT, Pourya Akhbari), shaped after its "Hop" bunny. */
export const zuffiBunny: CharacterSpec = {
  id: 'zuffi',
  name: 'Zuffi',
  tagline: 'A soft blush-pink bunny with tall ears, little paws and sparkly eyes',
  accent: '#ff8fb1',
  frame: { target: 0.6, radius: 0.8 },
  bound: { y: 0.6, radius: 0.7 },
  motion: { hop: 0.2, squash: 1.25, snap: 1.1, talkSquash: 0.45 },
  glowPool: 0.25,
  materials: {
    fur: { color: '#fff4f6', f0: 0.03, spec: 0.45, shininess: 22, rim: 1.1, sheen: 0.85, sss: 0.25, sssColor: '#ffc9d6', surface: { kind: 'fur', scale: 120, strength: 0.32, bone: 'head' } },
    bodyFur: { color: '#fff4f6', shadeOf: 'fur', f0: 0.03, spec: 0.45, shininess: 22, rim: 1.1, sheen: 0.85, sss: 0.25, sssColor: '#ffc9d6', surface: { kind: 'fur', scale: 120, strength: 0.32 } },
    belly: { color: '#ffffff', shadeOf: 'fur', f0: 0.03, spec: 0.35, shininess: 18, rim: 0.9, sheen: 0.9, surface: { kind: 'fur', scale: 140, strength: 0.25 } },
    earFur: { color: '#fff1f4', shadeOf: 'fur', f0: 0.03, spec: 0.4, shininess: 20, rim: 1.3, sheen: 0.7, sss: 0.55, sssColor: '#ffb3c6' },
    nose: { color: '#ff7fa5', f0: 0.06, spec: 1.8, shininess: 180, rim: 0.3, gloss: 0.9 },
  },
  bones: [
    { name: 'body', pivot: [0, 0, 0], drive: { ry: [['yaw', 0.2]], rz: [['roll', 0.35]] } },
    { name: 'head', parent: 'body', pivot: [0, 0.44, 0.02], drive: { rx: [['pitch', -1]], ry: [['yaw', 0.8]], rz: [['roll', 0.7]] } },
    /* tall ears, a little apart, that perk up and swing */
    { name: 'earL', parent: 'head', pivot: [-0.09, 0.32, -0.02], rest: { rz: 0.16, rx: -0.05 }, jiggle: { axis: [0, 1, 0], length: 0.34, freq: 2.2, damping: 0.15, maxAngle: 0.7 } },
    { name: 'earR', parent: 'head', pivot: [0.09, 0.32, -0.02], rest: { rz: -0.22, rx: -0.05 }, jiggle: { axis: [0, 1, 0], length: 0.34, freq: 2.2, damping: 0.15, maxAngle: 0.7 } },
    { name: 'armL', parent: 'body', pivot: [-0.15, 0.32, 0.12], drive: { rz: [['flap', -0.9]] }, jiggle: { axis: [-0.3, -1, 0.2], length: 0.1, freq: 2.4, damping: 0.25, maxAngle: 0.5 } },
    { name: 'armR', parent: 'body', pivot: [0.15, 0.32, 0.12], drive: { rz: [['flap', 0.9]] }, jiggle: { axis: [0.3, -1, 0.2], length: 0.1, freq: 2.4, damping: 0.25, maxAngle: 0.5 } },
    { name: 'tail', parent: 'body', pivot: [0, 0.14, -0.2], jiggle: { axis: [0, 0, -1], length: 0.06, freq: 4, damping: 0.2 } },
  ],
  parts: [
    { bone: 'body', shape: 'ellipsoid', at: [0, 0.22, 0], radii: [0.21, 0.23, 0.2], material: 'bodyFur' },
    { bone: 'body', shape: 'ellipsoid', at: [0, 0.2, 0.09], radii: [0.14, 0.15, 0.11], blend: 0.05, material: 'belly' },
    { bone: 'body', shape: 'ellipsoid', at: [-0.11, 0.04, 0.1], radii: [0.075, 0.045, 0.12], blend: 0.04, material: 'bodyFur' },
    { bone: 'body', shape: 'ellipsoid', at: [0.11, 0.04, 0.1], radii: [0.075, 0.045, 0.12], blend: 0.04, material: 'bodyFur' },
    { bone: 'armL', shape: 'capsule', from: [0, 0, 0], to: [-0.02, -0.11, 0.05], radius: 0.045, blend: 0.05, material: 'bodyFur' },
    { bone: 'armR', shape: 'capsule', from: [0, 0, 0], to: [0.02, -0.11, 0.05], radius: 0.045, blend: 0.05, material: 'bodyFur' },
    { bone: 'tail', shape: 'sphere', at: [0, 0, -0.03], radius: 0.07, blend: 0.03, material: 'bodyFur' },
    { bone: 'head', shape: 'ellipsoid', at: [0, 0.14, 0], radii: [0.26, 0.225, 0.22], blend: 0.1, material: 'fur' },
    { bone: 'head', shape: 'ellipsoid', at: [-0.06, 0.055, 0.17], radii: [0.07, 0.055, 0.06], blend: 0.04, material: 'fur' },
    { bone: 'head', shape: 'ellipsoid', at: [0.06, 0.055, 0.17], radii: [0.07, 0.055, 0.06], blend: 0.04, material: 'fur' },
    { bone: 'head', shape: 'ellipsoid', at: [0, 0.095, 0.222], radii: [0.03, 0.021, 0.018], material: 'nose' },
    { bone: 'earL', shape: 'ellipsoid', at: [0, 0.21, 0], radii: [0.068, 0.23, 0.032], material: 'earFur' },
    { bone: 'earR', shape: 'ellipsoid', at: [0, 0.21, 0], radii: [0.068, 0.23, 0.032], material: 'earFur' },
  ],
  paints: [
    { bone: 'earL', on: ['earFur'], kind: 'ellipse', at: [0, 0.21, 0.032], radii: [0.038, 0.17], color: '#ffb6ca', soft: 0.45 },
    { bone: 'earR', on: ['earFur'], kind: 'ellipse', at: [0, 0.21, 0.032], radii: [0.038, 0.17], color: '#ffb6ca', soft: 0.45 },
    { bone: 'head', on: ['fur'], kind: 'sphere', at: [-0.165, 0.07, 0.16], radius: 0.05, color: '#ff9fbc', soft: 0.6, opacity: 0.85 },
    { bone: 'head', on: ['fur'], kind: 'sphere', at: [0.165, 0.07, 0.16], radius: 0.05, color: '#ff9fbc', soft: 0.6, opacity: 0.85 },
  ],
  eyes: { kind: 'ball', bone: 'head', at: [[-0.1, 0.175, 0.17], [0.1, 0.175, 0.17]], radius: 0.054, iris: '#3a1d2c', irisSize: 0.88, pupilSize: 0.55, lid: 'fur' },
  face: { kind: 'mouth', bone: 'head', on: ['fur'], at: [0, 0.03, 0.212], width: 0.038, color: '#5a2a3a', tongue: '#ff8fa3' },
  anchors: {
    top: { bone: 'head', at: [0.15, 0.52, 0.05] },
    mouth: { bone: 'head', at: [0, 0.03, 0.24] },
    ear: { bone: 'earL', at: [0, 0.21, 0] },
    center: { bone: 'body', at: [0, 0.35, 0] },
    feet: { bone: 'root', at: [0, 0.02, 0.15] },
  },
  acting: {
    idle: { armL: { rz: [0, 0.06, 0.8, 0] }, armR: { rz: [0, 0.06, 0.8, 1.4] } },
    thinking: { earR: { rz: -0.5 }, head: { rz: 0.1 }, armR: { rx: -1.5, rz: 0.4 } },
    /* a paw cupped by its ear */
    listening: { earL: { rz: 0.05, rx: -0.25 }, earR: { rz: -0.05, rx: -0.25 }, armR: { rx: -2.2, rz: 0.9 } },
    speaking: { armL: { rx: [-0.4, 0.25, 1.3, 0] }, armR: { rx: [-0.4, 0.25, 1.3, 1.9] } },
    sleeping: { earL: { rz: 1.2, rx: 0.5 }, earR: { rz: -1.4, rx: 0.5 } },
    working: { armL: { rx: [-0.7, 0.15, 6, 0] }, armR: { rx: [-0.7, 0.15, 6, Math.PI] } },
    error: { earL: { rz: [0.6, 0.2, 9, 0] }, earR: { rz: [-0.6, 0.2, 9, 1] }, armL: { rx: -0.9, rz: 0.6 }, armR: { rx: -0.9, rz: -0.6 } },
    surprised: { earL: { rz: 0.02, rx: -0.15 }, earR: { rz: -0.02, rx: -0.15 }, armL: { rx: -1.4 }, armR: { rx: -1.4 } },
    celebrating: { earL: { rz: [0.2, 0.3, 4, 0] }, earR: { rz: [-0.2, 0.3, 4, Math.PI] }, armL: { rz: [-1.8, 0.3, 4, 0] }, armR: { rz: [1.8, 0.3, 4, Math.PI] } },
    sad: { earL: { rz: 1.4, rx: 0.6 }, earR: { rz: -1.4, rx: 0.6 }, armL: { rz: 0.2 }, armR: { rz: -0.2 } },
  },
  fx: {
    happy: [{ glyph: 'heart', anchor: 'top', rate: 1.2, velocity: [0, 0.22, 0.04], jitter: 0.1, life: [1, 1.3], size: [0.04, 0.06], color: '#ff8fb1' }],
  },
};
