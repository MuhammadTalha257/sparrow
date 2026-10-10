// Zuffi Business on the phone / tablet / Windows — the same leads, money, staff, properties and business
// info as the Mac dashboard, kept in step by bizsync.js (link devices with a QR code).
import * as bs from './bizsync.js';

const $ = (s, el = document) => el.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const iso = (d = new Date()) => { const z = new Date(d.getTime() - d.getTimezoneOffset() * 60000); return z.toISOString().slice(0, 10); };
const N = window.SparrowNative || null;

const PACKS = {
  realEstate: { label: 'Estate agent', icon: '🏠' }, salon: { label: 'Salon / beauty', icon: '💇' }, clinic: { label: 'Clinic / dentist', icon: '🩺' },
  shop: { label: 'Shop / online store', icon: '🛍️' }, restaurant: { label: 'Restaurant / café', icon: '🍽️' }, services: { label: 'Services', icon: '🛠️' },
};
const kind = () => bs.cfg('kind') || 'realEstate';
const estate = () => kind() === 'realEstate';
const country = () => bs.cfg('country') || (/PK|Karachi/.test(Intl.DateTimeFormat().resolvedOptions().timeZone + navigator.language) ? 'PK' : /GB|London/.test(Intl.DateTimeFormat().resolvedOptions().timeZone + navigator.language) ? 'GB' : 'OTHER');
const cur = () => bs.cfg('currency') || ({ PK: 'Rs', GB: '£' }[country()] || '$');
const stages = () => ({
  realEstate: ['New', 'Contacted', 'Site visit', 'Negotiating', 'Won', 'Lost'], salon: ['New', 'Contacted', 'Booked', 'Visited', 'Regular', 'Lost'],
  clinic: ['New', 'Contacted', 'Booked', 'Visited', 'Regular', 'Lost'], restaurant: ['New', 'Contacted', 'Booked', 'Visited', 'Regular', 'Lost'],
  shop: ['New', 'Contacted', 'Quoted', 'Ordered', 'Delivered', 'Lost'], services: ['New', 'Contacted', 'Quoted', 'Negotiating', 'Won', 'Lost'],
}[kind()] || ['New', 'Contacted', 'Won', 'Lost']);
const labels = () => ({
  realEstate: ['Wants', 'Area', 'Budget', 'Deal value'], salon: ['Service', 'Preferred day / staff', 'Budget', 'Spent'], clinic: ['Service', 'Preferred day / staff', 'Budget', 'Spent'],
  restaurant: ['Booking for', 'Party size / time', 'Budget', 'Spent'], shop: ['Product', 'Delivery area', 'Budget', 'Order value'], services: ['Job', 'Location', 'Budget', 'Job value'],
}[kind()]);
const SALE = ['Won', 'Visited', 'Regular', 'Ordered', 'Delivered'];
const incomeCats = () => estate() ? ['Commission', 'Token / advance', 'Installment received', 'Rent collected', 'Other income'] : ['Sales', 'Services', 'Products', 'Deposits', 'Other income'];
const expenseCats = () => estate() ? ['Salaries', 'Office rent', 'Marketing & ads', 'Portal fees (Zameen etc.)', 'Dealer share', 'Fuel & travel', 'Utilities & bills', 'Advance to staff', 'Other']
  : ['Wages', 'Rent', 'Stock & supplies', 'Utilities', 'Marketing', 'Equipment', 'Card / booking fees', 'VAT & tax', 'Advance to staff', 'Other'];
const methods = () => country() === 'PK' ? ['Cash', 'Bank', 'JazzCash', 'Easypaisa', 'Cheque'] : ['Card', 'Cash', 'Bank transfer', 'Online'];
const SOURCES = ['WhatsApp', 'Facebook', 'Instagram', 'Zameen.com', 'Graana', 'OLX', 'TikTok', 'Google', 'Website', 'Referral', 'Walk-in', 'Phone call'];

const f = (r, ...names) => { for (const n of names) for (const k in r) if (k.toLowerCase() === n.toLowerCase()) return r[k] || ''; return ''; };
export const num = v => { const s = String(v || '').toLowerCase().replace(/,/g, ''); const m = s.match(/(\d+(?:\.\d+)?)\s*(crore|cr|lakh|lac|k|m|million)?/); if (!m) return 0; const x = +m[1]; return x * ({ crore: 1e7, cr: 1e7, lakh: 1e5, lac: 1e5, k: 1e3, m: 1e6, million: 1e6 }[m[2]] || 1); };
const money = v => cur() + ' ' + Math.round(v).toLocaleString();

// ---------------- leads helpers ----------------
const leads = () => bs.rows('Leads').map(({ k, r }) => ({ k, r, name: f(r, 'Name'), phone: f(r, 'Phone'), status: f(r, 'Status') || 'New', pri: f(r, 'Priority'),
  next: f(r, 'Next follow-up'), added: f(r, 'Added'), last: f(r, 'Last contact'), value: f(r, 'Value') }));
const isOpen = l => !['Won', 'Lost', 'Delivered', 'Regular'].includes(l.status);
const dueToday = l => isOpen(l) && l.next && l.next.slice(0, 10) <= iso();
const overdue = l => isOpen(l) && l.next && l.next.slice(0, 10) < iso();
const stageColor = s => ({ New: '#7CC4FF', Contacted: '#C4B5FD', 'Site visit': '#FBC56A', Booked: '#FBC56A', Negotiating: '#F59E0B', Quoted: '#F59E0B', Won: '#34D399', Ordered: '#34D399', Visited: '#34D399', Regular: '#34D399', Delivered: '#34D399', Lost: '#9CA3AF' }[s] || '#F58FA8');

// ---------------- view ----------------
let root = null, tab = 'today', search = '', stageFilter = '', toast = t => console.log(t), propFilter = '';
const TABS = [['today', '☀️', 'Today'], ['leads', '👥', 'Leads'], ['money', '💷', 'Money'], ['team', '🧑‍💼', 'Team'], ['props', '🏘️', 'Property'], ['biz', '🏪', 'Business'], ['devices', '🔗', 'Devices']];

export function mount(el, opts = {}) {
  root = el; toast = opts.toast || toast;
  bs.onChange(what => { if (what === 'status' || what === 'peers') renderHead(); else if (isVisible()) render(); else renderHead(); });
  render();
}
const isVisible = () => root && root.closest('.view')?.classList.contains('active');
export function show(t) { if (t) tab = t; importPhoneChats(); render(); }

function render() {
  if (!root) return;
  if (tab === 'props' && !estate() && !bs.rows('Listings').length) tab = 'today';
  const tabs = TABS.filter(([id]) => id !== 'props' || estate() || bs.rows('Listings').length);
  root.innerHTML = `
    <div class="bz-head glass" id="bzHead"></div>
    <div class="bz-tabs" role="tablist">${tabs.map(([id, ic, lb]) => `<button class="${tab === id ? 'on' : ''}" data-bt="${id}"><span>${ic}</span>${lb}</button>`).join('')}</div>
    <div class="bz-body">${({ today: viewToday, leads: viewLeads, money: viewMoney, team: viewTeam, props: viewProps, biz: viewBiz, devices: viewDevices }[tab] || viewToday)()}</div>`;
  // The ＋ button lives on the page itself (a parent with a transform would carry it away while scrolling).
  let fab = document.getElementById('bzFab');
  if (!fab) { fab = document.createElement('button'); fab.id = 'bzFab'; fab.className = 'bz-fab'; document.body.appendChild(fab); }
  const fa = ['today', 'leads'].includes(tab) ? 'addLead' : tab === 'props' ? 'addProp' : '';
  fab.hidden = !fa; fab.textContent = '＋'; fab.setAttribute('aria-label', fa === 'addProp' ? 'Add property' : 'Add lead');
  fab.onclick = () => fa === 'addProp' ? editProp(null) : editLead(null);
  renderHead();
  root.querySelectorAll('[data-bt]').forEach(b => b.onclick = () => { tab = b.dataset.bt; render(); b.scrollIntoView?.({ inline: 'center', block: 'nearest' }); });
  root.onclick = onClick;
  root.oninput = onInput;
  root.onchange = onChangeEv;
  root.querySelector('.bz-tabs .on')?.scrollIntoView?.({ inline: 'center', block: 'nearest' });
}

function renderHead() {
  const h = root && $('#bzHead', root); if (!h) return;
  const name = bs.cfg('name') || 'My business', p = PACKS[kind()] || PACKS.realEstate;
  const peers = Object.entries(bs.peers()).sort((a, b) => b[1] - a[1]);
  const chip = bs.linked()
    ? `<button class="bz-sync ${bs.status.connected ? 'live' : ''}" data-bt2="devices"><i></i>${bs.status.connected ? 'Live' : 'Connecting'}${peers.length ? ' · ' + peers.length + ' device' + (peers.length > 1 ? 's' : '') : ''}</button>`
    : `<button class="bz-sync off" data-bt2="devices"><i></i>Link devices</button>`;
  h.innerHTML = `<div class="bz-logo">${p.icon}</div><div class="bz-ttl"><b>${esc(name)}</b><small>${esc(p.label)}${country() === 'PK' ? ' · Pakistan' : country() === 'GB' ? ' · UK' : ''}</small></div>${chip}`;
  h.querySelector('[data-bt2]').onclick = () => { tab = 'devices'; render(); };
}

const tile = (label, value, icon, color) => `<div class="bz-tile glass" style="--c:${color}"><span>${icon}</span><b>${esc(String(value))}</b><small>${esc(label)}</small></div>`;
const empty = t => `<p class="bz-empty">${t}</p>`;
const pill = (t, c) => `<span class="bz-pill" style="--c:${c}">${esc(t)}</span>`;

function leadRow(l) {
  const sub = [f(l.r, 'Interest'), f(l.r, 'Area'), f(l.r, 'Budget')].filter(Boolean).join(' · ') || l.phone || f(l.r, 'Source');
  const due = l.next ? (overdue(l) ? `<em class="bad">⏰ ${esc(l.next.slice(0, 10))}</em>` : dueToday(l) ? '<em class="warn">⏰ today</em>' : `<em>${esc(l.next.slice(0, 10))}</em>`) : '';
  return `<button class="bz-row" data-lead="${esc(l.k)}">
    <span class="bz-av" style="--c:${stageColor(l.status)}">${esc((l.name || l.phone || '?').trim().charAt(0).toUpperCase())}</span>
    <span class="bz-rt"><b>${esc(l.name || l.phone || 'No name')}${l.pri.toLowerCase() === 'hot' ? ' 🔥' : ''}</b><small>${esc(sub)}</small></span>
    <span class="bz-rr">${pill(l.status, stageColor(l.status))}${due}</span></button>`;
}

function viewToday() {
  const L = leads(), today = iso(), ago = iso(new Date(Date.now() - 30 * 864e5));
  const sales = L.filter(l => SALE.includes(l.status) && (l.last || l.added) >= ago);
  const due = L.filter(dueToday).sort((a, b) => (a.next || '').localeCompare(b.next || ''));
  const recent = [...L].sort((a, b) => (b.added || '').localeCompare(a.added || '')).slice(0, 6);
  const m = monthMoney(today.slice(0, 7));
  return `<div class="bz-tiles">
      ${tile('New today', L.filter(l => (l.added || '').slice(0, 10) === today).length, '📥', '#7CC4FF')}
      ${tile('Follow up today', due.length, '📞', '#FBC56A')}
      ${tile('Hot leads', L.filter(l => isOpen(l) && l.pri.toLowerCase() === 'hot').length, '🔥', '#F58FA8')}
      ${tile('Overdue', L.filter(overdue).length, '⚠️', '#F87171')}
      ${tile('Sales · 30 days', sales.length, '🏆', '#34D399')}
      ${tile('Profit this month', money(m.inc - m.exp), '💷', m.inc - m.exp >= 0 ? '#34D399' : '#F87171')}
    </div>
    <div class="bz-card glass"><h4>📞 Follow up today</h4>${due.length ? due.slice(0, 12).map(leadRow).join('') : empty('Nobody to chase today 🎉')}</div>
    <div class="bz-card glass"><h4>🆕 Latest leads</h4>${recent.length ? recent.map(leadRow).join('') : empty('No leads yet. Tap ＋ to add one, or link your Mac in Devices to see the same leads here.')}</div>
    <div class="bz-card glass"><h4>📣 Today's update for clients</h4>
      <textarea class="bz-in" data-cfg="today" rows="3" placeholder="e.g. 10% off colour today · new plots in Phase 8 · closed at 4pm">${esc(bs.cfg('today'))}</textarea>
      <small class="bz-hint">Zuffi's replies use this today (on every linked device).</small></div>`;
}

function viewLeads() {
  const q = search.toLowerCase();
  const L = leads().filter(l => (!stageFilter || l.status === stageFilter) && (!q || JSON.stringify(l.r).toLowerCase().includes(q)))
    .sort((a, b) => (dueToday(b) - dueToday(a)) || (b.added || '').localeCompare(a.added || ''));
  const counts = Object.fromEntries(stages().map(s => [s, leads().filter(l => l.status === s).length]));
  return `<div class="bz-search glass"><span>🔎</span><input class="bz-q" placeholder="Search name, number, area…" value="${esc(search)}"></div>
    <div class="bz-chips"><button class="${!stageFilter ? 'on' : ''}" data-stage="">All ${leads().length}</button>${stages().map(s => `<button class="${stageFilter === s ? 'on' : ''}" data-stage="${esc(s)}" style="--c:${stageColor(s)}">${esc(s)} ${counts[s] || 0}</button>`).join('')}</div>
    <div class="bz-card glass">${L.length ? L.map(leadRow).join('') : empty(search || stageFilter ? 'No leads match.' : 'No leads yet. Tap ＋ to add one.')}</div>`;
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
let moneyType = 'Expense';
function viewMoney() {
  const ym = iso().slice(0, 7), m = monthMoney(ym);
  const due = bs.rows('Due').filter(({ r }) => !/paid/i.test(f(r, 'Status'))).sort((a, b) => f(a.r, 'Due date').localeCompare(f(b.r, 'Due date')));
  const cats = moneyType === 'Income' ? incomeCats() : expenseCats();
  return `<div class="bz-tiles three">
      ${tile('Money in', money(m.inc), '⬇️', '#34D399')}${tile('Money out', money(m.exp), '⬆️', '#F87171')}${tile('Profit', money(m.inc - m.exp), '✨', m.inc - m.exp >= 0 ? '#34D399' : '#F87171')}
    </div>
    <div class="bz-card glass"><h4>➕ Add</h4>
      <div class="bz-seg"><button class="${moneyType === 'Expense' ? 'on' : ''}" data-mt="Expense">Money out</button><button class="${moneyType === 'Income' ? 'on' : ''}" data-mt="Income">Money in</button></div>
      <div class="bz-grid2">
        <input class="bz-in" id="mAmt" inputmode="decimal" placeholder="Amount (${esc(cur())})">
        <select class="bz-in" id="mCat">${cats.map(c => `<option>${esc(c)}</option>`).join('')}</select>
        <input class="bz-in" id="mParty" placeholder="${moneyType === 'Income' ? 'From (client)' : 'Paid to'}">
        <select class="bz-in" id="mMethod">${methods().map(c => `<option>${esc(c)}</option>`).join('')}</select>
      </div>
      <input class="bz-in" id="mNote" placeholder="Note (optional)">
      <button class="bz-btn" data-act="addMoney">Save</button></div>
    <div class="bz-card glass"><h4>🧾 ${new Date().toLocaleDateString([], { month: 'long' })}</h4>
      ${m.list.length ? m.list.slice(0, 60).map(x => `<div class="bz-line"><span class="bz-rt"><b>${esc(f(x.r, 'Category') || f(x.r, 'Type'))}</b><small>${esc([f(x.r, 'Date'), f(x.r, 'Party'), f(x.r, 'Method'), f(x.r, 'Note')].filter(Boolean).join(' · '))}</small></span>
        <b class="${x.t.startsWith('inc') ? 'good' : 'bad'}">${x.t.startsWith('inc') ? '+' : '−'}${esc(money(x.a))}</b><button class="bz-x" data-delmoney="${esc(x.k)}" aria-label="Delete">✕</button></div>`).join('') : empty('Nothing this month yet.')}</div>
    <div class="bz-card glass"><h4>⏳ Money owed to you</h4>
      ${due.length ? due.map(({ k, r }) => `<div class="bz-line"><span class="bz-rt"><b>${esc(f(r, 'Client'))}</b><small>${esc([f(r, 'For'), 'due ' + f(r, 'Due date')].filter(Boolean).join(' · '))}</small></span>
        <b>${esc(money(num(f(r, 'Amount'))))}</b><button class="bz-mini" data-paid="${esc(k)}">Paid ✓</button></div>`).join('') : empty('No one owes you money 👍')}
      <details class="bz-more"><summary>Add money owed</summary>
        <div class="bz-grid2"><input class="bz-in" id="dClient" placeholder="Client"><input class="bz-in" id="dAmt" inputmode="decimal" placeholder="Amount">
        <input class="bz-in" id="dFor" placeholder="For (installment, deposit…)"><input class="bz-in" id="dDate" type="date" value="${iso()}"></div>
        <button class="bz-btn ghost" data-act="addDue">Add</button></details></div>`;
}

// ---------------- team ----------------
function viewTeam() {
  const team = bs.rows('Team'), ym = iso().slice(0, 7);
  const hours = {}; bs.rows('Hours').forEach(({ r }) => { if ((f(r, 'Date') || '').startsWith(ym)) hours[f(r, 'Name')] = (hours[f(r, 'Name')] || 0) + num(f(r, 'Hours')); });
  const paid = new Set(bs.rows('Payroll').filter(({ r }) => f(r, 'Month') === ym && f(r, 'Paid on')).map(({ r }) => f(r, 'Name').toLowerCase()));
  return `<div class="bz-card glass"><h4>🧑‍💼 Team & staff <button class="bz-mini r" data-act="addStaff">＋ Add</button></h4>
      ${team.length ? team.map(({ k, r }) => {
        const pay = f(r, 'Pay type') || 'Monthly', rate = f(r, 'Rate');
        const owed = pay.toLowerCase().startsWith('hour') ? num(rate) * (hours[f(r, 'Name')] || 0) : pay.toLowerCase().startsWith('month') ? num(rate) : 0;
        return `<div class="bz-line"><button class="bz-rowbtn" data-staff="${esc(k)}"><span class="bz-av" style="--c:#C4B5FD">${esc(f(r, 'Name').charAt(0).toUpperCase())}</span>
          <span class="bz-rt"><b>${esc(f(r, 'Name'))}</b><small>${esc([f(r, 'Role'), pay + (rate ? ' ' + cur() + ' ' + rate : ''), hours[f(r, 'Name')] ? hours[f(r, 'Name')] + ' h this month' : ''].filter(Boolean).join(' · '))}</small></span></button>
          ${owed ? (paid.has(f(r, 'Name').toLowerCase()) ? pill('Paid', '#34D399') : `<button class="bz-mini" data-pay="${esc(k)}">Pay ${esc(money(owed))}</button>`) : ''}</div>`;
      }).join('') : empty('Add your staff / agents to track salaries, hours and commission.')}</div>
    ${team.length ? `<div class="bz-card glass"><h4>⏱️ Log hours</h4><div class="bz-grid2">
        <select class="bz-in" id="hName">${team.map(({ r }) => `<option>${esc(f(r, 'Name'))}</option>`).join('')}</select>
        <input class="bz-in" id="hHours" inputmode="decimal" placeholder="Hours"><input class="bz-in" id="hDate" type="date" value="${iso()}"><input class="bz-in" id="hNote" placeholder="Note"></div>
        <button class="bz-btn ghost" data-act="addHours">Save hours</button></div>` : ''}`;
}

// ---------------- properties ----------------
function viewProps() {
  const P = bs.rows('Listings').filter(({ r }) => !propFilter || f(r, 'Purpose').toLowerCase().includes(propFilter) || (propFilter === 'available' && !/sold|rented/i.test(f(r, 'Status'))));
  return `<div class="bz-chips">${[['', 'All'], ['available', 'Available'], ['sale', 'For sale'], ['rent', 'For rent']].map(([v, t]) => `<button class="${propFilter === v ? 'on' : ''}" data-pf="${v}">${t}</button>`).join('')}</div>
    <div class="bz-props">${P.length ? P.map(({ k, r }) => `<button class="bz-prop glass" data-prop="${esc(k)}">
        <span class="bz-ptop">${pill(f(r, 'Status') || 'Available', /sold|rented/i.test(f(r, 'Status')) ? '#9CA3AF' : '#34D399')}<small>${esc(f(r, 'Property ID'))}</small></span>
        <b>${esc(f(r, 'Title') || [f(r, 'Size'), f(r, 'Type')].filter(Boolean).join(' ') || 'Property')}</b>
        <small>${esc([f(r, 'Area'), f(r, 'Block / Phase')].filter(Boolean).join(', '))}</small>
        <span class="bz-pbot"><b>${esc(f(r, 'Price') ? cur() + ' ' + f(r, 'Price') : '')}</b><small>${esc([f(r, 'Purpose'), f(r, 'Beds') && f(r, 'Beds') + ' bed', f(r, 'Agent')].filter(Boolean).join(' · '))}</small></span></button>`).join('')
      : empty('No properties yet. Tap ＋ to add your first plot, house, flat or shop.')}</div>`;
}

// ---------------- business ----------------
function viewBiz() {
  const k = kind();
  return `<div class="bz-card glass"><h4>🏪 My business</h4>
      <label class="bz-lbl">Business name<input class="bz-in" data-cfg="name" value="${esc(bs.cfg('name'))}" placeholder="e.g. Al-Noor Estate, Glow Salon"></label>
      <div class="bz-grid2">
        <label class="bz-lbl">Country<select class="bz-in" data-cfg="country">${[['PK', 'Pakistan'], ['GB', 'United Kingdom'], ['OTHER', 'Other']].map(([v, t]) => `<option value="${v}" ${country() === v ? 'selected' : ''}>${t}</option>`).join('')}</select></label>
        <label class="bz-lbl">Currency<select class="bz-in" data-cfg="currency">${['Rs', '£', '$', '€', 'AED', 'SAR', '₹'].map(c => `<option ${cur() === c ? 'selected' : ''}>${c}</option>`).join('')}</select></label>
      </div>
      <label class="bz-lbl">Type of business<select class="bz-in" data-cfg="kind">${Object.entries(PACKS).filter(([id]) => country() !== 'PK' || id === 'realEstate').map(([id, p]) => `<option value="${id}" ${k === id ? 'selected' : ''}>${p.icon} ${p.label}</option>`).join('')}</select></label></div>
    <div class="bz-card glass"><h4>📋 Business info for replies</h4>
      <textarea class="bz-in" data-cfg="info" rows="7" placeholder="Opening hours, prices, location, what you sell, how to book…">${esc(bs.cfg('info'))}</textarea>
      <small class="bz-hint">Zuffi uses this when it answers clients on WhatsApp.</small></div>
    <div class="bz-card glass"><h4>📣 Today's update</h4>
      <textarea class="bz-in" data-cfg="today" rows="3" placeholder="Discounts, new stock, new plots, closed early…">${esc(bs.cfg('today'))}</textarea></div>
    ${N?.waLeads ? `<div class="bz-card glass"><h4>💬 WhatsApp on this phone</h4><p class="bz-hint">Chats Zuffi saw on this phone become leads here automatically.</p><button class="bz-btn ghost" data-act="importWa">Bring in WhatsApp chats now</button></div>` : ''}`;
}

// ---------------- devices ----------------
let qrShown = false;
function viewDevices() {
  if (!bs.linked()) return `<div class="bz-card glass bz-link">
      <div class="bz-linkart"><span>💻</span><i></i><span>📱</span><i></i><span>📲</span></div>
      <h3>One business, every device</h3>
      <p>Link this ${/Mobi|Android|iPhone/.test(navigator.userAgent) ? 'phone' : 'device'} to your Mac, tablet or other phones. Add a lead or an expense on one — it appears on the others in seconds. Everything is end-to-end encrypted.</p>
      <button class="bz-btn" data-act="scan">📷 Scan the code from my Mac</button>
      <button class="bz-btn ghost" data-act="create">Show a code to link another device</button>
      <input class="bz-in" data-act2="paste" placeholder="…or paste a link code">
      <video class="bz-video" id="bzVideo" hidden muted></video>
      <small class="bz-hint">On the Mac: Business → Connect & devices → Link my phone.</small></div>`;
  const peers = Object.entries(bs.peers()).sort((a, b) => b[1] - a[1]);
  return `<div class="bz-card glass bz-link">
      <div class="bz-status ${bs.status.connected ? 'live' : ''}"><i></i>${bs.status.connected ? 'Live — changes sync instantly' : 'Connecting to your other devices…'}</div>
      ${bs.status.last ? `<small class="bz-hint">Last change ${ago(bs.status.last)}</small>` : ''}
      <h4>Linked devices</h4>
      <div class="bz-dev"><span>${/Mobi|Android|iPhone/.test(navigator.userAgent) ? '📱' : '💻'}</span><b>This ${esc(bs.deviceName())}</b><small>you're here</small></div>
      ${peers.length ? peers.map(([n, t]) => `<div class="bz-dev"><span>${/mac|pc|windows|computer/i.test(n) ? '💻' : /ipad|tablet/i.test(n) ? '📲' : '📱'}</span><b>${esc(n)}</b><small>${ago(t)}</small></div>`).join('') : '<p class="bz-hint">No other device has said hello yet. Open Zuffi on the other device.</p>'}
      ${qrShown ? `<div class="bz-qr" id="bzQr"></div><small class="bz-hint warn">Keep this code private — whoever scans it sees your business data.</small>` : ''}
      <div class="bz-btns"><button class="bz-btn ghost" data-act="toggleQr">${qrShown ? 'Hide code' : 'Link another device'}</button><button class="bz-btn ghost" data-act="syncNow">Sync now</button></div>
      <button class="bz-link-x" data-act="unlink">Unlink this device</button></div>`;
}
const ago = t => { const s = (Date.now() - t) / 1000; return s < 50 ? 'just now' : s < 3600 ? Math.round(s / 60) + ' min ago' : s < 86400 ? Math.round(s / 3600) + ' h ago' : Math.round(s / 86400) + ' d ago'; };

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
  w.querySelector('[data-save]').onclick = () => { if (onSave(w) !== false) close(); };
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
  const wa = phone ? 'https://wa.me/' + phone.replace(/^\+/, '').replace(/^0(?=3\d{9}$)/, '92') : '';
  const html = `${field('lName', 'Name', f(old, 'Name'), 'autocomplete="off"')}
    ${field('lPhone', 'Phone / WhatsApp', f(old, 'Phone'), 'inputmode="tel"')}
    ${phone ? `<div class="bz-btns tight"><a class="bz-btn ghost" href="tel:${esc(phone)}">📞 Call</a><a class="bz-btn ghost" href="${esc(wa)}" target="_blank" rel="noopener">💬 WhatsApp</a></div>` : ''}
    <div class="bz-lbl">Stage</div><div class="bz-chips wrap" id="lStage">${stages().map(s => `<button type="button" class="${status === s ? 'on' : ''}" data-v="${esc(s)}" style="--c:${stageColor(s)}">${esc(s)}</button>`).join('')}</div>
    <div class="bz-lbl">How hot</div><div class="bz-chips" id="lPri">${['Hot', 'Warm', 'Cold'].map(s => `<button type="button" class="${pri.toLowerCase() === s.toLowerCase() ? 'on' : ''}" data-v="${s}">${{ Hot: '🔥', Warm: '☀️', Cold: '❄️' }[s]} ${s}</button>`).join('')}</div>
    <div class="bz-grid2">${field('lInt', lw, f(old, 'Interest'))}${field('lArea', la, f(old, 'Area'))}${field('lBud', lb, f(old, 'Budget'))}${field('lVal', lv, f(old, 'Value'))}</div>
    <div class="bz-grid2"><label class="bz-lbl">Source<input class="bz-in" id="lSrc" list="bzSources" value="${esc(f(old, 'Source'))}"></label>
      <label class="bz-lbl">Next follow-up<input class="bz-in" id="lNext" type="date" value="${esc(f(old, 'Next follow-up').slice(0, 10))}"></label></div>
    <datalist id="bzSources">${SOURCES.map(s => `<option>${s}</option>`).join('')}</datalist>
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
    if (status !== prevStage) row['Last contact'] = iso();
    bs.put('Leads', row, k || undefined);
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
  const { w } = sheet(k ? esc(f(old, 'Title') || f(old, 'Property ID')) : 'New property', `${field('pTitle', 'Title', f(old, 'Title'), 'placeholder="10 Marla house, DHA Phase 6"')}
    <div class="bz-grid2">${opt('pPurpose', 'Purpose', ['Sale', 'Rent'])}${opt('pType', 'Type', ['Plot', 'House', 'Flat', 'Shop', 'Office', 'File', 'Farmhouse', 'Other'])}
    ${field('pArea', 'Area', f(old, 'Area'))}${field('pBlock', 'Block / Phase', f(old, 'Block / Phase'))}${field('pSize', 'Size', f(old, 'Size'), 'placeholder="10 marla, 1 kanal…"')}${field('pPrice', 'Price', f(old, 'Price'), 'placeholder="2.5 crore"')}
    ${field('pBeds', 'Beds', f(old, 'Beds'), 'inputmode="numeric"')}${field('pBaths', 'Baths', f(old, 'Baths'), 'inputmode="numeric"')}
    ${opt('pStatus', 'Status', ['Available', 'On hold', 'Token received', 'Sold', 'Rented'])}
    <label class="bz-lbl">Agent<select class="bz-in" id="pAgent"><option value="">—</option>${team.map(t => `<option ${f(old, 'Agent') === t ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select></label>
    ${field('pOwner', 'Owner', f(old, 'Owner'))}${field('pOwnerPh', 'Owner phone', f(old, 'Owner phone'), 'inputmode="tel"')}</div>
    ${field('pFeat', 'Features', f(old, 'Features'), 'placeholder="corner, park facing, gas…"')}<label class="bz-lbl">Notes<textarea class="bz-in" id="pNotes" rows="2">${esc(f(old, 'Notes'))}</textarea></label>`, w => {
    bs.put('Listings', { ...old, Title: read(w, 'pTitle'), Purpose: read(w, 'pPurpose'), Type: read(w, 'pType'), Area: read(w, 'pArea'), 'Block / Phase': read(w, 'pBlock'), Size: read(w, 'pSize'),
      Price: read(w, 'pPrice'), Beds: read(w, 'pBeds'), Baths: read(w, 'pBaths'), Status: read(w, 'pStatus'), Agent: read(w, 'pAgent'), Owner: read(w, 'pOwner'), 'Owner phone': read(w, 'pOwnerPh'), Features: read(w, 'pFeat'), Notes: read(w, 'pNotes') }, k || undefined);
    toast('Saved ✓');
  }, k ? '<button class="bz-btn danger" data-del>Delete</button><button class="bz-btn ghost" data-share>Share</button>' : '');
  w.querySelector('[data-del]')?.addEventListener('click', () => { if (confirmDel()) { bs.del('Listings', k); w.querySelector('[data-close]').click(); } });
  w.querySelector('[data-share]')?.addEventListener('click', () => {
    const r = old, text = [`🏠 ${f(r, 'Title') || f(r, 'Size') + ' ' + f(r, 'Type')}`, [f(r, 'Area'), f(r, 'Block / Phase')].filter(Boolean).join(', '), f(r, 'Size') && 'Size: ' + f(r, 'Size'),
      f(r, 'Beds') && `${f(r, 'Beds')} bed · ${f(r, 'Baths') || '–'} bath`, f(r, 'Price') && 'Demand: ' + cur() + ' ' + f(r, 'Price'), f(r, 'Features'), bs.cfg('name') && '— ' + bs.cfg('name')].filter(Boolean).join('\n');
    if (navigator.share) navigator.share({ text }).catch(() => {}); else { navigator.clipboard?.writeText(text); toast('Copied — paste it in WhatsApp'); }
  });
}

// ---------------- events ----------------
function onClick(e) {
  const t = e.target.closest('button, [data-lead], [data-prop]'); if (!t) return;
  const d = t.dataset;
  if (d.lead) return editLead(d.lead);
  if (d.prop) return editProp(d.prop);
  if (d.staff) return editStaff(d.staff);
  if (d.stage !== undefined) { stageFilter = d.stage; return render(); }
  if (d.pf !== undefined) { propFilter = d.pf; return render(); }
  if (d.mt) { moneyType = d.mt; return render(); }
  if (d.delmoney) { if (confirmDel()) bs.del('Money', d.delmoney); return; }
  if (d.paid) {
    const x = bs.rows('Due').find(r => r.k === d.paid); if (!x) return;
    bs.put('Due', { ...x.r, Status: 'Paid', 'Paid on': iso() }, x.k);
    bs.put('Money', { Date: iso(), Type: 'Income', Category: estate() ? 'Installment received' : 'Sales', Amount: f(x.r, 'Amount'), Party: f(x.r, 'Client'), Method: methods()[0], Note: f(x.r, 'For'), 'Added by': bs.deviceName() });
    return toast('Marked paid ✓ and added to money in');
  }
  if (d.pay) {
    const s = bs.rows('Team').find(r => r.k === d.pay); if (!s) return;
    const ym = iso().slice(0, 7), r = s.r, pay = (f(r, 'Pay type') || 'Monthly').toLowerCase();
    const h = bs.rows('Hours').filter(({ r: x }) => (f(x, 'Date') || '').startsWith(ym) && f(x, 'Name') === f(r, 'Name')).reduce((a, { r: x }) => a + num(f(x, 'Hours')), 0);
    const amt = pay.startsWith('hour') ? num(f(r, 'Rate')) * h : num(f(r, 'Rate'));
    bs.put('Payroll', { Month: ym, Name: f(r, 'Name'), Amount: String(Math.round(amt)), 'Paid on': iso() });
    bs.put('Money', { Date: iso(), Type: 'Expense', Category: estate() ? 'Salaries' : 'Wages', Amount: String(Math.round(amt)), Party: f(r, 'Name'), Method: methods()[0], Note: 'Salary ' + ym, 'Added by': bs.deviceName() });
    return toast(`Paid ${f(r, 'Name')} ✓`);
  }
  switch (d.act) {
    case 'addLead': return editLead(null);
    case 'addProp': return editProp(null);
    case 'addStaff': return editStaff(null);
    case 'addMoney': {
      const a = $('#mAmt', root).value.trim(); if (!num(a)) return toast('Type the amount');
      bs.put('Money', { Date: iso(), Type: moneyType, Category: $('#mCat', root).value, Amount: a, Party: $('#mParty', root).value.trim(), Method: $('#mMethod', root).value, Note: $('#mNote', root).value.trim(), 'Added by': bs.deviceName() });
      return toast(moneyType === 'Income' ? '💚 Money in saved' : '🧾 Expense saved');
    }
    case 'addDue': {
      const c = $('#dClient', root).value.trim(), a = $('#dAmt', root).value.trim(); if (!c || !num(a)) return toast('Add the client and amount');
      bs.put('Due', { Client: c, Amount: a, For: $('#dFor', root).value.trim(), 'Due date': $('#dDate', root).value, Status: 'Due' }); return toast('Added ✓');
    }
    case 'addHours': {
      const h = $('#hHours', root).value.trim(); if (!num(h)) return toast('Type the hours');
      bs.put('Hours', { Date: $('#hDate', root).value, Name: $('#hName', root).value, Hours: h, Note: $('#hNote', root).value.trim() }); return toast('Hours saved ✓');
    }
    case 'importWa': { const n = importPhoneChats(true); return toast(n ? `${n} chat${n > 1 ? 's' : ''} added as leads` : 'No new WhatsApp chats'); }
    case 'scan': return doScan();
    case 'create': bs.create(); qrShown = true; render(); return drawQr();
    case 'toggleQr': qrShown = !qrShown; render(); return qrShown && drawQr();
    case 'syncNow': bs.syncNow(); return toast('🔄 Syncing…');
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
  const k = e.target.dataset.cfg;
  if (k) { bs.setCfg(k, e.target.value); if (['kind', 'country', 'currency', 'name'].includes(k)) render(); toast('Saved ✓'); }
  if (e.target.dataset.act2 === 'paste') { if (bs.join(e.target.value)) { toast('💗 Linked! Getting your business data…'); render(); } else toast('That code doesn’t look right.'); }
}
// Typing in the big text boxes saves a moment after you stop.
document.addEventListener('input', e => {
  const k = e.target?.dataset?.cfg; if (!k || !root?.contains(e.target) || e.target.tagName !== 'TEXTAREA') return;
  clearTimeout(cfgT[k]); cfgT[k] = setTimeout(() => bs.setCfg(k, e.target.value), 800);
});

async function doScan() {
  const v = $('#bzVideo', root); if (!v) return;
  v.hidden = false;
  const ctl = new AbortController(); setTimeout(() => ctl.abort(), 60000);
  try { if (await bs.scan(v, ctl.signal)) { toast('💗 Linked! Getting your business data…', 4000); render(); } }
  catch { toast('Allow the camera to scan the code.'); }
  v.hidden = true;
}
async function drawQr() {
  const el = $('#bzQr', root); if (!el) return;
  try { el.innerHTML = await bs.qrSVG(bs.pairingURL()); } catch { el.textContent = bs.pairingURL(); }
}

/** Android: WhatsApp chats Zuffi saw on this phone → leads (once each). */
function importPhoneChats(force) {
  if (!N?.waLeads) return 0;
  let list = []; try { list = JSON.parse(N.waLeads()); } catch { return 0; }
  const have = leads();
  let n = 0;
  for (const c of list) {
    const name = (c.name || '').trim(); if (!name) continue;
    if (have.some(l => (c.phone && l.phone && l.phone.replace(/\D/g, '').slice(-9) === String(c.phone).replace(/\D/g, '').slice(-9)) || l.name.toLowerCase() === name.toLowerCase())) continue;
    bs.put('Leads', { Name: name, Phone: c.phone || '', Source: 'WhatsApp', Status: 'New', Added: (c.at || iso()).slice(0, 10), 'Last message': c.last || '', 'Last message at': c.at || '', Notes: c.needs ? 'Needs you: ' + c.needs : '' });
    n++;
  }
  if (n && !force) toast(`💬 ${n} WhatsApp chat${n > 1 ? 's' : ''} added to leads`);
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
    const src = SOURCES.find(s => lo.includes(s.toLowerCase().split('.')[0])) || '';
    const want = (rest.match(/\bwants?\s+(.+?)(?:\s+(?:in|budget|from)\s+|$)/i) || [])[1] || '';
    const area = (rest.match(/\bin\s+(.+?)(?:\s+(?:budget|from|wants)\s+|$)/i) || [])[1] || '';
    const bud = (rest.match(/\bbudget\s+(.+?)(?:\s+(?:in|from|wants)\s+|$)/i) || [])[1] || '';
    if (!name && !phone) return null;
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
