// Word, Excel and PowerPoint from one sentence. The AI writes the content (as JSON); the file itself is built
// on this device (docx, SheetJS, PptxGenJS — MIT / Apache-2.0). Business exports (leads, money) need no AI at all.
import { ask } from './ai.js';
import * as bs from './bizsync.js';

const loadScript = src => new Promise((res, rej) => {
  if (document.querySelector(`script[data-src="${src}"]`)) return res();
  const s = document.createElement('script'); s.src = src; s.dataset.src = src; s.onload = res; s.onerror = () => rej(new Error('Couldn’t load ' + src)); document.head.appendChild(s);
});
const safeName = s => String(s || 'Document').replace(/[\\/:*?"<>|]+/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 60) || 'Document';

/** "make a powerpoint about…" / "excel of my leads" → 'docx' | 'xlsx' | 'pptx' | null */
export function kindOf(text) {
  const t = String(text).toLowerCase();
  if (!/\b(make|create|write|build|prepare|draft|generate|give me|export|bana|banao)\b/.test(t)) return null;
  if (/\b(power ?point|pptx?|slides?|slide deck|deck|presentation)\b/.test(t)) return 'pptx';
  if (/\b(excel|xlsx|spreadsheet|sheet|budget|table of)\b/.test(t)) return 'xlsx';
  if (/\b(word|docx|document|letter|contract|agreement|report|proposal|cv|resume|cover letter|policy|job ad(vert)?)\b/.test(t)) return 'docx';
  return null;
}

const SPEC = {
  docx: `{"title": string, "sections": [{"heading": string (optional), "paragraphs": [string], "bullets": [string] (optional)}]}`,
  xlsx: `{"title": string, "sheets": [{"name": string (max 28 chars), "columns": [string], "rows": [[string|number]], "total": [column names to add up] (optional)}]}`,
  pptx: `{"title": string, "subtitle": string, "slides": [{"title": string, "bullets": [string] (3-5 short points), "note": string (speaker note, optional)}]} — 5 to 8 slides`,
};
function parseJSON(t) {
  const s = String(t || '').replace(/^```(json)?/m, '').replace(/```\s*$/m, '');
  const a = s.indexOf('{'), b = s.lastIndexOf('}');
  return JSON.parse(s.slice(a, b + 1));
}
/** Ask the AI for the content. biz: extra facts about the user's business. */
export async function plan(kind, request, biz = '') {
  const system = `You write the content for a ${kind === 'docx' ? 'Word document' : kind === 'xlsx' ? 'Excel spreadsheet' : 'PowerPoint presentation'}.
Reply with ONLY valid JSON in this shape: ${SPEC[kind]}.
Write real, finished, useful content in the language of the request — no placeholders like [Name] unless the detail is truly unknown. UK spelling and £ unless the request says otherwise. Numbers in spreadsheets must be numbers, not text.${biz ? '\nAbout the user: ' + biz : ''}`;
  const r = await ask(request, null, { noHistory: true, system, maxTokens: 3000 });
  return parseJSON(r.text);
}

// ---------------- builders ----------------
export async function buildDocx(spec) {
  await loadScript('lib/docx.iife.js');
  const D = window.docx;
  const kids = [new D.Paragraph({ heading: D.HeadingLevel.TITLE, children: [new D.TextRun({ text: spec.title || 'Document' })] })];
  for (const sec of spec.sections || []) {
    if (sec.heading) kids.push(new D.Paragraph({ heading: D.HeadingLevel.HEADING_1, spacing: { before: 240 }, children: [new D.TextRun(sec.heading)] }));
    for (const p of sec.paragraphs || []) kids.push(new D.Paragraph({ spacing: { after: 120 }, children: [new D.TextRun(String(p))] }));
    for (const b of sec.bullets || []) kids.push(new D.Paragraph({ bullet: { level: 0 }, children: [new D.TextRun(String(b))] }));
  }
  const doc = new D.Document({ creator: 'Zuffi', title: spec.title, styles: { default: { document: { run: { font: 'Calibri', size: 23 } } } }, sections: [{ children: kids }] });
  return { name: safeName(spec.title) + '.docx', bytes: new Uint8Array(await (await D.Packer.toBlob(doc)).arrayBuffer()), mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' };
}
export async function buildXlsx(spec) {
  await loadScript('lib/xlsx.mini.min.js');
  const X = window.XLSX, wb = X.utils.book_new();
  for (const sh of spec.sheets || []) {
    const cols = sh.columns || [], rows = (sh.rows || []).map(r => cols.map((_, i) => { const v = r[i]; const n = typeof v === 'string' && /^-?[£$€]?\d[\d,]*(\.\d+)?$/.test(v.trim()) ? +v.replace(/[£$€,]/g, '') : v; return n ?? ''; }));
    const aoa = [cols, ...rows];
    if (sh.total?.length && rows.length) aoa.push(cols.map((c, i) => i === 0 ? 'Total' : sh.total.includes(c) ? rows.reduce((a, r) => a + (+r[i] || 0), 0) : ''));
    const ws = X.utils.aoa_to_sheet(aoa);
    ws['!cols'] = cols.map((c, i) => ({ wch: Math.min(40, Math.max(String(c).length, ...rows.map(r => String(r[i] ?? '').length)) + 2) }));
    X.utils.book_append_sheet(wb, ws, String(sh.name || 'Sheet').slice(0, 28));
  }
  if (!wb.SheetNames.length) X.utils.book_append_sheet(wb, X.utils.aoa_to_sheet([['Empty']]), 'Sheet1');
  const out = X.write(wb, { bookType: 'xlsx', type: 'array' });
  return { name: safeName(spec.title) + '.xlsx', bytes: new Uint8Array(out), mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' };
}
export async function buildPptx(spec, accent = 'E2648A') {
  await loadScript('lib/pptxgen.bundle.js');
  const P = new window.PptxGenJS(); P.layout = 'LAYOUT_WIDE'; P.title = spec.title || 'Presentation';
  const ink = '16213A', soft = '5B6A85';
  const t = P.addSlide(); t.background = { color: 'F6F7FB' };
  t.addShape(P.ShapeType.rect, { x: 0, y: 6.9, w: 13.33, h: 0.6, fill: { color: accent } });
  t.addText(spec.title || 'Presentation', { x: 0.8, y: 2.3, w: 11.7, h: 1.4, fontSize: 44, bold: true, color: ink, fontFace: 'Calibri' });
  if (spec.subtitle) t.addText(spec.subtitle, { x: 0.8, y: 3.7, w: 11.7, h: 0.8, fontSize: 22, color: soft, fontFace: 'Calibri' });
  for (const s of spec.slides || []) {
    const sl = P.addSlide(); sl.background = { color: 'FFFFFF' };
    sl.addShape(P.ShapeType.rect, { x: 0.8, y: 0.55, w: 0.12, h: 0.75, fill: { color: accent } });
    sl.addText(s.title || '', { x: 1.1, y: 0.45, w: 11.4, h: 0.95, fontSize: 32, bold: true, color: ink, fontFace: 'Calibri' });
    const pts = (s.bullets || []).map(b => ({ text: String(b), options: { bullet: { indent: 22 }, paraSpaceAfter: 14 } }));
    if (pts.length) sl.addText(pts, { x: 1.1, y: 1.7, w: 11.2, h: 4.9, fontSize: 22, color: '2A3550', fontFace: 'Calibri', valign: 'top' });
    if (s.note) sl.addNotes(String(s.note));
  }
  const blob = await P.write({ outputType: 'blob' });
  return { name: safeName(spec.title) + '.pptx', bytes: new Uint8Array(await blob.arrayBuffer()), mime: 'application/vnd.openxmlformats-officedocument.presentationml.presentation' };
}
export async function build(kind, spec) { return kind === 'docx' ? buildDocx(spec) : kind === 'xlsx' ? buildXlsx(spec) : buildPptx(spec); }

/** Whole job: request → file. */
export async function make(kind, request, biz) { const spec = await plan(kind, request, biz); return { spec, file: await build(kind, spec) }; }

// ---------------- no-AI exports from the user's own business data ----------------
export const EXPORTS = {
  Leads: 'My leads', Clients: 'My clients', Money: 'Money in & out', Due: 'Who owes me', Appointments: 'Appointments', Listings: 'Property listings', Team: 'My team',
};
export function exportable() { return Object.keys(EXPORTS).filter(s => (bs.rows(s) || []).length); }
export async function exportSheets(names) {
  const sheets = names.map(n => { const rows = (bs.rows(n) || []).map(x => x.r || {}); const cols = bs.HEADERS[n] || Object.keys(rows[0] || {}); const money = n === 'Money' || n === 'Due';
    return { name: EXPORTS[n] || n, columns: cols, rows: rows.map(r => cols.map(c => r[c] ?? '')), total: money ? ['Amount'] : [] }; });
  return buildXlsx({ title: names.length === 1 ? (EXPORTS[names[0]] || names[0]) : 'My business', sheets });
}
