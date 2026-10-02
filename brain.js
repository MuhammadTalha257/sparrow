// Sparrow's built-in brain: understands everyday requests instantly, offline, no AI needed.
import * as chrono from './lib/chrono.js';
import { store } from './store.js';

export const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

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
export function partOfDay(h = new Date().getHours()) {
  return h >= 5 && h < 12 ? 'morning' : h < 17 ? 'afternoon' : h < 22 ? 'evening' : 'night';
}
export function greetingWord() {
  const p = partOfDay();
  return p === 'morning' ? 'Good morning' : p === 'afternoon' ? 'Good afternoon' : p === 'evening' ? 'Good evening' : 'Hi, night owl';
}

// ---------- dates ----------
function parseWhen(text) {
  const r = chrono.parse(text, new Date(), { forwardDate: true });
  if (!r.length) return { date: null, rest: text };
  const p = r[0];
  const date = p.start.date();
  if (!p.start.isCertain('hour')) date.setHours(9, 0, 0, 0);   // a day with no time → 9 am
  const rest = (text.slice(0, p.index) + ' ' + text.slice(p.index + p.text.length)).replace(/\s+/g, ' ').trim();
  return { date, rest };
}

// ---------- quick actions ----------
export const DEFAULT_QUICK = [
  { k: 'whatsapp', n: 'WhatsApp', e: '💬', url: 'https://wa.me/' },
  { k: 'spotify', n: 'Spotify', e: '🎧', url: 'https://open.spotify.com' },
  { k: 'youtube', n: 'YouTube', e: '▶️', url: 'https://www.youtube.com' },
  { k: 'gmail', n: 'Gmail', e: '✉️', url: 'https://mail.google.com' },
  { k: 'maps', n: 'Maps', e: '🗺️', url: isIOS ? 'https://maps.apple.com' : 'https://maps.google.com' },
  { k: 'instagram', n: 'Instagram', e: '📸', url: 'https://www.instagram.com' },
  { k: 'calendar', n: 'Calendar', e: '📅', url: isIOS ? 'calshow:' : 'https://calendar.google.com' },
  { k: 'chatgpt', n: 'ChatGPT', e: '🤖', url: 'https://chatgpt.com' },
];
/** The person's own quick buttons (editable), falling back to the defaults. */
export function getQuick() { return (store.settings.quick && store.settings.quick.length) ? store.settings.quick : DEFAULT_QUICK; }
export const QUICK = DEFAULT_QUICK;

const SITES = {
  facebook: 'https://www.facebook.com', twitter: 'https://x.com', x: 'https://x.com', tiktok: 'https://www.tiktok.com',
  netflix: 'https://www.netflix.com', linkedin: 'https://www.linkedin.com', reddit: 'https://www.reddit.com',
  google: 'https://www.google.com', drive: 'https://drive.google.com', 'google drive': 'https://drive.google.com',
  outlook: 'https://outlook.live.com', amazon: 'https://www.amazon.co.uk', github: 'https://github.com',
  claude: 'https://claude.ai', gemini: 'https://gemini.google.com', bbc: 'https://www.bbc.co.uk/news',
  'google maps': 'https://maps.google.com', snapchat: 'https://www.snapchat.com', telegram: 'https://t.me/',
  uber: 'https://m.uber.com', notion: 'https://www.notion.so', canva: 'https://www.canva.com', email: 'https://mail.google.com',
  mail: isIOS ? 'message:' : 'https://mail.google.com', music: isIOS ? 'music:' : 'https://music.youtube.com',
  camera: null, settings: isIOS ? 'App-prefs:' : null,
};
function openTarget(name) {
  const n = name.toLowerCase().replace(/^(the|my)\s+/, '').replace(/\s+(app|website|site)$/, '').trim();
  const q = getQuick().find(x => x.k === n || x.n.toLowerCase() === n);
  if (q) return { url: q.url, label: q.n };
  if (n in SITES && SITES[n]) return { url: SITES[n], label: cap(n) };
  if (/^[\w-]+(\.[\w-]+)+(\/\S*)?$/.test(n)) return { url: n.startsWith('http') ? n : 'https://' + n, label: n };
  return null;
}

// ---------- calendar (.ics + Google) ----------
const icsDate = d => new Date(d).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '');
const icsEsc = s => String(s).replace(/([,;\\])/g, '\\$1').replace(/\n/g, '\\n');
export function icsFor(item) {
  const start = new Date(item.when);
  const end = new Date(start.getTime() + (item.type === 'meeting' ? (item.duration || 60) : 15) * 60000);
  const alarm = item.type === 'meeting' ? '-PT10M' : 'PT0M';
  return [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//Sparrow//EN', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT', `UID:${item.id}@sparrow`, `DTSTAMP:${icsDate(new Date())}`,
    `DTSTART:${icsDate(start)}`, `DTEND:${icsDate(end)}`, `SUMMARY:${icsEsc(item.title)}`,
    'DESCRIPTION:Added by Sparrow 🐦',
    'BEGIN:VALARM', 'ACTION:DISPLAY', `DESCRIPTION:${icsEsc(item.title)}`, `TRIGGER:${alarm}`, 'END:VALARM',
    'END:VEVENT', 'END:VCALENDAR',
  ].join('\r\n');
}
export function googleCalUrl(item) {
  const start = new Date(item.when);
  const end = new Date(start.getTime() + (item.type === 'meeting' ? 60 : 15) * 60000);
  const p = new URLSearchParams({ action: 'TEMPLATE', text: item.title, dates: `${icsDate(start)}/${icsDate(end)}`, details: 'Added by Sparrow 🐦' });
  return 'https://calendar.google.com/calendar/render?' + p.toString();
}

// ---------- weather (free, no key) ----------
let cachedLoc = null, cachedAt = 0;
async function getJSON(url) { const r = await fetch(url); if (!r.ok) throw new Error(r.status); return r.json(); }
async function cityName(lat, lon) {
  try {
    const j = await getJSON(`https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${lat}&longitude=${lon}&localityLanguage=en`);
    return j.city || j.locality || j.principalSubdivision || '';
  } catch { return ''; }
}
async function location() {
  if (cachedLoc && Date.now() - cachedAt < 20 * 60e3) return cachedLoc;
  cachedAt = Date.now();
  const city = (store.settings.city || '').trim();
  if (city) {
    try {
      const g = await getJSON('https://geocoding-api.open-meteo.com/v1/search?count=1&name=' + encodeURIComponent(city));
      const r = g.results?.[0];
      if (r) return (cachedLoc = { lat: r.latitude, lon: r.longitude, city: r.name });
    } catch {}
  }
  try {
    // Where you are right now (phone GPS / Wi-Fi) — right even when you travel.
    const pos = await new Promise((res, rej) => navigator.geolocation
      ? navigator.geolocation.getCurrentPosition(res, rej, { timeout: 8000, maximumAge: 10 * 60e3 }) : rej());
    const { latitude: lat, longitude: lon } = pos.coords;
    return (cachedLoc = { lat, lon, city: await cityName(lat, lon) });
  } catch {}
  try {
    const j = await getJSON('https://ipapi.co/json/');
    if (j.latitude) return (cachedLoc = { lat: j.latitude, lon: j.longitude, city: j.city || '' });
  } catch {}
  return null;
}
const WMO = c => c === 0 ? 'clear' : c <= 2 ? 'partly cloudy' : c === 3 ? 'cloudy' : c <= 48 ? 'foggy' : c <= 57 ? 'drizzly'
  : c <= 67 || (c >= 80 && c <= 82) ? 'rainy' : c <= 77 || c === 85 || c === 86 ? 'snowy' : c >= 95 ? 'stormy' : 'mild';
export async function weatherText() {
  const loc = await location();
  if (!loc) return null;
  const f = navigator.language === 'en-US';
  const u = `https://api.open-meteo.com/v1/forecast?latitude=${loc.lat}&longitude=${loc.lon}&current=temperature_2m,weather_code`
    + `&daily=temperature_2m_max,precipitation_probability_max&timezone=auto&forecast_days=1${f ? '&temperature_unit=fahrenheit' : ''}`;
  try {
    const j = await getJSON(u);
    const t = Math.round(j.current.temperature_2m), hi = Math.round(j.daily.temperature_2m_max[0]);
    const rain = j.daily.precipitation_probability_max?.[0] ?? 0;
    let s = `${loc.city ? 'In ' + loc.city + ' it' : 'It'}'s ${t}° and ${WMO(j.current.weather_code)}, high of ${hi}°.`;
    if (rain >= 50) s += ` ${rain}% chance of rain — take an umbrella ☔`;
    return s;
  } catch { return null; }
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
  if (!short) {
    const first = items.find(i => !i.done && new Date(i.when) > new Date());
    if (first) s += ` Next: ${first.title} at ${fmtTime(first.when)}.`;
  }
  return s;
}
export async function briefing() {
  const name = store.settings.name ? `, ${store.settings.name}` : '';
  let s = `${greetingWord()}${name}! It's ${fmtTime(new Date())}.`;
  const w = await weatherText();
  if (w) s += ' ' + w;
  s += ' ' + spokenPlan(new Date());
  return s;
}

// ---------- daily routine (offline) ----------
const endOfDay = d => { const x = new Date(d); x.setHours(24, 0, 0, 0); return x; };
const sameDay = (a, b) => new Date(a).toDateString() === new Date(b).toDateString();
/** Tasks for a day: due that day or earlier, or added that day without a date. */
export function tasksForDay(date = new Date(), includeUndated = false) {
  const end = endOfDay(date);
  return store.items.filter(i => i.type === 'task' && !i.done && (
    i.when ? new Date(i.when) < end : (includeUndated || sameDay(i.created, date))));
}
export function spokenList(titles, max = 5) {
  const t = titles.slice(0, max);
  if (titles.length > max) t.push(`${titles.length - max} more`);
  return t.length <= 1 ? (t[0] || '') : t.slice(0, -1).join(', ') + ' and ' + t[t.length - 1];
}
/** "You have 2 meetings: … Your tasks for today are: …" — written for speaking. */
export function spokenPlan(date = new Date()) {
  const items = store.onDay(date);
  const now = new Date();
  const meetings = items.filter(i => i.type === 'meeting' && (!sameDay(date, now) || new Date(i.when) > new Date(now - 30 * 60e3)));
  const reminders = items.filter(i => i.type === 'reminder' && !i.done);
  const d0 = new Date(date); d0.setHours(0, 0, 0, 0);
  const tasks = tasksForDay(date, true);
  const dated = tasks.filter(i => i.when && new Date(i.when) >= d0), overdue = tasks.filter(i => i.when && new Date(i.when) < d0);
  const undated = tasks.filter(i => !i.when);
  const parts = [];
  if (meetings.length) parts.push(`You have ${meetings.length} meeting${meetings.length > 1 ? 's' : ''}: ` + spokenList(meetings.map(m => `${m.title} at ${fmtTime(m.when)}`), 4) + '.');
  if (dated.length) parts.push(`Your task${dated.length > 1 ? 's for today are' : ' for today is'}: ` + spokenList(dated.map(i => i.title)) + '.');
  if (undated.length) parts.push(`On your list: ` + spokenList(undated.map(i => i.title), 4) + '.');
  if (overdue.length) parts.push(`And ${overdue.length === 1 ? 'one task' : overdue.length + ' tasks'} from before: ` + spokenList(overdue.map(i => i.title), 3) + '.');
  if (reminders.length) parts.push(`${reminders.length === 1 ? 'One reminder' : reminders.length + ' reminders'} later: ` + spokenList(reminders.map(r => `${r.title} at ${fmtTime(r.when)}`), 3) + '.');
  return parts.length ? parts.join(' ') : 'Your day is clear — no meetings or tasks yet.';
}
export function moveToTomorrow(id) {
  const it = store.items.find(i => i.id === id); if (!it) return false;
  const t = new Date(); t.setDate(t.getDate() + 1);
  const d = it.when ? new Date(it.when) : new Date(t.setHours(9, 0, 0, 0));
  d.setFullYear(t.getFullYear(), t.getMonth(), t.getDate());
  store.update(id, { when: d.toISOString(), notified: false, soonDone: false });
  return true;
}
export function moveRestToTomorrow() {
  const list = tasksForDay(new Date());
  list.forEach(i => moveToTomorrow(i.id));
  return list.length;
}

// ---------- the brain ----------
/**
 * Returns { reply, item?, url?, list? } or null when the AI should answer instead.
 */
export async function handle(input) {
  const o = input.trim().replace(/^(hey |hi |ok )?sparrow[,!\s]*/i, '').replace(/\s*please[.!]?$/i, '')
    .replace(/^(um+|uh+|erm|so|okay|ok|well|please|can you|could you)[,\s]+/i, '');
  const t = o.toLowerCase().replace(/[?!.]+$/, '');
  if (!t) return { reply: 'Yes? 🐦' };

  if (/^(help|what can you do|commands)\b/.test(t)) return { reply:
    'Try:\n• remind me to call mum at 6pm\n• meeting with Ali Friday 3pm\n• add task buy milk\n• note wifi password is 1234\n• what\'s on today?\n• open WhatsApp · directions to the station\n• weather\nAnything else, just ask — I\'ll think about it.' };

  if (/^(hi|hello|hey|salam|assalam|good (morning|afternoon|evening))\b/.test(t) && t.split(' ').length <= 4)
    return { reply: `${greetingWord()}${store.settings.name ? ', ' + store.settings.name : ''}! How can I help? 🐦` };

  // What's on…
  if (/(what('?s| is) (on|up|planned)|my (day|agenda|schedule|plan)|what do i have|anything (on|planned)|agenda|schedule for)/.test(t)) {
    const d = /tomorrow/.test(t) ? new Date(Date.now() + 86400000) : new Date();
    return { reply: daySummary(d), list: d };
  }
  if (/^(show |list |what are )?(my )?(tasks|to-?dos|todo list|to do list)$/.test(t)) {
    const open = store.openTasks();
    return { reply: open.length ? 'Your tasks:\n' + open.map(i => '• ' + i.title + (i.when ? ` (${whenText(i.when)})` : '')).join('\n') : 'No open tasks. 🎉' };
  }

  // Daily routine
  if (/^((give me|read|tell me|what('?s| is| are)) )?(my |the )?(morning briefing|briefing|tasks?( for| of)? today|today'?s tasks|plan for today)$|^brief me/.test(t))
    return { reply: spokenPlan(new Date()) };
  if (/^(start |open |do )?(my |the )?(evening |night |daily )?check[- ]?in\b/.test(t))
    return { reply: 'Opening your check-in.', action: 'checkin' };
  let mv = t.match(/^(?:move|shift|push|postpone|reschedule)\s+(.+?)(?:\s+(?:to|till|until|for)\s+tomorrow)?$/);
  if (mv && (/tomorrow/.test(t) || t.startsWith('postpone'))) {
    if (/^(everything|all|the rest|rest|all( my)? tasks|remaining( tasks)?|them|the remaining( ones)?)$/.test(mv[1])) {
      const n = moveRestToTomorrow();
      return { reply: n ? `Done. I moved ${n} task${n > 1 ? 's' : ''} to tomorrow.` : 'Nothing left for today to move.' };
    }
    const it = fuzzy(mv[1].replace(/^(the|my) /, ''), store.items.filter(i => !i.done && i.type !== 'note'));
    if (it && moveToTomorrow(it.id)) return { reply: `Moved "${it.title}" to tomorrow.` };
    return { reply: `I couldn't find "${mv[1]}" in your list.` };
  }

  // Reminders
  let m = o.match(/^(?:please\s+)?(?:remind(?:s|ed)? me|set (?:a )?reminder|reminder|don'?t let me forget)\b[\s,:]*(.*)$/i);
  if (m) {
    let { date, rest } = parseWhen(m[1]);
    let title = cap(tidy(rest.replace(/^(to|that|about)\s+/i, '')));
    if (!title) title = 'Reminder';
    let note = '';
    if (!date) { date = new Date(Date.now() + 3600e3); note = ' (in 1 hour — say a time to change it)'; }
    const item = store.add({ type: 'reminder', title, when: date.toISOString() });
    return { reply: `⏰ I'll remind you: ${title} — ${whenText(item.when)}${note}.`, item };
  }

  // Meetings
  if (/\b(meeting|meet|call with|appointment|interview|lunch with|dinner with|catch ?up|zoom|teams call|doctor|dentist)\b/.test(t) ||
      /^(schedule|book|set up|arrange)\b/.test(t)) {
    const { date, rest } = parseWhen(o);
    if (date) {
      let title = tidy(rest.replace(/^(add|schedule|book|set up|arrange|create|i have|there'?s|put)\s+(a |an )?/i, '')
        .replace(/\s+(to|in|on) (my )?(calendar|agenda|schedule)$/i, ''));
      title = cap(title || 'Meeting');
      const item = store.add({ type: 'meeting', title, when: date.toISOString(), duration: 60 });
      return { reply: `🗓️ Added: ${title} — ${whenText(item.when)}.`, item };
    }
  }

  // Notes
  m = o.match(/^(?:take a note|note(?: down)?|write down|remember that|save (?:a )?note|jot down)\b[\s,:]*(.+)$/i);
  if (m) {
    const item = store.add({ type: 'note', title: cap(m[1].trim()) });
    return { reply: `📝 Saved your note.`, item };
  }

  // Tasks
  m = o.match(/^(?:add|new|create)?\s*(?:a\s+)?(?:task|todo|to-do|to do)\b[\s,:]*(.+)$/i)
    || o.match(/^(?:add|put)\s+(.+?)\s+(?:to|on)\s+(?:my\s+)?(?:list|tasks|to-?do(?: list)?|shopping list)$/i)
    || o.match(/^i (?:need|have|must|should) to\s+(.+)$/i);
  if (m) {
    const { date, rest } = parseWhen(m[1]);
    const title = cap(tidy(rest)) || cap(m[1]);
    const item = store.add({ type: 'task', title, when: date ? date.toISOString() : null });
    return { reply: `✅ Added to your tasks: ${title}${date ? ' — ' + whenText(item.when) : ''}.`, item };
  }

  // Done / delete
  m = t.match(/^(?:done|completed?|finish(?:ed)?|mark|tick(?: off)?|i (?:did|finished))\s+(.+?)(?:\s+(?:as\s+)?(?:done|complete))?$/);
  if (m) {
    const it = fuzzy(m[1], store.items.filter(i => !i.done && i.type !== 'note'));
    if (it) { store.update(it.id, { done: true }); return { reply: `Nice! ✔️ "${it.title}" done.` }; }
    return { reply: `I couldn't find "${m[1]}" in your list.` };
  }
  m = t.match(/^(?:delete|remove|cancel)\s+(?:the\s+|my\s+)?(.+)$/);
  if (m) {
    const it = fuzzy(m[1].replace(/\s+(meeting|reminder|task|note)$/, ''), store.items);
    if (it) { store.remove(it.id); return { reply: `🗑️ Removed "${it.title}".` }; }
    return { reply: `I couldn't find "${m[1]}".` };
  }

  // Open / call / text / directions / search
  m = t.match(/^(?:open|launch|start|go to|show me)\s+(.+)$/);
  if (m) {
    const tg = openTarget(m[1]);
    // Android / Windows app: open any installed app or folder by name
    const host = window.SparrowNative || window.SparrowDesktop;
    if (host && host.openApp(m[1])) return { reply: `Opening ${cap(m[1])}…` };
    if (tg) return { reply: `Opening ${tg.label}…`, url: tg.url };
    return { reply: `I couldn't find "${m[1]}". Say "search ${m[1]}" to look it up.` };
  }
  m = t.match(/^(?:call|ring|phone)\s+([+\d][\d\s()-]{5,})$/);
  if (m) return { reply: `Calling ${m[1]}…`, url: 'tel:' + m[1].replace(/[^\d+]/g, '') };
  m = t.match(/^(?:text|message|sms)\s+([+\d][\d\s()-]{5,})(?:\s+(?:saying|that)\s+(.+))?$/);
  if (m) return { reply: 'Opening Messages…', url: 'sms:' + m[1].replace(/[^\d+]/g, '') + (m[2] ? (isIOS ? '&' : '?') + 'body=' + encodeURIComponent(m[2]) : '') };
  m = t.match(/^(?:directions|navigate|take me|route|how do i get) to\s+(.+)$/);
  if (m) return { reply: `Getting directions to ${m[1]}…`,
    url: (isIOS ? 'https://maps.apple.com/?daddr=' : 'https://www.google.com/maps/dir/?api=1&destination=') + encodeURIComponent(m[1]) };
  m = t.match(/^(?:search(?: for)?|google|look up)\s+(.+)$/);
  if (m) return { reply: `Searching for ${m[1]}…`, url: 'https://www.google.com/search?q=' + encodeURIComponent(m[1]) };
  m = t.match(/^(?:youtube|play)\s+(.+?)(?:\s+on youtube)?$/);
  if (m && (/youtube/.test(t) || t.startsWith('youtube'))) return { reply: `Searching YouTube for ${m[1]}…`, url: 'https://www.youtube.com/results?search_query=' + encodeURIComponent(m[1]) };

  // Media & volume (Windows app)
  const D = window.SparrowDesktop;
  if (D) {
    const media = [
      [/^(play|pause|resume|stop)( (the )?(music|song|video))?$/, 'playpause', 'OK'],
      [/^(next|skip)( (song|track))?$/, 'next', 'Next'],
      [/^(previous|last|back)( (song|track))?$/, 'prev', 'Previous'],
      [/^(volume up|louder|turn (it )?up)$/, 'volup', 'Volume up'],
      [/^(volume down|quieter|softer|turn (it )?down)$/, 'voldown', 'Volume down'],
      [/^(mute|unmute)$/, 'mute', 'OK'],
      [/^lock( (the )?(screen|computer|pc))?$/, 'lock', 'Locking'],
    ];
    for (const [re, cmd, say] of media) if (re.test(t)) { D.media(cmd); return { reply: say + ' 🎵' }; }
    const vm = t.match(/^(?:set )?volume (?:to )?(\d{1,3})%?$/);
    if (vm) { D.media('vol:' + Math.min(100, +vm[1])); return { reply: `Volume ${Math.min(100, +vm[1])}` }; }
  }

  // Info
  if (/\bweather\b|\btemperature\b|\brain(ing)? today\b/.test(t)) {
    const w = await weatherText();
    return { reply: w || "I couldn't get the weather — check your internet or set your city in Settings." };
  }
  if (/^(what('?s| is) the )?time( is it)?( now)?$|^what time is it/.test(t)) return { reply: `It's ${fmtTime(new Date())}.` };
  if (/^(what('?s| is) )?(the |today'?s )?date$|^what day is it/.test(t))
    return { reply: `Today is ${new Date().toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' })}.` };

  return null;
}

function fuzzy(q, list) {
  const s = q.toLowerCase().trim();
  return list.find(i => i.title.toLowerCase() === s)
    || list.find(i => i.title.toLowerCase().includes(s))
    || list.find(i => s.split(' ').filter(w => w.length > 2).every(w => i.title.toLowerCase().includes(w)));
}
