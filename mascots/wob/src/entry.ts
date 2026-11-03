/* Zuffi's characters, drawn live with Wobnimo (MIT © 2026 Pourya Akhbari — see LICENSE-wobnimo.txt). */
import { mount, isSupported, type Mascot, type MascotState } from './packages/engine/src/index';
import { boo } from './packages/characters/src/boo';
import { bao } from './packages/characters/src/bao';
import { zuffiBunny } from './zuffibunny';

const cast: Record<string, any> = { zuffi: zuffiBunny, boo, bao };
let m: Mascot | null = null;
let current = '';

function show(id: string) {
  const spec = cast[id] || zuffiBunny;
  if (current === spec.id && m) return;
  current = spec.id;
  const el = document.getElementById('stage')!;
  if (m) { m.setSpec(spec); return; }
  m = mount(el, spec, {} as any);
}
(window as any).ZuffiMascot = {
  supported: () => isSupported(),
  show,
  state: (s: MascotState) => { m?.setState(s); },
  poke: () => { m?.poke(); },
  ready: () => !!(m && (m as any).ready),
  pause: () => m?.pause(),
  play: () => m?.play(),
};
const q = new URLSearchParams(location.search);
show(q.get('c') || 'zuffi');
if (q.get('s')) m?.setState(q.get('s') as MascotState);
