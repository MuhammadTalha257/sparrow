// Posts & reels for a business: a designed post (square), a Status / Story (9:16) or a short reel made from your
// photos — with your business name, the headline, price and a WhatsApp call-to-action. Everything is drawn on this
// device (canvas + MediaRecorder). The AI only writes the caption and hashtags. No photos? Zuffi can make a
// background picture with your picture AI, or use a clean branded design.
import { ask } from './ai.js';
import { outputType } from './reels.js';

export const KINDS = {
  estate: [
    ['listing', 'New listing', 'A property for sale'], ['rent', 'For rent', 'A house, flat or shop to let'],
    ['visit', 'Site visit / open house', 'Invite buyers to come and see'], ['price', 'Price drop', 'Now cheaper — act fast'],
    ['sold', 'Sold!', 'Show buyers you close deals'], ['project', 'New project / society', 'Plots and installments'],
  ],
  local: [
    ['offer', 'Special offer', 'A discount or deal'], ['slots', 'Free slots today', 'Fill empty appointments'],
    ['new', 'New service / product', 'Something new to try'], ['review', 'Happy customer', 'A review or before & after'],
    ['hours', 'Opening hours / holiday', 'Changes to your times'], ['event', 'Event / launch', 'Come along'],
  ],
};
export const SHAPES = { post: { w: 1080, h: 1080, label: 'Post 1:1' }, story: { w: 1080, h: 1920, label: 'Status / Story 9:16' }, reel: { w: 1080, h: 1920, label: 'Reel (video)' } };
const TAG = { listing: 'FOR SALE', rent: 'TO LET', visit: 'SITE VISIT', price: 'PRICE DROP', sold: 'SOLD', project: 'NEW PROJECT', offer: 'OFFER', slots: 'TODAY', new: 'NEW', review: 'HAPPY CUSTOMER', hours: 'OPENING HOURS', event: 'EVENT' };

export function loadImages(files) {
  return Promise.all([...files].filter(f => /^image\//.test(f.type)).slice(0, 8).map(f => new Promise(res => {
    const im = new Image(); im.onload = () => res(im); im.onerror = () => res(null); im.src = URL.createObjectURL(f);
  }))).then(a => a.filter(Boolean));
}
export function imageFromBytes(bytes, type = 'image/png') {
  return new Promise(res => { const im = new Image(); im.onload = () => res(im); im.onerror = () => res(null); im.src = URL.createObjectURL(new Blob([bytes], { type })); });
}

function cover(g, im, W, H, zoom = 1, dx = 0, dy = 0) {
  const r = Math.max(W / im.width, H / im.height) * zoom, w = im.width * r, h = im.height * r;
  g.drawImage(im, (W - w) / 2 + dx * W, (H - h) / 2 + dy * H, w, h);
}
function wrap(g, text, maxW, maxLines = 3) {
  const words = String(text || '').split(/\s+/).filter(Boolean), lines = []; let line = '';
  for (const w of words) { const t = line ? line + ' ' + w : w; if (g.measureText(t).width > maxW && line) { lines.push(line); line = w; } else line = t; }
  if (line) lines.push(line); return lines.slice(0, maxLines);
}
function rr(g, x, y, w, h, r) { g.beginPath(); g.roundRect ? g.roundRect(x, y, w, h, r) : g.rect(x, y, w, h); }
const RTL = s => /[؀-ۿ]/.test(s || '');
const FONT = (wt, px, s) => `${wt} ${px}px ${RTL(s) ? '"Noto Nastaliq Urdu", "Noto Naskh Arabic", ' : ''}Inter, "Segoe UI", system-ui, sans-serif`;

/**
 * Draws one frame. spec: { kind, headline, price, details[], phone, biz, accent, photo (Image|null), t (0..1 for reels), tag }
 */
export function draw(g, W, H, spec, photo, anim = null) {
  const accent = spec.accent || '#C9A24A', s = W / 1080, tall = H > W;
  // background: the photo, or a calm branded gradient
  g.fillStyle = '#0E1116'; g.fillRect(0, 0, W, H);
  if (photo) { const z = anim ? 1.04 + anim.p * 0.08 : 1.02; cover(g, photo, W, H, z, anim ? (anim.dir * (anim.p - .5) * 0.03) : 0, 0); }
  else {
    const gr = g.createLinearGradient(0, 0, W, H); gr.addColorStop(0, '#0F1A2B'); gr.addColorStop(1, '#141018'); g.fillStyle = gr; g.fillRect(0, 0, W, H);
    g.globalAlpha = .18; g.fillStyle = accent; g.beginPath(); g.arc(W * .85, H * .2, W * .45, 0, Math.PI * 2); g.fill(); g.globalAlpha = 1;
  }
  // readable shade at the bottom
  const sh = g.createLinearGradient(0, H * (tall ? .38 : .28), 0, H); sh.addColorStop(0, 'rgba(8,10,14,0)'); sh.addColorStop(1, 'rgba(8,10,14,.92)');
  g.fillStyle = sh; g.fillRect(0, 0, W, H);
  const top = g.createLinearGradient(0, 0, 0, H * .2); top.addColorStop(0, 'rgba(8,10,14,.55)'); top.addColorStop(1, 'rgba(8,10,14,0)'); g.fillStyle = top; g.fillRect(0, 0, W, H * .2);
  const pad = 64 * s;
  // business name, top left
  g.textBaseline = 'middle'; g.textAlign = 'left'; g.fillStyle = '#fff'; g.font = FONT(700, 34 * s, spec.biz);
  const bn = String(spec.biz || '').slice(0, 34);
  if (bn) { g.fillStyle = accent; rr(g, pad, pad, 10 * s, 44 * s, 5 * s); g.fill(); g.fillStyle = '#fff'; g.fillText(bn, pad + 26 * s, pad + 22 * s); }
  // tag pill, top right
  const tag = spec.tag || TAG[spec.kind] || '';
  if (tag) { g.font = FONT(800, 28 * s); const tw = g.measureText(tag).width + 44 * s; g.fillStyle = accent; rr(g, W - pad - tw, pad, tw, 54 * s, 27 * s); g.fill(); g.fillStyle = '#111'; g.textAlign = 'center'; g.fillText(tag, W - pad - tw / 2, pad + 28 * s); }
  // headline + details from the bottom up
  const a = anim ? Math.min(1, anim.p * 3) : 1, rise = anim ? (1 - a) * 30 * s : 0;
  g.globalAlpha = a; g.textAlign = RTL(spec.headline) ? 'right' : 'left';
  const x = g.textAlign === 'right' ? W - pad : pad;
  let y = H - pad;
  // call to action bar
  if (spec.phone) {
    g.font = FONT(700, 34 * s); const cta = `WhatsApp ${spec.phone}`; const cw = g.measureText(cta).width + 84 * s;
    g.fillStyle = '#25D366'; rr(g, pad, y - 74 * s, cw, 74 * s, 37 * s); g.fill();
    g.fillStyle = '#fff'; g.textAlign = 'left'; g.fillText(cta, pad + 60 * s, y - 37 * s);
    g.beginPath(); g.arc(pad + 33 * s, y - 37 * s, 12 * s, 0, Math.PI * 2); g.fill();
    y -= 110 * s; g.textAlign = RTL(spec.headline) ? 'right' : 'left';
  }
  // detail chips
  const det = (spec.details || []).filter(Boolean).slice(0, 4);
  if (det.length) {
    g.font = FONT(600, 30 * s); let cx = pad, rowY = y - 58 * s;
    g.textAlign = 'left';
    for (const d of det) { const w = g.measureText(d).width + 40 * s; if (cx + w > W - pad) break; g.fillStyle = 'rgba(255,255,255,.16)'; rr(g, cx, rowY, w, 54 * s, 14 * s); g.fill(); g.fillStyle = '#fff'; g.fillText(d, cx + 20 * s, rowY + 28 * s); cx += w + 12 * s; }
    y -= 84 * s; g.textAlign = RTL(spec.headline) ? 'right' : 'left';
  }
  // price
  if (spec.price) { g.font = FONT(800, (tall ? 76 : 66) * s, spec.price); g.fillStyle = accent; g.fillText(spec.price, x, y - 40 * s + rise); y -= (tall ? 104 : 92) * s; }
  // headline
  g.font = FONT(800, (tall ? 84 : 72) * s, spec.headline); g.fillStyle = '#fff';
  const lines = wrap(g, spec.headline, W - pad * 2, 3), lh = (tall ? 96 : 82) * s;
  lines.reverse().forEach((l, i) => g.fillText(l, x, y - 44 * s - i * lh + rise));
  g.globalAlpha = 1;
}

/** A still post or Status → PNG blob. */
export async function renderImage(spec, shape, photos) {
  const S = SHAPES[shape] || SHAPES.post, cv = document.createElement('canvas'); cv.width = S.w; cv.height = S.h;
  draw(cv.getContext('2d'), S.w, S.h, spec, photos[0] || null);
  return new Promise(r => cv.toBlob(r, 'image/png'));
}

/** A reel: each photo ~2.6 s with a slow zoom, the text rising in, an end card with the WhatsApp number. → video blob */
export async function renderReel(spec, photos, onProgress) {
  const W = 1080, H = 1920, cv = document.createElement('canvas'); cv.width = W; cv.height = H; const g = cv.getContext('2d');
  const pics = photos.length ? photos : [null], per = 2.6, endCard = 2.2, total = pics.length * per + endCard;
  const stream = cv.captureStream(30), type = outputType(), chunks = [];
  const rec = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 6_000_000 });
  rec.ondataavailable = e => e.data.size && chunks.push(e.data);
  return new Promise(resolve => {
    rec.onstop = () => resolve(new Blob(chunks, { type: type.split(';')[0] }));
    rec.start(500);
    const t0 = performance.now();
    const tick = () => {
      const t = (performance.now() - t0) / 1000;
      if (t >= total) { rec.stop(); return; }
      onProgress?.(t / total);
      if (t < pics.length * per) {
        const i = Math.floor(t / per), p = (t - i * per) / per;
        draw(g, W, H, { ...spec, phone: '' }, pics[i], { p, dir: i % 2 ? -1 : 1 });
        if (p < .12 && i > 0) { g.globalAlpha = 1 - p / .12; draw(g, W, H, { ...spec, phone: '' }, pics[i - 1], { p: 1, dir: (i - 1) % 2 ? -1 : 1 }); g.globalAlpha = 1; }
      } else {
        const p = (t - pics.length * per) / endCard;
        draw(g, W, H, { ...spec, details: [], headline: spec.cta || 'Message us on WhatsApp', price: '', tag: '' }, pics[pics.length - 1], { p, dir: 1 });
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
  });
}

/** Caption + hashtags for Instagram / Facebook / WhatsApp Status, in the chosen language. */
export async function caption(spec, lang = 'auto', facts = '') {
  const system = `You write short social media captions for a small business. Warm, clear, no exaggeration, no invented facts. 2-4 short lines, then a call to action to message on WhatsApp${spec.phone ? ' (' + spec.phone + ')' : ''}, then 5-8 relevant hashtags (local area if known). ${lang === 'auto' ? 'Write in the language of the headline.' : 'Write in ' + lang + '.'} Plain text, emojis allowed sparingly.`;
  const r = await ask(`Business: ${spec.biz || ''}\nPost type: ${spec.kind}\nHeadline: ${spec.headline}\nPrice: ${spec.price || '-'}\nDetails: ${(spec.details || []).join(', ')}\n${facts ? 'Business facts:\n' + facts.slice(0, 2500) : ''}`, null, { noHistory: true, system, maxTokens: 400 });
  return String(r.text || '').trim();
}
