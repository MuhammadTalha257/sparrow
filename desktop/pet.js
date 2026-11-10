// Zuffi's pet on the Windows desktop — Aurora in 3D, the same bunny and the same moves as on the Mac.
// She hops along the bottom of the screen, sits and does little rabbit things, brings your reminders on her back legs,
// does a happy binky when you say Done and gets cross (stamps, cheeks puff) when you say Not yet.
// Tap = what's next · double-click = open Zuffi · drag = move her. Only she and her bubble catch the mouse.
import { Aurora3D } from './aurora3d.js';

const D = window.SparrowDesktop;
const pet = document.getElementById('pet'), card = document.getElementById('card');
const W = 170;
const aurora = new Aurora3D(document.getElementById('aurora'), { framing: 'full' });
let x = Number(localStorage.getItem('petX')) || innerWidth - W - 80, target = null, then = null, last = 0, busy = false, hiddenUntil = 0, moodT = null;
const place = () => { pet.style.transform = `translateX(${x}px)`; placeCard(); reportRects(); };

/** Tell the main process exactly where she (and her bubble) are, so only those spots catch the mouse. */
function reportRects() {
  const rs = [pet, card.classList.contains('on') ? card : null].filter(Boolean).map(e => { const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; });
  D.hitRects?.(pet.classList.contains('hidden') ? [] : rs);
}
function mood(m, ms = 0, pose = null) {
  aurora.setMood(m); if (pose) aurora.setPose(pose);
  clearTimeout(moodT); if (ms) moodT = setTimeout(() => { aurora.setMood('smile'); if (target === null) aurora.setPose('sit'); }, ms);
}

function walkTo(nx, cb) {
  target = Math.max(4, Math.min(innerWidth - W - 4, nx)); then = cb || null;
  aurora.setFaceLeft(target < x); aurora.setPose('hop');
}
function stand() { target = null; aurora.setPose('sit'); try { localStorage.setItem('petX', String(Math.round(x))); } catch {} }
function tick(t) {
  const dt = Math.min(0.05, (t - last) / 1000 || 0); last = t;
  if (target !== null) {
    const d = target - x, v = 90 * dt;
    if (Math.abs(d) <= v) { x = target; place(); stand(); const f = then; then = null; f && f(); }
    else { x += Math.sign(d) * v; place(); }
  }
  requestAnimationFrame(tick);
}
place(); requestAnimationFrame(tick);

// she looks at your mouse (the main process sends where it is)
D.onCursor?.(p => { const r = pet.getBoundingClientRect(); aurora.look(p.x - (r.left + r.width / 2), p.y - (r.top + r.height * 0.3)); });

// Life: wander now and then
setInterval(() => {
  const hide = Date.now() < hiddenUntil; pet.classList.toggle('hidden', hide); if (hide) { reportRects(); return; }
  if (busy || target !== null || card.classList.contains('on')) return;
  if (Math.random() < 0.55) walkTo(Math.random() * (innerWidth - W));
}, 9000);

// ---------- speech bubble ----------
let cardT = null;
function placeCard() {
  const cw = card.offsetWidth || 220;
  const left = Math.max(8, Math.min(innerWidth - cw - 8, x + W / 2 - cw / 2));
  card.style.left = left + 'px'; card.style.setProperty('--tail', Math.max(14, Math.min(cw - 28, x + W / 2 - left - 7)) + 'px');
}
function say(text, buttons = [], ms = 6000, tone = '') {
  card.className = tone;
  document.getElementById('cT').textContent = text;
  const b = document.getElementById('cB'); b.innerHTML = ''; b.style.display = buttons.length ? '' : 'none';
  for (const [label, solid, fn] of buttons) {
    const e = document.createElement('button'); e.textContent = label; if (solid) e.className = 'solid';
    e.onclick = ev => { ev.stopPropagation(); e.classList.add('pressed'); setTimeout(() => { hideCard(); fn(); }, 160); }; b.appendChild(e);
  }
  card.classList.add('on'); placeCard(); reportRects();
  aurora.talk(true, text); setTimeout(() => aurora.talk(false), Math.min(6000, 600 + text.length * 70));
  clearTimeout(cardT); if (ms) cardT = setTimeout(hideCard, ms);
}
function hideCard() { card.classList.remove('on'); busy = false; clearTimeout(cardT); setTimeout(reportRects, 320); }
const happy = text => { busy = true; mood('happy', 3200, 'happy'); say(text, [], 2800, 'good'); };
const cross = text => { busy = true; mood('cross', 2600, 'cross'); say(text, [], 2600, 'bad'); };
window.zuffiPetDance = t => happy(t || 'Yay, done! 🎉');

D.onPet(v => {
  hiddenUntil = 0; pet.classList.remove('hidden');
  if (v.kind === 'remind') {
    busy = true;
    walkTo(innerWidth / 2 - W / 2, () => {
      aurora.setPose('hold'); mood('surprised', 900);
      const btns = v.id ? [['Done', true, () => { D.petAction({ action: 'done', id: v.id }); happy(/meeting/i.test(v.head || '') ? 'Good luck! 🍀' : 'Yay, done! 🎉 Nice work'); }],
                           ['Not yet', false, () => { D.petAction({ action: 'snooze', id: v.id }); cross('Hmph! I’ll be back in 10 minutes ⏰'); }]]
                        : [['OK', true, () => happy('Yay! 💗')]];
      say(`${v.title || 'Reminder'} ⏰`, btns, 120000);
    });
  } else if (v.kind === 'say') { mood('happy', 1500); say(v.text || '', [], v.ms || 6000); }
  else if (v.kind === 'charge') { mood(v.charging ? 'happy' : 'sleepy', 3000); say(v.charging ? 'Yum, charging ⚡' : 'Unplugged — I’ll save energy 🌙', [], 3500); }
});

// ---------- mouse: tap, double-click, drag ----------
let down = null, moved = false, clickT = null;
pet.addEventListener('mousedown', e => { down = { cx: e.clientX, x }; moved = false; pet.style.cursor = 'grabbing'; });
document.addEventListener('mousemove', e => {
  if (!down) return;
  const dx = e.clientX - down.cx; if (Math.abs(dx) > 6) moved = true;
  if (moved) { target = null; aurora.setPose('sit'); x = Math.max(0, Math.min(innerWidth - W, down.x + dx)); place(); }
});
document.addEventListener('mouseup', e => {
  if (!down) return;
  const wasMove = moved; down = null; pet.style.cursor = 'grab';
  if (wasMove) { stand(); return; }
  if (clickT) { clearTimeout(clickT); clickT = null; D.petAction({ action: 'open' }); return; }   // double-click → open Zuffi
  const r = pet.getBoundingClientRect(); aurora.poke(e.clientY < r.top + r.height * 0.3);
  clickT = setTimeout(async () => {
    clickT = null; mood('laugh', 1400);
    let next = ''; try { next = await D.petNext(); } catch {}
    say(next || ['Hi! I’m here 💗', 'Double-click me to open Zuffi.', 'Drink some water 💧', 'You’re doing great ✨'][Math.floor(Math.random() * 4)],
      [['Open Zuffi', true, () => D.petAction({ action: 'open' })], ['Hide 1 hour', false, () => { hiddenUntil = Date.now() + 3600000; pet.classList.add('hidden'); reportRects(); }]], 7000);
  }, 260);
});
addEventListener('resize', () => { x = Math.min(x, innerWidth - W - 4); place(); });
