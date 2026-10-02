// Extras for the Sparrow computer app (Mac + Windows). Loaded only there, never on phones.
import { store } from './store.js';
import { greetingWord, fmtTime, tasksForDay } from './brain.js';
import * as mem from './memory.js';

const D = window.SparrowDesktop;
const S = () => store.settings;
const plat = D.platform();
document.documentElement.classList.add('desktop', 'os-' + plat);

// ---------- window bar (drag + hide) ----------
const bar = document.createElement('div');
bar.className = 'win-bar';
bar.innerHTML = `<span class="wb-title">Sparrow</span><div><button data-w="min" title="Minimise" aria-label="Minimise">—</button><button data-w="hide" title="Hide — Sparrow keeps running for your reminders" aria-label="Hide">✕</button></div>`;
document.body.prepend(bar);
bar.onclick = e => { const b = e.target.closest('[data-w]'); if (b) D.window(b.dataset.w); };
const css = document.createElement('style');
css.textContent = `
  .win-bar { position: fixed; z-index: 50; top: 0; left: 0; right: 0; height: 30px; display: flex; align-items: center; justify-content: space-between;
    padding: 0 6px 0 14px; font-size: 12px; font-weight: 700; color: var(--faint); -webkit-app-region: drag; background: var(--bg); }
  .win-bar button { -webkit-app-region: no-drag; width: 34px; height: 26px; border-radius: 8px; color: var(--muted); }
  .win-bar button:hover { background: var(--soft); color: var(--text); }
  html.desktop #installHint { display: none !important; }
  html.desktop ::-webkit-scrollbar { width: 8px; } html.desktop ::-webkit-scrollbar-thumb { background: var(--line); border-radius: 4px; }
`;
document.head.appendChild(css);

// ---------- settings: computer section ----------
const sec = document.createElement('details');
sec.innerHTML = `<summary>💻 This ${plat === 'mac' ? 'Mac' : 'computer'}</summary>
  <label class="row"><input type="checkbox" id="dLogin"> 🚀 Start Sparrow when I log in</label>
  <label class="row"><input type="checkbox" id="dPill"> 🐦 Show the little Sparrow bar at the top of the screen</label>
  <label class="row"><input type="checkbox" id="dClip"> 📎 Keep a clipboard history (on this computer only)</label>
  <p class="small-text">Shortcut: <b>${plat === 'mac' ? '⌘' : 'Ctrl'} + Shift + Space</b> opens Sparrow from anywhere. Or just say “Sparrow, open Chrome”, “Sparrow, find the contract”, “Sparrow, volume up”.</p>
  <p class="small-text" id="dNote"></p>`;
document.querySelector('#desktopSection').appendChild(sec);
const dLogin = sec.querySelector('#dLogin'), dPill = sec.querySelector('#dPill'), dClip = sec.querySelector('#dClip');
D.getSettings().then(s => { dLogin.checked = s.login; dPill.checked = s.pill; dClip.checked = s.clipboard !== false; });
dLogin.onchange = () => D.setSetting('login', dLogin.checked);
dPill.onchange = () => D.setSetting('pill', dPill.checked);
dClip.onchange = () => D.setSetting('clipboard', dClip.checked);

// ---------- the little bar at the top of the screen ----------
function pushState(extra = {}) {
  const now = Date.now();
  const next = store.items.filter(i => i.when && !i.done && ['task', 'meeting', 'reminder'].includes(i.type) && new Date(i.when).getTime() > now)
    .sort((a, b) => new Date(a.when) - new Date(b.when))[0];
  const left = tasksForDay(new Date()).length;
  D.state({ hello: `${greetingWord()}${S().name ? ', ' + S().name : ''}`,
    next: next ? `${next.title} · ${fmtTime(next.when)}` : (left ? `${left} task${left > 1 ? 's' : ''} today` : 'All clear today'), ...extra });
}
store.onChange(() => pushState());
setInterval(pushState, 60000);
pushState();

// ---------- folder watcher & other events from the computer ----------
D.onEvent(ev => {
  if (ev.type === 'file-arrived') {
    mem.remember('file', ev.name, '', { folder: ev.folder, path: ev.path });
    window.Sparrow?.toast(`📥 New file in ${ev.folder}: ${ev.name}`, 6000);
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

// ---------- voice: offline speech recognition (Vosk), wake word + dictation ----------
const send = e => window.sparrowEvent && window.sparrowEvent(e);
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
  async ensureMic() {
    if (this.stream) return;
    await this.load();
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, channelCount: 1 } });
    this.ctx = new AudioContext();
    this.rec = new this.model.KaldiRecognizer(this.ctx.sampleRate);
    this.rec.on('result', m => this.onText(m.result.text, true));
    this.rec.on('partialresult', m => this.onText(m.result.partial, false));
    this.node = this.ctx.createScriptProcessor(4096, 1, 1);
    this.node.onaudioprocess = ev => {
      if (this.mode === 'off' || (this.mode !== 'dictate' && window.speechSynthesis?.speaking)) return;   // don't hear ourselves
      try { this.rec.acceptWaveform(ev.inputBuffer); } catch {}
    };
    const src = this.ctx.createMediaStreamSource(this.stream);
    src.connect(this.node); this.node.connect(this.ctx.destination);
  },
  onText(text, final) {
    text = (text || '').trim().toLowerCase();
    if (this.mode === 'dictate') { if (text) this.dictateCb?.(text, final); return; }
    if (!text) return;
    const wake = /^(hey |ok |okay )?(sparrow|spar row|sparo|sparrows|barrow|sparrow's)\b/;
    if (this.mode === 'wake') {
      if (!wake.test(text)) return;
      const rest = text.replace(wake, '').trim();
      if (!final) { send({ type: 'partial', text: rest }); return; }
      if (rest.length > 2) { this.finish(rest); return; }
      this.startCommand();
      return;
    }
    if (this.mode === 'command') {
      const tx = text.replace(wake, '').trim();
      if (!final) { send({ type: 'partial', text: tx }); clearTimeout(this.cmdTimer); this.cmdTimer = setTimeout(() => this.endCommand(), 7000); return; }
      if (tx) this.finish(tx); else this.endCommand();
    }
  },
  async startCommand() {
    try { await this.ensureMic(); if (this.ctx.state === 'suspended') await this.ctx.resume(); } catch { return; }
    this.mode = 'command';
    send({ type: 'listening', on: true }); D.state({ listening: true });
    clearTimeout(this.cmdTimer); this.cmdTimer = setTimeout(() => this.endCommand(), 7000);
  },
  endCommand() {
    clearTimeout(this.cmdTimer);
    send({ type: 'listening', on: false }); D.state({ listening: false }); pushState();
    this.mode = this.wakeOn ? 'wake' : 'off';
  },
  finish(text) { this.endCommand(); send({ type: 'partial', text: '' }); D.show(); send({ type: 'speech', text }); },
  /** Mic button / bird tap: take one command, no wake word needed. */
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
      sec.querySelector('#dNote').textContent = 'Listening for “Sparrow…” — understood on this computer, never uploaded.';
      document.querySelector('#listenHint').hidden = false;
    } catch (e) {
      this.wakeOn = false;
      sec.querySelector('#dNote').textContent = `Couldn't use the microphone: ${e.message || e}. ${plat === 'mac' ? 'Allow it in System Settings → Privacy & Security → Microphone.' : 'Allow it in Settings → Privacy → Microphone.'}`;
    }
  },
  stopWake() { this.wakeOn = false; if (this.mode === 'wake') this.mode = 'off'; document.querySelector('#listenHint').hidden = true; },
  /** Meeting notes: every word goes to cb(text, isFinal) until the returned stop() is called. */
  dictate(cb) {
    const before = this.mode;
    this.dictateCb = cb;
    this.ensureMic().then(() => { if (this.ctx.state === 'suspended') this.ctx.resume(); this.mode = 'dictate'; })
      .catch(e => cb(`(microphone not available: ${e.message || e})`, true));
    return () => { this.dictateCb = null; this.mode = this.wakeOn ? 'wake' : (before === 'dictate' ? 'off' : before); };
  },
};
window.SparrowVoice = Voice;
if (S().wake !== false) setTimeout(() => Voice.startWake(), 2500);
D.onCommand(cmd => { if (cmd === 'listen') Voice.toggle(); });
