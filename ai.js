// Zuffi's AI. Free options first: Ollama on your computer, or a small model that runs on the phone.
// Or your own key for Claude, ChatGPT, Gemini, Grok, DeepSeek, Mistral, Groq, OpenRouter or Perplexity.
import { ABOUT } from './about.js';
import { store } from './store.js';
import { daySummary, fmtTime } from './brain.js';
import * as account from './account.js';

let engine = null, loading = null;

const MODELS = {
  'Qwen2.5-0.5B-Instruct': ['Qwen2.5-0.5B-Instruct-q4f16_1-MLC', 'Qwen2.5-0.5B-Instruct-q4f32_1-MLC'],
  'Llama-3.2-1B-Instruct': ['Llama-3.2-1B-Instruct-q4f16_1-MLC', 'Llama-3.2-1B-Instruct-q4f32_1-MLC'],
  'Qwen2.5-1.5B-Instruct': ['Qwen2.5-1.5B-Instruct-q4f16_1-MLC', 'Qwen2.5-1.5B-Instruct-q4f32_1-MLC'],
  'gemma-2-2b-it': ['gemma-2-2b-it-q4f16_1-MLC', 'gemma-2-2b-it-q4f32_1-MLC'],
};

/** Cloud AIs you can connect with your own key. Most speak the same "OpenAI style" API. */
export const PROVIDERS = {
  groq: { name: 'Groq (very fast, free tier)', url: 'https://api.groq.com/openai/v1/chat/completions', model: 'llama-3.3-70b-versatile', site: 'https://console.groq.com/keys' },
  openrouter: { name: 'OpenRouter (many models, some free)', url: 'https://openrouter.ai/api/v1/chat/completions', model: 'openrouter/auto', site: 'https://openrouter.ai/keys' },
  gemini: { name: 'Google Gemini (free tier)', model: 'gemini-2.5-flash', site: 'https://aistudio.google.com/apikey' },
  openai: { name: 'ChatGPT (OpenAI)', url: 'https://api.openai.com/v1/chat/completions', model: 'gpt-4o-mini', site: 'https://platform.openai.com/api-keys' },
  claude: { name: 'Claude (Anthropic)', model: 'claude-sonnet-5-5', site: 'https://console.anthropic.com/settings/keys' },
  grok: { name: 'Grok (xAI)', url: 'https://api.x.ai/v1/chat/completions', model: 'grok-4', site: 'https://console.x.ai' },
  deepseek: { name: 'DeepSeek', url: 'https://api.deepseek.com/chat/completions', model: 'deepseek-chat', site: 'https://platform.deepseek.com/api_keys' },
  mistral: { name: 'Mistral', url: 'https://api.mistral.ai/v1/chat/completions', model: 'mistral-small-latest', site: 'https://console.mistral.ai/api-keys' },
  perplexity: { name: 'Perplexity (answers with web search)', url: 'https://api.perplexity.ai/chat/completions', model: 'sonar', site: 'https://www.perplexity.ai/settings/api' },
};

export async function deviceSupport() {
  if (!('gpu' in navigator)) return { ok: false, why: 'This device has no WebGPU, so the built-in AI can’t run here. Use Ollama on a computer, or add a key.' };
  try {
    const a = await navigator.gpu.requestAdapter();
    if (!a) return { ok: false, why: "This device's graphics chip isn't supported for on-device AI." };
    return { ok: true, f16: a.features.has('shader-f16') };
  } catch { return { ok: false, why: 'On-device AI is not available here.' }; }
}
export function aiReady() { return !!engine || hasKey() || !!window.SparrowDesktop || account.isPaid(); }
export const hasKey = () => Object.values(store.settings.keys || {}).some(Boolean);

const modelId = (sup) => { const ids = MODELS[store.settings.model] || MODELS['Qwen2.5-0.5B-Instruct']; return sup.f16 ? ids[0] : ids[1]; };
/** Is the on-device model really saved on this phone? (iPhone can clear website storage; old app updates also did.) */
export async function localDownloaded() {
  try {
    const sup = await deviceSupport(); if (!sup.ok) return false;
    const webllm = await import('./lib/web-llm.js');
    return await webllm.hasModelInCache(modelId(sup));
  } catch { return false; }
}
function friendly(e) {
  const m = String(e?.message || e || '');
  if (/quota|QuotaExceeded|storage/i.test(m)) return 'Not enough space for the AI on this device. Free some space, or choose the “Fast” model, then try again.';
  if (/device.*lost|out of memory|OOM|memory/i.test(m)) return 'The phone ran out of memory for this model. Choose the “Fast” model and try again.';
  if (/fetch|network|Load failed|NetworkError/i.test(m)) return 'The download stopped (internet dropped or the app went to the background). Tap Try again — it carries on where it stopped.';
  return m || 'Something went wrong — tap Try again.';
}
export async function loadLocal(onProgress) {
  if (engine) return engine;
  if (loading) return loading;
  loading = (async () => {
    const sup = await deviceSupport();
    if (!sup.ok) throw new Error(sup.why);
    try { await navigator.storage?.persist?.(); } catch {}          // ask the phone to keep the model
    const webllm = await import('./lib/web-llm.js');
    try {
      engine = await webllm.CreateMLCEngine(modelId(sup), { initProgressCallback: r => onProgress?.(r.progress ?? 0, r.text ?? '') });
    } catch (e) { store.settings.aiReady = false; store.save(); throw new Error(friendly(e)); }
    store.settings.aiReady = true; store.save();
    return engine;
  })();
  try { return await loading; } finally { loading = null; }
}

/** Ollama models installed on this computer (desktop app only). */
export async function ollamaModels() {
  const D = window.SparrowDesktop; if (!D) return [];
  try {
    const list = await D.ollama('models');
    const pref = ['llama3.2', 'qwen2.5', 'gemma3', 'qwen3', 'phi3', 'mistral', 'llama3.1'];
    return list.sort((a, b) => (pref.findIndex(p => a.startsWith(p)) + 99) % 99 - (pref.findIndex(p => b.startsWith(p)) + 99) % 99);
  } catch { return []; }
}

function systemPrompt(extra = '') {
  const s = store.settings;
  // Always answer in the language (and script) the person used: Urdu, Roman Urdu, Hindi, Punjabi, Spanish, French, Portuguese…
  const langNote = ` Detect the language of the user's latest message and reply in that SAME language and script: Urdu script → Urdu script; Roman Urdu ("kia kar rahe ho") → Roman Urdu; Hindi → Hindi; Punjabi → Punjabi; Spanish, French, Brazilian Portuguese, Arabic, Turkish → the same; English → English. If they mix languages, mix the same way.${s.lang && s.lang !== 'en' ? ` If unsure, use ${{ ur: 'Urdu', hi: 'Hindi', pa: 'Punjabi', ar: 'Arabic' }[s.lang] || 'English'}.` : ''} If asked to translate, give the translation clearly.`;
  return `You are Zuffi, a friendly, smart little assistant on the user's ${window.SparrowDesktop ? 'computer' : 'phone'}.${s.name ? ` The user's name is ${s.name}.` : ''}${window.zuffiProfileLine?.() || ''}${langNote}
Be clear and concise (2–6 sentences unless asked for more). Plain text, no markdown symbols like ** or ##.
${ABOUT}
It is now ${new Date().toLocaleString()}. ${daySummary(new Date(), true)}
Today's items: ${store.onDay(new Date()).map(i => `${i.title} at ${fmtTime(i.when)}`).join('; ') || 'none'}.
Open tasks: ${store.openTasks().slice(0, 15).map(i => i.title).join('; ') || 'none'}.${extra}`;
}
// Only real conversation goes to the AI — not commands like "open Spotify" and their replies
// (a small model would otherwise just repeat "Opening Spotify…").
function history() { return store.chat.filter(m => m.text && !m.cmd).slice(-10).map(m => ({ role: m.role === 'me' ? 'user' : 'assistant', content: m.text })); }

// Network: the desktop and Android apps send requests natively (no browser CORS limits).
let reqId = 0; const pending = new Map();
window.addEventListener('sparrow-http', e => { const p = pending.get(e.detail.id); if (p) { pending.delete(e.detail.id); p(e.detail); } });
async function post(url, body, headers) {
  const D = window.SparrowDesktop, N = window.SparrowNative;
  let status, text;
  if (window.SparrowHost === 'mac') ({ status, text } = await window.SparrowMac.call('http', { url, headers: headers || {}, body: JSON.stringify(body) }));
  else if (D?.http) ({ status, text } = await D.http(url, headers, JSON.stringify(body)));
  else if (N?.httpPost) {
    const id = ++reqId;
    const res = await new Promise(r => { pending.set(id, r); N.httpPost(id, url, JSON.stringify({ 'Content-Type': 'application/json', ...headers }), JSON.stringify(body)); });
    status = res.status; text = res.body;
  } else {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
    status = r.status; text = await r.text();
  }
  let j = {}; try { j = JSON.parse(text); } catch {}
  if (status < 200 || status >= 300) {
    const msg = j.error?.message || j.error || j.message || `HTTP ${status}`;
    throw new Error(status === 401 || status === 403 ? `${msg} — check the key in Settings.` : String(msg));
  }
  try { trackUsage(url, body?.model || '', j); } catch {}
  return j;
}

// ---- Your own AI keys: how many tokens you used this month and roughly what it cost ----
// Prices are approximate list prices in US dollars per million tokens (input, output); the AI
// company's own bill is the real number. OpenRouter tells us the exact cost itself.
const PRICE = [
  [/anthropic/, m => /opus/.test(m) ? [15, 75] : /haiku/.test(m) ? [1, 5] : [3, 15]],
  [/openai\.com/, m => /mini|nano/.test(m) ? [0.15, 0.6] : [2.5, 10]],
  [/groq/, () => [0.59, 0.79]], [/googleapis/, m => /pro/.test(m) ? [1.25, 10] : [0.3, 2.5]],
  [/x\.ai/, () => [3, 15]], [/deepseek/, () => [0.27, 1.1]], [/mistral/, () => [0.4, 2]], [/perplexity/, () => [1, 1]], [/openrouter/, () => [0, 0]],
];
const NAMES = [[/anthropic/, 'Claude'], [/openai\.com/, 'ChatGPT'], [/groq/, 'Groq'], [/googleapis/, 'Gemini'], [/x\.ai/, 'Grok'], [/deepseek/, 'DeepSeek'], [/mistral/, 'Mistral'], [/perplexity/, 'Perplexity'], [/openrouter/, 'OpenRouter']];
const UKEY = 'zuffiAIUsage';
function trackUsage(url, model, j) {
  const name = NAMES.find(([re]) => re.test(url))?.[1]; if (!name) return;           // only AI companies (not Zuffi's own server)
  const u = j.usage || {}, g = j.usageMetadata || {};
  const inT = u.prompt_tokens ?? u.input_tokens ?? g.promptTokenCount ?? 0, outT = u.completion_tokens ?? u.output_tokens ?? g.candidatesTokenCount ?? 0;
  const price = PRICE.find(([re]) => re.test(url))?.[1](model || '') || [0, 0];
  const cost = typeof u.cost === 'number' ? u.cost : (inT * price[0] + outT * price[1]) / 1e6;
  const month = new Date().toISOString().slice(0, 7);
  let all = {}; try { all = JSON.parse(localStorage.getItem(UKEY) || '{}'); } catch {}
  if (all.month !== month) all = { month, p: {} };
  const r = all.p[name] || (all.p[name] = { req: 0, in: 0, out: 0, cost: 0 });
  r.req++; r.in += inT; r.out += outT; r.cost += cost;
  try { localStorage.setItem(UKEY, JSON.stringify(all)); } catch {}
  document.dispatchEvent(new CustomEvent('zuffi-usage'));
  try { window.SparrowHost === 'mac' && window.SparrowMac?.post('usage', usageSummary()); } catch {}
}
/** This month with your own keys: {month, tokens, cost, req, byProvider:{name:{req,in,out,cost}}}. */
export function usageSummary() {
  let all = {}; try { all = JSON.parse(localStorage.getItem(UKEY) || '{}'); } catch {}
  const month = new Date().toISOString().slice(0, 7), p = all.month === month ? all.p || {} : {};
  const v = Object.values(p);
  return { month, req: v.reduce((a, r) => a + r.req, 0), tokens: v.reduce((a, r) => a + r.in + r.out, 0), cost: v.reduce((a, r) => a + r.cost, 0), byProvider: p };
}
window.zuffiUsage = usageSummary;

async function newestGemini(key) {
  try {
    const r = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200', { headers: { 'x-goog-api-key': key } });
    const names = ((await r.json()).models || []).filter(m => (m.supportedGenerationMethods || []).includes('generateContent'))
      .map(m => m.name.replace('models/', '')).filter(n => !/image|tts|embedding|live|audio/.test(n));
    const ver = n => parseFloat(n.split('-')[1]) || 0;
    const stable = names.filter(n => !/preview|exp/.test(n));
    for (const pool of [stable, names]) {
      const f = pool.filter(n => n.includes('flash') && !n.includes('lite')).sort((a, b) => ver(b) - ver(a))[0] || pool.filter(n => n.includes('flash')).sort((a, b) => ver(b) - ver(a))[0];
      if (f) return f;
    }
    return names.sort((a, b) => ver(b) - ver(a))[0] || null;
  } catch { return null; }
}

async function callProvider(p, key, messages, maxTokens = 1200) {
  const model = store.settings.models?.[p] || PROVIDERS[p].model;
  if (p === 'gemini') {
    const contents = messages.slice(1).map(m => ({ role: m.role === 'assistant' ? 'model' : 'user', parts: [{ text: m.content }] }));
    const body = { system_instruction: { parts: [{ text: messages[0].content }] }, contents };
    const run = m => post(`https://generativelanguage.googleapis.com/v1beta/models/${m}:generateContent`, body, { 'x-goog-api-key': key });
    let j;
    try { j = await run(store.settings.models?.gemini || store.settings.geminiAuto || model); }
    catch (e) {
      if (!/model|not found|no longer|deprecat|404/i.test(e.message)) throw e;
      const pick = await newestGemini(key); if (!pick) throw e;   // Google retired it — use the newest one this key can use
      store.settings.geminiAuto = pick; store.save();
      j = await run(pick);
    }
    return (j.candidates?.[0]?.content?.parts || []).map(x => x.text || '').join('').trim();
  }
  if (p === 'claude') {
    const j = await post('https://api.anthropic.com/v1/messages', { model, max_tokens: maxTokens, system: messages[0].content, messages: messages.slice(1) },
      { 'x-api-key': key, 'anthropic-version': '2023-06-01', 'anthropic-dangerous-direct-browser-access': 'true' });
    return (j.content || []).filter(b => b.type === 'text').map(b => b.text).join('').trim();
  }
  const extra = p === 'openrouter' ? { 'HTTP-Referer': 'https://lisansystems.com', 'X-Title': 'Zuffi' } : {};
  const j = await post(PROVIDERS[p].url, { model, messages, temperature: 0.6 }, { Authorization: 'Bearer ' + key, ...extra });
  return j.choices?.[0]?.message?.content?.trim() || '';
}

/** Which AIs can answer right now, best first. */
async function order() {
  const s = store.settings, k = s.keys || {}, out = [];
  const keyed = Object.keys(PROVIDERS).filter(p => k[p]);
  // Built-in AI (Pro / Business / trial) only if they want it: their choice in Settings → AI,
  // or automatically when they haven't added a key of their own.
  const builtIn = account.isPaid() && (s.aiSource === 'zuffi' || (s.aiSource !== 'own' && !keyed.length));
  if (builtIn) out.push('zuffi');
  if (s.provider && s.provider !== 'auto') out.push(s.provider);
  if (window.SparrowDesktop && (await ollamaModels()).length) out.push('ollama');
  out.push(...keyed);
  if (engine || s.aiReady) out.push('local');
  return [...new Set(out)];
}

/**
 * Answer a question. opts: { context: extra text (e.g. from your files), onToken }.
 * Returns { text, source }.
 */
export async function ask(question, onToken, opts = {}) {
  const extra = opts.context ? `\n\nUse this information from the user's files to answer. If the answer isn't there, say so.\n<files>\n${opts.context}\n</files>` : '';
  // opts.system replaces Zuffi's chatty persona (used for structured jobs: CV analysis, cover letters, JSON).
  const messages = [{ role: 'system', content: opts.system ? opts.system + extra : systemPrompt(extra) }, ...(opts.noHistory ? [] : history()), { role: 'user', content: question }];
  const tried = [];
  for (const p of await order()) {
    try {
      if (p === 'ollama') {
        const list = await ollamaModels();
        const model = store.settings.ollamaModel && list.includes(store.settings.ollamaModel) ? store.settings.ollamaModel : list[0];
        const text = await window.SparrowDesktop.ollama('chat', { model, messages, stream: false, options: { num_ctx: opts.context ? 8192 : 4096 } });
        return { text: text.trim(), source: 'Ollama · ' + model };
      }
      if (p === 'local') {
        if (!engine) await loadLocal((p, txt) => opts.onStatus?.(p >= 1 ? '' : `Getting the free AI ready… ${Math.round(p * 100)}%`));
        let text = '';
        const stream = await engine.chat.completions.create({ messages, stream: true, temperature: 0.6, max_tokens: Math.min(opts.maxTokens || 500, 1500) });
        for await (const chunk of stream) { text += chunk.choices[0]?.delta?.content || ''; onToken?.(text); }
        return { text: text.trim(), source: 'on-device AI' };
      }
      if (p === 'zuffi') {
        const text = await account.ai(messages, Math.min(opts.maxTokens || 900, 1500));
        onToken?.(text);
        return { text: text.trim(), source: 'Zuffi AI' };
      }
      const key = store.settings.keys?.[p];
      if (!key || !PROVIDERS[p]) continue;
      return { text: await callProvider(p, key, messages, opts.maxTokens || 1200), source: PROVIDERS[p].name.split(' (')[0] };
    } catch (e) { tried.push(`${p}: ${e.message}`); }
  }
  if (tried.length) throw new Error(tried[tried.length - 1]);
  throw new Error('NO_AI');
}
