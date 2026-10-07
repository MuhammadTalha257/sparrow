import { store, DEFAULT_SETTINGS } from './store.js';
import { t, applyI18n, LANGS, SPEECH_LANG } from './i18n.js';
import { METHODS, NAMES as PRAYERS, prayerTimes, refreshOnline } from './prayer.js';
import * as mem from './memory.js';
import * as tools from './tools.js';
import * as sync from './sync.js';
import {
  handle, briefing, daySummary, whenText, fmtTime, fmtDay, greetingWord, getQuick, AI_APPS, icsFor, googleCalUrl, prayerICS, isIOS, isAndroid,
  spokenPlan, spokenList, tasksForDay, moveToTomorrow, nextOccurrence, repeatText, weather, location as getLocation, prayerToday, habitCount, bumpHabit,
  setLastAlert, lastAlert, findCustomer,
} from './brain.js';
import { ask, loadLocal, deviceSupport, aiReady, PROVIDERS, ollamaModels } from './ai.js';
import * as nv from './neuralvoice.js';
import * as jobs from './jobs.js';
import { mountMascot as mountBird } from './mascot.js';
import * as maclink from './maclink.js';
import { liveUsable, startLive, stopLive, liveActive, liveSendImage, cameraShot } from './live.js';

const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ICON = { task: '✅', meeting: '🗓️', reminder: '⏰', note: '📝', habit: '💧', customer: '👤', expense: '💸', quote: '🧾', invoice: '🧾', timer: '⏱️',
  file: '📄', chat: '💬', done: '✔️', opened: '↗️', 'meeting-notes': '🎤', email: '📧', report: '📊' };
const N = window.SparrowNative || null;     // Android app
const D = window.SparrowDesktop || null;    // Windows app
const M = window.SparrowHost === 'mac' ? window.SparrowMac : null;   // inside the native Mac island app
const S = () => store.settings;
const dayKey = () => new Date().toDateString();
if (N) document.documentElement.classList.add('android-app');
if (D) document.documentElement.classList.add('desktop');
if (M) document.documentElement.classList.add('mac-host');
// On the Mac the panel is dragged by its top bar (grab handle + greeting area).
if (M) document.addEventListener('pointerdown', e => {
  if (e.button !== 0 || !e.target.closest('.top, .grab') || e.target.closest('button, input, select, textarea, a')) return;
  M.post('dragWindow');
});

// ---------------- look: theme, language, simple mode ----------------
function applyLook() {
  const html = document.documentElement;
  html.dataset.theme = S().theme || 'daylight';
  html.classList.toggle('simple', !!S().simple);
  html.classList.toggle('no-mic', S().micButton === false);
  applyI18n();
  const bg = getComputedStyle(html).getPropertyValue('--bg').trim();
  $('meta[name=theme-color]')?.setAttribute('content', bg || '#EEF4FB');
}

// ---------------- navigation ----------------
let planType = 'task';
function go(v) {
  $$('.view').forEach(x => x.classList.toggle('active', x.id === 'view-' + v));
  $$('.tabs button').forEach(b => b.classList.toggle('on', b.dataset.v === v));
  if (v === 'chat') setTimeout(() => window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' }), 50);
  else window.scrollTo({ top: 0 });
  if (v === 'memory') renderMemory();
}
$$('.tabs button').forEach(b => b.onclick = () => go(b.dataset.v));
$$('[data-goto]').forEach(b => b.onclick = () => go(b.dataset.goto));
$$('#seg button').forEach(b => b.onclick = () => { planType = b.dataset.t; $$('#seg button').forEach(x => x.classList.toggle('on', x === b)); renderPlan(); });

// ---------------- header ----------------
function renderHeader() {
  $('#hello').textContent = `${greetingWord()}${S().name ? ', ' + S().name : ''}`;
  $('#todayLabel').textContent = new Date().toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' });
}

// ---------------- lists ----------------
function itemSub(i) {
  if (i.type === 'note') return new Date(i.created).toLocaleDateString([], { day: 'numeric', month: 'short' });
  if (i.type === 'customer') return [i.phone, i.email].filter(Boolean).join(' · ') || 'Customer';
  if (i.type === 'expense') return `${S().business.currency}${(+i.amount).toFixed(2)} · ${new Date(i.created).toLocaleDateString([], { day: 'numeric', month: 'short' })}`;
  if (i.type === 'quote' || i.type === 'invoice') return `${S().business.currency}${(+i.total || 0).toFixed(2)} · ${new Date(i.created).toLocaleDateString([], { day: 'numeric', month: 'short' })}`;
  if (i.type === 'habit') return `${habitCount(i)}/${i.target} today${i.every ? ` · every ${i.every} h` : ''}`;
  return (i.when ? whenText(i.when) : 'No date') + (i.repeat ? ` · 🔁 ${repeatText(i.repeat)}` : '');
}
function itemRow(i) {
  const lead = i.type === 'task' ? `<button class="check" data-act="toggle" aria-label="Done">${i.done ? '✓' : ''}</button>`
    : i.type === 'habit' ? `<button class="check" data-act="bump" aria-label="Add one">＋</button>`
    : `<div class="ic">${ICON[i.type] || '•'}</div>`;
  const cal = i.when && ['meeting', 'reminder', 'task'].includes(i.type) ? `<button data-act="cal" title="Add to calendar" aria-label="Add to calendar">📅</button>` : '';
  const callBtn = i.type === 'customer' && i.phone ? `<button data-act="call" title="Call" aria-label="Call">📞</button>` : '';
  return `<div class="item ${i.done ? 'done' : ''}" data-id="${i.id}">
    ${lead}<div class="txt"><div class="t1">${esc(i.title)}</div><div class="t2">${esc(itemSub(i))}</div></div>
    <div class="acts">${callBtn}${cal}<button data-act="del" title="Delete" aria-label="Delete">🗑️</button></div></div>`;
}
function bindList(root) {
  root.addEventListener('click', e => {
    const b = e.target.closest('[data-act]'); if (!b) {
      const row = e.target.closest('.item'); const it = row && store.items.find(x => x.id === row.dataset.id);
      if (it?.type === 'customer') { go('memory'); $('#memSearch').value = it.title; renderMemory(); }
      return;
    }
    const id = b.closest('.item').dataset.id; const it = store.items.find(x => x.id === id); if (!it) return;
    if (b.dataset.act === 'toggle') {
      const nd = !it.done;
      if (nd && it.repeat && it.when) { store.update(id, { when: nextOccurrence(it.repeat, it.when).toISOString(), notified: false, soonDone: false }); mem.remember('done', it.title); }
      else store.update(id, { done: nd, doneAt: nd ? new Date().toISOString() : null });
      if (nd) { birdMood('happy'); chirp(); mem.remember('done', it.title); }
    }
    if (b.dataset.act === 'bump') { const c = bumpHabit(it); chirp(); if (c === it.target) toast(`🎉 ${it.title}: goal reached!`); }
    if (b.dataset.act === 'del') { store.remove(id); toast('Removed'); }
    if (b.dataset.act === 'cal') addToCalendar(it);
    if (b.dataset.act === 'call') openUrl('tel:' + it.phone.replace(/[^\d+]/g, ''));
  });
}
bindList($('#todayList')); bindList($('#planList'));

function renderToday() {
  renderNext(); renderProgress(); renderHabits();
  const day = store.onDay(new Date()).filter(i => !(i.type === 'reminder' && i.done));
  const undated = store.openTasks().filter(i => !i.when).slice(0, 4);
  const items = [...day, ...undated];
  $('#todayList').innerHTML = items.length ? items.map(itemRow).join('')
    : `<div class="empty">Nothing planned yet.<br>Try <b>"meeting with Ali Friday 3pm"</b> or <b>"remind me every day at 8pm to take medicine"</b>.</div>`;
}
function renderPlan() {
  let list;
  if (planType === 'money') {
    const ex = tools.monthExpenses(), total = ex.reduce((n, i) => n + (+i.amount || 0), 0);
    list = [...store.items.filter(i => ['invoice', 'quote', 'expense'].includes(i.type))].sort((a, b) => new Date(b.created) - new Date(a.created));
    $('#planList').innerHTML = `<div class="item"><div class="ic">📈</div><div class="txt"><div class="t1">This month's expenses</div><div class="t2">${S().business.currency}${total.toFixed(2)} · ${ex.length} item${ex.length === 1 ? '' : 's'}</div></div><div class="acts"><button data-tool-go="expenses" title="Export">⬇️</button></div></div>`
      + (list.map(itemRow).join('') || '');
    $('#planHint').textContent = 'Say "spent £12 on lunch", "quote for Ali, 3 hours at £40" or "invoice Ahmed, website £300".';
    $('#planList').querySelector('[data-tool-go]')?.addEventListener('click', () => { go('tools'); openTool('expenses'); });
    return;
  }
  list = store.ofType(planType);
  if (planType === 'task') list.sort((a, b) => a.done - b.done || (a.when ? new Date(a.when) : 9e15) - (b.when ? new Date(b.when) : 9e15));
  else if (['note', 'customer', 'habit'].includes(planType)) list.sort((a, b) => new Date(b.created) - new Date(a.created));
  else list.sort((a, b) => new Date(a.when) - new Date(b.when));
  const examples = {
    task: '"add task buy milk" or "I need to pay rent Friday"', meeting: '"meeting with Ali Friday 3pm" or "team meeting every Monday at 9"',
    reminder: '"remind me every day at 8pm to take medicine"', note: '"note wifi password is sparrow123"',
    habit: '"add habit drink water 8 times a day"', customer: '"add customer Ahmed Khan 07123 456789 ahmed@mail.com"',
  };
  $('#planList').innerHTML = list.length ? list.map(itemRow).join('') : `<div class="empty">Nothing here yet.<br>Say ${examples[planType]}</div>`;
  $('#planHint').textContent = ['reminder', 'meeting'].includes(planType) ? (isIOS ? 'iPhone tip: tap 📅 so your iPhone rings even when Zuffi is closed.' : 'Tap 📅 to add it to your calendar too.')
    : planType === 'customer' ? 'Tap a customer to see their whole history.' : '';
}
function renderNext() {
  const now = Date.now();
  const next = store.items.filter(i => i.when && !i.done && ['task', 'meeting', 'reminder'].includes(i.type) && new Date(i.when).getTime() > now)
    .sort((a, b) => new Date(a.when) - new Date(b.when))[0];
  const el = $('#upNext');
  if (!next) { el.hidden = true; return; }
  const mins = Math.round((new Date(next.when) - now) / 60000);
  const rel = mins < 60 ? `in ${mins} min` : mins < 24 * 60 ? `in ${Math.floor(mins / 60)} h${mins % 60 ? ' ' + (mins % 60) + ' min' : ''}` : fmtDay(next.when);
  el.hidden = false;
  el.innerHTML = `<div class="un-ic">${ICON[next.type]}</div><div class="txt"><div class="un-k">${t('upNext')}</div><div class="t1">${esc(next.title)}</div></div><div class="un-t">${esc(rel)}<br><small>${fmtTime(next.when)}</small></div>`;
}
function renderProgress() {
  const tdy = dayKey(), open = tasksForDay(new Date());
  const done = store.items.filter(i => i.type === 'task' && i.done && i.doneAt && new Date(i.doneAt).toDateString() === tdy).length;
  const total = open.length + done;
  $('#ring').style.setProperty('--p', total ? done / total : 0);
  $('#ringTxt').textContent = total ? `${done}/${total}` : '✓';
  $('#ringLbl').textContent = total ? (done === total ? t('allDone') : `${open.length} ${open.length === 1 && S().lang === 'en' ? 'task left today' : t('tasksLeft')}`) : t('noTasks');
}
function renderHabits() {
  const hs = store.ofType('habit'), el = $('#habitsCard');
  el.hidden = !hs.length;
  el.innerHTML = hs.slice(0, 4).map(h => { const c = habitCount(h); return `<div class="habit" data-id="${h.id}"><div class="hb-t">${esc(h.title)}</div><div class="hb-bar"><i style="width:${Math.min(100, c / h.target * 100)}%"></i></div><div class="hb-n">${c}/${h.target}</div><button aria-label="Add one">＋</button></div>`; }).join('');
}
$('#habitsCard').onclick = e => { const b = e.target.closest('button'); if (!b) return; const h = store.items.find(i => i.id === b.closest('.habit').dataset.id); if (h) { const c = bumpHabit(h); chirp(); if (c === h.target) toast(`🎉 ${h.title}: goal reached!`); } };
async function renderWeather() {
  const w = await weather().catch(() => null);
  if (!w) { $('#wTemp').textContent = '–°'; $('#wSky').textContent = 'Weather'; return; }
  $('#wTemp').textContent = `${w.temp}°`; $('#wSky').textContent = `${w.sky}${w.city ? ' · ' + w.city : ''}`;
}
async function renderPrayer() {
  const el = $('#prayerCard');
  if (!S().prayer.on) { el.hidden = true; return; }
  const p = await prayerToday().catch(() => null);
  if (!p) { el.hidden = false; el.innerHTML = `<div class="pr-head"><b>🕌 ${t('prayer')}</b><span>Allow location or set your city in Settings</span></div>`; return; }
  el.hidden = false;
  el.innerHTML = `<div class="pr-head"><b>🕌 ${t('nextPrayer')}: ${p.next ? p.next.name + ' · ' + fmtTime(p.next.at) : '—'}</b><span>${esc(p.loc.city || '')}</span></div>
    <div class="pr-row">${PRAYERS.map(n => `<div class="${p.next?.name === n && p.next.at.toDateString() === dayKey() ? 'next' : ''}">${n}<b>${fmtTime(p.times[n]).replace(/\s?[AP]M/i, '')}</b></div>`).join('')}</div>`;
}
function renderQuick() {
  const list = getQuick();
  $('#quick').innerHTML = list.map((q, i) => `<button class="q" data-i="${i}"><span>${q.e}</span>${esc(q.n)}</button>`).join('') + `<button class="q" data-add="1"><span>＋</span>Add</button>`;
  $('#quick').onclick = e => { const b = e.target.closest('.q'); if (!b) return; if (b.dataset.add) return addQuick(); openUrl(list[+b.dataset.i].url); };
  let pressT;
  $('#quick').onpointerdown = e => {
    const b = e.target.closest('.q[data-i]'); if (!b) return;
    pressT = setTimeout(() => { const q = list[+b.dataset.i]; if (confirm(`Remove "${q.n}" from your quick buttons?`)) { S().quick = list.filter((_, i) => i !== +b.dataset.i); store.save(); renderQuick(); } }, 650);
  };
  $('#quick').onpointerup = $('#quick').onpointerleave = () => clearTimeout(pressT);
  $('#aiApps').innerHTML = AI_APPS.map((a, i) => `<button data-i="${i}">${esc(a.n)}</button>`).join('');
  $('#aiApps').onclick = e => { const b = e.target.closest('button'); if (!b) return; const a = AI_APPS[+b.dataset.i]; if (a.app && (D || N)?.openApp(a.app)) return; openUrl(a.url); };
}
function addQuick() {
  const name = prompt(N || D ? 'Which app? Type its name (e.g. Netflix, Uber, Excel):' : 'Name of the app or website (e.g. Netflix, BBC News):'); if (!name) return;
  if (N || D) { const e = (prompt('Pick an emoji for the button:', '⭐') || '⭐').slice(0, 2); S().quick = [...getQuick(), { k: name.toLowerCase(), n: name, e, url: 'app:' + name }]; store.save(); renderQuick(); return; }
  let url = prompt(`Link for ${name} (e.g. netflix.com):`, name.toLowerCase().replace(/\s+/g, '') + '.com'); if (!url) return;
  if (!/^[a-z]+:/i.test(url)) url = 'https://' + url;
  const e = (prompt('Pick an emoji for the button:', '⭐') || '⭐').slice(0, 2);
  S().quick = [...getQuick(), { k: name.toLowerCase(), n: name, e, url }]; store.save(); renderQuick(); toast(`Added ${name}`);
}
function renderAll() { applyLook(); renderHeader(); renderToday(); renderPlan(); renderQuick(); renderChat(); renderWeather(); renderPrayer(); }
store.onChange(() => {
  renderToday(); renderPlan(); syncAlarms();
  $('#brief').textContent = `${greetingWord()}${S().name ? ', ' + S().name : ''}! ${daySummary(new Date(), true)}`;
});

// ---------------- calendar ----------------
function addToCalendar(it) {
  if (N) { const start = new Date(it.when).getTime(); N.addToCalendar(it.title, start, start + (it.type === 'meeting' ? 60 : 15) * 60000); return; }
  if (isAndroid) { openUrl(googleCalUrl(it)); return; }
  downloadICS(icsFor(it), it.title);
}
function downloadICS(ics, title) {
  if (isIOS) { location.href = 'data:text/calendar;charset=utf-8,' + encodeURIComponent(ics); return; }
  tools.deliver((title.replace(/[^\w ]/g, '').slice(0, 30) || 'event') + '.ics', new TextEncoder().encode(ics), 'text/calendar');
}

// ---------------- chat ----------------
function addMsg(role, text, extra = {}) {
  const m = { role, text, ts: Date.now(), ...extra };
  store.chat.push(m); store.save(); renderChat(); return m;
}
function resultRows(m) {
  if (m.files?.length) return `<div class="res">${m.files.slice(0, 12).map(f => `<div class="res-row"><span>📄</span><div class="txt"><div class="t1">${esc(f.name)}</div><div class="t2">${new Date(f.mtime).toLocaleString([], { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })}</div></div><button data-open="${esc(f.path)}">Open</button><button data-reveal="${esc(f.path)}">Show</button></div>`).join('')}</div>`;
  if (m.results?.length) return `<div class="res">${m.results.slice(0, 12).map(r => `<div class="res-row"><span>${ICON[r.kind] || '•'}</span><div class="txt"><div class="t1">${esc(r.title)}</div><div class="t2">${new Date(r.at).toLocaleString([], { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })}</div></div>${r.meta?.fileId ? `<button data-file="${r.meta.fileId}">Open</button>` : ''}</div>`).join('')}</div>`;
  if (m.clips?.length) return `<div class="res">${m.clips.slice(0, 15).map((c, i) => `<div class="res-row"><div class="txt"><div class="t1">${esc(c.text.slice(0, 80))}</div><div class="t2">${new Date(c.at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}</div></div><button data-clip="${i}">Copy</button></div>`).join('')}</div>`;
  return '';
}
function renderChat() {
  const box = $('#chat');
  if (!store.chat.length) { box.innerHTML = `<div class="msg bot">Hi${S().name ? ' ' + esc(S().name) : ''}! I'm Zuffi 🐦\nAsk me anything, tell me what to remember, or drop a file with 📎 and ask about it.</div>`; return; }
  box.innerHTML = store.chat.slice(-60).map(m => {
    let extra = '';
    if (m.itemId) { const it = store.items.find(x => x.id === m.itemId); if (it?.when) extra = `<div class="cal"><button class="chip" data-cal="${it.id}">📅 Add to calendar</button></div>`; }
    if (m.action === 'ai') extra = `<div class="cal"><button class="chip" data-settings="ai">✨ Set up free AI</button></div>`;
    if (m.draft) extra = `<div class="cal"><button class="chip" data-mailto="${esc(m.draft)}">✉️ Open in email</button><button class="chip" data-copy="${esc(m.draftBody || '')}">📋 Copy</button></div>`;
    return `<div class="msg ${m.role}">${esc(m.text)}${m.src ? `<span class="src">${esc(m.src)}</span>` : ''}${resultRows(m)}${extra}</div>`;
  }).join('');
}
$('#chat').onclick = async e => {
  const b = e.target.closest('button'); if (!b) return;
  if (b.dataset.settings) return openSettings(b.dataset.settings);
  if (b.dataset.cal) { const it = store.items.find(x => x.id === b.dataset.cal); if (it) addToCalendar(it); }
  if (b.dataset.open) { D?.openPath(b.dataset.open); mem.remember('opened', b.dataset.open.split(/[\\/]/).pop(), '', { path: b.dataset.open }); }
  if (b.dataset.reveal) D?.openPath(b.dataset.reveal, true);
  if (b.dataset.file) { const f = await mem.getFile(b.dataset.file); if (f?.blob) tools.deliver(f.name, new Uint8Array(await f.blob.arrayBuffer()), f.type); else toast(f ? 'Zuffi remembered this file but didn’t keep a copy (turn on “Keep a copy” in Settings → Memory).' : 'That file is gone.', 5000); }
  if (b.dataset.clip !== undefined) { const clips = await D.clips('get'); D.clips('copy', clips[+b.dataset.clip].text); toast('Copied'); }
  if (b.dataset.mailto) openUrl(b.dataset.mailto);
  if (b.dataset.copy !== undefined) { try { await navigator.clipboard.writeText(b.dataset.copy); toast('Copied'); } catch {} }
};

let attachments = [];       // files attached to the next question
let activeDocs = [];        // file ids the conversation is about
let lastWasVoice = false, replyKind = 'cmd', followUps = 0;
async function submit(text, fromVoice = false) {
  text = text.trim();
  if (!text && !attachments.length) return;
  lastWasVoice = fromVoice;
  const files = attachments; attachments = []; renderAttached();
  if (files.length) {
    addMsg('me', (text ? text + '\n' : '') + files.map(f => '📎 ' + f.name).join('\n'));
    go('chat');
    const saved = [];
    for (const f of files) { try { saved.push(await mem.addFile(f)); } catch {} }
    activeDocs = saved.map(s => s.id);
    if (!text && saved.length === 1 && jobs.isCV(saved[0])) {
      addMsg('bot', `Got your CV — ${saved[0].name}. Give me a moment to read it…`);
      const a = await jobs.analyseCV(saved[0]); addMsg('bot', a.reply); if (a.ok) jobs.openJobs('profile');
      return;
    }
    if (!text) {
      const words = saved.reduce((n, s) => n + (s.text ? s.text.split(/\s+/).length : 0), 0);
      addMsg('bot', `Got it — I saved ${saved.map(s => s.name).join(', ')} in your memory${words ? ` (${words.toLocaleString()} words)` : ''}. Ask me anything about ${saved.length > 1 ? 'them' : 'it'}.`);
      return;
    }
  } else { addMsg('me', text); go('chat'); }
  mem.remember('chat', text);

  // "lock my Mac", "turn off the laptop", "open Spotify on my Mac"… → your Mac at home does it
  if (!files.length && !M && maclink.isForMac(text)) {
    const wait = addMsg('bot', '💻 Sending to your Mac…', { cmd: true });
    const r = await maclink.send(text);
    { const i = store.chat.indexOf(wait); if (i >= 0) store.chat.splice(i, 1); }
    addMsg('bot', (r.ok ? '💻 ' : '⚠️ ') + r.text, { cmd: true });
    birdMood(r.ok ? 'happy' : 'talk');
    if (fromVoice || S().speak) speak(r.text);
    return;
  }
  if (!files.length) {
    const r = await handle(text);
    if (r) {
      const mine = store.chat[store.chat.length - 1]; if (mine?.role === 'me') mine.cmd = true;   // keep commands out of the AI's memory
      replyKind = 'cmd';
      if (await runAction(r)) return;
      addMsg('bot', r.reply, { cmd: true, ...(r.item ? { itemId: r.item.id } : {}), ...(r.results ? { results: r.results } : {}), ...(r.files ? { files: r.files } : {}) });
      birdMood(r.item ? 'happy' : 'talk');
      if (r.url) setTimeout(() => openUrl(r.url), 350);
      if (fromVoice || S().speak) speak(r.reply);
      if (fromVoice) window.SparrowIsland?.reply(r.reply, !r.results && !r.files);
      return;
    }
  }
  // Ask an AI (with your files if the question is about them)
  const aboutDocs = activeDocs.length && (files.length || /\b(it|this|that|file|document|pdf|contract|cv|resume|report|invoice|attached|summar|page)\b/i.test(text));
  let context = '';
  if (aboutDocs) context = await mem.relevantText(text, activeDocs);
  else if (/\b(my files?|my documents?|in my (files|docs))\b/i.test(text)) context = await mem.relevantText(text);
  const box = $('#chat');
  const typing = document.createElement('div');
  typing.className = 'msg bot typing'; typing.innerHTML = '<span></span><span></span><span></span>';
  box.appendChild(typing); window.scrollTo({ top: document.body.scrollHeight });
  setBird('talking', true);
  try {
    const res = await ask(text, partial => { typing.classList.remove('typing'); typing.textContent = partial; window.scrollTo({ top: document.body.scrollHeight }); }, { context });
    typing.remove();
    replyKind = 'ai';
    addMsg('bot', res.text || '…', { src: res.source });
    if (fromVoice) window.SparrowIsland?.reply(res.text || '', false);
    mem.remember('chat', 'Zuffi: ' + (res.text || '').slice(0, 200));
    if (fromVoice || S().speak) speak(res.text);
  } catch (e) {
    typing.remove();
    if (e.message === 'NO_AI') addMsg('bot', D ? "I can do reminders, apps, files, music and lots more right now. To answer open questions, install the free Ollama app on this computer (ollama.com) or add a free key (Groq or Gemini) in Settings → AI."
      : "I can handle reminders, meetings, tasks, notes, habits, prayer times and more right now. To answer anything else, switch on the free AI (Settings → AI) or add a free key.", { action: 'ai' });
    else addMsg('bot', '⚠️ ' + e.message);
  } finally { setBird('talking', false); }
}
/** Fresh conversation: clears the chat, attached files and the files it was talking about. */
/** Keeps a finished conversation in History so it can be reopened and continued later. */
function archiveChat(msgs = store.chat) {
  const real = msgs.filter(m => m.role === 'me' || m.role === 'bot');
  if (real.filter(m => m.role === 'me').length < 1) return;
  const first = real.find(m => m.role === 'me')?.text || 'Chat';
  store.sessions = [{ id: 's' + Date.now().toString(36), title: first.replace(/\s+/g, ' ').slice(0, 60), ts: real[real.length - 1].ts || Date.now(), chat: real.slice(-80) },
    ...store.sessions].slice(0, 40);
}
function newChat(fromIsland = false) {
  archiveChat();
  store.chat = []; store.save();
  attachments = []; activeDocs = []; followUps = 0; replyKind = 'cmd';
  renderAttached(); renderChat();
  if (M && !fromIsland) M.post('newchat');
}
$('#newChatBtn').onclick = () => { newChat(); renderHistory(false); toast('New chat'); $('#askInput').focus(); };
function renderHistory(show = !$('#historyList').classList.contains('open')) {
  const el = $('#historyList');
  el.classList.toggle('open', show);
  if (!show) return;
  el.innerHTML = store.sessions.length
    ? store.sessions.map(s => `<div class="hist-row" data-id="${s.id}"><div class="txt"><div class="t1">${esc(s.title)}</div><div class="t2">${new Date(s.ts).toLocaleString([], { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })} · ${s.chat.length} messages</div></div><button class="hist-del" data-del="${s.id}" title="Delete">✕</button></div>`).join('')
    : '<div class="hist-empty">No past chats yet. When you start a new chat, the old one is kept here.</div>';
}
$('#historyBtn').onclick = () => renderHistory();
$('#historyList').onclick = e => {
  const del = e.target.closest('[data-del]');
  if (del) { store.sessions = store.sessions.filter(s => s.id !== del.dataset.del); store.save(); renderHistory(true); return; }
  const row = e.target.closest('.hist-row'); if (!row) return;
  const s = store.sessions.find(x => x.id === row.dataset.id); if (!s) return;
  archiveChat();                                   // keep what was open
  store.sessions = store.sessions.filter(x => x.id !== s.id);
  store.chat = s.chat.slice(); activeDocs = []; replyKind = 'ai';
  store.save(); renderHistory(false); renderChat(); go('chat');
  toast('Chat reopened — carry on, I remember it');
  $('#askInput').focus();
};
$('#askForm').onsubmit = e => { e.preventDefault(); const v = $('#askInput').value; $('#askInput').value = ''; followUps = 0; submit(v); };

/** Things the brain asks the app to do. Returns true if fully handled. */
async function runAction(r) {
  switch (r.action) {
    case 'checkin': openCheckIn(true); return true;
    case 'focus': addMsg('bot', r.reply); startFocus(r.minutes); return true;
    case 'report': openReport(); addMsg('bot', 'Here is your report for today — copy or share it from the panel.'); return true;
    case 'memory': go('memory'); $('#memSearch').value = r.query?.q || ''; renderMemory(); return true;
    case 'clipboard': {
      if (!D) { addMsg('bot', 'Clipboard history works in the Mac and Windows app. On a phone, save things as snippets: "save snippet bank details: …"'); return true; }
      addMsg('bot', r.reply, { clips: await D.clips('get') }); return true;
    }
    case 'meeting-start': addMsg('bot', 'Opening meeting notes…'); startMeetingNotes(); return true;
    case 'meeting-stop': stopMeetingNotes(); return true;
    case 'sync': openSync(); return true;
    case 'newchat': newChat(); addMsg('bot', r.reply, { cmd: true }); return true;
    // ----- job agent -----
    case 'jobs-open': jobs.openJobs(); addMsg('bot', jobs.data.profile ? 'Here’s your job agent.' : 'Here’s your job agent — start by adding your CV.', { cmd: true }); return true;
    case 'cv-analyse': {
      addMsg('bot', 'Reading your CV…', { cmd: true });
      const a = await jobs.analyseCV(activeDocs.length ? await mem.getFile(activeDocs[0]).then(f => jobs.isCV(f) ? f : null).catch(() => null) : null);
      addMsg('bot', a.reply, { cmd: true }); if (a.ok) jobs.openJobs('profile'); return true;
    }
    case 'jobs-search': {
      addMsg('bot', `Looking for ${r.q || 'jobs that fit you'}${r.where ? ' in ' + r.where : ''}…`, { cmd: true });
      const a = await jobs.searchJobs(r.q, r.where); addMsg('bot', a.reply, { cmd: true }); jobs.openJobs('jobs'); return true;
    }
    case 'jobs-tailor': { const a = await jobs.tailor(jobs.jobAt(r.n)); addMsg('bot', a.reply, { cmd: true }); if (a.ok) jobs.openJobs('jobs'); return true; }
    case 'jobs-apply': { const a = await jobs.startApply(jobs.jobAt(r.n)); addMsg('bot', a.reply, { cmd: true }); return true; }
    case 'jobs-tracker': addMsg('bot', jobs.trackerSummary(), { cmd: true }); jobs.openJobs('applied'); return true;
    case 'refresh': renderAll(); addMsg('bot', r.reply); return true;
    case 'email': addMsg('bot', r.reply); lastEmail = r.email; speak(`Email from ${r.email.from.replace(/<.*>/, '')}. ${r.email.subject}`); return true;
    case 'email-reply': {
      let body = r.text;
      if (!body || body.split(' ').length < 4) {
        try { body = (await ask(`Write a short, polite email reply${body ? ' that says: ' + body : ''}. Only the reply text, no subject line.\n\nThe email:\nFrom: ${lastEmail?.from}\nSubject: ${lastEmail?.subject}\n${lastEmail?.body?.slice(0, 3000)}`, null, { noHistory: true })).text; }
        catch { body = body || 'Thank you for your email. I will get back to you shortly.'; }
      }
      const res = await D.mail('reply', body);
      addMsg('bot', res?.ok ? `✉️ Your reply is ready in Mail — check it and press Send:\n\n${body}` : 'I couldn’t open Mail. Allow Zuffi under System Settings → Privacy & Security → Automation.');
      return true;
    }
    case 'email-new': {
      const cust = findCustomer(r.to); const to = cust?.email || (/@/.test(r.to) ? r.to : '');
      let body = '';
      try { body = (await ask(`Write a short, friendly email to ${cust?.title || r.to} about: ${r.about}. Sign off with ${S().name || 'my name'}. Only the email body.`, null, { noHistory: true })).text; }
      catch { body = `Hi ${(cust?.title || r.to).split(' ')[0]},\n\n${r.about.charAt(0).toUpperCase() + r.about.slice(1)}.\n\nBest wishes,\n${S().name || ''}`; }
      const subject = r.about.charAt(0).toUpperCase() + r.about.slice(0, 60);
      const url = `mailto:${encodeURIComponent(to)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
      mem.remember('email', `Email to ${cust?.title || r.to}: ${subject}`, body);
      addMsg('bot', `✉️ Draft for ${cust?.title || r.to}${to ? '' : ' (no email address saved — add it with "add customer …")'}:\n\n${body}`, { draft: url, draftBody: body });
      return true;
    }
  }
  return false;
}
let lastEmail = null;

// ---------------- attachments ----------------
$('#attachBtn').onclick = () => $('#fileInput').click();
$('#fileInput').onchange = e => { attachments.push(...e.target.files); e.target.value = ''; renderAttached(); $('#askInput').focus(); };
function renderAttached() {
  const el = $('#attached'); el.hidden = !attachments.length;
  el.innerHTML = attachments.map(f => `<span title="${esc(f.name)}">📎 ${esc(f.name)}</span>`).join('');
}
// drag & drop files anywhere (computer)
document.addEventListener('dragover', e => e.preventDefault());
document.addEventListener('drop', e => { e.preventDefault(); if (e.dataTransfer?.files?.length) { attachments.push(...e.dataTransfer.files); renderAttached(); toast('File attached — ask a question or press send'); } });

function openUrl(url) {
  if (!url) return;
  if (M) { M.post('open', { url: url.startsWith('app:') ? 'app:' + url.slice(4) : url }); return; }
  if (url.startsWith('app:')) { if (!((N || D) && (N || D).openApp(url.slice(4)))) toast(`Couldn't find ${url.slice(4)}`); return; }
  if (/^https?:/.test(url)) window.open(url, '_blank', 'noopener');
  else location.href = url;
}

// ---------------- the sparrow ----------------
const bird = $('#bird');
// The pink sparrow: looks at your pointer, reacts when tapped (and tapping still means "talk").
const sparrow = mountBird(bird, { onTap: () => listen() });
function setBird(cls, on) { bird.classList.toggle(cls, on); }
function birdMood(m) { if (m === 'happy') { bird.classList.remove('happy'); void bird.offsetWidth; bird.classList.add('happy'); setTimeout(() => bird.classList.remove('happy'), 1100); sparrow.react(['delighted', 'heart', 'sparkle'][Math.floor(Math.random() * 3)], 1000); } }
function tone(pairs, vol = .08) {
  try {
    const ac = new (window.AudioContext || window.webkitAudioContext)();
    pairs.forEach(([f0, f1, t0, d]) => {
      const o = ac.createOscillator(), g = ac.createGain();
      o.frequency.setValueAtTime(f0, ac.currentTime + t0); o.frequency.exponentialRampToValueAtTime(f1, ac.currentTime + t0 + d * .8);
      g.gain.setValueAtTime(.0001, ac.currentTime + t0); g.gain.exponentialRampToValueAtTime(vol, ac.currentTime + t0 + .01);
      g.gain.exponentialRampToValueAtTime(.0001, ac.currentTime + t0 + d);
      o.connect(g).connect(ac.destination); o.start(ac.currentTime + t0); o.stop(ac.currentTime + t0 + d + .05);
    });
    setTimeout(() => ac.close(), 2000);
  } catch {}
}
const chirp = () => tone([[2600, 3600, 0, .08], [3000, 4200, .09, .08]]);
const chime = () => tone([[880, 880, 0, .5], [1318.5, 1318.5, .16, .9]], .18);

// ---------------- voice out ----------------
let voices = [];
function loadVoices() { voices = speechSynthesis?.getVoices?.() || []; }
if ('speechSynthesis' in window) { loadVoices(); speechSynthesis.onvoiceschanged = loadVoices; }
const FEMALE = /samantha|ava|zoe|serena|allison|susan|karen|moira|tessa|kate|victoria|fiona|female|woman|google uk english female|google us english|siri.*female|sonia|libby|jenny|aria|zira|hazel|heera|kalpana|swara|lekha|uzma|salma|hoda|zariyah/i;
const MALE = /daniel|alex|tom|evan|nathan|aaron|arthur|oliver|fred|rishi|male|man|google uk english male|guy|ryan|thomas|david|mark|george|ravi|hemant|asad|naayf|hamed|maged/i;
function pickVoice() {
  const want = SPEECH_LANG[S().lang] || 'en-GB', lang = want.slice(0, 2);
  const pool = voices.filter(v => v.lang?.toLowerCase().startsWith(lang));
  const list = pool.length ? pool : voices.filter(v => v.lang?.startsWith('en'));
  const re = S().gender === 'male' ? MALE : FEMALE;
  const q = v => (/premium|enhanced|natural|neural|siri|online/i.test(v.name) ? 0 : 2) + (v.lang?.replace('_', '-') === want ? 0 : 1);
  return list.filter(v => re.test(v.name)).sort((a, b) => q(a) - q(b))[0] || list.sort((a, b) => q(a) - q(b))[0] || null;
}
let speakEnd = null;
function speak(text) {
  if (!text) return;
  const clean = text.replace(/[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}•]/gu, '').replace(/\n+/g, '. ');
  if (N) { N.speak(clean, S().gender); return; }
  if (M) { M.post('speak', { text: clean }); return; }   // the Mac island speaks with Apple's natural voices
  if (window.SparrowVoice?.nativeSay && window.SparrowVoice.nativeSay(clean)) return;   // Mac: Apple's natural voices
  if (S().neural !== false) {
    const myTurn = ++speakTurn;
    try { speechSynthesis?.cancel(); } catch {}
    nv.say(clean, neuralOpts()).then(ok => { if (!ok && myTurn === speakTurn) systemSpeak(clean); });
    return;
  }
  systemSpeak(clean);
}
let speakTurn = 0;
function neuralOpts(extra = {}) {
  return {
    lang: S().lang, gender: S().gender, voice: S().voiceName || undefined, studio: !!S().studio, speed: S().simple ? 0.9 : 1,
    onstart: () => { setBird('talking', true); D?.state({ speaking: true }); },
    onend: () => { setBird('talking', false); D?.state({ speaking: false }); afterSpeech(); },
    ...extra,
  };
}
function systemSpeak(clean) {
  if (!('speechSynthesis' in window)) return;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(clean);
  const v = pickVoice(); if (v) { u.voice = v; u.lang = v.lang; } else u.lang = SPEECH_LANG[S().lang] || 'en-GB';
  u.rate = S().simple ? 0.85 : 0.98; u.pitch = S().gender === 'male' ? 0.95 : 1.05;
  u.onstart = () => { setBird('talking', true); D?.state({ speaking: true }); };
  u.onend = u.onerror = () => { setBird('talking', false); D?.state({ speaking: false }); afterSpeech(); };
  speechSynthesis.speak(u);
}
// Conversation mode: after answering a spoken question, listen again without a tap.
function afterSpeech() {
  // Only after a real answer to a spoken question (never after "Opening Spotify…"), and at most twice in a row.
  if (!lastWasVoice || !S().conversation || replyKind !== 'ai' || followUps >= 2) { lastWasVoice = false; followUps = 0; return; }
  lastWasVoice = false; followUps++;
  setTimeout(() => { if (window.SparrowVoice) window.SparrowVoice.startCommand(); else listen(true); }, 300);
}

// ---------------- Jarvis: live conversation (iPhone, Android, Windows, browser) ----------------
const LIVE_TOOLS = [
  { name: 'run_command', description: "Do something with Zuffi in plain English: 'open WhatsApp', 'play music', 'remind me…', 'what's on today', 'weather', 'prayer times', 'note buy milk', 'search google for X', 'open youtube.com', 'focus 25 minutes', 'add task…'.", parameters: { type: 'OBJECT', properties: { command: { type: 'STRING' } }, required: ['command'] } },
  { name: 'add_reminder', description: 'Create a reminder/task/meeting at an exact time.', parameters: { type: 'OBJECT', properties: { title: { type: 'STRING' }, when: { type: 'STRING', description: 'ISO local date-time, e.g. 2026-10-12T10:00:00' }, kind: { type: 'STRING', description: 'reminder | task | meeting' }, repeat: { type: 'STRING', description: 'daily | weekdays | weekly | monthly (optional)' } }, required: ['title', 'when'] } },
  { name: 'delete_reminder', description: 'Delete an item by id (from the list in your instructions).', parameters: { type: 'OBJECT', properties: { id: { type: 'STRING' } }, required: ['id'] } },
  { name: 'complete_task', description: 'Mark an item done by id.', parameters: { type: 'OBJECT', properties: { id: { type: 'STRING' } }, required: ['id'] } },
  { name: 'list_reminders', description: 'Current reminders, meetings and tasks with ids.' },
  { name: 'find_jobs', description: "Search jobs that fit the user's CV, plus LinkedIn and Indeed searches with the same filters.", parameters: { type: 'OBJECT', properties: { role: { type: 'STRING' }, location: { type: 'STRING' }, level: { type: 'STRING', description: 'internship | apprentice | entry | mid | senior | lead' } }, required: ['role'] } },
  { name: 'look_through_camera', description: 'Take a look through the camera to answer what the user is showing or asking about.', parameters: { type: 'OBJECT', properties: { camera: { type: 'STRING', description: 'front (default) or back' } } } },
  { name: 'control_mac', description: "Do something on the user's Mac at home (it's linked): lock, sleep, shut down, restart, volume, play/pause music, open/quit apps or websites, battery, what's running, notes, reminders on the Mac. Write one clear English command, e.g. 'lock the screen', 'shut down mac', 'open Spotify', 'volume 30'.", parameters: { type: 'OBJECT', properties: { command: { type: 'STRING' } }, required: ['command'] } },
  { name: 'end_conversation', description: 'Call after a short goodbye when the user says thanks/bye/that is all.' },
];
async function liveTool(name, a) {
  const res = r => r ? { ok: true, result: typeof r === 'string' ? r : JSON.stringify(r) } : { ok: false, result: 'Zuffi could not do that.' };
  switch (name) {
    case 'run_command': return res(await voiceAsk(a.command || ''));
    case 'add_reminder': return res(window.Sparrow.addReminder(a.title, a.when, a.kind || 'reminder', a.repeat || ''));
    case 'delete_reminder': { const t = window.Sparrow.removeItem(a.id); return t ? { ok: true, result: 'Deleted: ' + t } : { ok: false, result: 'No item with that id.' }; }
    case 'complete_task': { const t = window.Sparrow.completeItem(a.id); return t ? { ok: true, result: 'Done: ' + t } : { ok: false, result: 'No item with that id.' }; }
    case 'list_reminders': return res(window.Sparrow.listItems());
    case 'find_jobs': return res(await voiceAsk(`find ${a.level ? a.level + ' ' : ''}${a.role} jobs${a.location ? ' in ' + a.location : ''}`));
    case 'look_through_camera': {
      try { liveSendImage(await cameraShot(/back|rear/.test(a.camera || '') ? 'environment' : 'user')); return { ok: true, result: 'A camera photo was just sent to you. Answer from what you see.' }; }
      catch { return { ok: false, result: 'The camera is not allowed. Allow it in the browser/phone settings.' }; }
    }
    case 'control_mac': { const r = await maclink.send(a.command || ''); return { ok: r.ok, result: r.text }; }
    case 'end_conversation': return { ok: true, result: 'Ending after your goodbye.' };
  }
  return { ok: false, result: 'Unknown tool.' };
}
function livePrompt() {
  const name = S().name || '';
  return `You are Zuffi, ${name ? name + "'s" : "the user's"} personal assistant — like JARVIS: calm, quick, warm, a little witty. Live voice conversation on their ${isIOS ? 'iPhone' : isAndroid ? 'Android phone' : D ? 'computer' : 'device'}.
Now: ${new Date().toLocaleString([], { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' })} (${Intl.DateTimeFormat().resolvedOptions().timeZone}).
Their reminders, meetings and tasks (JSON with ids): ${JSON.stringify(window.Sparrow.listItems()).slice(0, 4000)}
TALK: 1–2 short spoken sentences, no lists or emojis. Detect the language they speak and ALWAYS answer in that same language and style (Urdu, Roman Urdu/Hindi mix, Punjabi, Hindi, Arabic, Spanish, French, Brazilian Portuguese, Turkish, English…). Translate clearly when asked. They may interrupt you.
ACT: call tools right away, even mid-sentence; do multi-step requests step by step. Reminders: use add_reminder with an exact ISO time worked out from now ("coming Monday at 10" = next Monday 10:00); to delete, pick the matching id (by day, time or words) — ask if two match. Use Google Search for facts, news, prices and "what is this", combining sources. For "what do you see / look at this" use look_through_camera.${maclink.linked() && !M ? ' Their Mac at home is linked: anything about their Mac/laptop/computer ("lock my Mac", "turn off the laptop", "play music on my Mac") → control_mac.' : ''} Jobs: find_jobs with role, place and level. Only say something is done if the tool says so.
END: when they say thanks / bye / that's all / khuda hafiz / shukriya, give a very short goodbye and call end_conversation.`;
}
let liveSparrow = null;
function startJarvis(firstText) {
  const scr = $('#liveScreen'), status = $('#liveStatus'), cap = $('#liveCaption'), orb = $('#liveOrb');
  liveSparrow = liveSparrow || mountBird($('#liveBird'), {});
  const label = { connecting: 'Connecting…', listening: 'Listening…', speaking: 'Speaking…', working: 'On it…' };
  scr.hidden = false; scr.dataset.state = 'connecting'; status.textContent = label.connecting; cap.textContent = '';
  speechSynthesis?.cancel(); stopWake();
  startLive({
    tools: maclink.linked() && !M ? LIVE_TOOLS : LIVE_TOOLS.filter(t => t.name !== 'control_mac'), run: liveTool, prompt: livePrompt, firstText,
    onState: (st, info) => { if (st === 'error') { status.textContent = info || 'Something went wrong.'; liveSparrow.react('surprised', 1500); return; } if (st === 'working' && scr.dataset.state !== 'working') liveSparrow.react('sparkle', 700); scr.dataset.state = st; status.textContent = label[st] || ''; },
    onLevel: v => orb.style.setProperty('--lv', v.toFixed(2)),
    onLine: (who, t) => { cap.textContent = t.slice(-160); },
    onTurn: (u, a) => { if (u) addMsg('me', u, { cmd: true }); if (a) addMsg('bot', a, { src: 'Live' }); },
    onEnd: why => { if (why === 'goodbye') liveSparrow.react('heart', 900); setTimeout(() => { scr.hidden = true; }, why === 'no-mic' || why === 'no-model' || why === 'timeout' ? 3500 : 250); setTimeout(startWake, 900); },
  });
}
$('#liveEnd').onclick = () => stopLive('tap');
$('#liveCam').onclick = async () => { try { liveSendImage(await cameraShot('environment')); toast('Zuffi is looking 👀'); } catch { toast('Allow the camera for Zuffi.'); } };

// ---------------- voice in ----------------
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
let rec = null, listening = false, wakeRec = null;
function listen(quiet = false) {
  if (liveActive()) { stopLive('tap'); return; }
  if (liveUsable()) { startJarvis(); return; }
  if (N) { N.listen(); return; }
  if (M) { M.post('listen'); return; }
  if (window.SparrowVoice) { window.SparrowVoice.toggle(); return; }
  if (!SR) { if (!quiet) toast('Voice input isn\'t supported in this browser — type instead.'); return; }
  if (listening) { rec?.stop(); return; }
  stopWake();
  speechSynthesis?.cancel();
  rec = new SR(); rec.lang = SPEECH_LANG[S().lang] || navigator.language || 'en-GB'; rec.interimResults = true; rec.maxAlternatives = 1;
  let finalText = '';
  rec.onstart = () => { listening = true; $('#micBtn').classList.add('on'); $('#pulse').classList.add('on'); setBird('listening', true); chirp(); $('#askInput').placeholder = 'Listening…'; };
  rec.onresult = e => { let txt = ''; for (const r of e.results) txt += r[0].transcript; $('#askInput').value = txt; if (e.results[e.results.length - 1].isFinal) finalText = txt; };
  rec.onerror = e => { if (e.error === 'not-allowed' && !quiet) toast('Allow the microphone for Zuffi in your settings.'); };
  rec.onend = () => {
    listening = false; $('#micBtn').classList.remove('on'); $('#pulse').classList.remove('on'); setBird('listening', false);
    applyI18n();
    const tx = (finalText || $('#askInput').value).trim();
    $('#askInput').value = '';
    if (tx && tx.length > 2 && !/^(i|a|uh|um|the|oh|ah|hmm|huh)$/i.test(tx)) submit(tx, true);
    setTimeout(startWake, 800);
  };
  try { rec.start(); } catch {}
}
$('#micBtn').onclick = () => listen();
$('#micHeroBtn').onclick = () => listen();


// Hands-free on phones/browsers: listen for "Zuffi …" while the app is open.
function startWake() {
  if (N || D || M || !SR || !S().wake || wakeRec || listening || document.hidden) return;
  try {
    wakeRec = new SR(); wakeRec.continuous = true; wakeRec.interimResults = false; wakeRec.lang = SPEECH_LANG[S().lang] || 'en-GB';
    wakeRec.onresult = e => {
      const tx = e.results[e.results.length - 1][0].transcript.trim();
      const m = tx.match(/\b(?:hey |ok )?(sparrow|spa?rrow|sparo)\b[,\s]*(.*)$/i);
      if (!m) return;
      stopWake();
      if (m[2] && m[2].length > 2) submit(m[2], true); else listen(true);
    };
    wakeRec.onend = () => { wakeRec = null; if (S().wake && !listening) setTimeout(startWake, 1200); };
    wakeRec.onerror = e => { if (e.error === 'not-allowed') S().wake && ($('#listenHint').hidden = true); };
    wakeRec.start();
    $('#listenHint').hidden = false;
  } catch { wakeRec = null; }
}
function stopWake() { try { wakeRec?.abort(); } catch {} wakeRec = null; $('#listenHint').hidden = true; }
document.addEventListener('visibilitychange', () => { if (document.hidden) stopWake(); else setTimeout(startWake, 600); });

// ---------------- briefing ----------------
async function showBriefing(speakIt) {
  $('#brief').textContent = `${greetingWord()}${S().name ? ', ' + S().name : ''}! ${daySummary(new Date(), true)}`;
  const text = await briefing();
  $('#brief').textContent = text;
  if (speakIt) speakSoon(text);
}
$('#hearBriefBtn').onclick = () => showBriefing(true);

// ---------------- alerts: reminders, snooze, prayer, habits ----------------
async function notify(msg, tag) {
  if (M) return;    // the island shows it
  try {
    if (Notification?.permission === 'granted') {
      const reg = await navigator.serviceWorker?.getRegistration();
      reg ? reg.showNotification('Zuffi', { body: msg, icon: 'icons/icon-192.png', tag }) : new Notification('Zuffi', { body: msg });
    }
  } catch {}
}
function showAlert(title, sub, itemId) {
  // On the Mac, a reminder or meeting brings Zuffi walking across the screen with a banner.
  const item = itemId && store.items.find(i => i.id === itemId);
  if (M && item) M.post('reminder', { itemId, kind: item.type || 'reminder', title: item.title || title, sub: sub || '' });
  else if (M) M.post('note', { title, sub: sub || '' });
  window.SparrowIsland?.peek(title, sub || '', 9000);
  $('#alertTitle').textContent = title; $('#alertSub').textContent = sub || '';
  $('#alert').hidden = false;
  $('#alertSnooze').hidden = !itemId; $('#alertSnooze').dataset.id = itemId || ''; $('#alertDone').dataset.id = itemId || '';
  clearTimeout(showAlert.t); showAlert.t = setTimeout(() => $('#alert').hidden = true, 60000);
}
$('#alertSnooze').onclick = () => { const id = $('#alertSnooze').dataset.id; const it = store.items.find(i => i.id === id); if (it) { store.update(id, { snoozeUntil: Date.now() + 10 * 60000, snoozed: false, done: false }); toast('😴 Snoozed for 10 minutes'); } $('#alert').hidden = true; };
$('#alertDone').onclick = () => { const id = $('#alertDone').dataset.id; const it = store.items.find(i => i.id === id); if (it && !it.repeat) store.update(id, { done: true, doneAt: new Date().toISOString() }); $('#alert').hidden = true; };
function alertNow(spoken, shown, tag, itemId) {
  chime(); showAlert(shown, itemId ? 'Or say “snooze”' : '', itemId); birdMood('happy');
  if (itemId) setLastAlert(itemId);
  if (!N) { speakSoon(spoken); notify(shown, tag); }
}
const who = () => S().name ? S().name + ', ' : '';
async function checkDue() {
  const now = Date.now(), lead = (+S().lead || 0) * 60000;
  const missed = [];
  for (const it of store.items) {
    if (!['reminder', 'meeting', 'task'].includes(it.type) || it.done) continue;
    if (it.snoozeUntil && !it.snoozed && it.snoozeUntil <= now) {
      store.update(it.id, { snoozed: true, snoozeUntil: null });
      alertNow(`${who()}snoozed reminder: ${it.title}.`, '⏰ ' + it.title, it.id + 'snz', it.id); continue;
    }
    if (!it.when || (it.type === 'task' && !it.timed)) continue;
    const at = new Date(it.when).getTime(), meet = it.type === 'meeting';
    if (!it.notified && at <= now) {
      if (now - at < 10 * 60000) alertNow(meet ? `${who()}you have a meeting now: ${it.title}.` : `${who()}it's time: ${it.title}.`, (meet ? '🗓️ Now: ' : '⏰ ') + it.title, it.id, it.id);
      else if (now - at < 24 * 3600e3) missed.push(`${it.title} (${fmtTime(new Date(at))})`);   // the Mac was asleep
      if (it.repeat) { const nx = nextOccurrence(it.repeat, it.when, new Date(now)); store.update(it.id, { when: nx.toISOString(), notified: false, soonDone: false }); }
      else store.update(it.id, { notified: true, soonDone: true, ...(it.type === 'reminder' ? { done: true, doneAt: new Date().toISOString() } : {}) });
    } else if (lead && !it.soonDone && at > now && at - now <= lead) {
      store.update(it.id, { soonDone: true });
      const mins = Math.max(1, Math.round((at - now) / 60000));
      alertNow(meet ? `${who()}you have a meeting in ${mins} minute${mins > 1 ? 's' : ''}: ${it.title}.` : `${who()}reminder in ${mins} minute${mins > 1 ? 's' : ''}: ${it.title}.`, `⏳ In ${mins} min: ${it.title}`, it.id + 'soon', it.id);
    }
  }
  if (missed.length) {
    const msg = `While your Mac was asleep you missed: ${missed.slice(0, 4).join(', ')}.`;
    chime(); showAlert('⏰ You missed ' + missed.length + (missed.length > 1 ? ' reminders' : ' reminder'), missed.slice(0, 3).join(' · ')); speakSoon(`${who()}${msg}`);
  }
  checkPrayer(); checkHabits(); checkDaily(); checkFocus(); checkHealth();
}
let prayerCache = { day: '', times: null };
function checkPrayer() {
  const p = S().prayer, loc = S().lastLoc;
  if (!p.on || !loc || N) return;      // Android rings these with its own alarms
  if (prayerCache.day !== dayKey() && p.method === 'Auto') refreshOnline(loc.lat, loc.lon, p.asr);
  prayerCache = { day: dayKey(), times: prayerTimes(new Date(), loc.lat, loc.lon, p.method, p.asr) };
  const fired = S().prayerFired || {}, now = Date.now();
  for (const n of PRAYERS) {
    if (n === 'Sunrise') continue;
    const at = prayerCache.times[n].getTime() - (+p.before || 0) * 60000, key = dayKey() + n;
    if (!fired[key] && now >= at && now - at < 10 * 60000) {
      fired[key] = 1; S().prayerFired = Object.fromEntries(Object.entries(fired).slice(-12)); store.save();
      const msg = +p.before ? `${n} prayer in ${p.before} minutes` : `It's time for ${n} prayer`;
      chime(); showAlert('🕌 ' + msg, fmtTime(prayerCache.times[n])); if (p.speak) speakSoon(`${who()}${msg}.`); notify(msg, 'prayer' + n);
    }
  }
}
function checkHabits() {
  const h = new Date().getHours(); if (h < 9 || h >= 21) return;
  for (const hb of store.ofType('habit')) {
    if (!hb.every || habitCount(hb) >= hb.target) continue;
    if (Date.now() - (hb.lastNudge || 0) < hb.every * 3600e3) continue;
    store.update(hb.id, { lastNudge: Date.now() });
    if (!hb.lastNudge) continue;      // first run just starts the clock
    const msg = `Time for ${/water/i.test(hb.title) ? 'a glass of water' : hb.title} — ${habitCount(hb)}/${hb.target} today`;
    chime(); showAlert('💧 ' + msg, 'Tap ＋ on the Home screen to log it'); speakSoon(`${who()}${msg}.`);
  }
}
// Water, coffee and medicine reminders (Settings → Water, coffee & medicine)
const HEALTH = {
  water: { icon: '💧', title: 'Water', say: n => `${n}time for a glass of water.`, show: 'Time for a glass of water', sub: 'Stay fresh!' },
  coffee: { icon: '☕', title: 'Coffee', say: n => `${n}coffee time! Take a little break.`, show: 'Coffee time', sub: 'A little break ☕' },
  meds: { icon: '💊', title: 'Medicine', say: (n, h) => `${n}it's time to take your ${h.name || 'medicine'}.`, show: h => `Time to take your ${h.name || 'medicine'}`, sub: '' },
};
const INTERVALS = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360];
const intervalText = m => m < 60 ? `${m} min` : m % 60 ? `${Math.floor(m / 60)}½ h` : `${m / 60} hour${m > 60 ? 's' : ''}`;
function checkHealth() {
  const all = S().health; if (!all) return;
  const now = new Date(), mins = now.getHours() * 60 + now.getMinutes();
  for (const kind of Object.keys(HEALTH)) {
    const h = all[kind]; if (!h?.on) continue;
    const from = minsOf(h.start || '00:00'), to = minsOf(h.end || '23:59');
    if (mins < from || mins >= to) continue;
    let due = false;
    if (h.mode === 'every') {
      const every = Math.max(1, +h.every || 120) * 60000;
      if (!h.last) { h.last = Date.now(); store.save(); continue; }        // starts counting from now
      due = Date.now() - h.last >= every;
    } else {
      const fired = S().healthFired || {};
      for (const tm of String(h.times || '').split(/[,\s]+/).filter(Boolean)) {
        const at = minsOf(tm), key = dayKey() + kind + tm;
        if (!fired[key] && mins >= at && mins - at < 15) { fired[key] = 1; S().healthFired = Object.fromEntries(Object.entries(fired).slice(-30)); due = true; }
      }
    }
    if (!due) continue;
    h.last = Date.now(); store.save();
    const def = HEALTH[kind], shown = typeof def.show === 'function' ? def.show(h) : def.show;
    if (M) M.post('health', { kind, text: shown });      // the Mac: the pet sparrow flies in carrying it
    chime(); showAlert(`${def.icon} ${shown}`, def.sub); speakSoon(def.say(who(), h));
  }
}
function renderHealthSettings(hl) {
  $('#healthList').innerHTML = Object.entries(HEALTH).map(([k, d]) => {
    const h = hl[k] || {};
    return `<div class="hl-card" data-hk="${k}">
      <label class="row hl-top"><input type="checkbox" data-f="on" ${h.on ? 'checked' : ''}> <span class="hl-ic">${d.icon}</span> <b>${d.title}</b></label>
      <div class="hl-body">
        ${k === 'meds' ? `<label class="field"><span>Name</span><input data-f="name" value="${esc(h.name || 'medicine')}"></label>` : ''}
        <div class="seg small hl-mode"><button data-mode="every" class="${h.mode === 'every' ? 'on' : ''}">Every…</button><button data-mode="times" class="${h.mode !== 'every' ? 'on' : ''}">At set times</button></div>
        <label class="field hl-every" ${h.mode === 'every' ? '' : 'hidden'}><span>Every</span><select data-f="every">${INTERVALS.map(m => `<option value="${m}" ${+h.every === m ? 'selected' : ''}>${intervalText(m)}</option>`).join('')}</select></label>
        <label class="field hl-times" ${h.mode === 'every' ? 'hidden' : ''}><span>Times (24h)</span><input data-f="times" value="${esc(h.times || '')}" placeholder="09:00, 13:00, 18:00"></label>
        <div class="row-2"><label class="field"><span>From</span><input type="time" data-f="start" value="${h.start || '09:00'}"></label><label class="field"><span>Until</span><input type="time" data-f="end" value="${h.end || '22:00'}"></label></div>
      </div></div>`;
  }).join('');
  $$('#healthList .hl-mode button').forEach(b => b.onclick = e => {
    e.preventDefault(); const card = b.closest('.hl-card');
    card.querySelectorAll('.hl-mode button').forEach(x => x.classList.toggle('on', x === b));
    card.querySelector('.hl-every').hidden = b.dataset.mode !== 'every'; card.querySelector('.hl-times').hidden = b.dataset.mode === 'every';
  });
}
function readHealthSettings(old) {
  const out = { ...old };
  $$('#healthList .hl-card').forEach(card => {
    const k = card.dataset.hk, f = n => card.querySelector(`[data-f="${n}"]`);
    const mode = card.querySelector('.hl-mode button.on')?.dataset.mode || 'every';
    const next = { ...(old[k] || {}), on: f('on').checked, mode, every: +f('every').value, times: f('times').value.trim(), start: f('start').value || '09:00', end: f('end').value || '22:00' };
    if (k === 'meds') next.name = f('name').value.trim() || 'medicine';
    if (next.mode !== old[k]?.mode || next.every !== old[k]?.every || !next.on) delete next.last;
    out[k] = next;
  });
  return out;
}
const minsOf = hm => { const [h, m] = (hm || '0:0').split(':').map(Number); return h * 60 + m; };
async function checkDaily() {
  if (M) return;    // the Mac island gives the morning briefing and evening check-in itself
  const d = new Date(), mins = d.getHours() * 60 + d.getMinutes();
  if (S().morningOn && S().lastMorning !== dayKey()) {
    const m = minsOf(S().morningTime);
    if (mins >= m && mins < Math.max(m + 240, 720)) { S().lastMorning = dayKey(); S().lastBriefDay = dayKey(); store.save(); showBriefing(true); return; }
  }
  if (S().nightOn && S().lastNight !== dayKey()) {
    const n = minsOf(S().nightTime);
    if (mins >= n && mins < n + 180) { S().lastNight = dayKey(); store.save(); openCheckIn(true); }
  }
}
setInterval(checkDue, 20000);
// Browsers only allow speech after one tap on the page; queue it until then.
let activated = false, queuedSpeech = null;
document.addEventListener('pointerdown', () => { activated = true; if (queuedSpeech) { const tx = queuedSpeech; queuedSpeech = null; speak(tx); } startWake(); }, { capture: true });
function speakSoon(text) { if (activated || N || D || M) speak(text); else queuedSpeech = text; }

// ---------------- evening check-in ----------------
function openCheckIn(spoken) {
  const list = tasksForDay(new Date());
  const doneToday = store.items.filter(i => i.type === 'task' && i.done && i.doneAt && new Date(i.doneAt).toDateString() === dayKey()).length;
  const hi = `Hi${S().name ? ' ' + S().name : ''}`;
  if (spoken && !list.length) {
    const msg = `${hi}, it's check-in time.${doneToday ? ` You finished ${doneToday} task${doneToday > 1 ? 's' : ''} today. Well done!` : ' Nothing left for today.'} Want to add anything for tomorrow? Just tell me.`;
    chime(); toast('🌙 ' + msg, 7000); speakSoon(msg); return;
  }
  $('#ciSub').textContent = doneToday ? `You finished ${doneToday} task${doneToday > 1 ? 's' : ''} today ✨` : 'How did today go?';
  const moved = new Set();
  const render = () => {
    const rows = [...new Map([...tasksForDay(new Date()), ...list].map(r => [r.id, store.items.find(x => x.id === r.id) || r])).values()];
    $('#ciList').innerHTML = rows.length ? rows.map(i => `<div class="ci-row ${i.done ? 'done' : ''} ${moved.has(i.id) ? 'moved' : ''}" data-id="${i.id}">
        <button class="check" data-ci="done">${i.done ? '✓' : ''}</button>
        <div class="txt"><div class="t1">${esc(i.title)}</div><div class="t2">${moved.has(i.id) ? 'Moved to tomorrow' : i.when ? whenText(i.when) : 'Added today'}</div></div>
        ${i.done || moved.has(i.id) ? '' : '<button class="chip" data-ci="tmr">↪ Tomorrow</button>'}</div>`).join('') : '<div class="empty">Nothing left for today 🎉</div>';
    const left = rows.filter(i => !i.done && !moved.has(i.id)).length;
    $('#ciGo').textContent = left ? `Move ${left} to tomorrow` : 'All done';
  };
  $('#ciList').onclick = e => {
    const b = e.target.closest('[data-ci]'); if (!b) return;
    const id = b.closest('.ci-row').dataset.id, it = store.items.find(x => x.id === id); if (!it) return;
    if (b.dataset.ci === 'done') { store.update(id, { done: !it.done, doneAt: it.done ? null : new Date().toISOString() }); if (it.done) { chirp(); mem.remember('done', it.title); } }
    else { moveToTomorrow(id); moved.add(id); }
    render();
  };
  $('#ciGo').onclick = () => {
    const left = tasksForDay(new Date()).filter(i => !moved.has(i.id));
    left.forEach(i => moveToTomorrow(i.id));
    const n = left.length + moved.size;
    closeSheets();
    const msg = n ? `Done. I moved ${n} task${n > 1 ? 's' : ''} to tomorrow. Sleep well${S().name ? ', ' + S().name : ''}!` : `Great job today${S().name ? ', ' + S().name : ''}! Sleep well.`;
    toast('🌙 ' + msg, 4000); speak(msg);
  };
  $('#ciLater').onclick = closeSheets;
  render(); openSheet('#checkin');
  if (spoken) {
    chime();
    speakSoon(`${hi}, it's check-in time.${doneToday ? ` You finished ${doneToday} task${doneToday > 1 ? 's' : ''} today. Nice work!` : ''} ${list.length === 1 ? 'One task is' : list.length + ' tasks are'} still open: ${spokenList(list.map(i => i.title))}. Tick the ones you finished, and I'll move the rest to tomorrow.`);
  }
}
$('#checkinBtn').onclick = () => openCheckIn(false);

// ---------------- sheets ----------------
function openSheet(sel) { $$('.sheet').forEach(s => s.hidden = true); $(sel).hidden = false; $('#sheetBg').hidden = false; }
function closeSheets() {
  if (!$('#sheet').hidden) saveSettings();
  $$('.sheet').forEach(s => s.hidden = true); $('#sheetBg').hidden = true;
  panelCleanup?.(); panelCleanup = null;
}
$('#sheetBg').onclick = closeSheets;
$('#panelClose').onclick = closeSheets;
document.addEventListener('keydown', e => { if (e.key === 'Escape') { if (!$('#focus').hidden) return; closeSheets(); } });
let panelCleanup = null;
function openPanel(title, html, cleanup) { $('#panelTitle').textContent = title; $('#panelBody').innerHTML = html; panelCleanup = cleanup || null; openSheet('#panel'); return $('#panelBody'); }

// ---------------- memory view ----------------
let memKinds = null;
$$('#memSeg button').forEach(b => b.onclick = () => { memKinds = b.dataset.k ? b.dataset.k.split(',') : null; $$('#memSeg button').forEach(x => x.classList.toggle('on', x === b)); renderMemory(); });
let memT; $('#memSearch').oninput = () => { clearTimeout(memT); memT = setTimeout(renderMemory, 250); };
async function renderMemory() {
  const q = $('#memSearch').value.trim();
  let rows;
  if (q) { const { dateRange } = await import('./brain.js'); const r = dateRange(q); rows = await mem.search({ q: r ? q.replace(/\b(today|yesterday|last|this|week|month|year|on|in)\b/gi, '') : q, from: r?.[0] || 0, to: r?.[1] || Infinity, kinds: memKinds, limit: 200 }); }
  else rows = (await mem.recent(300)).filter(r => !memKinds || memKinds.includes(r.kind));
  if (!S().memory.on) { $('#memList').innerHTML = '<div class="card empty">Memory is paused. Turn it on in Settings → Memory.</div>'; return; }
  if (!rows.length) { $('#memList').innerHTML = `<div class="card empty">${q ? 'Nothing found.' : 'Nothing remembered yet.<br>Chats, files you drop, tasks and quotes appear here.'}</div>`; return; }
  const byDay = {};
  rows.sort((a, b) => b.at - a.at).forEach(r => { const k = new Date(r.at).toDateString(); (byDay[k] = byDay[k] || []).push(r); });
  $('#memList').innerHTML = Object.entries(byDay).map(([day, list]) => `<div class="mem-day">${fmtDay(new Date(day))}${fmtDay(new Date(day)).length > 10 ? '' : ' · ' + new Date(day).toLocaleDateString([], { day: 'numeric', month: 'short' })}</div>
    <div class="card list">${list.map(r => `<div class="item" data-mid="${r.id}"><div class="ic">${ICON[r.kind] || '•'}</div><div class="txt"><div class="t1">${esc(r.title)}</div><div class="t2">${new Date(r.at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })} · ${esc(r.kind)}${r.text && r.kind !== 'chat' ? ' · ' + esc(r.text.slice(0, 60)) : ''}</div></div>
      <div class="acts">${r.meta?.fileId ? `<button data-mfile="${r.meta.fileId}" title="Open">📂</button><button data-mask="${r.meta.fileId}" title="Ask about it">💬</button>` : ''}<button data-mdel="${r.id}" title="Forget">🗑️</button></div></div>`).join('')}</div>`).join('');
}
$('#memList').onclick = async e => {
  const b = e.target.closest('button'); if (!b) return;
  if (b.dataset.mdel) { await mem.forget(+b.dataset.mdel); renderMemory(); }
  if (b.dataset.mfile) { const f = await mem.getFile(b.dataset.mfile); if (f?.blob) tools.deliver(f.name, new Uint8Array(await f.blob.arrayBuffer()), f.type); else toast('Zuffi didn’t keep a copy of this file. Turn on “Keep a copy” in Settings → Memory.', 5000); }
  if (b.dataset.mask) { activeDocs = [b.dataset.mask]; go('chat'); $('#askInput').placeholder = 'Ask about this file…'; $('#askInput').focus(); }
};

// ---------------- tools ----------------
$$('.tool').forEach(b => b.onclick = () => openTool(b.dataset.tool));
function pickFiles(accept, multiple = true) {
  return new Promise(res => { const i = $('#toolFile'); i.accept = accept; i.multiple = multiple; i.value = ''; i.onchange = () => res([...i.files]); i.click(); });
}
function updateTimerLabel() { const r = tools.runningTimer(); $('#timerLbl').textContent = r ? `⏹ ${r.title} · ${tools.fmtHours(tools.hours(r))}` : 'Time tracker'; }
setInterval(updateTimerLabel, 30000);
async function openTool(name) {
  if (name === 'jobs') { jobs.openJobs(); return; }
  const P = $('#toolPanel'); P.hidden = false;
  const done = html => { P.innerHTML = html; P.scrollIntoView({ behavior: 'smooth', block: 'start' }); };
  const cur = S().business.currency;
  if (name === 'quote') {
    done(`<h3>🧾 Quote or invoice</h3><p class="small-text">Type it like you'd say it. A PDF is made on this device.</p>
      <select id="qKind"><option>Quote</option><option>Invoice</option></select>
      <input id="qCust" placeholder="Customer name">
      <textarea class="field-in" id="qLines" placeholder="One line each, e.g.\n3 hours web design at 40\nHosting 20"></textarea>
      <button class="btn" id="qGo">Make PDF</button>${!S().business.name ? '<p class="small-text">Tip: add your business name in Settings → Business.</p>' : ''}`);
    $('#qGo').onclick = async () => {
      const text = `${$('#qKind').value} for ${$('#qCust').value || 'Customer'}, ${$('#qLines').value.split('\n').filter(Boolean).join(', ')}`;
      const r = await handle(text); toast(r?.reply?.split('\n')[0] || 'Done', 5000);
    };
  }
  if (name === 'timer') {
    const r = tools.runningTimer();
    const week = store.items.filter(i => i.type === 'timer' && i.start > Date.now() - 7 * 86400e3);
    const byLabel = {}; week.forEach(i => byLabel[i.title] = (byLabel[i.title] || 0) + tools.hours(i));
    done(`<h3>⏱️ Time tracker</h3>${r ? `<p><b>Running:</b> ${esc(r.title)} · ${tools.fmtHours(tools.hours(r))}</p><button class="btn" id="tStop">Stop</button>`
      : `<input id="tLabel" placeholder="What are you working on? e.g. Ali website"><button class="btn" id="tStart">Start</button>`}
      <p class="small-text" style="margin-top:14px"><b>This week</b></p>${Object.entries(byLabel).map(([k, v]) => `<div class="res-row"><div class="txt"><div class="t1">${esc(k)}</div></div><b>${tools.fmtHours(v)}</b></div>`).join('') || '<p class="small-text">No time tracked yet.</p>'}
      <p class="small-text">Then say “invoice Ali at £40” — tracked hours go straight onto the invoice.</p>`);
    $('#tStart') && ($('#tStart').onclick = () => { tools.startTimer($('#tLabel').value || 'Work'); updateTimerLabel(); openTool('timer'); });
    $('#tStop') && ($('#tStop').onclick = () => { tools.stopTimer(); updateTimerLabel(); openTool('timer'); });
  }
  if (name === 'expenses') {
    const ex = tools.monthExpenses(), total = ex.reduce((n, i) => n + (+i.amount || 0), 0);
    done(`<h3>💸 Expenses this month · ${cur}${total.toFixed(2)}</h3>
      <div class="row-btns"><input id="exWhat" placeholder="What for?"><input id="exAmt" placeholder="Amount" inputmode="decimal" style="max-width:110px"></div>
      <button class="btn" id="exAdd">Add expense</button>
      ${ex.map(i => `<div class="res-row"><div class="txt"><div class="t1">${esc(i.title)}</div><div class="t2">${new Date(i.created).toLocaleDateString()}</div></div><b>${cur}${(+i.amount).toFixed(2)}</b></div>`).join('')}
      <button class="btn ghost" id="exCsv">⬇️ Export all expenses (CSV for Excel)</button>`);
    $('#exAdd').onclick = () => { const a = parseFloat($('#exAmt').value); if (!a) return; store.add({ type: 'expense', title: $('#exWhat').value || 'Expense', amount: a }); mem.remember('expense', `${$('#exWhat').value}: ${a}`); openTool('expenses'); };
    $('#exCsv').onclick = () => tools.deliver(`expenses-${new Date().toISOString().slice(0, 7)}.csv`, new TextEncoder().encode(tools.csv([['Date', 'What', 'Amount'], ...store.ofType('expense').map(i => [new Date(i.created).toLocaleDateString(), i.title, i.amount])])), 'text/csv');
  }
  if (name === 'report') openReport();
  if (name === 'focus') { const m = parseInt(prompt('Focus for how many minutes?', '25'), 10); if (m) startFocus(m); }
  if (name === 'meeting') startMeetingNotes();
  if (name === 'sync') openSync();
  if (name === 'merge') { const f = await pickFiles('application/pdf'); if (f.length < 2) return toast('Pick two or more PDFs'); toast('Merging…'); tools.deliver('Merged.pdf', await tools.mergePDFs(f), 'application/pdf'); mem.remember('file', 'Merged PDF: ' + f.map(x => x.name).join(', ')); }
  if (name === 'images') { const f = await pickFiles('image/*'); if (!f.length) return; toast('Making PDF…'); tools.deliver('Photos.pdf', await tools.imagesToPDF(f), 'application/pdf'); }
  if (name === 'pages') { const [f] = await pickFiles('application/pdf', false); if (!f) return; const spec = prompt('Which pages to keep? e.g. 1-3, 5', '1'); if (!spec) return; tools.deliver(f.name.replace(/\.pdf$/i, '') + ' (pages).pdf', await tools.extractPages(f, spec), 'application/pdf'); }
  if (name === 'rotate') { const [f] = await pickFiles('application/pdf', false); if (!f) return; tools.deliver(f.name.replace(/\.pdf$/i, '') + ' (rotated).pdf', await tools.rotatePDF(f, 90), 'application/pdf'); }
  if (name === 'snippets') {
    const list = S().snippets || [];
    done(`<h3>📋 Snippets</h3><p class="small-text">Text you paste often — addresses, bank details, standard replies.</p>
      ${list.map((s, i) => `<div class="res-row"><div class="txt"><div class="t1">${esc(s.name)}</div><div class="t2">${esc(s.text.slice(0, 70))}</div></div><button data-sc="${i}">Copy</button><button data-sd="${i}">✕</button></div>`).join('') || ''}
      <input id="snName" placeholder="Name, e.g. Bank details"><textarea class="field-in" id="snText" placeholder="The text"></textarea><button class="btn" id="snAdd">Save snippet</button>`);
    P.onclick = async e => {
      const b = e.target.closest('button'); if (!b) return;
      if (b.dataset.sc) { try { await navigator.clipboard.writeText(list[+b.dataset.sc].text); } catch { D?.clips('copy', list[+b.dataset.sc].text); } toast('Copied'); }
      if (b.dataset.sd) { S().snippets = list.filter((_, i) => i !== +b.dataset.sd); store.save(); openTool('snippets'); }
      if (b.id === 'snAdd' && $('#snName').value && $('#snText').value) { S().snippets = [...list, { name: $('#snName').value, text: $('#snText').value }]; store.save(); openTool('snippets'); }
    };
    return;
  }
  if (name === 'find' && D) {
    done(`<h3>📁 Find files</h3><input id="fQ" placeholder="e.g. invoice Ali, contract, CV" enterkeyhint="search"><div id="fRes"></div>`);
    $('#fQ').onkeydown = async e => { if (e.key !== 'Enter') return; $('#fRes').innerHTML = '<p class="small-text">Searching…</p>'; const files = await D.findFiles($('#fQ').value);
      $('#fRes').innerHTML = files.map(f => `<div class="res-row"><div class="txt"><div class="t1">${esc(f.name)}</div><div class="t2">${new Date(f.mtime).toLocaleDateString()}</div></div><button data-o="${esc(f.path)}">Open</button><button data-r="${esc(f.path)}">Show</button></div>`).join('') || '<p class="small-text">Nothing found.</p>'; };
    $('#fQ').focus();
    P.onclick = e => { const b = e.target.closest('button'); if (b?.dataset.o) D.openPath(b.dataset.o); if (b?.dataset.r) D.openPath(b.dataset.r, true); };
    return;
  }
  if (name === 'tidy' && D) {
    const plan = await D.tidyDownloads(false), total = Object.values(plan).reduce((a, b) => a + b, 0);
    done(`<h3>🧹 Tidy Downloads</h3>${total ? `<p>I'll sort <b>${total}</b> files into folders inside Downloads:</p><p class="small-text">${Object.entries(plan).map(([k, v]) => `${k}: ${v}`).join(' · ')}</p><button class="btn" id="tdGo">Tidy now</button>` : '<p>Your Downloads folder is already tidy ✨</p>'}`);
    $('#tdGo') && ($('#tdGo').onclick = async () => { await D.tidyDownloads(true); toast('Downloads tidied 🧹'); openTool('tidy'); });
  }
  if (name === 'clipboard' && D) {
    const clips = await D.clips('get');
    done(`<h3>📎 Clipboard history</h3><p class="small-text">The last things you copied, kept on this computer only.</p>${clips.slice(0, 30).map((c, i) => `<div class="res-row"><div class="txt"><div class="t1">${esc(c.text.slice(0, 90))}</div><div class="t2">${new Date(c.at).toLocaleString([], { hour: 'numeric', minute: '2-digit', day: 'numeric', month: 'short' })}</div></div><button data-ci="${i}">Copy</button></div>`).join('') || '<p class="small-text">Nothing yet — copy something.</p>'}
      <button class="btn ghost" id="clClear">Clear history</button>`);
    P.onclick = async e => { const b = e.target.closest('button'); if (!b) return; if (b.dataset.ci !== undefined) { D.clips('copy', clips[+b.dataset.ci].text); toast('Copied'); } if (b.id === 'clClear') { await D.clips('clear'); openTool('clipboard'); } };
    return;
  }
  if (name === 'watch' && D) {
    const st = await D.getSettings();
    done(`<h3>👀 Watch a folder</h3><p class="small-text">I'll tell you when a new file arrives — e.g. your Invoices or Downloads folder.</p>
      ${(st.watch || []).map(d => `<div class="res-row"><div class="txt"><div class="t1">${esc(d.split(/[\\/]/).pop())}</div><div class="t2">${esc(d)}</div></div><button data-wr="${esc(d)}">Stop</button></div>`).join('')}
      <button class="btn" id="wAdd">＋ Choose a folder</button>`);
    P.onclick = async e => { const b = e.target.closest('button'); if (!b) return; if (b.id === 'wAdd') { const d = await D.pickFolder(); if (d) { await D.watch('add', d); openTool('watch'); } } if (b.dataset.wr) { await D.watch('remove', b.dataset.wr); openTool('watch'); } };
    return;
  }
  P.onclick = null;
}

// ---------------- daily report ----------------
function buildReport() {
  const tdy = dayKey(), on = d => d && new Date(d).toDateString() === tdy;
  const done = store.items.filter(i => i.done && on(i.doneAt));
  const meetings = store.onDay(new Date()).filter(i => i.type === 'meeting');
  const timers = store.items.filter(i => i.type === 'timer' && on(i.start));
  const byLabel = {}; timers.forEach(i => byLabel[i.title] = (byLabel[i.title] || 0) + tools.hours(i));
  const docs = store.items.filter(i => ['quote', 'invoice'].includes(i.type) && on(i.created));
  const ex = store.items.filter(i => i.type === 'expense' && on(i.created));
  const open = tasksForDay(new Date());
  const L = [`Daily report — ${new Date().toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' })}${S().name ? ' — ' + S().name : ''}`, ''];
  L.push('Completed:', ...(done.length ? done.map(i => '• ' + i.title) : ['• —']), '');
  if (meetings.length) L.push('Meetings:', ...meetings.map(m => `• ${fmtTime(m.when)} ${m.title}`), '');
  if (timers.length) L.push('Time:', ...Object.entries(byLabel).map(([k, v]) => `• ${k}: ${tools.fmtHours(v)}`), '');
  if (docs.length) L.push('Quotes & invoices:', ...docs.map(d => `• ${d.title} — ${S().business.currency}${(+d.total).toFixed(2)}`), '');
  if (ex.length) L.push('Expenses:', ...ex.map(e => `• ${e.title} — ${S().business.currency}${(+e.amount).toFixed(2)}`), '');
  L.push('Still open:', ...(open.length ? open.map(i => '• ' + i.title) : ['• Nothing — all clear!']));
  return L.join('\n');
}
function openReport() {
  const text = buildReport();
  const body = openPanel('📊 Daily report', `<div class="report">${esc(text)}</div><div class="row-btns"><button class="btn ghost" id="rpCopy">📋 Copy</button><button class="btn" id="rpShare">Share</button></div>`);
  body.querySelector('#rpCopy').onclick = async () => { try { await navigator.clipboard.writeText(text); } catch { D?.clips('copy', text); } toast('Copied'); };
  body.querySelector('#rpShare').onclick = async () => { if (navigator.share) { try { await navigator.share({ text }); } catch {} } else openUrl('mailto:?subject=' + encodeURIComponent('Daily report') + '&body=' + encodeURIComponent(text)); };
  mem.remember('report', 'Daily report', text);
}

// ---------------- focus ----------------
let focusEnd = 0, focusTotal = 0;
function startFocus(min) { focusTotal = min * 60000; focusEnd = Date.now() + focusTotal; $('#focus').hidden = false; tickFocus(); }
function tickFocus() {
  if ($('#focus').hidden) return;
  const left = Math.max(0, focusEnd - Date.now());
  $('#focusTime').textContent = `${String(Math.floor(left / 60000)).padStart(2, '0')}:${String(Math.floor(left / 1000) % 60).padStart(2, '0')}`;
  $('#focusArc').style.strokeDashoffset = String(339.3 * (1 - left / focusTotal));
  if (left <= 0) { $('#focus').hidden = true; chime(); const msg = `${who()}great focus! Time for a short break.`; showAlert('🎯 Focus done', 'Stretch, drink some water 💧'); speak(msg); return; }
  setTimeout(tickFocus, 1000);
}
function checkFocus() { if (!$('#focus').hidden) tickFocus(); }
$('#focusStop').onclick = () => { $('#focus').hidden = true; };

// ---------------- meeting notes ----------------
let meeting = null;
function startMeetingNotes() {
  const desktopVoice = window.SparrowVoice?.dictate;
  if (!desktopVoice && !SR) { addMsg('bot', N ? 'Meeting notes need the Mac/Windows app or Chrome for now. Coming to the Android app soon.' : 'Meeting notes aren’t supported in this browser — use Chrome, or the Mac/Windows app.'); go('chat'); return; }
  let finalText = '', partial = '';
  const body = openPanel('🎤 Meeting notes', `<p class="small-text">Listening… everything is written ${desktopVoice ? 'on this computer, offline' : 'by your browser'}. Press Stop when the meeting ends.</p><div class="live" id="live"></div><button class="btn" id="mnStop">⏹ Stop & save</button>`, () => meeting?.stop());
  const live = body.querySelector('#live');
  const show = () => { live.innerHTML = esc(finalText) + `<span class="partial">${esc(partial)}</span>`; live.scrollTop = live.scrollHeight; };
  const onText = (tx, isFinal) => { if (isFinal) { finalText += (finalText ? ' ' : '') + tx; partial = ''; } else partial = ' ' + tx; show(); };
  let stopFn;
  if (desktopVoice) stopFn = window.SparrowVoice.dictate(onText);
  else {
    stopWake();
    let on = true; const r = new SR(); r.continuous = true; r.interimResults = true; r.lang = SPEECH_LANG[S().lang] || 'en-GB';
    r.onresult = e => { for (let i = e.resultIndex; i < e.results.length; i++) onText(e.results[i][0].transcript.trim(), e.results[i].isFinal); };
    r.onend = () => { if (on) try { r.start(); } catch {} };
    try { r.start(); } catch {}
    stopFn = () => { on = false; try { r.stop(); } catch {} };
  }
  meeting = { stop: () => { stopFn?.(); meeting = null; } };
  body.querySelector('#mnStop').onclick = () => finishMeeting(finalText + partial);
}
function stopMeetingNotes() { const live = $('#live'); finishMeeting(live ? live.textContent : ''); }
function finishMeeting(text) {
  meeting?.stop();
  text = text.trim();
  if (!text) { closeSheets(); toast('Nothing was heard.'); return; }
  const title = `Meeting notes – ${new Date().toLocaleString([], { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' })}`;
  store.add({ type: 'note', title, text });
  mem.remember('meeting-notes', title, text);
  const items = tools.actionItems(text);
  const body = openPanel('🎤 Saved', `<p>Saved as a note and in your memory.</p>${items.length ? `<p class="small-text"><b>Action items I spotted</b> — tick to add as tasks:</p>${items.map((a, i) => `<label class="row"><input type="checkbox" data-ai="${i}" checked> ${esc(a)}</label>`).join('')}<button class="btn" id="aiAdd">Add as tasks</button>` : ''}<button class="btn ghost" id="mnSum">✨ Summarise with AI</button>`);
  body.querySelector('#aiAdd')?.addEventListener('click', () => { body.querySelectorAll('[data-ai]:checked').forEach(c => store.add({ type: 'task', title: items[+c.dataset.ai].slice(0, 120) })); toast('Tasks added ✅'); closeSheets(); });
  body.querySelector('#mnSum').onclick = async () => { closeSheets(); go('chat'); addMsg('me', 'Summarise my meeting notes'); try { const r = await ask('Summarise these meeting notes in short bullet points, then list action items with owners if mentioned.', null, { context: text, noHistory: true }); addMsg('bot', r.text, { src: r.source }); } catch (e) { addMsg('bot', e.message === 'NO_AI' ? 'Turn on an AI in Settings → AI to get summaries.' : '⚠️ ' + e.message, e.message === 'NO_AI' ? { action: 'ai' } : {}); } };
}

// ---------------- sync ----------------
function openSync() {
  const body = openPanel('🔁 Sync devices', `<p class="small-text">Copy your tasks, reminders, notes, customers and habits between your phone and computer — no account, nothing goes online.</p>
    <div class="row-btns"><button class="btn" id="syShow">Show my QR code</button><button class="btn ghost" id="syScan">Scan a QR code</button></div>
    <div id="syArea"></div>
    <div class="row-btns"><button class="btn ghost" id="syFile">Save sync file</button><button class="btn ghost" id="syOpen">Open sync file</button></div>
    <label class="row"><input type="checkbox" id="syMem"> Include memory (text only)</label>`, () => { abort?.abort(); clearInterval(cycle); });
  let abort = null, cycle = null;
  body.querySelector('#syShow').onclick = async () => {
    const codes = await sync.qrCodes(await sync.bundle($('#syMem').checked));
    let i = 0; const area = body.querySelector('#syArea');
    const show = () => { area.innerHTML = `<div class="qr-box">${codes[i]}</div><p class="small-text center">${codes.length > 1 ? `Code ${i + 1} of ${codes.length} — keep it in view, it changes by itself` : 'Scan this with Zuffi on your other device (Tools → Sync → Scan)'}</p>`; i = (i + 1) % codes.length; };
    clearInterval(cycle); show(); if (codes.length > 1) cycle = setInterval(show, 900);
  };
  body.querySelector('#syScan').onclick = async () => {
    const area = body.querySelector('#syArea');
    area.innerHTML = `<video class="scan" playsinline muted></video><p class="small-text center" id="syProg">Point the camera at the QR code…</p>`;
    abort = new AbortController();
    try {
      const data = await sync.scan(area.querySelector('video'), (got, total) => { area.querySelector('#syProg').textContent = `Got ${got} of ${total}…`; }, abort.signal);
      const r = await sync.applyBundle(data);
      area.innerHTML = `<p>✅ Synced: ${r.added} new, ${r.changed} updated.</p>`; renderAll();
    } catch (e) { if (e.message !== 'cancelled') area.innerHTML = `<p class="small-text">⚠️ ${esc(e.message)} — allow the camera, or use a sync file.</p>`; }
  };
  body.querySelector('#syFile').onclick = async () => tools.deliver(`sparrow-sync-${new Date().toISOString().slice(0, 10)}.sparrow`, new TextEncoder().encode(await sync.bundle($('#syMem').checked)), 'application/octet-stream');
  body.querySelector('#syOpen').onclick = async () => { const [f] = await pickFiles('', false); if (!f) return; try { const r = await sync.applyBundle((await f.text()).trim()); toast(`✅ Synced: ${r.added} new, ${r.changed} updated`); renderAll(); } catch { toast('That isn’t a Zuffi sync file.'); } };
}

// ---------------- settings ----------------
const PROVIDER_ORDER = Object.keys(PROVIDERS);
function fillSettings() {
  const s = S();
  $('#sName').value = s.name; $('#sCity').value = s.city;
  $('#sLang').innerHTML = Object.entries(LANGS).map(([k, v]) => `<option value="${k}">${v}</option>`).join(''); $('#sLang').value = s.lang;
  $$('#sTheme button').forEach(b => b.classList.toggle('on', b.dataset.th === s.theme));
  $('#sSimple').checked = s.simple; $('#sSpeak').checked = s.speak; $('#sWake').checked = s.wake; $('#sConv').checked = s.conversation; $('#sMic').checked = s.micButton !== false;
  $('#sLive').checked = s.liveMode !== false; $('#sLiveVoice').value = s.liveVoice || 'Kore';
  $$('#sGender button').forEach(b => b.classList.toggle('on', b.dataset.g === s.gender));
  $('#sVoiceName').innerHTML = '<option value="">Automatic</option>' + Object.entries(nv.KOKORO_VOICES).map(([k, v]) => `<option value="${k}">${v}</option>`).join('');
  $('#sVoiceName').value = s.voiceName || ''; $('#sNeural').checked = s.neural !== false; $('#sHandsFree').checked = s.handsFree === true; $('#handsFreeRow').hidden = !M;
  $('#macVoice').hidden = !M;
  if (M) {
    $('#sListen').value = s.listen || ''; $('#sStudio').checked = !!s.studio;
    M.call('studio', {}).then(st => { $('#studioNote').textContent = st?.installed ? (st.running ? '✅ Studio voice is installed and running.' : '✅ Installed — it starts when you switch it on.') : 'Not installed. It downloads about 4 GB once (OmniVoice), then works offline.'; $('#studioInstall').hidden = !!st?.installed; });
  }
  $('#wakeNote').textContent = N ? 'On Android, also switch on “Listen for Zuffi” under Android powers.' : D ? 'Works offline on this computer.' : isIOS ? 'On iPhone, Zuffi listens while the app is open. Apple doesn’t allow listening in the background.' : 'Zuffi listens while the app is open.';
  $('#rMorningOn').checked = s.morningOn; $('#rMorning').value = s.morningTime; $('#rNightOn').checked = s.nightOn; $('#rNight').value = s.nightTime; $('#rLead').value = String(s.lead);
  $('#pMethod').innerHTML = Object.entries(METHODS).map(([k, v]) => `<option value="${k}">${v.name}</option>`).join('');
  const hl = s.health || {};
  renderHealthSettings(hl);
  $('#pOn').checked = s.prayer.on; $('#pMethod').value = s.prayer.method; $('#pAsr').value = s.prayer.asr; $('#pBefore').value = String(s.prayer.before); $('#pSpeak').checked = s.prayer.speak;
  $('#sProvider').innerHTML = `<option value="auto">Automatic (free first)</option>${D ? '<option value="ollama">Ollama on this computer</option>' : '<option value="local">Free AI on this device</option>'}` + PROVIDER_ORDER.map(p => `<option value="${p}">${PROVIDERS[p].name}</option>`).join('');
  $('#sProvider').value = s.provider || 'auto';
  $('#sModel').value = s.model;
  $('#keyFields').innerHTML = PROVIDER_ORDER.map(p => `<label class="field"><span>${PROVIDERS[p].name}</span><div class="key-row"><input type="password" data-key="${p}" value="${esc(s.keys[p] || '')}" placeholder="API key" autocomplete="off"><a href="${PROVIDERS[p].site}" target="_blank" rel="noopener">Get a key</a></div></label>`).join('');
  $('#bName').value = s.business.name; $('#bAddr').value = s.business.address; $('#bCur').value = s.business.currency; $('#sMusic').value = s.musicApp;
  $('#mOn').checked = s.memory.on; $('#mCopies').checked = s.memory.keepCopies; $('#mDays').value = String(s.memory.days); $('#mRecent').checked = s.memory.recentFiles;
}
async function openSettings(section) {
  fillSettings(); openSheet('#sheet');
  if (section === 'ai') { const d = $$('#sheet details').find(x => x.querySelector('summary').textContent.includes('AI')); if (d) { d.open = true; setTimeout(() => d.scrollIntoView({ behavior: 'smooth' }), 100); } }
  refreshAiStatus(); refreshAndroid();
  if (D) {
    const list = await ollamaModels();
    $('#sOllama').innerHTML = '<option value="">Automatic</option>' + list.map(m => `<option>${esc(m)}</option>`).join(''); $('#sOllama').value = S().ollamaModel || '';
    $('#ollamaNote').innerHTML = list.length ? `✅ Ollama is running with ${list.length} model${list.length > 1 ? 's' : ''}. Free and private.` : 'Not found. Install the free <a href="https://ollama.com/download" target="_blank" rel="noopener">Ollama app</a>, then run “ollama pull llama3.2”.';
  }
}
function saveSettings() {
  const s = S();
  s.name = $('#sName').value.trim(); s.city = $('#sCity').value.trim(); s.lang = $('#sLang').value; s.simple = $('#sSimple').checked;
  s.voiceName = $('#sVoiceName').value; s.neural = $('#sNeural').checked; s.handsFree = $('#sHandsFree').checked;
  if (M) { s.listen = $('#sListen').value; s.studio = $('#sStudio').checked; }
  s.speak = $('#sSpeak').checked; s.wake = $('#sWake').checked; s.conversation = $('#sConv').checked; s.micButton = $('#sMic').checked;
  s.liveMode = $('#sLive').checked; s.liveVoice = $('#sLiveVoice').value;
  s.morningOn = $('#rMorningOn').checked; s.morningTime = $('#rMorning').value || '08:30'; s.nightOn = $('#rNightOn').checked; s.nightTime = $('#rNight').value || '21:30'; s.lead = +$('#rLead').value;
  s.health = readHealthSettings(s.health || {});
  s.prayer = { ...s.prayer, on: $('#pOn').checked, method: $('#pMethod').value, asr: $('#pAsr').value, before: +$('#pBefore').value, speak: $('#pSpeak').checked };
  s.provider = $('#sProvider').value; s.model = $('#sModel').value; if (D) s.ollamaModel = $('#sOllama').value;
  $$('#keyFields [data-key]').forEach(i => s.keys[i.dataset.key] = i.value.trim());
  s.business = { ...s.business, name: $('#bName').value.trim(), address: $('#bAddr').value.trim(), currency: $('#bCur').value }; s.musicApp = $('#sMusic').value;
  s.memory = { ...s.memory, on: $('#mOn').checked, keepCopies: $('#mCopies').checked, days: +$('#mDays').value, recentFiles: $('#mRecent').checked };
  store.save(); renderAll(); sendVoicePrefs();
  if (s.wake) startWake(); else stopWake();
  window.SparrowVoice && (s.wake ? window.SparrowVoice.startWake() : window.SparrowVoice.stopWake());
}
$('#settingsBtn').onclick = () => openSettings();
$('#closeSheet').onclick = closeSheets;
$$('#sTheme button').forEach(b => b.onclick = () => { S().theme = b.dataset.th; $$('#sTheme button').forEach(x => x.classList.toggle('on', x === b)); applyLook(); store.save(); });
$('#sSimple').onchange = e => { S().simple = e.target.checked; applyLook(); };
$('#sLang').onchange = e => { S().lang = e.target.value; applyLook(); renderHeader(); };
$$('#sGender button').forEach(b => b.onclick = () => { S().gender = b.dataset.g; $$('#sGender button').forEach(x => x.classList.toggle('on', x === b)); store.save(); sendVoicePrefs(); });
$('#studioInstall').onclick = () => { M?.post('studio', { action: 'install' }); toast('A Terminal window opens and installs the Studio voice — keep it open until it says ✅.', 7000); };
$('#sVoiceName').onchange = e => { S().voiceName = e.target.value; store.save(); sendVoicePrefs(); };
$('#sLang').addEventListener('change', () => { store.save(); sendVoicePrefs(); });
$('#testVoice').onclick = () => speak(S().lang === 'ur' ? 'السلام علیکم! میں سپیرو ہوں۔ آپ کی کیا مدد کروں؟' : S().lang === 'hi' ? 'नमस्ते! मैं स्पैरो हूँ। बताइए, मैं क्या मदद करूँ?' : S().lang === 'pa' ? 'ਸਤ ਸ੍ਰੀ ਅਕਾਲ! ਮੈਂ ਸਪੈਰੋ ਹਾਂ। ਦੱਸੋ, ਮੈਂ ਕੀ ਮਦਦ ਕਰਾਂ?' : `Hi${S().name ? ' ' + S().name : ''}! I'm Zuffi. Ready when you are.`);
$('#pCalendar').onclick = async () => { const l = await getLocation(); if (!l) return toast('I need your location or city first.'); downloadICS(prayerICS(l.lat, l.lon, 30), 'Prayer times'); };
$('#exportBtn').onclick = () => tools.deliver('sparrow-backup.json', new TextEncoder().encode(JSON.stringify({ items: store.items, settings: { ...S(), keys: undefined } }, null, 2)), 'application/json');
$('#clearBtn').onclick = () => { if (confirm('Delete all your tasks, meetings, reminders, notes and chat?')) { store.clearAll(); renderChat(); toast('Everything deleted'); } };
$('#mExport').onclick = async () => tools.deliver('sparrow-memory.json', new TextEncoder().encode(JSON.stringify(await mem.exportMemory())), 'application/json');
$('#mWipe').onclick = async () => { if (confirm('Forget everything Zuffi remembers (files and history)?')) { await mem.forgetAll(); toast('Memory wiped'); renderMemory(); } };

async function refreshAiStatus() {
  if (D) return;
  const st = $('#aiStatus'), btn = $('#aiDownload');
  if (S().aiReady) { st.textContent = '✅ Free on-device AI is downloaded. It works offline.'; btn.hidden = true; return; }
  const sup = await deviceSupport();
  if (!sup.ok) { st.textContent = '⚠️ ' + sup.why; btn.disabled = true; return; }
  btn.disabled = false; btn.hidden = false;
  st.textContent = 'Your device can run a free AI. It downloads once (use Wi-Fi), then works offline. Nothing you say leaves your device.';
}
$('#aiDownload').onclick = async () => {
  const bar = $('#aiProgress'), btn = $('#aiDownload');
  S().model = $('#sModel').value; store.save();
  bar.hidden = false; btn.disabled = true; btn.textContent = 'Downloading…';
  try {
    await loadLocal((p, txt) => { bar.firstElementChild.style.width = Math.round(p * 100) + '%'; $('#aiStatus').textContent = txt.slice(0, 90); });
    btn.textContent = 'Ready ✅'; toast('Free AI ready 🐦'); refreshAiStatus();
  } catch (e) { btn.disabled = false; btn.textContent = '⬇️ Try again'; $('#aiStatus').textContent = '⚠️ ' + e.message; }
};

// ---------------- toast ----------------
let toastT;
function toast(text, ms = 2600) { const el = $('#toast'); el.textContent = text; el.hidden = false; clearTimeout(toastT); toastT = setTimeout(() => el.hidden = true, ms); }

// ---------------- install hint ----------------
function installHint() {
  if (N || D) return;
  if (matchMedia('(display-mode: standalone)').matches || navigator.standalone) return;
  const el = $('#installHint'); el.hidden = false;
  el.innerHTML = isIOS ? '📲 <b>Install Zuffi:</b> tap <b>Share</b> in Safari, then <b>“Add to Home Screen”</b>.'
    : isAndroid ? '📲 <b>Get the full Android app</b> (floating sparrow, hands-free voice, alarms): <a href="https://github.com/MuhammadTalha257/sparrow/releases/download/latest/Sparrow.apk">download Sparrow.apk</a>'
    : '💻 <b>Get Zuffi for your computer</b> — hands-free “Zuffi…”, files, clipboard and more: <a href="get.html">download for Mac or Windows</a>';
}

// ---------------- Android app ----------------
window.sparrowEvent = raw => {
  const e = typeof raw === 'string' ? JSON.parse(raw) : raw;
  if (e.type === 'speech') submit(e.text, true);
  else if (e.type === 'ask') submit(e.text, !!e.voice);
  else if (e.type === 'partial') $('#askInput').value = e.text;
  else if (e.type === 'listening') { $('#micBtn').classList.toggle('on', e.on); $('#pulse').classList.toggle('on', e.on); setBird('listening', e.on); if (e.on) chirp(); }
  else if (e.type === 'speaking') { setBird('talking', e.on); if (!e.on) afterSpeech(); }
  else if (e.type === 'toast') toast(e.text);
  else if (e.type === 'status') refreshAndroid();
  else if (e.type === 'open') { if (e.what === 'checkin') openCheckIn(false); else if (e.what === 'briefing') showBriefing(false); }
  else if (e.type === 'http') window.dispatchEvent(new CustomEvent('sparrow-http', { detail: e }));
};
function refreshAndroid() {
  if (!N) return;
  let st = {}; try { st = JSON.parse(N.status()); } catch {}
  $('#aWake').checked = !!st.wakeWord; $('#aBubble').checked = !!st.bubble; $('#aNotif').checked = !!st.readNotifs;
  const notes = [];
  if (st.bubble && !st.overlay) notes.push('Allow "Display over other apps" for Zuffi to show the floating bird.');
  if (st.readNotifs && !st.notifAccess) notes.push('Allow "Notification access" for Zuffi to read notifications.');
  if (st.wakeWord && !st.mic) notes.push('Allow the microphone so Zuffi can hear you.');
  $('#aNote').textContent = notes.join(' ');
}
/** Android rings these with real alarms, even when Zuffi is closed. */
function syncAlarms() {
  if (!N) return;
  const s = S(), w = s.name ? s.name + ', ' : '', lead = (+s.lead || 0) * 60000, list = [];
  const push = (i, at, suffix = '') => {
    const meet = i.type === 'meeting';
    list.push({ id: i.id + suffix, title: i.title, type: i.type, at, head: meet ? 'Meeting now' : 'Reminder', say: meet ? `${w}you have a meeting now: ${i.title}.` : `${w}it's time: ${i.title}.` });
    if (lead) list.push({ id: i.id + suffix + '|soon', title: i.title, type: i.type, at: at - lead, head: `In ${s.lead} minutes`, say: meet ? `${w}you have a meeting in ${s.lead} minutes: ${i.title}.` : `${w}reminder in ${s.lead} minutes: ${i.title}.` });
  };
  for (const i of store.items.filter(i => i.when && !i.done && (i.type === 'reminder' || i.type === 'meeting' || (i.type === 'task' && i.timed)))) {
    push(i, new Date(i.when).getTime());
    if (i.repeat) { let d = new Date(i.when); for (let k = 1; k < 7; k++) { d = nextOccurrence(i.repeat, d, d); if (!d) break; push(i, d.getTime(), '|r' + k); } }
    if (i.snoozeUntil && !i.snoozed) list.push({ id: i.id + '|snz', title: i.title, type: i.type, at: i.snoozeUntil, head: 'Reminder', say: `${w}snoozed reminder: ${i.title}.` });
  }
  const next = hm => { const [h, m] = (hm || '08:30').split(':').map(Number); const d = new Date(); d.setHours(h, m, 0, 0); if (d <= new Date()) d.setDate(d.getDate() + 1); return d; };
  if (s.morningOn) { const d = next(s.morningTime); list.push({ id: 'morning', title: 'Good morning', type: 'briefing', at: d.getTime(), head: '☀️ Your day', open: 'briefing', say: `Good morning${s.name ? ', ' + s.name : ''}! ` + spokenPlan(d) + ' Have a lovely day!', again: `Good morning${s.name ? ', ' + s.name : ''}! Tap to hear your day.` }); }
  if (s.nightOn) { const d = next(s.nightTime), open = tasksForDay(d); list.push({ id: 'night', title: 'Evening check-in', type: 'checkin', at: d.getTime(), head: '🌙 Check-in time', open: 'checkin',
    say: open.length ? `Hi${s.name ? ' ' + s.name : ''}, it's check-in time. ${open.length === 1 ? 'One task is' : open.length + ' tasks are'} still open: ${spokenList(open.map(i => i.title))}. Tap to tick what you finished.` : `Hi${s.name ? ' ' + s.name : ''}, it's check-in time. Nothing left for today. Well done!`,
    again: `Hi${s.name ? ' ' + s.name : ''}, it's check-in time. Tap to tick off today's tasks.` }); }
  if (s.prayer.on && s.lastLoc) {
    for (let day = 0; day < 3; day++) {
      const d = new Date(); d.setDate(d.getDate() + day);
      const tms = prayerTimes(d, s.lastLoc.lat, s.lastLoc.lon, s.prayer.method, s.prayer.asr);
      for (const n of PRAYERS) if (n !== 'Sunrise') { const at = tms[n].getTime() - (+s.prayer.before || 0) * 60000; if (at > Date.now()) list.push({ id: `pr-${n}-${day}`, title: `${n} prayer`, type: 'prayer', at, head: `🕌 ${n}`, say: +s.prayer.before ? `${w}${n} prayer in ${s.prayer.before} minutes.` : `${w}it's time for ${n} prayer.` }); }
    }
  }
  try { N.syncAlarms(JSON.stringify(list)); } catch {}
}
if (N) {
  $('#androidSection').hidden = false;
  $('#aWake').onchange = e => { N.setWakeWord(e.target.checked); setTimeout(refreshAndroid, 600); };
  $('#aBubble').onchange = e => { N.setBubble(e.target.checked); setTimeout(refreshAndroid, 600); };
  $('#aNotif').onchange = e => { N.setReadNotifications(e.target.checked); setTimeout(refreshAndroid, 600); };
  refreshAndroid(); syncAlarms();
}

// ---------------- computer app extras ----------------
if (D) import('./desktop.js').catch(e => console.error('desktop', e));

// ---------------- start ----------------
renderAll(); installHint(); updateTimerLabel();
bird.classList.add('fly'); setTimeout(() => { bird.classList.remove('fly'); chirp(); }, 1150);
showBriefing(false);
checkDue(); mem.prune();
const todayK = dayKey();
if (S().lastBriefDay !== todayK) {
  const once = e => {
    if (e.target.closest('#birdWrap,#micBtn,#micHeroBtn,#askForm,#settingsBtn,.sheet,.tabs')) return;
    document.removeEventListener('pointerdown', once);
    if (S().lastBriefDay === todayK) return;
    S().lastBriefDay = todayK; store.save(); showBriefing(true);
  };
  document.addEventListener('pointerdown', once);
}
if ('Notification' in window && Notification.permission === 'default' && !D && !M) document.addEventListener('pointerdown', () => Notification.requestPermission?.().catch(() => {}), { once: true });
if ('serviceWorker' in navigator && !D && !N) navigator.serviceWorker.register('sw.js').catch(() => {});
setInterval(() => { renderHeader(); renderNext(); }, 60000);
setInterval(() => { renderWeather(); renderPrayer(); }, 30 * 60000);
const pre = new URLSearchParams(location.search).get('ask');
if (pre) { $('#askInput').value = pre; $('#askInput').focus(); }
// Questions the Mac island passes on (spoken or typed there). Returns the reply to speak, or null if Zuffi's brain can't do it.
async function voiceAsk(text) {
  text = String(text || '').trim(); if (!text) return null;
  const r = await handle(text).catch(() => null);
  if (!r) return null;
  addMsg('me', text, { cmd: true });
  mem.remember('chat', text);
  replyKind = 'cmd';
  if (r.action) {
    const before = store.chat.length;
    if (await runAction(r)) {
      M?.post('show', { tab: '' });
      const said = store.chat.slice(before).filter(m => m.role === 'bot').pop();
      return said?.text || r.reply || 'Done — have a look.';
    }
  }
  addMsg('bot', r.reply, { cmd: true, ...(r.item ? { itemId: r.item.id } : {}), ...(r.results ? { results: r.results } : {}), ...(r.files ? { files: r.files } : {}) });
  if (r.url) setTimeout(() => openUrl(r.url), 350);
  if (r.results?.length || r.files?.length) { go('chat'); M?.post('show', { tab: 'chat' }); }
  return r.reply;
}
jobs.initJobs({ openPanel, openUrl, toast, pickFiles, closeSheets });
window.Sparrow = {
  catchUp: () => checkDue(),
  rememberNote: (title, text) => mem.remember('meeting-notes', title, text),
  rememberFile: async (name, type, base64) => {
    const bin = atob(base64), u = new Uint8Array(bin.length); for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
    const rec = await mem.addFile(new File([u], name, { type }), true);
    activeDocs = [rec.id];
    return rec.id;
  },
  // Water / coffee / medicine reminders (the Mac's Settings window edits these).
  getHealth: () => JSON.parse(JSON.stringify(S().health || {})),
  setHealth: h => { const old = S().health || {}; for (const k of ['water', 'coffee', 'meds']) if (h?.[k]) { const n = { ...old[k], ...h[k] }; if (n.mode !== old[k]?.mode || n.every !== old[k]?.every || !n.on) delete n.last; old[k] = n; } S().health = old; store.save(); return true; },
  testHealth: kind => { const def = HEALTH[kind]; if (!def) return false; const h = S().health[kind] || {}; const shown = typeof def.show === 'function' ? def.show(h) : def.show; M?.post('health', { kind, text: shown }); speak(def.say(who(), h)); return true; },
  // Zuffi's live voice reads and changes your real list (never guesses).
  listItems: () => store.items.filter(i => !i.done && ['reminder', 'task', 'meeting'].includes(i.type))
    .sort((a, b) => new Date(a.when || 8e15) - new Date(b.when || 8e15))
    .map(i => ({ id: i.id, kind: i.type, title: i.title, when: i.when ? new Date(i.when).toLocaleString([], { weekday: 'long', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' }) : null, repeat: i.repeat ? repeatText(i.repeat) : null })),
  addReminder: (title, when, kind = 'reminder', rep = '') => {
    const d = new Date(when); if (!title || isNaN(d)) return { ok: false, error: 'bad title or time' };
    const rule = { daily: { freq: 'daily' }, weekdays: { freq: 'weekly', days: [1, 2, 3, 4, 5] }, weekly: { freq: 'weekly', days: [d.getDay()] }, monthly: { freq: 'monthly' } }[rep] || null;
    const it = store.add({ type: ['task', 'meeting'].includes(kind) ? kind : 'reminder', title, when: d.toISOString(), repeat: rule });
    mem.remember(it.type, title, '', { when: it.when }); renderAll();
    return { ok: true, id: it.id, title, when: whenText(it.when) };
  },
  removeItem: id => { const it = store.items.find(i => i.id === id); if (!it) return null; store.remove(id); renderAll(); return it.title; },
  snoozeItem: (id, mins = 10) => { const it = store.items.find(i => i.id === id); if (!it) return null; store.update(id, { snoozeUntil: Date.now() + mins * 60000, snoozed: false, done: false }); renderAll(); return it.title; },
  completeItem: id => { const it = store.items.find(i => i.id === id); if (!it) return null; store.update(id, { done: true, doneAt: new Date().toISOString() }); mem.remember('done', it.title); renderAll(); return it.title; },
  // "Zuffi, type my email" (Mac): the value comes from your CV profile / latest cover letter.
  jobField: name => jobs.field(name),
  submit, speak, toast, openTool, store, voiceAsk, go: v => { if (v) go(v); }, newChat,
  // Island chats go to History too, so they can be continued here.
  archiveChat: msgs => { archiveChat((msgs || []).map(m => ({ role: m.role === 'user' ? 'me' : 'bot', text: m.content, ts: Date.now() }))); store.save(); },
  // The Mac island speaks through here (Kokoro / Urdu / Hindi / Punjabi / Studio voice), and hears when it's done.
  neuralSay: t => S().neural === false ? Promise.resolve(false) : nv.say(t, neuralOpts({
    onstart: () => setBird('talking', true),
    onend: () => { setBird('talking', false); M?.post('speaking', { on: false }); },
  })),
  neuralStop: () => nv.stop(),
};   // for the computer apps
function sendVoicePrefs() {
  if (!M) return;
  const listen = S().listen || ({ en: 'en-US', ur: 'en-IN', hi: 'en-IN', pa: 'en-IN', ar: 'ar-SA' }[S().lang] || 'en-US');
  M.post('prefs', { listen, neural: S().neural !== false, studio: !!S().studio, lang: S().lang || 'en', voiceName: S().voiceName || '', gender: S().gender || 'female', handsFree: S().handsFree === true });
}
if (M) {
  M.post('ready'); sendVoicePrefs();
  // Esc tucks the panel away (unless a sheet is open, then Esc closes the sheet first)
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && !document.querySelector('.sheet:not([hidden])')) M.post('hide'); });
}   // the Mac app speaks with its own fast native voice engine

// ---------------- Control my Mac (iPhone ↔ Mac link) ----------------
function renderMacLink() {
  const box = $('#macLinkBox'); if (!box) return;
  const on = maclink.linked();
  box.innerHTML = on
    ? `<p class="small-text">✅ Linked to your Mac. Say or type things like “lock my Mac”, “turn off my Mac”, “open Spotify on my Mac”, “Mac volume 30”.</p>
       <div class="mac-pad">${[['🔒', 'Lock', 'lock my mac'], ['😴', 'Sleep', 'sleep mac'], ['▶️', 'Play', 'play music on my mac'], ['⏸️', 'Pause', 'pause music on my mac'], ['🔉', 'Vol −', 'volume down on my mac'], ['🔊', 'Vol +', 'volume up on my mac'], ['⏻', 'Shut down', 'shut down mac'], ['✋', 'Cancel', 'cancel on my mac']].map(([i, l, c]) => `<button class="mac-key" data-mac="${c}"><span>${i}</span>${l}</button>`).join('')}</div>
       <div class="row-2"><button class="btn ghost" id="macPing">📡 Test link</button><button class="btn ghost" id="macUnlink">Unlink</button></div>`
    : `<p class="small-text">Use Zuffi on this phone to control your Mac from anywhere. On your Mac: Zuffi Settings → <b>iPhone</b> → switch on → <b>Show link code</b>. Then scan it here (or with the iPhone Camera).</p>
       <button class="btn" id="macScan">📷 Scan Mac code</button>
       <video id="macVideo" playsinline muted hidden style="width:100%;border-radius:14px;margin-top:8px"></video>
       <label class="field"><span>…or paste the link</span><input id="macPaste" placeholder="https://…#link=…"></label>`;
  box.querySelectorAll('[data-mac]').forEach(b => b.onclick = async () => {
    if (b.dataset.mac === 'shut down mac' && !confirm('Shut down your Mac?')) return;
    b.disabled = true; toast('💻 Sending…'); const r = await maclink.send(b.dataset.mac); b.disabled = false; toast((r.ok ? '💻 ' : '⚠️ ') + r.text, 5000);
  });
  $('#macPing')?.addEventListener('click', async () => { toast('📡 Checking your Mac…'); const r = await maclink.ping(); toast((r.ok ? '✅ ' : '⚠️ ') + r.text, 6000); });
  $('#macUnlink')?.addEventListener('click', () => { maclink.unlink(); renderMacLink(); toast('Unlinked'); });
  $('#macPaste')?.addEventListener('change', e => { if (maclink.takeLink(e.target.value)) { renderMacLink(); afterLink(); } else toast('That link doesn’t look right.'); });
  $('#macScan')?.addEventListener('click', async () => {
    const v = $('#macVideo'); v.hidden = false; const ctl = new AbortController(); setTimeout(() => ctl.abort(), 60000);
    try { if (await maclink.scanLink(v, ctl.signal)) { renderMacLink(); afterLink(); } } catch { toast('Allow the camera to scan the code.'); }
    v.hidden = true;
  });
}
async function afterLink() {
  toast('💗 Linked to your Mac — checking it…', 4000);
  const r = await maclink.ping();
  toast((r.ok ? '✅ ' : '⚠️ ') + r.text, 6000);
}
if (!M && maclink.takeLink(location.hash)) {
  history.replaceState(null, '', location.pathname + location.search);   // the key never stays in the address bar
  setTimeout(afterLink, 800);
}
document.addEventListener('toggle', e => { if (e.target.id === 'macLinkDetails' && e.target.open) renderMacLink(); }, true);
