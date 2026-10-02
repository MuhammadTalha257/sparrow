// Phone ↔ laptop sync with no account: show QR codes on one device, scan them on the other.
// Large lists also work as a small "sync file" you can AirDrop / share / email to yourself.
import { store } from './store.js';
import { exportMemory, importMemory } from './memory.js';

const loadScript = src => new Promise((res, rej) => {
  if (document.querySelector(`script[data-src="${src}"]`)) return res();
  const s = document.createElement('script'); s.src = src; s.dataset.src = src; s.onload = res; s.onerror = rej; document.head.appendChild(s);
});

async function gzip(str) {
  if (!('CompressionStream' in window)) return 'R' + btoa(unescape(encodeURIComponent(str)));
  const s = new Blob([str]).stream().pipeThrough(new CompressionStream('gzip'));
  const bytes = new Uint8Array(await new Response(s).arrayBuffer());
  let bin = ''; bytes.forEach(b => bin += String.fromCharCode(b));
  return 'G' + btoa(bin);
}
async function gunzip(data) {
  if (data[0] === 'R') return decodeURIComponent(escape(atob(data.slice(1))));
  const bin = atob(data.slice(1)), bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  const s = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Response(s).text();
}

/** Everything worth syncing (never API keys). */
export async function bundle(withMemory = false) {
  const { keys, aiReady, ...settings } = store.settings;
  const data = { v: 1, at: Date.now(), items: store.items, settings: { snippets: settings.snippets, business: settings.business, quick: settings.quick, name: settings.name } };
  if (withMemory) { const m = await exportMemory(); data.memory = { log: m.log.slice(-400).map(({ id, ...r }) => r) }; }
  return gzip(JSON.stringify(data));
}
export async function applyBundle(packed) {
  const data = JSON.parse(await gunzip(packed));
  const r = store.merge(data.items || []);
  const s = data.settings || {};
  if (s.snippets?.length) store.settings.snippets = [...new Map([...(store.settings.snippets || []), ...s.snippets].map(x => [x.name, x])).values()];
  if (s.business?.name && !store.settings.business.name) store.settings.business = { ...store.settings.business, ...s.business };
  if (s.name && !store.settings.name) store.settings.name = s.name;
  store.save();
  if (data.memory) await importMemory(data.memory);
  return r;
}

const CHUNK = 900;
/** QR codes (as SVG strings) for the data, in order. */
export async function qrCodes(packed) {
  await loadScript('lib/qrcode.js');
  const parts = packed.match(new RegExp(`[\\s\\S]{1,${CHUNK}}`, 'g')) || [];
  const id = Math.random().toString(36).slice(2, 6);
  return parts.map((p, i) => {
    const qr = window.qrcode(0, 'L'); qr.addData(`SPW|${id}|${i + 1}|${parts.length}|${p}`); qr.make();
    return qr.createSvgTag({ cellSize: 4, margin: 2, scalable: true });
  });
}

/** Scan with the camera. onProgress(got, total). Resolves with the packed data. */
export async function scan(video, onProgress, signal) {
  await loadScript('lib/jsQR.js');
  const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
  video.srcObject = stream; await video.play();
  const c = document.createElement('canvas'), ctx = c.getContext('2d', { willReadFrequently: true });
  const got = new Map(); let total = 0, sid = null;
  try {
    while (!signal?.aborted) {
      await new Promise(r => setTimeout(r, 120));
      if (!video.videoWidth) continue;
      const w = Math.min(800, video.videoWidth), h = Math.round(video.videoHeight * w / video.videoWidth);
      c.width = w; c.height = h; ctx.drawImage(video, 0, 0, w, h);
      const code = window.jsQR(ctx.getImageData(0, 0, w, h).data, w, h);
      const m = code?.data?.match(/^SPW\|(\w+)\|(\d+)\|(\d+)\|([\s\S]*)$/);
      if (!m) continue;
      if (sid && m[1] !== sid) { got.clear(); }
      sid = m[1]; total = +m[3]; got.set(+m[2], m[4]);
      onProgress?.(got.size, total);
      if (got.size === total) return [...Array(total)].map((_, i) => got.get(i + 1)).join('');
    }
    throw new Error('cancelled');
  } finally { stream.getTracks().forEach(t => t.stop()); }
}
