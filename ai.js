// Sparrow's AI: a free model that runs on the phone (WebLLM / WebGPU), or the person's own key.
import { store } from './store.js';
import { daySummary, fmtTime } from './brain.js';

let engine = null;
let loading = null;

const MODELS = {
  'Qwen2.5-0.5B-Instruct': ['Qwen2.5-0.5B-Instruct-q4f16_1-MLC', 'Qwen2.5-0.5B-Instruct-q4f32_1-MLC'],
  'Llama-3.2-1B-Instruct': ['Llama-3.2-1B-Instruct-q4f16_1-MLC', 'Llama-3.2-1B-Instruct-q4f32_1-MLC'],
  'Qwen2.5-1.5B-Instruct': ['Qwen2.5-1.5B-Instruct-q4f16_1-MLC', 'Qwen2.5-1.5B-Instruct-q4f32_1-MLC'],
  'gemma-2-2b-it': ['gemma-2-2b-it-q4f16_1-MLC', 'gemma-2-2b-it-q4f32_1-MLC'],
};

export async function deviceSupport() {
  if (!('gpu' in navigator)) return { ok: false, why: 'This browser has no WebGPU. Use iOS 26 Safari or a recent Chrome on Android.' };
  try {
    const a = await navigator.gpu.requestAdapter();
    if (!a) return { ok: false, why: "This phone's graphics chip isn't supported for on-device AI." };
    return { ok: true, f16: a.features.has('shader-f16') };
  } catch { return { ok: false, why: 'On-device AI is not available here.' }; }
}

export function aiReady() { return !!engine; }

/** Downloads (first time) and starts the on-device model. onProgress(0..1, text) */
export async function loadLocal(onProgress) {
  if (engine) return engine;
  if (loading) return loading;
  loading = (async () => {
    const sup = await deviceSupport();
    if (!sup.ok) throw new Error(sup.why);
    const webllm = await import('./lib/web-llm.js');
    const ids = MODELS[store.settings.model] || MODELS['Qwen2.5-0.5B-Instruct'];
    const id = sup.f16 ? ids[0] : ids[1];
    engine = await webllm.CreateMLCEngine(id, {
      initProgressCallback: r => onProgress?.(r.progress ?? 0, r.text ?? ''),
    });
    store.settings.aiReady = true; store.save();
    return engine;
  })();
  try { return await loading; } finally { loading = null; }
}

function systemPrompt() {
  const name = store.settings.name ? ` The user's name is ${store.settings.name}.` : '';
  return `You are Sparrow, a friendly, cheerful little AI helper living on the user's phone.${name}
Keep answers short and clear (2–5 sentences unless asked for more). Plain text, no markdown symbols.
It is now ${new Date().toLocaleString()}. ${daySummary(new Date(), true)}
Today's items: ${store.onDay(new Date()).map(i => `${i.title} at ${fmtTime(i.when)}`).join('; ') || 'none'}.
Open tasks: ${store.openTasks().map(i => i.title).join('; ') || 'none'}.`;
}

function history() {
  return store.chat.slice(-10).map(m => ({ role: m.role === 'me' ? 'user' : 'assistant', content: m.text }));
}

/** Answer a question. onToken streams partial text when supported. Returns { text, source }. */
export async function ask(question, onToken) {
  const k = store.settings.keys || {};
  const messages = [{ role: 'system', content: systemPrompt() }, ...history(), { role: 'user', content: question }];

  if (engine || store.settings.aiReady) {
    try {
      if (!engine) await loadLocal();   // cached after the first download — quick
      let text = '';
      const stream = await engine.chat.completions.create({ messages, stream: true, temperature: 0.6, max_tokens: 400 });
      for await (const chunk of stream) {
        text += chunk.choices[0]?.delta?.content || '';
        onToken?.(text);
      }
      return { text: text.trim(), source: 'on-device AI' };
    } catch (e) {
      if (!k.gemini && !k.openai && !k.claude) throw e;
    }
  }
  if (k.gemini) return { text: await gemini(k.gemini, messages), source: 'Gemini' };
  if (k.openai) return { text: await openai(k.openai, messages), source: 'ChatGPT' };
  if (k.claude) return { text: await claude(k.claude, messages), source: 'Claude' };
  throw new Error('NO_AI');
}

async function post(url, body, headers) {
  const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error?.message || `HTTP ${r.status}`);
  return j;
}
async function gemini(key, messages) {
  const sys = messages[0].content;
  const contents = messages.slice(1).map(m => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }));
  const j = await post('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent',
    { system_instruction: { parts: [{ text: sys }] }, contents }, { 'x-goog-api-key': key });
  return (j.candidates?.[0]?.content?.parts || []).map(p => p.text || '').join('').trim();
}
async function openai(key, messages) {
  const j = await post('https://api.openai.com/v1/chat/completions', { model: 'gpt-4o-mini', messages }, { Authorization: 'Bearer ' + key });
  return j.choices?.[0]?.message?.content?.trim() || '';
}
async function claude(key, messages) {
  const j = await post('https://api.anthropic.com/v1/messages', {
    model: 'claude-sonnet-5-5', max_tokens: 800, system: messages[0].content, messages: messages.slice(1),
  }, { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'anthropic-dangerous-direct-browser-access': 'true' });
  return (j.content || []).filter(b => b.type === 'text').map(b => b.text).join('').trim();
}
