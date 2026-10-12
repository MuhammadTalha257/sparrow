// Zuffi as an animated blob creature (blobatar, MIT — "bunny00"): breathes, bobs, blinks, glances,
// and changes mood with what's happening — happy for a sale, thinking while working, sleepy at night.
import { _parts, serializeVars } from './lib/blobatar-internal.js';
import * as E from './lib/blobatar-expression.js';

export const NAME = 'bunny00';
export const MOODS = ['idle', 'happy', 'love', 'thinking', 'surprised', 'sleepy', 'wink', 'shy', 'smug', 'unsure', 'sad', 'scared'];
let cssAdded = false;
function css() {
  if (cssAdded) return; cssAdded = true;
  const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = 'lib/blobatar-motion.css'; document.head.appendChild(l);
}
/** Animated SVG markup of Zuffi in a mood. */
export function svg(mood = 'idle', opts = {}) {
  css();
  const expression = E[mood] || E.idle;
  const p = _parts(NAME, { animate: 'always', expression, background: false, ...opts });
  const style = p.vars ? serializeVars(p.vars) : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" class="${p.cls || ''}" style="${style}" role="img" aria-label="Zuffi">${p.inner}</svg>`;
}
/** Put Zuffi into an element and let the mood follow the time of day (or a one-off reaction). */
export function mount(el, mood) {
  if (!el) return;
  const h = new Date().getHours();
  el.innerHTML = svg(mood || (h >= 23 || h < 6 ? 'sleepy' : 'idle'));
  el.classList.add('zblob');
  el.onclick = () => react(el, ['happy', 'love', 'wink', 'surprised'][Math.floor(Math.random() * 4)]);
}
let t = 0;
export function react(el, mood, ms = 1800) {
  if (!el) return;
  el.innerHTML = svg(mood);
  clearTimeout(t); t = setTimeout(() => mount(el), ms);
}
