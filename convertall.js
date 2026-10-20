// Convert almost any file Zuffi is given into another format, on this device (inspired by Filee):
//   photos ↔ JPG / PNG / WebP / PDF · Word / PDF / PowerPoint / text → PDF, Word or text · CSV ↔ Excel · Excel → CSV or PDF
import * as studio from './studio.js';
import { fileText } from './memory.js';
import { buildDocx, buildXlsx } from './office.js';

const ext = n => (String(n || '').split('.').pop() || '').toLowerCase();
const base = n => String(n || 'file').replace(/\.[^.]+$/, '') || 'file';
const kind = f => {
  const e = ext(f.name), t = f.type || '';
  if (/^image\//.test(t) || ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp', 'heic'].includes(e)) return 'image';
  if (e === 'csv') return 'csv';
  if (['xlsx', 'xls'].includes(e)) return 'sheet';
  if (e === 'pdf') return 'pdf';
  if (e === 'docx') return 'word';
  if (e === 'pptx') return 'slides';
  if (/^text\//.test(t) || ['txt', 'md', 'html', 'htm', 'json', 'rtf', 'log'].includes(e)) return 'text';
  return 'other';
};
export const LABELS = { jpg: 'JPG', png: 'PNG', webp: 'WebP', pdf: 'PDF', docx: 'Word', txt: 'Text', xlsx: 'Excel', csv: 'CSV' };

/** The formats this file can become. */
export function formatsFor(f) {
  const e = ext(f.name);
  const list = { image: ['jpg', 'png', 'webp', 'pdf'], csv: ['xlsx', 'pdf', 'txt'], sheet: ['csv', 'pdf'], pdf: ['docx', 'txt'], word: ['pdf', 'txt'], slides: ['pdf', 'docx', 'txt'], text: ['pdf', 'docx', 'txt'], other: [] }[kind(f)];
  return list.filter(x => x !== e && !(x === 'jpg' && e === 'jpeg'));
}

const textFile = (name, text) => new File([text], name + '.txt', { type: 'text/plain' });

/** file → { name, bytes, mime } in the chosen format. */
export async function convertAny(f, to) {
  const k = kind(f);
  if (k === 'image' || (k === 'text' && ['pdf', 'txt'].includes(to) && /^text\//.test(f.type || 'text/plain'))) return (await studio.convert([f], to))[0];
  if (k === 'csv' && to === 'xlsx') {
    await import('./office.js');
    const rows = (await f.text()).replace(/\r/g, '').split('\n').filter(Boolean).map(line => { const out = []; let cur = '', q = false; for (const ch of line) { if (ch === '"') q = !q; else if (ch === ',' && !q) { out.push(cur); cur = ''; } else cur += ch; } out.push(cur); return out; });
    const r = await buildXlsx({ title: base(f.name), sheets: [{ name: 'Sheet1', columns: rows[0] || [], rows: rows.slice(1) }] });
    return { ...r, name: base(f.name) + '.xlsx' };
  }
  if (k === 'sheet' && to === 'csv') {
    const text = await fileText(f);   // tab separated rows
    const csv = text.split('\n').map(r => r.split('\t').map(c => /[",\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c).join(',')).join('\n');
    return { name: base(f.name) + '.csv', bytes: new TextEncoder().encode(csv), mime: 'text/csv' };
  }
  // everything else goes through the file's text
  const text = k === 'text' || k === 'csv' ? await f.text() : await fileText(f);
  if (!String(text || '').trim()) throw new Error('I couldn’t read any text in this file (a scanned PDF?).');
  if (to === 'txt') return { name: base(f.name) + '.txt', bytes: new TextEncoder().encode(text), mime: 'text/plain' };
  if (to === 'pdf') { const r = (await studio.convert([textFile(base(f.name), text.replace(/\t/g, '    '))], 'pdf'))[0]; return { ...r, name: base(f.name) + '.pdf' }; }
  if (to === 'docx') {
    const paras = text.replace(/\r/g, '').split(/\n{2,}|\n/).map(s => s.trim()).filter(Boolean);
    const r = await buildDocx({ title: base(f.name), sections: [{ paragraphs: paras.slice(0, 4000) }] });
    return { ...r, name: base(f.name) + '.docx' };
  }
  throw new Error('That conversion isn’t available yet.');
}
