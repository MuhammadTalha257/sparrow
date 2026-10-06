// Sparrow's own bird (the original drawn character), now pink & white.
// Its eyes and head follow the pointer; a tap gives a little reaction (four quick taps = dizzy).
let n = 0;

const svg = id => `
<svg class="bird-svg" viewBox="0 0 200 170" aria-hidden="true">
  <defs>
    <linearGradient id="gBody${id}" x1="0.8" y1="0" x2="0.2" y2="1"><stop offset="0" class="b1"/><stop offset="1" class="b2"/></linearGradient>
    <clipPath id="bodyClip${id}"><ellipse cx="100" cy="92" rx="66" ry="56"/></clipPath>
  </defs>
  <g class="feet"><path d="M88 146 v10 m-5 0 h10 M112 146 v10 m-5 0 h10" class="feet-s" stroke-width="3.5" stroke-linecap="round" fill="none"/></g>
  <g class="tail"><path d="M150 104 Q176 82 190 62 Q196 74 194 86 Q182 104 162 122 Z" class="cap-f"/></g>
  <g class="body-g">
    <g class="look">
      <ellipse cx="100" cy="92" rx="66" ry="56" fill="url(#gBody${id})"/>
      <g clip-path="url(#bodyClip${id})">
        <ellipse cx="100" cy="128" rx="44" ry="40" class="belly-f"/>
        <ellipse cx="100" cy="40" rx="64" ry="34" class="cap-f"/>
      </g>
      <g class="eyes">
        <g transform="translate(80 90)"><g class="eye"><rect x="-7.5" y="-10" width="15" height="20" rx="7.5" fill="#1A1412"/><circle cx="2.5" cy="-4.5" r="3.2" fill="#fff"/></g></g>
        <g transform="translate(120 90)"><g class="eye"><rect x="-7.5" y="-10" width="15" height="20" rx="7.5" fill="#1A1412"/><circle cx="2.5" cy="-4.5" r="3.2" fill="#fff"/></g></g>
      </g>
      <g class="brows"><path d="M70 74 L90 80 M130 74 L110 80" stroke="#1A1412" stroke-width="4" stroke-linecap="round"/></g>
      <path class="beak beak-f" d="M91 104 Q100 98 109 104 L100 118 Z"/>
      <ellipse class="blush" cx="62" cy="108" rx="10" ry="6" fill="#FF6F9A" opacity=".35"/><ellipse class="blush" cx="138" cy="108" rx="10" ry="6" fill="#FF6F9A" opacity=".35"/>
    </g>
  </g>
  <g class="wing"><path d="M40 98 Q62 92 76 108 Q70 128 46 132 Q30 124 40 98 Z" class="wing-f"/></g>
</svg>`;

const POP = { heart: '💗', sparkle: '✨', delighted: '💕', starstruck: '⭐', surprised: '❗', dizzy: '💫', angry: '💢', bashful: '☺️', sleepy: '💤' };

export function mountBird(host, { onTap } = {}) {
  const id = ++n;
  host.classList.add('bird');
  host.innerHTML = svg(id);
  const look = host.querySelector('.look'), eyes = host.querySelector('.eyes');
  let timer = 0, boops = 0, lastBoop = 0;

  function react(name, ms = 900) {
    clearTimeout(timer);
    host.classList.remove('r-hop', 'r-surprised', 'r-dizzy', 'r-angry', 'r-sleepy');
    void host.offsetWidth;
    const cls = { surprised: 'r-surprised', dizzy: 'r-dizzy', angry: 'r-angry', sleepy: 'r-sleepy' }[name] || 'r-hop';
    host.classList.add(cls);
    if (POP[name]) {
      const p = document.createElement('span');
      p.className = 'bird-pop'; p.textContent = POP[name];
      host.appendChild(p); setTimeout(() => p.remove(), 1100);
    }
    timer = setTimeout(() => host.classList.remove(cls), ms);
  }
  function boop() {
    const now = Date.now();
    boops = now - lastBoop < 1600 ? boops + 1 : 1; lastBoop = now;
    if (boops >= 4) { boops = 0; react('dizzy', 1200); return; }
    react(['heart', 'sparkle', 'delighted', 'starstruck', 'bashful'][(boops - 1) % 5], 800);
  }
  function aim(x, y) {
    const r = host.getBoundingClientRect();
    if (!r.width) return;
    const dx = x - (r.left + r.width / 2), dy = y - (r.top + r.height / 2);
    const d = Math.hypot(dx, dy) || 1, k = Math.min(1, d / 240);
    eyes.style.transform = `translate(${(dx / d) * 7 * k}px, ${(dy / d) * 5 * k}px)`;
    look.style.transform = `rotate(${(dx / d) * 6 * k}deg)`;
  }
  if (matchMedia('(pointer: fine)').matches) addEventListener('pointermove', e => aim(e.clientX, e.clientY), { passive: true });
  host.addEventListener('click', () => { boop(); onTap?.(); });
  return { el: host, react, boop, aim };
}
