// Zuffi Business on the phone / tablet / Windows — the same leads, money, staff, stock and business
// info as the Mac dashboard, kept in step by bizsync.js (link devices with a QR code).
// Design: "Nocturne Ledger" — one big number per card, one meaning per colour:
//   rose = people waiting · amber = money & stock · violet = time & linked · green = done.
import * as bs from './bizsync.js';
import * as C from './countries.js';
import * as Z from './zblob.js';
import * as account from './account.js';

const $ = (s, el = document) => el.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const iso = (d = new Date()) => { const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 10); };
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const N = window.SparrowNative || null;
const LS = { get: (k, d = '') => { try { return localStorage.getItem(k) ?? d; } catch { return d; } }, set: (k, v) => { try { localStorage.setItem(k, v); } catch {} } };
// Professional colours (dash.css): red = needs you, amber = due, accent = your colour, green = done, grey = quiet
const ROSE = 'var(--bz-hot)', AMBER = 'var(--bz-warn)', VIOLET = 'var(--accent)', GREEN = 'var(--bz-ok)', GREY = 'var(--bz-grey)';

const PACKS = {
  realEstate: { label: 'Estate agent', icon: '🏠' }, salon: { label: 'Salon / barber / beauty', icon: '💇' }, clinic: { label: 'Clinic / dentist', icon: '🩺' },
  shop: { label: 'Shop / online store', icon: '🛍️' }, restaurant: { label: 'Restaurant / takeaway', icon: '🍽️' }, services: { label: 'Trades & services', icon: '🛠️' },
  freelancer: { label: 'Freelancer', icon: '💻' },
};
const freelance = () => kind() === 'freelancer';
// Business types follow the country: Pakistan → estate agents; UK → small businesses; elsewhere → all.
export const kindsFor = c => c === 'PK' ? ['realEstate'] : c === 'GB' ? ['salon', 'restaurant', 'clinic', 'shop', 'services', 'freelancer'] : Object.keys(PACKS);
const kind = () => { const ok = kindsFor(country()), k = bs.cfg('kind') || ok[0]; return ok.includes(k) ? k : ok[0]; };
const estate = () => kind() === 'realEstate';
const country = () => { const c = bs.cfg('country'); return c && c !== 'OTHER' ? c : (C.guess() || 'OTHER'); };
const feats = () => C.features(country());
const cur = () => bs.cfg('currency') || (country() === 'OTHER' ? '$' : C.symbol(country()));
const stages = () => ({
  realEstate: ['New', 'Contacted', 'Site visit', 'Negotiating', 'Won', 'Lost'], salon: ['New', 'Contacted', 'Booked', 'Visited', 'Regular', 'Lost'],
  clinic: ['New', 'Contacted', 'Booked', 'Visited', 'Regular', 'Lost'], restaurant: ['New', 'Contacted', 'Booked', 'Visited', 'Regular', 'Lost'],
  shop: ['New', 'Contacted', 'Quoted', 'Ordered', 'Delivered', 'Lost'], services: ['New', 'Contacted', 'Quoted', 'Negotiating', 'Won', 'Lost'],
  freelancer: ['New', 'Proposal sent', 'Working', 'Invoiced', 'Paid', 'Lost'],
}[kind()] || ['New', 'Contacted', 'Won', 'Lost']);
const labels = () => ({
  realEstate: ['Wants', 'Area', 'Budget', 'Deal value'], salon: ['Service', 'Preferred day / staff', 'Budget', 'Spent'], clinic: ['Service', 'Preferred day / staff', 'Budget', 'Spent'],
  restaurant: ['Booking for', 'Party size / time', 'Budget', 'Spent'], shop: ['Product', 'Delivery area', 'Budget', 'Order value'], services: ['Job', 'Location', 'Budget', 'Job value'],
  freelancer: ['Project', 'Deadline', 'Budget', 'Project value'],
}[kind()]);
const SALE = ['Won', 'Visited', 'Regular', 'Ordered', 'Delivered', 'Paid'];
const incomeCats = () => estate() ? ['Commission', 'Token / advance', 'Installment received', 'Rent collected', 'Other income'] : freelance() ? ['Project fees', 'Hourly work', 'Retainer', 'Other income'] : ['Sales', 'Services', 'Products', 'Deposits', 'Other income'];
const expenseCats = () => estate() ? ['Salaries', 'Office rent', 'Marketing & ads', 'Portal fees', 'Dealer share', 'Fuel & travel', 'Utilities & bills', 'Advance to staff', 'Other']
  : freelance() ? ['Software & tools', 'Equipment', 'Travel', 'Marketing', 'Accountant', 'Tax set aside', 'Other']
  : ['Wages', 'Rent', 'Stock & supplies', 'Utilities', 'Marketing', 'Equipment', 'Card / booking fees', 'VAT & tax', 'Advance to staff', 'Other'];
const methods = () => feats().methods;
const SOURCES_BASE = ['WhatsApp', 'Missed call', 'Phone call', 'Facebook', 'Instagram', 'TikTok', 'Google', 'Website', 'Referral', 'Walk-in', 'WhatsApp group'];
const sources = () => [...new Set([...feats().portals, ...SOURCES_BASE])];

const f = (r, ...names) => { for (const n of names) for (const k in r) if (k.toLowerCase() === n.toLowerCase()) return r[k] || ''; return ''; };
export const num = v => { const s = String(v || '').toLowerCase().replace(/,/g, ''); const m = s.match(/(\d+(?:\.\d+)?)\s*(crore|cr|lakh|lac|k|m|million)?/); if (!m) return 0; const x = +m[1]; return x * ({ crore: 1e7, cr: 1e7, lakh: 1e5, lac: 1e5, k: 1e3, m: 1e6, million: 1e6 }[m[2]] || 1); };
/** Rs 4.2 lac / £1,240 / $12.5k — short, readable money. */
const money = v => {
  const n = Math.round(v), c = cur();
  if (c === 'Rs' || c === '₹') { const a = Math.abs(n); return c + ' ' + (a >= 1e7 ? +(n / 1e7).toFixed(2) + ' cr' : a >= 1e5 ? +(n / 1e5).toFixed(1) + ' lac' : n.toLocaleString()); }
  return (c.length > 1 ? c + ' ' : c) + (Math.abs(n) >= 1e6 ? +(n / 1e6).toFixed(1) + 'm' : n.toLocaleString());
};
const when = s => { if (!s) return 0; const t = Date.parse(String(s).replace(' ', 'T')); return isNaN(t) ? 0 : t; };
const mins = t => Math.round((Date.now() - t) / 60000);
const first = n => String(n || '').trim().split(/\s+/)[0] || 'there';

// Every client / staff member gets their own little animated face (blobatar, MIT) — same name, same face, on every device.
let blob = null; const blobCache = new Map();
import('./lib/blobatar.js').then(m => {
  blob = m.blobatar;
  if (root) render();
}).catch(() => {});
function face(name, c, letter) {
  const n = String(name || '').trim();
  if (blob && n && !/^[+\d\s-]+$/.test(n)) {
    let svg = blobCache.get(n);
    if (!svg) { try { svg = blob(n.toLowerCase(), { background: 'circle' }); } catch { svg = ''; } blobCache.set(n, svg); }
    if (svg) return `<span class="bz-av blob" style="--c:${c}">${svg}</span>`;
  }
  return `<span class="bz-av" style="--c:${c}">${esc(letter || (n || '?').charAt(0).toUpperCase())}</span>`;
}
const bizName = () => bs.cfg('name') || '';

// WhatsApp links (wa.me on phones, the WhatsApp app on computers)
const DIAL = { PK: '92', GB: '44', IN: '91', AE: '971', SA: '966', BD: '880', US: '1', CA: '1', AU: '61', NG: '234', KE: '254', ZA: '27', QA: '974', KW: '965', OM: '968', BH: '973', EG: '20', TR: '90', MY: '60', ID: '62', IE: '353', NZ: '64' };
function intl(phone) {
  let p = String(phone || '').replace(/[^\d+]/g, '');
  if (!p) return '';
  if (p.startsWith('+')) return p.slice(1);
  if (p.startsWith('00')) return p.slice(2);
  if (p.startsWith('0') && DIAL[country()]) return DIAL[country()] + p.slice(1);
  return p;
}
export function waLink(phone, text = '') {
  const n = intl(phone), t = text ? encodeURIComponent(text) : '';
  if (window.SparrowDesktop) return `whatsapp://send?${n ? 'phone=' + n + '&' : ''}text=${t}`;
  return n ? `https://wa.me/${n}${t ? '?text=' + t : ''}` : `https://wa.me/?text=${t}`;
}
function openWa(phone, text) { const a = document.createElement('a'); a.href = waLink(phone, text); a.target = '_blank'; a.rel = 'noopener'; document.body.appendChild(a); a.click(); a.remove(); }

// ---------------- leads ----------------
const leads = () => bs.rows('Leads').map(({ k, r }) => ({ k, r, name: f(r, 'Name'), phone: f(r, 'Phone'), status: f(r, 'Status') || 'New', pri: f(r, 'Priority'),
  next: f(r, 'Next follow-up'), added: f(r, 'Added'), last: f(r, 'Last contact'), value: f(r, 'Value'), msgAt: f(r, 'Last message at'), replied: f(r, 'Replied at'),
  src: f(r, 'Source'), agent: f(r, 'Assigned to') }));
const isOpen = l => !['Won', 'Lost', 'Delivered', 'Regular', 'Visited'].includes(l.status);
const dueToday = l => isOpen(l) && l.next && l.next.slice(0, 10) <= iso();
const overdue = l => isOpen(l) && l.next && l.next.slice(0, 10) < iso();
const stageColor = s => ({ New: ROSE, Contacted: VIOLET, 'Site visit': VIOLET, Booked: VIOLET, Negotiating: AMBER, Quoted: AMBER, Won: GREEN, Ordered: GREEN, Visited: GREEN, Regular: GREEN, Delivered: GREEN, Lost: GREY }[s] || ROSE);

/** People who wrote and are still waiting for an answer (speed-to-lead). */
export function waiting() {
  return leads().filter(l => {
    if (l.status !== 'New' || !l.msgAt) return false;
    const t = when(l.msgAt); if (!t) return false;
    const m = mins(t);
    return m >= 3 && m < 24 * 60 && !(when(l.replied) >= t) && !(when(l.last) >= t - 60000);
  }).map(l => ({ ...l, waitMin: mins(when(l.msgAt)) })).sort((a, b) => b.waitMin - a.waitMin);
}
/** For the main dashboard: which business this is (country decides the type). */
export function profile() { return { country: country(), kind: kind(), estate: estate(), freelance: freelance(), name: bizName(), label: (PACKS[kind()] || {}).label || 'Business', icon: (PACKS[kind()] || {}).icon || '💼', cur: cur() }; }
/** For the main dashboard: the numbers that need you today. */
export function stats() {
  const L = leads(), owed = bs.rows('Due').filter(({ r }) => !/paid/i.test(f(r, 'Status')));
  return { waiting: waiting(), due: L.filter(dueToday), open: L.filter(isOpen).length, total: L.length, owed: owed.reduce((a, { r }) => a + num(f(r, 'Amount')), 0), owedCount: owed.length, cur: cur() };
}
/** Enquiries nobody followed up — the "lost money report". */
function forgotten() {
  const cut = iso(addDays(new Date(), -3)), today = iso();
  return leads().filter(l => isOpen(l) && !(l.next && l.next.slice(0, 10) >= today) && ((l.last || l.added || l.msgAt || '').slice(0, 10) || '0') <= cut && (l.phone || l.name));
}
function avgDeal() {
  const set = num(bs.cfg('avgDeal')); if (set) return set;
  const won = leads().filter(l => SALE.includes(l.status) && num(l.value)); if (won.length >= 3) return won.reduce((a, l) => a + num(l.value), 0) / won.length;
  const pk = ['Rs', '₹'].includes(cur());
  return ({ realEstate: pk ? 50000 : 1500, salon: pk ? 2500 : 40, clinic: pk ? 4000 : 80, restaurant: pk ? 2000 : 30, shop: pk ? 3000 : 50, services: pk ? 8000 : 250 })[kind()];
}
const hourRate = () => num(bs.cfg('hourRate')) || (['Rs', '₹'].includes(cur()) ? 1000 : 25);

// ---------------- wins: what Zuffi did for you (synced) ----------------
export function logWin(kindName, detail, minutes = 2, value = 0) {
  bs.put('Wins', { Date: new Date().toISOString().slice(0, 16).replace('T', ' '), Kind: kindName, Detail: String(detail || '').slice(0, 80), Minutes: String(minutes), Value: value ? String(Math.round(value)) : '' });
}
function weekStats() {
  const since = iso(addDays(new Date(), -6));
  let minutes = 0, earned = 0, actions = 0;
  for (const { r } of bs.rows('Wins')) { if ((f(r, 'Date') || '').slice(0, 10) < since) continue; minutes += num(f(r, 'Minutes')); earned += num(f(r, 'Value')); actions++; }
  const newLeads = leads().filter(l => (l.added || '').slice(0, 10) >= since).length;
  minutes += newLeads * 2;
  let moneyIn = 0; for (const { r } of bs.rows('Money')) if ((f(r, 'Date') || '') >= since && f(r, 'Type').toLowerCase().startsWith('inc')) moneyIn += num(f(r, 'Amount'));
  return { minutes, hours: Math.round(minutes / 6) / 10, earned, actions, newLeads, moneyIn };
}

// Zuffi's mood follows the business: someone waiting → surprised, a sale today → happy, late night → sleepy.
function zMood() {
  const h = new Date().getHours();
  if (h >= 23 || h < 6) return 'sleepy';
  if (waiting().length) return 'surprised';
  if (bs.rows('Wins').some(({ r }) => f(r, 'Kind') === 'deal' && (f(r, 'Date') || '').startsWith(iso()))) return 'happy';
  return 'idle';
}
const HUES = { rose: 350, violet: 262, sky: 205, mint: 155, amber: 40, coral: 15 };
const zHue = () => { const a = bs.cfg('accent'); return a && HUES[a] != null ? { hue: HUES[a] } : {}; };

// ---------------- security: PIN lock, auto-lock, privacy mode ----------------
let unlockedAt = 0, lastTouch = Date.now();
const pinSet = () => !!LS.get('zuffiPinHash');
const lockMins = () => +(LS.get('zuffiLockMins', '5')) || 5;
function locked() { return pinSet() && (!unlockedAt || Date.now() - lastTouch > lockMins() * 60000); }
async function pinHash(pin, salt) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(pin), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', salt: new TextEncoder().encode(salt), iterations: 150000, hash: 'SHA-256' }, k, 256);
  return btoa(String.fromCharCode(...new Uint8Array(bits)));
}
let pinTries = 0, pinWaitUntil = 0;
function renderLock() {
  unlockedAt = 0;
  const fab = document.getElementById('bzFab'); if (fab) fab.hidden = true;
  let entry = '';
  root.innerHTML = `<div class="bz-lock"><div class="bz-lockface">${Z.svg('shy', zHue())}</div><b>Business is locked</b><small>Enter your PIN</small>
    <div class="bz-dots">${'<i></i>'.repeat(6)}</div><div class="bz-pad">${[1, 2, 3, 4, 5, 6, 7, 8, 9, '', 0, '⌫'].map(k => `<button data-k="${k}" ${k === '' ? 'disabled' : ''}>${k}</button>`).join('')}</div><small class="bz-lockmsg"></small></div>`;
  const dots = [...root.querySelectorAll('.bz-dots i')], msg = root.querySelector('.bz-lockmsg');
  const show = () => dots.forEach((d, i) => d.classList.toggle('on', i < entry.length));
  root.onclick = async e => {
    const b = e.target.closest('[data-k]'); if (!b) return;
    if (Date.now() < pinWaitUntil) { msg.textContent = `Too many tries — wait ${Math.ceil((pinWaitUntil - Date.now()) / 1000)} s`; return; }
    const k = b.dataset.k;
    if (k === '⌫') entry = entry.slice(0, -1); else if (entry.length < 6) entry += k;
    show();
    if (entry.length >= 4 && entry.length === +(LS.get('zuffiPinLen', '4'))) {
      const ok = (await pinHash(entry, LS.get('zuffiPinSalt'))) === LS.get('zuffiPinHash');
      if (ok) { pinTries = 0; unlockedAt = lastTouch = Date.now(); root.onclick = null; render(); }
      else { pinTries++; entry = ''; show(); root.querySelector('.bz-dots').classList.add('shake'); setTimeout(() => root.querySelector('.bz-dots')?.classList.remove('shake'), 400);
        if (pinTries >= 5) { pinWaitUntil = Date.now() + 30000 * (pinTries - 4); msg.textContent = 'Too many tries — wait a little'; } else msg.textContent = 'Wrong PIN'; }
    }
  };
}
['pointerdown', 'keydown'].forEach(ev => document.addEventListener(ev, () => { if (unlockedAt) lastTouch = Date.now(); }, true));
setInterval(() => { if (pinSet() && unlockedAt && Date.now() - lastTouch > lockMins() * 60000 && root) { unlockedAt = 0; document.querySelector('.bz-sheet')?.remove(); render(); } }, 15000);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'hidden' && pinSet()) lastTouch = Math.min(lastTouch, Date.now()); });
function setPin() {
  const { w } = sheet(pinSet() ? 'Change PIN' : 'Lock Business with a PIN', `<p class="bz-p">Business opens only with this PIN on this device. It locks again after ${lockMins()} idle minutes.</p>
    ${field('pin1', 'New PIN (4–6 digits)', '', 'type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"')}${field('pin2', 'Type it again', '', 'type="password" inputmode="numeric" maxlength="6" autocomplete="new-password"')}`, async w => {
    const a = read(w, 'pin1'), b = read(w, 'pin2');
    if (!/^\d{4,6}$/.test(a)) { toast('Use 4 to 6 digits'); return false; }
    if (a !== b) { toast('The two PINs are different'); return false; }
    const salt = crypto.getRandomValues(new Uint32Array(4)).join('-');
    LS.set('zuffiPinSalt', salt); LS.set('zuffiPinLen', String(a.length)); LS.set('zuffiPinHash', await pinHash(a, salt));
    unlockedAt = lastTouch = Date.now(); toast('🔒 PIN set'); render();
  });
}

// ---------------- view ----------------
let root = null, tab = 'today', search = '', stageFilter = '', toast = t => console.log(t), propFilter = '';
const DASH = () => document.documentElement.classList.contains('biz-dash');
// The computer dashboard (Windows) has the same sections as the Mac one.
const SVG = {
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  inbox: '<path d="M22 12h-6l-2 3h-4l-2-3H2"/><path d="M5.5 5h13L22 12v6a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2v-6z"/>',
  cols: '<rect x="3" y="4" width="5" height="16" rx="1.5"/><rect x="10" y="4" width="5" height="11" rx="1.5"/><rect x="17" y="4" width="4" height="7" rx="1.5"/>',
  house: '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2 21c0-3.9 3.1-7 7-7s7 3.1 7 7M16 4.5a3.5 3.5 0 0 1 0 7M22 21c0-3.2-2-5.9-5-6.7"/>',
  table: '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 10h18M3 15h18M9 4v16"/>',
  cash: '<rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 9v.01M18 15v.01"/>',
  team: '<circle cx="12" cy="7" r="3"/><circle cx="5" cy="10" r="2.2"/><circle cx="19" cy="10" r="2.2"/><path d="M7 20c0-2.8 2.2-5 5-5s5 2.2 5 5M1.5 19c0-2 1.6-3.6 3.5-3.6M22.5 19c0-2-1.6-3.6-3.5-3.6"/>',
  building: '<rect x="4" y="3" width="16" height="18" rx="1.5"/><path d="M9 7h.01M15 7h.01M9 11h.01M15 11h.01M9 15h.01M15 15h.01M10 21v-3h4v3"/>',
  bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
  link: '<path d="M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7"/>',
  learn: '<path d="M22 10 12 5 2 10l10 5z"/><path d="M6 12v5c3 2 9 2 12 0v-5"/>',
};
const icon = (n, sz = 16) => `<svg viewBox="0 0 24 24" width="${sz}" height="${sz}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${SVG[n]}</svg>`;
const SECTIONS = () => [
  ['today', 'Today', 'sun', 'What needs you today', ['The people to call, who is waiting and money owed — all on one page.', 'Click a number to jump to the list behind it.', 'Write today’s offer at the bottom; Zuffi uses it in replies.']],
  ['inbox', 'Inbox', 'inbox', 'WhatsApp messages & replies', ['New WhatsApp messages land here and become clients by themselves.', 'Click Reply — WhatsApp opens with the chat ready.', 'Red means someone has waited more than 5 minutes.']],
  ['pipeline', 'Pipeline', 'cols', 'Where each client is up to', ['Each column is a step: New → Contacted → … → Won.', 'Drag a client to the next column when things move on.', 'Click a client to see everything about them.']],
  estate() ? ['stock', 'Properties', 'house', 'Plots, houses & shops you’re selling', ['Add a property once — Zuffi matches it to buyers.', 'WhatsApp group posts become stock on Android.', 'Mark it Sold / Let when it’s done.']]
    : ['clients', 'Clients', 'users', 'Regulars & who to invite back', ['Everyone who visited, with their usual service.', 'Zuffi shows who is due to come back.', 'One click sends a friendly invite on WhatsApp.']],
  ['records', 'Records', 'table', 'Every client in one table', ['Everyone who ever contacted you, like a spreadsheet.', 'Click a column title to sort; search at the top.', 'Export to Excel (CSV) any time — it’s your data.']],
  ['money', 'Money', 'cash', 'Money in, money out, profit', ['Add money in or out in two clicks — or type “expense 2500 fuel” below.', 'Owed to you: chase late payments with a ready message.', 'Profit is worked out for you.']],
  ...(freelance() ? [] : [['team', 'Team & staff', 'team', 'Staff, salaries & hours', ['Add each person and how they are paid.', 'Pay salary or commission — it goes into Money by itself.', 'See who is slow to follow up their leads.']]]),
  ['business', 'My business', 'building', 'Your details Zuffi uses to reply', ['Write your prices, hours and location — Zuffi uses them when replying.', 'Pick your country and currency here.', 'Choose Zuffi’s look and colour for every device.']],
  ['automations', 'Automations', 'bolt', 'Jobs Zuffi does for you', ['Switch on the jobs you want Zuffi to do.', 'Each switch says exactly what it does.', 'They work on all your linked devices.']],
  ['connect', 'Connect & devices', 'link', 'WhatsApp, your phone & other devices', ['Link your phone or tablet with the QR code.', 'Changes on one device appear on the others by themselves.', 'Lock Business with a PIN and hide amounts here.']],
  ['learn', 'Learn & help', 'learn', 'How Zuffi works, step by step', ['Short guides for every part of Zuffi.', 'Includes setting up a free AI model on this computer.', 'Something not working? Open “Something not working?”.']],
];
const TABS = () => DASH() ? SECTIONS().map(([id, lb]) => [id, lb, GREY]) : [['today', 'Today', VIOLET], ['leads', 'Leads', ROSE], estate() ? ['stock', 'Stock', AMBER] : ['clients', 'Clients', AMBER], ['money', 'Money', AMBER], ...(freelance() ? [] : [['team', 'Team', VIOLET]]), ['more', 'More', GREY]];

export function mount(el, opts = {}) {
  root = el; toast = opts.toast || toast;
  document.addEventListener('zuffi-plan', () => { if (root && isVisible()) render(); });
  bs.onChange(what => { if (what === 'status' || what === 'peers') renderHead(); else if (isVisible()) render(); else renderHead(); });
  render();
  setInterval(watch, 60000); setTimeout(watch, 5000);
}
const isVisible = () => root && root.closest('.view')?.classList.contains('active');
export function show(t) {
  if (t === 'devices' || t === 'biz') { tab = 'more'; moreFocus = t; } else if (t) tab = t;
  importPhoneChats(); importGroupListings(); render();
  if (!bs.cfg('country') && !LS.get('zuffiOnboarded')) setTimeout(onboarding, 250);
}

function render() {
  if (!root) return;
  if (locked()) return renderLock();
  const A = window.zuffiAccount;
  if (A && !A.isBusiness()) {   // Pro or no plan: show what Business adds instead of the dashboard
    const pk = (bs.cfg('country') || '') === 'PK', pr = pk ? 'Rs 2,000' : '£14.99';
    root.innerHTML = `<div class="biz-lock"><div class="gd-ico">🔒</div><h2>Business is part of Zuffi Business</h2><p>You’re on ${A.isPaid() ? 'Pro' : 'no plan'}. Zuffi Business (${pr} a month) adds the WhatsApp inbox, leads and follow-ups, money and late payers, staff and automations, set up for your type of business.</p><button class="btn" id="bizLockUp">See Business</button></div>`;
    root.querySelector('#bizLockUp').onclick = () => { const u = A.upgradeUrl('business', pk ? 'PK' : 'GB'); window.zuffiOpenSite ? window.zuffiOpenSite(u) : u.then(x => window.open(x, '_blank')); };
    return;
  }
  root.classList.toggle('bz-private', LS.get('zuffiPrivate') === '1');
  const tabs = TABS();
  if (DASH() && ({ leads: 1, more: 1 })[tab]) tab = tab === 'leads' ? 'inbox' : 'business';
  if (!tabs.some(t => t[0] === tab)) tab = 'today';
  root.innerHTML = `
    <div class="bz-head" id="bzHead"></div>
    ${DASH() ? sideNav() : `<div class="bz-tabs" role="tablist">${tabs.map(([id, lb, c]) => `<button class="${tab === id ? 'on' : ''}" data-bt="${id}" style="--c:${c}"><i></i>${lb}</button>`).join('')}</div>`}
    <div class="bz-body">${DASH() ? topBar() : ''}${({ today: viewToday, leads: viewLeads, stock: viewStock, clients: viewClients, money: viewMoney, team: viewTeam, more: viewMore,
      inbox: viewInbox, pipeline: viewPipeline, records: viewRecords, business: viewBusiness, automations: viewAutomations, connect: viewConnect, learn: viewLearn }[tab] || viewToday)()}</div>`;
  let fab = document.getElementById('bzFab');
  if (!fab) { fab = document.createElement('button'); fab.id = 'bzFab'; fab.className = 'bz-fab'; document.body.appendChild(fab); }
  const fa = DASH() ? '' : ['today', 'leads'].includes(tab) ? 'addLead' : tab === 'stock' ? 'addProp' : tab === 'clients' ? 'addClient' : '';
  fab.hidden = !fa; fab.textContent = '＋'; fab.setAttribute('aria-label', { addLead: 'Add lead', addProp: 'Add property', addClient: 'Add client' }[fa] || '');
  fab.onclick = () => fa === 'addProp' ? editProp(null) : fa === 'addClient' ? editClient(null) : editLead(null);
  renderHead();
  root.querySelectorAll('[data-bt]').forEach(b => b.onclick = () => { tab = b.dataset.bt; moreFocus = ''; render(); });
  root.onclick = onClick; root.oninput = onInput; root.onchange = onChangeEv;
  root.querySelector('.bz-tabs .on')?.scrollIntoView?.({ inline: 'center', block: 'nearest' });
  if (moreFocus && tab === 'more' && DASH()) { tab = moreFocus === 'devices' ? 'connect' : 'business'; moreFocus = ''; return render(); }
  if (moreFocus && tab === 'more') setTimeout(() => root.querySelector('#more-' + moreFocus)?.scrollIntoView({ block: 'start', behavior: 'smooth' }), 60);
  if (qrShown && (tab === 'more' || tab === 'connect')) drawQr();
  if (tab === 'pipeline') wirePipeline();
}

function renderHead() {
  const h = root && $('#bzHead', root); if (!h) return;
  const p = PACKS[kind()] || PACKS.realEstate;
  const peers = Object.keys(bs.peers()).length;
  const chip = bs.linked()
    ? `<button class="bz-sync ${bs.status.connected ? 'live' : ''}" data-go="devices"><i></i>${bs.status.connected ? 'Live' : 'Linking'}${peers ? ' · ' + (peers + 1) + ' devices' : ''}</button>`
    : `<button class="bz-sync off" data-go="devices"><i></i>Link devices</button>`;
  const blobLook = (bs.cfg('zstyle') || 'blob') === 'blob';
  h.innerHTML = `<button class="bz-logo ${blobLook ? 'blob' : ''}" data-go="biz" title="${blobLook ? 'Zuffi' : 'My business'}">${blobLook ? '' : p.icon}</button>
    <div class="bz-ttl"><b>${esc(bizName() || 'My business')}</b><small>${esc(p.label)} · ${C.flag(country())} ${esc(C.name(country()))}</small></div>${chip}`;
  h.querySelectorAll('[data-go]').forEach(b => b.onclick = () => { tab = 'more'; moreFocus = b.dataset.go; render(); });
  if (blobLook) { const lg = h.querySelector('.bz-logo'); lg.innerHTML = Z.svg(zMood(), zHue()); lg.onclick = e => { e.stopPropagation(); Z.react(lg, 'happy'); }; }
}

const plane = (label, value, c, sub = '', act = '') => `<${act ? 'button' : 'div'} class="bz-tile glass" style="--c:${c}" ${act}><i></i><b>${esc(String(value))}</b><small>${esc(label)}</small>${sub ? `<em>${esc(sub)}</em>` : ''}</${act ? 'button' : 'div'}>`;
const empty = t => `<p class="bz-empty">${t}</p>`;
const pill = (t, c) => `<span class="bz-pill" style="--c:${c}">${esc(t)}</span>`;
// ---------------- plans: Free keeps up to N leads on one device; Business = unlimited, linked devices, automations ----------------
const leadRoom = () => account.isBusiness() || leads().length < account.freeLeads();
const openLink = u => (window.zuffiOpenUrl || (x => window.open(x, '_blank', 'noopener')))(u);
function upgradeSheet(why) {
  const { w } = sheet('Zuffi Business', `<p class="bz-p">${why}</p>
    <ul class="bz-perks"><li>Unlimited leads and clients</li><li>The same business on your phone, tablet and computer</li><li>Morning summary, late-payment and lost-money automations</li><li>Built-in AI — nothing to set up</li></ul>
    <p class="bz-hint">${account.signedIn() ? 'You’ll finish on our website, then come back here — Zuffi switches on by itself.' : 'Sign in first (Settings → Zuffi account), then upgrade on our website.'} Your leads stay safe on this device whatever you choose.</p>`,
    async () => { if (!account.signedIn()) { (window.zuffiOpenSettings || (() => {}))('account'); return; } openLink(await account.upgradeUrl('business')); });
  w.querySelector('[data-save]').textContent = account.signedIn() ? 'Get Business' : 'Sign in';
}
function planCard() {
  const p = account.plan(), n = leads().length, max = account.freeLeads();
  if (p === 'business') return card('Your plan', `<p class="bz-p">Zuffi Business${account.email() ? ' · ' + esc(account.email()) : ''}. Unlimited leads, linked devices and automations.</p>`);
  if (p === 'trial') return card('Your free trial', `<p class="bz-p">Everything in Zuffi Business is switched on during your trial. Choose a plan any time to keep it.</p>
    <button class="bz-btn" data-act="upgrade">Choose Business</button>`);
  return card('Your plan', `<p class="bz-p">Zuffi Pro · ${Math.min(n, max)} of ${max} business leads used.</p>
    <div class="bz-meter"><i style="width:${Math.min(100, n / max * 100)}%"></i></div>
    <button class="bz-btn" data-act="upgrade">Get Business — unlimited leads &amp; linked devices</button>`);
}

const card = (title, body, extra = '', cls = '') => `<section class="bz-card glass ${cls}"><h4>${title}${extra}</h4>${body}</section>`;

function leadRow(l, opts = {}) {
  const sub = [f(l.r, 'Interest'), f(l.r, 'Area'), f(l.r, 'Budget')].filter(Boolean).join(' · ') || l.phone || l.src;
  let tag = '';
  if (opts.wait) tag = pill(l.waitMin >= 60 ? Math.floor(l.waitMin / 60) + ' h waiting' : l.waitMin + ' min', ROSE);
  else if (overdue(l)) tag = pill('overdue', ROSE);
  else if (dueToday(l)) tag = pill('today', AMBER);
  else tag = pill(l.status, stageColor(l.status));
  const c = opts.wait || overdue(l) ? ROSE : dueToday(l) ? AMBER : stageColor(l.status);
  return `<button class="bz-row" data-lead="${esc(l.k)}">
    ${face(l.name, c, (l.name || l.phone || '?').trim().charAt(0).toUpperCase())}
    <span class="bz-rt"><b>${esc(l.name || l.phone || 'No name')}${l.pri.toLowerCase() === 'hot' ? ' <span class="hot">●</span>' : ''}</b><small>${esc(sub)}</small></span>
    <span class="bz-rr">${tag}</span></button>`;
}

function greeting() { const h = new Date().getHours(); return h < 12 ? 'Good morning' : h < 18 ? 'Good afternoon' : 'Good evening'; }

function viewToday() {
  const L = leads(), today = iso(), W = waiting(), lost = forgotten(), wk = weekStats();
  const due = L.filter(dueToday).sort((a, b) => (overdue(b) - overdue(a)) || (a.next || '').localeCompare(b.next || ''));
  const visits = [...bs.rows('Visits'), ...bs.rows('Appointments')].filter(({ r }) => f(r, 'Date') === today && !/cancel/i.test(f(r, 'Status')));
  const owed = bs.rows('Due').filter(({ r }) => !/paid/i.test(f(r, 'Status')));
  const owedSum = owed.reduce((a, { r }) => a + num(f(r, 'Amount')), 0);
  const m = monthMoney(today.slice(0, 7));
  const saved = wk.hours ? ` · saved you ${wk.hours} h (≈ ${money(wk.hours * hourRate())})` : '';
  const hero = wk.earned
    ? `<span class="k">Zuffi helped you earn this week</span><b>${money(wk.earned)}</b><small>${wk.actions} things done for you${esc(saved)}</small>`
    : `<span class="k">Money in this week</span><b>${money(wk.moneyIn)}</b><small>${wk.newLeads} new enquir${wk.newLeads === 1 ? 'y' : 'ies'}${esc(saved)}</small>`;
  const alerts = [];
  if (W.length) alerts.push(card(`<i class="dot" style="--c:${ROSE}"></i>Waiting for a reply`, W.slice(0, 5).map(l => `<div class="bz-wait">${leadRow(l, { wait: true })}<button class="bz-mini" data-reply="${esc(l.k)}">Reply</button></div>`).join(''),
    `<span class="r">${W.length}</span>`, 'bz-alert'));
  if (lost.length >= 2) alerts.push(`<section class="bz-card glass bz-lost"><div><span class="k">Lost money report</span><b>${lost.length} people never got a follow-up</b>
      <small>You could still win about ${money(lost.length * avgDeal() * 0.25)} — one tap writes to them all.</small></div><button class="bz-btn" data-act="followAll">Follow them up</button></section>`);
  const extras = [ukDueCard(), rebookCard(true), groupMatchesCard()].filter(Boolean).join('');
  const dash = document.documentElement.classList.contains('biz-dash');
  return `<div class="bz-hello"><b>${dash ? greeting() + (bs.cfg('owner') ? ', ' + esc(first(bs.cfg('owner'))) : '') : 'Today'}</b><small>${due.length ? `${due.length} ${due.length === 1 ? 'person' : 'people'} to call today` : 'Nobody to chase today'}${W.length ? ` · ${W.length} waiting` : ''}</small></div>
    <section class="bz-hero glass">${hero}</section>
    <div class="bz-tiles">
      ${plane('People waiting', W.length, ROSE, '', 'data-bt="leads"')}
      ${plane('Call today', due.length, ROSE)}
      ${plane(estate() ? 'Viewings today' : 'Bookings today', visits.length, VIOLET)}
      ${plane('Owed to you', owedSum ? money(owedSum) : '—', AMBER, owed.length ? owed.length + ' unpaid' : '', 'data-bt="money"')}
    </div>
    ${alerts.join('')}
    ${dayCard()}
    ${card('Who to call', due.length ? due.slice(0, 12).map(l => leadRow(l)).join('') : empty('Nobody to chase today 🎉 New enquiries appear here automatically.'), `<span class="r">${due.length}</span>`)}
    ${card('This month', `<b class="bz-big" style="color:${m.inc - m.exp >= 0 ? AMBER : ROSE}">${money(m.inc - m.exp)}</b><small class="bz-sub">profit · in ${money(m.inc)} · out ${money(m.exp)}</small>${bars()}`)}
    ${estate() ? stockMini() : ''}
    ${extras}
    ${card('Today’s update for clients', `<textarea class="bz-in" data-cfg="today" rows="2" placeholder="Today’s offer, news or changed hours">${esc(bs.cfg('today'))}</textarea><small class="bz-hint">Zuffi’s replies use this today, on every linked device.</small>`)}`;
}

/** Your day as a timeline: viewings, bookings, follow-ups and reminders, in time order. */
function dayCard() {
  const today = iso(), items = [];
  for (const { r } of [...bs.rows('Visits'), ...bs.rows('Appointments')]) if (f(r, 'Date') === today) items.push({ t: f(r, 'Time') || '—', what: (estate() ? 'Viewing · ' : 'Booking · ') + (f(r, 'Client') || ''), sub: f(r, 'Property ID') || f(r, 'Service') || f(r, 'Staff'), c: VIOLET });
  for (const { r } of bs.rows('Due')) if (!/paid/i.test(f(r, 'Status')) && f(r, 'Due date') === today) items.push({ t: 'today', what: 'Payment due · ' + f(r, 'Client'), sub: money(num(f(r, 'Amount'))), c: AMBER });
  if (!items.length) return '';
  items.sort((a, b) => (/^\d/.test(a.t) ? a.t : 'zz' + a.t).localeCompare(/^\d/.test(b.t) ? b.t : 'zz' + b.t));
  return card('Your day', `<ol class="bz-timeline">${items.slice(0, 10).map(x => `<li style="--c:${x.c}"><time>${esc(x.t)}</time><span class="bz-rt"><b>${esc(x.what)}</b>${x.sub ? `<small>${esc(x.sub)}</small>` : ''}</span></li>`).join('')}</ol>`, `<span class="r">${items.length}</span>`);
}

function bars() {
  const days = [...Array(30)].map((_, i) => iso(addDays(new Date(), i - 29)));
  const inc = Object.fromEntries(days.map(d => [d, 0]));
  for (const { r } of bs.rows('Money')) { const d = f(r, 'Date'); if (d in inc && f(r, 'Type').toLowerCase().startsWith('inc')) inc[d] += num(f(r, 'Amount')); }
  const max = Math.max(1, ...Object.values(inc));
  return `<div class="bz-bars" aria-label="Money in, last 30 days">${days.map(d => `<i style="height:${Math.max(4, inc[d] / max * 100)}%" class="${d === iso() ? 'now' : ''}" title="${d}: ${money(inc[d])}"></i>`).join('')}</div>`;
}

function stockMini() {
  const P = bs.rows('Listings');
  if (!P.length) return '';
  const st = r => /sold|rented|let\b/i.test(f(r, 'Status')) ? 'sold' : /token|hold|offer/i.test(f(r, 'Status')) ? 'hold' : 'av';
  const av = P.filter(({ r }) => st(r) === 'av').length;
  return card('Stock', `<div class="bz-stockgrid">${P.slice(0, 24).map(({ k, r }) => `<button class="sq ${st(r)}" data-prop="${esc(k)}" title="${esc(f(r, 'Title') || f(r, 'Property ID'))}"><i></i></button>`).join('')}</div>
    <div class="bz-legend"><span><i class="av"></i>available</span><span><i class="hold"></i>token / on hold</span><span><i class="sold"></i>sold / let</span></div>`, `<span class="r">${av} available</span>`);
}

function viewLeads() {
  const q = search.toLowerCase();
  const W = new Set(waiting().map(l => l.k));
  const L = leads().filter(l => (!stageFilter || l.status === stageFilter || (stageFilter === '_wait' && W.has(l.k))) && (!q || JSON.stringify(l.r).toLowerCase().includes(q)))
    .sort((a, b) => (W.has(b.k) - W.has(a.k)) || (dueToday(b) - dueToday(a)) || (b.added || '').localeCompare(a.added || ''));
  const counts = Object.fromEntries(stages().map(s => [s, leads().filter(l => l.status === s).length]));
  const wl = waiting();
  return `<div class="bz-search glass"><span>⌕</span><input class="bz-q" placeholder="Search name, number, area…" value="${esc(search)}"></div>
    <div class="bz-chips"><button class="${!stageFilter ? 'on' : ''}" data-stage="">All ${leads().length}</button>${W.size ? `<button class="${stageFilter === '_wait' ? 'on' : ''}" data-stage="_wait" style="--c:${ROSE}">Waiting ${W.size}</button>` : ''}${stages().map(s => `<button class="${stageFilter === s ? 'on' : ''}" data-stage="${esc(s)}" style="--c:${stageColor(s)}">${esc(s)} ${counts[s] || 0}</button>`).join('')}</div>
    ${card('', L.length ? L.map(l => leadRow(W.has(l.k) ? wl.find(x => x.k === l.k) : l, { wait: W.has(l.k) })).join('') : empty(search || stageFilter ? 'No leads match.' : 'No leads yet. Tap ＋ to add one — or link WhatsApp in More.'), '', 'flush')}`;
}

// ---------------- stock (estate) ----------------
function viewStock() {
  const all = bs.rows('Listings');
  const P = all.filter(({ r }) => !propFilter || (propFilter === 'available' && !/sold|rented|let\b/i.test(f(r, 'Status'))) || (propFilter === 'groups' && f(r, 'Source') === 'WhatsApp group') || f(r, 'Purpose').toLowerCase().includes(propFilter));
  const groups = all.filter(({ r }) => f(r, 'Source') === 'WhatsApp group').length;
  return `<div class="bz-chips">${[['', 'All ' + all.length], ['available', 'Available'], ['sale', 'For sale'], ['rent', 'To rent']].concat(groups ? [['groups', 'From groups ' + groups]] : []).map(([v, t]) => `<button class="${propFilter === v ? 'on' : ''}" data-pf="${v}">${t}</button>`).join('')}</div>
    ${groupMatchesCard() || ''}
    <div class="bz-props">${P.length ? P.map(({ k, r }) => {
      const sold = /sold|rented|let\b/i.test(f(r, 'Status')), mt = matchesFor(r).length;
      return `<button class="bz-prop glass" data-prop="${esc(k)}">
        <span class="bz-ptop">${pill(f(r, 'Status') || 'Available', sold ? GREY : /token|hold/i.test(f(r, 'Status')) ? VIOLET : AMBER)}<small>${esc(f(r, 'Property ID'))}</small></span>
        <b>${esc(f(r, 'Title') || [f(r, 'Size'), f(r, 'Type')].filter(Boolean).join(' ') || 'Property')}</b>
        <small>${esc([f(r, 'Area'), f(r, 'Block / Phase')].filter(Boolean).join(', '))}</small>
        <span class="bz-pbot"><b>${esc(f(r, 'Price') ? cur() + ' ' + f(r, 'Price') : '')}</b><small>${esc([f(r, 'Purpose'), f(r, 'Size'), f(r, 'Agent')].filter(Boolean).join(' · '))}</small>
        ${mt && !sold ? `<em style="--c:${ROSE}">${mt} buyer${mt > 1 ? 's' : ''} match</em>` : ''}</span></button>`;
    }).join('') : empty('No properties yet. Tap ＋ to add your first plot, house, flat or shop' + (feats().groupListings ? ' — or turn on “WhatsApp group posts → stock” in More.' : '.'))}</div>`;
}

// buyer ↔ property matching
const words = s => String(s || '').toLowerCase().split(/[^a-z0-9]+/).filter(w => w.length > 1 && !['the', 'and', 'in', 'for', 'near', 'block', 'phase', 'sector', 'town', 'road'].includes(w));
function matchesFor(r) {
  const aw = new Set(words(f(r, 'Area') + ' ' + f(r, 'Block / Phase') + ' ' + f(r, 'Title')));
  const price = num(f(r, 'Price')), size = (String(f(r, 'Size') + ' ' + f(r, 'Title')).match(/(\d+(?:\.\d+)?)\s*(marla|kanal|sq|bed)/i) || []);
  return leads().filter(l => {
    if (!isOpen(l)) return false;
    const want = (f(l.r, 'Interest') + ' ' + f(l.r, 'Area')).toLowerCase();
    const areaHit = words(f(l.r, 'Area')).some(w => aw.has(w));
    if (!areaHit) return false;
    const b = num(f(l.r, 'Budget'));
    const priceOk = !price || !b || price <= b * 1.15;
    const sizeOk = !size[1] || !/\d/.test(want) || want.includes(size[1] + ' ' + size[2].toLowerCase()) || want.includes(size[1] + size[2].toLowerCase());
    return priceOk && sizeOk;
  });
}
function groupMatchesCard() {
  if (!estate()) return '';
  const fresh = bs.rows('Listings').filter(({ r }) => f(r, 'Source') === 'WhatsApp group' && (f(r, 'Added') || '') >= iso(addDays(new Date(), -2)) && !/sold/i.test(f(r, 'Status')));
  const hits = fresh.map(x => ({ ...x, m: matchesFor(x.r) })).filter(x => x.m.length);
  if (!hits.length) return '';
  return card(`<i class="dot" style="--c:${AMBER}"></i>New from WhatsApp groups`, hits.slice(0, 5).map(({ k, r, m }) => `<button class="bz-row" data-prop="${esc(k)}"><span class="bz-av" style="--c:${AMBER}">▦</span>
      <span class="bz-rt"><b>${esc(f(r, 'Title') || f(r, 'Size'))}</b><small>${esc([f(r, 'Area'), f(r, 'Price') && cur() + ' ' + f(r, 'Price'), f(r, 'Posted by')].filter(Boolean).join(' · '))}</small></span>
      <span class="bz-rr">${pill(m.slice(0, 2).map(l => first(l.name)).join(', ') + (m.length > 2 ? ' +' + (m.length - 2) : ''), ROSE)}</span></button>`).join(''), `<span class="r">${hits.length} match buyers</span>`);
}

// ---------------- clients + rebooking (salons, garages, trades…) ----------------
const rebookDays = () => num(bs.cfg('rebookDays')) || ({ salon: 35, clinic: 180, restaurant: 30, shop: 60, services: 365, realEstate: 365 })[kind()];
function rebookDue() {
  const today = iso();
  return bs.rows('Clients').map(({ k, r }) => {
    const lv = f(r, 'Last visit'); if (!lv) return null;
    const dueOn = iso(addDays(new Date(lv), num(f(r, 'Every (days)')) || rebookDays()));
    const invited = (f(r, 'Notes').match(/Invited (\d{4}-\d{2}-\d{2})/) || [])[1] || '';
    if (dueOn > iso(addDays(new Date(), 3)) || (invited && invited >= lv)) return null;
    return { k, r, dueOn, late: dueOn < today };
  }).filter(Boolean).sort((a, b) => a.dueOn.localeCompare(b.dueOn));
}
function rebookCard(compact) {
  if (estate()) return '';
  const D = rebookDue(); if (!D.length) return '';
  return card(`<i class="dot" style="--c:${VIOLET}"></i>Due to come back`, D.slice(0, compact ? 4 : 30).map(({ k, r, dueOn }) => `<div class="bz-line">${face(f(r, 'Name'), VIOLET)}
      <span class="bz-rt"><b>${esc(f(r, 'Name'))}</b><small>${esc([f(r, 'Usual service'), 'last ' + f(r, 'Last visit'), 'due ' + dueOn].filter(Boolean).join(' · '))}</small></span>
      <button class="bz-mini" data-rebook="${esc(k)}">Invite back</button></div>`).join(''), `<span class="r">${D.length}</span>`);
}
function viewClients() {
  const C2 = bs.rows('Clients').sort((a, b) => f(b.r, 'Last visit').localeCompare(f(a.r, 'Last visit')));
  return `${rebookCard(false)}
    ${card('Clients', C2.length ? C2.map(({ k, r }) => `<button class="bz-row" data-client="${esc(k)}">${face(f(r, 'Name'), AMBER)}
      <span class="bz-rt"><b>${esc(f(r, 'Name'))}</b><small>${esc([f(r, 'Usual service'), f(r, 'Last visit') && 'last visit ' + f(r, 'Last visit'), f(r, 'Phone')].filter(Boolean).join(' · '))}</small></span></button>`).join('')
      : empty('Your regulars live here. Clients are added when a lead becomes “Visited / Regular”, or tap ＋.'), `<span class="r">every ${rebookDays()} days</span>`, 'flush')}`;
}

// ---------------- UK: Renters' Rights + safety certificates ----------------
function ukItems() {
  if (!feats().compliance) return [];
  const today = new Date(), out = [];
  const soon = (d, days) => d && (new Date(d) - today) / 864e5 <= days;
  for (const { k, r } of bs.rows('Listings')) {
    if (!/rent|let/i.test(f(r, 'Purpose') + f(r, 'Status'))) continue;
    const name = f(r, 'Title') || f(r, 'Property ID') || 'Rental';
    const g = f(r, 'Gas safety'), e = f(r, 'EICR'), start = f(r, 'Tenancy start'), dep = f(r, 'Deposit protected'), rise = f(r, 'Last rent rise'), pet = f(r, 'Pet request'), petA = f(r, 'Pet answered');
    if (g) { const due = iso(addDays(new Date(g), 365)); if (soon(due, 30)) out.push({ k, name, what: 'Gas safety check', due }); }
    else if (/let|rented/i.test(f(r, 'Status'))) out.push({ k, name, what: 'Gas safety date missing', due: '' });
    if (e) { const due = iso(addDays(new Date(e), 5 * 365)); if (soon(due, 60)) out.push({ k, name, what: 'Electrical check (EICR)', due }); }
    if (start && !dep) out.push({ k, name, what: 'Protect the deposit (30 days)', due: iso(addDays(new Date(start), 30)) });
    if (pet && !petA) out.push({ k, name, what: 'Answer pet request in writing', due: iso(addDays(new Date(pet), 28)) });
    const base = [start && iso(addDays(new Date(start), 365)), rise && iso(addDays(new Date(rise), 365))].filter(Boolean).sort().pop();
    if (base && soon(base, 75)) out.push({ k, name, what: 'Rent rise allowed from (2 months’ notice, Form 4A)', due: base, info: true });
  }
  return out.sort((a, b) => (a.due || '0').localeCompare(b.due || '0'));
}
function ukDueCard() {
  const I = ukItems(); if (!I.length) return '';
  return card(`<i class="dot" style="--c:${VIOLET}"></i>Rentals: due soon`, I.slice(0, 6).map(x => `<button class="bz-row" data-prop="${esc(x.k)}"><span class="bz-av" style="--c:${x.info ? VIOLET : x.due && x.due < iso() ? ROSE : AMBER}">!</span>
      <span class="bz-rt"><b>${esc(x.what)}</b><small>${esc(x.name)}</small></span><span class="bz-rr">${x.due ? pill(x.due, x.due < iso() ? ROSE : AMBER) : pill('add date', ROSE)}</span></button>`).join('')
    + '<small class="bz-hint">England rules (Renters’ Rights Act 2025, gas & electrical safety). Check GOV.UK — this is a reminder, not legal advice.</small>', `<span class="r">${I.length}</span>`);
}

// ---------------- money ----------------
function monthMoney(ym) {
  let inc = 0, exp = 0; const list = [];
  for (const { k, r } of bs.rows('Money')) {
    if (!(f(r, 'Date') || '').startsWith(ym)) continue;
    const a = num(f(r, 'Amount')), t = f(r, 'Type').toLowerCase();
    if (t.startsWith('inc')) inc += a; else exp += a;
    list.push({ k, r, a, t });
  }
  return { inc, exp, list: list.sort((a, b) => (f(b.r, 'Date')).localeCompare(f(a.r, 'Date'))) };
}
// UK Making Tax Digital quarters (6 Apr – 5 Jul → due 7 Aug, …)
function mtdQuarter(d = new Date()) {
  const y = d.getMonth() < 3 || (d.getMonth() === 3 && d.getDate() < 6) ? d.getFullYear() - 1 : d.getFullYear();
  const Q = [[`${y}-04-06`, `${y}-07-05`, `${y}-08-07`], [`${y}-07-06`, `${y}-10-05`, `${y}-11-07`], [`${y}-10-06`, `${y + 1}-01-05`, `${y + 1}-02-07`], [`${y + 1}-01-06`, `${y + 1}-04-05`, `${y + 1}-05-07`]];
  const t = iso(d);
  const cur = Q.find(q => t >= q[0] && t <= q[1]) || Q[0];
  const prev = Q[Q.indexOf(cur) - 1];
  return { cur, next: prev && t <= prev[2] ? prev : cur };
}
let moneyType = 'Expense';
function viewMoney() {
  const ym = iso().slice(0, 7), m = monthMoney(ym);
  const due = bs.rows('Due').filter(({ r }) => !/paid/i.test(f(r, 'Status'))).sort((a, b) => f(a.r, 'Due date').localeCompare(f(b.r, 'Due date')));
  const cats = moneyType === 'Income' ? incomeCats() : expenseCats();
  const today = iso();
  const mtd = feats().mtd ? (() => { const q = mtdQuarter().next; return card(`<i class="dot" style="--c:${VIOLET}"></i>Making Tax Digital`, `<p class="bz-p">Next quarterly update due <b>${new Date(q[2]).toLocaleDateString([], { day: 'numeric', month: 'long' })}</b> for ${new Date(q[0]).toLocaleDateString([], { day: 'numeric', month: 'short' })} – ${new Date(q[1]).toLocaleDateString([], { day: 'numeric', month: 'short' })}.</p>
      <button class="bz-btn ghost" data-act="mtdExport" data-from="${q[0]}" data-to="${q[1]}">Export this quarter for your accountant (CSV)</button>
      <small class="bz-hint">For sole traders & landlords over the threshold. Your accountant’s HMRC-recognised software does the filing.</small>`); })() : '';
  return `<div class="bz-tiles three">
      ${plane('Money in', money(m.inc), AMBER)}${plane('Money out', money(m.exp), GREY)}${plane('Profit', money(m.inc - m.exp), m.inc - m.exp >= 0 ? GREEN : ROSE)}
    </div>
    ${card('Owed to you', due.length ? due.map(({ k, r }) => {
      const late = f(r, 'Due date') && f(r, 'Due date') < today, days = late ? Math.round((new Date(today) - new Date(f(r, 'Due date'))) / 864e5) : 0;
      const chased = (f(r, 'Notes').match(/Chased (\d{4}-\d{2}-\d{2})/g) || []).length;
      return `<div class="bz-line">${face(f(r, 'Client'), late ? ROSE : AMBER)}
        <span class="bz-rt"><b>${esc(f(r, 'Client'))}</b><small>${esc([money(num(f(r, 'Amount'))), f(r, 'For'), late ? days + ' days late' : 'due ' + f(r, 'Due date'), chased ? 'chased ×' + chased : ''].filter(Boolean).join(' · '))}</small></span>
        ${late ? `<button class="bz-mini ghost" data-chase="${esc(k)}">Chase</button>` : ''}<button class="bz-mini" data-paid="${esc(k)}">Paid ✓</button></div>`;
    }).join('') : empty('No one owes you money 👍'), `<span class="r">${due.length}</span>`)
      .replace('</section>', `<details class="bz-more"><summary>＋ Add money owed</summary>
        <div class="bz-grid2"><input class="bz-in" id="dClient" placeholder="Client"><input class="bz-in" id="dPhone" inputmode="tel" placeholder="Phone (for chasers)">
        <input class="bz-in" id="dAmt" inputmode="decimal" placeholder="Amount"><input class="bz-in" id="dDate" type="date" value="${iso()}"></div>
        <input class="bz-in" id="dFor" placeholder="For (installment, invoice #, deposit…)">
        <button class="bz-btn ghost" data-act="addDue">Add</button></details></section>`)}
    ${card('Add money', `<div class="bz-seg"><button class="${moneyType === 'Expense' ? 'on' : ''}" data-mt="Expense">Money out</button><button class="${moneyType === 'Income' ? 'on' : ''}" data-mt="Income">Money in</button></div>
      <div class="bz-grid2">
        <input class="bz-in" id="mAmt" inputmode="decimal" placeholder="Amount (${esc(cur())})">
        <select class="bz-in" id="mCat">${cats.map(c => `<option>${esc(c)}</option>`).join('')}</select>
        <input class="bz-in" id="mParty" placeholder="${moneyType === 'Income' ? 'From (client)' : 'Paid to'}">
        <select class="bz-in" id="mMethod">${methods().map(c => `<option>${esc(c)}</option>`).join('')}</select>
      </div>
      <input class="bz-in" id="mNote" placeholder="Note (optional) — or just say “expense 2500 fuel”">
      <button class="bz-btn" data-act="addMoney">Save</button>`)}
    ${mtd}
    ${card(new Date().toLocaleDateString([], { month: 'long' }), m.list.length ? m.list.slice(0, 80).map(x => `<div class="bz-line"><span class="bz-rt"><b>${esc(f(x.r, 'Category') || f(x.r, 'Type'))}</b><small>${esc([f(x.r, 'Date'), f(x.r, 'Party'), f(x.r, 'Method'), f(x.r, 'Note')].filter(Boolean).join(' · '))}</small></span>
        <b class="${x.t.startsWith('inc') ? 'good' : 'out'}">${x.t.startsWith('inc') ? '+' : '−'}${esc(money(x.a))}</b><button class="bz-x" data-delmoney="${esc(x.k)}" aria-label="Delete">✕</button></div>`).join('') : empty('Nothing this month yet.'), '', 'flush')}`;
}
function chaseText(r, days) {
  const who = first(f(r, 'Client')), amt = money(num(f(r, 'Amount'))), what = f(r, 'For') ? ` for ${f(r, 'For')}` : '', by = bizName() ? `\n– ${bizName()}` : '';
  const interest = feats().lateInterest && bs.cfg('lateInterest') === '1' ? '\nPlease note: for business invoices, statutory late-payment interest may be added.' : '';
  if (days < 7) return `Hi ${who}, hope you’re well! Just a friendly reminder that ${amt}${what} was due on ${f(r, 'Due date')}. Could you let me know when you can pay? Thank you 🙏${by}`;
  if (days < 21) return `Hi ${who}, ${amt}${what} is now ${days} days overdue. Please arrange payment this week, or let me know if there’s a problem.${interest}${by}`;
  return `Hi ${who}, ${amt}${what} is ${days} days overdue and still unpaid. Please pay within 7 days. If you can’t, reply and we’ll agree a plan.${interest}${by}`;
}

// ---------------- team / office ----------------
function viewTeam() {
  const team = bs.rows('Team'), ym = iso().slice(0, 7), L = leads(), W = waiting();
  const hours = {}; bs.rows('Hours').forEach(({ r }) => { if ((f(r, 'Date') || '').startsWith(ym)) hours[f(r, 'Name')] = (hours[f(r, 'Name')] || 0) + num(f(r, 'Hours')); });
  const paid = new Set(bs.rows('Payroll').filter(({ r }) => f(r, 'Month') === ym && f(r, 'Paid on')).map(({ r }) => f(r, 'Name').toLowerCase()));
  const me = LS.get('zuffiAgent');
  return `${card('Team & staff', team.length ? team.map(({ k, r }) => {
      const nm = f(r, 'Name'), pay = f(r, 'Pay type') || 'Monthly', rate = f(r, 'Rate');
      const mine = L.filter(l => l.agent === nm), won = mine.filter(l => SALE.includes(l.status) && (l.last || '').startsWith(ym));
      const late = W.filter(l => l.agent === nm).length;
      const comm = pay.toLowerCase().startsWith('comm') ? won.reduce((a, l) => a + num(l.value) * num(rate) / 100, 0) : 0;
      const owed = pay.toLowerCase().startsWith('hour') ? num(rate) * (hours[nm] || 0) : pay.toLowerCase().startsWith('month') ? num(rate) : comm;
      return `<div class="bz-line"><button class="bz-rowbtn" data-staff="${esc(k)}">${face(nm, VIOLET)}
        <span class="bz-rt"><b>${esc(nm)}${me === nm ? ' · this device' : ''}</b><small>${esc([f(r, 'Role'), mine.length + ' leads', won.length ? won.length + ' won' : '', late ? late + ' waiting!' : '', pay + (rate ? ' ' + (pay.startsWith('Comm') ? rate + '%' : cur() + ' ' + rate) : '')].filter(Boolean).join(' · '))}</small></span></button>
        ${owed ? (paid.has(nm.toLowerCase()) ? pill('Paid', GREEN) : `<button class="bz-mini" data-pay="${esc(k)}">Pay ${esc(money(owed))}</button>`) : ''}</div>`;
    }).join('') : empty('Add your staff or agents to track who follows up, salaries, hours and commission.'), '<button class="bz-mini r" data-act="addStaff">＋ Add</button>')}
    ${team.length ? card('This device belongs to', `<select class="bz-in" data-agent="1"><option value="">Owner / office</option>${team.map(({ r }) => `<option ${me === f(r, 'Name') ? 'selected' : ''}>${esc(f(r, 'Name'))}</option>`).join('')}</select>
      <small class="bz-hint">Leads added on this phone are given to this person. The owner sees everyone’s leads — and they stay with the office if someone leaves.</small>`) : ''}
    ${team.length ? card('Log hours', `<div class="bz-grid2">
        <select class="bz-in" id="hName">${team.map(({ r }) => `<option>${esc(f(r, 'Name'))}</option>`).join('')}</select>
        <input class="bz-in" id="hHours" inputmode="decimal" placeholder="Hours"><input class="bz-in" id="hDate" type="date" value="${iso()}"><input class="bz-in" id="hNote" placeholder="Note"></div>
        <button class="bz-btn ghost" data-act="addHours">Save hours</button>`) : ''}`;
}

// ---------------- more: business, country, colour, phone, devices ----------------
let moreFocus = '';
// App colour (Settings → You → Colour, or Business → My business): changes the accent everywhere
export const THEMES = [['blue', '#4F6BFF', 0, 'Blue'], ['indigo', '#6366F1', 30, 'Indigo'], ['purple', '#8B5CF6', 55, 'Purple'], ['teal', '#0E9F9A', 115, 'Teal'], ['green', '#16A34A', 170, 'Green'], ['orange', '#EA7A2A', 230, 'Orange'], ['rose', '#E5487A', 330, 'Rose'], ['slate', '#475569', 200, 'Slate']];
export function applyAccent() {
  const t = THEMES.find(x => x[0] === (bs.cfg('accent') || LS.get('zuffiAccent'))) || null;
  const de = document.documentElement;
  window.zuffiUserAccent = t ? t[1] : '';
  const ev = window.zuffiEventAccent;                       // a season's colour wins while the season lasts (seasons.js)
  if (!t) { de.style.removeProperty('--zfur'); if (ev) de.style.setProperty('--accent', ev); else de.style.removeProperty('--accent'); return; }
  de.style.setProperty('--accent', ev || t[1]); de.style.setProperty('--zfur', t[2] + 'deg');
  try { window.SparrowNative?.setAccent?.(t[0]); window.SparrowDesktop?.setSetting?.('accent', t[0]); } catch {}
}
// ---------------- computer dashboard: sidebar, top bar and the extra Mac sections ----------------
function sideNav() {
  const W = waiting().length, due = leads().filter(dueToday).length;
  const badge = { today: due ? pill(String(due), AMBER) : '', inbox: W ? `<span class="bz-cnt">${W}</span>` : '' };
  return `<nav class="bz-side" role="tablist">${SECTIONS().map(([id, lb, ic, sub]) => `<button class="${tab === id ? 'on' : ''}" data-bt="${id}" title="${esc(sub)}">
    <span class="si">${icon(ic)}</span><span class="st"><b>${esc(lb)}</b>${tab === id ? `<small>${esc(sub)}</small>` : ''}</span>${badge[id] || ''}</button>`).join('')}</nav>`;
}
let tipsOpen = false;
function topBar() {
  const sec = SECTIONS().find(x => x[0] === tab) || SECTIONS()[0];
  let title = sec[1], sub = sec[3];
  if (tab === 'today') { const due = leads().filter(dueToday).length, W = waiting().length; title = greeting() + (bs.cfg('owner') ? ', ' + first(bs.cfg('owner')) : ''); sub = (due ? `${due} ${due === 1 ? 'person' : 'people'} to call today` : 'Nobody to chase today') + (W ? ` · ${W} waiting` : ''); }
  const main = ['today', 'inbox', 'pipeline', 'records'].includes(tab) ? ['addLead', '＋ New lead'] : tab === 'stock' ? ['addProp', '＋ Property'] : tab === 'clients' ? ['addClient', '＋ Client'] : tab === 'team' ? ['addStaff', '＋ Staff'] : tab === 'records' ? ['csv', 'Export'] : null;
  return `<div class="bz-top"><div class="bz-tt"><b>${esc(title)}</b><small>${esc(sub)}</small></div>
    <button class="bz-btn ghost sm" data-act="tips">${tipsOpen ? 'Hide tips' : 'What is this page?'}</button>
    ${tab === 'records' ? '<button class="bz-btn ghost sm" data-act="csv">Export (CSV)</button>' : ''}
    ${main ? `<button class="bz-btn sm" data-act="${main[0]}">${main[1]}</button>` : ''}</div>
    ${tipsOpen ? `<div class="bz-tips">${sec[4].map((t, i) => `<div><i>${i + 1}</i><span>${esc(t)}</span></div>`).join('')}</div>` : ''}`;
}
const agoMin = t => { const m = mins(t); return m < 1 ? 'now' : m < 60 ? m + ' min' : m < 1440 ? Math.round(m / 60) + ' h' : Math.round(m / 1440) + ' d'; };
function viewInbox() {
  const W = new Set(waiting().map(l => l.k));
  const L = leads().filter(l => f(l.r, 'Last message') || l.msgAt).sort((a, b) => when(b.msgAt) - when(a.msgAt));
  if (!L.length) return card('No WhatsApp messages yet', `<p class="bz-p">When a client writes on WhatsApp, the message appears here and the client is saved by themselves.</p>
    <p class="bz-hint">On Windows, messages come from your Android phone or office Mac (linked under Connect & devices). Leads you add by hand are in Pipeline and Records.</p>
    <button class="bz-btn ghost" data-bt="connect">Connect WhatsApp</button>`);
  return card('', L.map(l => `<div class="bz-msg ${W.has(l.k) ? 'wait' : ''}">${face(l.name, W.has(l.k) ? ROSE : VIOLET, (l.name || '?').charAt(0))}
      <button class="bz-rt" data-lead="${esc(l.k)}"><b>${esc(l.name || l.phone)}</b><small>“${esc(f(l.r, 'Last message') || '…')}”</small></button>
      <span class="bz-when">${l.msgAt ? agoMin(when(l.msgAt)) : ''}</span>
      ${W.has(l.k) ? pill('waiting', ROSE) : pill(l.status, stageColor(l.status))}
      <button class="bz-mini" data-reply="${esc(l.k)}">Reply</button></div>`).join(''), '', 'flush');
}
function viewPipeline() {
  const L = leads();
  return `<div class="bz-pipe">${stages().map(st => { const col = L.filter(l => l.status === st); const sum = col.reduce((a, l) => a + num(l.value || f(l.r, 'Budget')), 0);
    return `<section class="bz-col" data-col="${esc(st)}" style="--c:${stageColor(st)}"><h5><i></i>${esc(st)}<span>${col.length}</span></h5>${sum && SALE.concat(['Negotiating', 'Quoted']).includes(st) ? `<small class="bz-colsum">${money(sum)}</small>` : ''}
      <div class="bz-colb">${col.map(l => `<button class="bz-kcard" draggable="true" data-lead="${esc(l.k)}"><b>${esc(l.name || l.phone)}${l.pri.toLowerCase() === 'hot' ? ' <span class="hot">●</span>' : ''}</b>
        <small>${esc([f(l.r, 'Interest'), f(l.r, 'Area')].filter(Boolean).join(' · ') || l.phone)}</small>${overdue(l) ? pill('overdue', ROSE) : dueToday(l) ? pill('today', AMBER) : ''}</button>`).join('') || '<p class="bz-empty">Drop here</p>'}</div></section>`; }).join('')}</div>`;
}
function wirePipeline() {
  const P = root.querySelector('.bz-pipe'); if (!P) return;
  let dragK = '';
  P.addEventListener('dragstart', e => { const c = e.target.closest('[data-lead]'); if (!c) return; dragK = c.dataset.lead; c.classList.add('drag'); e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', dragK); });
  P.addEventListener('dragend', e => { e.target.closest('[data-lead]')?.classList.remove('drag'); P.querySelectorAll('.over').forEach(x => x.classList.remove('over')); });
  P.addEventListener('dragover', e => { const col = e.target.closest('[data-col]'); if (!col) return; e.preventDefault(); P.querySelectorAll('.over').forEach(x => x !== col && x.classList.remove('over')); col.classList.add('over'); });
  P.addEventListener('drop', e => {
    const col = e.target.closest('[data-col]'); if (!col || !dragK) return; e.preventDefault();
    const x = bs.rows('Leads').find(r => r.k === dragK); if (!x) return;
    const prev = f(x.r, 'Status') || 'New', st = col.dataset.col; if (prev === st) return render();
    const row = { ...x.r, Status: st, 'Last contact': iso() };
    if (prev === 'New') row['Replied at'] = new Date().toISOString().slice(0, 16).replace('T', ' ');
    bs.put('Leads', row, x.k); stageWon(row, prev); toast(`${f(x.r, 'Name') || 'Client'} → ${st}`);
  });
}
let recSort = ['Added', -1];
const REC_COLS = () => [['Name', 'Name'], ['Phone', 'Phone'], ['Status', 'Stage'], ['Interest', labels()[0]], ['Area', labels()[1]], ['Budget', labels()[2]], ['Value', labels()[3]], ['Source', 'Source'], ['Next follow-up', 'Next follow-up'], ['Assigned to', 'Agent'], ['Added', 'Added']];
function recRows() {
  const q = search.toLowerCase(), [col, dir] = recSort;
  return leads().filter(l => !q || JSON.stringify(l.r).toLowerCase().includes(q)).sort((a, b) => {
    const x = f(a.r, col), y = f(b.r, col);
    const nx = num(x), ny = num(y);
    return (['Budget', 'Value'].includes(col) ? nx - ny : String(x).localeCompare(String(y))) * dir;
  });
}
function viewRecords() {
  const R = recRows();
  return `<div class="bz-search glass"><span>⌕</span><input class="bz-q" placeholder="Search name, number, area…" value="${esc(search)}"></div>
    <section class="bz-card glass flush bz-tablewrap"><table class="bz-table"><thead><tr>${REC_COLS().map(([k, lb]) => `<th data-sort="${esc(k)}" class="${recSort[0] === k ? 'on' : ''}">${esc(lb)}${recSort[0] === k ? (recSort[1] > 0 ? ' ▲' : ' ▼') : ''}</th>`).join('')}</tr></thead>
    <tbody>${R.map(l => `<tr data-lead="${esc(l.k)}">${REC_COLS().map(([k]) => k === 'Status' ? `<td>${pill(l.status, stageColor(l.status))}</td>` : `<td>${esc(f(l.r, k))}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="${REC_COLS().length}" class="bz-empty">No clients yet.</td></tr>`}</tbody></table></section>
    <small class="bz-hint">${R.length} of ${leads().length} clients</small>`;
}
function exportRecords() {
  const cols = REC_COLS(), q = v => `"${String(v ?? '').replace(/"/g, '""')}"`;
  const csv = [cols.map(c => q(c[1])).join(','), ...recRows().map(l => cols.map(([k]) => q(k === 'Status' ? l.status : f(l.r, k))).join(','))].join('\r\n');
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv' })); a.download = `zuffi-clients-${iso()}.csv`; document.body.appendChild(a); a.click(); a.remove();
  toast('Saved ' + a.download);
}
function viewBusiness() { return moreBusiness(); }
const AUTOS = [
  ['auto_speed', 'Speed-to-lead alarm', 'If someone waits 5 minutes for a reply, Zuffi buzzes you — and again at 15 minutes.', true],
  ['auto_brief', 'Morning summary', 'Every morning: who to call, who is waiting, viewings and payments due — in one message.', true],
  ['auto_late', 'Late payment nudge', 'When a payment is overdue, Zuffi reminds you each morning with a ready-written chaser.', true],
  ['auto_lost', 'Monday lost-money report', 'Every Monday: people who asked and never got a follow-up, and what they could be worth.', true],
];
const autoOn = k => { if (k !== 'auto_speed' && !account.isBusiness()) return false; const v = bs.cfg(k); const d = AUTOS.find(a => a[0] === k); return v === '' ? !!d?.[3] : v === '1'; };
function viewAutomations() {
  const biz = account.isBusiness();
  return card('Jobs Zuffi does for you', AUTOS.map(([k, t, sub]) => `<label class="bz-auto"><span class="bz-rt"><b>${esc(t)}</b><small>${esc(sub)}${!biz && k !== 'auto_speed' ? ' <em class="bz-tag">Business</em>' : ''}</small></span><input type="checkbox" class="bz-sw" data-auto="${k}" ${autoOn(k) ? 'checked' : ''} ${!biz && k !== 'auto_speed' ? 'disabled' : ''}></label>`).join('')
    + (biz ? '' : '<button class="bz-btn ghost" data-act="upgrade" style="margin-top:10px">Get Business to switch these on</button>')
    + '<small class="bz-hint">Switches are shared with your phone and other linked devices.</small>')
    + card('Automatic WhatsApp replies', `<p class="bz-p">Zuffi can answer new WhatsApp enquiries by itself (with a 10-second Stop button). This runs on the device that has WhatsApp: your <b>Android phone</b> (Business → More → This phone) or your <b>Mac</b>.</p>
      <p class="bz-hint">Windows shows the same leads and replies through sync. Replying from here opens WhatsApp Desktop with the chat ready.</p>`);
}
function viewConnect() {
  const D = window.SparrowDesktop;
  const power = D ? card('Keep Zuffi working', `<label class="bz-auto"><span class="bz-rt"><b>While charging, don’t sleep</b><small>Zuffi keeps alerts and sync going. The screen can still turn off.</small></span><input type="checkbox" class="bz-sw" data-dset="awakeCharging"></label>
      <label class="bz-auto"><span class="bz-rt"><b>Keep working with the lid closed</b><small>Only while plugged in. Don’t leave a closed, running laptop in a bag.</small></span><input type="checkbox" class="bz-sw" data-dset="lidCharging"></label>`) : '';
  if (D) setTimeout(() => D.getSettings?.().then(st => root.querySelectorAll('[data-dset]').forEach(i => { i.checked = !!st[i.dataset.dset]; })), 0);
  return card('WhatsApp', `<div class="bz-sec">
      <div><i class="ok">1</i><span class="bz-rt"><b>Android phone</b><small>Business → More → This phone: allow Notification access. New chats become leads and sync here.</small></span></div>
      <div><i class="ok">2</i><span class="bz-rt"><b>Windows</b><small>Install WhatsApp Desktop. Reply buttons open the chat with the message ready — press Enter to send.</small></span></div>
      <div><i class="ok">3</i><span class="bz-rt"><b>iPhone</b><small>Use an office Mac or a spare Android as the WhatsApp hub, then link it here.</small></span></div></div>
      <button class="bz-btn ghost" data-guide="whatsapp">Step-by-step guide</button>`)
    + `${planCard()}<div id="more-devices"></div>${viewDevices()}<div id="more-security"></div>${securityCard()}${power}`;
}
function viewLearn() { return learnCard(); }

function moreBusiness() {
  const p = feats();
  return `${card('My business', `
      <label class="bz-lbl">Business name<input class="bz-in" data-cfg="name" value="${esc(bs.cfg('name'))}" placeholder="Your business name"></label>
      <label class="bz-lbl">Your name<input class="bz-in" data-cfg="owner" value="${esc(bs.cfg('owner'))}" placeholder="for greetings and messages"></label>
      <button class="bz-pick" data-act="pickCountry"><span>${C.flag(country())}</span><span class="bz-rt"><b>${esc(C.name(country()))}</b><small>Country · features & currency</small></span><span>›</span></button>
      <div class="bz-grid2">
        <label class="bz-lbl">Type of business<select class="bz-in" data-cfg="kind">${Object.entries(PACKS).filter(([id]) => kindsFor(country()).includes(id)).map(([id, x]) => `<option value="${id}" ${kind() === id ? 'selected' : ''}>${x.icon} ${x.label}</option>`).join('')}</select></label>
        <label class="bz-lbl">Currency<input class="bz-in" data-cfg="currency" value="${esc(cur())}" maxlength="4"></label>
        <label class="bz-lbl">Average deal / job value<input class="bz-in" data-cfg="avgDeal" inputmode="decimal" value="${esc(bs.cfg('avgDeal'))}" placeholder="${esc(money(avgDeal()))}"></label>
        <label class="bz-lbl">Your time is worth (per hour)<input class="bz-in" data-cfg="hourRate" inputmode="decimal" value="${esc(bs.cfg('hourRate'))}" placeholder="${esc(money(hourRate()))}"></label>
        ${!estate() ? `<label class="bz-lbl">Invite clients back every (days)<input class="bz-in" data-cfg="rebookDays" inputmode="numeric" value="${esc(bs.cfg('rebookDays'))}" placeholder="${rebookDays()}"></label>` : ''}
      </div>
      ${p.lateInterest ? `<label class="bz-check"><input type="checkbox" data-cfgchk="lateInterest" ${bs.cfg('lateInterest') === '1' ? 'checked' : ''}> Mention statutory late-payment interest in chasers (business clients)</label>` : ''}`)}
    ${card('Zuffi’s look', `<div class="bz-looks">
        <button class="${(bs.cfg('zstyle') || 'blob') === 'blob' ? 'on' : ''}" data-zstyle="blob"><span class="lk">${Z.svg('happy', zHue())}</span><b>Animated blob</b><small>Blinks, looks around, shows moods</small></button>
        <button class="${bs.cfg('zstyle') === 'bunny' ? 'on' : ''}" data-zstyle="bunny"><span class="lk"><img src="mascots/zuffi-body.webp" alt=""></span><b>Classic bunny</b><small>The original Zuffi</small></button></div>`)}
    ${card('App colour', `<div class="bz-themes">${THEMES.map(([id, c, , n]) => `<button class="${(bs.cfg('accent') || 'blue') === id ? 'on' : ''}" data-theme="${id}" style="--c:${c}"><i></i><span>${n}</span></button>`).join('')}</div>
      <small class="bz-hint">Changes the app colour and Zuffi’s fur on all your linked devices.</small>`)}
    ${card('Business info for replies', `<textarea class="bz-in" data-cfg="info" rows="6" placeholder="Opening hours, prices, location, what you sell, how to book…">${esc(bs.cfg('info'))}</textarea>
      <small class="bz-hint">Zuffi only uses these facts when it answers clients. It never invents prices.</small>`)}
    ${card('Messages Zuffi sends', `<label class="bz-lbl">Missed call → WhatsApp<textarea class="bz-in" data-cfg="missedText" rows="2" placeholder="Sorry I missed your call — I’m with a client. How can I help? 🙂">${esc(bs.cfg('missedText'))}</textarea></label>
      <small class="bz-hint">Follow-ups, chasers and invite-backs are written for you each time — you see them before they go.</small>`)}`;
}
function viewMore() {
  const p = feats();
  const phone = N?.setBizPhone ? phoneSettings() : '';
  return `${planCard()}${learnCard()}<div id="more-biz"></div>${moreBusiness()}
    ${phone}
    <div id="more-devices"></div>${viewDevices()}
    <div id="more-security"></div>${securityCard()}
    ${!N && !window.SparrowDesktop ? card('Zuffi on screen', `<label class="bz-check"><input type="checkbox" data-webpet ${LS.get('zuffiWebPet', '1') === '1' ? 'checked' : ''}> Let Zuffi walk along the bottom of the app and show reminders</label>`) : ''}`;
}

// Android: what Zuffi does on this phone
function phoneSettings() {
  let st = {}; try { st = JSON.parse(N.bizPhone?.() || '{}'); } catch {}
  const row = (k, t, sub, on = st[k]) => `<label class="bz-check"><input type="checkbox" data-phone="${k}" ${on ? 'checked' : ''}><span><b>${t}</b><small>${sub}</small></span></label>`;
  return card('This phone', `
    ${row('speedAlarm', 'Speed-to-lead alarm', 'Buzz me if someone waits 5 min; again at 15 min')}
    ${row('missedCall', 'Missed call → WhatsApp', 'Saves the caller as a lead and gets the reply ready')}
    ${feats().groupListings ? row('groupListings', 'WhatsApp group posts → stock', 'Reads dealer groups (never replies there) and matches buyers') : ''}
    ${row('undo', '10-second undo on auto-replies', 'A “Stop” button before every automatic reply', st.undo !== false)}
    ${row('workCharging', 'Keep working while charging', 'Stays awake on the charger, even with the screen off')}
    ${row('hub', 'Office hub mode', 'This phone handles WhatsApp for your iPhone or the office — keep it plugged in')}
    <div class="bz-grid2"><label class="bz-lbl">Zuffi’s size<select class="bz-in" data-phonesel="petSize">${['small', 'medium', 'large'].map(s => `<option ${(st.petSize || 'medium') === s ? 'selected' : ''}>${s}</option>`).join('')}</select></label>
      <label class="bz-lbl">On screen<select class="bz-in" data-phonesel="petMode">${[['walk', 'Walks around'], ['sit', 'Sits in a corner'], ['alerts', 'Only for alerts']].map(([v, t]) => `<option value="${v}" ${(st.petMode || 'walk') === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label></div>
    <button class="bz-btn ghost" data-act="battery">Let Zuffi run in the background (battery settings)</button>
    <small class="bz-hint">Phones like Xiaomi, Oppo, Infinix and Tecno stop apps to save battery — allow Zuffi so alerts arrive on time.</small>`);
}

// ---------------- learn: how it all works, step by step (guides.json is shared with the Mac app) ----------------
let guides = null;
fetch('guides.json').then(r => r.json()).then(j => { guides = j.guides || []; if (root && tab === 'more') render(); }).catch(() => { guides = []; });
function learnCard() {
  if (!guides) return card('Learn Zuffi Business', '<p class="bz-hint">Loading guides…</p>');
  return card('Learn Zuffi Business', `<div class="bz-guides">${guides.map(g => `<button data-guide="${g.id}"><span class="gi">${g.icon}</span><span class="bz-rt"><b>${esc(g.title)}</b><small>${esc(g.summary)}</small></span><span class="chev">›</span></button>`).join('')}</div>`, `<span class="r">${guides.length} guides</span>`);
}
function openGuide(id) {
  const g = (guides || []).find(x => x.id === id); if (!g) return;
  const { w } = sheet(`${g.icon} ${esc(g.title)}`, `<p class="bz-p">${esc(g.summary)}</p><ol class="bz-steps">${g.steps.map(([t, d]) => `<li><b>${esc(t)}</b><span>${esc(d).replace(/\n/g, '<br>').replace(/(ollama (?:pull|run) [\w.:-]+)/g, '<code>$1</code>')}</span></li>`).join('')}</ol>`, () => {});
  w.querySelector('[data-save]').textContent = 'Got it';
}
function securityCard() {
  const lockOn = pinSet();
  return card('Security & privacy', `
    <div class="bz-sec">
      <div><i class="ok">✓</i><span class="bz-rt"><b>Data stays on your devices</b><small>No Zuffi servers. Sync is end-to-end encrypted (AES-256).</small></span></div>
      <div><i class="${lockOn ? 'ok' : 'warn'}">${lockOn ? '✓' : '!'}</i><span class="bz-rt"><b>${lockOn ? 'Business is locked with a PIN' : 'No lock on this device'}</b><small>${lockOn ? `Locks after ${lockMins()} idle minutes.` : 'Anyone holding this phone can see your clients and money.'}</small></span>
        <button class="bz-mini ${lockOn ? 'ghost' : ''}" data-act="pin">${lockOn ? 'Change' : 'Set PIN'}</button></div>
      <div><i class="${bs.linked() ? 'ok' : 'idle'}">${bs.linked() ? '✓' : '–'}</i><span class="bz-rt"><b>${bs.linked() ? (Object.keys(bs.peers()).length + 1) + ' linked devices' : 'Not linked to other devices'}</b><small>Lost a phone or someone left? Make a new link code — old devices are cut off.</small></span>
        ${bs.linked() ? '<button class="bz-mini ghost" data-act="rotate">New code</button>' : ''}</div>
    </div>
    ${lockOn ? `<div class="bz-grid2"><label class="bz-lbl">Lock after<select class="bz-in" data-lockmins="1">${[1, 5, 15, 60].map(m => `<option value="${m}" ${lockMins() === m ? 'selected' : ''}>${m} min idle</option>`).join('')}</select></label>
      <label class="bz-lbl">&nbsp;<button class="bz-btn ghost" data-act="lockNow" style="margin-top:4px">Lock now</button></label></div>` : ''}
    <label class="bz-check"><input type="checkbox" data-private ${LS.get('zuffiPrivate') === '1' ? 'checked' : ''}><span><b>Hide amounts</b><small>Blurs money on screen — tap a number to peek.</small></span></label>
    ${lockOn ? '<button class="bz-link-x" data-act="pinOff">Remove PIN</button>' : ''}
    <button class="bz-link-x" data-act="wipe">Remove all business data from this device</button>`);
}

// ---------------- devices ----------------
let qrShown = false;
function viewDevices() {
  if (!bs.linked()) return card('Same business on every device', `<div class="bz-link">
      <div class="bz-linkart"><span>💻</span><i></i><span>📱</span><i></i><span>📲</span></div>
      <p>Link this ${/Mobi|Android|iPhone/.test(navigator.userAgent) ? 'phone' : 'device'} to your Mac, Windows PC, tablet or other phones. Add a lead or an expense on one — it appears on the others in seconds. End-to-end encrypted.</p>
      <button class="bz-btn" data-act="scan">Scan the code from my Mac or PC</button>
      <button class="bz-btn ghost" data-act="create">Show a code to link another device</button>
      <input class="bz-in" data-act2="paste" placeholder="…or paste a link code">
      <video class="bz-video" id="bzVideo" hidden muted></video></div>`);
  const peers = Object.entries(bs.peers()).sort((a, b) => b[1] - a[1]);
  return card('Linked devices', `<div class="bz-link">
      <div class="bz-status ${bs.status.connected ? 'live' : ''}"><i></i>${bs.status.connected ? 'Live — changes sync instantly' : 'Connecting to your other devices…'}</div>
      ${bs.status.last ? `<small class="bz-hint">Last change ${ago(bs.status.last)}</small>` : ''}
      <div class="bz-dev"><span>${/Mobi|Android|iPhone/.test(navigator.userAgent) ? '📱' : '💻'}</span><b>This ${esc(bs.deviceName())}</b><small>you’re here</small></div>
      ${peers.length ? peers.map(([n, t]) => `<div class="bz-dev"><span>${/mac|pc|windows|computer/i.test(n) ? '💻' : /ipad|tablet/i.test(n) ? '📲' : '📱'}</span><b>${esc(n)}</b><small>${ago(t)}</small></div>`).join('') : '<p class="bz-hint">No other device has said hello yet. Open Zuffi on the other device.</p>'}
      ${qrShown ? `<div class="bz-qr" id="bzQr"></div><small class="bz-hint warn">Keep this code private — whoever scans it sees your business data.</small>` : ''}
      <div class="bz-btns"><button class="bz-btn ghost" data-act="toggleQr">${qrShown ? 'Hide code' : 'Link another device'}</button><button class="bz-btn ghost" data-act="syncNow">Sync now</button></div>
      <button class="bz-link-x" data-act="unlink">Unlink this device</button></div>`);
}
const ago = t => { const s = (Date.now() - t) / 1000; return s < 50 ? 'just now' : s < 3600 ? Math.round(s / 60) + ' min ago' : s < 86400 ? Math.round(s / 3600) + ' h ago' : Math.round(s / 86400) + ' d ago'; };

// ---------------- first run: pick your country ----------------
function onboarding(fromSettings) {
  let sel = country() === 'OTHER' ? '' : country(), q = '';
  const list = C.all();
  const html = () => `<div class="bz-ob">
      <p class="bz-p">Zuffi switches on what matters where you work — currency, payment apps, property portals and local rules.</p>
      <div class="bz-search glass"><span>⌕</span><input class="bz-q2" placeholder="Search country" value="${esc(q)}"></div>
      <div class="bz-countries">${list.filter(c => !q || c.name.toLowerCase().includes(q.toLowerCase()) || c.code.toLowerCase() === q.toLowerCase()).map(c => `<button class="${sel === c.code ? 'on' : ''}" data-cc="${c.code}"><span>${c.flag}</span>${esc(c.name)}</button>`).join('')}</div>
      ${sel ? `<div class="bz-feat"><b>${C.flag(sel)} What you get in ${esc(C.name(sel))}</b>${C.featureList(sel).map(([i, t, s]) => `<div><span>${i}</span><span class="bz-rt"><b>${esc(t)}</b><small>${esc(s)}</small></span></div>`).join('')}</div>` : ''}
      ${!fromSettings ? `<label class="bz-lbl">Type of business<select class="bz-in" id="obKind">${Object.entries(PACKS).filter(([id]) => kindsFor(sel || country()).includes(id)).map(([id, x]) => `<option value="${id}" ${kind() === id ? 'selected' : ''}>${x.icon} ${x.label}</option>`).join('')}</select></label>
      <label class="bz-lbl">Business name<input class="bz-in" id="obName" value="${esc(bs.cfg('name'))}" placeholder="Your business name"></label>` : ''}</div>`;
  const { w } = sheet(fromSettings ? 'Country' : 'Welcome to Zuffi Business', html(), w => {
    if (!sel) { toast('Pick your country'); return false; }
    bs.setCfg('country', sel); bs.setCfg('currency', C.symbol(sel));
    if (!fromSettings) { bs.setCfg('kind', $('#obKind', w).value); if ($('#obName', w).value.trim()) bs.setCfg('name', $('#obName', w).value.trim()); }
    LS.set('zuffiOnboarded', '1'); render(); toast(`${C.flag(sel)} Set up for ${C.name(sel)}`);
  });
  w.querySelector('[data-save]').textContent = fromSettings ? 'Save' : 'Start';
  const body = w.querySelector('.bz-sheet-b');
  const redraw = () => { const k = $('#obKind', w)?.value, n = $('#obName', w)?.value; body.innerHTML = html(); if (k && $('#obKind', w)) $('#obKind', w).value = k; if (n != null && $('#obName', w)) $('#obName', w).value = n; };
  body.addEventListener('click', e => { const b = e.target.closest('[data-cc]'); if (b) { sel = b.dataset.cc; redraw(); body.querySelector('.bz-feat')?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }); } });
  body.addEventListener('input', e => { if (e.target.classList.contains('bz-q2')) { q = e.target.value; const pos = e.target.selectionStart; redraw(); const i = $('.bz-q2', w); i.focus(); try { i.setSelectionRange(pos, pos); } catch {} } });
  w.querySelector('[data-close]').addEventListener('click', () => LS.set('zuffiOnboarded', '1'));
}

// ---------------- follow everyone up (lost money report) ----------------
function followText(l) {
  const it = f(l.r, 'Interest'), ar = f(l.r, 'Area'), by = bizName() ? `\n– ${bizName()}` : '';
  if (estate()) return `Hi ${first(l.name)}, just checking in — are you still looking for ${it || 'a property'}${ar ? ' in ' + ar : ''}? We have some new options that may suit you.${by}`;
  return `Hi ${first(l.name)}, just following up on your enquiry${it ? ' about ' + it : ''}. Can I help with anything, or book you in this week?${by}`;
}
function followAll() {
  const L = forgotten();
  const html = `<p class="bz-p">${L.length} people asked and never heard back. Tap each to send a ready-written WhatsApp — you see it before it goes.</p>
    ${L.map(l => `<div class="bz-line" data-fk="${esc(l.k)}">${face(l.name, ROSE)}
      <span class="bz-rt"><b>${esc(l.name || l.phone)}</b><small>${esc(followText(l).slice(0, 70))}…</small></span>
      <button class="bz-mini" data-fsend="${esc(l.k)}">${l.phone ? 'Send' : 'Copy'}</button></div>`).join('')}`;
  const { w } = sheet('Follow them up', html, () => {});
  w.querySelector('[data-save]').textContent = 'Done';
  w.querySelector('.bz-sheet-b').addEventListener('click', e => {
    const b = e.target.closest('[data-fsend]'); if (!b) return;
    const l = leads().find(x => x.k === b.dataset.fsend); if (!l) return;
    const text = followText(l);
    if (l.phone) openWa(l.phone, text); else navigator.clipboard?.writeText(text);
    bs.put('Leads', { ...l.r, 'Last contact': iso(), Status: l.status === 'New' ? 'Contacted' : l.status, 'Next follow-up': iso(addDays(new Date(), 3)) }, l.k);
    logWin('follow-up', l.name, 3);
    b.textContent = 'Sent ✓'; b.disabled = true; b.closest('.bz-line').classList.add('done');
  });
}

// ---------------- alerts: speed-to-lead (all devices), checked every minute ----------------
function watch() {
  const W = autoOn('auto_speed') ? waiting() : []; let told = {};
  try { told = JSON.parse(LS.get('zuffiTold', '{}')); } catch {}
  for (const l of W) {
    const stage = l.waitMin >= 15 ? 15 : l.waitMin >= 5 ? 5 : 0; if (!stage) continue;
    const key = l.k + '|' + l.msgAt;
    if ((told[key] || 0) >= stage) continue;
    told[key] = stage;
    const msg = stage === 15 ? `${l.name || l.phone} has waited ${l.waitMin} min — reply now or they’ll go elsewhere` : `${l.name || l.phone} is waiting for a reply (${l.waitMin} min)`;
    try { window.SparrowIsland?.peek('⏱️ ' + msg, 'Tap to reply', 9000); } catch {}
    try { N?.petSay?.('⏱️ ' + msg); } catch {}
    if (document.visibilityState === 'visible') toast('⏱️ ' + msg, 5000);
    else if ('Notification' in window && Notification.permission === 'granted' && !N) { try { new Notification('Zuffi', { body: msg, icon: 'icons/icon-192.png' }); } catch {} }
  }
  const keys = Object.keys(told); if (keys.length > 300) keys.slice(0, 100).forEach(k => delete told[k]);
  LS.set('zuffiTold', JSON.stringify(told));
  if (!DASH()) morningJobs();
  if (isVisible() && tab === 'today') render();
}
// Automations: morning summary, late payments, Monday lost-money report — once a day, from 9am, on this device.
function nudge(msg, sub = '') {
  try { window.SparrowIsland?.peek(msg, sub, 12000); } catch {}
  try { N?.petSay?.(msg); } catch {}
  if (document.visibilityState === 'visible') toast(msg, 7000);
  else if ('Notification' in window && Notification.permission === 'granted' && !N) { try { new Notification('Zuffi', { body: msg + (sub ? '\n' + sub : ''), icon: 'icons/icon-192.png' }); } catch {} }
}
function morningJobs() {
  const d = new Date(); if (d.getHours() < 9 || !leads().length && !bs.rows('Due').length) return;
  const today = iso(); let done = {}; try { done = JSON.parse(LS.get('zuffiJobs', '{}')); } catch {}
  const run = (k, fn) => { if (done[k] === today || !autoOn(k)) return; done[k] = today; fn(); };
  run('auto_brief', () => {
    const due = leads().filter(dueToday).length, W = waiting().length;
    const visits = [...bs.rows('Visits'), ...bs.rows('Appointments')].filter(({ r }) => f(r, 'Date') === today).length;
    const pay = bs.rows('Due').filter(({ r }) => !/paid/i.test(f(r, 'Status')) && f(r, 'Due date') === today).length;
    const parts = [due && `${due} to call`, W && `${W} waiting`, visits && `${visits} ${estate() ? 'viewing' : 'booking'}${visits > 1 ? 's' : ''}`, pay && `${pay} payment${pay > 1 ? 's' : ''} due`].filter(Boolean);
    nudge(`☀️ ${greeting()}! ${parts.length ? 'Today: ' + parts.join(' · ') : 'Nothing urgent today.'}`, 'Open Business → Today');
  });
  run('auto_late', () => {
    const late = bs.rows('Due').filter(({ r }) => !/paid/i.test(f(r, 'Status')) && f(r, 'Due date') && f(r, 'Due date') < today);
    if (late.length) nudge(`💸 ${late.length} payment${late.length > 1 ? 's are' : ' is'} late — ${money(late.reduce((a, { r }) => a + num(f(r, 'Amount')), 0))}`, 'Money → Owed to you → Chase');
  });
  if (d.getDay() === 1) run('auto_lost', () => { const L = forgotten(); if (L.length >= 2) nudge(`📉 ${L.length} people never got a follow-up — about ${money(L.length * avgDeal() * 0.25)} you could still win`, 'Today → Follow them up'); });
  LS.set('zuffiJobs', JSON.stringify(done));
}
// ---------------- sheets (editors) ----------------
function sheet(title, html, onSave, extra = '') {
  document.querySelector('.bz-sheet')?.remove();
  const w = document.createElement('div');
  w.className = 'bz-sheet';
  w.innerHTML = `<div class="bz-sheet-bg"></div><div class="bz-sheet-card glass"><div class="bz-grab"></div><div class="bz-sheet-h"><b>${title}</b><button class="bz-x" data-close>✕</button></div>
    <div class="bz-sheet-b">${html}</div><div class="bz-btns">${extra}<button class="bz-btn" data-save>Save</button></div></div>`;
  document.body.appendChild(w);
  requestAnimationFrame(() => w.classList.add('on'));
  const close = () => { w.classList.remove('on'); setTimeout(() => w.remove(), 260); };
  w.querySelector('.bz-sheet-bg').onclick = close; w.querySelector('[data-close]').onclick = close;
  w.querySelector('[data-save]').onclick = () => Promise.resolve(onSave(w)).then(r => { if (r !== false) close(); });
  return { w, close };
}
const field = (id, label, value = '', attrs = '') => `<label class="bz-lbl">${label}<input class="bz-in" id="${id}" value="${esc(value)}" ${attrs}></label>`;
const read = (w, id) => (w.querySelector('#' + id)?.value || '').trim();

function editLead(k) {
  const old = k ? bs.rows('Leads').find(x => x.k === k)?.r || {} : { Source: '', Status: 'New', Added: iso() };
  const [lw, la, lb, lv] = labels();
  const team = bs.rows('Team').map(({ r }) => f(r, 'Name')).filter(Boolean);
  let status = f(old, 'Status') || 'New', pri = f(old, 'Priority');
  const phone = f(old, 'Phone').replace(/[^\d+]/g, '');
  const wa = phone ? waLink(phone) : '';
  const html = `${field('lName', 'Name', f(old, 'Name'), 'autocomplete="off"')}
    ${field('lPhone', 'Phone / WhatsApp', f(old, 'Phone'), 'inputmode="tel"')}
    ${phone ? `<div class="bz-btns tight"><a class="bz-btn ghost" href="tel:${esc(phone)}">📞 Call</a><a class="bz-btn ghost" href="${esc(wa)}" target="_blank" rel="noopener">💬 WhatsApp</a></div>` : ''}
    <div class="bz-lbl">Stage</div><div class="bz-chips wrap" id="lStage">${stages().map(s => `<button type="button" class="${status === s ? 'on' : ''}" data-v="${esc(s)}" style="--c:${stageColor(s)}">${esc(s)}</button>`).join('')}</div>
    <div class="bz-lbl">How hot</div><div class="bz-chips" id="lPri">${['Hot', 'Warm', 'Cold'].map(s => `<button type="button" class="${pri.toLowerCase() === s.toLowerCase() ? 'on' : ''}" data-v="${s}">${{ Hot: '🔥', Warm: '☀️', Cold: '❄️' }[s]} ${s}</button>`).join('')}</div>
    <div class="bz-grid2">${field('lInt', lw, f(old, 'Interest'))}${field('lArea', la, f(old, 'Area'))}${field('lBud', lb, f(old, 'Budget'))}${field('lVal', lv, f(old, 'Value'))}</div>
    <div class="bz-grid2"><label class="bz-lbl">Source<input class="bz-in" id="lSrc" list="bzSources" value="${esc(f(old, 'Source'))}"></label>
      <label class="bz-lbl">Next follow-up<input class="bz-in" id="lNext" type="date" value="${esc(f(old, 'Next follow-up').slice(0, 10))}"></label></div>
    <datalist id="bzSources">${sources().map(s => `<option>${s}</option>`).join('')}</datalist>
    ${team.length ? `<label class="bz-lbl">Assigned to<select class="bz-in" id="lAsg"><option value="">—</option>${team.map(t => `<option ${f(old, 'Assigned to') === t ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></label>` : ''}
    <label class="bz-lbl">Notes<textarea class="bz-in" id="lNotes" rows="3">${esc(f(old, 'Notes'))}</textarea></label>
    ${f(old, 'Last message') ? `<p class="bz-hint">💬 Last message: “${esc(f(old, 'Last message'))}”</p>` : ''}`;
  const { w } = sheet(k ? esc(f(old, 'Name') || 'Lead') : 'New lead', html, w => {
    const name = read(w, 'lName'), ph = read(w, 'lPhone');
    if (!name && !ph) { toast('Add a name or a number'); return false; }
    const prevStage = f(old, 'Status');
    const row = { ...old, Name: name, Phone: ph, Status: status, Priority: pri, Interest: read(w, 'lInt'), Area: read(w, 'lArea'), Budget: read(w, 'lBud'), Value: read(w, 'lVal'),
      Source: read(w, 'lSrc'), 'Next follow-up': read(w, 'lNext'), Notes: read(w, 'lNotes'), Added: f(old, 'Added') || iso() };
    if (w.querySelector('#lAsg')) row['Assigned to'] = read(w, 'lAsg');
    // Same phone number already in Leads? Update that client instead of making a duplicate.
    let dupe = null;
    if (!k) { const d = ph.replace(/\D/g, '').slice(-9); if (d.length >= 9) dupe = bs.rows('Leads').find(x => f(x.r, 'Phone').replace(/\D/g, '').slice(-9) === d); }
    if (!k && !dupe && !leadRoom()) { upgradeSheet(`Zuffi Pro keeps up to ${account.freeLeads()} business leads. Upgrade to Business to add ${esc(name || 'this client')} and as many more as you like.`); return false; }
    if (dupe) { const keep = {}; for (const c in row) if (String(row[c] ?? '').trim()) keep[c] = row[c]; delete keep.Added; if (keep.Status === 'New') delete keep.Status;
      bs.put('Leads', { ...dupe.r, ...keep }, dupe.k); toast(`${f(dupe.r, 'Name') || 'This number'} is already in your leads — updated ✓`); return; }
    if (!k && !row['Assigned to'] && LS.get('zuffiAgent')) row['Assigned to'] = LS.get('zuffiAgent');
    if (status !== prevStage) { row['Last contact'] = iso(); if (prevStage === 'New') row['Replied at'] = new Date().toISOString().slice(0, 16).replace('T', ' '); }
    bs.put('Leads', row, k || undefined);
    if (status !== prevStage) stageWon(row, prevStage);
    toast(k ? 'Saved ✓' : '✨ Lead added');
  }, k ? '<button class="bz-btn danger" data-del>Delete</button>' : '');
  w.querySelector('#lStage').onclick = e => { const b = e.target.closest('[data-v]'); if (!b) return; status = b.dataset.v; w.querySelectorAll('#lStage button').forEach(x => x.classList.toggle('on', x === b)); };
  w.querySelector('#lPri').onclick = e => { const b = e.target.closest('[data-v]'); if (!b) return; pri = pri === b.dataset.v ? '' : b.dataset.v; w.querySelectorAll('#lPri button').forEach(x => x.classList.toggle('on', x.dataset.v === pri)); };
  w.querySelector('[data-del]')?.addEventListener('click', () => { if (confirmDel()) { bs.del('Leads', k); w.querySelector('[data-close]').click(); toast('Deleted'); } });
}
// Two taps to delete (no browser pop-ups inside the app)
let delArm = 0;
function confirmDel() { if (Date.now() - delArm < 3000) { delArm = 0; return true; } delArm = Date.now(); toast('Tap Delete again to remove it'); return false; }

function editStaff(k) {
  const old = k ? bs.rows('Team').find(x => x.k === k)?.r || {} : {};
  const { w } = sheet(k ? esc(f(old, 'Name')) : 'New staff member', `${field('sName', 'Name', f(old, 'Name'))}${field('sPhone', 'Phone', f(old, 'Phone'), 'inputmode="tel"')}
    ${field('sRole', 'Role', f(old, 'Role'), 'placeholder="Agent, stylist, receptionist…"')}
    <div class="bz-grid2"><label class="bz-lbl">Pay<select class="bz-in" id="sPay">${['Monthly', 'Hourly', 'Commission', 'Daily'].map(p => `<option ${(f(old, 'Pay type') || 'Monthly') === p ? 'selected' : ''}>${p}</option>`).join('')}</select></label>
    ${field('sRate', 'Rate (' + esc(cur()) + ' or %)', f(old, 'Rate'), 'inputmode="decimal"')}</div>
    ${field('sStart', 'Start date', f(old, 'Start date'), 'type="date"')}<label class="bz-lbl">Notes<textarea class="bz-in" id="sNotes" rows="2">${esc(f(old, 'Notes'))}</textarea></label>`, w => {
    if (!read(w, 'sName')) { toast('Add a name'); return false; }
    bs.put('Team', { ...old, Name: read(w, 'sName'), Phone: read(w, 'sPhone'), Role: read(w, 'sRole'), 'Pay type': read(w, 'sPay'), Rate: read(w, 'sRate'), 'Start date': read(w, 'sStart'), Notes: read(w, 'sNotes') }, k || undefined);
    toast('Saved ✓');
  }, k ? '<button class="bz-btn danger" data-del>Remove</button>' : '');
  w.querySelector('[data-del]')?.addEventListener('click', () => { if (confirmDel()) { bs.del('Team', k); w.querySelector('[data-close]').click(); } });
}

function editProp(k) {
  const old = k ? bs.rows('Listings').find(x => x.k === k)?.r || {} : { 'Property ID': 'P' + String(bs.rows('Listings').length + 1).padStart(3, '0'), Status: 'Available', Purpose: 'Sale', Added: iso() };
  const team = bs.rows('Team').map(({ r }) => f(r, 'Name')).filter(Boolean);
  const opt = (id, label, list) => `<label class="bz-lbl">${label}<select class="bz-in" id="${id}">${list.map(o => `<option ${f(old, label) === o ? 'selected' : ''}>${o}</option>`).join('')}</select></label>`;
  const { w } = sheet(k ? esc(f(old, 'Title') || f(old, 'Property ID')) : 'New property', `${field('pTitle', 'Title', f(old, 'Title'), 'placeholder="Property title"')}
    <div class="bz-grid2">${opt('pPurpose', 'Purpose', ['Sale', 'Rent'])}${opt('pType', 'Type', ['Plot', 'House', 'Flat', 'Shop', 'Office', 'File', 'Farmhouse', 'Other'])}
    ${field('pArea', 'Area', f(old, 'Area'))}${field('pBlock', 'Block / Phase', f(old, 'Block / Phase'))}${field('pSize', 'Size', f(old, 'Size'), 'placeholder="Size"')}${field('pPrice', 'Price', f(old, 'Price'), 'placeholder="Price"')}
    ${field('pBeds', 'Beds', f(old, 'Beds'), 'inputmode="numeric"')}${field('pBaths', 'Baths', f(old, 'Baths'), 'inputmode="numeric"')}
    ${opt('pStatus', 'Status', ['Available', 'On hold', 'Token received', 'Sold', 'Rented'])}
    <label class="bz-lbl">Agent<select class="bz-in" id="pAgent"><option value="">—</option>${team.map(t => `<option ${f(old, 'Agent') === t ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></label>
    ${field('pOwner', 'Owner', f(old, 'Owner'))}${field('pOwnerPh', 'Owner phone', f(old, 'Owner phone'), 'inputmode="tel"')}</div>
    ${field('pFeat', 'Features', f(old, 'Features'), 'placeholder="corner, park facing, gas…"')}<label class="bz-lbl">Notes<textarea class="bz-in" id="pNotes" rows="2">${esc(f(old, 'Notes'))}</textarea></label>
    ${feats().compliance ? `<details class="bz-more" ${/rent|let/i.test(f(old, 'Purpose') + f(old, 'Status')) ? 'open' : ''}><summary>Rental: certificates & tenancy (England)</summary><div class="bz-grid2">
      ${field('pGas', 'Gas safety check done', f(old, 'Gas safety'), 'type="date"')}${field('pEicr', 'Electrical check (EICR) done', f(old, 'EICR'), 'type="date"')}
      ${field('pStart', 'Tenancy start', f(old, 'Tenancy start'), 'type="date"')}${field('pDep', 'Deposit protected on', f(old, 'Deposit protected'), 'type="date"')}
      ${field('pRise', 'Last rent rise', f(old, 'Last rent rise'), 'type="date"')}${field('pPet', 'Pet request received', f(old, 'Pet request'), 'type="date"')}
      ${field('pPetA', 'Pet request answered', f(old, 'Pet answered'), 'type="date"')}</div></details>` : ''}
    ${k && matchesFor(old).length ? `<p class="bz-hint">Matching buyers: ${matchesFor(old).map(l => esc(l.name)).join(', ')}</p>` : ''}`, w => {
    const extra = feats().compliance ? { 'Gas safety': read(w, 'pGas'), EICR: read(w, 'pEicr'), 'Tenancy start': read(w, 'pStart'), 'Deposit protected': read(w, 'pDep'), 'Last rent rise': read(w, 'pRise'), 'Pet request': read(w, 'pPet'), 'Pet answered': read(w, 'pPetA') } : {};
    bs.put('Listings', { ...old, Title: read(w, 'pTitle'), Purpose: read(w, 'pPurpose'), Type: read(w, 'pType'), Area: read(w, 'pArea'), 'Block / Phase': read(w, 'pBlock'), Size: read(w, 'pSize'),
      Price: read(w, 'pPrice'), Beds: read(w, 'pBeds'), Baths: read(w, 'pBaths'), Status: read(w, 'pStatus'), Agent: read(w, 'pAgent'), Owner: read(w, 'pOwner'), 'Owner phone': read(w, 'pOwnerPh'), Features: read(w, 'pFeat'), Notes: read(w, 'pNotes'), ...extra }, k || undefined);
    toast('Saved ✓');
  }, k ? '<button class="bz-btn danger" data-del>Delete</button><button class="bz-btn ghost" data-share>Share</button>' : '');
  w.querySelector('[data-del]')?.addEventListener('click', () => { if (confirmDel()) { bs.del('Listings', k); w.querySelector('[data-close]').click(); } });
  w.querySelector('[data-share]')?.addEventListener('click', () => {
    const r = old, text = [`🏠 ${f(r, 'Title') || f(r, 'Size') + ' ' + f(r, 'Type')}`, [f(r, 'Area'), f(r, 'Block / Phase')].filter(Boolean).join(', '), f(r, 'Size') && 'Size: ' + f(r, 'Size'),
      f(r, 'Beds') && `${f(r, 'Beds')} bed · ${f(r, 'Baths') || '–'} bath`, f(r, 'Price') && 'Demand: ' + cur() + ' ' + f(r, 'Price'), f(r, 'Features'), bs.cfg('name') && '— ' + bs.cfg('name')].filter(Boolean).join('\n');
    if (navigator.share) navigator.share({ text }).catch(() => {}); else { navigator.clipboard?.writeText(text); toast('Copied — paste it in WhatsApp'); }
  });
}


/** A lead just became a sale / visit: count the win, and keep them as a client for rebooking. */
function stageWon(row, prev) {
  if (!SALE.includes(f(row, 'Status')) || SALE.includes(prev)) return;
  logWin('deal', f(row, 'Name'), 5, num(f(row, 'Value')));
  if (estate()) return;
  const ex = bs.rows('Clients').find(({ r }) => (f(row, 'Phone') && f(r, 'Phone').replace(/\D/g, '').slice(-9) === f(row, 'Phone').replace(/\D/g, '').slice(-9)) || f(r, 'Name').toLowerCase() === f(row, 'Name').toLowerCase());
  bs.put('Clients', { ...(ex?.r || {}), Name: f(row, 'Name'), Phone: f(row, 'Phone'), 'Last visit': iso(), 'Usual service': f(row, 'Interest') || f(ex?.r || {}, 'Usual service') }, ex?.k);
}
function editClient(k) {
  const old = k ? bs.rows('Clients').find(x => x.k === k)?.r || {} : { 'Last visit': iso() };
  const { w } = sheet(k ? esc(f(old, 'Name')) : 'New client', `${field('cName', 'Name', f(old, 'Name'))}${field('cPhone', 'Phone / WhatsApp', f(old, 'Phone'), 'inputmode="tel"')}
    <div class="bz-grid2">${field('cSvc', 'Usual service', f(old, 'Usual service'), 'placeholder="cut & beard, MOT, boiler service…"')}${field('cLast', 'Last visit', f(old, 'Last visit'), 'type="date"')}
    ${field('cEvery', 'Comes back every (days)', f(old, 'Every (days)'), 'inputmode="numeric" placeholder="' + rebookDays() + '"')}</div>
    <label class="bz-lbl">Notes<textarea class="bz-in" id="cNotes" rows="2">${esc(f(old, 'Notes'))}</textarea></label>`, w => {
    if (!read(w, 'cName')) { toast('Add a name'); return false; }
    bs.put('Clients', { ...old, Name: read(w, 'cName'), Phone: read(w, 'cPhone'), 'Usual service': read(w, 'cSvc'), 'Last visit': read(w, 'cLast'), 'Every (days)': read(w, 'cEvery'), Notes: read(w, 'cNotes') }, k || undefined);
    toast('Saved ✓');
  }, k ? '<button class="bz-btn danger" data-del>Delete</button>' : '');
  w.querySelector('[data-del]')?.addEventListener('click', () => { if (confirmDel()) { bs.del('Clients', k); w.querySelector('[data-close]').click(); } });
}

// ---------------- events ----------------
function onClick(e) {
  const th = e.target.closest('[data-sort]');
  if (th && root.contains(th)) { const k = th.dataset.sort; recSort = recSort[0] === k ? [k, -recSort[1]] : [k, 1]; return render(); }
  const t = e.target.closest('button, [data-lead], [data-prop]'); if (!t || !root.contains(t)) return;
  const d = t.dataset;
  if (d.bt) return;
  if (d.reply) {
    const l = leads().find(x => x.k === d.reply); if (!l) return;
    if (l.phone) openWa(l.phone, ''); else toast('No number saved — open WhatsApp and reply there');
    bs.put('Leads', { ...l.r, Status: 'Contacted', 'Last contact': iso(), 'Replied at': new Date().toISOString().slice(0, 16).replace('T', ' ') }, l.k);
    logWin('reply', l.name, 2); return;
  }
  if (d.lead) return editLead(d.lead);
  if (d.prop) return editProp(d.prop);
  if (d.staff) return editStaff(d.staff);
  if (d.client) return editClient(d.client);
  if (d.stage !== undefined) { stageFilter = d.stage; return render(); }
  if (d.pf !== undefined) { propFilter = d.pf; return render(); }
  if (d.mt) { moneyType = d.mt; return render(); }
  if (d.guide) return openGuide(d.guide);
  if (d.zstyle) { bs.setCfg('zstyle', d.zstyle); render(); return; }
  if (d.theme) { bs.setCfg('accent', d.theme); LS.set('zuffiAccent', d.theme); applyAccent(); render(); return; }
  if (d.delmoney) { if (confirmDel()) bs.del('Money', d.delmoney); return; }
  if (d.chase) {
    const x = bs.rows('Due').find(r => r.k === d.chase); if (!x) return;
    const days = Math.max(0, Math.round((new Date(iso()) - new Date(f(x.r, 'Due date'))) / 864e5));
    const text = chaseText(x.r, days), ph = f(x.r, 'Phone') || leads().find(l => l.name.toLowerCase() === f(x.r, 'Client').toLowerCase())?.phone;
    if (ph) openWa(ph, text); else { navigator.clipboard?.writeText(text); toast('Message copied — no phone saved for this client'); }
    bs.put('Due', { ...x.r, Notes: (f(x.r, 'Notes') ? f(x.r, 'Notes') + ' | ' : '') + 'Chased ' + iso() }, x.k);
    logWin('chase', f(x.r, 'Client'), 5); return;
  }
  if (d.rebook) {
    const x = bs.rows('Clients').find(r => r.k === d.rebook); if (!x) return;
    const text = `Hi ${first(f(x.r, 'Name'))}! It’s been a while since your last ${f(x.r, 'Usual service') || 'visit'} — shall I book you in this week? 🙂${bizName() ? '\n– ' + bizName() : ''}`;
    if (f(x.r, 'Phone')) openWa(f(x.r, 'Phone'), text); else navigator.clipboard?.writeText(text);
    bs.put('Clients', { ...x.r, Notes: (f(x.r, 'Notes') ? f(x.r, 'Notes') + ' | ' : '') + 'Invited ' + iso() }, x.k);
    logWin('rebook', f(x.r, 'Name'), 3); return;
  }
  if (d.paid) {
    const x = bs.rows('Due').find(r => r.k === d.paid); if (!x) return;
    bs.put('Due', { ...x.r, Status: 'Paid', 'Paid on': iso() }, x.k);
    bs.put('Money', { Date: iso(), Type: 'Income', Category: estate() ? 'Installment received' : 'Sales', Amount: f(x.r, 'Amount'), Party: f(x.r, 'Client'), Method: methods()[0], Note: f(x.r, 'For'), 'Added by': bs.deviceName() });
    if (/Chased/.test(f(x.r, 'Notes'))) logWin('collected', f(x.r, 'Client'), 2, num(f(x.r, 'Amount')));
    return toast('Marked paid ✓ and added to money in');
  }
  if (d.pay) {
    const s = bs.rows('Team').find(r => r.k === d.pay); if (!s) return;
    const ym = iso().slice(0, 7), r = s.r, pay = (f(r, 'Pay type') || 'Monthly').toLowerCase();
    const h = bs.rows('Hours').filter(({ r: x }) => (f(x, 'Date') || '').startsWith(ym) && f(x, 'Name') === f(r, 'Name')).reduce((a, { r: x }) => a + num(f(x, 'Hours')), 0);
    const won = leads().filter(l => l.agent === f(r, 'Name') && SALE.includes(l.status) && (l.last || '').startsWith(ym));
    const amt = pay.startsWith('hour') ? num(f(r, 'Rate')) * h : pay.startsWith('comm') ? won.reduce((a, l) => a + num(l.value) * num(f(r, 'Rate')) / 100, 0) : num(f(r, 'Rate'));
    bs.put('Payroll', { Month: ym, Name: f(r, 'Name'), Amount: String(Math.round(amt)), 'Paid on': iso() });
    bs.put('Money', { Date: iso(), Type: 'Expense', Category: estate() ? (pay.startsWith('comm') ? 'Dealer share' : 'Salaries') : 'Wages', Amount: String(Math.round(amt)), Party: f(r, 'Name'), Method: methods()[0], Note: (pay.startsWith('comm') ? 'Commission ' : 'Salary ') + ym, 'Added by': bs.deviceName() });
    return toast(`Paid ${f(r, 'Name')} ✓`);
  }
  switch (d.act) {
    case 'tips': tipsOpen = !tipsOpen; return render();
    case 'csv': return exportRecords();
    case 'addLead': return editLead(null);
    case 'addProp': return editProp(null);
    case 'addClient': return editClient(null);
    case 'addStaff': return editStaff(null);
    case 'followAll': return followAll();
    case 'pickCountry': return onboarding(true);
    case 'battery': N?.openBatterySettings?.(); return;
    case 'pin': return setPin();
    case 'pinOff': if (confirmDel()) { ['zuffiPinHash', 'zuffiPinSalt', 'zuffiPinLen'].forEach(k => { try { localStorage.removeItem(k); } catch {} }); render(); toast('PIN removed'); } return;
    case 'lockNow': unlockedAt = 0; render(); return;
    case 'rotate': if (confirmDel()) { bs.create(); qrShown = true; render(); toast('New link code made — scan it on the devices you still use'); } return;
    case 'wipe': if (confirmDel()) { bs.unlink(); try { localStorage.removeItem('zuffiBiz'); } catch {} toast('Business data removed from this device'); setTimeout(() => location.reload(), 900); } return;
    case 'addMoney': {
      const a = $('#mAmt', root).value.trim(); if (!num(a)) return toast('Type the amount');
      bs.put('Money', { Date: iso(), Type: moneyType, Category: $('#mCat', root).value, Amount: a, Party: $('#mParty', root).value.trim(), Method: $('#mMethod', root).value, Note: $('#mNote', root).value.trim(), 'Added by': bs.deviceName() });
      return toast(moneyType === 'Income' ? 'Money in saved' : 'Expense saved');
    }
    case 'addDue': {
      const c = $('#dClient', root).value.trim(), a = $('#dAmt', root).value.trim(); if (!c || !num(a)) return toast('Add the client and amount');
      bs.put('Due', { Client: c, Phone: $('#dPhone', root).value.trim(), Amount: a, For: $('#dFor', root).value.trim(), 'Due date': $('#dDate', root).value, Status: 'Due' }); return toast('Added ✓');
    }
    case 'addHours': {
      const h = $('#hHours', root).value.trim(); if (!num(h)) return toast('Type the hours');
      bs.put('Hours', { Date: $('#hDate', root).value, Name: $('#hName', root).value, Hours: h, Note: $('#hNote', root).value.trim() }); return toast('Hours saved ✓');
    }
    case 'mtdExport': return exportCsv(d.from, d.to);
    case 'scan': if (!account.isBusiness()) return upgradeSheet('Linking your phone, tablet and computer is part of Zuffi Business.'); return doScan();
    case 'create': if (!account.isBusiness()) return upgradeSheet('Linking your phone, tablet and computer is part of Zuffi Business.'); bs.create(); qrShown = true; render(); return;
    case 'upgrade': return upgradeSheet('Get the whole business on every device.');
    case 'toggleQr': qrShown = !qrShown; render(); return;
    case 'syncNow': bs.syncNow(); return toast('Syncing…');
    case 'unlink': if (confirmDel()) { bs.unlink(); qrShown = false; render(); toast('Unlinked'); } return;
  }
}
function onInput(e) {
  if (e.target.classList.contains('bz-q')) {
    search = e.target.value;
    const pos = e.target.selectionStart; render();
    const q = $('.bz-q', root); q.focus(); try { q.setSelectionRange(pos, pos); } catch {}
  }
}
let cfgT = {};
function onChangeEv(e) {
  const t = e.target, k = t.dataset.cfg;
  if (k) { bs.setCfg(k, t.value); if (['kind', 'currency', 'name', 'rebookDays'].includes(k)) render(); toast('Saved ✓'); }
  if (t.dataset.cfgchk) { bs.setCfg(t.dataset.cfgchk, t.checked ? '1' : ''); toast('Saved ✓'); }
  if (t.dataset.agent) { LS.set('zuffiAgent', t.value); render(); toast(t.value ? `This device is ${t.value}’s` : 'This device is the office’s'); }
  if (t.dataset.phone || t.dataset.phonesel) {
    const o = {}; o[t.dataset.phone || t.dataset.phonesel] = t.dataset.phone ? t.checked : t.value;
    try { N?.setBizPhone?.(JSON.stringify(o)); } catch {}
    toast('Saved ✓');
  }
  if (t.dataset.auto) { bs.setCfg(t.dataset.auto, t.checked ? '1' : '0'); toast(t.checked ? 'On ✓' : 'Off'); }
  if (t.dataset.dset) { window.SparrowDesktop?.setSetting?.(t.dataset.dset, t.checked); toast('Saved ✓'); }
  if (t.dataset.lockmins) { LS.set('zuffiLockMins', t.value); toast('Saved ✓'); }
  if (t.dataset.private !== undefined) { LS.set('zuffiPrivate', t.checked ? '1' : '0'); render(); }
  if (t.dataset.webpet !== undefined) { LS.set('zuffiWebPet', t.checked ? '1' : '0'); window.zuffiWebPet?.(t.checked); }
  if (t.dataset.act2 === 'paste' && !account.isBusiness()) { t.value = ''; upgradeSheet('Linking your phone, tablet and computer is part of Zuffi Business.'); return; }
  if (t.dataset.act2 === 'paste') { if (bs.join(t.value)) { toast('Linked! Getting your business data…'); render(); } else toast('That code doesn’t look right.'); }
}
// Typing in the big text boxes saves a moment after you stop.
document.addEventListener('input', e => {
  const k = e.target?.dataset?.cfg; if (!k || !root?.contains(e.target) || e.target.tagName !== 'TEXTAREA') return;
  clearTimeout(cfgT[k]); cfgT[k] = setTimeout(() => { bs.setCfg(k, e.target.value); if (k === 'missedText') try { N?.setBizPhone?.(JSON.stringify({ missedText: e.target.value })); } catch {} }, 800);
});

async function doScan() {
  const v = $('#bzVideo', root); if (!v) return;
  v.hidden = false;
  const ctl = new AbortController(); setTimeout(() => ctl.abort(), 60000);
  try { if (await bs.scan(v, ctl.signal)) { toast('Linked! Getting your business data…', 4000); render(); } }
  catch { toast('Allow the camera to scan the code.'); }
  v.hidden = true;
}
async function drawQr() {
  const el = $('#bzQr', root); if (!el || el.firstChild) return;
  try { el.innerHTML = await bs.qrSVG(bs.pairingURL()); } catch { el.textContent = bs.pairingURL(); }
}
function exportCsv(from, to) {
  const rows = bs.rows('Money').map(x => x.r).filter(r => f(r, 'Date') >= from && f(r, 'Date') <= to).sort((a, b) => f(a, 'Date').localeCompare(f(b, 'Date')));
  const H = ['Date', 'Type', 'Category', 'Amount', 'Party', 'Method', 'Note'];
  const csv = [H, ...rows.map(r => H.map(h => f(r, h)))].map(l => l.map(c => /[",\n]/.test(c) ? `"${String(c).replace(/"/g, '""')}"` : c).join(',')).join('\n');
  const name = `zuffi-${from}-to-${to}.csv`;
  try {
    const file = new File([csv], name, { type: 'text/csv' });
    if (navigator.canShare?.({ files: [file] })) { navigator.share({ files: [file], title: name }).catch(() => {}); return; }
  } catch {}
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csv], { type: 'text/csv' })); a.download = name; document.body.appendChild(a); a.click(); a.remove();
  toast(`Exported ${rows.length} entries`);
}

// ---------------- Android: chats, missed calls and group posts seen on this phone ----------------
function importPhoneChats(force) {
  if (!N?.waLeads) return 0;
  let list = []; try { list = JSON.parse(N.waLeads()); } catch { return 0; }
  const have = leads(), me = LS.get('zuffiAgent');
  let n = 0, full = 0;
  for (const c of list) {
    const name = (c.name || '').trim(); if (!name) continue;
    const digits = String(c.phone || (/^[+\d\s-]{9,}$/.test(name) ? name : '')).replace(/\D/g, '');
    const ex = have.find(l => (digits.length >= 9 && l.phone.replace(/\D/g, '').slice(-9) === digits.slice(-9)) || l.name.toLowerCase() === name.toLowerCase());
    const sent = c.status === 'sent';
    if (ex) {
      // newer message from someone we know → bring the conversation up to date
      if (c.at && c.at > (ex.msgAt || '')) bs.put('Leads', { ...ex.r, 'Last message': c.last || '', 'Last message at': c.at, ...(sent ? { 'Replied at': c.at, Status: ex.status === 'New' ? 'Contacted' : ex.status } : {}) }, ex.k);
      continue;
    }
    if (!leadRoom()) { full++; continue; }
    bs.put('Leads', { Name: /^[+\d\s-]+$/.test(name) ? '' : name, Phone: digits ? (c.phone || name) : '', Source: c.source || 'WhatsApp', Status: sent ? 'Contacted' : 'New', Added: (c.added || c.at || iso()).slice(0, 10),
      'Last message': c.last || '', 'Last message at': c.at || '', ...(sent ? { 'Replied at': c.at } : {}), 'Assigned to': me || '', Notes: c.needs ? 'Needs you: ' + c.needs : '' });
    if (sent) logWin('auto-reply', name, 3);
    n++;
  }
  if (n && !force) toast(`${n} new enquir${n > 1 ? 'ies' : 'y'} from this phone added to leads`);
  if (full && !force) toast(`${full} new WhatsApp enquir${full > 1 ? 'ies' : 'y'} not saved — Pro keeps up to ${account.freeLeads()} leads. Get Business to keep them all.`, 6000);
  return n;
}
function importGroupListings() {
  if (!N?.waListings || !estate()) return 0;
  let list = []; try { list = JSON.parse(N.waListings()); } catch { return 0; }
  if (!list.length) return 0;
  const have = new Set(bs.rows('Listings').map(({ r }) => f(r, 'Notes').slice(0, 60)));
  let n = 0;
  for (const g of list) {
    const raw = String(g.text || '').trim(); if (!raw || have.has(raw.slice(0, 60))) continue;
    const id = 'G' + Math.abs([...raw].reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 7)).toString(36).slice(0, 6).toUpperCase();
    bs.put('Listings', { 'Property ID': id, Title: [g.size, g.type].filter(Boolean).join(' ') || raw.slice(0, 40), Purpose: g.purpose || 'Sale', Type: g.type || '', Area: g.area || '', Size: g.size || '',
      Price: g.price || '', Status: 'Available', Owner: g.sender || '', 'Owner phone': g.phone || '', Source: 'WhatsApp group', 'Posted by': [g.sender, g.group].filter(Boolean).join(' · '), Added: (g.at || iso()).slice(0, 10), Notes: raw });
    n++;
  }
  N.waListingsClear?.();
  if (n) toast(`${n} propert${n > 1 ? 'ies' : 'y'} from WhatsApp groups added to stock`);
  return n;
}

// ---------------- talking to Zuffi about the business ----------------
/** "new lead Ali 03331234567 from facebook wants 10 marla", "expense 2500 fuel", "mark Ali as hot / won", "follow up Ali tomorrow". */
export function command(text) {
  const t = text.trim(), lo = t.toLowerCase();
  let m;
  if ((m = lo.match(/^(?:new|add)\s+(?:lead|client|customer)\s+(.+)$/))) {
    const rest = t.slice(t.length - m[1].length);
    const phone = (rest.match(/\+?\d[\d\s-]{8,15}\d/) || [''])[0].replace(/[\s-]/g, '');
    let name = rest.replace(phone ? rest.match(/\+?\d[\d\s-]{8,15}\d/)[0] : '', ' ').split(/\s+(?:from|wants|for|in|budget)\s+/i)[0].trim();
    const src = sources().find(s => lo.includes(s.toLowerCase().split('.')[0])) || '';
    const want = (rest.match(/\bwants?\s+(.+?)(?:\s+(?:in|budget|from)\s+|$)/i) || [])[1] || '';
    const area = (rest.match(/\bin\s+(.+?)(?:\s+(?:budget|from|wants)\s+|$)/i) || [])[1] || '';
    const bud = (rest.match(/\bbudget\s+(.+?)(?:\s+(?:in|from|wants)\s+|$)/i) || [])[1] || '';
    if (!name && !phone) return null;
    if (!leadRoom()) return `Zuffi Pro keeps up to ${account.freeLeads()} leads. Open Business → More → Get Business to add more.`;
    bs.put('Leads', { Name: name, Phone: phone, Source: src, Interest: want, Area: area, Budget: bud, Status: 'New', Added: iso() });
    return `✨ Added ${name || phone} to your leads${bs.linked() ? ' — on all your devices' : ''}.`;
  }
  if ((m = lo.match(/^(expense|spent|paid out|income|received|got paid)\s+([\d.,]+\s*(?:k|lakh|lac|crore)?)\s*(?:for|on|from)?\s*(.*)$/))) {
    const inc = /income|received|got paid/.test(m[1]);
    const note = t.slice(t.length - m[3].length).trim();
    const cats = inc ? incomeCats() : expenseCats();
    const cat = cats.find(c => note.toLowerCase().includes(c.toLowerCase().split(' ')[0])) || (inc ? cats[0] : 'Other');
    bs.put('Money', { Date: iso(), Type: inc ? 'Income' : 'Expense', Category: cat, Amount: m[2].trim(), Note: note, Method: methods()[0], 'Added by': bs.deviceName() });
    return `${inc ? '💚 Money in' : '🧾 Expense'} saved: ${cur()} ${m[2].trim()}${note ? ' — ' + note : ''}.`;
  }
  if ((m = lo.match(/^mark\s+(.+?)\s+as\s+(.+)$/))) {
    const l = findLead(m[1]); if (!l) return null;
    const v = m[2].trim(), row = { ...l.r };
    if (['hot', 'warm', 'cold'].includes(v)) row.Priority = v[0].toUpperCase() + v.slice(1);
    else { const s = stages().find(s => s.toLowerCase() === v || s.toLowerCase().startsWith(v)); if (!s) return null; row.Status = s; row['Last contact'] = iso(); }
    bs.put('Leads', row, l.k);
    return `Done — ${l.name || l.phone} is now ${v}.`;
  }
  if ((m = lo.match(/^follow\s*up\s+(?:with\s+)?(.+?)\s+(today|tomorrow|in \d+ days?|next week|on .+)$/))) {
    const l = findLead(m[1]); if (!l) return null;
    const d = new Date(), w = m[2];
    if (w === 'tomorrow') d.setDate(d.getDate() + 1); else if (w === 'next week') d.setDate(d.getDate() + 7);
    else if (/in (\d+)/.test(w)) d.setDate(d.getDate() + +w.match(/in (\d+)/)[1]);
    else if (w.startsWith('on ')) { const p = new Date(w.slice(3)); if (!isNaN(p)) d.setTime(p.getTime()); }
    bs.put('Leads', { ...l.r, 'Next follow-up': iso(d) }, l.k);
    return `⏰ I'll remind you to follow up with ${l.name || l.phone} on ${iso(d)}.`;
  }
  if (/^(how many|show|my)\s+(leads|follow ?ups?)/.test(lo) || /who (should|do) i (call|follow up)/.test(lo)) {
    const due = leads().filter(dueToday);
    return due.length ? `📞 Follow up today: ${due.slice(0, 8).map(l => l.name || l.phone).join(', ')}${due.length > 8 ? '…' : ''}` : `Nobody to follow up today. You have ${leads().length} leads.`;
  }
  if (/^(profit|how much did i make|this month'?s? (profit|money))/.test(lo)) {
    const mm = monthMoney(iso().slice(0, 7));
    return `This month: in ${money(mm.inc)}, out ${money(mm.exp)}, profit ${money(mm.inc - mm.exp)}.`;
  }
  return null;
}
function findLead(who) {
  const w = who.toLowerCase().replace(/['’]s$/, '').trim();
  const L = leads();
  return L.find(l => l.name.toLowerCase() === w) || L.find(l => l.name.toLowerCase().startsWith(w)) || L.find(l => l.name.toLowerCase().split(/\s+/).includes(w))
    || (w.replace(/\D/g, '').length >= 9 ? L.find(l => l.phone.replace(/\D/g, '').slice(-9) === w.replace(/\D/g, '').slice(-9)) : null);
}

/** Leads due today, for reminders on the phone (pet + notifications). */
export function followUpsToday() { return leads().filter(dueToday).map(l => l.name || l.phone); }
