// The Sparrow island for Mac + Windows: a black glass island at the top of the screen that springs open.
// Loaded only in the computer app, never on phones.
import { store } from './store.js';
import { greetingWord, fmtTime, tasksForDay } from './brain.js';
import * as mem from './memory.js';

const D = window.SparrowDesktop;
const S = () => store.settings;
const plat = D.platform();
const html = document.documentElement;
html.classList.add('desktop', 'island-mode', 'isl-collapsed', 'os-' + plat);

// ---------- build the island around the app ----------
const island = document.createElement('div'); island.id = 'island';
const body = document.createElement('div'); body.className = 'isl-body';
[...document.body.children].forEach(el => { if (el.tagName !== 'SCRIPT') body.appendChild(el); });
const cap = document.createElement('button'); cap.className = 'cap'; cap.setAttribute('aria-label', 'Open Sparrow');
cap.innerHTML = `<span class="cap-bird"><img src="icons/icon-192.png" alt=""></span>
  <span class="cap-txt"><b id="capT1">Sparrow</b><small id="capT2">Say “Sparrow…”</small></span>
  <span class="cap-wave" aria-hidden="true"><i></i><i></i><i></i><i></i></span>`;
const glow = document.createElement('div'); glow.className = 'isl-glow';
island.append(glow, cap, body);
document.body.prepend(island);

// collapse button in the header
const top = body.querySelector('.top');
const shrink = document.createElement('button');
shrink.className = 'icon-btn isl-shrink'; shrink.setAttribute('aria-label', 'Close'); shrink.title = 'Close (Esc)';
shrink.innerHTML = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg>';
top.appendChild(shrink);

// ---------- states: collapsed · peek · expanded ----------
let state = 'collapsed', peekTimer = null;
function setState(s) {
  state = s;
  html.classList.toggle('isl-collapsed', s === 'collapsed');
  html.classList.toggle('isl-peek', s === 'peek');
  html.classList.toggle('isl-expanded', s === 'expanded');
  D.islandState(s === 'expanded' ? 'expanded' : 'collapsed');
  if (s === 'expanded') setTimeout(() => document.querySelector('#askInput')?.focus({ preventScroll: true }), 380);
  if (s !== 'peek') clearTimeout(peekTimer);
  mouseInside(s === 'expanded');
}
const expand = () => setState('expanded');
const collapse = () => { if (document.querySelector('.sheet:not([hidden])')) document.querySelector('#sheetBg')?.click(); setState('collapsed'); pushCap(); };
/** Show a short message in the island (alerts, voice replies), then shrink back. */
function peek(t1, t2 = '', ms = 6000) {
  if (state === 'expanded') return;
  capText(t1, t2); setState('peek');
  clearTimeout(peekTimer); peekTimer = setTimeout(() => { if (state === 'peek') { setState('collapsed'); pushCap(); } }, ms);
}
cap.onclick = expand;
shrink.onclick = collapse;
document.addEventListener('keydown', e => { if (e.key === 'Escape' && state === 'expanded' && document.querySelector('#focus').hidden) { e.stopPropagation(); collapse(); } }, true);
D.onIsland(v => {
  if (v === 'expand') expand();
  else if (v === 'collapse') collapse();
  else if (v === 'hide-cap') html.classList.add('cap-hidden');
  else if (v === 'show-cap') html.classList.remove('cap-hidden');
  else if (v.startsWith('pos:')) setPos(v.slice(4));
});
D.getSettings().then(s => { if (s.pill === false) html.classList.add('cap-hidden'); if (s.notch) html.classList.add('has-notch'); });

function setPos(p) { html.classList.remove('pos-right', 'pos-left', 'pos-center'); html.classList.add('pos-' + p); }
setPos('right');

// Only the island catches the mouse — the rest of the window clicks through to your apps.
let inside = null;
function mouseInside(v) { if (v !== inside) { inside = v; D.mouseInside(v); } }
document.addEventListener('mousemove', e => {
  const r = island.getBoundingClientRect();
  const over = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom + 4;
  mouseInside(over || state === 'expanded' && !!document.querySelector('.sheet:not([hidden]), #focus:not([hidden])'));
  html.classList.toggle('cap-hover', over && state === 'collapsed');
});
document.addEventListener('mouseleave', () => { if (state !== 'expanded') mouseInside(false); html.classList.remove('cap-hover'); });

// ---------- capsule text ----------
function capText(t1, t2) { cap.querySelector('#capT1').textContent = t1; cap.querySelector('#capT2').textContent = t2; }
function pushCap() {
  if (state === 'peek' || Voice.mode === 'command') return;
  const now = Date.now();
  const next = store.items.filter(i => i.when && !i.done && ['task', 'meeting', 'reminder'].includes(i.type) && new Date(i.when).getTime() > now)
    .sort((a, b) => new Date(a.when) - new Date(b.when))[0];
  const left = tasksForDay(new Date()).length;
  capText(`${greetingWord()}${S().name ? ', ' + S().name : ''}`,
    next ? `${next.title} · ${fmtTime(next.when)}` : left ? `${left} task${left > 1 ? 's' : ''} today` : (Voice.wakeOn ? 'Say “Sparrow…”' : 'All clear today'));
}
store.onChange(pushCap); setInterval(pushCap, 60000); setTimeout(pushCap, 300);

// hooks used by app.js
window.SparrowIsland = {
  peek, expand, collapse, get state() { return state; },
  /** A reply to something said while the island was closed: short ones peek, long ones open the island. */
  reply(text, isCommand) {
    if (state === 'expanded') return;
    if (isCommand || text.length < 90) peek(text.split('\n')[0].slice(0, 80), isCommand ? '' : 'Tap to see more', isCommand ? 4000 : 7000);
    else expand();
  },
};

// ---------- settings: this computer ----------
const sec = document.createElement('details');
sec.innerHTML = `<summary>💻 This ${plat === 'mac' ? 'Mac' : 'computer'}</summary>
  <label class="row"><input type="checkbox" id="dLogin"> 🚀 Start Sparrow when I log in</label>
  <label class="row"><input type="checkbox" id="dPill"> 🐦 Show the island at the top when Sparrow is closed</label>
  <label class="row"><input type="checkbox" id="dClip"> 📎 Keep a clipboard history (on this computer only)</label>
  <label class="field"><span>Where Sparrow lives</span><select id="dPos"><option value="right">Top right corner</option><option value="center">Top centre (notch)</option><option value="left">Top left corner</option></select></label>
  <p class="small-text">Open Sparrow: click the island, press <b>${plat === 'mac' ? '⌘' : 'Ctrl'} + Shift + Space</b>, or just say “Sparrow…”. Close: <b>Esc</b> or click anywhere else.</p>
  <p class="small-text" id="dNote"></p>`;
body.querySelector('#desktopSection').appendChild(sec);
const dLogin = sec.querySelector('#dLogin'), dPill = sec.querySelector('#dPill'), dClip = sec.querySelector('#dClip');
const dPos = sec.querySelector('#dPos');
D.getSettings().then(s => { dLogin.checked = s.login; dPill.checked = s.pill !== false; dClip.checked = s.clipboard !== false; dPos.value = s.position || 'right'; setPos(s.position || 'right'); });
dPos.onchange = () => D.setSetting('position', dPos.value);
dLogin.onchange = () => D.setSetting('login', dLogin.checked);
dPill.onchange = () => D.setSetting('pill', dPill.checked);
dClip.onchange = () => D.setSetting('clipboard', dClip.checked);

// ---------- folder watcher ----------
D.onEvent(ev => {
  if (ev.type === 'file-arrived') {
    mem.remember('file', ev.name, '', { folder: ev.folder, path: ev.path });
    peek(`📥 ${ev.name}`, `New file in ${ev.folder}`);
    if (S().speak) window.Sparrow?.speak(`New file in ${ev.folder}: ${ev.name.replace(/\.[^.]+$/, '')}`);
  }
});

// ---------- recent files into memory (optional) ----------
async function rememberRecent() {
  if (!S().memory?.recentFiles) return;
  const seen = new Set(JSON.parse(localStorage.getItem('sparrow.recentSeen') || '[]'));
  for (const f of await D.recentFiles(1)) {
    const key = f.path + '|' + Math.round(f.mtime / 3600e3);
    if (seen.has(key)) continue;
    seen.add(key); mem.remember('opened', f.name, '', { path: f.path, recent: true });
  }
  try { localStorage.setItem('sparrow.recentSeen', JSON.stringify([...seen].slice(-500))); } catch {}
}
setInterval(rememberRecent, 15 * 60000); setTimeout(rememberRecent, 20000);

// ---------- voice: offline speech recognition (Vosk) ----------
const send = e => window.sparrowEvent && window.sparrowEvent(e);
// Things the recogniser "hears" in background noise — never treat these as a command.
const JUNK = /^(i|a|the|uh|um|umm|hm+|huh|oh|ah|eh|and|so|it|is|you|to|in|of|on|at|but|that|this|yeah|hey|hmm|mm|her|his|he|she|we|they|one|be|or|if|an)$/;
function meaningful(text, words) {
  const t = text.trim();
  if (t.length < 3 || JUNK.test(t)) return false;
  const w = t.split(/\s+/);
  if (w.length === 1 && w[0].length < 4 && !/^(yes|no|stop|play|next|mute)$/.test(w[0])) return false;
  if (words?.length) { const avg = words.reduce((n, x) => n + (x.conf ?? 1), 0) / words.length; if (avg < 0.62) return false; }
  return true;
}
const Voice = {
  model: null, rec: null, ctx: null, node: null, stream: null, loading: null,
  mode: 'off',          // 'off' | 'wake' | 'command' | 'dictate'
  cmdTimer: null, wakeOn: false, dictateCb: null,

  async load() {
    if (this.model) return this.model;
    if (this.loading) return this.loading;
    this.loading = (async () => {
      if (!window.Vosk) await new Promise((res, rej) => { const s = document.createElement('script'); s.src = 'lib/vosk.js'; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
      this.model = await window.Vosk.createModel(await D.modelUrl());
      return this.model;
    })();
    return this.loading;
  },
  native: false,
  /** On a Mac, Apple's own speech engine (much better than the built-in fallback). */
  nativeReady() {
    if (this.native) return true;
    const nvx = D.nativeVoice;
    if (!nvx || !nvx.available()) return false;
    this.native = true;
    nvx.on(ev => {
      if (ev.ev === 'partial') this.onText(ev.text, false);
      else if (ev.ev === 'final') this.onText(ev.text, true);
      else if (ev.ev === 'speaking') send({ type: 'speaking', on: ev.on });
      else if (ev.ev === 'auth' && !(ev.speech && ev.mic)) sec.querySelector('#dNote').textContent = 'Sparrow needs Microphone and Speech Recognition: System Settings → Privacy & Security → Microphone / Speech Recognition → turn on Sparrow.';
      else if (ev.ev === 'voices') this.voiceList = ev;
    });
    nvx.send({ cmd: 'voices' });
    return true;
  },
  nativeSay(text) {
    if (!this.nativeReady()) return false;
    const rate = S().simple ? 0.44 : 0.5;
    return D.nativeVoice.send({ cmd: 'say', text, gender: S().gender || 'female', rate });
  },
  async ensureMic() {
    if (this.nativeReady()) { if (!this.nativeOn) { const ctx = [...new Set([...(S().quick || []).map(q => q.n), ...store.ofType('customer').map(c => c.title), 'Gmail', 'Spotify', 'WhatsApp'])]; D.nativeVoice.send({ cmd: 'listen', context: ctx }); this.nativeOn = true; } this.ctx = { state: 'running' }; return; }
    if (this.stream) return;
    await this.load();
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } });
    this.ctx = new AudioContext();
    this.rec = new this.model.KaldiRecognizer(this.ctx.sampleRate);
    try { this.rec.setWords(true); } catch {}
    this.rec.on('result', m => this.onText(m.result.text, true, m.result.result));
    this.rec.on('partialresult', m => this.onText(m.result.partial, false));
    this.node = this.ctx.createScriptProcessor(4096, 1, 1);
    this.node.onaudioprocess = ev => {
      if (this.mode === 'off' || (this.mode !== 'dictate' && window.speechSynthesis?.speaking)) return;   // don't hear ourselves
      try { this.rec.acceptWaveform(ev.inputBuffer); } catch {}
    };
    const src = this.ctx.createMediaStreamSource(this.stream);
    src.connect(this.node); this.node.connect(this.ctx.destination);
  },
  onText(text, final, words) {
    text = (text || '').replace(/\[unk\]/g, '').trim().toLowerCase().replace(/[.,!?]+$/, '');
    if (this.mode === 'dictate') { if (text) this.dictateCb?.(text, final); return; }
    if (!text) return;
    const wake = /^(hey |ok |okay )?(sparrow|spar row|sparo|sparrows|sparrow's)\b/;
    if (this.mode === 'wake') {
      // the wake word can come anywhere: "…hey Sparrow, open Gmail"
      const m = text.match(/\b(?:hey |ok |okay )?(sparrow's|sparrows|sparrow|sparro|sparo|spar row)\b[,\s]*(.*)$/);
      if (!m) return;
      const rest = m[2].trim();
      if (!final) { capText('Listening…', rest || 'Go ahead'); return; }
      if (meaningful(rest, words?.slice(1))) { this.finish(rest); return; }
      this.startCommand();
      return;
    }
    if (this.mode === 'command') {
      const tx = text.replace(wake, '').trim();
      if (!final) { send({ type: 'partial', text: tx }); capText('Listening…', tx || 'Go ahead'); clearTimeout(this.cmdTimer); this.cmdTimer = setTimeout(() => this.endCommand(), 6000); return; }
      if (meaningful(tx, words)) this.finish(tx);   // noise like "i" is ignored — keep listening until the timeout
    }
  },
  async startCommand() {
    try { await this.ensureMic(); if (this.ctx.state === 'suspended') await this.ctx.resume(); } catch { return; }
    this.mode = 'command';
    html.classList.add('isl-listening'); capText('Listening…', 'Go ahead');
    if (state === 'collapsed') setState('peek');
    send({ type: 'listening', on: true });
    clearTimeout(this.cmdTimer); this.cmdTimer = setTimeout(() => this.endCommand(), 6000);
  },
  endCommand() {
    clearTimeout(this.cmdTimer);
    if (this.native && !this.wakeOn && this.mode !== 'dictate') { D.nativeVoice.send({ cmd: 'stop' }); this.nativeOn = false; }
    html.classList.remove('isl-listening');
    send({ type: 'listening', on: false });
    this.mode = this.wakeOn ? 'wake' : 'off';
    if (state === 'peek') { setState('collapsed'); }
    pushCap();
  },
  finish(text) {
    this.endCommand(); send({ type: 'partial', text: '' });
    capText('🐦 ' + text.slice(0, 60), 'On it…'); if (state !== 'expanded') setState('peek');
    send({ type: 'speech', text });
  },
  /** Mic button / tap: take one command, no wake word needed. */
  async toggle() {
    try {
      if (this.mode === 'command') { this.endCommand(); return; }
      if (!this.model) send({ type: 'toast', text: 'Getting voice ready… (first time only)' });
      await this.startCommand();
    } catch (e) { send({ type: 'toast', text: 'Microphone not available: ' + (e.message || e) }); }
  },
  async startWake() {
    try {
      this.wakeOn = true; await this.ensureMic();
      if (this.mode === 'off') this.mode = 'wake';
      sec.querySelector('#dNote').textContent = this.native ? 'Listening for “Sparrow…” with your Mac’s own speech recognition.' : 'Listening for “Sparrow…” — understood on this computer, never uploaded.';
      pushCap();
    } catch (e) {
      this.wakeOn = false;
      sec.querySelector('#dNote').textContent = `Couldn't use the microphone: ${e.message || e}. ${plat === 'mac' ? 'Allow it in System Settings → Privacy & Security → Microphone.' : 'Allow it in Settings → Privacy → Microphone.'}`;
    }
  },
  stopWake() { this.wakeOn = false; if (this.mode === 'wake') this.mode = 'off'; if (this.native) { D.nativeVoice.send({ cmd: 'stop' }); this.nativeOn = false; } pushCap(); },
  /** Meeting notes: every word goes to cb(text, isFinal) until the returned stop() is called. */
  dictate(cb) {
    this.dictateCb = cb;
    this.ensureMic().then(() => { if (this.ctx.state === 'suspended') this.ctx.resume(); this.mode = 'dictate'; })
      .catch(e => cb(`(microphone not available: ${e.message || e})`, true));
    return () => { this.dictateCb = null; this.mode = this.wakeOn ? 'wake' : 'off'; if (this.native && !this.wakeOn) { D.nativeVoice.send({ cmd: 'stop' }); this.nativeOn = false; } };
  },
};
window.SparrowVoice = Voice;
if (S().wake !== false) setTimeout(() => Voice.startWake(), 2500);
D.onCommand(cmd => { if (cmd === 'listen') Voice.toggle(); });
