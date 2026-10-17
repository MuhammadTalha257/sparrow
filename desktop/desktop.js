// The Zuffi island for Windows (and the old Mac build): a black glass island at the top of the screen that springs open.
// Loaded only in the computer app, never on phones.
import { store } from './store.js';
import { greetingWord, fmtTime, tasksForDay } from './brain.js';
import * as mem from './memory.js';
import { mountMascot } from './mascot.js';

const D = window.SparrowDesktop;
const S = () => store.settings;
const plat = D.platform();
const html = document.documentElement;
html.classList.add('desktop', 'island-mode', 'isl-collapsed', 'os-' + plat);

// ---------- build the island around the app ----------
const island = document.createElement('div'); island.id = 'island';
const body = document.createElement('div'); body.className = 'isl-body';
[...document.body.children].forEach(el => { if (el.tagName !== 'SCRIPT') body.appendChild(el); });
const cap = document.createElement('button'); cap.className = 'cap'; cap.setAttribute('aria-label', 'Open Zuffi');
cap.innerHTML = `<span class="cap-bird"><i class="cap-face"></i></span>
  <span class="cap-txt"><b id="capT1">Zuffi</b><small id="capT2">Say “Zuffi…”</small></span>
  <span class="cap-wave" aria-hidden="true"><i></i><i></i><i></i><i></i></span>`;
const glow = document.createElement('div'); glow.className = 'isl-glow';
island.append(glow, cap, body);
document.body.prepend(island);
['l', 'r'].forEach(x => { const e = document.createElement('i'); e.className = 'isl-ear ' + x; document.body.appendChild(e); });

// collapse button in the header
const top = body.querySelector('.top');
const shrink = document.createElement('button');
shrink.className = 'icon-btn isl-shrink'; shrink.setAttribute('aria-label', 'Close'); shrink.title = 'Close (Esc)';
shrink.innerHTML = '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M6 15l6-6 6 6"/></svg>';
top.appendChild(shrink);
// Business dashboard button in the header (opens the big window)
const bizBtn = document.createElement('button');
bizBtn.className = 'icon-btn isl-biz'; bizBtn.title = 'Business dashboard'; bizBtn.setAttribute('aria-label', 'Business dashboard');
bizBtn.innerHTML = '<svg viewBox="0 0 24 24" width="19" height="19" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="7" width="18" height="13" rx="3"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 13h18"/></svg>';
bizBtn.onclick = () => D.openBusiness?.();
top.insertBefore(bizBtn, shrink);

// ---------- open apps row (Windows): your open windows — click one to jump to it ----------
const appsRow = document.createElement('div'); appsRow.className = 'isl-apps'; appsRow.hidden = true;
top.after(appsRow);
let appsT = null;
async function refreshApps() {
  if (!D.openWindows || state !== 'expanded') return;
  const list = await D.openWindows().catch(() => []);
  appsRow.hidden = !list.length;
  appsRow.innerHTML = list.map(w => `<button data-pid="${w.pid}" title="${(w.name + ' · ' + w.title).replace(/"/g, '&quot;')}">${w.icon ? `<img src="${w.icon}" alt="">` : '<span>🪟</span>'}<em>${(w.name || '').replace(/</g, '&lt;').slice(0, 14)}</em></button>`).join('');
}
appsRow.onclick = e => { const b = e.target.closest('[data-pid]'); if (b) { b.classList.add('go'); D.focusWindow(b.dataset.pid); setTimeout(() => b.classList.remove('go'), 600); } };

// ---------- Mac-style home: what the island shows when it drops open ----------
// Same layout as the Mac notch: your open apps on top, Zuffi in the middle (her head follows the mouse),
// four buttons on each side, and Mic · Chat · Business · Talk along the bottom.
const I = {
  chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
  more: '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
  pet: '<path d="M9 3c-1 0-1.5 2-1.5 4.5S8 11 8 11M15 3c1 0 1.5 2 1.5 4.5S16 11 16 11"/><circle cx="12" cy="15" r="6"/><path d="M10 15h.01M14 15h.01"/>',
  today: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
  call: '<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1 1 .4 1.9.7 2.8a2 2 0 0 1-.5 2.1L8 9.9a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.8.7a2 2 0 0 1 1.7 2z"/>',
  whatsapp: '<path d="M3 21l1.7-5A8.5 8.5 0 1 1 8 19.3z"/><path d="M9 9.5c0 3 2.5 5.5 5.5 5.5l1.2-1.2-1.8-1-1 .7a4 4 0 0 1-2.4-2.4l.7-1-1-1.8z"/>',
  notes: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6M8 13h8M8 17h5"/>',
  mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
  micoff: '<path d="M3 3l18 18M9 9v2a3 3 0 0 0 5.1 2.1M15 10V6a3 3 0 0 0-5.7-1.3M19 11a7 7 0 0 1-1.2 3.9M5 11a7 7 0 0 0 10.4 6.1M12 18v3"/>',
  biz: '<rect x="3" y="7" width="18" height="13" rx="3"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 13h18"/>',
  wave: '<path d="M4 10v4M8 7v10M12 4v16M16 7v10M20 10v4"/>',
  home: '<path d="M15 18l-6-6 6-6"/>',
};
const ico = (n, sz = 15) => `<svg viewBox="0 0 24 24" width="${sz}" height="${sz}" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${I[n]}</svg>`;
const HOME_BTNS = {
  chat: ['Chat', 'chat', '#F58FA8'], settings: ['Settings', 'settings', '#A9B2C6'], more: ['More', 'more', '#F7C948'], pet: ['Zuffi on screen', 'pet', '#FFB7C5'],
  today: ['Today', 'today', '#FBC56A'], call: ['Who to call today', 'call', '#34D399'], whatsapp: ['WhatsApp', 'whatsapp', '#34D399'], notes: ['My notes', 'notes', '#FDE68A'],
};
const LEFT = ['chat', 'settings', 'more', 'pet'], RIGHT = ['today', 'call', 'whatsapp', 'notes'];
const hbtn = (id, round) => { const [label, icon, tint] = HOME_BTNS[id]; return `<button class="nh-b ${round ? 'round' : 'cap2'}" data-h="${id}" title="${label}" aria-label="${label}" style="--t:${tint}">${ico(icon, 14)}</button>`; };
const nhome = document.createElement('div'); nhome.className = 'nhome';
nhome.innerHTML = `<div class="nh-apps"><span class="nh-zuffi">Zuffi</span></div>
  <div class="nh-mid"><div class="nh-col">${LEFT.map(id => hbtn(id, true)).join('')}</div>
    <div class="nh-c"><div class="nh-head"></div><p class="nh-words"></p></div>
    <div class="nh-col">${RIGHT.map(id => hbtn(id, false)).join('')}</div></div>
  <div class="nh-bot"><button class="nh-pill" data-h="mic" title="Turn the microphone on or off">${ico('mic', 13)}<span>Mic</span></button>
    <button class="nh-pill" data-h="chat">${ico('chat', 13)}<span>Chat</span></button>
    <button class="nh-pill biz" data-h="business" title="Your leads, money, team and automations">${ico('biz', 13)}<span>Business</span></button>
    <button class="nh-talk" data-h="talk" title="Talk to Zuffi" aria-label="Talk to Zuffi">${ico('wave', 14)}</button></div>
  <div class="nh-tip" hidden></div>`;
island.insertBefore(nhome, body);
const nhApps = nhome.querySelector('.nh-apps'), nhWords = nhome.querySelector('.nh-words'), nhTip = nhome.querySelector('.nh-tip');
const head = mountMascot(nhome.querySelector('.nh-head'), { onTap: () => Voice.toggle() });
let wordsHold = 0;
function setWords(t, hold = 0) { nhWords.textContent = t; if (hold) wordsHold = Date.now() + hold; }
function homeWords() {
  if (Date.now() < wordsHold || html.classList.contains('isl-listening')) return;
  const now = Date.now();
  const next = store.items.filter(i => i.when && !i.done && ['task', 'meeting', 'reminder'].includes(i.type) && new Date(i.when).getTime() > now)
    .sort((a, b) => new Date(a.when) - new Date(b.when))[0];
  const nm = S().name ? ' ' + S().name : '';
  setWords(next ? `Next: ${next.title} · ${fmtTime(next.when)}` : Voice.wakeOn ? `Hi${nm}! Say “Zuffi…” or click me` : `Hi${nm}! Click me or the mic to talk`);
}
function micLabel() { const b = nhome.querySelector('[data-h="mic"]'); const on = Voice.wakeOn; b.classList.toggle('off', !on); b.innerHTML = `${ico(on ? 'mic' : 'micoff', 13)}<span>${on ? 'Mic' : 'Off'}</span>`; }
/** Show one of the app's pages (chat, plan, settings…) in the big island. */
function openFull(view) {
  html.classList.add('isl-full');
  if (state !== 'expanded') setState('expanded');
  const b = document.querySelector(`nav.tabs button[data-v="${view}"]`); if (b) b.click();
  setTimeout(() => document.querySelector('#askInput')?.focus({ preventScroll: true }), 380);
}
const backHome = () => { html.classList.remove('isl-full'); homeWords(); };
nhome.addEventListener('click', e => {
  const b = e.target.closest('[data-h]'); if (!b) return;
  const h = b.dataset.h;
  if (h === 'chat') openFull('chat');
  else if (h === 'settings') { openFull('home'); setTimeout(() => document.querySelector('#settingsBtn')?.click(), 60); }
  else if (h === 'more') openFull('tools');
  else if (h === 'today') openFull('plan');
  else if (h === 'notes') { openFull('tools'); setTimeout(() => document.querySelector('[data-goto2="memory"]')?.click(), 60); }
  else if (h === 'call') D.openBusiness?.('today');
  else if (h === 'business') D.openBusiness?.();
  else if (h === 'whatsapp') { const ok = D.openApp?.('WhatsApp'); setWords(ok === false ? 'I couldn’t find WhatsApp on this computer — install WhatsApp from the Microsoft Store.' : 'Opening WhatsApp…', 4000); }
  else if (h === 'pet') D.getSettings().then(s => { const on = s.pet === false; D.setSetting('pet', on); setWords(on ? 'I’ll walk along the bottom of your screen 🐰' : 'Okay — I’ll stay up here.', 3500); head.react(on ? 'delighted' : 'bashful', 900); });
  else if (h === 'mic') { Voice.wakeOn ? Voice.stopWake() : Voice.startWake(); setTimeout(micLabel, 300); setWords(Voice.wakeOn ? 'Mic off — click Mic to turn it back on' : 'Listening for “Zuffi…”', 3000); }
  else if (h === 'talk') Voice.toggle();
});
nhome.addEventListener('mouseover', e => { const b = e.target.closest('[title]'); if (b && nhome.contains(b)) { nhTip.textContent = b.title; nhTip.hidden = false; } });
nhome.addEventListener('mouseout', e => { const b = e.target.closest('[title]'); if (b && !b.contains(e.relatedTarget)) nhTip.hidden = true; });
// pop-up messages on the home show as Zuffi's words instead of covering them
const toastEl = document.querySelector('#toast');
if (toastEl) new MutationObserver(() => { if (state !== 'expanded' || html.classList.contains('isl-full') || toastEl.hidden || !toastEl.textContent.trim()) return;
  setWords(toastEl.textContent.trim().slice(0, 160), 8000); head.react('surprised', 700); })
  .observe(toastEl, { childList: true, characterData: true, subtree: true, attributes: true, attributeFilter: ['hidden'] });
// a reply or alert while the island is open shows in Zuffi's words
document.addEventListener('zuffi-said', e => { setWords(String(e.detail || '').slice(0, 160), 20000); head.react('delighted', 700); });
async function homeApps() {
  if (!D.openWindows || state !== 'expanded' || html.classList.contains('isl-full')) return;
  const list = (await D.openWindows().catch(() => [])).slice(0, 7);
  if (!list.length) { nhApps.innerHTML = '<span class="nh-zuffi">Zuffi</span>'; return; }
  nhApps.innerHTML = list.map((w, i) => `<button data-pid="${w.pid}" class="${i === 0 ? 'cur' : ''}" title="${(w.name + (w.title ? ' · ' + w.title : '')).replace(/"/g, '&quot;')}">${w.icon ? `<img src="${w.icon}" alt="">` : '<span class="nh-dot"></span>'}${i === 0 ? `<em>${(w.name || '').replace(/</g, '&lt;').slice(0, 16)}</em>` : ''}</button>`).join('');
}
nhApps.onclick = e => { const b = e.target.closest('[data-pid]'); if (b) D.focusWindow(b.dataset.pid); };
setInterval(() => { if (state === 'expanded') { homeApps(); micLabel(); } }, 5000);
// back-to-home button in the big island's header
const homeBtn = document.createElement('button');
homeBtn.className = 'icon-btn isl-home'; homeBtn.title = 'Back'; homeBtn.setAttribute('aria-label', 'Back to Zuffi');
homeBtn.innerHTML = ico('home', 20); homeBtn.onclick = backHome;
top.prepend(homeBtn);

// ---------- states: collapsed · peek · expanded ----------
let state = 'collapsed', peekTimer = null;
function setState(s) {
  state = s;
  if (s !== 'expanded') html.classList.remove('isl-full');
  html.classList.toggle('isl-collapsed', s === 'collapsed');
  html.classList.toggle('isl-peek', s === 'peek');
  html.classList.toggle('isl-expanded', s === 'expanded');
  D.islandState(s === 'expanded' ? 'expanded' : 'collapsed');
  if (s === 'expanded' && html.classList.contains('isl-full')) setTimeout(() => document.querySelector('#askInput')?.focus({ preventScroll: true }), 380);
  if (s === 'expanded') homeWords();
  clearInterval(appsT);
  if (s === 'expanded' && plat === 'windows') { refreshApps(); appsT = setInterval(refreshApps, 6000); }
  if (s !== 'peek') clearTimeout(peekTimer);
  mouseInside(s === 'expanded');
}
const expand = () => { setState('expanded'); homeApps(); micLabel(); };
const collapse = () => { if (document.querySelector('.sheet:not([hidden])')) document.querySelector('#sheetBg')?.click(); setState('collapsed'); pushCap(); };
/** Show a short message in the island (alerts, voice replies), then shrink back. */
let typeT = null;
function peek(t1, t2 = '', ms = 6000) {
  if (state === 'expanded') return;
  capText(t1, t2); setState('peek');
  // "WhatsApp · Sana" style lines sit on top in green; the message types itself in, like the Mac notch
  const sm = cap.querySelector('#capT2'), b = cap.querySelector('#capT1');
  sm.classList.toggle('from', / · /.test(t2) && t2.length < 60);
  clearInterval(typeT);
  if (t1.length < 140 && !matchMedia('(prefers-reduced-motion: reduce)').matches) { let n = 0; b.textContent = ''; typeT = setInterval(() => { b.textContent = t1.slice(0, ++n); if (n >= t1.length) clearInterval(typeT); }, 16); }
  clearTimeout(peekTimer); peekTimer = setTimeout(() => { if (state === 'peek') { setState('collapsed'); pushCap(); } }, ms);
}
cap.onclick = expand;
shrink.onclick = collapse;
document.addEventListener('keydown', e => { if (e.key === 'Escape' && state === 'expanded' && document.querySelector('#focus').hidden) { e.stopPropagation(); collapse(); } }, true);
D.onIsland(v => {
  if (v === 'expand') expand();
  else if (v === 'collapse') collapse();
  else if (v === 'hide-cap') html.classList.add('cap-hidden');
  else if (v === 'show-cap') html.classList.remove('cap-hidden');
  else if (v.startsWith('pos:')) setPos(v.slice(4));
});
D.getSettings().then(s => { if (s.pill === false) html.classList.add('cap-hidden'); if (s.notch) html.classList.add('has-notch'); });

function setPos(p) { html.classList.remove('pos-right', 'pos-left', 'pos-center'); html.classList.add('pos-' + p); }
setPos('center');

// Only the island catches the mouse — the rest of the window clicks through to your apps.
let inside = null;
function mouseInside(v) { if (v !== inside) { inside = v; D.mouseInside(v); } }
document.addEventListener('mousemove', e => {
  const r = island.getBoundingClientRect();
  const over = e.clientX >= r.left && e.clientX <= r.right && e.clientY >= r.top && e.clientY <= r.bottom + 4;
  mouseInside(over || state === 'expanded' && !!document.querySelector('.sheet:not([hidden]), #focus:not([hidden])'));
  html.classList.toggle('cap-hover', over && state === 'collapsed');
});
document.addEventListener('mouseleave', () => { if (state !== 'expanded') mouseInside(false); html.classList.remove('cap-hover'); });

// ---------- capsule text ----------
function capText(t1, t2) { cap.querySelector('#capT1').textContent = t1; cap.querySelector('#capT2').textContent = t2; if (/Listening/.test(t1)) setWords(t2 && t2 !== 'Go ahead' ? `“${t2}”` : 'I’m listening…'); }
function pushCap() {
  if (state === 'peek' || Voice.mode === 'command') return;
  const now = Date.now();
  const next = store.items.filter(i => i.when && !i.done && ['task', 'meeting', 'reminder'].includes(i.type) && new Date(i.when).getTime() > now)
    .sort((a, b) => new Date(a.when) - new Date(b.when))[0];
  const left = tasksForDay(new Date()).length;
  capText(`${greetingWord()}${S().name ? ', ' + S().name : ''}`,
    next ? `${next.title} · ${fmtTime(next.when)}` : left ? `${left} task${left > 1 ? 's' : ''} today` : (Voice.wakeOn ? 'Say “Zuffi…”' : 'All clear today'));
}
store.onChange(pushCap); setInterval(pushCap, 60000); setTimeout(pushCap, 300);

// hooks used by app.js
window.SparrowIsland = {
  peek, expand, collapse, get state() { return state; },
  /** AI usage line on the open notch: "Built-in AI: 12 of 300 · 288 left". */
  usage(lines) { let el = nhome.querySelector('.nh-usage'); if (!el) { el = document.createElement('div'); el.className = 'nh-usage'; nhome.appendChild(el); } el.textContent = (lines || [])[0] || ''; el.hidden = !el.textContent; },
  /** A reply to something said while the island was closed: short ones peek, long ones open the island. */
  reply(text, isCommand) {
    if (state === 'expanded') { if (!html.classList.contains('isl-full')) setWords(text.slice(0, 160), 20000); return; }
    if (isCommand || text.length < 90) peek(text.split('\n')[0].slice(0, 80), isCommand ? '' : 'Tap to see more', isCommand ? 4000 : 7000);
    else expand();
  },
};

// What's next (the walking bunny asks this when you tap her)
window.zuffiNext = () => {
  const now = Date.now();
  const next = store.items.filter(i => i.when && !i.done && ['task', 'meeting', 'reminder'].includes(i.type) && new Date(i.when).getTime() > now)
    .sort((a, b) => new Date(a.when) - new Date(b.when))[0];
  return next ? `Next: ${next.title} · ${fmtTime(next.when)}` : '';
};

// ---------- settings: this computer ----------
const sec = document.createElement('details');
sec.innerHTML = `<summary>💻 This ${plat === 'mac' ? 'Mac' : 'computer'}</summary>
  <label class="row"><input type="checkbox" id="dLogin"> 🚀 Start Zuffi when I log in</label>
  <label class="row"><input type="checkbox" id="dPill"> 🐰 Show the island at the top when Zuffi is closed</label>
  <label class="row"><input type="checkbox" id="dClip"> 📎 Keep a clipboard history (on this computer only)</label>
  <label class="row"><input type="checkbox" id="dPet"> 🐰 Zuffi walks along the bottom of my screen (shows reminders)</label>
  <label class="row"><input type="checkbox" id="dCharge"> ⚡ Charging light round the screen when I plug in (laptops)</label>
  <label class="row"><input type="checkbox" id="dAwake"> 🔌 Keep Zuffi working while charging (the screen can still turn off)</label>
  <label class="row"><input type="checkbox" id="dLid"> 💼 Keep working with the lid closed — only while plugged in</label>
  <p class="small-text">Don't leave a closed, plugged-in laptop inside a bag for long — it can get hot. On battery it still goes to sleep.</p>
  <label class="field"><span>Where Zuffi lives</span><select id="dPos"><option value="right">Top right corner</option><option value="center">Top centre (notch)</option><option value="left">Top left corner</option></select></label>
  <p class="small-text">Open Zuffi: click the island, press <b>${plat === 'mac' ? '⌘' : 'Ctrl'} + Shift + Space</b>, or just say “Zuffi…”. Close: <b>Esc</b> or click anywhere else.</p>
  <p class="small-text" id="dNote"></p>`;
body.querySelector('#desktopSection').appendChild(sec);
const dLogin = sec.querySelector('#dLogin'), dPill = sec.querySelector('#dPill'), dClip = sec.querySelector('#dClip');
const dPos = sec.querySelector('#dPos');
const dPet = sec.querySelector('#dPet'), dCharge = sec.querySelector('#dCharge');
D.getSettings().then(s => { dLogin.checked = s.login; dPill.checked = s.pill !== false; dClip.checked = s.clipboard !== false; dPos.value = s.position || 'center'; setPos(s.position || 'center');
  dPet.checked = s.pet !== false; dCharge.checked = s.chargeLight !== false; });
dPet.onchange = () => D.setSetting('pet', dPet.checked);
dCharge.onchange = () => D.setSetting('chargeLight', dCharge.checked);
const dAwake = sec.querySelector('#dAwake'), dLid = sec.querySelector('#dLid');
D.getSettings().then(s => { dAwake.checked = !!s.awakeCharging; dLid.checked = !!s.lidCharging; });
dAwake.onchange = () => D.setSetting('awakeCharging', dAwake.checked);
dLid.onchange = () => D.setSetting('lidCharging', dLid.checked);
dPos.onchange = () => D.setSetting('position', dPos.value);
dLogin.onchange = () => D.setSetting('login', dLogin.checked);
dPill.onchange = () => D.setSetting('pill', dPill.checked);
dClip.onchange = () => D.setSetting('clipboard', dClip.checked);

// ---------- folder watcher ----------
D.onEvent(ev => {
  if (ev.type === 'toast') { window.sparrowEvent?.({ type: 'toast', text: ev.text }); peek(ev.text.slice(0, 80), '', 6000); return; }
  if (ev.type === 'pet-action') {
    // Done / Snooze tapped on the bunny's card
    const btn = document.querySelector(ev.action === 'done' ? '#alertDone' : '#alertSnooze');
    if (btn) { btn.dataset.id = ev.id || ''; btn.click(); }
    return;
  }
  if (ev.type === 'file-arrived') {
    mem.remember('file', ev.name, '', { folder: ev.folder, path: ev.path });
    peek(`📥 ${ev.name}`, `New file in ${ev.folder}`);
    if (S().speak) window.Sparrow?.speak(`New file in ${ev.folder}: ${ev.name.replace(/\.[^.]+$/, '')}`);
  }
});

// ---------- recent files into memory (optional) ----------
async function rememberRecent() {
  if (!S().memory?.recentFiles) return;
  const seen = new Set(JSON.parse(localStorage.getItem('sparrow.recentSeen') || '[]'));
  for (const f of await D.recentFiles(1)) {
    const key = f.path + '|' + Math.round(f.mtime / 3600e3);
    if (seen.has(key)) continue;
    seen.add(key); mem.remember('opened', f.name, '', { path: f.path, recent: true });
  }
  try { localStorage.setItem('sparrow.recentSeen', JSON.stringify([...seen].slice(-500))); } catch {}
}
setInterval(rememberRecent, 15 * 60000); setTimeout(rememberRecent, 20000);

// ---------- voice: offline speech recognition (Vosk) ----------
const send = e => window.sparrowEvent && window.sparrowEvent(e);
// Things the recogniser "hears" in background noise — never treat these as a command.
const JUNK = /^(i|a|the|uh|um|umm|hm+|huh|oh|ah|eh|and|so|it|is|you|to|in|of|on|at|but|that|this|yeah|hey|hmm|mm|her|his|he|she|we|they|one|be|or|if|an)$/;
function meaningful(text, words) {
  const t = text.trim();
  if (t.length < 3 || JUNK.test(t)) return false;
  const w = t.split(/\s+/);
  if (w.length === 1 && w[0].length < 4 && !/^(yes|no|stop|play|next|mute)$/.test(w[0])) return false;
  if (words?.length) { const avg = words.reduce((n, x) => n + (x.conf ?? 1), 0) / words.length; if (avg < 0.62) return false; }
  return true;
}
const Voice = {
  model: null, rec: null, ctx: null, node: null, stream: null, loading: null,
  mode: 'off',          // 'off' | 'wake' | 'command' | 'dictate'
  cmdTimer: null, wakeOn: false, dictateCb: null,

  async load() {
    if (this.model) return this.model;
    if (this.loading) return this.loading;
    this.loading = (async () => {
      if (!window.Vosk) await new Promise((res, rej) => { const s = document.createElement('script'); s.src = 'lib/vosk.js'; s.onload = res; s.onerror = rej; document.head.appendChild(s); });
      this.model = await window.Vosk.createModel(await D.modelUrl());
      return this.model;
    })();
    return this.loading;
  },
  native: false,
  /** On a Mac, Apple's own speech engine (much better than the built-in fallback). */
  nativeReady() {
    if (this.native) return true;
    const nvx = D.nativeVoice;
    if (!nvx || !nvx.available()) return false;
    this.native = true;
    nvx.on(ev => {
      if (ev.ev === 'partial') this.onText(ev.text, false);
      else if (ev.ev === 'final') this.onText(ev.text, true);
      else if (ev.ev === 'speaking') send({ type: 'speaking', on: ev.on });
      else if (ev.ev === 'auth' && !(ev.speech && ev.mic)) sec.querySelector('#dNote').textContent = 'Zuffi needs Microphone and Speech Recognition: System Settings → Privacy & Security → Microphone / Speech Recognition → turn on Zuffi.';
      else if (ev.ev === 'voices') this.voiceList = ev;
    });
    nvx.send({ cmd: 'voices' });
    return true;
  },
  nativeSay(text) {
    if (!this.nativeReady()) return false;
    const rate = S().simple ? 0.44 : 0.5;
    return D.nativeVoice.send({ cmd: 'say', text, gender: S().gender || 'female', rate });
  },
  async ensureMic() {
    if (this.nativeReady()) { if (!this.nativeOn) { const ctx = [...new Set([...(S().quick || []).map(q => q.n), ...store.ofType('customer').map(c => c.title), 'Gmail', 'Spotify', 'WhatsApp'])]; D.nativeVoice.send({ cmd: 'listen', context: ctx }); this.nativeOn = true; } this.ctx = { state: 'running' }; return; }
    if (this.stream) return;
    await this.load();
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 } });
    this.ctx = new AudioContext();
    this.rec = new this.model.KaldiRecognizer(this.ctx.sampleRate);
    try { this.rec.setWords(true); } catch {}
    this.rec.on('result', m => this.onText(m.result.text, true, m.result.result));
    this.rec.on('partialresult', m => this.onText(m.result.partial, false));
    this.node = this.ctx.createScriptProcessor(4096, 1, 1);
    this.node.onaudioprocess = ev => {
      if (this.mode === 'off' || (this.mode !== 'dictate' && window.speechSynthesis?.speaking)) return;   // don't hear ourselves
      try { this.rec.acceptWaveform(ev.inputBuffer); } catch {}
    };
    const src = this.ctx.createMediaStreamSource(this.stream);
    src.connect(this.node); this.node.connect(this.ctx.destination);
  },
  onText(text, final, words) {
    text = (text || '').replace(/\[unk\]/g, '').trim().toLowerCase().replace(/[.,!?]+$/, '');
    if (this.mode === 'dictate') { if (text) this.dictateCb?.(text, final); return; }
    if (!text) return;
    const wake = /^(hey |ok |okay )?(zuffi|zuffy|zoffee|sophie|zoofi|sparrow|spar row|sparo|sparrows|sparrow's)\b/;
    if (this.mode === 'wake') {
      // the wake word can come anywhere: "…hey Sparrow, open Gmail"
      const m = text.match(/\b(?:hey |ok |okay )?(zuffi|zuffy|zoffee|zoofi|sophie|sparrow's|sparrows|sparrow|sparro|sparo|spar row)\b[,\s]*(.*)$/);
      if (!m) return;
      const rest = m[2].trim();
      if (!final) { capText('Listening…', rest || 'Go ahead'); return; }
      if (meaningful(rest, words?.slice(1))) { this.finish(rest); return; }
      try { const u = new SpeechSynthesisUtterance('Yes?'); u.rate = 1.05; speechSynthesis.cancel(); speechSynthesis.speak(u); } catch {}   // like the Mac: a short "Yes?"
      setTimeout(() => this.startCommand(), 450);
      return;
    }
    if (this.mode === 'command') {
      const tx = text.replace(wake, '').trim();
      if (!final) { send({ type: 'partial', text: tx }); capText('Listening…', tx || 'Go ahead'); clearTimeout(this.cmdTimer); this.cmdTimer = setTimeout(() => this.endCommand(), 6000); return; }
      if (meaningful(tx, words)) this.finish(tx);   // noise like "i" is ignored — keep listening until the timeout
    }
  },
  async startCommand() {
    try { await this.ensureMic(); if (this.ctx.state === 'suspended') await this.ctx.resume(); } catch { return; }
    this.mode = 'command';
    html.classList.add('isl-listening'); capText('Listening…', 'Go ahead');
    if (state === 'collapsed') setState('peek');
    send({ type: 'listening', on: true });
    clearTimeout(this.cmdTimer); this.cmdTimer = setTimeout(() => this.endCommand(), 6000);
  },
  endCommand() {
    clearTimeout(this.cmdTimer);
    if (this.native && !this.wakeOn && this.mode !== 'dictate') { D.nativeVoice.send({ cmd: 'stop' }); this.nativeOn = false; }
    html.classList.remove('isl-listening');
    send({ type: 'listening', on: false });
    this.mode = this.wakeOn ? 'wake' : 'off';
    if (state === 'peek') { setState('collapsed'); }
    pushCap();
  },
  finish(text) {
    this.endCommand(); send({ type: 'partial', text: '' });
    capText('🐰 ' + text.slice(0, 60), 'On it…'); if (state !== 'expanded') setState('peek');
    send({ type: 'speech', text });
  },
  /** Mic button / tap: take one command, no wake word needed. */
  async toggle() {
    try {
      if (this.mode === 'command') { this.endCommand(); return; }
      if (!this.model) send({ type: 'toast', text: 'Getting voice ready… (first time only)' });
      await this.startCommand();
    } catch (e) { send({ type: 'toast', text: 'Microphone not available: ' + (e.message || e) }); }
  },
  async startWake() {
    try {
      this.wakeOn = true; await this.ensureMic();
      if (this.mode === 'off') this.mode = 'wake';
      sec.querySelector('#dNote').textContent = this.native ? 'Listening for “Zuffi…” with your Mac’s own speech recognition.' : 'Listening for “Zuffi…” — understood on this computer, never uploaded.';
      pushCap();
    } catch (e) {
      this.wakeOn = false;
      sec.querySelector('#dNote').textContent = `Couldn't use the microphone: ${e.message || e}. ${plat === 'mac' ? 'Allow it in System Settings → Privacy & Security → Microphone.' : 'Allow it in Settings → Privacy → Microphone.'}`;
    }
  },
  stopWake() { this.wakeOn = false; if (this.mode === 'wake') this.mode = 'off'; if (this.native) { D.nativeVoice.send({ cmd: 'stop' }); this.nativeOn = false; } pushCap(); },
  /** Meeting notes: every word goes to cb(text, isFinal) until the returned stop() is called. */
  dictate(cb) {
    this.dictateCb = cb;
    this.ensureMic().then(() => { if (this.ctx.state === 'suspended') this.ctx.resume(); this.mode = 'dictate'; })
      .catch(e => cb(`(microphone not available: ${e.message || e})`, true));
    return () => { this.dictateCb = null; this.mode = this.wakeOn ? 'wake' : 'off'; if (this.native && !this.wakeOn) { D.nativeVoice.send({ cmd: 'stop' }); this.nativeOn = false; } };
  },
};
window.SparrowVoice = Voice;
if (S().wake !== false) setTimeout(() => Voice.startWake(), 2500);
D.onCommand(cmd => {
  if (cmd === 'listen') Voice.toggle();
  else if (typeof cmd === 'string' && cmd.startsWith('ask:')) send({ type: 'speech', text: cmd.slice(4) });   // typed in the Business window
});
