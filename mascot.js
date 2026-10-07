// The pink sparrow: its head turns toward the pointer and it reacts when tapped.
// Two 3×3 sprite sheets (nine head directions, nine expressions) — the cell is picked with
// background-position, so there is no per-frame JavaScript and no animation library.
// Built with the page-mascot skill (atlases verified: 0 px shift between sheets).

const DIRECTIONS = ['up-left', 'up', 'up-right', 'left', 'center', 'right', 'down-left', 'down', 'down-right'];
const REACTIONS = ['blink', 'heart', 'sparkle', 'surprised', 'starstruck', 'bashful', 'sleepy', 'dizzy', 'delighted'];
const CLOCKWISE = ['right', 'down-right', 'down', 'down-left', 'left', 'up-left', 'up', 'up-right'];
const SECTOR = Math.PI * 2 / CLOCKWISE.length, HYSTERESIS = 0.12, DEAD_ZONE = 60;
const PAYOFFS = ['heart', 'sparkle', 'delighted', 'starstruck', 'bashful'];
const SQUASH = [
  { transform: 'scale(1, 1)', easing: 'ease-in' },
  { transform: 'scale(1.10, 0.86)', offset: 0.18, easing: 'ease-out' },
  { transform: 'scale(0.95, 1.08)', offset: 0.45, easing: 'ease-in-out' },
  { transform: 'scale(1.03, 0.97)', offset: 0.72, easing: 'ease-in-out' },
  { transform: 'scale(1, 1)' },
];
const cell = i => `${(i % 3) * 50}% ${Math.floor(i / 3) * 50}%`;
const wrap = a => Math.atan2(Math.sin(a), Math.cos(a));

const all = new Set();
let pointer = null, listening = false;
function aimAll() { for (const m of all) m.aim(); }
function listen() {
  if (listening) return; listening = true;
  window.addEventListener('pointermove', e => { pointer = { x: e.clientX, y: e.clientY }; aimAll(); }, { passive: true });
  window.addEventListener('scroll', aimAll, { passive: true });
}

/** Turns `host` into the sparrow. Returns { react(name, ms), look(direction), el }. */
export function mountMascot(host, { directions = 'mascots/zuffi-directions.webp', reactions = 'mascots/zuffi-reactions.webp', label = 'Zuffi', onTap } = {}) {
  host.classList.add('mascot');
  host.innerHTML = `<span class="mascot-squash"><span class="mascot-layer mascot-dir"></span><span class="mascot-layer mascot-react"></span></span>`;
  host.setAttribute('role', 'button'); host.setAttribute('aria-label', `Boop ${label}`); host.tabIndex = 0;
  const squash = host.firstElementChild, dir = squash.children[0], react = squash.children[1];
  dir.style.backgroundImage = `url(${directions})`; react.style.backgroundImage = `url(${reactions})`;
  let sector = -1, timers = [], boops = { count: 0, at: 0 }, locked = null;
  const setDir = d => { dir.style.backgroundPosition = cell(DIRECTIONS.indexOf(d)); };
  const setReact = r => { react.style.opacity = r ? 1 : 0; dir.style.opacity = r ? 0 : 1; if (r) react.style.backgroundPosition = cell(REACTIONS.indexOf(r)); };
  setDir('center'); setReact(null);
  const api = {
    el: host,
    aim() {
      if (locked || !pointer || !host.isConnected) return;
      const b = host.getBoundingClientRect(); if (!b.width) return;
      const dx = pointer.x - (b.left + b.width / 2), dy = pointer.y - (b.top + b.height / 2);
      if (Math.hypot(dx, dy) < DEAD_ZONE) { sector = -1; setDir('center'); return; }
      const angle = Math.atan2(dy, dx);
      if (sector !== -1 && Math.abs(wrap(angle - sector * SECTOR)) < SECTOR / 2 + HYSTERESIS) return;
      sector = (Math.round(angle / SECTOR) + CLOCKWISE.length) % CLOCKWISE.length;
      setDir(CLOCKWISE[sector]);
    },
    look(d) { locked = d; setDir(d || 'center'); if (!d) { sector = -1; api.aim(); } },
    /** Show an expression for a moment (heart, sparkle, delighted, surprised, sleepy, dizzy, bashful, starstruck, blink). */
    react(name, ms = 900) {
      timers.forEach(clearTimeout); timers = [];
      setReact(name); timers.push(setTimeout(() => setReact(null), ms));
      if (!matchMedia('(prefers-reduced-motion: reduce)').matches) squash.animate(SQUASH, { duration: 420, easing: 'linear' });
    },
    boop() {
      timers.forEach(clearTimeout); timers = [];
      const now = Date.now();
      boops.count = now - boops.at < 1600 ? boops.count + 1 : 1; boops.at = now;
      if (boops.count >= 4) { boops.count = 0; api.react('dizzy', 1100); return; }
      setReact('blink');
      timers.push(setTimeout(() => setReact(PAYOFFS[(boops.count - 1) % PAYOFFS.length]), 120));
      timers.push(setTimeout(() => setReact(null), 640));
      if (!matchMedia('(prefers-reduced-motion: reduce)').matches) squash.animate(SQUASH, { duration: 420, easing: 'linear' });
    },
  };
  host.addEventListener('click', e => { api.boop(); onTap?.(e); });
  host.addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); api.boop(); onTap?.(e); } });
  all.add(api);
  if (matchMedia('(hover: hover) and (pointer: fine)').matches) listen();
  return api;
}
