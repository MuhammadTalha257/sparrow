// Quick reels: trim a video, crop it for Reels / TikTok / WhatsApp Status, burn in a title, captions and your name.
// Rendered on this device in real time (canvas + MediaRecorder), saved as MP4 where the device supports it.
export const SHAPES = { vertical: { label: 'Vertical 9:16 (Reels, TikTok, Status)', w: 1080, h: 1920 }, square: { label: 'Square 1:1', w: 1080, h: 1080 }, wide: { label: 'Wide 16:9 (YouTube)', w: 1920, h: 1080 } };

export function loadVideo(file) {
  return new Promise((res, rej) => {
    const v = document.createElement('video'); v.preload = 'auto'; v.playsInline = true; v.src = URL.createObjectURL(file);
    v.onloadedmetadata = () => res(v); v.onerror = () => rej(new Error('This video can’t be opened here'));
  });
}
export function outputType() {
  const c = ['video/mp4;codecs=avc1.42E01E,mp4a.40.2', 'video/mp4', 'video/webm;codecs=vp9,opus', 'video/webm'];
  return c.find(t => window.MediaRecorder?.isTypeSupported?.(t)) || 'video/webm';
}
function wrap(g, text, maxW) {
  const words = String(text).split(/\s+/), lines = []; let line = '';
  for (const w of words) { const t = line ? line + ' ' + w : w; if (g.measureText(t).width > maxW && line) { lines.push(line); line = w; } else line = t; }
  if (line) lines.push(line); return lines.slice(0, 3);
}
/** Spread typed lines evenly over the clip when there's no timed transcript. */
export function evenCaptions(lines, len) {
  const L = lines.map(s => s.trim()).filter(Boolean); if (!L.length) return [];
  const d = len / L.length; return L.map((text, i) => ({ s: i * d, e: (i + 1) * d, text }));
}

/** opts: { start, len, shape, title, mark, captions:[{s,e,text}] (seconds from the clip start), onProgress(0..1) } → Blob */
export async function render(video, opts) {
  const S = SHAPES[opts.shape] || SHAPES.vertical, W = S.w, H = S.h;
  const start = Math.max(0, Math.min(opts.start || 0, Math.max(0, video.duration - 1)));
  const len = Math.min(opts.len || 30, video.duration - start);
  const cv = document.createElement('canvas'); cv.width = W; cv.height = H; const g = cv.getContext('2d');
  // sound: route the video's audio into the recording (not to the speakers)
  const AC = window.AudioContext || window.webkitAudioContext; const ac = new AC();
  const src = ac.createMediaElementSource(video), dest = ac.createMediaStreamDestination(); src.connect(dest);
  const stream = cv.captureStream(30); dest.stream.getAudioTracks().forEach(t => stream.addTrack(t));
  const type = outputType(), chunks = [];
  const rec = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 6_000_000, audioBitsPerSecond: 128_000 });
  rec.ondataavailable = e => e.data.size && chunks.push(e.data);
  const draw = () => {
    const t = video.currentTime - start;
    const vw = video.videoWidth, vh = video.videoHeight, r = W / H;
    let sx = 0, sy = 0, sw = vw, sh = vh; if (vw / vh > r) { sw = vh * r; sx = (vw - sw) / 2; } else { sh = vw / r; sy = (vh - sh) / 2; }
    g.fillStyle = '#000'; g.fillRect(0, 0, W, H); g.drawImage(video, sx, sy, sw, sh, 0, 0, W, H);
    const base = Math.round(Math.min(W, H) * 0.056);
    if (opts.title && t < 3.2) {   // title card for the first 3 seconds
      g.font = `800 ${Math.round(base * 1.25)}px Inter, system-ui, sans-serif`; g.textAlign = 'center'; g.textBaseline = 'top';
      const lines = wrap(g, opts.title, W * 0.84), lh = base * 1.5, y0 = H * 0.09, a = Math.min(1, t * 4, (3.2 - t) * 4);
      g.globalAlpha = Math.max(0, a); g.fillStyle = 'rgba(0,0,0,.42)';
      g.beginPath(); g.roundRect?.(W * 0.06, y0 - base * 0.5, W * 0.88, lines.length * lh + base, base * 0.6); g.fill();
      g.fillStyle = '#fff'; lines.forEach((l, i) => g.fillText(l, W / 2, y0 + i * lh)); g.globalAlpha = 1;
    }
    const cap = (opts.captions || []).find(c => t >= c.s && t < c.e);
    if (cap) {   // captions: big, bold, bottom third — readable with the sound off
      g.font = `800 ${base}px Inter, system-ui, sans-serif`; g.textAlign = 'center'; g.textBaseline = 'middle';
      const lines = wrap(g, cap.text, W * 0.84), lh = base * 1.3, y0 = H * (S.h > S.w ? 0.72 : 0.80) - (lines.length - 1) * lh / 2;
      g.lineJoin = 'round'; g.lineWidth = base * 0.22; g.strokeStyle = 'rgba(0,0,0,.85)'; g.fillStyle = '#fff';
      lines.forEach((l, i) => { g.strokeText(l, W / 2, y0 + i * lh); g.fillText(l, W / 2, y0 + i * lh); });
    }
    if (opts.mark) { g.font = `600 ${Math.round(base * 0.55)}px Inter, system-ui, sans-serif`; g.textAlign = 'right'; g.textBaseline = 'bottom'; g.fillStyle = 'rgba(255,255,255,.85)'; g.shadowColor = 'rgba(0,0,0,.5)'; g.shadowBlur = 8; g.fillText(opts.mark, W - base * 0.7, H - base * 0.7); g.shadowBlur = 0; }
    opts.onProgress?.(Math.max(0, Math.min(1, t / len)));
  };
  await new Promise(r => { video.currentTime = start; video.onseeked = r; });
  draw();
  return new Promise((resolve, reject) => {
    let done = false, timer = null;
    const finish = () => { if (done) return; done = true; clearInterval(timer); video.pause(); try { rec.stop(); } catch {} };
    rec.onstop = () => { ac.close?.(); resolve(new Blob(chunks, { type: type.split(';')[0] })); };
    rec.onerror = e => reject(e.error || new Error('Recording failed'));
    rec.start(1000);
    video.muted = false; video.volume = 1;
    video.play().catch(reject);
    const tick = () => { if (done) return; draw(); if (video.currentTime >= start + len || video.ended) finish(); };
    if (video.requestVideoFrameCallback) { const f = () => { tick(); if (!done) video.requestVideoFrameCallback(f); }; video.requestVideoFrameCallback(f); }
    timer = setInterval(tick, 1000 / 30);    // also keeps going when frames stall
    video.onended = finish;
  });
}
