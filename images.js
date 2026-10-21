// Make a picture from a sentence — with whichever AI you have: Ollama picture models on your computer (offline),
// OpenAI, Google Gemini, xAI Grok, Together (FLUX), Stability AI or OpenRouter. Returns PNG/JPEG bytes.
import { store } from './store.js';

const b64ToBytes = b => Uint8Array.from(atob(String(b).replace(/^data:[^,]+,/, '')), c => c.charCodeAt(0));
const OLLAMA_IMG = /z-image|flux|stable-diffusion|sdxl|image-gen|qwen-image/i;

export const MAKERS = {
  ollama: 'Ollama on this computer (offline)', openai: 'OpenAI', gemini: 'Google Gemini', grok: 'xAI Grok',
  together: 'Together (FLUX)', stability: 'Stability AI', openrouter: 'OpenRouter',
  free: 'Free picture maker (Pollinations, no key — your description is sent to pollinations.ai)',
};

async function ollamaImageModel() {
  try {
    const D = window.SparrowDesktop;
    const names = D ? await D.ollama('allmodels') : ((await (await fetch('http://127.0.0.1:11434/api/tags')).json()).models || []).map(m => m.name);
    return names.find(n => OLLAMA_IMG.test(n)) || null;
  } catch { return null; }
}
/** Which picture makers you can use right now, best first. */
export async function available() {
  const k = { ...(window.zuffiMacKeys || {}), ...(store.settings.keys || {}) }, out = [];
  if (await ollamaImageModel()) out.push('ollama');
  for (const p of ['openai', 'gemini', 'grok', 'together', 'stability', 'openrouter']) if (k[p]) out.push(p);
  if (store.settings.freeImages !== false) out.push('free');   // always works, no key needed
  const pref = store.settings.imageMaker; if (pref && out.includes(pref)) out.sort((a, b) => (b === pref) - (a === pref));
  return out;
}

const SIZE = { square: [1024, 1024], portrait: [1024, 1536], landscape: [1536, 1024] };
async function json(url, body, headers) {
  const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error?.message || j.message || j.error || ('HTTP ' + r.status));
  return j;
}

async function makeWith(p, prompt, shape) {
  const k = { ...(window.zuffiMacKeys || {}), ...(store.settings.keys || {}) }, [w, h] = SIZE[shape] || SIZE.square;
  if (p === 'ollama') {
    const model = await ollamaImageModel(); if (!model) throw new Error('No picture model in Ollama');
    const body = { model, prompt, width: w, height: h };
    const D = window.SparrowDesktop;
    const b64 = D ? await D.ollama('image', body) : await (async () => { const j = await json('http://127.0.0.1:11434/api/generate', { stream: false, ...body }, {}); return j.image || (j.images || [])[0]; })();
    if (!b64) throw new Error('Ollama returned no picture'); return b64ToBytes(b64);
  }
  if (p === 'openai') {
    const j = await json('https://api.openai.com/v1/images/generations', { model: store.settings.models?.openaiImage || 'gpt-image-1', prompt, size: `${w}x${h}`, n: 1 }, { Authorization: 'Bearer ' + k.openai });
    const d = j.data?.[0]; if (d?.b64_json) return b64ToBytes(d.b64_json); if (d?.url) return new Uint8Array(await (await fetch(d.url)).arrayBuffer());
    throw new Error('No picture');
  }
  if (p === 'gemini') {
    let model = store.settings.models?.geminiImage;
    if (!model) {   // the newest Gemini model that can draw
      const list = ((await (await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200', { headers: { 'x-goog-api-key': k.gemini } })).json()).models || []).map(m => m.name.replace('models/', ''));
      model = list.filter(n => /image/.test(n) && /gemini/.test(n) && !/imagen/.test(n)).sort().reverse()[0] || 'gemini-2.5-flash-image';
      store.settings.models = { ...(store.settings.models || {}), geminiImage: model }; store.save();
    }
    const j = await json(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      contents: [{ role: 'user', parts: [{ text: `${prompt}\n(${shape} picture)` }] }], generationConfig: { responseModalities: ['IMAGE', 'TEXT'] } }, { 'x-goog-api-key': k.gemini });
    const part = (j.candidates?.[0]?.content?.parts || []).find(x => x.inlineData || x.inline_data);
    if (!part) throw new Error('Gemini didn’t return a picture'); return b64ToBytes((part.inlineData || part.inline_data).data);
  }
  if (p === 'grok') {
    const j = await json('https://api.x.ai/v1/images/generations', { model: store.settings.models?.grokImage || 'grok-2-image', prompt, n: 1, response_format: 'b64_json' }, { Authorization: 'Bearer ' + k.grok });
    return b64ToBytes(j.data?.[0]?.b64_json || '');
  }
  if (p === 'together') {
    const j = await json('https://api.together.xyz/v1/images/generations', { model: store.settings.models?.togetherImage || 'black-forest-labs/FLUX.1-schnell', prompt, width: w, height: h, steps: 4, n: 1, response_format: 'b64_json' }, { Authorization: 'Bearer ' + k.together });
    const d = j.data?.[0]; if (d?.b64_json) return b64ToBytes(d.b64_json); if (d?.url) return new Uint8Array(await (await fetch(d.url)).arrayBuffer());
    throw new Error('No picture');
  }
  if (p === 'stability') {
    const fd = new FormData(); fd.append('prompt', prompt); fd.append('output_format', 'png'); fd.append('aspect_ratio', shape === 'portrait' ? '2:3' : shape === 'landscape' ? '3:2' : '1:1');
    const r = await fetch('https://api.stability.ai/v2beta/stable-image/generate/core', { method: 'POST', headers: { Authorization: 'Bearer ' + k.stability, Accept: 'image/*' }, body: fd });
    if (!r.ok) throw new Error('Stability ' + r.status); return new Uint8Array(await r.arrayBuffer());
  }
  if (p === 'openrouter') {
    const j = await json('https://openrouter.ai/api/v1/chat/completions', { model: store.settings.models?.openrouterImage || 'google/gemini-2.5-flash-image', modalities: ['image', 'text'], messages: [{ role: 'user', content: `${prompt} (${shape} picture)` }] },
      { Authorization: 'Bearer ' + k.openrouter, 'HTTP-Referer': 'https://lisansystems.com', 'X-Title': 'Zuffi' });
    const url = j.choices?.[0]?.message?.images?.[0]?.image_url?.url; if (!url) throw new Error('No picture'); return b64ToBytes(url);
  }
  if (p === 'free') {
    // Pollinations (free, no key): FLUX, a random seed so each try is new; "enhance" makes the description richer.
    const seed = Math.floor(Math.random() * 1e9);
    const url = `https://image.pollinations.ai/prompt/${encodeURIComponent(prompt + ', high detail, realistic lighting')}?width=${w}&height=${h}&model=flux&nologo=true&enhance=true&seed=${seed}`;
    const ctl = new AbortController(); const tm = setTimeout(() => ctl.abort(), 90000);
    try {
      const r = await fetch(url, { signal: ctl.signal });
      if (!r.ok) throw new Error(r.status === 429 ? 'The free picture maker is busy — try again in a few seconds' : 'Free picture maker ' + r.status);
      return new Uint8Array(await r.arrayBuffer());
    } finally { clearTimeout(tm); }
  }
  throw new Error('Unknown picture maker');
}

/** prompt → { bytes, maker }. Tries your preferred maker, then the others. */
export async function make(prompt, { shape = 'square', maker } = {}) {
  const list = maker ? [maker] : await available();
  if (!list.length) throw new Error('NO_MAKER');
  let last;
  for (const p of list) { try { return { bytes: await makeWith(p, prompt, shape), maker: p }; } catch (e) { last = e; } }
  throw last || new Error('Couldn’t make the picture');
}

/** "make a picture of…", "draw…", "create an image…", "design a poster…" → the description, or null */
export function wantsImage(text) {
  const m = String(text).match(/^(?:zuffi,?\s*)?(?:please\s+)?(?:make|create|generate|draw|design|paint)\s+(?:me\s+)?(?:an?\s+|the\s+)?(image|picture|photo|poster|flyer|drawing|illustration|logo|banner|social media post|instagram post|post|graphic)\s*((?:of|for|about|showing|with)?\s*.+)$/i)
    || String(text).match(/^(?:zuffi,?\s*)?draw\s+(.+)$/i);
  if (!m) return null;
  if (m.length > 2) return (/^(image|picture|photo)$/i.test(m[1]) ? m[2].replace(/^(of|showing|with)\s+/i, '') : `${m[1]} ${m[2]}`).trim();
  return m[1].trim();
}
