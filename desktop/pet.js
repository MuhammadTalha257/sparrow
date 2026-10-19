// Zuffi walking along the bottom of the Windows desktop — same bunny and same idea as on the Mac.
// Wanders, breathes, hops; walks to the middle with your reminders (Done / Snooze); tap = what's next;
// double-click = open Zuffi; drag = move her. Only she and her card catch the mouse.
const D = window.SparrowDesktop;
const pet = document.getElementById('pet'), img = document.getElementById('img'), card = document.getElementById('card');
const W = 92;
// Zuffi's outfit (winter, Eid…) — set by the island window through the main process
let outfit = 'none';
const pic = n => outfit && outfit !== 'none' ? `mascots/outfits/${n}-${outfit}.webp` : `mascots/${n}.webp`;
const FRN = ['zuffi-side-1', 'zuffi-side-2', 'zuffi-side-3', 'zuffi-side-2'];
const preload = () => FRN.concat('zuffi-body').forEach(n => { const i = new Image(); i.src = pic(n); });
preload();
D.getSettings?.().then(st => { if (st?.outfit && st.outfit !== outfit) { outfit = st.outfit; preload(); if (target === null) img.src = pic('zuffi-body'); } }).catch(() => {});
let x = Number(localStorage.getItem('petX')) || innerWidth - W - 80, target = null, then = null, last = 0, step = 0, stepT = 0, busy = false, hiddenUntil = 0;
const place = () => { pet.style.transform = `translateX(${x}px)`; placeCard(); };
place();

function walkTo(nx, cb) {
  target = Math.max(4, Math.min(innerWidth - W - 4, nx)); then = cb || null;
  pet.classList.remove('idle'); pet.classList.toggle('left', target < x);
}
function stand() { target = null; pet.classList.add('idle'); pet.classList.remove('left'); img.src = pic('zuffi-body'); try { localStorage.setItem('petX', String(Math.round(x))); } catch {} }
function tick(t) {
  const dt = Math.min(0.05, (t - last) / 1000 || 0); last = t;
  if (target !== null) {
    const d = target - x, v = 74 * dt;
    if (Math.abs(d) <= v) { x = target; place(); stand(); const f = then; then = null; f && f(); }
    else { x += Math.sign(d) * v; place(); if (t - stepT > 130) { stepT = t; step = (step + 1) % 4; img.src = pic(FRN[step]); } }
  }
  requestAnimationFrame(tick);
}
requestAnimationFrame(tick);
function hop() { pet.classList.remove('hop'); void pet.offsetWidth; pet.classList.add('hop'); }

// Life: wander now and then
setInterval(() => {
  if (Date.now() < hiddenUntil) { pet.classList.add('hidden'); return; }
  pet.classList.remove('hidden');
  if (busy || target !== null || card.classList.contains('on')) return;
  const r = Math.random();
  if (r < 0.55) walkTo(Math.random() * (innerWidth - W));
  else if (r < 0.65) hop();
}, 9000);

// ---------- speech card ----------
let cardT = null;
function placeCard() {
  const cw = card.offsetWidth || 220;
  const left = Math.max(8, Math.min(innerWidth - cw - 8, x + W / 2 - cw / 2));
  card.style.left = left + 'px'; card.style.setProperty('--tail', Math.max(14, Math.min(cw - 28, x + W / 2 - left - 7)) + 'px');
}
function say(text, head = '', buttons = [], ms = 6000, reply = false) {
  card.classList.toggle('reply', reply);
  document.getElementById('cH').textContent = head; document.getElementById('cH').style.display = head ? '' : 'none';
  document.getElementById('cT').textContent = text;
  const b = document.getElementById('cB'); b.innerHTML = ''; b.style.display = buttons.length ? '' : 'none';
  for (const [label, solid, fn] of buttons) { const e = document.createElement('button'); e.textContent = label; if (solid) e.className = 'solid'; e.onclick = ev => { ev.stopPropagation(); e.classList.add('pressed'); setTimeout(() => { hideCard(); fn(); }, 160); }; b.appendChild(e); }
  card.classList.add('on'); placeCard();
  clearTimeout(cardT); if (ms) cardT = setTimeout(hideCard, ms);
}
function hideCard() { card.classList.remove('on'); busy = false; clearTimeout(cardT); }
// The happy dance + hearts and sparkles floating up
function dance() {
  pet.classList.remove('dance'); void pet.offsetWidth; pet.classList.add('dance'); setTimeout(() => pet.classList.remove('dance'), 2300);
  ['💗', '✨', '🌸', '💖', '⭐️', '🎉', '💕', '✨'].forEach((m, i) => setTimeout(() => {
    const e = document.createElement('div'); e.className = 'joy'; e.textContent = m;
    e.style.left = (x + W / 2 - 9 + (i % 2 ? 1 : -1) * (10 + (i * 13) % 34)) + 'px'; e.style.bottom = (110 + (i % 3) * 14) + 'px';
    e.style.setProperty('--dx', ((i % 2 ? 1 : -1) * (20 + (i * 7) % 30)) + 'px'); document.body.appendChild(e); setTimeout(() => e.remove(), 1500);
  }, i * 140));
}

D.onPet(v => {
  hiddenUntil = 0; pet.classList.remove('hidden');
  if (v.kind === 'remind') {
    busy = true;
    walkTo(innerWidth / 2 - W / 2, () => {
      hop();
      const emoji = /meeting/i.test(v.head || '') ? '📅' : /prayer/i.test(v.head || '') ? '🌙' : '⏰';
      const happy = () => { busy = true; dance(); say(/meeting/i.test(v.head || '') ? 'Good luck! 🍀' : 'Yay, done! 🎉 Nice work 💗', '', [], 2600, true); };
      const btns = v.id ? [['Done', true, () => { D.petAction({ action: 'done', id: v.id }); happy(); }], ['Later', false, () => { D.petAction({ action: 'snooze', id: v.id }); say('I’ll come back in 10 minutes ⏰', '', [], 2600, true); }]]
                        : [['Thanks', true, happy]];
      say(`${v.title || 'Reminder'} ${emoji}`, '', btns, 120000);
    });
  } else if (v.kind === 'say') { hop(); say(v.text || '', v.head || '', [], v.ms || 6000); }
  else if (v.kind === 'outfit') { outfit = v.v || 'none'; preload(); if (target === null) img.src = pic('zuffi-body'); }
  else if (v.kind === 'accent') { const deg = { violet: 55, sky: 115, mint: 170, amber: 230, coral: 330 }[v.v] || 0; img.style.filter = `drop-shadow(0 6px 10px rgba(0,0,0,.28)) hue-rotate(${deg}deg)`; }
  else if (v.kind === 'charge') { hop(); say(v.charging ? 'Yum, charging ⚡' : 'Unplugged — I’ll save energy 🌙', '', [], 3500); }
});

// ---------- mouse: tap, double-click, drag ----------
let inside = false, down = null, moved = false, clickT = null;
const over = (e, el) => { const r = el.getBoundingClientRect(); return e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom; };
document.addEventListener('mousemove', e => {
  const now = over(e, pet) || (card.classList.contains('on') && over(e, card)) || !!down;
  if (now !== inside) { inside = now; D.petMouse(now); }
  if (down) { const dx = e.clientX - down.cx; if (Math.abs(dx) > 6) moved = true; if (moved) { target = null; x = Math.max(0, Math.min(innerWidth - W, down.x + dx)); place(); } }
});
document.addEventListener('mouseleave', () => { if (!down && inside) { inside = false; D.petMouse(false); } });
pet.addEventListener('mousedown', e => { down = { cx: e.clientX, x }; moved = false; pet.style.cursor = 'grabbing'; });
document.addEventListener('mouseup', async () => {
  if (!down) return;
  const wasMove = moved; down = null; pet.style.cursor = 'grab';
  if (wasMove) { stand(); return; }
  if (clickT) { clearTimeout(clickT); clickT = null; D.petAction({ action: 'open' }); return; }   // double-click → open Zuffi
  clickT = setTimeout(async () => {
    clickT = null; hop();
    let next = ''; try { next = await D.petNext(); } catch {}
    say(next || ['Hi! I’m here 💗', 'Double-click me to open Zuffi.', 'Drink some water 💧', 'You’re doing great ✨'][Math.floor(Math.random() * 4)], '',
      [['Open Zuffi', true, () => D.petAction({ action: 'open' })], ['Hide 1 hour', false, () => { hiddenUntil = Date.now() + 3600000; pet.classList.add('hidden'); }]], 7000);
  }, 260);
});
addEventListener('resize', () => { x = Math.min(x, innerWidth - W - 4); place(); });
