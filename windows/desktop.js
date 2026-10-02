// Windows (desktop) extras for the shared Sparrow web app.
// Loaded only inside the Sparrow desktop app, never on phones.
import { store } from './store.js';
import { greetingWord, fmtTime, tasksForDay } from './brain.js';

const D = window.SparrowDesktop;
document.documentElement.classList.add('desktop');

// ---------- window bar (drag + hide) ----------
const bar = document.createElement('div');
bar.className = 'win-bar';
bar.innerHTML = `<span>🐦 Sparrow</span><div><button data-w="min" title="Minimise">—</button><button data-w="hide" title="Hide (Sparrow keeps running for your reminders)">✕</button></div>`;
document.body.prepend(bar);
bar.onclick = e => { const b = e.target.closest('[data-w]'); if (b) D.window(b.dataset.w); };

const css = document.createElement('style');
css.textContent = `
  .win-bar { position: fixed; z-index: 50; top: 0; left: 0; right: 0; height: 30px; display: flex; align-items: center;
    justify-content: space-between; padding: 0 6px 0 14px; font-size: 12px; color: var(--muted); -webkit-app-region: drag;
    background: linear-gradient(var(--bg0), rgba(18,12,8,.6)); }
  .win-bar button { -webkit-app-region: no-drag; width: 34px; height: 26px; border-radius: 8px; color: var(--muted); }
  .win-bar button:hover { background: rgba(255,255,255,.08); color: var(--text); }
  html.desktop .top { padding-top: 38px; }
  html.desktop #installHint { display: none !important; }
  html.desktop ::-webkit-scrollbar { width: 8px; } html.desktop ::-webkit-scrollbar-thumb { background: rgba(249,168,48,.25); border-radius: 4px; }
`;
document.head.appendChild(css);

// ---------- settings: Windows section ----------
const sec = document.createElement('div');
sec.innerHTML = `<h3>Windows</h3>
  <label class="row"><input type="checkbox" id="wLogin"> 🚀 Start Sparrow when Windows starts</label>
  <label class="row"><input type="checkbox" id="wWake"> 🗣️ Listen for “Sparrow…” hands-free (offline)</label>
  <label class="row"><input type="checkbox" id="wPill"> 🐦 Show the little sparrow bar at the top of the screen</label>
  <p class="small-text">Shortcut: <b>Ctrl + Shift + Space</b> opens Sparrow from anywhere. Say “Sparrow, open Chrome”, “Sparrow, volume up”, “Sparrow, remind me…”.</p>
  <p class="small-text" id="wNote"></p>`;
document.querySelector('#androidSection').after(sec);
const wLogin = sec.querySelector('#wLogin'), wWake = sec.querySelector('#wWake'), wPill = sec.querySelector('#wPill');
D.getSettings().then(s => { wLogin.checked = s.login; wPill.checked = s.pill; });
wLogin.onchange = () => D.setSetting('login', wLogin.checked);
wPill.onchange = () => D.setSetting('pill', wPill.checked);
wWake.checked = localStorage.getItem('sparrow.wake') !== '0';
wWake.onchange = () => { localStorage.setItem('sparrow.wake', wWake.checked ? '1' : '0'); wWake.checked ? Voice.startWake() : Voice.stopWake(); };

// ---------- the little bar at the top of the screen ----------
function pushState(extra = {}) {
  const now = Date.now();
  const next = store.items.filter(i => i.when && !i.done && i.type !== 'note' && new Date(i.when).getTime() > now)
    .sort((a, b) => new Date(a.when) - new Date(b.when))[0];
  const left = tasksForDay(new Date()).length;
  D.state({
    hello: `${greetingWord()}${store.settings.name ? ', ' + store.settings.name : ''}`,
    next: next ? `${next.title} · ${fmtTime(next.when)}` : (left ? `${left} task${left > 1 ? 's' : ''} today` : 'All clear today'),
    ...extra,
  });
}
store.onChange(() => pushState());
setInterval(pushState, 60000);
pushState();

// ---------- voice: offline speech recognition (Vosk) ----------
const send = e => window.sparrowEvent && window.sparrowEvent(e);
const Voice = {
  model: null, rec: null, ctx: null, node: null, stream: null,
  mode: 'off',            // 'off' | 'wake' (waiting for "Sparrow") | 'command' (taking a command)
  cmdTimer: null, loading: null,

  async load() {
    if (this.model) return this.model;
    if (this.loading) return this.loading;
    this.loading = (async () => {
      if (!window.Vosk) await new Promise((res, rej) => {
        const s = document.createElement('script'); s.src = 'lib/vosk.js'; s.onload = res; s.onerror = rej; document.head.appendChild(s);
      });
      const url = await D.modelUrl();
      this.model = await window.Vosk.createModel(url);
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
      if (this.mode === 'off' || window.speechSynthesis?.speaking) return;   // don't hear ourselves
      try { this.rec.acceptWaveform(ev.inputBuffer); } catch {}
    };
    const src = this.ctx.createMediaStreamSource(this.stream);
    src.connect(this.node); this.node.connect(this.ctx.destination);
  },

  /** Text from the recogniser: wake word handling + commands. */
  onText(text, final) {
    text = (text || '').trim().toLowerCase();
    if (!text) return;
    const wake = /^(hey |ok |okay )?(sparrow|spar row|sparo|sparrows|barrow|sparrow's)\b/;
    if (this.mode === 'wake') {
      if (!wake.test(text)) return;
      const rest = text.replace(wake, '').trim();
      if (!final) { send({ type: 'partial', text: rest }); return; }
      if (rest.split(' ').length >= 1 && rest.length > 2) { this.finish(rest); return; }
      this.startCommand();            // just "Sparrow" → listen for the command
      return;
    }
    if (this.mode === 'command') {
      const t = text.replace(wake, '').trim();
      if (!final) { send({ type: 'partial', text: t }); clearTimeout(this.cmdTimer); this.cmdTimer = setTimeout(() => this.endCommand(), 7000); return; }
      if (t) this.finish(t); else this.endCommand();
    }
  },

  startCommand() {
    this.mode = 'command';
    send({ type: 'listening', on: true });
    D.state({ listening: true });
    clearTimeout(this.cmdTimer);
    this.cmdTimer = setTimeout(() => this.endCommand(), 7000);
  },
  endCommand() {
    clearTimeout(this.cmdTimer);
    send({ type: 'listening', on: false });
    D.state({ listening: false });
    pushState();
    this.mode = this.wakeOn ? 'wake' : 'off';
  },
  finish(text) {
    this.endCommand();
    send({ type: 'partial', text: '' });
    D.show();
    send({ type: 'speech', text });
  },

  /** Mic button / bird tap: take one command, no wake word needed. */
  async toggle() {
    try {
      if (this.mode === 'command') { this.endCommand(); return; }
      if (!this.model) send({ type: 'toast', text: 'Getting voice ready… (first time only)' });
      await this.ensureMic();
      if (this.ctx.state === 'suspended') await this.ctx.resume();
      this.startCommand();
    } catch (e) {
      send({ type: 'toast', text: 'Microphone not available: ' + (e.message || e) });
    }
  },
  wakeOn: false,
  async startWake() {
    try {
      this.wakeOn = true;
      await this.ensureMic();
      if (this.mode === 'off') this.mode = 'wake';
      sec.querySelector('#wNote').textContent = 'Listening for “Sparrow…” — everything stays on this PC.';
    } catch (e) {
      this.wakeOn = false;
      sec.querySelector('#wNote').textContent = 'Couldn\'t use the microphone: ' + (e.message || e);
    }
  },
  stopWake() { this.wakeOn = false; if (this.mode === 'wake') this.mode = 'off'; sec.querySelector('#wNote').textContent = ''; },
};
window.SparrowVoice = Voice;
if (wWake.checked) setTimeout(() => Voice.startWake(), 2500);

// Global shortcut / pill click → listen
D.onCommand(cmd => { if (cmd === 'listen') Voice.toggle(); });
