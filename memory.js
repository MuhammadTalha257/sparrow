// Sparrow's private memory: a timeline of what you did with Sparrow, kept on this device only
// (IndexedDB). Nothing is uploaded. You can pause it, forget items, or wipe it.
import { store } from './store.js';

const DB = 'sparrow-memory', VER = 1;
let dbp = null;
function db() {
  if (dbp) return dbp;
  dbp = new Promise((res, rej) => {
    const r = indexedDB.open(DB, VER);
    r.onupgradeneeded = () => {
      const d = r.result;
      if (!d.objectStoreNames.contains('log')) { const s = d.createObjectStore('log', { keyPath: 'id', autoIncrement: true }); s.createIndex('at', 'at'); }
      if (!d.objectStoreNames.contains('files')) { const s = d.createObjectStore('files', { keyPath: 'id' }); s.createIndex('at', 'at'); }
    };
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
  return dbp;
}
const tx = async (store, mode, fn) => {
  const d = await db();
  return new Promise((res, rej) => {
    const t = d.transaction(store, mode), s = t.objectStore(store);
    let out; const r = fn(s);
    if (r) r.onsuccess = () => { out = r.result; };
    t.oncomplete = () => res(out); t.onerror = () => rej(t.error);
  });
};
// Inside the Mac app, memory lives in the app itself (Application Support), shared with the island — reliable and private.
const NATIVE = window.SparrowHost === 'mac' && window.SparrowMac;
const nat = (op, args = {}) => window.SparrowMac.call('mem', { op, ...args });
const b64 = async blob => { const u = new Uint8Array(await blob.arrayBuffer()); let s = ''; for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); };
const back = {
  logAdd: r => NATIVE ? nat('logAdd', { rec: r }) : tx('log', 'readwrite', s => s.add(r)),
  logDel: id => NATIVE ? nat('logDel', { id }) : tx('log', 'readwrite', s => s.delete(id)),
  filePut: async r => {
    if (!NATIVE) return tx('files', 'readwrite', s => s.put(r));
    const { blob, ...lite } = r;
    return nat('filePut', { rec: lite, base64: blob ? await b64(blob) : '' });
  },
  fileGet: async id => {
    if (!NATIVE) return tx('files', 'readonly', s => s.get(id));
    const r = await nat('fileGet', { id }); if (!r) return null;
    if (r.base64) { const bin = atob(r.base64), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i); r.blob = new Blob([u], { type: r.type || 'application/octet-stream' }); }
    delete r.base64; return r;
  },
  fileDel: id => NATIVE ? nat('fileDel', { id }) : tx('files', 'readwrite', s => s.delete(id)),
  clear: async () => { if (NATIVE) return nat('wipe'); await tx('log', 'readwrite', s => s.clear()); await tx('files', 'readwrite', s => s.clear()); },
};
const all = async (name) => {
  if (NATIVE) return (await nat(name === 'log' ? 'logAll' : 'fileAll')) || [];
  const d = await db();
  return new Promise((res, rej) => {
    const r = d.transaction(name).objectStore(name).getAll();
    r.onsuccess = () => res(r.result || []); r.onerror = () => rej(r.error);
  });
};

/** Remember something. kind: chat | file | task | done | reminder | meeting | note | quote | invoice | expense | email | opened | meeting-notes | customer | habit | report */
export async function remember(kind, title, text = '', meta = {}) {
  if (!store.settings.memory?.on) return null;
  try { return await back.logAdd({ at: Date.now(), kind, title: String(title).slice(0, 300), text: String(text || '').slice(0, 20000), meta }); }
  catch { return null; }
}

// ---------- reading text out of files (offline) ----------
async function unzipEntries(buf, want) {
  // Minimal ZIP reader (enough for .docx / .xlsx / .pptx) using the browser's own decompressor.
  const v = new DataView(buf), out = {};
  let eocd = -1;
  for (let i = buf.byteLength - 22; i >= Math.max(0, buf.byteLength - 70000); i--) if (v.getUint32(i, true) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) return out;
  let p = v.getUint32(eocd + 16, true);
  const n = v.getUint16(eocd + 10, true), dec = new TextDecoder();
  for (let k = 0; k < n; k++) {
    if (v.getUint32(p, true) !== 0x02014b50) break;
    const method = v.getUint16(p + 10, true), csize = v.getUint32(p + 20, true);
    const nlen = v.getUint16(p + 28, true), elen = v.getUint16(p + 30, true), clen = v.getUint16(p + 32, true);
    const local = v.getUint32(p + 42, true);
    const name = dec.decode(new Uint8Array(buf, p + 46, nlen));
    p += 46 + nlen + elen + clen;
    if (!want(name)) continue;
    const lnlen = v.getUint16(local + 26, true), lelen = v.getUint16(local + 28, true);
    const data = new Uint8Array(buf, local + 30 + lnlen + lelen, csize);
    try {
      if (method === 0) out[name] = dec.decode(data);
      else if (method === 8 && 'DecompressionStream' in window) {
        const s = new Blob([data]).stream().pipeThrough(new DecompressionStream('deflate-raw'));
        out[name] = await new Response(s).text();
      }
    } catch {}
  }
  return out;
}
const xmlText = x => x.replace(/<\/(w:p|a:p|row)>/g, '\n').replace(/<(w:tab|w:br)\/>/g, ' ').replace(/<[^>]+>/g, '')
  .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/\n{3,}/g, '\n\n').trim();

let pdfjs = null;
async function pdfText(buf) {
  if (!pdfjs) {
    pdfjs = await import('./lib/pdf.min.js');
    pdfjs.GlobalWorkerOptions.workerSrc = new URL('./lib/pdf.worker.min.js', import.meta.url).href;
  }
  const doc = await pdfjs.getDocument({ data: new Uint8Array(buf) }).promise;
  let text = '';
  for (let i = 1; i <= Math.min(doc.numPages, 80); i++) {
    const page = await doc.getPage(i);
    const c = await page.getTextContent();
    text += c.items.map(it => it.str + (it.hasEOL ? '\n' : ' ')).join('') + '\n\n';
    if (text.length > 200000) break;
  }
  return text.trim();
}

/** Best-effort plain text of a file (txt, md, csv, json, html, pdf, docx, xlsx, pptx). */
export async function fileText(file) {
  const name = (file.name || '').toLowerCase();
  try {
    if (/\.(txt|md|csv|tsv|json|log|html?|xml|js|py|ts|css|ics|vcf|eml)$/.test(name) || (file.type || '').startsWith('text/')) return (await file.text()).slice(0, 300000);
    const buf = await file.arrayBuffer();
    if (name.endsWith('.pdf')) return await pdfText(buf);
    if (name.endsWith('.docx')) { const e = await unzipEntries(buf, n => n === 'word/document.xml'); return xmlText(e['word/document.xml'] || ''); }
    if (name.endsWith('.pptx')) { const e = await unzipEntries(buf, n => /^ppt\/slides\/slide\d+\.xml$/.test(n)); return Object.keys(e).sort().map(k => xmlText(e[k])).join('\n\n'); }
    if (name.endsWith('.xlsx')) {
      const e = await unzipEntries(buf, n => n === 'xl/sharedStrings.xml' || /^xl\/worksheets\/sheet\d+\.xml$/.test(n));
      const strings = (e['xl/sharedStrings.xml'] || '').match(/<si>[\s\S]*?<\/si>/g)?.map(xmlText) || [];
      return Object.keys(e).filter(k => k.includes('worksheets')).sort().map(k =>
        (e[k].match(/<row[\s\S]*?<\/row>/g) || []).map(row => (row.match(/<c [^>]*?(?:\/>|>[\s\S]*?<\/c>)/g) || []).map(c => {
          const val = (c.match(/<v>([\s\S]*?)<\/v>/) || [])[1] ?? xmlText(c);
          return /t="s"/.test(c) ? (strings[+val] ?? '') : val;
        }).join('\t')).join('\n')).join('\n\n');
    }
  } catch (e) { console.warn('fileText', e); }
  return '';
}

/** Save a file the person gave Sparrow. Returns the stored record (without the blob). */
export async function addFile(file, keepCopy = store.settings.memory?.keepCopies) {
  const text = await fileText(file);
  const rec = { id: 'f' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6), name: file.name, type: file.type, size: file.size,
    at: Date.now(), text: text.slice(0, 400000), blob: keepCopy && file.size < 30e6 ? file : null };
  try { await back.filePut(rec); } catch (e) { console.warn('memory: file not saved', e); }
  await remember('file', file.name, text.slice(0, 4000), { fileId: rec.id, size: file.size, copy: !!rec.blob });
  const { blob, ...lite } = rec;
  return lite;
}
export async function getFile(id) { try { return await back.fileGet(id); } catch { return null; } }
export async function listFiles() { return (await all('files')).sort((a, b) => b.at - a.at).map(({ blob, ...r }) => ({ ...r, hasCopy: !!blob || !!r.hasCopy })); }

// ---------- search ----------
/** Search memory. opts: { q, from, to, kinds } — from/to are timestamps. */
export async function search({ q = '', from = 0, to = Infinity, kinds = null, limit = 60 } = {}) {
  const words = q.toLowerCase().split(/\s+/).filter(w => w.length > 1);
  const rows = (await all('log')).filter(r => r.at >= from && r.at <= to && (!kinds || kinds.includes(r.kind)));
  const scored = rows.map(r => {
    const hay = (r.title + ' ' + r.text).toLowerCase();
    const s = words.length ? words.reduce((n, w) => n + (hay.includes(w) ? 1 : 0), 0) : 1;
    return { r, s };
  }).filter(x => x.s > 0).sort((a, b) => b.s - a.s || b.r.at - a.r.at);
  return scored.slice(0, limit).map(x => x.r);
}
export async function recent(limit = 100) { return (await all('log')).sort((a, b) => b.at - a.at).slice(0, limit); }
export async function forget(id) { try { await back.logDel(id); } catch {} }
export async function forgetFile(id) { try { await back.fileDel(id); } catch {} }
export async function forgetAll() { try { await back.clear(); } catch {} }
/** Remove entries older than the chosen number of days (0 = keep forever). */
export async function prune() {
  const days = +store.settings.memory?.days || 0;
  if (!days) return;
  const cut = Date.now() - days * 86400e3;
  for (const r of await all('log')) if (r.at < cut) await forget(r.id);
  for (const f of await all('files')) if (f.at < cut) await forgetFile(f.id);
}
export async function exportMemory() { return { log: await all('log'), files: (await all('files')).map(({ blob, ...f }) => f) }; }
export async function importMemory(data) {
  const have = new Set((await all('log')).map(r => r.at + r.title));
  for (const r of data?.log || []) if (!have.has(r.at + r.title)) { const { id, ...rest } = r; await back.logAdd(rest); }
  for (const f of data?.files || []) await back.filePut(f);
}

/** Text chunks from your files that best match a question (for "ask your documents"). */
export async function relevantText(question, fileIds = null, max = 9000) {
  const files = (await all('files')).filter(f => !fileIds || fileIds.includes(f.id)).sort((a, b) => b.at - a.at);
  const words = question.toLowerCase().split(/\W+/).filter(w => w.length > 3);
  const chunks = [];
  for (const f of files.slice(0, 12)) {
    const parts = (f.text || '').split(/\n\s*\n/).flatMap(p => p.length > 1500 ? p.match(/[\s\S]{1,1500}/g) : [p]);
    parts.forEach((p, i) => {
      const lp = p.toLowerCase();
      chunks.push({ name: f.name, text: p, s: words.reduce((n, w) => n + (lp.includes(w) ? 1 : 0), 0) + (i === 0 ? 0.5 : 0) + (fileIds ? 0.2 : 0) });
    });
  }
  chunks.sort((a, b) => b.s - a.s);
  let out = '', used = 0;
  for (const c of chunks) { if (used + c.text.length > max) break; out += `[${c.name}]\n${c.text}\n\n`; used += c.text.length; }
  return out.trim();
}
