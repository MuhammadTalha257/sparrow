// Zuffi's own voices on Windows — used by the notch window (desktop.js) and the big window (app.js).
import { store } from './store.js';
const D = window.SparrowDesktop || {};
const S = () => store.settings;
const send = e => window.sparrowEvent && window.sparrowEvent(e);

// ---------- Her own voice on Windows: Her 4 · Her 2 · His 1 (the same voices as the Mac) ----------
// The main process makes each sentence (sherpa-onnx, offline); we play them one after another,
// making the next while the current one plays, so she starts talking quickly and never stops mid-answer.
export const Her = {
  ok: null, ctx: null, src: null, turn: 0, playing: false,
  available() { if (this.ok === null) { try { this.ok = !!D.her?.available?.(); } catch { this.ok = false; } } return this.ok; },
  use() {
    const v = S().voiceName || '';
    return this.available() && v !== 'system' && !/^[a-z]{2}_/.test(v) && (!S().lang || S().lang === 'en') ;
  },
  sid() { const v = S().voiceName || ''; return v.startsWith('her:') ? Number(v.slice(4)) || 3 : 3; },
  split(t) {
    const parts = String(t).replace(/\s+/g, ' ').match(/[^.!?]+[.!?]+["')\]]*\s*|[^.!?]+$/g) || [t];
    const out = [];
    for (const p of parts.map(x => x.trim()).filter(Boolean)) { if (out.length && (out[out.length - 1].length < 40 || p.length < 12)) out[out.length - 1] += ' ' + p; else out.push(p); }
    return out.slice(0, 40);
  },
  async say(text) {
    const turn = ++this.turn; this.stopSound();
    const parts = this.split(text); if (!parts.length) return;
    const speed = S().simple ? 0.95 : 1.05, sid = this.sid();
    const make = p => D.her.say({ text: p, sid, speed, lang: 'en' }).catch(() => null);
    let next = make(parts[0]);
    this.playing = true; send({ type: 'speaking', on: true });
    try {
      for (let i = 0; i < parts.length; i++) {
        const got = await next;
        if (turn !== this.turn) return;
        next = i + 1 < parts.length ? make(parts[i + 1]) : null;
        if (!got?.samples?.length) { if (i === 0) { this.playing = false; send({ type: 'speaking', on: false }); return this.fallback(text); } continue; }
        await this.play(got, turn);
        if (turn !== this.turn) return;
      }
    } finally { if (turn === this.turn) { this.playing = false; send({ type: 'speaking', on: false }); } }
  },
  play({ rate, samples }, turn) {
    return new Promise(res => {
      try {
        this.ctx ||= new AudioContext();
        if (this.ctx.state === 'suspended') this.ctx.resume();
        const f = samples instanceof Float32Array ? samples : new Float32Array(samples);
        const buf = this.ctx.createBuffer(1, f.length, rate || 44100); buf.copyToChannel(f, 0);
        const src = this.ctx.createBufferSource(); src.buffer = buf; src.connect(this.ctx.destination);
        src.onended = () => { if (this.src === src) this.src = null; res(); };
        this.src = src; if (turn !== this.turn) return res(); src.start();
      } catch { res(); }
    });
  },
  stopSound() { try { this.src?.stop(); } catch {} this.src = null; },
  stop() { this.turn++; this.stopSound(); if (this.playing) { this.playing = false; send({ type: 'speaking', on: false }); } },
  fallback(text) { try { const u = new SpeechSynthesisUtterance(text); u.rate = 1; speechSynthesis.speak(u); } catch {} },
};
// stopping speech anywhere in Zuffi (a new question, Stop, Esc) also stops her voice;
// and while she talks, the microphone knows not to listen to her
try {
  const ss = window.speechSynthesis;
  if (ss) {
    const cancel = ss.cancel.bind(ss);
    ss.cancel = () => { Her.stop(); cancel(); };
    const proto = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(ss), 'speaking');
    Object.defineProperty(ss, 'speaking', { configurable: true, get: () => Her.playing || !!proto?.get?.call(ss) });
  }
} catch {}
if (Her.available()) setTimeout(() => D.her.warm?.(), 4000);     // load her voice in the background, ready for the first answer
