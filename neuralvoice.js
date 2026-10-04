// Sparrow's natural voices — neural text-to-speech that runs on the device, offline.
//   English: Kokoro-82M (Apache-2.0)        Urdu / Roman Urdu / Hindi / Punjabi: Meta MMS-TTS (CC-BY-NC 4.0)
//   Optional "Studio voice": OmniVoice running on this computer (127.0.0.1:47321), used first when it's ready.
// Models ship inside the app (./models/…); when they're missing this module simply says "not available"
// and the app falls back to the system voice.

const BASE = new URL('./', location.href).href;
const MODELS = BASE + 'models/';
const LIB = BASE + 'lib/voice/';
const STUDIO = 'http://127.0.0.1:47321';

export const KOKORO_VOICES = {
  af_heart: 'Heart (warm, American)', af_bella: 'Bella (bright, American)', bf_emma: 'Emma (British)',
  am_michael: 'Michael (calm, American)', bm_george: 'George (British)',
  ...(window.SparrowHost === 'mac' ? { af_nicole: 'Nicole (soft, American)', bf_isabella: 'Isabella (British)', bm_lewis: 'Lewis (British)' } : {}),
};
const MMS = { urd: 'mms-urd', 'urd-latn': 'mms-urd-latn', hin: 'mms-hin', pan: 'mms-pan', 'hin-x': 'mms-hin-x' };
const PROBE = { urd: 'سلام', 'urd-latn': 'salam', hin: 'नमस्ते', pan: 'ਸਤ ਸ੍ਰੀ', 'hin-x': 'नमस्ते' };
export const MMS_DTYPES = ['q8', 'int8'];
const ortMessage = e => (typeof e === 'number' || /^\d+$/.test(String(e?.message ?? e))) ? 'engine error ' + (e?.message ?? e) : String(e?.message || e);

let lib = null, kokoro = null, kokoroLoading = null;
const mms = {};
let ctx = null, current = null, turn = 0, present = null;

const log = (...a) => { try { window.SparrowMac?.post('log', { text: '[voice] ' + a.join(' ') }); } catch {} console.log('[voice]', ...a); };

async function exists(url) {
  try { const r = await fetch(url, { method: 'HEAD' }); return r.ok; } catch { return false; }
}
/** Are the built-in models shipped with this app? (checked once) */
export async function available() {
  if (present === null) present = await exists(MODELS + 'kokoro/config.json');
  return present;
}

async function loadLib() {
  if (lib) return lib;
  lib = await import(LIB + 'voice.js');
  const { env } = lib;
  env.allowRemoteModels = false;
  env.allowLocalModels = true;
  env.localModelPath = MODELS;
  env.useBrowserCache = false;
  env.backends.onnx.wasm.wasmPaths = LIB;
  env.backends.onnx.wasm.numThreads = self.crossOriginIsolated ? Math.min(4, navigator.hardwareConcurrency || 2) : 1;
  globalThis.SPARROW_KOKORO_VOICES = MODELS + 'kokoro/voices/';
  log('engine: threads', env.backends.onnx.wasm.numThreads, 'isolated', !!self.crossOriginIsolated, 'secure', !!self.isSecureContext);
  return lib;
}

async function getKokoro() {
  if (kokoro) return kokoro;
  if (!kokoroLoading) kokoroLoading = (async () => {
    const { KokoroTTS } = await loadLib();
    const t0 = performance.now();
    kokoro = await KokoroTTS.from_pretrained('kokoro', { dtype: 'q8', device: 'wasm' });
    log('Kokoro ready in', Math.round(performance.now() - t0), 'ms');
    return kokoro;
  })().catch(e => { kokoroLoading = null; throw e; });
  return kokoroLoading;
}

async function getMMS(key) {
  if (mms[key]) return mms[key];
  mms[key] = (async () => {
    const { VitsModel, AutoTokenizer } = await loadLib();
    const tok = await AutoTokenizer.from_pretrained(MMS[key]);
    let lastErr;
    for (const dtype of MMS_DTYPES) {
      try {
        const model = await VitsModel.from_pretrained(MMS[key], { dtype, device: 'wasm' });
        const run = async text => {
          const { waveform } = await model(tok(text));
          return { audio: waveform.data, sampling_rate: model.config.sampling_rate };
        };
        await run(PROBE[key] || 'salam');    // make sure this build actually runs here
        log('voice', key, 'ready as', dtype);
        return run;
      } catch (e) { lastErr = e; log('voice', key, dtype, 'failed:', ortMessage(e)); }
    }
    throw lastErr;
  })().catch(e => { delete mms[key]; throw e; });
  return mms[key];
}

/** Loads the English voice in the background so the first reply is quick. */
export async function warmUp() {
  if (!(await available())) return;
  try { await getKokoro(); await speakChunk('kokoro', 'Hi.', { voice: 'af_heart', silent: true }); } catch (e) { log('warm-up failed', e?.message || e); }
}

// ---------- which voice for this text ----------
const ROMAN_URDU = /\b(hai|hain|kya|kia|aap|ap|mein|main|nahi|nahin|karo|kar|ka|ki|ke|ko|se|tha|thi|ho|hum|tum|yeh|ye|woh|wo|acha|accha|theek|jee|ji|shukriya|kal|aaj|baje|minute|abhi|bhi|lekin|aur|ya|sab|kuch|bohat|bahut|mujhe|apka|apki|tera|mera|meri|sanu|tusi|assi|kiven|haan|haanji)\b/gi;
export function pickModel(text, lang) {
  if (/[਀-੿]/.test(text)) return 'pan';                 // Gurmukhi
  if (/[ऀ-ॿ]/.test(text)) return 'hin';                 // Devanagari
  if (/[؀-ۿ]/.test(text)) return 'urd';                 // Urdu / Shahmukhi Punjabi
  if (['ur', 'hi', 'pa'].includes(lang)) {
    const words = text.split(/\s+/).length || 1;
    const hits = (text.match(ROMAN_URDU) || []).length;
    if (hits / words > 0.18) return 'urd-latn';                   // Roman Urdu / Hinglish
  }
  return 'kokoro';
}

// ---------- text → sentences ----------
function sentences(text) {
  const clean = text.replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}•*_#`>]/gu, '').replace(/\s*\n+\s*/g, '. ').replace(/\s+/g, ' ').trim();
  const parts = clean.match(/[^.!?۔।]+[.!?۔।]*\s*/g) || [clean];
  const out = [];
  for (let p of parts) {
    p = p.trim(); if (!p) continue;
    // keep chunks short so the first words come out fast
    while (p.length > 220) { const cut = p.lastIndexOf(',', 200) > 60 ? p.lastIndexOf(',', 200) + 1 : p.lastIndexOf(' ', 200); out.push(p.slice(0, cut).trim()); p = p.slice(cut).trim(); }
    if (out.length && out[out.length - 1].length < 25) out[out.length - 1] += ' ' + p; else out.push(p);
  }
  // Start talking sooner: if the first sentence is long, say its first clause on its own.
  if (out.length && out[0].length > 70) {
    const f = out[0], cut = f.search(/[,;:]\s/);
    if (cut > 12 && cut < 70) out.splice(0, 1, f.slice(0, cut + 1), f.slice(cut + 2));
  }
  return out;
}

// ---------- a small cache: phrases Sparrow says often play instantly ----------
let dbP = null;
function db() {
  if (!dbP) dbP = new Promise(res => {
    try {
      const r = indexedDB.open('sparrow-voice-cache', 1);
      r.onupgradeneeded = () => r.result.createObjectStore('a');
      r.onsuccess = () => res(r.result); r.onerror = () => res(null);
    } catch { res(null); }
  });
  return dbP;
}
async function cacheGet(k) {
  const d = await db(); if (!d) return null;
  return new Promise(res => { try { const q = d.transaction('a').objectStore('a').get(k); q.onsuccess = () => res(q.result || null); q.onerror = () => res(null); } catch { res(null); } });
}
async function cachePut(k, v) {
  const d = await db(); if (!d) return;
  try {
    const st = d.transaction('a', 'readwrite').objectStore('a');
    st.put(v, k);
    const c = st.count(); c.onsuccess = () => { if (c.result > 600) st.clear(); };
  } catch {}
}

// ---------- generation ----------
async function speakChunk(model, text, o) {
  if (model === 'studio' || text.length > 140) return generate(model, text, o);
  const key = `${model}|${o.voice}|${o.speed}|${text}`;
  const hit = await cacheGet(key);
  if (hit) return hit.wav ? { wav: hit.wav } : { pcm: hit.pcm, rate: hit.rate };
  const out = await generate(model, text, o);
  if (out.pcm) cachePut(key, { pcm: out.pcm instanceof Float32Array ? out.pcm : Float32Array.from(out.pcm), rate: out.rate });
  return out;
}
let rtfLogged = 0;
function noteSpeed(model, text, t0, out) {
  const secs = out.pcm ? out.pcm.length / out.rate : 0;
  if (!secs || rtfLogged > 20) return;
  rtfLogged++;
  log('speed', model, `${secs.toFixed(1)}s audio in ${((performance.now() - t0) / 1000).toFixed(1)}s`, `"${text.slice(0, 40)}"`);
}
const COMMON = ['Done.', 'Playing.', 'Paused.', 'Next song.', 'Previous song.', 'Muted.', 'Sound back on.', 'Opening Spotify.', 'Opening Chrome.',
  'Opening Safari.', 'Opening WhatsApp.', 'Opening Gmail in your browser.', 'Opening YouTube in your browser.', 'Opening Notes.', 'Opening Finder.',
  'Opening your Downloads folder.', '📝 Saved in your Notes.', 'Here I am!', 'Yes?', 'Sorry, I didn\'t catch that.', 'Locking the screen.'];
/** After start-up, quietly prepares the phrases Sparrow says most, so they play instantly. */
export async function prepareCommon(voice) {
  if (!(await available())) return;
  for (const p of COMMON) {
    const text = sentences(p)[0]; if (!text) continue;
    const key = `kokoro|${voice}|1|${text}`;
    if (await cacheGet(key)) continue;
    try { await speakChunk('kokoro', text, { voice, speed: 1 }); } catch { return; }
    await new Promise(r => setTimeout(r, 300));
  }
}
async function generate(model, text, o) {
  const t0 = performance.now();
  const out = await generateRaw(model, text, o);
  noteSpeed(model, text, t0, out);
  return out;
}
async function generateRaw(model, text, o) {
  if (model === 'studio') {
    const r = await fetch(STUDIO + '/speak', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ text, lang: o.lang || 'en', speed: o.speed || 1 }) });
    if (!r.ok) throw new Error('studio ' + r.status);
    return { wav: await r.arrayBuffer() };
  }
  if (model === 'kokoro') {
    const tts = await getKokoro();
    const a = await tts.generate(text, { voice: o.voice || 'af_heart', speed: o.speed || 1 });
    return { pcm: a.audio, rate: a.sampling_rate };
  }
  const tts = await getMMS(model);
  const input = model === 'urd-latn' ? text.toLowerCase() : text;
  const a = await tts(input);
  return { pcm: a.audio, rate: a.sampling_rate };
}

let studioOK = 0;        // 0 unknown, time of last good check (ms) or -time of last failure
async function studioReady() {
  const now = Date.now();
  if (studioOK > 0 && now - studioOK < 60e3) return true;
  if (studioOK < 0 && now + studioOK < 30e3) return false;
  try {
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 800);
    const j = await (await fetch(STUDIO + '/health', { signal: ctl.signal })).json(); clearTimeout(t);
    studioOK = j.ready ? now : -now; return !!j.ready;
  } catch { studioOK = -now; return false; }
}

function audioCtx() {
  if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
  if (ctx.state === 'suspended') ctx.resume().catch(() => {});
  return ctx;
}
async function toBuffer(chunk) {
  const ac = audioCtx();
  if (chunk.wav) return ac.decodeAudioData(chunk.wav.slice(0));
  const b = ac.createBuffer(1, chunk.pcm.length, chunk.rate);
  b.copyToChannel(chunk.pcm instanceof Float32Array ? chunk.pcm : Float32Array.from(chunk.pcm), 0);
  return b;
}
function play(buf, myTurn) {
  return new Promise(res => {
    if (myTurn !== turn) return res();
    const ac = audioCtx(), src = ac.createBufferSource(), g = ac.createGain();
    g.gain.value = 0.98;
    src.buffer = buf; src.connect(g).connect(ac.destination);
    src.onended = () => { if (current === src) current = null; res(); };
    current = src; src.start();
  });
}

/**
 * Speaks text with the most natural voice available. Resolves true as soon as audio starts
 * (false if no neural voice could do it — the caller then uses the system voice).
 * opts: { lang, gender, voice, speed, studio, onstart, onend }
 */
export async function say(text, opts = {}) {
  stop();
  const myTurn = ++turn;
  const parts = sentences(String(text || ''));
  if (!parts.length) return false;
  const lang = opts.lang || 'en';
  let model = (opts.studio && await studioReady()) ? 'studio' : pickModel(parts.join(' '), lang);
  if (model !== 'studio' && !(await available())) return false;
  const voice = opts.voice || (opts.gender === 'male' ? 'bm_george' : 'af_heart');
  const o = { voice, speed: opts.speed || 1, lang, silent: false };

  let started = false;
  return new Promise(resolve => {
    (async () => {
      try {
        // Generate the next sentence while the current one plays.
        let next = speakChunk(model, parts[0], o).catch(async e => {
          if (model !== 'studio') throw e;
          log('studio failed, using built-in voice', e?.message); model = pickModel(parts.join(' '), lang); return speakChunk(model, parts[0], o);
        });
        for (let i = 0; i < parts.length; i++) {
          const chunk = await next;
          if (myTurn !== turn) break;
          if (i + 1 < parts.length) next = speakChunk(model, parts[i + 1], o).catch(() => null);
          if (!chunk) continue;
          const buf = await toBuffer(chunk);
          if (!started) { started = true; opts.onstart?.(); resolve(true); }
          await play(buf, myTurn);
          if (myTurn !== turn) break;
        }
      } catch (e) {
        log('voice error', model, e?.message || e);
        if (!started) { resolve(false); return; }
      }
      if (started && myTurn === turn) opts.onend?.();
      if (!started) resolve(false);
    })();
  });
}

export function stop() {
  turn++;
  try { current?.stop(); } catch {}
  current = null;
}

export async function studioStatus() { return studioReady(); }

/** Renders text to one WAV file (used by tests and "save as audio"). */
export async function renderWav(text, opts = {}) {
  const parts = sentences(String(text || ''));
  const lang = opts.lang || 'en';
  const model = opts.model || pickModel(parts.join(' '), lang);
  const o = { voice: opts.voice || 'af_heart', speed: opts.speed || 1, lang };
  const chunks = []; let rate = 24000;
  for (const p of parts) { const c = await speakChunk(model, p, o); chunks.push(c.pcm); rate = c.rate; }
  const gap = new Float32Array(Math.round(rate * 0.18));
  const total = chunks.reduce((n, c) => n + c.length + gap.length, 0);
  const pcm = new Float32Array(total); let off = 0;
  for (const c of chunks) { pcm.set(c, off); off += c.length + gap.length; }
  const dv = new DataView(new ArrayBuffer(44 + pcm.length * 2));
  const w = (o2, s) => [...s].forEach((ch, i) => dv.setUint8(o2 + i, ch.charCodeAt(0)));
  w(0, 'RIFF'); dv.setUint32(4, 36 + pcm.length * 2, true); w(8, 'WAVE'); w(12, 'fmt ');
  dv.setUint32(16, 16, true); dv.setUint16(20, 1, true); dv.setUint16(22, 1, true); dv.setUint32(24, rate, true);
  dv.setUint32(28, rate * 2, true); dv.setUint16(32, 2, true); dv.setUint16(34, 16, true); w(36, 'data'); dv.setUint32(40, pcm.length * 2, true);
  for (let i = 0; i < pcm.length; i++) dv.setInt16(44 + i * 2, Math.max(-1, Math.min(1, pcm[i])) * 0x7fff, true);
  return { wav: new Uint8Array(dv.buffer), model, seconds: pcm.length / rate };
}
