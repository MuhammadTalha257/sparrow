// Business data shared by every device you link with a QR code — Mac, phone, tablet, Windows.
// Same rules as BizSync.swift on the Mac (keep them in step):
//  • a group = random channel + 256-bit key, handed over once by a QR code ("…#biz=CHANNEL.KEY")
//  • changes go through the free ntfy.sh relay, end-to-end encrypted with AES-GCM (the relay can't read them)
//  • every row has a key (phone for leads, name for staff, property ID…) and a time; the newest change wins;
//    deleted rows leave a tombstone so they don't come back
//  • the relay keeps messages ~12 hours; a device away for longer asks the others for everything ("hello")

const RELAY = 'https://ntfy.sh';
const LS = 'zuffiBiz';
export const SHEETS = ['Leads', 'Team', 'Money', 'Due', 'Hours', 'Payroll', 'Listings', 'Visits', 'Appointments', 'Clients'];
export const HEADERS = {
  Leads: ['Name', 'Phone', 'Source', 'Interest', 'Area', 'Budget', 'Value', 'Status', 'Priority', 'Assigned to', 'Added', 'Last contact', 'Next follow-up', 'Last message', 'Last message at', 'Notes'],
  Team: ['Name', 'Phone', 'Role', 'PIN', 'Pay type', 'Rate', 'Start date', 'Notes'],
  Money: ['Date', 'Type', 'Category', 'Amount', 'Party', 'Method', 'Note', 'Added by'],
  Due: ['Client', 'Phone', 'For', 'Amount', 'Due date', 'Status', 'Paid on'],
  Hours: ['Date', 'Name', 'Hours', 'Note'],
  Payroll: ['Month', 'Name', 'Amount', 'Paid on'],
  Listings: ['Property ID', 'Title', 'Purpose', 'Type', 'Area', 'Block / Phase', 'Size', 'Beds', 'Baths', 'Price', 'Status', 'Owner', 'Owner phone', 'Agent', 'Features', 'Added', 'Notes'],
  Visits: ['Date', 'Time', 'Client', 'Phone', 'Property ID', 'Staff', 'Status', 'Notes'],
  Appointments: ['Date', 'Time', 'Client', 'Phone', 'Service', 'Staff', 'Price', 'Status'],
  Clients: ['Name', 'Phone', 'Last visit', 'Usual service', 'Notes'],
};
const KEYCOLS = {
  Team: ['name'], Listings: ['property id'], Due: ['client', 'for', 'due date'], Appointments: ['date', 'time', 'client'],
  Visits: ['date', 'time', 'client', 'property id'], Hours: ['date', 'name'], Payroll: ['month', 'name'],
  Money: ['date', 'type', 'category', 'amount', 'party', 'method', 'note'],
};

const b64u = {
  enc: b => { let s = ''; const u = new Uint8Array(b); for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); },
  dec: s => { s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; return Uint8Array.from(atob(s), c => c.charCodeAt(0)); },
};

// ---------------- local data ----------------
let db = load();
function blank() { return { sheets: {}, tomb: {}, cfg: {}, group: null, dev: 'web-' + Math.random().toString(36).slice(2, 10), peers: {}, lastId: '', heard: 0 }; }
function load() {
  try { const d = JSON.parse(localStorage.getItem(LS) || 'null'); if (d && d.sheets) return { ...blank(), ...d }; } catch {}
  return blank();
}
let saveT = null;
function save() { clearTimeout(saveT); saveT = setTimeout(() => { try { localStorage.setItem(LS, JSON.stringify(db)); } catch (e) { console.warn('biz save', e); } }, 150); }
function saveNow() { clearTimeout(saveT); try { localStorage.setItem(LS, JSON.stringify(db)); } catch {} }

const listeners = new Set();
/** Called whenever data changes (from this device or another). */
export function onChange(fn) { listeners.add(fn); return () => listeners.delete(fn); }
const emit = what => listeners.forEach(f => { try { f(what); } catch (e) { console.warn(e); } });

// ---------------- keys (identical to BizSync.swift) ----------------
const low = v => String(v ?? '').trim().toLowerCase();
function get(r, c) { for (const k in r) if (k.toLowerCase() === c) return low(r[k]); return ''; }
function whole(r) { return 'r|' + Object.keys(r).sort((a, b) => a < b ? -1 : a > b ? 1 : 0).map(k => low(r[k])).filter(Boolean).join('|'); }
export function rowKey(sheet, r) {
  if (sheet === 'Leads' || sheet === 'Clients') {
    const d = get(r, 'phone').replace(/[^0-9]/g, '');
    if (d.length >= 9) return 'p' + d.slice(-9);
    const n = get(r, 'name');
    return n ? 'n' + n : whole(r);
  }
  const parts = (KEYCOLS[sheet] || []).map(c => get(r, c));
  return parts.every(p => !p) ? whole(r) : 'k|' + parts.join('|');
}
const clean = r => { const o = {}; for (const k in r) { const v = r[k] == null ? '' : String(r[k]); if (v.trim()) o[k] = v; } return o; };
const now = () => Date.now();

// ---------------- reading ----------------
/** [{k, r}] for a sheet, newest first-ish (insertion order). */
export function rows(sheet) {
  const s = db.sheets[sheet] || {};
  return Object.entries(s).map(([k, v]) => ({ k, r: v.r, at: v.at }));
}
export const cfg = k => db.cfg[k]?.v ?? '';
export const linked = () => !!db.group;
export const peers = () => db.peers;
export const deviceId = () => db.dev;

// ---------------- writing (this device) ----------------
const pending = new Map();   // sheet → Map(k → op)
let cfgPending = {};
let flushT = null;
function queue(sheet, op) {
  if (!pending.has(sheet)) pending.set(sheet, new Map());
  pending.get(sheet).set(op.k, op);
  clearTimeout(flushT); flushT = setTimeout(flush, 1500);
}

/** Adds or updates a row. Pass the old key when editing (its key may change, e.g. a new phone number). */
export function put(sheet, row, oldKey) {
  const r = clean(row), t = now();
  let k = rowKey(sheet, r);
  const s = db.sheets[sheet] ||= {};
  if (oldKey && oldKey.replace(/#\d+$/, '') === k) k = oldKey;          // same row, same key
  else {
    if (oldKey) del(sheet, oldKey, t);                                    // its key changed (e.g. new phone number)
    if (s[k]) { let n = 2; while (s[`${k}#${n}`]) n++; k = `${k}#${n}`; } // looks like another row — keep both
  }
  s[k] = { r, at: t };
  if (db.tomb[sheet]) delete db.tomb[sheet][k];
  queue(sheet, { k, at: t, r });
  save(); emit(sheet);
  return k;
}
export function del(sheet, k, t = now()) {
  const s = db.sheets[sheet] || {};
  if (!s[k]) return;
  delete s[k];
  (db.tomb[sheet] ||= {})[k] = t;
  queue(sheet, { k, at: t, r: null });
  save(); emit(sheet);
}
export function setCfg(k, v) {
  v = String(v ?? '');
  if (db.cfg[k]?.v === v) return;
  const t = now();
  db.cfg[k] = { v, at: t };
  cfgPending[k] = { v, at: t };
  clearTimeout(flushT); flushT = setTimeout(flush, 1500);
  save(); emit('cfg');
}

// ---------------- applying (other devices) ----------------
function apply(sheet, ops) {
  const s = db.sheets[sheet] ||= {}, tomb = db.tomb[sheet] ||= {};
  let n = 0;
  for (const op of ops || []) {
    if (!op || typeof op.k !== 'string') continue;
    const mine = Math.max(s[op.k]?.at || 0, tomb[op.k] || 0);
    if (!(op.at > mine)) continue;
    if (op.r && typeof op.r === 'object') { s[op.k] = { r: clean(op.r), at: op.at }; delete tomb[op.k]; }
    else { delete s[op.k]; tomb[op.k] = op.at; }
    n++;
  }
  return n;
}
function applyCfg(c) {
  let n = 0;
  for (const k in c || {}) {
    const e = c[k];
    if (!e || typeof e.v !== 'string' || !(e.at > (db.cfg[k]?.at || 0))) continue;
    db.cfg[k] = { v: e.v, at: e.at }; n++;
  }
  return n;
}

// ---------------- relay + encryption ----------------
let keyCache = null;
async function key() {
  const k = db.group.key;
  if (keyCache?.k !== k) keyCache = { k, c: await crypto.subtle.importKey('raw', b64u.dec(k), 'AES-GCM', false, ['encrypt', 'decrypt']) };
  return keyCache.c;
}
async function deflate(bytes) {
  if (!('CompressionStream' in window)) return null;
  try { return new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new CompressionStream('deflate-raw'))).arrayBuffer()); } catch { return null; }
}
async function inflate(bytes) {
  return new Uint8Array(await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('deflate-raw'))).arrayBuffer());
}
export function deviceName() {
  const ua = navigator.userAgent;
  if (window.SparrowDesktop) return /Windows/.test(ua) ? 'Windows PC' : 'Computer';
  const m = ua.match(/Android [\d.]+; ([^;)]+?)(?: Build|\))/);
  if (m && !/^K$/.test(m[1])) return m[1].trim();
  if (/iPad/.test(ua)) return 'iPad';
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/Android/.test(ua)) return /Mobile/.test(ua) ? 'Android phone' : 'Android tablet';
  return 'Browser';
}
async function seal(obj) {
  const json = new TextEncoder().encode(JSON.stringify({ v: 1, from: db.dev, dev: deviceName(), id: crypto.randomUUID?.() || String(now()) + Math.random(), at: now(), ...obj }));
  const z = await deflate(json);
  const plain = z && z.length < json.length ? concat([1], z) : concat([0], json);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(), plain));
  return b64u.enc(concat(iv, ct));
}
function concat(a, b) { const o = new Uint8Array(a.length + b.length); o.set(a); o.set(b, a.length); return o; }
async function open(s) {
  try {
    const d = b64u.dec(String(s).trim());
    const p = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: d.slice(0, 12) }, await key(), d.slice(12)));
    const body = p[0] === 1 ? await inflate(p.slice(1)) : p.slice(1);
    return JSON.parse(new TextDecoder().decode(body));
  } catch { return null; }
}
async function post(obj) {
  if (!db.group) return false;
  try { const r = await fetch(`${RELAY}/${db.group.topic}-biz`, { method: 'POST', body: await seal(obj) }); return r.ok; } catch { return false; }
}
async function sendOps(sheet, ops) {
  if (!ops.length) return true;
  const body = await seal({ t: 'ops', sheet, ops });
  if (body.length > 3700 && ops.length > 1) { const h = ops.length >> 1; const a = await sendOps(sheet, ops.slice(0, h)); const b = await sendOps(sheet, ops.slice(h)); return a && b; }
  return post({ t: 'ops', sheet, ops });
}
let flushing = false;
async function flush() {
  if (!db.group) { pending.clear(); cfgPending = {}; return; }
  if (flushing) { clearTimeout(flushT); flushT = setTimeout(flush, 800); return; }
  flushing = true;
  try {
    const batch = [...pending.entries()]; pending.clear();
    let ok = true;
    for (const [sheet, m] of batch) ok = (await sendOps(sheet, [...m.values()])) && ok;
    const c = cfgPending; cfgPending = {};
    if (Object.keys(c).length) ok = (await post({ t: 'cfg', cfg: c })) && ok;
    if (!ok) { db.dirty = true; save(); }               // offline — everything goes out next time we're connected
    if (batch.length || Object.keys(c).length) setStatus({ last: now() });
  } finally { flushing = false; }
}
async function pushAll() {
  const cutoff = now() - 90 * 86400000;
  for (const sheet of SHEETS) {
    const ops = Object.entries(db.sheets[sheet] || {}).map(([k, v]) => ({ k, at: v.at, r: v.r }))
      .concat(Object.entries(db.tomb[sheet] || {}).filter(([, t]) => t > cutoff).map(([k, t]) => ({ k, at: t, r: null })));
    await sendOps(sheet, ops);
  }
  if (Object.keys(db.cfg).length) await post({ t: 'cfg', cfg: db.cfg });
}

// ---------------- listening ----------------
let es = null, seen = [];
export const status = { connected: false, last: 0 };
function setStatus(p) { Object.assign(status, p); emit('status'); }

async function handle(raw) {
  const o = await open(raw);
  if (!o || !o.id || seen.includes(o.id)) return;
  seen.push(o.id); if (seen.length > 400) seen = seen.slice(-300);
  if (!o.from || o.from === db.dev) return;
  db.heard = now();
  db.peers[o.dev || o.from] = now();
  if (o.t === 'hello') {
    setTimeout(pushAll, 200 + Math.random() * 1300);
  } else if (o.t === 'ops' && SHEETS.includes(o.sheet)) {
    if (apply(o.sheet, o.ops)) { save(); emit(o.sheet); setStatus({ last: now() }); }
  } else if (o.t === 'cfg') {
    if (applyCfg(o.cfg)) { save(); emit('cfg'); setStatus({ last: now() }); }
  }
  save(); emit('peers');
}

export function start() {
  if (!db.group || es) return;
  const since = db.lastId || '12h';
  try {
    es = new EventSource(`${RELAY}/${db.group.topic}-biz/sse?since=${encodeURIComponent(since)}`);
  } catch { return; }
  es.onopen = () => setStatus({ connected: true });
  es.onerror = () => setStatus({ connected: false });
  es.onmessage = e => {
    let m; try { m = JSON.parse(e.data); } catch { return; }
    if (m.event !== 'message' || !m.message) return;
    if (m.id) { db.lastId = m.id; save(); }
    handle(m.message);
  };
  // Away longer than the relay keeps things (or brand new)? Ask everyone for everything; otherwise just say hi.
  const stale = now() - (db.heard || 0) > 11 * 3600000;     // decided before the backlog arrives
  setTimeout(async () => {
    if (!(await post({ t: stale ? 'hello' : 'here' }))) return;
    if (stale || db.dirty) { db.dirty = false; save(); await pushAll(); }
  }, 600);
}
export function stop() { es?.close(); es = null; setStatus({ connected: false }); }
// The relay connection sleeps with the app; wake it up when the app comes back.
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && db.group) { stop(); start(); } });

// ---------------- linking ----------------
const APP = 'https://muhammadtalha257.github.io/sparrow/test/';
export function pairingURL() { return db.group ? `${APP}#biz=${db.group.topic}.${db.group.key}` : ''; }
/** Starts a new group with this device's data in it. */
export function create() {
  const r = crypto.getRandomValues(new Uint8Array(15)), k = crypto.getRandomValues(new Uint8Array(32));
  db.group = { topic: 'zb' + b64u.enc(r).replace(/-/g, 'x').replace(/_/g, 'y'), key: b64u.enc(k) };
  db.lastId = ''; db.heard = 0; db.peers = {};
  saveNow(); stop(); start(); emit('status');
  return pairingURL();
}
/** "…#biz=zb….KEY" from a QR code or a pasted link. */
export function join(text) {
  const m = String(text || '').match(/biz=(zb[A-Za-z0-9]{16,})\.([A-Za-z0-9_-]{40,})/);
  if (!m) return false;
  try { if (b64u.dec(m[2]).length !== 32) return false; } catch { return false; }
  db.group = { topic: m[1], key: m[2] }; db.lastId = ''; db.heard = 0; db.peers = {};
  saveNow(); stop(); start(); emit('status');
  return true;
}
export function unlink() { stop(); db.group = null; db.peers = {}; db.lastId = ''; saveNow(); emit('status'); }
export function syncNow() { if (!db.group) return; post({ t: 'hello' }); pushAll(); }

/** Scan a QR code with the camera. */
export async function scan(video, signal) {
  if (!window.jsQR) await new Promise((res, rej) => { const s = document.createElement('script'); s.src = 'lib/jsQR.js'; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
  const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
  video.srcObject = stream; video.setAttribute('playsinline', ''); await video.play();
  const c = document.createElement('canvas'), ctx = c.getContext('2d', { willReadFrequently: true });
  try {
    while (!signal?.aborted) {
      await new Promise(r => setTimeout(r, 150));
      if (!video.videoWidth) continue;
      const w = Math.min(720, video.videoWidth), h = Math.round(video.videoHeight * w / video.videoWidth);
      c.width = w; c.height = h; ctx.drawImage(video, 0, 0, w, h);
      const code = window.jsQR(ctx.getImageData(0, 0, w, h).data, w, h);
      if (code?.data && join(code.data)) return true;
    }
    return false;
  } finally { stream.getTracks().forEach(t => t.stop()); }
}
export async function qrSVG(text) {
  if (!window.qrcode) await new Promise((res, rej) => { const s = document.createElement('script'); s.src = 'lib/qrcode.js'; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
  const q = window.qrcode(0, 'M'); q.addData(text); q.make();
  return q.createSvgTag({ cellSize: 5, margin: 2, scalable: true });
}

// For tests
export const _internal = { apply, applyCfg, db: () => db, reset: () => { db = blank(); saveNow(); } };

if (db.group) start();
