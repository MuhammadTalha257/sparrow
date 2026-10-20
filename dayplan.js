// Calendars, "Plan my day" and personalities.
//  • Google / Outlook / any calendar: paste its private iCal (.ics) link once; Zuffi reads your events (read-only).
//  • Plan my day: fits your open tasks into the free time between meetings, calendar events and timed reminders.
//  • Personalities: how Zuffi talks (friendly, professional, butler, big brother, coach, teacher, funny).
import { store } from './store.js';

// ---------------- personalities ----------------
export const PERSONALITIES = {
  friendly: ['Friendly', 'Warm, cheerful and helpful — the usual Zuffi.', ''],
  professional: ['Professional', 'Calm, precise and to the point.', 'Speak like a calm, precise executive assistant: polite, brief, no jokes, no emojis.'],
  butler: ['Butler', 'Polite and formal, at your service.', 'Speak like a refined, loyal English butler: formal, gracious, gently witty ("Very good", "At once"). Address the user respectfully.'],
  sibling: ['Big brother / sister', 'Caring, honest, a bit cheeky.', 'Speak like a caring older sibling: warm, honest, encouraging, a little cheeky, but always helpful.'],
  coach: ['Coach', 'Motivating — keeps you moving.', 'Speak like an upbeat personal coach: motivating, action-focused, short sentences, celebrate progress.'],
  teacher: ['Teacher', 'Patient, explains step by step.', 'Speak like a patient teacher: explain simply, step by step, check understanding.'],
  funny: ['Funny friend', 'Light-hearted, with a joke now and then.', 'Speak like a funny friend: light-hearted with the odd gentle joke, but still answer properly.'],
};
export const personalityLine = () => { const p = PERSONALITIES[store.settings.personality || 'friendly']; return p && p[2] ? `\nPERSONALITY: ${p[2]}` : ''; };

// ---------------- calendars (iCal links) ----------------
const CAL_LS = 'zuffiCalEvents';
export const calendars = () => store.settings.calendars || [];
export function events() { try { return (JSON.parse(localStorage.getItem(CAL_LS) || '[]')).map(e => ({ ...e, start: new Date(e.start), end: new Date(e.end) })); } catch { return []; } }
export function eventsOn(day = new Date()) { const k = day.toDateString(); return events().filter(e => e.start.toDateString() === k).sort((a, b) => a.start - b.start); }

/** GET a calendar link — through the Mac / Windows app when there is one (calendar servers block web pages). */
async function getText(url) {
  url = url.replace(/^webcal:/i, 'https:');
  const M = window.SparrowHost === 'mac' ? window.SparrowMac : null, D = window.SparrowDesktop;
  if (M) { const r = await M.call('http', { url, method: 'GET', headers: {}, body: '' }); if (r?.status >= 200 && r.status < 300) return r.text; throw new Error('The calendar link answered ' + (r?.status || 'nothing')); }
  if (D?.httpGet) return D.httpGet(url);
  const r = await fetch(url); if (!r.ok) throw new Error('The calendar link answered ' + r.status); return r.text();
}
function icsDate(v, tzid) {
  const m = String(v).match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})?(Z)?)?/); if (!m) return null;
  if (!m[4]) return new Date(+m[1], +m[2] - 1, +m[3]);
  if (m[7]) return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0)));
  return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +(m[6] || 0));   // local / TZID: treat as this device's time
}
/** .ics text → events in the next 21 days (simple weekly / daily repeats included). */
export function parseICS(text, source = '') {
  const lines = String(text).replace(/\r\n[ \t]/g, '').split(/\r?\n/), out = [], now = Date.now(), until = now + 21 * 864e5;
  let ev = null;
  for (const l of lines) {
    if (l === 'BEGIN:VEVENT') ev = {};
    else if (l === 'END:VEVENT' && ev) {
      if (ev.start) {
        const dur = (ev.end || new Date(+ev.start + 3600e3)) - ev.start, push = s => { if (+s + dur >= now - 864e5 && +s <= until) out.push({ title: ev.title || 'Busy', start: s.toISOString(), end: new Date(+s + dur).toISOString(), allDay: ev.allDay, where: ev.where || '', source }); };
        const rr = /FREQ=(DAILY|WEEKLY)/.exec(ev.rrule || ''), cnt = +(/COUNT=(\d+)/.exec(ev.rrule || '') || [])[1] || 400, untilR = (/UNTIL=([0-9TZ]+)/.exec(ev.rrule || '') || [])[1];
        if (rr) { const step = rr[1] === 'DAILY' ? 864e5 : 7 * 864e5, stop = Math.min(until, untilR ? +icsDate(untilR) : until); for (let t = +ev.start, i = 0; t <= stop && i < cnt; t += step, i++) push(new Date(t)); }
        else push(ev.start);
      }
      ev = null;
    } else if (ev) {
      const i = l.indexOf(':'); if (i < 0) continue;
      const key = l.slice(0, i), val = l.slice(i + 1).replace(/\\,/g, ',').replace(/\\n/g, ' ').replace(/\\;/g, ';');
      if (key.startsWith('DTSTART')) { ev.start = icsDate(val); ev.allDay = /VALUE=DATE(?!-)/.test(key) || val.length === 8; }
      else if (key.startsWith('DTEND')) ev.end = icsDate(val);
      else if (key === 'SUMMARY') ev.title = val;
      else if (key === 'LOCATION') ev.where = val;
      else if (key === 'RRULE') ev.rrule = val;
    }
  }
  return out;
}
export async function refresh() {
  const cals = calendars(); if (!cals.length) { localStorage.removeItem(CAL_LS); return 0; }
  const all = [];
  for (const c of cals) { try { all.push(...parseICS(await getText(c.url), c.name)); c.ok = true; c.error = ''; } catch (e) { c.ok = false; c.error = e.message; } }
  store.settings.calendars = cals; store.save();
  try { localStorage.setItem(CAL_LS, JSON.stringify(all)); } catch {}
  document.dispatchEvent(new CustomEvent('zuffi-calendar'));
  return all.length;
}
export async function addCalendar(url, name) {
  url = String(url || '').trim(); if (!/^(https?|webcal):\/\/\S+$/i.test(url)) throw new Error('Paste the calendar’s private link (it starts with https:// or webcal://).');
  const kind = /google\.com/.test(url) ? 'Google Calendar' : /outlook|office365|live\.com/.test(url) ? 'Outlook' : /icloud/.test(url) ? 'iCloud' : 'Calendar';
  const cals = calendars().filter(c => c.url !== url); cals.push({ url, name: name || kind });
  store.settings.calendars = cals; store.save();
  const n = await refresh(); const c = calendars().find(x => x.url === url);
  if (c && c.ok === false) throw new Error(c.error || 'Couldn’t read that calendar.');
  return n;
}
export function removeCalendar(url) { store.settings.calendars = calendars().filter(c => c.url !== url); store.save(); return refresh(); }

// ---------------- Plan my day ----------------
/** Free time today between busy blocks → open tasks placed in it. Returns { blocks:[{start,end,title,kind}], unplaced:[task] } */
export function planDay({ startHour = 9, endHour = 18, minutes = 30 } = {}) {
  const now = new Date(), day = new Date(now.toDateString());
  let start = new Date(+day + startHour * 3600e3); const end = new Date(+day + endHour * 3600e3);
  if (now > start) start = new Date(Math.ceil(now / (15 * 60e3)) * 15 * 60e3);
  const busy = [
    ...eventsOn(now).filter(e => !e.allDay).map(e => ({ start: e.start, end: e.end, title: e.title, kind: 'event' })),
    ...store.items.filter(i => i.when && !i.done && ['meeting', 'reminder', 'task'].includes(i.type) && new Date(i.when).toDateString() === now.toDateString() && new Date(i.when) >= now)
      .map(i => ({ start: new Date(i.when), end: new Date(+new Date(i.when) + (i.type === 'meeting' ? 60 : i.type === 'task' ? 30 : 15) * 60e3), title: i.title, kind: i.type === 'task' ? 'reminder' : i.type })),
  ].sort((a, b) => a.start - b.start);
  const tasks = store.items.filter(i => i.type === 'task' && !i.done && (!i.when || new Date(i.when).toDateString() === now.toDateString() && new Date(i.when) < now))
    .sort((a, b) => (b.priority === 'high') - (a.priority === 'high') || new Date(a.created) - new Date(b.created));
  const est = t => { const m = /(\d+(?:\.\d+)?)\s*(h|hr|hrs|hour|hours|m|min|mins|minutes)\b/i.exec(t.title || ''); return m ? (/^h/i.test(m[2]) ? +m[1] * 60 : +m[1]) : minutes; };
  const blocks = [], unplaced = [];
  let cursor = start, bi = 0;
  for (const t of tasks) {
    const need = est(t) * 60e3; let placed = false;
    while (+cursor + need <= +end) {
      const clash = busy.find(b => b.start < new Date(+cursor + need) && b.end > cursor);
      if (!clash) { blocks.push({ start: new Date(cursor), end: new Date(+cursor + need), title: t.title, kind: 'task', id: t.id }); cursor = new Date(+cursor + need + 5 * 60e3); placed = true; break; }
      cursor = new Date(Math.max(+cursor, +clash.end));
    }
    if (!placed) unplaced.push(t);
    bi++;
  }
  return { blocks: [...busy.filter(b => b.end > now), ...blocks].sort((a, b) => a.start - b.start), unplaced, from: start, to: end };
}
/** Puts each planned task at its time (so reminders ring). */
export function applyPlan(plan) {
  let n = 0;
  for (const b of plan.blocks) if (b.kind === 'task' && b.id) { store.update(b.id, { when: b.start.toISOString(), notified: false }); n++; }
  return n;
}
