// Send to my other device: files, photos, text and links between YOUR devices (Mac, Windows, phone).
//  • devices link once (QR code or a link) → they share a random channel + 256-bit key
//  • everything is end-to-end encrypted with AES-GCM before it leaves the device; the relay (ntfy.sh) only sees noise
//  • files go up as encrypted attachments (up to 15 MB) and expire from the relay after a few hours
const RELAY = 'https://ntfy.sh';
const LS = 'zuffiSend';
export const MAX_FILE = 15 * 1024 * 1024;

const b64u = {
  enc: b => { let s = ''; const u = new Uint8Array(b); for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''); },
  dec: s => { s = String(s).replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; return Uint8Array.from(atob(s), c => c.charCodeAt(0)); },
};
const now = () => Date.now();

let st = load();
function load() { try { const d = JSON.parse(localStorage.getItem(LS) || 'null'); if (d) return d; } catch {} return { group: null, dev: 'd' + Math.random().toString(36).slice(2, 10), inbox: [], peers: {}, lastId: '' }; }
function save() { try { localStorage.setItem(LS, JSON.stringify(st)); } catch {} }

export function deviceName() {
  const ua = navigator.userAgent;
  if (window.SparrowHost === 'mac') return 'Mac';
  if (window.SparrowDesktop) return /Windows/.test(ua) ? 'Windows PC' : 'Computer';
  if (/iPad/.test(ua)) return 'iPad';
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/Android/.test(ua)) return /Mobile/.test(ua) ? 'Android phone' : 'Android tablet';
  return 'Browser';
}
export const linked = () => !!st.group;
export const inbox = () => st.inbox.slice();
export const peers = () => Object.entries(st.peers).filter(([n]) => n !== deviceName()).map(([name, at]) => ({ name, at }));

let K = null;
async function key() { if (!K) K = await crypto.subtle.importKey('raw', b64u.dec(st.group.key), 'AES-GCM', false, ['encrypt', 'decrypt']); return K; }
async function encrypt(bytes) { const iv = crypto.getRandomValues(new Uint8Array(12)); const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(), bytes)); const o = new Uint8Array(12 + ct.length); o.set(iv); o.set(ct, 12); return o; }
async function decrypt(bytes) { return new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: bytes.slice(0, 12) }, await key(), bytes.slice(12))); }
const seal = async obj => b64u.enc(await encrypt(new TextEncoder().encode(JSON.stringify({ from: st.dev, dev: deviceName(), at: now(), id: crypto.randomUUID?.() || String(Math.random()), ...obj }))));
const unseal = async s => { try { return JSON.parse(new TextDecoder().decode(await decrypt(b64u.dec(s)))); } catch { return null; } };
const topic = () => st.group.topic + '-send';

// ---------------- linking ----------------
export function linkCode() { return st.group ? `ZSEND:${st.group.topic}.${st.group.key}` : ''; }
export function create() {
  const r = crypto.getRandomValues(new Uint8Array(15)), k = crypto.getRandomValues(new Uint8Array(32));
  st.group = { topic: 'zs' + b64u.enc(r).replace(/-/g, 'x').replace(/_/g, 'y'), key: b64u.enc(k) };
  st.lastId = ''; st.peers = {}; K = null; save(); restart();
  return linkCode();
}
export function join(text) {
  const m = String(text || '').match(/ZSEND:(zs[A-Za-z0-9]{16,})\.([A-Za-z0-9_-]{40,})/);
  if (!m) return false;
  st.group = { topic: m[1], key: m[2] }; st.lastId = ''; K = null; save(); restart();
  setTimeout(() => post({ t: 'hi' }), 800);
  return true;
}
export function unlink() { stop(); st.group = null; st.peers = {}; K = null; save(); emit({ t: 'status' }); }

// ---------------- sending ----------------
async function post(obj) {
  if (!st.group) return false;
  try { return (await fetch(`${RELAY}/${topic()}`, { method: 'POST', body: await seal(obj) })).ok; } catch { return false; }
}
export async function sendText(text) {
  const t = String(text || '').trim(); if (!t) return false;
  return post({ t: /^https?:\/\/\S+$/.test(t) ? 'link' : 'text', text: t.slice(0, 3000) });
}
/** file: a File/Blob with a name. Returns true when it's on its way. */
export async function sendFile(file) {
  if (!st.group) return false;
  if (file.size > MAX_FILE) throw new Error('Files up to 15 MB for now');
  const enc = await encrypt(new Uint8Array(await file.arrayBuffer()));
  const meta = await seal({ t: 'file', name: file.name || 'file', mime: file.type || 'application/octet-stream', size: file.size });
  try {
    const r = await fetch(`${RELAY}/${topic()}`, { method: 'PUT', body: enc, headers: { Filename: 'z.bin', Message: meta } });
    return r.ok;
  } catch { return false; }
}

// ---------------- receiving ----------------
const listeners = new Set();
export function onEvent(fn) { listeners.add(fn); return () => listeners.delete(fn); }
function emit(e) { listeners.forEach(f => { try { f(e); } catch {} }); }
let es = null, seen = [];
async function handle(m) {
  const o = await unseal(m.message || ''); if (!o || seen.includes(o.id)) return;
  seen.push(o.id); if (seen.length > 200) seen = seen.slice(-150);
  st.peers[o.dev] = now(); save();
  if (o.from === st.dev) return;
  if (o.t === 'hi') { emit({ t: 'peer', dev: o.dev }); post({ t: 'here' }); return; }
  if (o.t === 'here') { emit({ t: 'peer', dev: o.dev }); return; }
  const item = { id: o.id, kind: o.t, from: o.dev, at: o.at, text: o.text, name: o.name, mime: o.mime, size: o.size, url: m.attachment?.url };
  if (st.inbox.some(i => i.id === item.id)) return;
  if (o.t === 'file' && !item.url) return;
  st.inbox = [item, ...st.inbox].slice(0, 30); save();
  emit({ t: 'got', item });
}
/** Downloads + decrypts a received file → { name, bytes, mime }. */
export async function fetchFile(item) {
  const r = await fetch(item.url); if (!r.ok) throw new Error('This file has expired — send it again');
  return { name: item.name, mime: item.mime, bytes: await decrypt(new Uint8Array(await r.arrayBuffer())) };
}
export function forget(id) { st.inbox = st.inbox.filter(i => i.id !== id); save(); }
export function start() {
  if (!st.group || es) return;
  try { es = new EventSource(`${RELAY}/${topic()}/sse?since=${encodeURIComponent(st.lastId || '3h')}`); } catch { return; }
  es.onopen = () => emit({ t: 'status', connected: true });
  es.onerror = () => emit({ t: 'status', connected: false });
  es.onmessage = e => { let m; try { m = JSON.parse(e.data); } catch { return; } if (m.event !== 'message') return; if (m.id) { st.lastId = m.id; save(); } handle(m); };
  setTimeout(() => post({ t: 'here' }), 1200);
}
export function stop() { es?.close(); es = null; }
function restart() { stop(); start(); emit({ t: 'status' }); }
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && st.group) restart(); });
