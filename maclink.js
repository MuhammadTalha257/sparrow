// Control your Mac from Sparrow on the iPhone (or any phone/browser), from anywhere.
// Messages go through the free ntfy.sh relay on a private random channel, end-to-end encrypted
// (AES-GCM) with a key that only your Mac and this phone have — handed over once by a QR code.
import { store } from './store.js';

const RELAY = 'https://ntfy.sh';
const b64u = {
  enc: b => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, ''),
  dec: s => { s = s.replace(/-/g, '+').replace(/_/g, '/'); while (s.length % 4) s += '='; return Uint8Array.from(atob(s), c => c.charCodeAt(0)); },
};

export const linked = () => !!store.settings.macLink?.topic;

/** "…#link=TOPIC.KEY" (from the Mac's QR code) → saved. Returns true if it linked. */
export function takeLink(text) {
  const m = String(text || '').match(/link=(sp[A-Za-z0-9]{20,})\.([A-Za-z0-9_-]{40,})/);
  if (!m) return false;
  try { if (b64u.dec(m[2]).length !== 32) return false; } catch { return false; }
  store.settings.macLink = { topic: m[1], key: m[2], at: Date.now() };
  store.save();
  return true;
}
export function unlink() { delete store.settings.macLink; store.save(); }

let keyCache = null;
async function key() {
  const k = store.settings.macLink.key;
  if (keyCache?.k !== k) keyCache = { k, c: await crypto.subtle.importKey('raw', b64u.dec(k), 'AES-GCM', false, ['encrypt', 'decrypt']) };
  return keyCache.c;
}
async function seal(obj) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(), new TextEncoder().encode(JSON.stringify(obj))));
  const out = new Uint8Array(12 + ct.length); out.set(iv); out.set(ct, 12);
  return b64u.enc(out);
}
async function open(s) {
  try {
    const d = b64u.dec(s.trim());
    const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: d.slice(0, 12) }, await key(), d.slice(12));
    return JSON.parse(new TextDecoder().decode(pt));
  } catch { return null; }
}

/** Sends to the Mac and waits for its answer. Resolves to the answer text, or a friendly "couldn't reach it". */
async function exchange(t, text, waitMs) {
  if (!linked()) return { ok: false, text: 'Link your Mac first: on the Mac, Sparrow Settings → iPhone → Show link code, then scan it.' };
  const { topic } = store.settings.macLink;
  const id = crypto.randomUUID?.() || String(Date.now()) + Math.random();
  const since = Math.floor(Date.now() / 1000) - 2;
  try {
    const r = await fetch(`${RELAY}/${topic}-mac`, { method: 'POST', body: await seal({ t, id, text, at: Date.now() }) });
    if (!r.ok) throw new Error('relay ' + r.status);
  } catch { return { ok: false, text: "I couldn't reach the internet relay. Check this phone's connection." }; }
  const end = Date.now() + waitMs;
  while (Date.now() < end) {
    await new Promise(r => setTimeout(r, 1200));
    try {
      const res = await fetch(`${RELAY}/${topic}-phone/json?poll=1&since=${since}`);
      const lines = (await res.text()).split('\n').filter(Boolean);
      for (const l of lines) {
        let m; try { m = JSON.parse(l); } catch { continue; }
        if (m.event !== 'message' || !m.message) continue;
        const o = await open(m.message);
        if (o?.re === id) return { ok: true, text: o.text || 'Done.' };
      }
    } catch {}
  }
  return { ok: false, text: "Your Mac didn't answer. Make sure it's on and awake, online, with Sparrow open and Settings → iPhone switched on." };
}

// Screen tasks (clicking and typing on the Mac) can take a couple of minutes.
export const send = text => exchange('cmd', text, /\b(screen|click|scroll)\b/i.test(text) ? 180000 : 45000);
export const ping = () => exchange('ping', '', 15000);

/** Is this meant for the Mac? ("lock my mac", "turn off the laptop", "mac pe spotify chalao", "on my computer…") */
export function isForMac(text) {
  return linked() && /\b(mac|macbook|imac|laptop|computer)\b/i.test(text) && !/\b(what is a|buy|price of|how much)\b/i.test(text);
}

/** Scan the Mac's QR code with this phone's camera (inside the app, e.g. from the Home Screen). */
export async function scanLink(video, signal) {
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
      if (code?.data && takeLink(code.data)) return true;
    }
    return false;
  } finally { stream.getTracks().forEach(t => t.stop()); }
}
