// Renders the 30-second Sparrow launch film: animation (video.html) + Kokoro voiceover + a soft original score.
// node render.mjs [outDir]   (needs ffmpeg, Playwright Chromium, internet for the Kokoro model the first time)
import { chromium } from 'playwright';
import { spawn, execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.resolve(process.argv[2] || path.join(here, 'out'));
fs.mkdirSync(out, { recursive: true });
const FPS = 30, DUR = 30, W = 1920, H = 1080, SR = 44100;

// ---------------------------------------------------------------- 1. voiceover
const LINES = [
  { at: 0.45, end: 3.95, text: 'Meet Sparrow, the little helper at the top of your Mac.' },
  { at: 4.30, end: 9.85, text: 'Just say: Sparrow, open Spotify and play some music... and it is already playing.' },
  { at: 10.30, end: 15.35, text: 'Talk the way you talk. English, Urdu, or Hindi, it plans your day.' },
  { at: 15.80, end: 20.35, text: 'It takes your meeting notes, and keeps prayers and water on time.' },
  { at: 20.80, end: 25.35, text: 'It even runs your Mac, from Wi-Fi to shut down. Always safely.' },
  { at: 26.20, end: 29.75, text: 'Sparrow. Private, fast, and free, at lisansystems dot com.' },
];
const VOICE = process.env.SPARROW_VOICE || 'af_heart';
const vo = new Float32Array(SR * DUR);
const speech = [];
const SKIP_VOICE = process.env.SKIP_VOICE === '1';     // for quick picture checks without the voice model
let tts = null;
if (!SKIP_VOICE) {
  console.log('Loading Kokoro…');
  const { KokoroTTS } = await import('kokoro-js');
  tts = await KokoroTTS.from_pretrained('onnx-community/Kokoro-82M-v1.0-ONNX', { dtype: 'fp32', device: 'cpu' });
}
for (const [i, l] of LINES.entries()) {
  if (!tts) { speech.push([l.at, l.end - .3]); continue; }
  const a = await tts.generate(l.text, { voice: VOICE, speed: 1.0 });
  let pcm = a.audio, rate = a.sampling_rate;
  // trim silence at both ends
  let s0 = 0, s1 = pcm.length - 1;
  while (s0 < pcm.length && Math.abs(pcm[s0]) < 0.01) s0++;
  while (s1 > s0 && Math.abs(pcm[s1]) < 0.01) s1--;
  pcm = pcm.subarray(Math.max(0, s0 - 200), Math.min(pcm.length, s1 + 1200));
  let secs = pcm.length / rate;
  const slot = l.end - l.at;
  // speed up slightly only if a line would overrun its scene
  const tempo = secs > slot ? Math.min(1.22, secs / slot) : 1;
  const step = (rate / SR) * tempo;               // resample to 44.1k (and tempo) by linear interpolation
  const n = Math.floor(pcm.length / step);
  const start = Math.round(l.at * SR);
  for (let k = 0; k < n && start + k < vo.length; k++) {
    const x = k * step, j = Math.floor(x), f = x - j;
    vo[start + k] += (pcm[j] * (1 - f) + (pcm[j + 1] ?? 0) * f) * 0.95;
  }
  speech.push([l.at, l.at + n / SR]);
  console.log(`line ${i + 1}: ${secs.toFixed(2)}s → slot ${slot.toFixed(2)}s ${tempo > 1 ? `(×${tempo.toFixed(2)})` : ''}`);
}

// ---------------------------------------------------------------- 2. score + sound effects (original, synthesised)
const L = new Float32Array(SR * DUR), R = new Float32Array(SR * DUR);
const hz = m => 440 * Math.pow(2, (m - 69) / 12);
const CHORDS = [[53, 57, 60, 64, 67], [57, 60, 64, 67, 71], [50, 53, 57, 60, 64], [46, 50, 53, 57, 62]]; // Fmaj9 · Am7 · Dm9 · B♭maj9
const BAR = 3.75;
// pad
for (let i = 0; i < L.length; i++) {
  const t = i / SR, bar = Math.floor(t / BAR), ch = CHORDS[bar % 4], u = (t % BAR) / BAR;
  const env = Math.min(1, u * 5) * Math.min(1, (1 - u) * 6 + .35);
  let s = 0;
  for (const [k, m] of ch.entries()) {
    const f = hz(m);
    s += Math.sin(2 * Math.PI * f * t + k) * .5 + Math.sin(2 * Math.PI * f * 1.003 * t) * .35 + Math.sin(2 * Math.PI * f * 2 * t) * .06;
  }
  const lfo = .85 + .15 * Math.sin(2 * Math.PI * .23 * t);
  const v = s * env * lfo * .018 * Math.min(1, t / 1.2) * Math.min(1, (DUR - t) / 1.5);
  L[i] += v * (1 + .1 * Math.sin(t)); R[i] += v * (1 - .1 * Math.sin(t));
}
// soft plucked arpeggio (from the second scene)
const STEP = 60 / 96 / 2;
for (let n = Math.floor(3.75 / STEP); n * STEP < DUR - 1; n++) {
  const t0 = n * STEP, bar = Math.floor(t0 / BAR), ch = CHORDS[bar % 4];
  const m = ch[[0, 2, 4, 3, 1, 3, 2, 4][n % 8]] + 12;
  const f = hz(m), i0 = Math.round(t0 * SR), pan = (n % 2 ? .35 : -.35);
  for (let k = 0; k < SR * .7 && i0 + k < L.length; k++) {
    const tt = k / SR, e = Math.exp(-tt * 7) * Math.min(1, tt * 400);
    const v = (Math.sin(2 * Math.PI * f * tt) + .3 * Math.sin(2 * Math.PI * f * 2 * tt)) * e * .028;
    L[i0 + k] += v * (1 - pan); R[i0 + k] += v * (1 + pan);
  }
}
// gentle low pulse on the downbeats
for (let b = 1; b * BAR < DUR - 2; b++) for (const off of [0, BAR / 2]) {
  const i0 = Math.round((b * BAR + off) * SR);
  for (let k = 0; k < SR * .35 && i0 + k < L.length; k++) {
    const tt = k / SR, f = 55 + 40 * Math.exp(-tt * 30), v = Math.sin(2 * Math.PI * f * tt) * Math.exp(-tt * 9) * .09;
    L[i0 + k] += v; R[i0 + k] += v;
  }
}
// whooshes at scene changes, pops when cards land, a chime at the end
let seed = 7; const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647) * 2 - 1;
function whoosh(at, len = .55, gain = .05) {
  let lp = 0; const i0 = Math.round(at * SR);
  for (let k = 0; k < SR * len; k++) {
    const u = k / (SR * len), a = .02 + .25 * Math.sin(Math.PI * u);
    lp += (rnd() - lp) * a;
    const v = lp * Math.sin(Math.PI * u) * gain;
    if (i0 + k < L.length) { L[i0 + k] += v * (1 - u); R[i0 + k] += v * u; }
  }
}
function pop(at, f = 880, gain = .06) {
  const i0 = Math.round(at * SR);
  for (let k = 0; k < SR * .12 && i0 + k < L.length; k++) {
    const tt = k / SR, v = Math.sin(2 * Math.PI * (f + 500 * Math.exp(-tt * 40)) * tt) * Math.exp(-tt * 35) * gain;
    L[i0 + k] += v; R[i0 + k] += v;
  }
}
function chime(at) { [72, 76, 79, 84].forEach((m, j) => pop(at + j * .09, hz(m), .05)); }
[3.8, 9.8, 15.3, 20.3, 25.3].forEach(t => whoosh(t));
whoosh(0.15, 1.6, .04);                                  // the sparrow flying in
[2.0, 8.0, 12.5, 13.0, 16.4, 16.65, 16.9, 21.4, 21.7, 22.0, 24.2].forEach((t, i) => pop(t, 700 + (i % 3) * 180));
chime(26.6);

// duck the music under the voice, then mix
const duck = new Float32Array(L.length).fill(1);
for (const [a, b] of speech) for (let i = Math.round((a - .15) * SR); i < Math.min(L.length, Math.round((b + .25) * SR)); i++) if (i >= 0) duck[i] = .45;
let d = 1; for (let i = 0; i < L.length; i++) { d += (duck[i] - d) * .0006; L[i] = L[i] * d + vo[i]; R[i] = R[i] * d + vo[i]; }
let peak = 0; for (let i = 0; i < L.length; i++) peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
const norm = .89 / peak;
const wav = Buffer.alloc(44 + L.length * 4);
wav.write('RIFF', 0); wav.writeUInt32LE(36 + L.length * 4, 4); wav.write('WAVEfmt ', 8); wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(2, 22);
wav.writeUInt32LE(SR, 24); wav.writeUInt32LE(SR * 4, 28); wav.writeUInt16LE(4, 32); wav.writeUInt16LE(16, 34); wav.write('data', 36); wav.writeUInt32LE(L.length * 4, 40);
for (let i = 0; i < L.length; i++) { wav.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[i] * norm)) * 32767), 44 + i * 4); wav.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[i] * norm)) * 32767), 46 + i * 4); }
const audioPath = path.join(out, 'soundtrack.wav');
fs.writeFileSync(audioPath, wav);
console.log('soundtrack ready');

// ---------------------------------------------------------------- 3. pictures (frame-exact) → video
const videoOnly = path.join(out, 'video-only.mp4');
const ff = spawn('ffmpeg', ['-y', '-v', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'mjpeg', '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', videoOnly], { stdio: ['pipe', 'inherit', 'inherit'] });
const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const page = await browser.newPage({ viewport: { width: W, height: H } });
await page.goto('file://' + path.join(here, 'video.html') + '?capture=1');
await page.waitForFunction('window.READY === true');
const total = FPS * DUR;
for (let f = 0; f < total; f++) {
  await page.evaluate(t => window.renderAt(t), f / FPS);
  const buf = await page.screenshot({ type: 'jpeg', quality: 95 });
  if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
  if (f % 90 === 0) console.log(`frame ${f}/${total}`);
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
// poster: the logo moment
await page.evaluate(t => window.renderAt(t), 28.2);
await page.screenshot({ path: path.join(out, 'sparrow-poster.jpg'), type: 'jpeg', quality: 92 });
await browser.close();

// ---------------------------------------------------------------- 4. final film
const final = path.join(out, 'sparrow-30s.mp4');
execFileSync('ffmpeg', ['-y', '-v', 'error', '-i', videoOnly, '-i', audioPath, '-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', final]);
fs.unlinkSync(videoOnly);
console.log('done:', fs.readdirSync(out).join(', '));
