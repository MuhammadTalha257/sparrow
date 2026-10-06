// Sparrow's built-in brain: understands everyday requests instantly, offline, with no AI or key.
import * as chrono from './lib/chrono.js';
import { store } from './store.js';
import { t as tr, normalizeCommand } from './i18n.js';
import { prayerTimes, nextPrayer, refreshOnline, NAMES as PRAYERS } from './prayer.js';
import * as mem from './memory.js';
import { parseDoc, makeDocPDF, deliver, startTimer, stopTimer, runningTimer, timeFor, fmtHours, parseExpense, monthExpenses } from './tools.js';

export const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
export const isAndroid = /Android/i.test(navigator.userAgent);

// ---------- formatting ----------
export const fmtTime = d => new Date(d).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
export function fmtDay(d) {
  const x = new Date(d), t = new Date(); t.setHours(0, 0, 0, 0);
  const y = new Date(x); y.setHours(0, 0, 0, 0);
  const diff = Math.round((y - t) / 86400000);
  if (diff === 0) return 'Today';
  if (diff === 1) return 'Tomorrow';
  if (diff === -1) return 'Yesterday';
  if (diff > 1 && diff < 7) return x.toLocaleDateString([], { weekday: 'long' });
  return x.toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' });
}
export const whenText = iso => iso ? `${fmtDay(iso)} · ${fmtTime(iso)}` : '';
const cap = s => s ? s.charAt(0).toUpperCase() + s.slice(1) : s;
const tidy = s => s.replace(/\s+/g, ' ')
  .replace(/^(to|that|about|for|of|me|a|an)\s+/i, '')
  .replace(/\s+(at|on|by|for|in|from|this|next)$/i, '')
  .replace(/^[,:\-\s]+|[,.!?:\-\s]+$/g, '').trim();
export function partOfDay(h = new Date().getHours()) { return h >= 5 && h < 12 ? 'morning' : h >= 12 && h < 17 ? 'afternoon' : h >= 17 && h < 22 ? 'evening' : 'night'; }
export function greetingWord() { return tr(partOfDay()); }
const hi = () => store.settings.name ? `, ${store.settings.name}` : '';

// ---------- dates ----------
function parseWhen(text) {
  text = text.replace(/\b(?:coming|upcoming)\s+(?=(?:mon|tues|wednes|thurs|fri|satur|sun)day|week|month)/gi, 'next ');
  const r = chrono.parse(text, new Date(), { forwardDate: true });
  if (!r.length) return { date: null, rest: text, hasTime: false };
  const p = r[0];
  const date = p.start.date();
  const hasTime = p.start.isCertain('hour');
  if (!hasTime) date.setHours(9, 0, 0, 0);   // a day with no time → 9 am
  // "at 5" with no am/pm: people mean 5 pm, not 5 in the morning
  else if (!p.start.isCertain('meridiem') && date.getHours() >= 1 && date.getHours() <= 6 && !/\b(am|a\.m|morning)\b/i.test(text)) date.setHours(date.getHours() + 12);
  const rest = (text.slice(0, p.index) + ' ' + text.slice(p.index + p.text.length)).replace(/\s+/g, ' ').replace(/\s+(?:on|at|for|by|this|next)$/i, '').trim();
  return { date, rest, hasTime };
}
/** A date range from words like "last month", "on 12 September", "yesterday", "this week". */
export function dateRange(text) {
  const now = new Date(), d0 = new Date(now); d0.setHours(0, 0, 0, 0);
  const day = 86400e3, t = text.toLowerCase();
  const dow = (d0.getDay() + 6) % 7;   // Monday = 0
  if (/\btoday\b/.test(t)) return [d0.getTime(), now.getTime()];
  if (/\byesterday\b/.test(t)) return [d0 - day, d0.getTime()];
  if (/\bthis week\b/.test(t)) return [d0 - dow * day, now.getTime()];
  if (/\blast week\b/.test(t)) return [d0 - (dow + 7) * day, d0 - dow * day];
  if (/\bthis month\b/.test(t)) return [new Date(now.getFullYear(), now.getMonth(), 1).getTime(), now.getTime()];
  if (/\blast month\b/.test(t)) return [new Date(now.getFullYear(), now.getMonth() - 1, 1).getTime(), new Date(now.getFullYear(), now.getMonth(), 1).getTime()];
  if (/\bthis year\b/.test(t)) return [new Date(now.getFullYear(), 0, 1).getTime(), now.getTime()];
  const m = t.match(/\blast (\d+) days\b/); if (m) return [d0 - (+m[1]) * day, now.getTime()];
  const r = chrono.parse(text, now, { forwardDate: false });
  if (r.length) {
    const s = r[0].start.date(); s.setHours(0, 0, 0, 0);
    const e = r[0].end ? r[0].end.date() : new Date(s.getTime() + day);
    if (s > now && !r[0].start.isCertain('year')) s.setFullYear(s.getFullYear() - 1), e.setFullYear(e.getFullYear() - 1);
    return [s.getTime(), Math.max(e.getTime(), s.getTime() + day)];
  }
  return null;
}

// ---------- repeating ----------
const DAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
/** Finds "every day / every Monday / weekdays / monthly …" and returns { rule, rest } */
function parseRepeat(text) {
  let m = text.match(/\b(every\s*day|daily|each day|har\s*roz|every\s*(morning|evening|night))\b/i);
  if (m) return { rule: { freq: 'daily' }, rest: text.replace(m[0], m[2] ? m[2] : ' ') };
  m = text.match(/\b(every\s*weekday|on\s*weekdays|weekdays|monday\s*to\s*friday)\b/i);
  if (m) return { rule: { freq: 'weekly', days: [1, 2, 3, 4, 5] }, rest: text.replace(m[0], ' ') };
  m = text.match(/\b(every\s*weekend|weekends)\b/i);
  if (m) return { rule: { freq: 'weekly', days: [0, 6] }, rest: text.replace(m[0], ' ') };
  m = text.match(/\bevery\s+((?:(?:sun|mon|tues?|wed(?:nes)?|thu(?:rs)?|fri|sat(?:ur)?)(?:day)?(?:\s*(?:,|and)\s*)?)+)/i);
  if (m) {
    const days = [...new Set(m[1].toLowerCase().split(/\s*(?:,|and)\s*/).map(d => DAYS.findIndex(x => x.startsWith(d.slice(0, 3)))).filter(i => i >= 0))];
    if (days.length) return { rule: { freq: 'weekly', days }, rest: text.replace(m[0], ' ') };
  }
  m = text.match(/\b(every\s*week|weekly)\b/i);
  if (m) return { rule: { freq: 'weekly', days: [new Date().getDay()] }, rest: text.replace(m[0], ' ') };
  m = text.match(/\b(every\s*month|monthly)(?:\s+on\s+the\s+(\d{1,2})(?:st|nd|rd|th)?)?\b/i);
  if (m) return { rule: { freq: 'monthly', day: m[2] ? +m[2] : null }, rest: text.replace(m[0], ' ') };
  return null;
}
/** Next time a repeating item is due, strictly after `after`. */
export function nextOccurrence(rule, base, after = new Date()) {
  const b = new Date(base), h = b.getHours(), mi = b.getMinutes();
  const d = new Date(after); d.setSeconds(0, 0);
  for (let i = 0; i < 400; i++) {
    const c = new Date(d.getFullYear(), d.getMonth(), d.getDate() + i, h, mi);
    if (c <= after) continue;
    if (rule.freq === 'daily') return c;
    if (rule.freq === 'weekly' && (rule.days || [b.getDay()]).includes(c.getDay())) return c;
    if (rule.freq === 'monthly' && c.getDate() === (rule.day || b.getDate())) return c;
  }
  return null;
}
export function repeatText(rule) {
  if (!rule) return '';
  if (rule.freq === 'daily') return 'every day';
  if (rule.freq === 'monthly') return 'every month';
  const d = rule.days || [];
  if (d.length === 5 && !d.includes(0) && !d.includes(6)) return 'every weekday';
  if (d.length === 2 && d.includes(0) && d.includes(6)) return 'every weekend';
  return 'every ' + d.map(i => cap(DAYS[i])).join(', ');
}

// ---------- quick actions ----------
export const DEFAULT_QUICK = [
  { k: 'whatsapp', n: 'WhatsApp', e: '💬', url: 'https://wa.me/' },
  { k: 'gmail', n: 'Gmail', e: '✉️', url: 'https://mail.google.com' },
  { k: 'youtube', n: 'YouTube', e: '▶️', url: 'https://www.youtube.com' },
  { k: 'spotify', n: 'Spotify', e: '🎧', url: 'https://open.spotify.com' },
  { k: 'maps', n: 'Maps', e: '🗺️', url: isIOS ? 'https://maps.apple.com' : 'https://maps.google.com' },
  { k: 'calendar', n: 'Calendar', e: '📅', url: isIOS ? 'calshow:' : 'https://calendar.google.com' },
  { k: 'instagram', n: 'Instagram', e: '📸', url: 'https://www.instagram.com' },
  { k: 'drive', n: 'Drive', e: '📁', url: 'https://drive.google.com' },
];
export const AI_APPS = [
  { k: 'chatgpt', n: 'ChatGPT', url: 'https://chatgpt.com' },
  { k: 'claude', n: 'Claude', url: 'https://claude.ai' },
  { k: 'gemini', n: 'Gemini', url: 'https://gemini.google.com' },
  { k: 'grok', n: 'Grok', url: 'https://grok.com' },
  { k: 'perplexity', n: 'Perplexity', url: 'https://www.perplexity.ai' },
  { k: 'deepseek', n: 'DeepSeek', url: 'https://chat.deepseek.com' },
  { k: 'copilot', n: 'Copilot', url: 'https://copilot.microsoft.com' },
  { k: 'cursor', n: 'Cursor', url: 'https://cursor.com', app: 'Cursor' },
];
export function getQuick() { return (store.settings.quick && store.settings.quick.length) ? store.settings.quick : DEFAULT_QUICK; }

const SITES = {
  facebook: 'https://www.facebook.com', twitter: 'https://x.com', x: 'https://x.com', tiktok: 'https://www.tiktok.com',
  netflix: 'https://www.netflix.com', linkedin: 'https://www.linkedin.com', reddit: 'https://www.reddit.com',
  google: 'https://www.google.com', drive: 'https://drive.google.com', 'google drive': 'https://drive.google.com',
  outlook: 'https://outlook.live.com', amazon: 'https://www.amazon.co.uk', github: 'https://github.com',
  bbc: 'https://www.bbc.co.uk/news', 'google maps': 'https://maps.google.com', snapchat: 'https://www.snapchat.com', telegram: 'https://t.me/',
  uber: 'https://m.uber.com', notion: 'https://www.notion.so', canva: 'https://www.canva.com', email: 'https://mail.google.com',
  mail: isIOS ? 'message:' : 'https://mail.google.com', 'youtube music': 'https://music.youtube.com', daraz: 'https://www.daraz.pk',
  ...Object.fromEntries(AI_APPS.map(a => [a.k, a.url])),
};
function openTarget(name) {
  const n = name.toLowerCase().replace(/^(the|my)\s+/, '').replace(/\s+(app|website|site)$/, '').trim();
  const q = getQuick().find(x => x.k === n || x.n.toLowerCase() === n);
  if (q) return { url: q.url, label: q.n };
  if (SITES[n]) return { url: SITES[n], label: cap(n) };
  if (/^[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(n)) return { url: n.startsWith('http') ? n : 'https://' + n, label: n };
  return null;
}

// ---------- calendar (.ics + Google) ----------
const icsDate = d => new Date(d).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const icsEsc = s => String(s).replace(/([,;\\])/g, '\\$1').replace(/\n/g, '\\n');
function rrule(rule) {
  if (!rule) return null;
  if (rule.freq === 'daily') return 'RRULE:FREQ=DAILY';
  if (rule.freq === 'monthly') return 'RRULE:FREQ=MONTHLY';
  return 'RRULE:FREQ=WEEKLY;BYDAY=' + (rule.days || []).map(d => ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA'][d]).join(',');
}
export function icsFor(item) {
  const start = new Date(item.when);
  const end = new Date(start.getTime() + (item.type === 'meeting' ? (item.duration || 60) : 15) * 60000);
  const alarm = item.type === 'meeting' ? `-PT${Math.max(5, +store.settings.lead || 10)}M` : 'PT0M';
  return ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Sparrow//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT', `UID:${item.id}@sparrow`, `DTSTAMP:${icsDate(new Date())}`, `DTSTART:${icsDate(start)}`, `DTEND:${icsDate(end)}`,
    `SUMMARY:${icsEsc(item.title)}`, rrule(item.repeat), 'DESCRIPTION:Added by Sparrow 🐦',
    'BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${icsEsc(item.title)}`, `TRIGGER:${alarm}`, 'END:VALARM', 'END:VEVENT', 'END:VCALENDAR',
  ].filter(Boolean).join('\r\n');
}
/** A month of prayer times as calendar events, so an iPhone alerts even when Sparrow is closed. */
export function prayerICS(lat, lon, days = 30) {
  const p = store.settings.prayer, lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Sparrow//EN'];
  for (let i = 0; i < days; i++) {
    const d = new Date(); d.setDate(d.getDate() + i);
    const tms = prayerTimes(d, lat, lon, p.method, p.asr);
    for (const n of PRAYERS) if (n !== 'Sunrise') lines.push('BEGIN:VEVENT', `UID:${n}-${d.toDateString().replace(/\s/g, '')}@sparrow`, `DTSTAMP:${icsDate(new Date())}`,
      `DTSTART:${icsDate(tms[n])}`, `DTEND:${icsDate(new Date(tms[n].getTime() + 10 * 60000))}`, `SUMMARY:${n} prayer`,
      'BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${n}`, `TRIGGER:-PT${+p.before || 0}M`, 'END:VALARM', 'END:VEVENT');
  }
  lines.push('END:VCALENDAR');
  return lines.join('\r\n');
}
export function googleCalUrl(item) {
  const start = new Date(item.when);
  const end = new Date(start.getTime() + (item.type === 'meeting' ? 60 : 15) * 60000);
  const p = new URLSearchParams({ action: 'TEMPLATE', text: item.title, dates: `${icsDate(start)}/${icsDate(end)}`, details: 'Added by Sparrow 🐦' });
  if (item.repeat) p.set('recur', rrule(item.repeat));
  return 'https://calendar.google.com/calendar/render?' + p.toString();
}

// ---------- location & weather (free, no key) ----------
let cachedLoc = null, cachedAt = 0;
async function getJSON(url) { const r = await fetch(url); if (!r.ok) throw new Error(r.status); return r.json(); }
async function cityName(lat, lon) {
  try {
    const j = await getJSON(`https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${lat}&longitude=${lon}&localityLanguage=en`);
    return j.city || j.locality || j.principalSubdivision || '';
  } catch { return ''; }
}
/** Where you are: chosen city → device location → internet guess. Remembers the last place (works offline). */
export async function location(force = false) {
  if (!force && cachedLoc && Date.now() - cachedAt < 20 * 60e3) return cachedLoc;
  const save = l => { cachedLoc = l; cachedAt = Date.now(); store.settings.lastLoc = l; store.save(); return l; };
  const city = (store.settings.city || '').trim();
  if (city) {
    try {
      const g = await getJSON('https://geocoding-api.open-meteo.com/v1/search?count=1&name=' + encodeURIComponent(city));
      const r = g.results?.[0];
      if (r) return save({ lat: r.latitude, lon: r.longitude, city: r.name });
    } catch {}
  }
  const D = window.SparrowDesktop;
  if (window.SparrowHost === 'mac') {
    try { const p = await window.SparrowMac.call('location'); if (p?.lat) return save({ lat: p.lat, lon: p.lon, city: p.city || await cityName(p.lat, p.lon) }); } catch {}
  } else if (D) {
    try { const p = await D.location(); if (p) return save({ ...p, city: await cityName(p.lat, p.lon) }); } catch {}
  } else {
    try {
      const pos = await new Promise((res, rej) => navigator.geolocation ? navigator.geolocation.getCurrentPosition(res, rej, { timeout: 8000, maximumAge: 10 * 60e3 }) : rej());
      const { latitude: lat, longitude: lon } = pos.coords;
      return save({ lat, lon, city: await cityName(lat, lon) });
    } catch {}
  }
  try {
    const j = await getJSON('https://ipapi.co/json/');
    if (j.latitude) return save({ lat: j.latitude, lon: j.longitude, city: j.city || '' });
  } catch {}
  return store.settings.lastLoc || null;
}
const WMO = c => c === 0 ? 'clear' : c <= 2 ? 'partly cloudy' : c === 3 ? 'cloudy' : c <= 48 ? 'foggy' : c <= 57 ? 'drizzly'
  : c <= 67 || (c >= 80 && c <= 82) ? 'rainy' : c <= 77 || c === 85 || c === 86 ? 'snowy' : c >= 95 ? 'stormy' : 'mild';
export async function weather() {
  const loc = await location();
  if (!loc) return null;
  const f = navigator.language === 'en-US';
  const u = `https://api.open-meteo.com/v1/forecast?latitude=${loc.lat}&longitude=${loc.lon}&current=temperature_2m,weather_code`
    + `&daily=temperature_2m_max,precipitation_probability_max&timezone=auto&forecast_days=1${f ? '&temperature_unit=fahrenheit' : ''}`;
  try {
    const j = await getJSON(u);
    return { city: loc.city, temp: Math.round(j.current.temperature_2m), hi: Math.round(j.daily.temperature_2m_max[0]),
      sky: WMO(j.current.weather_code), rain: j.daily.precipitation_probability_max?.[0] ?? 0 };
  } catch { return null; }
}
export async function weatherText() {
  const w = await weather(); if (!w) return null;
  let s = `${w.city ? 'In ' + w.city + ' it' : 'It'}'s ${w.temp}° and ${w.sky}, high of ${w.hi}°.`;
  if (w.rain >= 50) s += ` ${w.rain}% chance of rain — take an umbrella ☔`;
  return s;
}

// ---------- prayer ----------
export async function prayerToday() {
  const loc = await location(); if (!loc) return null;
  const p = store.settings.prayer;
  if (p.method === 'Auto') await refreshOnline(loc.lat, loc.lon, p.asr);
  return { loc, times: prayerTimes(new Date(), loc.lat, loc.lon, p.method, p.asr), next: nextPrayer(loc.lat, loc.lon, p.method, p.asr) };
}

// ---------- summaries ----------
export function daySummary(date = new Date(), short = false) {
  const items = store.onDay(date);
  const meetings = items.filter(i => i.type === 'meeting');
  const reminders = items.filter(i => i.type === 'reminder' && !i.done);
  const tasks = store.openTasks();
  const label = fmtDay(date).toLowerCase();
  if (!items.length && !tasks.length) return `Nothing planned ${label === 'today' ? 'today' : 'for ' + label}. Enjoy! 🌤️`;
  const parts = [];
  if (meetings.length) parts.push(`${meetings.length} meeting${meetings.length > 1 ? 's' : ''}`);
  if (reminders.length) parts.push(`${reminders.length} reminder${reminders.length > 1 ? 's' : ''}`);
  if (tasks.length) parts.push(`${tasks.length} open task${tasks.length > 1 ? 's' : ''}`);
  let s = `${cap(label)} you have ${parts.join(', ').replace(/, ([^,]*)$/, ' and $1')}.`;
  if (!short) { const first = items.find(i => !i.done && new Date(i.when) > new Date()); if (first) s += ` Next: ${first.title} at ${fmtTime(first.when)}.`; }
  return s;
}
const endOfDay = d => { const x = new Date(d); x.setHours(24, 0, 0, 0); return x; };
const sameDay = (a, b) => new Date(a).toDateString() === new Date(b).toDateString();
export function tasksForDay(date = new Date(), includeUndated = false) {
  const end = endOfDay(date);
  return store.items.filter(i => i.type === 'task' && !i.done && (i.when ? new Date(i.when) < end : (includeUndated || sameDay(i.created, date))));
}
export function spokenList(titles, max = 5) {
  const t = titles.slice(0, max);
  if (titles.length > max) t.push(`${titles.length - max} more`);
  return t.length <= 1 ? (t[0] || '') : t.slice(0, -1).join(', ') + ' and ' + t[t.length - 1];
}
export function spokenPlan(date = new Date()) {
  const items = store.onDay(date), now = new Date();
  const meetings = items.filter(i => i.type === 'meeting' && (!sameDay(date, now) || new Date(i.when) > new Date(now - 30 * 60e3)));
  const reminders = items.filter(i => i.type === 'reminder' && !i.done && (!sameDay(date, now) || new Date(i.when) > now));
  const d0 = new Date(date); d0.setHours(0, 0, 0, 0);
  const tasks = tasksForDay(date, true);
  const dated = tasks.filter(i => i.when && new Date(i.when) >= d0), overdue = tasks.filter(i => i.when && new Date(i.when) < d0);
  const undated = tasks.filter(i => !i.when);
  const habits = store.ofType('habit');
  const parts = [];
  if (meetings.length) parts.push(`You have ${meetings.length} meeting${meetings.length > 1 ? 's' : ''}: ` + spokenList(meetings.map(m => `${m.title} at ${fmtTime(m.when)}`), 4) + '.');
  if (dated.length) parts.push(`Your task${dated.length > 1 ? 's for today are' : ' for today is'}: ` + spokenList(dated.map(i => i.title)) + '.');
  if (undated.length) parts.push(`On your list: ` + spokenList(undated.map(i => i.title), 4) + '.');
  if (overdue.length) parts.push(`And ${overdue.length === 1 ? 'one task' : overdue.length + ' tasks'} from before: ` + spokenList(overdue.map(i => i.title), 3) + '.');
  if (reminders.length) parts.push(`${reminders.length === 1 ? 'One reminder' : reminders.length + ' reminders'} later: ` + spokenList(reminders.map(r => `${r.title} at ${fmtTime(r.when)}`), 3) + '.');
  if (habits.length) parts.push(`Habits: ` + spokenList(habits.map(h => `${h.title} ${h.target > 1 ? h.target + ' times' : ''}`.trim()), 3) + '.');
  return parts.length ? parts.join(' ') : 'Your day is clear — no meetings or tasks yet.';
}
export async function briefing() {
  let s = `${greetingWord()}${hi()}! It's ${fmtTime(new Date())}.`;
  const w = await weatherText(); if (w) s += ' ' + w;
  if (store.settings.prayer.on) { try { const p = await prayerToday(); if (p?.next) s += ` Next prayer: ${p.next.name} at ${fmtTime(p.next.at)}.`; } catch {} }
  return s + ' ' + spokenPlan(new Date());
}
export function moveToTomorrow(id) {
  const it = store.items.find(i => i.id === id); if (!it) return false;
  const t = new Date(); t.setDate(t.getDate() + 1);
  const d = it.when ? new Date(it.when) : new Date(t.setHours(9, 0, 0, 0));
  d.setFullYear(t.getFullYear(), t.getMonth(), t.getDate());
  store.update(id, { when: d.toISOString(), notified: false, soonDone: false });
  return true;
}
export function moveRestToTomorrow() { const list = tasksForDay(new Date()); list.forEach(i => moveToTomorrow(i.id)); return list.length; }

// ---------- habits ----------
export const todayKey = () => new Date().toISOString().slice(0, 10);
export function habitCount(h) { return (h.log || {})[todayKey()] || 0; }
export function bumpHabit(h, n = 1) {
  const log = { ...(h.log || {}) }; log[todayKey()] = Math.max(0, (log[todayKey()] || 0) + n);
  store.update(h.id, { log }); mem.remember('habit', `${h.title} ${log[todayKey()]}/${h.target}`);
  return log[todayKey()];
}
function findHabit(t) {
  const hs = store.ofType('habit'); if (!hs.length) return null;
  const words = t.toLowerCase().split(/\W+/).filter(w => w.length > 2);
  return hs.find(h => words.some(w => h.title.toLowerCase().includes(w) || (h.alias || []).includes(w)));
}

// ---------- customers ----------
export function findCustomer(text) {
  const t = text.toLowerCase();
  return store.ofType('customer').find(c => t.includes(c.title.toLowerCase()) || t.includes(c.title.toLowerCase().split(' ')[0]));
}

// ---------- the brain ----------
export let lastAlert = null;                         // the reminder that just went off (for "snooze")
export function setLastAlert(id) { lastAlert = { id, at: Date.now() }; }
let pendingTidy = false;

/** Returns { reply, item?, url?, list?, action?, files?, results? } or null when an AI should answer instead. */
export async function handle(input) {
  const o = normalizeCommand(input).trim().replace(/^(hey |hi |ok |okay )?sparrow[,!\s]*/i, '').replace(/\s*please[.!]?$/i, '')
    .replace(/^(um+|uh+|erm|so|okay|ok|well|please|can you|could you|would you)[,\s]+/i, '');
  const t = o.toLowerCase().replace(/[?!.]+$/, '').trim();
  const D = window.SparrowDesktop, N = window.SparrowNative;
  let m;
  if (!t) return { reply: 'Yes? 🐦' };

  if (/^(help|what can you do|commands)\b/.test(t)) return { reply:
    'Try:\n• remind me every day at 8pm to take medicine\n• meeting with Ali Friday 3pm\n• add task buy milk\n• snooze 10 minutes\n• prayer times\n• add habit drink water 8 times a day\n• quote for Ali, 3 hours at £40\n• start timer for Ali · stop timer\n• spent £12 on lunch\n• which file did I send on 12 September?\n• play Tum Hi Ho on Spotify\n• open WhatsApp · weather · focus 25 minutes\nAnything else, just ask.' };
  if (/^(hi|hello|hey|salam|assalam|aoa|good (morning|afternoon|evening))\b/.test(t) && t.split(' ').length <= 4)
    return { reply: `${greetingWord()}${hi()}! How can I help? 🐦` };

  if (/^(new chat|start (a )?new chat|start (a )?fresh chat|start over|clear (the |this )?chat|reset (the )?chat|naya chat|nayi chat|nai chat|chat clear kar(o|do)|نئی چیٹ|नई चैट)$/.test(t))
    return { reply: 'Fresh chat started. Ask me anything.', action: 'newchat' };

  // ----- job agent (CV, job search, cover letters, applications) -----
  {
    const num = String.raw`(?:the )?(?:job |number |no\.? )?(\d+|first|second|third|fourth|fifth|top|best|one|two|three|four|five)(?: one| job)?`;
    let j;
    if (/^((analy[sz]e|review|check|read|score|rate|improve|look at) (my |the )?(cv|resume|résumé|c\.v\.?)|(meri |mera )?(cv|resume) (check|dekho|analy[sz]e|review) ?(karo|kar do|kr do)?|how good is my (cv|resume))$/.test(t))
      return { reply: 'Reading your CV…', action: 'cv-analyse' };
    if ((j = t.match(/^(?:find|search(?: for)?|look for|show|get|search me|find me)(?: me)?(?: some| new| the latest| latest)? (.+?) (jobs?|roles?|vacanc(?:y|ies)|positions?|openings?|apprenticeships?|internships?)(?: (?:in|near|around|at|for) (.+))?$/)) && !/\b(my|file|files)\b/.test(j[1]))
      return { reply: 'Looking for jobs…', action: 'jobs-search', q: j[1] + (/^(apprentice|intern)/.test(j[2]) ? ' ' + j[2] : ''), where: j[3] || '' };
    if ((j = t.match(/^(?:find|search(?: for)?|look for|show|get)(?: me)?(?: some| new)? (?:jobs?|work|vacancies)(?: for me)?(?: (?:in|near|around) (.+))?$/)))
      return { reply: 'Looking for jobs that fit you…', action: 'jobs-search', q: '', where: j[1] || '' };
    if ((j = t.match(/^(?:(.+?) (?:mein|me|main|vich) )?(.+?) (?:ki|ke|di|de) (?:jobs?|naukri|naukriyan) (?:dhoondo|dhundo|talash karo|dikhao|search karo)$/)))
      return { reply: 'Looking for jobs…', action: 'jobs-search', q: j[2], where: j[1] || '' };
    if (/^(?:mere liye |meri )?(?:jobs?|naukri) (?:dhoondo|dhundo|talash karo|dikhao)$/.test(t)) return { reply: 'Looking for jobs…', action: 'jobs-search', q: '', where: '' };
    if ((j = t.match(new RegExp(`^(?:tailor|customi[sz]e|adapt)(?: my)?(?: cv| resume)?(?: for)? ${num}$`))) || (j = t.match(new RegExp(`^(?:write |make )?(?:a |the |my )?cover letter for ${num}$`))))
      return { reply: 'Writing your cover letter…', action: 'jobs-tailor', n: j[1] };
    if ((j = t.match(new RegExp(`^apply (?:to|for) ${num}$`)))) return { reply: 'Opening the application…', action: 'jobs-apply', n: j[1] };
    if (/^(my )?(job )?(applications|tracker|job tracker)$|^(which |what )?jobs (have i|did i) appl(y|ied)( to| for)?$|^jobs i applied (to|for)$/.test(t)) return { reply: 'Your applications…', action: 'jobs-tracker' };
    if (/^(job agent|jobs?|job search|my jobs|open jobs?|career|naukri)$/.test(t)) return { reply: 'Opening your job agent…', action: 'jobs-open' };
  }

  // ----- health reminders (water, coffee, medicine) -----
  {
    const KIND = { water: /\b(water|drink water|paani|pani)\b/, coffee: /\b(coffee|chai|tea|caffeine)\b/, meds: /\b(medicine|medicines|meds|medication|tablets?|pills?|dawai|dawa)\b/ };
    const NAME = { water: '💧 water', coffee: '☕ coffee', meds: '💊 medicine' };
    const kind = Object.keys(KIND).find(k => KIND[k].test(t));
    const isRem = /\breminders?\b|\bremind me\b|\breminder\b|\byaad\b/.test(t);
    if (kind && isRem && /\b(turn off|stop|disable|switch off|no more|band karo|off)\b/.test(t)) {
      store.settings.health[kind].on = false; store.save(); return { reply: `${NAME[kind]} reminders are off.` };
    }
    // repeating only when it sounds repeating — "remind me to take medicine at 9pm" stays a normal one-off reminder
    const recurring = /\bevery\b|\bhar\b|\bdaily\b|\breminders\b|^(?:turn on|start|enable|switch on)\b/.test(t);
    if (kind && (isRem || /^(?:turn on|start|enable|switch on)\b/.test(t)) && recurring) {
      const h = store.settings.health[kind];
      const ev = t.match(/\bevery\s+(\d+(?:\.\d+)?|an?|one|half an?)\s*(min(?:ute)?s?|h(?:ou)?rs?)\b/) || t.match(/\bhar\s+(\d+)\s*(minute|ghante|ghanta)\b/);
      const at = t.match(/\bat\s+(.+)$/);
      if (ev) {
        const n = /half/.test(ev[1]) ? 0.5 : /^(a|an|one)$/.test(ev[1]) ? 1 : +ev[1];
        h.mode = 'every'; h.every = Math.max(1, Math.round(/^m/.test(ev[2]) || ev[2] === 'minute' ? n : n * 60));
      } else if (at) {
        const times = at[1].split(/\s*(?:,|and|&|aur)\s*/).map(x => { const d = chrono.parseDate(x); return d ? `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}` : null; }).filter(Boolean);
        if (times.length) { h.mode = 'times'; h.times = times.join(', '); }
      }
      h.on = true; delete h.last; store.save();
      const when = h.mode === 'every' ? `every ${h.every >= 60 && h.every % 60 === 0 ? (h.every / 60) + ' hour' + (h.every > 60 ? 's' : '') : h.every + ' minutes'}` : `at ${h.times}`;
      return { reply: `${NAME[kind]} reminders are on — ${when}, between ${h.start} and ${h.end}. The sparrow will bring it to you. Change it in Settings → Health.` };
    }
  }
  if (/^(turn on|start|enable|show)\s+(the )?(prayer|namaz|salah) (times|reminders?|alerts?)$/.test(t)) { store.settings.prayer.on = true; store.save(); return { reply: '🕌 Prayer times are on. They follow your location automatically.', action: 'refresh' }; }

  // ----- snooze -----
  m = t.match(/^snooze(?:\s+(?:it|for|that|this))?(?:\s+(?:for\s+)?(\d+)\s*(min(?:ute)?s?|h(?:ou)?rs?)?)?$/);
  if (m) {
    const it = lastAlert && store.items.find(i => i.id === lastAlert.id);
    if (!it) return { reply: 'Nothing to snooze right now.' };
    const mins = (+m[1] || 10) * (/^h/.test(m[2] || '') ? 60 : 1);
    store.update(it.id, { snoozeUntil: Date.now() + mins * 60000, snoozed: false, done: false });
    return { reply: `😴 OK, I'll remind you again in ${mins} minutes: ${it.title}.` };
  }

  // ----- daily routine -----
  if (/(what('?s| is) (on|up|planned)|my (day|agenda|schedule|plan)\b|what do i have|anything (on|planned)|^agenda|schedule for)/.test(t)) {
    const d = /tomorrow/.test(t) ? new Date(Date.now() + 86400000) : new Date();
    return { reply: daySummary(d), list: d };
  }
  if (/^((give me|read|tell me|what('?s| is| are)) )?(my |the )?(morning briefing|briefing|tasks?( for| of)? today|today'?s tasks|plan for today)$|^brief me/.test(t))
    return { reply: spokenPlan(new Date()) };
  if (/^(start |open |do )?(my |the )?(evening |night |daily )?check[- ]?in\b/.test(t)) return { reply: 'Opening your check-in.', action: 'checkin' };
  m = t.match(/^(?:move|shift|push|postpone|reschedule)\s+(.+?)(?:\s+(?:to|till|until|for)\s+tomorrow)?$/);
  if (m && (/tomorrow/.test(t) || t.startsWith('postpone'))) {
    if (/^(everything|all|the rest|rest|all( my)? tasks|remaining( tasks)?|them|the remaining( ones)?)$/.test(m[1])) {
      const n = moveRestToTomorrow();
      return { reply: n ? `Done. I moved ${n} task${n > 1 ? 's' : ''} to tomorrow.` : 'Nothing left for today to move.' };
    }
    const it = fuzzy(m[1].replace(/^(the|my) /, ''), store.items.filter(i => !i.done && ['task', 'reminder', 'meeting'].includes(i.type)));
    if (it && moveToTomorrow(it.id)) return { reply: `Moved "${it.title}" to tomorrow.` };
    return { reply: `I couldn't find "${m[1]}" in your list.` };
  }
  if (/^(show |list |what are )?(my )?(tasks|to-?dos|todo list|to do list)$/.test(t)) {
    const open = store.openTasks();
    return { reply: open.length ? 'Your tasks:\n' + open.map(i => '• ' + i.title + (i.when ? ` (${whenText(i.when)})` : '')).join('\n') : 'No open tasks. 🎉' };
  }

  // ----- prayer -----
  if (/\b(prayer|salah|salat|namaz)\b/.test(t) && !/^(remind|add)/.test(t)) {
    if (/\b(on|enable|start|turn on)\b/.test(t)) { store.settings.prayer.on = true; store.save(); }
    if (/\b(off|disable|stop|turn off)\b/.test(t)) { store.settings.prayer.on = false; store.save(); return { reply: 'Prayer reminders are off.' }; }
    const p = await prayerToday();
    if (!p) return { reply: "I need your location once to work out prayer times. Allow location, or set your city in Settings." };
    if (!store.settings.prayer.on) { store.settings.prayer.on = true; store.save(); }
    const list = PRAYERS.map(n => `• ${n} — ${fmtTime(p.times[n])}`).join('\n');
    return { reply: `🕌 Prayer times${p.loc.city ? ' in ' + p.loc.city : ''} today:\n${list}${p.next ? `\nNext: ${p.next.name} at ${fmtTime(p.next.at)}.` : ''}\nI'll remind you ${store.settings.prayer.before} minutes before each one.` };
  }

  // ----- habits -----
  m = o.match(/^(?:add|new|track|start)\s+(?:a\s+)?habit(?:\s+to)?\s+(.+)$/i) || o.match(/^track\s+(?:my\s+)?(water|medicine|meds|steps|reading|exercise|walk(?:ing)?|sleep)(.*)$/i);
  if (m) {
    let txt = m[1] + (m[2] || ''); let target = 1, every = 0;
    const n = txt.match(/(\d+)\s*(?:times|glasses|cups|x)\b/i); if (n) { target = +n[1]; txt = txt.replace(n[0], ''); }
    const ev = txt.match(/every\s+(\d+)\s*hours?/i); if (ev) { every = +ev[1]; txt = txt.replace(ev[0], ''); }
    txt = txt.replace(/\b(a|per|each)\s*day\b|\bdaily\b/gi, '').trim();
    if (/water/i.test(txt)) { target = target > 1 ? target : 8; every = every || 2; }
    const title = cap(tidy(txt)) || 'Habit';
    const item = store.add({ type: 'habit', title, target, every, log: {} });
    return { reply: `💧 Tracking "${title}" — ${target} time${target > 1 ? 's' : ''} a day${every ? `. I'll nudge you every ${every} hours` : ''}. Say "I drank water" (or tap ＋) to log it.`, item };
  }
  if (/^(i\s+)?(drank|had|took|did|finished|completed|done)\b|^(log|tick|count)\b/.test(t)) {
    const h = findHabit(t.replace(/^(log|tick|count)\s+/, ''));
    if (h) { const c = bumpHabit(h); return { reply: c >= h.target ? `🎉 ${h.title}: ${c}/${h.target} — goal reached today!` : `👍 ${h.title}: ${c}/${h.target} today.` }; }
  }

  // ----- reminders (one-off or repeating) -----
  m = o.match(/^(?:please\s+)?(?:remind(?:s|ed)? me|set (?:a )?reminder|reminder|don'?t let me forget|alert me)\b[\s,:]*(.*)$/i);
  if (m) {
    const rep = parseRepeat(m[1]);
    let { date, rest } = parseWhen(rep ? rep.rest : m[1]);
    let title = cap(tidy(rest.replace(/^(to|that|about)\s+/i, ''))) || 'Reminder';
    let note = '';
    if (rep) {
      const base = date || new Date(new Date().setHours(9, 0, 0, 0));
      date = nextOccurrence(rep.rule, base, new Date(Date.now() - 60000));
    }
    if (!date) { date = new Date(Date.now() + 3600e3); note = ' (in 1 hour — say a time to change it)'; }
    const item = store.add({ type: 'reminder', title, when: date.toISOString(), repeat: rep?.rule || null });
    mem.remember('reminder', title, '', { when: item.when });
    return { reply: `⏰ I'll remind you${rep ? ' ' + repeatText(rep.rule) : ''}: ${title} — ${rep ? 'next ' : ''}${whenText(item.when)}${note}.`, item };
  }

  // ----- meetings / appointments -----
  if (!/^(cancel|delete|remove|clear|move|reschedule|change|what|which|how many|list|show|my)\b/.test(t) &&
      (/\b(meeting|meet|call with|appointment|interview|lunch with|dinner with|catch ?up|zoom|teams call|doctor|dentist|client|session with|class with)\b/.test(t) ||
      /^(schedule|book|set up|arrange)\b/.test(t))) {
    const rep = parseRepeat(o);
    const { date, rest } = parseWhen(rep ? rep.rest : o);
    if (date) {
      let title = tidy(rest.replace(/^(add|schedule|book|set up|arrange|create|i have|there'?s|put)\s+(a |an )?/i, '')
        .replace(/\s+(to|in|on) (my )?(calendar|agenda|schedule)$/i, ''));
      title = cap(title || 'Meeting');
      const when = rep ? nextOccurrence(rep.rule, date, new Date(Date.now() - 60000)) : date;
      const cust = findCustomer(title);
      const item = store.add({ type: 'meeting', title, when: when.toISOString(), duration: 60, repeat: rep?.rule || null, customer: cust?.id || null });
      mem.remember('meeting', title, '', { when: item.when });
      return { reply: `🗓️ Added: ${title} — ${whenText(item.when)}${rep ? ' (' + repeatText(rep.rule) + ')' : ''}. I'll warn you ${store.settings.lead || 5} minutes before.`, item };
    }
  }

  // ----- notes & snippets -----
  m = o.match(/^(?:save|add|new)\s+(?:a\s+)?snippet\s+(.+?)\s*[:=-]\s*([\s\S]+)$/i);
  if (m) {
    store.settings.snippets = [...(store.settings.snippets || []).filter(s => s.name.toLowerCase() !== m[1].toLowerCase()), { name: m[1].trim(), text: m[2].trim() }];
    store.save(); return { reply: `📋 Saved snippet "${m[1].trim()}". Say "copy ${m[1].trim()}" to copy it.` };
  }
  m = t.match(/^copy\s+(?:my\s+)?(.+)$/);
  if (m) {
    const s = (store.settings.snippets || []).find(x => x.name.toLowerCase() === m[1] || x.name.toLowerCase().includes(m[1]));
    if (s) { try { await navigator.clipboard.writeText(s.text); } catch { D?.clips('copy', s.text); } return { reply: `📋 Copied "${s.name}".` }; }
  }
  m = o.match(/^(?:take a note|note(?: down)?|write down|remember that|save (?:a )?note|jot down)\b[\s,:]*(.+)$/i);
  if (m) {
    const item = store.add({ type: 'note', title: cap(m[1].trim()) });
    mem.remember('note', item.title);
    return { reply: `📝 Saved your note.`, item };
  }

  // ----- customers -----
  m = o.match(/^(?:add|new|save)\s+(?:a\s+)?(?:customer|client)\s+(.+)$/i);
  if (m) {
    let rest = m[1];
    const email = (rest.match(/[\w.+-]+@[\w-]+\.[\w.]+/) || [])[0] || '';
    const phone = (rest.match(/\+?\d[\d\s-]{6,}\d/) || [])[0] || '';
    rest = rest.replace(email, '').replace(phone, '').replace(/[,;]+/g, ' ');
    const name = cap(tidy(rest)) || 'Customer';
    const item = store.add({ type: 'customer', title: name, email, phone: phone.replace(/\s+/g, ' ').trim() });
    mem.remember('customer', name, [email, phone].filter(Boolean).join(' '));
    return { reply: `👤 Added customer ${name}${phone ? ' · ' + phone : ''}${email ? ' · ' + email : ''}.`, item };
  }
  m = t.match(/^(?:show|open|find)?\s*(?:customer|client)\s+(.+)$/) || t.match(/^(?:show )?everything (?:about|for|with)\s+(.+)$/);
  if (m) return { reply: `Here's everything about ${cap(m[1])}:`, action: 'memory', query: { q: m[1] } };

  // ----- quotes & invoices -----
  const doc = /^(quote|invoice|bill)\b/i.test(o) && parseDoc(o);
  if (doc) {
    const runningFor = doc.lines.length ? null : timeFor(doc.customer, Date.now() - 31 * 86400e3);
    if (!doc.lines.length && runningFor > 0) {
      const rate = +((o.match(/[£$€₹]\s*(\d+(?:\.\d+)?)/) || [])[1]) || 0;
      doc.lines.push({ desc: `Work for ${doc.customer}`, qty: Math.round(runningFor * 100) / 100, price: rate });
    }
    if (!doc.lines.length) return { reply: `What should it include? e.g. "${doc.kind.toLowerCase()} for ${doc.customer}, 3 hours at £40, travel £20".` };
    const b = store.settings.business, key = doc.kind === 'Quote' ? 'quoteNo' : 'invoiceNo';
    doc.number = `${doc.kind === 'Quote' ? 'Q' : 'INV'}-${String(b[key] || 1).padStart(4, '0')}`;
    b[key] = (b[key] || 1) + 1; store.save();
    const { bytes, total } = await makeDocPDF(doc);
    const fname = `${doc.kind} ${doc.number} ${doc.customer}.pdf`.replace(/[\\/:*?"<>|]/g, '');
    const cust = findCustomer(doc.customer);
    const item = store.add({ type: doc.kind.toLowerCase(), title: `${doc.kind} ${doc.number} · ${doc.customer}`, total, customer: cust?.id || null, lines: doc.lines });
    mem.remember(doc.kind.toLowerCase(), `${doc.kind} ${doc.number} for ${doc.customer}`, doc.lines.map(l => `${l.qty} × ${l.desc} @ ${l.price}`).join('; '), { total });
    await deliver(fname, bytes, 'application/pdf');
    return { reply: `🧾 ${doc.kind} ${doc.number} for ${doc.customer}: ${b.currency}${total.toFixed(2)}. ${D ? 'Saved — I opened the folder.' : 'Ready to save or share.'}${!b.name ? '\nTip: add your business name in Settings → Business.' : ''}`, item };
  }

  // ----- time tracking -----
  m = t.match(/^(?:start|begin)\s+(?:a\s+)?(?:timer|tracking|clock)(?:\s+(?:for|on))?\s*(.*)$/) || t.match(/^(?:start|begin)\s+working\s+on\s+(.+)$/);
  if (m) { const it = startTimer(cap(m[1]) || 'Work'); return { reply: `⏱️ Timer started for ${it.title}. Say "stop timer" when you finish.` }; }
  if (/^(stop|end|pause)\s+(the\s+)?(timer|tracking|clock|working)$/.test(t)) {
    const r = stopTimer(); if (!r) return { reply: 'No timer is running.' };
    const it = store.items.find(i => i.id === r.id);
    mem.remember('timer', `${it.title}: ${fmtHours((it.end - it.start) / 3600e3)}`);
    return { reply: `⏱️ Stopped. ${it.title}: ${fmtHours((it.end - it.start) / 3600e3)}. This week: ${fmtHours(timeFor(it.title, Date.now() - 7 * 86400e3))}.` };
  }
  m = t.match(/^how (?:much time|many hours|long)\s+(?:did i (?:spend|work)\s+)?(?:on|for)\s+(.+?)(?:\s+(this week|this month|today))?$/);
  if (m) {
    const since = m[2] === 'today' ? new Date().setHours(0, 0, 0, 0) : m[2] === 'this month' ? new Date(new Date().getFullYear(), new Date().getMonth(), 1).getTime() : Date.now() - 7 * 86400e3;
    return { reply: `${cap(m[1])}: ${fmtHours(timeFor(m[1], since))} ${m[2] || 'this week'}.` };
  }

  // ----- expenses -----
  const ex = /^(i\s+)?(spent|paid|bought|expense)\b/.test(t) && parseExpense(o);
  if (ex && ex.amount) {
    const item = store.add({ type: 'expense', title: cap(ex.what) || 'Expense', amount: ex.amount });
    mem.remember('expense', `${item.title}: ${ex.amount}`);
    const total = monthExpenses().reduce((n, i) => n + (+i.amount || 0), 0);
    return { reply: `💸 Logged ${store.settings.business.currency}${ex.amount.toFixed(2)} for ${item.title}. This month: ${store.settings.business.currency}${total.toFixed(2)}.`, item };
  }

  // ----- focus -----
  m = t.match(/^(?:focus|pomodoro|start focus|focus mode|deep work)(?:\s+(?:for\s+)?(\d+)\s*(?:min(?:ute)?s?)?)?$/);
  if (m) return { reply: `🎯 Focus for ${+m[1] || 25} minute${(+m[1] || 25) === 1 ? '' : 's'}. I'll tell you when it's time for a break.`, action: 'focus', minutes: +m[1] || 25 };

  // ----- daily report -----
  if (/^(daily|end of day|today'?s|my)\s+(report|summary)$|^what did i (do|finish|get done)( today)?$/.test(t)) return { reply: 'Here is your report for today:', action: 'report' };

  // ----- memory -----
  if (/^(which|what) (file|files|pdfs?|documents?|docs?)\b|\b(file|files|pdf|document)s? (did )?i (send|sent|give|gave|share|shared|upload|uploaded|attach|attached)\b|^what did i (do|send|ask|save)|^show (my )?(memory|history)|^(what|which) .* (last|this) (week|month)\b|\bremember when\b/.test(t)) {
    const range = dateRange(t);
    const kinds = /\b(file|files|pdf|pdfs|document|documents|docs?)\b/.test(t) ? ['file'] : /\b(do|did|finish|done)\b/.test(t) ? ['done', 'task', 'meeting', 'reminder', 'note', 'quote', 'invoice', 'timer', 'habit'] : null;
    const q = t.replace(/\b(which|what|file|files|pdfs?|documents?|docs?|did|i|you|send|sent|give|gave|share|shared|upload|uploaded|attach|attached|to|on|in|the|me|my|last|this|week|month|year|today|yesterday|show|memory|history|do|ask|save|from|about|of|a)\b/g, ' ')
      .replace(/\b\d{1,2}(st|nd|rd|th)?\b|\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w*\b|\b(mon|tues|wed|thurs|fri|sat|sun)\w*\b/g, ' ').trim();
    const results = await mem.search({ q, from: range?.[0] || 0, to: range?.[1] || Infinity, kinds });
    return { reply: results.length ? `I found ${results.length} thing${results.length > 1 ? 's' : ''}${range ? ' from ' + new Date(range[0]).toLocaleDateString([], { day: 'numeric', month: 'short' }) + (range[1] - range[0] > 86400e3 + 1 ? ' – ' + new Date(range[1] - 1).toLocaleDateString([], { day: 'numeric', month: 'short' }) : '') : ''}:` : "I don't remember anything like that. I only remember what passed through Sparrow.", results };
  }

  // ----- list reminders / tasks / meetings -----
  if (/^(?:how many|what|which|list|show|read|tell me)(?: are)?(?: all)?(?: of)?(?: my| the)? (reminders?|tasks?|meetings?|appointments?)(?: (?:do|have|did) (?:i|you)(?: got| have| set)?)?(?: (?:i|you) have)?(?: are there)?(?: (?:in|on) (?:your|my|the) list)?(?: (?:set|left|today|now))?$|^(?:my|meri|mere) (reminders?|tasks?|meetings?)(?: (?:kya|kitne|kitni) (?:hain|hai))?$/.test(t)) {
    const want = /task/.test(t) ? ['task'] : /meeting|appointment/.test(t) ? ['meeting'] : ['reminder', 'meeting'];
    const list = store.items.filter(i => want.includes(i.type) && !i.done).sort((a, b) => new Date(a.when || 8e15) - new Date(b.when || 8e15));
    const noun = want[0] === 'task' ? 'task' : want.length === 1 ? 'meeting' : 'reminder';
    if (!list.length) return { reply: `You have no ${noun}s right now.` };
    return { reply: `You have ${list.length} ${noun}${list.length > 1 ? 's' : ''}: ` + list.slice(0, 8).map((i, n) => `${n + 1}. ${i.title}${i.when ? ' — ' + whenText(i.when) : ''}`).join('; ') + (list.length > 8 ? '…' : '.') };
  }

  // ----- done / delete -----
  m = t.match(/^(?:done|completed?|finish(?:ed)?|mark|tick(?: off)?|i (?:did|finished))\s+(.+?)(?:\s+(?:as\s+)?(?:done|complete))?$/);
  if (m) {
    const it = findItem(m[1], store.items.filter(i => !i.done && ['task', 'reminder', 'meeting'].includes(i.type)));
    if (it) { store.update(it.id, { done: true, doneAt: new Date().toISOString() }); mem.remember('done', it.title); return { reply: `Nice! ✔️ "${it.title}" done.` }; }
    const h = findHabit(m[1]); if (h) { const c = bumpHabit(h); return { reply: `👍 ${h.title}: ${c}/${h.target} today.` }; }
    return { reply: `I couldn't find "${m[1]}" in your list.` };
  }
  m = t.match(/^(?:delete|remove|cancel|clear)\s+(?:all\s+)?(?:the\s+|my\s+)?(.+)$/) || t.match(/^(.+?)\s+(?:delete|remove|cancel|hata|khatam)\s*(?:karo|kar do|kr do|do)?$/);
  if (m) {
    const kind = (m[1].match(/\b(meeting|reminder|task|note|habit|customer)s?\b/) || [])[1];
    const pool = store.items.filter(i => i.type !== 'timer' && !i.done && (!kind || i.type === kind || (kind === 'reminder' && i.type === 'meeting')));
    if (/^all\b|\ball (my )?(reminders|tasks|meetings)\b/.test(t)) return { reply: `To be safe I delete one at a time. Which one? ${pool.slice(0, 5).map(i => `"${i.title}"`).join(', ')}` };
    const it = findItem(m[1], pool.length ? pool : store.items.filter(i => i.type !== 'timer'));
    if (it) { store.remove(it.id); return { reply: `🗑️ Removed "${it.title}"${it.when ? ' (' + whenText(it.when) + ')' : ''}.` }; }
    const left = pool.filter(i => i.when).slice(0, 4).map(i => `"${i.title}" ${whenText(i.when)}`).join('; ');
    return { reply: `I couldn't find that one.${left ? ' You have: ' + left + '.' : ''}` };
  }

  // ----- music -----
  m = t.match(/^(?:play|put on)\s+(.+?)(?:\s+on\s+(spotify|youtube|youtube music|apple music|music))?$/);
  if (m && !/^(the )?(music|song|video)$/.test(m[1])) {
    const q = m[1].replace(/\s+(song|music)$/, '');
    const where = (m[2] || store.settings.musicApp || 'spotify').replace('youtube music', 'youtube').replace('apple music', 'music');
    if (N?.playSong) { N.playSong(q, where); return { reply: `🎵 Playing ${q}…` }; }
    if (D) { const r = await D.playSong(q, where); return { reply: r === 'playing' ? `🎵 Playing ${q}.` : `🎵 Opening ${where === 'youtube' ? 'YouTube' : 'Spotify'} for "${q}" — tap play.` }; }
    const url = where === 'youtube' ? 'https://www.youtube.com/results?search_query=' + encodeURIComponent(q)
      : where === 'music' ? 'https://music.apple.com/search?term=' + encodeURIComponent(q) : 'https://open.spotify.com/search/' + encodeURIComponent(q);
    return { reply: `🎵 Opening ${where === 'youtube' ? 'YouTube' : where === 'music' ? 'Apple Music' : 'Spotify'} for "${q}".`, url };
  }

  // ----- email -----
  if (/^(read|check|what('?s| is)) (my )?(latest|last|new(est)?) (email|mail|message)/.test(t)) {
    if (D?.platform() === 'mac') {
      const r = await D.mail('latest');
      if (r?.error) return { reply: "I couldn't read Mail. Open the Mail app once, then allow Sparrow under System Settings → Privacy & Security → Automation." };
      return { reply: `📧 From ${r.from}\nSubject: ${r.subject}\n${r.body.slice(0, 500)}${r.body.length > 500 ? '…' : ''}\n\nSay "reply saying …" or "draft a reply".`, action: 'email', email: r };
    }
    return { reply: 'On this device I can write emails for you, but I can’t read your inbox. Say "email Ali about the invoice".' };
  }
  m = o.match(/^(?:reply|respond)(?:\s+to\s+(?:it|that|the email|this))?(?:\s+(?:saying|that|with))?\s*(.*)$/i);
  if (m && D?.platform() === 'mac') return { reply: 'Writing your reply…', action: 'email-reply', text: m[1] };
  m = o.match(/^(?:email|mail|write (?:an )?email to|send (?:an )?email to)\s+(\S+(?:\s\S+)?)\s+(?:about|saying|that|re)\s+(.+)$/i);
  if (m) return { reply: 'Writing your email…', action: 'email-new', to: m[1], about: m[2] };

  // ----- files (computer) -----
  m = t.match(/^(?:find|search for|look for|where is|where'?s)\s+(?:the\s+|my\s+)?(?:file|document|pdf|doc)?\s*(.+?)(?:\s+file)?$/);
  if (m && D && !/^(a |an )?(restaurant|cafe|shop|place)/.test(m[1])) {
    const files = await D.findFiles(m[1].replace(/\b(from|for)\b/g, ' ').trim());
    return { reply: files.length ? `📁 I found ${files.length} file${files.length > 1 ? 's' : ''}:` : `I couldn't find a file matching "${m[1]}".`, files };
  }
  if (/^(what )?(files? )?(did i work on|i worked on|recent files)( (today|yesterday|this week))?$/.test(t) && D) {
    const days = /today/.test(t) ? 1 : /yesterday/.test(t) ? 2 : 7;
    const files = await D.recentFiles(days);
    return { reply: files.length ? `📁 Files you worked on recently:` : 'I couldn’t see any recent files.', files };
  }
  if (/^(tidy|clean|organi[sz]e|sort)( up)? (my )?downloads( folder)?$/.test(t) && D) {
    const plan = await D.tidyDownloads(false);
    const total = Object.values(plan).reduce((a, b) => a + b, 0);
    if (!total) return { reply: 'Your Downloads folder is already tidy. ✨' };
    pendingTidy = true;
    return { reply: `🧹 I'd sort ${total} files into folders: ${Object.entries(plan).map(([k, v]) => `${k} (${v})`).join(', ')}. Say "yes, tidy it" to go ahead.` };
  }
  if (pendingTidy && /^(yes|yes,? tidy it|do it|go ahead|ok tidy)$/.test(t) && D) {
    pendingTidy = false; const plan = await D.tidyDownloads(true);
    return { reply: `Done! Downloads sorted into ${Object.keys(plan).join(', ')}. 🧹` };
  }
  if (/^(show |open )?(my )?clipboard( history)?$/.test(t)) return { reply: 'Your clipboard history:', action: 'clipboard' };
  if (/^(start|take|begin) (meeting )?notes$|^(record|transcribe) (the |this )?meeting$/.test(t)) return { reply: 'Taking meeting notes…', action: 'meeting-start' };
  if (/^(stop|end|finish) (meeting )?notes$|^(stop|end) (recording|transcribing)$/.test(t)) return { reply: 'Stopping…', action: 'meeting-stop' };

  // ----- settings by voice -----
  if (/^(simple|easy|big text) mode( on)?$|^turn on (simple|easy) mode$/.test(t)) { store.settings.simple = true; store.save(); return { reply: 'Simple mode is on — bigger text and fewer buttons.', action: 'refresh' }; }
  if (/^(simple|easy) mode off$|^turn off (simple|easy) mode$|^normal mode$/.test(t)) { store.settings.simple = false; store.save(); return { reply: 'Simple mode is off.', action: 'refresh' }; }
  m = t.match(/^(?:speak|talk|switch to|change language to|language)\s+(english|urdu|hindi|arabic)$/);
  if (m) { store.settings.lang = { english: 'en', urdu: 'ur', hindi: 'hi', arabic: 'ar' }[m[1]]; store.save(); return { reply: `OK — ${cap(m[1])}.`, action: 'refresh' }; }
  m = t.match(/^(?:theme|switch to|use)\s+(daylight|midnight|pop|sage|sunset)(?: theme)?$/);
  if (m) { store.settings.theme = m[1]; store.save(); return { reply: `Theme: ${cap(m[1])}.`, action: 'refresh' }; }
  if (/^(sync|copy to (my )?(phone|laptop|computer)|sync (my )?(phone|laptop))/.test(t)) return { reply: 'Opening sync…', action: 'sync' };

  // ----- tasks (keep after the more specific ones) -----
  m = o.match(/^(?:add|new|create)?\s*(?:a\s+)?(?:task|todo|to-do|to do)\b[\s,:]*(.+)$/i)
    || o.match(/^(?:add|put)\s+(.+?)\s+(?:to|on)\s+(?:my\s+)?(?:list|tasks|to-?do(?: list)?|shopping list)$/i)
    || o.match(/^i (?:need|have|must|should) to\s+(.+)$/i);
  if (m) {
    const rep = parseRepeat(m[1]);
    const { date, rest, hasTime } = parseWhen(rep ? rep.rest : m[1]);
    const title = cap(tidy(rest)) || cap(m[1]);
    const when = rep ? nextOccurrence(rep.rule, date || new Date(new Date().setHours(9, 0, 0, 0)), new Date(Date.now() - 60000)) : date;
    const item = store.add({ type: 'task', title, when: when ? when.toISOString() : null, repeat: rep?.rule || null, timed: hasTime });
    mem.remember('task', title);
    return { reply: `✅ Added to your tasks: ${title}${when ? ' — ' + whenText(item.when) : ''}${rep ? ' (' + repeatText(rep.rule) + ')' : ''}.`, item };
  }

  // ----- open / call / text / directions / search -----
  m = t.match(/^(?:open|launch|start|go to|show me|run)\s+(.+)$/);
  if (m) {
    const name = m[1];
    const host = N || D;
    if (host && host.openApp(name)) { mem.remember('opened', cap(name)); return { reply: `Opening ${cap(name)}…` }; }
    const ai = AI_APPS.find(a => a.k === name.toLowerCase().replace(/^(the|my) /, '') && a.app);
    if (ai && host && host.openApp(ai.app)) return { reply: `Opening ${ai.n}…` };
    const tg = openTarget(name);
    if (tg) { mem.remember('opened', tg.label); return { reply: `Opening ${tg.label}…`, url: tg.url }; }
    return { reply: `I couldn't find "${name}". Say "search ${name}" to look it up.` };
  }
  m = t.match(/^(?:call|ring|phone)\s+(.+)$/);
  if (m) {
    const num = /^[+\d][\d\s()-]{5,}$/.test(m[1]) ? m[1] : findCustomer(m[1])?.phone;
    if (num) return { reply: `Calling ${m[1]}…`, url: 'tel:' + num.replace(/[^\d+]/g, '') };
  }
  m = t.match(/^(?:text|message|sms|whatsapp)\s+(.+?)(?:\s+(?:saying|that)\s+(.+))?$/);
  if (m) {
    const num = /^[+\d][\d\s()-]{5,}$/.test(m[1]) ? m[1] : findCustomer(m[1])?.phone;
    if (num) {
      const n = num.replace(/[^\d+]/g, '');
      if (/^whatsapp/.test(t)) return { reply: 'Opening WhatsApp…', url: `https://wa.me/${n.replace(/^\+/, '')}${m[2] ? '?text=' + encodeURIComponent(m[2]) : ''}` };
      return { reply: 'Opening Messages…', url: 'sms:' + n + (m[2] ? (isIOS ? '&' : '?') + 'body=' + encodeURIComponent(m[2]) : '') };
    }
  }
  m = t.match(/^(?:directions|navigate|take me|route|how do i get) to\s+(.+)$/);
  if (m) return { reply: `Getting directions to ${m[1]}…`, url: (isIOS ? 'https://maps.apple.com/?daddr=' : 'https://www.google.com/maps/dir/?api=1&destination=') + encodeURIComponent(m[1]) };
  m = t.match(/^(?:search(?: for)?|google|look up)\s+(.+)$/);
  if (m) return { reply: `Searching for ${m[1]}…`, url: 'https://www.google.com/search?q=' + encodeURIComponent(m[1]) };

  // ----- media & volume (computer) -----
  if (D) {
    const media = [
      [/^(play|pause|resume|stop)( (the )?(music|song|video))?$/, 'playpause', 'OK'], [/^(next|skip)( (song|track))?$/, 'next', 'Next'],
      [/^(previous|last|back)( (song|track))?$/, 'prev', 'Previous'], [/^(volume up|louder|turn (it )?up)$/, 'volup', 'Volume up'],
      [/^(volume down|quieter|softer|turn (it )?down)$/, 'voldown', 'Volume down'], [/^(mute|unmute)$/, 'mute', 'OK'],
      [/^lock( (the )?(screen|computer|pc|mac))?$/, 'lock', 'Locking'],
    ];
    for (const [re, cmd, say] of media) if (re.test(t)) { D.media(cmd); return { reply: say + ' 🎵' }; }
    const vm = t.match(/^(?:set )?volume (?:to )?(\d{1,3})%?$/);
    if (vm) { D.media('vol:' + Math.min(100, +vm[1])); return { reply: `Volume ${Math.min(100, +vm[1])}` }; }
  }

  // ----- info -----
  if (/\bweather\b|\btemperature\b|\brain(ing)? today\b/.test(t)) {
    const w = await weatherText();
    return { reply: w || "I couldn't get the weather — check your internet or set your city in Settings." };
  }
  if (/^(what('?s| is) the )?time( is it)?( now)?$|^what time is it/.test(t)) return { reply: `It's ${fmtTime(new Date())}.` };
  if (/^(what('?s| is) )?(the |today'?s )?date$|^what day is it/.test(t))
    return { reply: `Today is ${new Date().toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' })}.` };

  return null;
}

/** Finds the item someone means by title words, day or time: "coming Monday reminder", "3pm meeting", "the dentist one". */
export function findItem(phrase, list) {
  if (!list.length) return null;
  const raw = phrase.toLowerCase().replace(/\b(coming|upcoming)\b/g, 'next');
  const filler = /\b(reminders?|tasks?|meetings?|appointments?|events?|the|my|one|for|on|at|about|that|this|next|wala|wali|ka|ki|ko)\b/g;
  let words = raw.replace(filler, ' ').replace(/\s+/g, ' ').trim();
  let pool = list;
  const r = chrono.parse(raw, new Date(), { forwardDate: true });
  if (r.length) {
    const at = r[0].start.date(), d0 = new Date(at); d0.setHours(0, 0, 0, 0);
    const d1 = new Date(d0.getTime() + 86400e3);
    const same = list.filter(i => i.when && new Date(i.when) >= d0 && new Date(i.when) < d1);
    if (same.length) {
      if (r[0].start.isCertain('hour') && same.length > 1) {
        const near = same.find(i => Math.abs(new Date(i.when) - at) <= 45 * 60e3); if (near) return near;
      }
      pool = same;
      for (const w of r[0].text.toLowerCase().split(/\s+/)) words = words.replace(new RegExp('\\b' + w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b'), ' ');
      words = words.replace(/\s+/g, ' ').trim();
    }
  }
  const ord = { first: 0, second: 1, third: 2, last: -1, latest: -1 }[words];
  if (ord !== undefined) { const sorted = [...pool].sort((a, b) => new Date(a.when || a.created) - new Date(b.when || b.created)); return sorted.at(ord); }
  if (pool !== list && (pool.length === 1 || !words)) return pool[0];
  return (words && fuzzy(words, pool)) || (pool !== list ? pool[0] : null) || fuzzy(phrase, list);
}

export function fuzzy(q, list) {
  const s = q.toLowerCase().trim();
  return list.find(i => i.title.toLowerCase() === s)
    || list.find(i => i.title.toLowerCase().includes(s))
    || list.find(i => s.split(' ').filter(w => w.length > 2).every(w => i.title.toLowerCase().includes(w)));
}
