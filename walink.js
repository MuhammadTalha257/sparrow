// WhatsApp linked to Zuffi on Windows (the app keeps WhatsApp Web in its own hidden window — see desktop/main.js).
// New messages arrive here instantly: a notification, read out if you like, a lead for the business,
// and with Autopilot a reply in the customer's language, sent in a second or two without touching the screen.
import { store } from './store.js';
import * as bs from './bizsync.js';
import * as bizknow from './bizknow.js';

const S = () => store.settings;
const D = () => window.SparrowDesktop;
export const available = () => !!D()?.wa;
export const recent = [];                 // newest first, kept in memory only
const history = new Map();                // chatId → [{ in } | { out }] for better replies
const held = new Set();                   // holding replies already sent today
let state = 'off';
const listeners = new Set();
export const getState = () => state;
export const onChange = f => { listeners.add(f); return () => listeners.delete(f); };
const emit = () => listeners.forEach(f => { try { f(state); } catch {} });

const digits = s => String(s || '').replace(/\D/g, '');
const now16 = () => new Date().toISOString().slice(0, 16).replace('T', ' ');

function upsertLead(name, phone, text) {
  const rows = bs.rows('Leads');
  const hit = rows.find(({ r }) => (phone && digits(r.Phone).endsWith(digits(phone).slice(-9))) || (!phone && name && String(r.Name || '').toLowerCase() === name.toLowerCase()));
  const row = { ...(hit ? hit.r : { Name: name, Phone: phone ? '+' + digits(phone) : '', Source: 'WhatsApp', Status: 'New', Added: now16().slice(0, 10) }),
    'Last message': text.slice(0, 200), 'Last message at': now16() };
  bs.put('Leads', row, hit?.k);
  return !hit;
}

/** ui: { toast(text), notify(title, body), speak(text), bizOn() } */
export function init(ui) {
  if (!available()) return;
  D().wa.state().then(s => { state = s || 'off'; emit(); }).catch(() => {});
  D().wa.on(async m => {
    if (!m || typeof m !== 'object') return;
    if (m.type === 'state') { const was = state; state = m.state; emit(); if (m.state === 'ready' && was !== 'ready') ui.toast('✅ WhatsApp is linked — new messages arrive instantly.'); return; }
    if (m.type !== 'msg' || m.fromMe || m.isGroup) return;
    const name = m.name || (m.phone ? '+' + m.phone : 'Someone');
    const voice = m.kind === 'ptt' || m.kind === 'audio';
    const text = m.body || (voice ? '🎤 Voice note' : m.kind === 'image' ? '📷 Photo' : `[${m.kind}]`);
    recent.unshift({ chatId: m.chatId, name, phone: m.phone || '', text, at: Date.now() }); recent.length = Math.min(recent.length, 40);
    const h = history.get(m.chatId) || []; h.push({ in: text }); history.set(m.chatId, h.slice(-8));
    ui.notify(`WhatsApp · ${name}`, text.slice(0, 160));
    if (S().waReadAloud) ui.speak(`WhatsApp from ${name}: ${text.slice(0, 200)}`);
    if (!ui.bizOn()) return;
    if (m.saved && !S().waBiz?.contacts) return;   // friends & family in your contacts are left alone
    const isNew = upsertLead(name, m.phone, text);
    if (isNew) ui.toast(`New WhatsApp lead: ${name}`);
    const pilot = S().waBiz?.pilot;
    if (!pilot || voice) return;
    try {
      // 1) instant answer from the business details (no AI, any business); 2) AI; 3) polite holding reply
      const quick = (await import('./bizquick.js')).answer(text, bizknow.brief(), { biz: bizknow.name(), first: isNew, today: bizknow.todayUpdate() });
      if (quick) { const sent = await D().wa.send(m.chatId, quick); if (sent?.ok) { h.push({ out: quick }); history.set(m.chatId, h.slice(-8)); } return; }
      const r = await bizknow.reply(text, h.slice(0, -1));
      if (!r.reply) return;
      if (r.human) {
        // Zuffi doesn't know: the customer still gets a polite holding reply (once a day), and you're told.
        ui.notify(`${name} needs you`, r.why || 'Please answer this one yourself.');
        const k = 'hold|' + m.chatId + new Date().toISOString().slice(0, 10);
        if (held.has(k)) return; held.add(k);
      }
      const sent = await D().wa.send(m.chatId, r.reply);
      if (sent?.ok) { h.push({ out: r.reply }); history.set(m.chatId, h.slice(-8)); }
    } catch {}
  });
}

export const link = () => D()?.wa.start();
export const show = () => D()?.wa.show();
export const unlink = () => D()?.wa.logout();
export const send = (to, text) => D()?.wa.send(to, text);

/** "read my WhatsApp messages" */
export async function unreadText() {
  if (state !== 'ready') return 'WhatsApp isn’t linked yet. Say “link WhatsApp” and scan the code with your phone.';
  const list = await D().wa.unread().catch(() => []);
  if (!list.length) return 'No unread WhatsApp messages.';
  return `You have ${list.length} unread chat${list.length === 1 ? '' : 's'}. ` + list.slice(0, 5).map(c => `${c.name || 'Someone'}: ${(c.last || []).slice(-3).join(' · ')}`).join('. ') + '.';
}
