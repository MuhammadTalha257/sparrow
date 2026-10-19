// Photo studio, file converter and PDF signing — all on this device, offline (canvas + pdf-lib).
let PDFLib = null;
async function lib() { if (!PDFLib) PDFLib = await import('./lib/pdf-lib.min.js'); return PDFLib; }

const base = n => n.replace(/\.[^.]+$/, '');
const toBlob = (c, type, q) => new Promise(r => c.toBlob(r, type, q));
async function bitmap(file) {
  try { return await createImageBitmap(file, { imageOrientation: 'from-image' }); }
  catch { const url = URL.createObjectURL(file); const img = new Image(); img.src = url; await img.decode(); URL.revokeObjectURL(url); return img; }
}

// ---------------- photo studio ----------------
export const SIZES = {
  original: { label: 'Original size' },
  square: { label: 'Instagram square', w: 1080, h: 1080 },
  portrait: { label: 'Instagram portrait', w: 1080, h: 1350 },
  story: { label: 'Story / WhatsApp Status', w: 1080, h: 1920 },
  wide: { label: 'Wide (website, YouTube)', w: 1920, h: 1080 },
  portal: { label: 'Property portal (1600 px)', max: 1600 },
  small: { label: 'Small for email (1200 px)', max: 1200 },
};
export const LOOKS = {
  none: { label: 'No change', b: 1, c: 1, s: 1, w: 0 },
  auto: { label: '✨ Auto fix', auto: true },
  bright: { label: 'Bright & airy', b: 1.14, c: 1.04, s: 1.06, w: 0.02 },
  warm: { label: 'Warm', b: 1.04, c: 1.05, s: 1.08, w: 0.10 },
  crisp: { label: 'Crisp', b: 1.02, c: 1.14, s: 1.1, w: 0 },
  mono: { label: 'Black & white', b: 1.03, c: 1.12, s: 0, w: 0 },
};

/** Average brightness (0–1) of a picture, for "Auto fix". */
function luminance(src) {
  const c = document.createElement('canvas'); c.width = 64; c.height = 64;
  const g = c.getContext('2d', { willReadFrequently: true }); g.drawImage(src, 0, 0, 64, 64);
  const d = g.getImageData(0, 0, 64, 64).data; let sum = 0;
  for (let i = 0; i < d.length; i += 4) sum += (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]) / 255;
  return sum / (d.length / 4);
}

/** opts: { look, b, c, s, w (warmth −0.3…0.3), size, mark (watermark text), blurBox? } → canvas */
export function render(src, opts = {}) {
  const sw = src.width, sh = src.height;
  let L = { ...(LOOKS[opts.look] || LOOKS.none) };
  if (L.auto) { const lum = luminance(src); L = { b: Math.min(1.45, Math.max(0.85, 0.56 / Math.max(lum, 0.05))), c: 1.07, s: 1.08, w: 0.02 }; }
  const b = (opts.b ?? 1) * L.b, c = (opts.c ?? 1) * L.c, s = (opts.s ?? 1) * L.s, w = (opts.w ?? 0) + L.w;
  // output size (cover-crop to the target shape, centred)
  const S = SIZES[opts.size] || SIZES.original;
  let ow = sw, oh = sh, sx = 0, sy = 0, cw = sw, ch = sh;
  if (S.w) {
    ow = S.w; oh = S.h; const r = ow / oh;
    if (sw / sh > r) { cw = sh * r; sx = (sw - cw) / 2; } else { ch = sw / r; sy = (sh - ch) / 2; }
  } else if (S.max) { const k = Math.min(1, S.max / Math.max(sw, sh)); ow = Math.round(sw * k); oh = Math.round(sh * k); }
  const cv = document.createElement('canvas'); cv.width = ow; cv.height = oh;
  const g = cv.getContext('2d');
  g.imageSmoothingQuality = 'high';
  g.filter = `brightness(${b}) contrast(${c}) saturate(${s})`;
  g.drawImage(src, sx, sy, cw, ch, 0, 0, ow, oh);
  g.filter = 'none';
  if (w) {   // warmth: a soft colour wash (warm = amber, cool = blue)
    g.globalCompositeOperation = 'soft-light';
    g.fillStyle = w > 0 ? `rgba(255,170,80,${Math.min(0.6, w * 2.2)})` : `rgba(80,150,255,${Math.min(0.6, -w * 2.2)})`;
    g.fillRect(0, 0, ow, oh); g.globalCompositeOperation = 'source-over';
  }
  if (opts.mark) {   // watermark: bottom-right, readable on any photo
    const fs = Math.round(Math.max(18, Math.min(ow, oh) * 0.042));
    g.font = `600 ${fs}px Inter, system-ui, sans-serif`; g.textAlign = 'right'; g.textBaseline = 'bottom';
    const pad = Math.round(fs * 0.9);
    g.shadowColor = 'rgba(0,0,0,.45)'; g.shadowBlur = fs * 0.5; g.fillStyle = 'rgba(255,255,255,.88)';
    g.fillText(opts.mark, ow - pad, oh - pad); g.shadowBlur = 0;
  }
  return cv;
}

export async function loadPhoto(file) { return bitmap(file); }
export async function exportPhoto(src, opts, name) {
  const cv = render(src, opts);
  const blob = await toBlob(cv, 'image/jpeg', 0.9);
  return { name: base(name) + (opts.size && opts.size !== 'original' ? '-' + opts.size : '') + '-zuffi.jpg', bytes: new Uint8Array(await blob.arrayBuffer()), mime: 'image/jpeg' };
}

// ---------------- converter (the Filee idea: drop files, pick a format) ----------------
export const TARGETS = {
  jpg: { label: 'JPG photo', mime: 'image/jpeg', ext: 'jpg', from: /^image\// },
  png: { label: 'PNG image', mime: 'image/png', ext: 'png', from: /^image\// },
  webp: { label: 'WebP (small, for websites)', mime: 'image/webp', ext: 'webp', from: /^image\// },
  pdf: { label: 'PDF', ext: 'pdf', from: /^(image\/|text\/|application\/json)/ },
  txt: { label: 'Plain text', ext: 'txt', from: /^(text\/|application\/json)/ },
};
/** Which formats make sense for these files. */
export function targetsFor(files) {
  return Object.entries(TARGETS).filter(([, t]) => files.every(f => t.from.test(f.type || guessType(f.name)))).map(([k]) => k);
}
export function guessType(name) {
  const e = (name.split('.').pop() || '').toLowerCase();
  return { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp', gif: 'image/gif', heic: 'image/heic', bmp: 'image/bmp',
    txt: 'text/plain', md: 'text/markdown', csv: 'text/csv', html: 'text/html', htm: 'text/html', json: 'application/json' }[e] || '';
}
const textOf = async f => { let t = await f.text(); if (/html/.test(f.type || guessType(f.name))) { const d = new DOMParser().parseFromString(t, 'text/html'); t = d.body?.innerText || d.body?.textContent || t; } return t; };

/** files → [{name, bytes, mime}] in the chosen format. Images to PDF become one PDF. */
export async function convert(files, to) {
  const T = TARGETS[to]; if (!T) throw new Error('Unknown format');
  const out = [];
  if (to === 'pdf') {
    const { PDFDocument, StandardFonts, rgb } = await lib();
    const imgs = files.filter(f => /^image\//.test(f.type || guessType(f.name))), texts = files.filter(f => !imgs.includes(f));
    if (imgs.length) {
      const doc = await PDFDocument.create();
      for (const f of imgs) {
        const src = await bitmap(f); const c = document.createElement('canvas'); c.width = src.width; c.height = src.height; c.getContext('2d').drawImage(src, 0, 0);
        const img = await doc.embedJpg(new Uint8Array(await (await toBlob(c, 'image/jpeg', 0.9)).arrayBuffer()));
        const W = 595, H = 842, k = Math.min((W - 40) / img.width, (H - 40) / img.height, 1), p = doc.addPage([W, H]);
        p.drawImage(img, { x: (W - img.width * k) / 2, y: (H - img.height * k) / 2, width: img.width * k, height: img.height * k });
      }
      out.push({ name: (imgs.length === 1 ? base(imgs[0].name) : 'Photos') + '.pdf', bytes: await doc.save(), mime: 'application/pdf' });
    }
    for (const f of texts) {
      const doc = await PDFDocument.create(), font = await doc.embedFont(StandardFonts.Helvetica);
      const safe = s => s.replace(/[^\x20-\x7E£€ -ÿ]/g, '?');
      const lines = []; const W = 595, H = 842, M = 50, size = 11, maxW = W - 2 * M;
      for (const para of (await textOf(f)).replace(/\r/g, '').split('\n')) {
        let line = '';
        for (const word of safe(para).split(' ')) { const t = line ? line + ' ' + word : word; if (font.widthOfTextAtSize(t, size) > maxW && line) { lines.push(line); line = word; } else line = t; }
        lines.push(line);
      }
      let p = doc.addPage([W, H]), y = H - M;
      for (const l of lines) { if (y < M) { p = doc.addPage([W, H]); y = H - M; } p.drawText(l, { x: M, y, size, font, color: rgb(0.1, 0.1, 0.12) }); y -= size * 1.45; }
      out.push({ name: base(f.name) + '.pdf', bytes: await doc.save(), mime: 'application/pdf' });
    }
    return out;
  }
  if (to === 'txt') { for (const f of files) out.push({ name: base(f.name) + '.txt', bytes: new TextEncoder().encode(await textOf(f)), mime: 'text/plain' }); return out; }
  for (const f of files) {   // image → image
    const src = await bitmap(f); const c = document.createElement('canvas'); c.width = src.width; c.height = src.height;
    const g = c.getContext('2d'); if (to === 'jpg') { g.fillStyle = '#fff'; g.fillRect(0, 0, c.width, c.height); } g.drawImage(src, 0, 0);
    const blob = await toBlob(c, T.mime, 0.9);
    out.push({ name: base(f.name) + '.' + T.ext, bytes: new Uint8Array(await blob.arrayBuffer()), mime: T.mime });
  }
  return out;
}

// ---------------- sign a PDF ----------------
/** A signature pad on a canvas: returns { clear(), empty(), png() }. */
export function signaturePad(canvas) {
  const g = canvas.getContext('2d'); let drawing = false, has = false, last = null;
  const ratio = canvas.width / canvas.getBoundingClientRect().width || 1;
  g.lineWidth = 3.2 * ratio; g.lineCap = 'round'; g.lineJoin = 'round'; g.strokeStyle = '#14223D';
  const pt = e => { const r = canvas.getBoundingClientRect(), t = e.touches?.[0] || e; return [(t.clientX - r.left) * (canvas.width / r.width), (t.clientY - r.top) * (canvas.height / r.height)]; };
  const down = e => { e.preventDefault(); drawing = true; last = pt(e); };
  const move = e => { if (!drawing) return; e.preventDefault(); const p = pt(e); g.beginPath(); g.moveTo(...last); g.lineTo(...p); g.stroke(); last = p; has = true; };
  const up = () => { drawing = false; };
  canvas.addEventListener('pointerdown', down); canvas.addEventListener('pointermove', move); window.addEventListener('pointerup', up);
  canvas.style.touchAction = 'none';
  return { clear: () => { g.clearRect(0, 0, canvas.width, canvas.height); has = false; }, empty: () => !has, png: async () => new Uint8Array(await (await toBlob(canvas, 'image/png')).arrayBuffer()) };
}
/** Puts the signature (and the date + name under it) on a page: where = 'last' | 'first' | page number. */
export async function signPDF(file, png, { where = 'last', name = '', corner = 'right' } = {}) {
  const { PDFDocument, StandardFonts, rgb } = await lib();
  const doc = await PDFDocument.load(await file.arrayBuffer(), { ignoreEncryption: true });
  const pages = doc.getPages(); const idx = where === 'first' ? 0 : where === 'last' ? pages.length - 1 : Math.max(0, Math.min(pages.length - 1, (+where || 1) - 1));
  const page = pages[idx], { width: W } = page.getSize();
  const img = await doc.embedPng(png), font = await doc.embedFont(StandardFonts.Helvetica);
  const w = Math.min(190, W * 0.32), h = w * (img.height / img.width), x = corner === 'left' ? 50 : W - w - 50, y = 70;
  page.drawImage(img, { x, y, width: w, height: h });
  page.drawLine({ start: { x, y: y - 4 }, end: { x: x + w, y: y - 4 }, thickness: 0.6, color: rgb(0.55, 0.58, 0.65) });
  const label = `${name ? name.replace(/[^\x20-\x7E -ÿ]/g, '') + ' · ' : ''}Signed ${new Date().toLocaleDateString('en-GB')}`;
  page.drawText(label, { x, y: y - 18, size: 9, font, color: rgb(0.35, 0.38, 0.45) });
  return { name: base(file.name) + ' (signed).pdf', bytes: await doc.save(), mime: 'application/pdf' };
}
