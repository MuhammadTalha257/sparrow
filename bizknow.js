// WhatsApp agent knowledge: the business gives Zuffi its details — typed, or by uploading files (price list, menu,
// brochure, property list, FAQ, PDF/Word/Excel/CSV/text). The AI reads them and writes one clear "business brief";
// the owner checks it, and from then on WhatsApp replies (phone autopilot, Mac inbox, server) use only those facts,
// in the language and script the customer wrote in.
import { ask } from './ai.js';
import { store } from './store.js';
import * as mem from './memory.js';
import * as bs from './bizsync.js';

const S = () => store.settings;
const wb = () => S().waBiz || (S().waBiz = { name: '', info: '', today: '', todayDate: '', leads: false, pilot: false });
const today = () => new Date().toISOString().slice(0, 10);

/** What Zuffi knows about the business right now (the longest of the copies kept on this device). */
export function brief() {
  const a = String(bs.cfg('info') || ''), b = String(wb().info || '');
  return a.length >= b.length ? a : b;
}
export const todayUpdate = () => (wb().todayDate === today() ? wb().today : '') || '';
export const name = () => bs.cfg('name') || wb().name || S().business?.name || '';

/** Saves the brief everywhere replies are written: this device, the phone autopilot, the Mac, linked devices. */
export function save(text, todayText) {
  const t = String(text || '').trim().slice(0, 12000);
  const w = wb(); w.info = t; if (!w.name) w.name = name();
  if (todayText !== undefined) { w.today = String(todayText || '').trim().slice(0, 500); w.todayDate = today(); try { bs.setCfg('today', w.today); bs.setCfg('todayDate', w.todayDate); } catch {} }
  store.save();
  try { bs.setCfg('info', t); } catch {}
  pushPhone();
  try { if (window.SparrowHost === 'mac') window.SparrowMac?.call('bizinfo', { text: t }); } catch {}
}
/** Android: the WhatsApp autopilot reads these. */
export function pushPhone() {
  const N = window.SparrowNative, b = wb(); if (!N?.setBusiness) return;
  try { N.setBusiness(JSON.stringify({ bizName: b.name || name(), bizInfo: b.info, bizToday: b.todayDate === today() ? b.today : '', bizTodayDate: b.todayDate, waLeads: !!b.leads, waPilot: !!b.pilot, waContactsToo: !!b.contacts, groqKey: S().keys?.groq || '', geminiKey: S().keys?.gemini || '' })); } catch {}
}
export function setPilot(on) { const b = wb(); b.pilot = !!on; if (on) b.leads = true; store.save(); pushPhone(); }

/** Reads uploaded files → plain text (each file trimmed so one huge sheet can't crowd out the rest). */
export async function readFiles(files) {
  const out = [];
  for (const f of files) {
    let t = ''; try { t = await mem.fileText(f); } catch {}
    out.push({ name: f.name, text: String(t || '').replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim(), size: f.size });
  }
  return out;
}

/**
 * The AI turns everything it was given into one business brief (facts only, no invention).
 * docs: [{name, text}] · typed: what the owner wrote · kind/country help it know what matters.
 */
export async function learn({ docs = [], typed = '', kind = '', country = '' } = {}) {
  const budget = 24000, per = Math.max(3000, Math.floor(budget / Math.max(1, docs.length)));
  const material = [typed && `OWNER WROTE:\n${typed}`, brief() && `ALREADY KNOWN:\n${brief()}`,
    ...docs.filter(d => d.text).map(d => `FILE "${d.name}":\n${d.text.slice(0, per)}`)].filter(Boolean).join('\n\n---\n\n');
  if (!material.trim()) throw new Error('Add a file or type a few lines about your business first.');
  const estate = /real ?estate|estate|property/i.test(kind) || country === 'PK';
  const system = `You build the knowledge sheet a WhatsApp assistant uses to answer customers of ONE business.
From the material, write a clear, complete business brief in English using only facts that are really there. Never invent prices, addresses or promises.
Use these headings when there is something for them (skip empty ones), with short lines or bullet points under each:
BUSINESS (name, what it does, area/location, contact)
HOURS
${estate ? 'PROPERTIES / STOCK (one line per property: type, size e.g. marla/kanal or bedrooms, area/society, price, status — keep every listing)\nPAYMENT (token money, installments, documents, commission)' : 'SERVICES & PRICES (one line each: item — price — duration if given)\nBOOKING (how to book, deposits, cancellations)'}
OFFERS
DELIVERY / AREA COVERED
POLICIES (refunds, payment methods, rules)
FAQ (common question → answer)
HAND OVER TO THE OWNER WHEN (discounts beyond offers, complaints, legal or payment problems, anything not covered)
Keep all numbers exactly as written (currency, units). Plain text only, no markdown symbols like ** or #. Maximum about 900 words.`;
  const r = await ask(material, null, { noHistory: true, system, maxTokens: 2200 });
  return String(r.text || '').replace(/\*\*/g, '').replace(/^#+\s*/gm, '').trim();
}

/** Language of a customer message (for the label in the test chat). The reply itself always follows the customer. */
export function langOf(t) {
  const s = String(t || '');
  if (/[؀-ۿ]/.test(s)) return /[ٹڈڑںےۓھ]/.test(s) ? 'Urdu' : 'Arabic';
  if (/[ऀ-ॿ]/.test(s)) return 'Hindi';
  if (/[਀-੿]/.test(s)) return 'Punjabi';
  if (/[Ѐ-ӿ]/.test(s)) return 'Russian';
  if (/\b(kya|hai|hain|aap|ap|kitna|kitne|kab|kahan|chahiye|mujhe|bhai|plot|marla|kanal|rate|krna|karna|ho ga|hoga|nahi|acha|theek|shukriya)\b/i.test(s) && !/\b(the|is|are|what|how)\b/i.test(s)) return 'Roman Urdu';
  if (/\b(hola|gracias|precio|cuánto|quiero)\b/i.test(s)) return 'Spanish';
  if (/\b(bonjour|merci|prix|combien)\b/i.test(s)) return 'French';
  if (/\b(dzień|cześć|ile|cena|dziękuję|proszę)\b/i.test(s)) return 'Polish';
  return 'English';
}

/** The same rules the phone autopilot and the Mac use — so "Try it" shows exactly what customers would get. */
export async function reply(message, history = []) {
  const facts = brief(), up = todayUpdate(), biz = name();
  const system = `You are the WhatsApp assistant of ${biz || 'a small business'}. You write as the business ("we"). Never give yourself a personal name, never say you are an AI, never invent facts. Reply with one JSON object only.`;
  const prompt = `BUSINESS FACTS (the only facts you may use):
${facts || '(none written yet — greet politely and ask how you can help)'}
${up ? `TODAY'S UPDATE: ${up}` : ''}
${history.length ? 'EARLIER IN THIS CHAT:\n' + history.map(h => `${h.in ? 'Client: ' + h.in : 'Business: ' + h.out}`).join('\n') : ''}
CLIENT'S NEW MESSAGE: ${message}

Write "reply": 1-3 short, natural WhatsApp sentences in EXACTLY the language and script the client used — whatever it is (English, Urdu script, Roman Urdu, Punjabi, Hindi, Arabic, Polish, Bengali, Spanish…). If they mix languages, mix the same way.
Set "needs_human" true ONLY if they bargain or ask for a discount not in today's update, complain, ask for a person or a call, raise payment / refund / legal issues, or the answer isn't in the facts. Then "reply" is a short polite holding message and "why" a 3-6 word reason in English.
JSON: {"reply":"","needs_human":false,"why":""}`;
  const r = await ask(prompt, null, { noHistory: true, system, maxTokens: 400 });
  const txt = String(r.text || ''); const a = txt.indexOf('{'), b = txt.lastIndexOf('}');
  let j = {}; try { j = JSON.parse(txt.slice(a, b + 1)); } catch { j = { reply: txt.trim() }; }
  return { reply: String(j.reply || '').trim(), human: j.needs_human === true || j.needs_human === 'true', why: String(j.why || '').trim(), lang: langOf(message), source: r.source };
}
