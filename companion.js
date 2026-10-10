// Zuffi Live — a full-screen animated Zuffi you talk to (like a video call with your assistant).
// The bunny breathes, blinks, listens, thinks, moves her mouth while she talks and reacts with hearts and sparkles.
// The helpers (agents) orbit around her and light up when they're working: reminders, calendar, search, music, memory, WhatsApp.
//
// Frames in mascots/zuffi-bust.webp (3×3): 0 blink · 1 heart · 2 sparkle · 3 surprised · 4 starstruck · 5 bashful · 6 sleepy · 7 dizzy · 8 delighted

const AGENTS = [
  { id: 'remind', icon: '⏰', name: 'Reminders' }, { id: 'plan', icon: '🗓️', name: 'Calendar' }, { id: 'search', icon: '🔎', name: 'Search' },
  { id: 'music', icon: '🎵', name: 'Music' }, { id: 'memory', icon: '🧠', name: 'Memory' }, { id: 'chat', icon: '💬', name: 'WhatsApp' },
  { id: 'ai', icon: '✨', name: 'AI brain' }, { id: 'money', icon: '💷', name: 'Money' },
];

let root = null, face = null, ring = null, capMe = null, capZ = null, stateLbl = null, input = null;
let state = 'idle', talkTimer = null, blinkTimer = null, typeTimer = null, onMic = null, onSend = null, onClose = null;
export let continuous = true;

const frame = i => { if (face) face.style.backgroundPosition = `${(i % 3) * 50}% ${Math.floor(i / 3) * 50}%`; };

export function isOpen() { return !!root && !root.hidden; }

export function open({ mic, send, close } = {}) {
  onMic = mic; onSend = send; onClose = close;
  if (!root) build();
  root.hidden = false;
  document.documentElement.classList.add('zc-open');
  setState('idle');
  greet();
}

export function close() {
  if (!root) return;
  root.hidden = true;
  document.documentElement.classList.remove('zc-open');
  clearInterval(talkTimer); clearTimeout(blinkTimer); clearInterval(typeTimer);
  onClose?.();
}

function greet() {
  const h = new Date().getHours();
  say(h < 12 ? 'Good morning! Tap the mic and talk to me.' : h < 18 ? 'Hi! Tap the mic and talk to me.' : 'Good evening! Tap the mic and talk to me.', true);
  react(2);
}

function build() {
  root = document.createElement('div');
  root.className = 'zc'; root.hidden = true;
  root.innerHTML = `
    <div class="zc-sky"><i class="o1"></i><i class="o2"></i><i class="o3"></i><b class="stars"></b><b class="stars s2"></b></div>
    <div class="zc-top"><span class="zc-live"><i></i> Zuffi Live</span><span class="zc-state">Ready</span><button class="zc-x" aria-label="Close">✕</button></div>
    <div class="zc-stage">
      <div class="zc-orbit">${AGENTS.map((a, i) => `<span class="zc-agent" data-a="${a.id}" style="--i:${i};--n:${AGENTS.length}" title="${a.name}"><em>${a.icon}</em><small>${a.name}</small></span>`).join('')}</div>
      <div class="zc-ring"></div><div class="zc-ring r2"></div>
      <div class="zc-body"><div class="zc-face" role="img" aria-label="Zuffi"></div></div>
      <div class="zc-shadow"></div>
      <div class="zc-fx"></div>
    </div>
    <div class="zc-caps"><p class="zc-me"></p><p class="zc-z"></p></div>
    <div class="zc-bar">
      <button class="zc-kb" aria-label="Type">⌨️</button>
      <button class="zc-mic" aria-label="Talk"><span class="zc-wave"><i></i><i></i><i></i><i></i><i></i></span><svg viewBox="0 0 24 24"><path d="M12 15a3 3 0 0 0 3-3V6a3 3 0 1 0-6 0v6a3 3 0 0 0 3 3Zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-2.08A7 7 0 0 0 19 12h-2Z" fill="currentColor"/></svg></button>
      <button class="zc-loop on" aria-label="Keep talking">🔁</button>
    </div>
    <form class="zc-type" hidden><input placeholder="Type to Zuffi…" autocomplete="off"><button>Send</button></form>`;
  document.body.appendChild(root);
  face = root.querySelector('.zc-face'); ring = root.querySelector('.zc-ring');
  capMe = root.querySelector('.zc-me'); capZ = root.querySelector('.zc-z'); stateLbl = root.querySelector('.zc-state');
  input = root.querySelector('.zc-type input');
  root.querySelector('.zc-x').onclick = close;
  root.querySelector('.zc-mic').onclick = () => onMic?.();
  root.querySelector('.zc-kb').onclick = () => { const f = root.querySelector('.zc-type'); f.hidden = !f.hidden; if (!f.hidden) input.focus(); };
  root.querySelector('.zc-loop').onclick = e => { continuous = !continuous; e.currentTarget.classList.toggle('on', continuous); };
  root.querySelector('.zc-type').onsubmit = e => { e.preventDefault(); const t = input.value.trim(); if (t) { input.value = ''; onSend?.(t); } };
  face.onclick = () => { react([1, 2, 4, 8][Math.floor(Math.random() * 4)]); hearts(5); };
  // Tilt toward the finger / mouse a little.
  root.addEventListener('pointermove', e => {
    const r = face.getBoundingClientRect(), dx = (e.clientX - (r.left + r.width / 2)) / innerWidth, dy = (e.clientY - (r.top + r.height / 2)) / innerHeight;
    root.style.setProperty('--tx', (dx * 14).toFixed(1) + 'px'); root.style.setProperty('--rot', (dx * 6).toFixed(1) + 'deg'); root.style.setProperty('--ty', (dy * 8).toFixed(1) + 'px');
  });
  scheduleBlink();
}

function scheduleBlink() {
  clearTimeout(blinkTimer);
  blinkTimer = setTimeout(() => {
    if (state === 'idle' || state === 'listening') { frame(0); setTimeout(() => { if (state === 'idle' || state === 'listening') frame(base()); }, 140); }
    scheduleBlink();
  }, 2600 + Math.random() * 2600);
}
const base = () => state === 'listening' ? 4 : state === 'thinking' ? 6 : 5;

/** idle · listening · thinking · talking */
export function setState(s) {
  if (!root) return;
  state = s;
  root.dataset.state = s;
  stateLbl.textContent = { idle: 'Ready', listening: 'Listening…', thinking: 'Thinking…', talking: 'Speaking' }[s] || '';
  clearInterval(talkTimer);
  if (s === 'talking') {
    let open = false;
    talkTimer = setInterval(() => { open = !open && Math.random() > 0.12; frame(open ? 8 : 5); }, 120 + Math.random() * 60);
  } else frame(base());
  if (s === 'thinking') agent('ai');
}

/** Briefly shows a reaction frame (1 heart, 2 sparkle, 4 starstruck, 8 delighted…). */
export function react(i, ms = 1100) {
  if (!root) return;
  frame(i);
  root.classList.remove('zc-pop'); void root.offsetWidth; root.classList.add('zc-pop');
  setTimeout(() => { if (state !== 'talking') frame(base()); }, ms);
}

export function hearts(n = 6) {
  if (!root) return;
  const fx = root.querySelector('.zc-fx');
  for (let k = 0; k < n; k++) {
    const h = document.createElement('i');
    h.textContent = ['💗', '✨', '💖', '⭐'][k % 4];
    h.style.left = (35 + Math.random() * 30) + '%'; h.style.animationDelay = (k * 0.08) + 's'; h.style.setProperty('--dx', (Math.random() * 120 - 60) + 'px');
    fx.appendChild(h); setTimeout(() => h.remove(), 1800);
  }
}

/** Lights up a helper in the orbit. */
export function agent(id) {
  if (!root) return;
  const el = root.querySelector(`.zc-agent[data-a="${id}"]`);
  if (!el) return;
  el.classList.remove('busy'); void el.offsetWidth; el.classList.add('busy');
  setTimeout(() => el.classList.remove('busy'), 2600);
}

/** Guess which helper did the work from the text. */
export function agentFor(text) {
  const t = (text || '').toLowerCase();
  if (/remind|alarm|water|medicine|timer/.test(t)) return 'remind';
  if (/meeting|calendar|tomorrow|today|schedule|appointment|plan/.test(t)) return 'plan';
  if (/search|google|look up|news|weather|price/.test(t)) return 'search';
  if (/play|song|music|spotify|youtube/.test(t)) return 'music';
  if (/remember|memory|note|file|document/.test(t)) return 'memory';
  if (/whatsapp|message|text |reply/.test(t)) return 'chat';
  if (/expense|income|profit|salary|paid|£|rs\b|lakh|crore/.test(t)) return 'money';
  return 'ai';
}

export function user(text) {
  if (!root) return;
  capMe.textContent = text ? '“' + text + '”' : '';
  agent(agentFor(text));
}

/** Shows Zuffi's words like live subtitles. */
export function say(text, instant = false) {
  if (!root) return;
  clearInterval(typeTimer);
  const clean = String(text || '').replace(/\s+/g, ' ').trim();
  if (instant) { capZ.textContent = clean; return; }
  let i = 0;
  capZ.textContent = '';
  typeTimer = setInterval(() => { i += 2; capZ.textContent = clean.slice(0, i); if (i >= clean.length) clearInterval(typeTimer); }, 28);
}

export function partial(text) { if (root && text) capMe.textContent = '“' + text + '…”'; }
