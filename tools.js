// Business & file tools that run entirely on the device: quotes, invoices, PDFs, time, expenses.
import { store } from './store.js';

let PDFLib = null;
async function lib() { if (!PDFLib) PDFLib = await import('./lib/pdf-lib.min.js'); return PDFLib; }

const b64 = bytes => { let s = ''; const c = 0x8000; for (let i = 0; i < bytes.length; i += c) s += String.fromCharCode.apply(null, bytes.subarray(i, i + c)); return btoa(s); };

/** Save or share a file the person made (PDF, CSV…). */
export async function deliver(name, bytes, mime) {
  const D = window.SparrowDesktop, N = window.SparrowNative;
  if (window.SparrowHost === 'mac') return window.SparrowMac.call('save', { name, base64: b64(bytes) });
  if (D) return D.saveFile(name, b64(bytes));
  if (N?.saveFile) return N.saveFile(name, b64(bytes), mime) ? name : null;
  const file = new File([bytes], name, { type: mime });
  if (navigator.canShare?.({ files: [file] })) { try { await navigator.share({ files: [file], title: name }); return name; } catch (e) { if (e.name === 'AbortError') return null; } }
  const a = document.createElement('a'); a.href = URL.createObjectURL(file); a.download = name; document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 4000);
  return name;
}

// ---------- quotes & invoices ----------
const money = n => (store.settings.business.currency || '£') + (Math.round(n * 100) / 100).toFixed(2);
// PDF standard fonts only cover Western characters; keep anything else readable.
const safe = s => String(s ?? '').replace(/[^\x20-\x7E£€ -ÿ]/g, '?');

/** doc: { kind:'Quote'|'Invoice', number, customer, lines:[{desc, qty, price}], note } → PDF bytes */
export async function makeDocPDF(doc) {
  const { PDFDocument, StandardFonts, rgb } = await lib();
  const pdf = await PDFDocument.create();
  const page = pdf.addPage([595, 842]);
  const f = await pdf.embedFont(StandardFonts.Helvetica), fb = await pdf.embedFont(StandardFonts.HelveticaBold);
  const ink = rgb(0.07, 0.13, 0.23), muted = rgb(0.35, 0.42, 0.52), accent = rgb(0.18, 0.44, 0.92);
  const biz = store.settings.business;
  let y = 790;
  page.drawText(safe(biz.name || store.settings.name || 'My business'), { x: 50, y, size: 20, font: fb, color: ink });
  page.drawText(safe(doc.kind.toUpperCase()), { x: 420, y, size: 20, font: fb, color: accent });
  y -= 18;
  for (const line of safe(biz.address || '').split(/\n|,\s*/).filter(Boolean).slice(0, 4)) { page.drawText(line, { x: 50, y, size: 10, font: f, color: muted }); y -= 13; }
  page.drawText(`No. ${doc.number}`, { x: 420, y: 772, size: 10, font: f, color: muted });
  page.drawText(new Date().toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' }), { x: 420, y: 759, size: 10, font: f, color: muted });
  y = Math.min(y, 720) - 20;
  page.drawText('For', { x: 50, y, size: 10, font: f, color: muted }); y -= 16;
  page.drawText(safe(doc.customer || 'Customer'), { x: 50, y, size: 13, font: fb, color: ink }); y -= 34;
  page.drawRectangle({ x: 50, y: y - 6, width: 495, height: 22, color: rgb(0.93, 0.96, 0.99) });
  page.drawText('Description', { x: 58, y, size: 10, font: fb, color: ink });
  page.drawText('Qty', { x: 330, y, size: 10, font: fb, color: ink });
  page.drawText('Price', { x: 390, y, size: 10, font: fb, color: ink });
  page.drawText('Total', { x: 480, y, size: 10, font: fb, color: ink });
  y -= 26;
  let total = 0;
  for (const l of doc.lines) {
    const t = (+l.qty || 1) * (+l.price || 0); total += t;
    page.drawText(safe(l.desc).slice(0, 55), { x: 58, y, size: 11, font: f, color: ink });
    page.drawText(String(l.qty ?? 1), { x: 330, y, size: 11, font: f, color: ink });
    page.drawText(money(+l.price || 0), { x: 390, y, size: 11, font: f, color: ink });
    page.drawText(money(t), { x: 480, y, size: 11, font: f, color: ink });
    y -= 20;
  }
  y -= 10;
  page.drawLine({ start: { x: 330, y: y + 8 }, end: { x: 545, y: y + 8 }, thickness: 1, color: rgb(0.85, 0.88, 0.92) });
  page.drawText('Total', { x: 390, y: y - 8, size: 13, font: fb, color: ink });
  page.drawText(money(total), { x: 480, y: y - 8, size: 13, font: fb, color: accent });
  if (doc.note) page.drawText(safe(doc.note).slice(0, 90), { x: 50, y: 90, size: 10, font: f, color: muted });
  page.drawText(doc.kind === 'Quote' ? 'This quote is valid for 30 days.' : 'Thank you for your business.', { x: 50, y: 70, size: 10, font: f, color: muted });
  return { bytes: await pdf.save(), total };
}

/** Parse "quote for Ali, 3 hours at £40" / "invoice Ahmed 2 x logo design £150, hosting £20" */
export function parseDoc(text) {
  const m = text.match(/^(quote|invoice|bill)\s+(?:for\s+)?(.+)$/i);
  if (!m) return null;
  const kind = /quote/i.test(m[1]) ? 'Quote' : 'Invoice';
  let rest = m[2];
  const cm = rest.match(/^([^,:]+?)(?:[,:]\s*|\s+(?=\d))(.*)$/);
  const customer = cm ? cm[1].trim() : rest.trim();
  const body = cm ? cm[2] : '';
  const lines = [];
  for (const part of body.split(/,|\band\b/).map(s => s.trim()).filter(Boolean)) {
    let r = part.match(/^(\d+(?:\.\d+)?)\s*(?:x\s*)?(hours?|hrs?|h|days?|items?|pcs?)?\s*(.*?)\s*(?:at|@|for|x)?\s*[£$€₹]?\s*(\d+(?:\.\d+)?)\s*(?:each|per\s+\w+|\/\w+)?$/i);
    if (r) { lines.push({ qty: +r[1], desc: (r[3] || r[2] || 'Work').trim() || (r[2] || 'Work'), price: +r[4] }); continue; }
    r = part.match(/^(.*?)\s*(?:at|@|for)?\s*[£$€₹]\s*(\d+(?:\.\d+)?)$/i) || part.match(/^(.*?)\s+(\d+(?:\.\d+)?)$/);
    if (r) lines.push({ qty: 1, desc: r[1].trim() || 'Work', price: +r[2] });
  }
  return { kind, customer: customer.replace(/^(for|to)\s+/i, ''), lines };
}

// ---------- time tracking ----------
export function runningTimer() { return store.items.find(i => i.type === 'timer' && !i.end); }
export function startTimer(label) {
  const r = runningTimer(); if (r) stopTimer();
  return store.add({ type: 'timer', title: label || 'Work', start: Date.now(), end: null });
}
export function stopTimer() {
  const r = runningTimer(); if (!r) return null;
  store.update(r.id, { end: Date.now() });
  return r;
}
export const hours = it => ((it.end || Date.now()) - it.start) / 3600e3;
export function timeFor(label, since = 0) {
  const l = (label || '').toLowerCase();
  return store.items.filter(i => i.type === 'timer' && i.start >= since && (!l || i.title.toLowerCase().includes(l))).reduce((n, i) => n + hours(i), 0);
}
export const fmtHours = h => { const m = Math.round(h * 60); return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60 ? (m % 60) + ' min' : ''}`.trim(); };

// ---------- expenses ----------
export function parseExpense(t) {
  const m = t.match(/^(?:i\s+)?(?:spent|paid|expense|bought)\s+(?:[£$€₹])?\s*(\d+(?:\.\d+)?)\s*(?:pounds|dollars|euros|rupees|rs)?\s*(?:on|for)?\s*(.*)$/i)
    || t.match(/^(?:i\s+)?(?:spent|paid|bought)\s+(.+?)\s+(?:for|at)\s+[£$€₹]?\s*(\d+(?:\.\d+)?)$/i);
  if (!m) return null;
  if (/^\d/.test(m[1])) return { amount: +m[1], what: (m[2] || 'Expense').trim() };
  return { amount: +m[2], what: m[1].trim() };
}
export function monthExpenses(d = new Date()) {
  return store.items.filter(i => i.type === 'expense' && new Date(i.created).getMonth() === d.getMonth() && new Date(i.created).getFullYear() === d.getFullYear());
}
export function csv(rows) {
  return rows.map(r => r.map(v => { const s = String(v ?? ''); return /[",\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s; }).join(',')).join('\n');
}

// ---------- PDF tools ----------
export async function mergePDFs(files) {
  const { PDFDocument } = await lib();
  const out = await PDFDocument.create();
  for (const f of files) {
    const src = await PDFDocument.load(await f.arrayBuffer(), { ignoreEncryption: true });
    (await out.copyPages(src, src.getPageIndices())).forEach(p => out.addPage(p));
  }
  return out.save();
}
export async function imagesToPDF(files) {
  const { PDFDocument } = await lib();
  const out = await PDFDocument.create();
  for (const f of files) {
    let bytes = new Uint8Array(await f.arrayBuffer()), img;
    if (/png$/i.test(f.type) || /\.png$/i.test(f.name)) img = await out.embedPng(bytes);
    else if (/jpe?g$/i.test(f.type) || /\.jpe?g$/i.test(f.name)) img = await out.embedJpg(bytes);
    else {   // webp/heic etc → draw onto a canvas and convert to JPEG
      const bmp = await createImageBitmap(f);
      const c = document.createElement('canvas'); c.width = bmp.width; c.height = bmp.height; c.getContext('2d').drawImage(bmp, 0, 0);
      const blob = await new Promise(r => c.toBlob(r, 'image/jpeg', 0.9));
      img = await out.embedJpg(new Uint8Array(await blob.arrayBuffer()));
    }
    const w = 595, h = 842, s = Math.min((w - 40) / img.width, (h - 40) / img.height, 1);
    const page = out.addPage([w, h]);
    page.drawImage(img, { x: (w - img.width * s) / 2, y: (h - img.height * s) / 2, width: img.width * s, height: img.height * s });
  }
  return out.save();
}
/** Keep pages, e.g. "1-3, 5" */
export async function extractPages(file, spec) {
  const { PDFDocument } = await lib();
  const src = await PDFDocument.load(await file.arrayBuffer(), { ignoreEncryption: true });
  const n = src.getPageCount(), want = [];
  for (const part of String(spec).split(',')) {
    const [a, b] = part.split('-').map(x => parseInt(x, 10));
    if (!a) continue;
    for (let i = a; i <= (b || a); i++) if (i >= 1 && i <= n) want.push(i - 1);
  }
  const out = await PDFDocument.create();
  (await out.copyPages(src, want.length ? want : src.getPageIndices())).forEach(p => out.addPage(p));
  return out.save();
}
export async function rotatePDF(file, degrees = 90) {
  const { PDFDocument, degrees: deg } = await lib();
  const doc = await PDFDocument.load(await file.arrayBuffer(), { ignoreEncryption: true });
  doc.getPages().forEach(p => p.setRotation(deg((p.getRotation().angle + degrees) % 360)));
  return doc.save();
}

/** Simple action items from meeting notes, no AI needed. */
export function actionItems(text) {
  return text.split(/(?<=[.!?])\s+|\n+/).map(s => s.trim()).filter(s =>
    s.length > 8 && /\b(i'?ll|we'?ll|will|need to|needs to|should|must|have to|action|to ?do|follow up|send|call|email|book|prepare|finish|by (monday|tuesday|wednesday|thursday|friday|tomorrow|next week|end of))\b/i.test(s))
    .slice(0, 12).map(s => s.replace(/^(so|and|okay|ok|um|uh),?\s+/i, ''));
}
