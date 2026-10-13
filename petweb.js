// Zuffi walking along the bottom of the app — for iPhone and the web, where nothing may float over other apps.
// Same bunny as the Mac, Windows and Android pets: wanders, breathes, hops; tap = what's next.
// Zuffi's outfit (seasons.js sets window.zuffiOutfitId): the dressed-up pictures live in mascots/outfits
const pic = n => { const o = window.zuffiOutfitId; return o && o !== 'none' ? `mascots/outfits/${n}-${o}.webp` : `mascots/${n}.webp`; };
const FRN = ['zuffi-side-1', 'zuffi-side-2', 'zuffi-side-3', 'zuffi-side-2'];
let el = null, img = null, bub = null, x = 40, target = null, step = 0, stepT = 0, last = 0, raf = 0, life = 0, getNext = () => '';
const W = 46;
let blobSvg = null;
export function start(next, opts = {}) {
  getNext = next || getNext; blobSvg = opts.blob || null;
  let on = '1'; try { on = localStorage.getItem('zuffiWebPet') ?? '1'; } catch {}
  if (on !== '1' || el) return;
  el = document.createElement('div'); el.className = 'webpet idle';
  el.innerHTML = (blobSvg ? `<span class="wpblob">${blobSvg()}</span>` : `<img alt="Zuffi" src="${pic('zuffi-body')}">`) + '<div class="webpet-b" hidden></div>';
  if (blobSvg) el.classList.add('is-blob');
  document.body.appendChild(el);
  img = el.querySelector('img') || { set src(v) {} }; bub = el.querySelector('.webpet-b');
  FRN.forEach(n => { const i = new Image(); i.src = pic(n); });
  try { x = +localStorage.getItem('webPetX') || innerWidth - W - 30; } catch { x = innerWidth - W - 30; }
  place();
  el.onclick = e => { e.stopPropagation(); hop(); say(getNext() || ['Hi! I’m here 💗', 'Drink some water 💧', 'You’re doing great ✨'][Math.floor(Math.random() * 3)]); };
  raf = requestAnimationFrame(tick);
  life = setInterval(() => { if (document.hidden || target !== null || !bub.hidden) return; if (Math.random() < 0.6) walkTo(10 + Math.random() * (innerWidth - W - 20)); else hop(); }, 9000);
}
export function stop() { if (!el) return; cancelAnimationFrame(raf); clearInterval(life); el.remove(); el = null; }
window.zuffiWebPet = on => on ? start() : stop();
document.addEventListener('zuffi-look', () => { if (el && blobSvg) { const w = el.querySelector('.wpblob'); if (w) w.innerHTML = blobSvg(); } if (el && !blobSvg && target === null) img.src = pic('zuffi-body'); FRN.forEach(n => { const i = new Image(); i.src = pic(n); }); });
function place() { el.style.transform = `translateX(${x}px)`; }
function walkTo(nx) { target = Math.max(6, Math.min(innerWidth - W - 6, nx)); el.classList.remove('idle'); el.classList.toggle('left', target < x); }
function tick(t) {
  const dt = Math.min(0.05, (t - last) / 1000 || 0); last = t;
  if (target !== null) {
    const d = target - x, v = 56 * dt;
    if (Math.abs(d) <= v) { x = target; target = null; el.classList.add('idle'); el.classList.remove('left'); if (!blobSvg) img.src = pic('zuffi-body'); try { localStorage.setItem('webPetX', String(Math.round(x))); } catch {} }
    else { x += Math.sign(d) * v; if (!blobSvg && t - stepT > 140) { stepT = t; step = (step + 1) % 4; img.src = pic(FRN[step]); } }
    place();
  }
  raf = requestAnimationFrame(tick);
}
function hop() { el.classList.remove('hop'); void el.offsetWidth; el.classList.add('hop'); }
let bubT = 0;
export function say(text, ms = 5000) {
  if (!el || !text) return;
  bub.textContent = text; bub.hidden = false; hop();
  const left = Math.max(8 - x, Math.min(innerWidth - x - 228, -100));
  bub.style.left = left + 'px';
  clearTimeout(bubT); bubT = setTimeout(() => { bub.hidden = true; }, ms);
}
