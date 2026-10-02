import { store } from './store.js';
import { handle, briefing, daySummary, whenText, fmtTime, greetingWord, getQuick, DEFAULT_QUICK, icsFor, googleCalUrl, isIOS } from './brain.js';
import { ask, loadLocal, deviceSupport, aiReady } from './ai.js';

const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = s => String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const ICON = { task: '✅', meeting: '🗓️', reminder: '⏰', note: '📝' };
// Present when running inside the Sparrow Android app
const N = window.SparrowNative || null;
if (N) document.documentElement.classList.add('android-app');

// ---------------- navigation ----------------
let planType = 'task';
function go(v) {
  $$('.view').forEach(x => x.classList.toggle('active', x.id === 'view-' + v));
  $$('.tabs button').forEach(b => b.classList.toggle('on', b.dataset.v === v));
  if (v === 'chat') setTimeout(() => window.scrollTo({ top: document.body.scrollHeight, behavior: 'smooth' }), 50);
  else window.scrollTo({ top: 0 });
}
$$('.tabs button').forEach(b => b.onclick = () => go(b.dataset.v));
$$('[data-goto]').forEach(b => b.onclick = () => go(b.dataset.goto));
$$('#seg button').forEach(b => b.onclick = () => { planType = b.dataset.t; $$('#seg button').forEach(x => x.classList.toggle('on', x === b)); renderPlan(); });

// ---------------- header ----------------
function renderHeader() {
  $('#hello').textContent = `${greetingWord()}${store.settings.name ? ', ' + store.settings.name : ''}`;
  $('#todayLabel').textContent = new Date().toLocaleDateString([], { weekday: 'long', day: 'numeric', month: 'long' });
}

// ---------------- lists ----------------
function itemRow(i, opts = {}) {
  const sub = i.type === 'note'
    ? new Date(i.created).toLocaleDateString([], { day: 'numeric', month: 'short' })
    : (i.when ? whenText(i.when) : 'No date');
  const lead = i.type === 'task'
    ? `<button class="check" data-act="toggle" aria-label="Done">${i.done ? '✓' : ''}</button>`
    : `<div class="ic ${i.type}">${ICON[i.type]}</div>`;
  const cal = i.when && i.type !== 'note' ? `<button data-act="cal" title="Add to phone calendar">📅</button>` : '';
  return `<div class="item ${i.done ? 'done' : ''}" data-id="${i.id}">
    ${lead}
    <div class="txt"><div class="t1">${esc(i.title)}</div><div class="t2">${esc(sub)}</div></div>
    <div class="acts">${cal}${opts.noDelete ? '' : '<button data-act="del" title="Delete">🗑️</button>'}</div>
  </div>`;
}
function bindList(root) {
  root.onclick = e => {
    const b = e.target.closest('[data-act]'); if (!b) return;
    const id = b.closest('.item').dataset.id; const it = store.items.find(x => x.id === id); if (!it) return;
    if (b.dataset.act === 'toggle') { store.update(id, { done: !it.done }); if (!it.done) { birdMood('happy'); chirp(); } }
    if (b.dataset.act === 'del') { store.remove(id); toast('Removed'); }
    if (b.dataset.act === 'cal') addToCalendar(it);
  };
}
function renderToday() {
  const day = store.onDay(new Date()).filter(i => !(i.type === 'reminder' && i.done));
  const undatedTasks = store.openTasks().filter(i => !i.when).slice(0, 4);
  const items = [...day, ...undatedTasks];
  $('#todayList').innerHTML = items.length ? items.map(i => itemRow(i)).join('')
    : `<div class="empty">Nothing planned yet.<br>Try <b>"meeting with Ali Friday 3pm"</b> or <b>"add task buy milk"</b>.</div>`;
}
function renderPlan() {
  let list = store.ofType(planType);
  if (planType === 'task') list.sort((a, b) => a.done - b.done || (a.when ? new Date(a.when) : 9e15) - (b.when ? new Date(b.when) : 9e15));
  else if (planType === 'note') list.sort((a, b) => new Date(b.created) - new Date(a.created));
  else list.sort((a, b) => new Date(a.when) - new Date(b.when));
  const examples = {
    task: '"add task buy milk" or "I need to pay rent Friday"',
    meeting: '"meeting with Ali Friday 3pm"',
    reminder: '"remind me to call mum at 6pm tomorrow"',
    note: '"note wifi password is sparrow123"',
  };
  $('#planList').innerHTML = list.length ? list.map(i => itemRow(i)).join('') : `<div class="empty">Nothing here yet.<br>Say ${examples[planType]}</div>`;
  $('#planHint').textContent = planType === 'reminder' || planType === 'meeting'
    ? 'Tap 📅 to put it in your phone calendar — then it rings even when Sparrow is closed.' : '';
}
function renderQuick() {
  const list = getQuick();
  $('#quick').innerHTML = list.map((q, i) => `<button class="q" data-i="${i}"><span>${q.e}</span>${esc(q.n)}</button>`).join('')
    + `<button class="q" data-add="1"><span>＋</span>Add</button>`;
  $('#quick').onclick = e => {
    const b = e.target.closest('.q'); if (!b) return;
    if (b.dataset.add) return addQuick();
    openUrl(list[+b.dataset.i].url);
  };
  // Long-press a button to remove it
  let pressT;
  $('#quick').onpointerdown = e => {
    const b = e.target.closest('.q[data-i]'); if (!b) return;
    pressT = setTimeout(() => {
      const q = list[+b.dataset.i];
      if (confirm(`Remove "${q.n}" from your quick buttons?`)) {
        store.settings.quick = list.filter((_, i) => i !== +b.dataset.i); store.save(); renderQuick();
      }
    }, 650);
  };
  $('#quick').onpointerup = $('#quick').onpointerleave = () => clearTimeout(pressT);
}
function addQuick() {
  const name = prompt(N ? 'Which app? Type its name (e.g. Netflix, Uber, Snapchat):' : 'Name of the app or website (e.g. Netflix, Uber, BBC News):'); if (!name) return;
  if (N) {
    const emojiA = (prompt('Pick an emoji for the button:', '⭐') || '⭐').slice(0, 2);
    store.settings.quick = [...getQuick(), { k: name.toLowerCase(), n: name, e: emojiA, url: 'app:' + name }];
    store.save(); renderQuick(); toast(`Added ${name}`); return;
  }
  let url = prompt(`Link for ${name} (e.g. netflix.com). Most apps open automatically from their website link:`, name.toLowerCase().replace(/\s+/g, '') + '.com');
  if (!url) return;
  if (!/^[a-z]+:/i.test(url)) url = 'https://' + url;
  const emoji = (prompt('Pick an emoji for the button:', '⭐') || '⭐').slice(0, 2);
  store.settings.quick = [...getQuick(), { k: name.toLowerCase(), n: name, e: emoji, url }];
  store.save(); renderQuick(); toast(`Added ${name} — you can also say "open ${name}"`);
}
function renderAll() { renderHeader(); renderToday(); renderPlan(); }
store.onChange(() => { renderToday(); renderPlan(); syncAlarms(); });
// Android: real alarms for reminders & meetings (ring even when Sparrow is closed)
function syncAlarms() {
  if (!N) return;
  const list = store.items.filter(i => i.when && !i.done && (i.type === 'reminder' || i.type === 'meeting'))
    .map(i => ({ id: i.id, title: i.title, type: i.type, at: new Date(i.when).getTime() - (i.type === 'meeting' ? 600000 : 0) }));
  try { N.syncAlarms(JSON.stringify(list)); } catch {}
}

// ---------------- calendar ----------------
function addToCalendar(it) {
  if (N) {
    const start = new Date(it.when).getTime();
    N.addToCalendar(it.title, start, start + (it.type === 'meeting' ? 60 : 15) * 60000);
    return;
  }
  if (!isIOS && /Android/i.test(navigator.userAgent)) {
    openUrl(googleCalUrl(it));   // Android: Google Calendar handles this best
    return;
  }
  const ics = icsFor(it);
  const file = new File([ics], (it.title.replace(/[^\w ]/g, '').slice(0, 30) || 'event') + '.ics', { type: 'text/calendar' });
  if (isIOS) {
    // iOS opens a data: calendar file straight into "Add to Calendar"
    location.href = 'data:text/calendar;charset=utf-8,' + encodeURIComponent(ics);
    return;
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(file); a.download = file.name; a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
  toast('Calendar file downloaded — open it to add the event');
}

// ---------------- chat ----------------
function addMsg(role, text, extra = {}) {
  const m = { role, text, ts: Date.now(), ...extra };
  store.chat.push(m); store.save(); renderChat(); return m;
}
function renderChat() {
  const box = $('#chat');
  if (!store.chat.length) {
    box.innerHTML = `<div class="msg bot">Hi${store.settings.name ? ' ' + esc(store.settings.name) : ''}! I'm Sparrow 🐦\nAsk me anything, or tell me what to remember.</div>`;
    return;
  }
  box.innerHTML = store.chat.map((m, idx) => {
    let calBtn = '';
    if (m.itemId) { const it = store.items.find(x => x.id === m.itemId); if (it?.when) calBtn = `<div class="cal"><button class="chip" data-cal="${it.id}">📅 Add to phone calendar</button></div>`; }
    if (m.action === 'ai' && !aiReady()) calBtn = `<div class="cal"><button class="chip" data-settings="1">✨ Turn on free AI</button></div>`;
    return `<div class="msg ${m.role}">${esc(m.text)}${m.src ? `<span class="src">${esc(m.src)}</span>` : ''}${calBtn}</div>`;
  }).join('');
  box.onclick = e => {
    if (e.target.closest('[data-settings]')) { openSettings(); return; }
    const b = e.target.closest('[data-cal]'); if (b) { const it = store.items.find(x => x.id === b.dataset.cal); if (it) addToCalendar(it); }
  };
}

async function submit(text, fromVoice = false) {
  text = text.trim(); if (!text) return;
  addMsg('me', text);
  go('chat');
  const r = await handle(text);
  if (r) {
    addMsg('bot', r.reply, r.item ? { itemId: r.item.id } : {});
    birdMood(r.item ? 'happy' : 'talk');
    if (r.url) setTimeout(() => openUrl(r.url), 350);
    if (fromVoice || store.settings.speak) speak(r.reply);
    return;
  }
  // Ask the AI
  const box = $('#chat');
  const typing = document.createElement('div');
  typing.className = 'msg bot typing'; typing.innerHTML = '<span></span><span></span><span></span>';
  box.appendChild(typing); window.scrollTo({ top: document.body.scrollHeight });
  setBird('talking', true);
  try {
    const res = await ask(text, partial => { typing.classList.remove('typing'); typing.textContent = partial; window.scrollTo({ top: document.body.scrollHeight }); });
    typing.remove();
    addMsg('bot', res.text || '…', { src: res.source });
    if (fromVoice || store.settings.speak) speak(res.text);
  } catch (e) {
    typing.remove();
    if (e.message === 'NO_AI') {
      addMsg('bot', "I can handle meetings, tasks, reminders, notes and quick actions right now. To answer anything else, turn on the free AI that runs on your phone (one-time download).", { action: 'ai' });
    } else addMsg('bot', '⚠️ ' + e.message);
  } finally { setBird('talking', false); }
}
$('#askForm').onsubmit = e => { e.preventDefault(); const v = $('#askInput').value; $('#askInput').value = ''; submit(v); };

function openUrl(url) {
  if (!url) return;
  if (url.startsWith('app:')) { if (!(N && N.openApp(url.slice(4)))) toast(`Couldn't find ${url.slice(4)}`); return; }
  if (/^https?:/.test(url)) window.open(url, '_blank', 'noopener');
  else location.href = url;
}

// ---------------- the sparrow ----------------
const bird = $('#bird');
function setBird(cls, on) { bird.classList.toggle(cls, on); }
function birdMood(m) {
  if (m === 'happy') { bird.classList.remove('happy'); void bird.offsetWidth; bird.classList.add('happy'); setTimeout(() => bird.classList.remove('happy'), 1100); }
}
function chirp() {
  try {
    const ac = new (window.AudioContext || window.webkitAudioContext)();
    [[2600, 3600, 0], [3000, 4200, .09]].forEach(([f0, f1, t]) => {
      const o = ac.createOscillator(), g = ac.createGain();
      o.frequency.setValueAtTime(f0, ac.currentTime + t); o.frequency.exponentialRampToValueAtTime(f1, ac.currentTime + t + .07);
      g.gain.setValueAtTime(.0001, ac.currentTime + t); g.gain.exponentialRampToValueAtTime(.08, ac.currentTime + t + .01);
      g.gain.exponentialRampToValueAtTime(.0001, ac.currentTime + t + .08);
      o.connect(g).connect(ac.destination); o.start(ac.currentTime + t); o.stop(ac.currentTime + t + .1);
    });
    setTimeout(() => ac.close(), 400);
  } catch {}
}

// ---------------- voice out ----------------
let voices = [];
function loadVoices() { voices = speechSynthesis?.getVoices?.() || []; }
if ('speechSynthesis' in window) { loadVoices(); speechSynthesis.onvoiceschanged = loadVoices; }
const FEMALE = /samantha|ava|zoe|serena|allison|susan|karen|moira|tessa|kate|victoria|fiona|female|woman|google uk english female|google us english|en-gb-x-.*#female|siri.*female|sonia|libby|jenny|aria/i;
const MALE = /daniel|alex|tom|evan|nathan|aaron|arthur|oliver|fred|rishi|male|man|google uk english male|en-gb-x-.*#male|guy|ryan|thomas/i;
function pickVoice() {
  const lang = (navigator.language || 'en').slice(0, 2);
  const pool = voices.filter(v => v.lang?.toLowerCase().startsWith(lang)) .concat(voices.filter(v => v.lang?.startsWith('en')));
  const want = store.settings.gender === 'male' ? MALE : FEMALE;
  const quality = v => /premium|enhanced|natural|neural|siri/i.test(v.name) ? 0 : 1;
  const matches = pool.filter(v => want.test(v.name)).sort((a, b) => quality(a) - quality(b));
  return matches[0] || pool.sort((a, b) => quality(a) - quality(b))[0] || null;
}
function speak(text) {
  if (N && text) { N.speak(text, store.settings.gender); return; }
  if (!('speechSynthesis' in window) || !text) return;
  speechSynthesis.cancel();
  const u = new SpeechSynthesisUtterance(text.replace(/[•✅⏰🗓️📝🐦✨☔🎉🌤️⚠️✔️🗑️]/gu, ''));
  const v = pickVoice(); if (v) { u.voice = v; u.lang = v.lang; }
  u.rate = 1.0; u.pitch = store.settings.gender === 'male' ? 0.95 : 1.05;
  u.onstart = () => setBird('talking', true);
  u.onend = u.onerror = () => setBird('talking', false);
  speechSynthesis.speak(u);
}

// ---------------- voice in ----------------
const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
let rec = null, listening = false;
function listen() {
  if (N) { N.listen(); return; }
  if (!SR) { toast('Voice input isn\'t supported in this browser — type instead.'); return; }
  if (listening) { rec?.stop(); return; }
  speechSynthesis?.cancel();
  rec = new SR(); rec.lang = navigator.language || 'en-GB'; rec.interimResults = true; rec.maxAlternatives = 1;
  let finalText = '';
  rec.onstart = () => { listening = true; $('#micBtn').classList.add('on'); $('#pulse').classList.add('on'); setBird('listening', true); chirp(); $('#askInput').placeholder = 'Listening…'; };
  rec.onresult = e => {
    let txt = ''; for (const r of e.results) txt += r[0].transcript;
    $('#askInput').value = txt;
    if (e.results[e.results.length - 1].isFinal) finalText = txt;
  };
  rec.onerror = e => { if (e.error === 'not-allowed') toast('Allow the microphone for Sparrow in your browser settings.'); };
  rec.onend = () => {
    listening = false; $('#micBtn').classList.remove('on'); $('#pulse').classList.remove('on'); setBird('listening', false);
    $('#askInput').placeholder = 'Ask Sparrow… e.g. remind me to call mum at 6pm';
    const t = (finalText || $('#askInput').value).trim();
    $('#askInput').value = '';
    if (t) submit(t, true);
  };
  rec.start();
}
$('#micBtn').onclick = listen;
$('#micHeroBtn').onclick = listen;
$('#birdWrap').onclick = listen;

// ---------------- briefing ----------------
async function showBriefing(speakIt) {
  $('#brief').textContent = `${greetingWord()}${store.settings.name ? ', ' + store.settings.name : ''}! ${daySummary(new Date(), true)}`;
  const text = await briefing();
  $('#brief').textContent = text;
  if (speakIt) speak(text);
}
$('#hearBriefBtn').onclick = () => showBriefing(true);

// ---------------- reminders while the app is open ----------------
async function checkDue() {
  const now = Date.now();
  for (const it of store.items) {
    if ((it.type === 'reminder' || it.type === 'meeting') && it.when && !it.notified && !it.done) {
      const t = new Date(it.when).getTime() - (it.type === 'meeting' ? 10 * 60000 : 0);
      if (t <= now && now - t < 30 * 60000) {
        store.update(it.id, { notified: true });
        const msg = it.type === 'meeting' ? `Meeting at ${fmtTime(it.when)}: ${it.title}` : `Reminder: ${it.title}`;
        toast('⏰ ' + msg, 6000); speak(msg); birdMood('happy');
        try {
          if (Notification?.permission === 'granted') {
            const reg = await navigator.serviceWorker?.getRegistration();
            reg ? reg.showNotification('Sparrow', { body: msg, icon: 'icons/icon-192.png', tag: it.id }) : new Notification('Sparrow', { body: msg });
          }
        } catch {}
        if (it.type === 'reminder') store.update(it.id, { done: true });
      } else if (t <= now) store.update(it.id, { notified: true });
    }
  }
}
setInterval(checkDue, 20000);

// ---------------- settings ----------------
function openSettings() {
  const s = store.settings;
  $('#sName').value = s.name; $('#sCity').value = s.city; $('#sSpeak').checked = s.speak;
  $('#sModel').value = s.model;
  $('#kGemini').value = s.keys.gemini || ''; $('#kOpenAI').value = s.keys.openai || ''; $('#kClaude').value = s.keys.claude || '';
  $$('#sGender button').forEach(b => b.classList.toggle('on', b.dataset.g === s.gender));
  $('#sheet').hidden = $('#sheetBg').hidden = false;
  refreshAiStatus(); refreshAndroid();
}
function closeSettings() {
  const s = store.settings;
  s.name = $('#sName').value.trim(); s.city = $('#sCity').value.trim(); s.speak = $('#sSpeak').checked; s.model = $('#sModel').value;
  s.keys = { gemini: $('#kGemini').value.trim(), openai: $('#kOpenAI').value.trim(), claude: $('#kClaude').value.trim() };
  store.save();
  $('#sheet').hidden = $('#sheetBg').hidden = true;
  renderHeader();
}
$('#settingsBtn').onclick = openSettings;
$('#closeSheet').onclick = closeSettings;
$('#sheetBg').onclick = closeSettings;
$$('#sGender button').forEach(b => b.onclick = () => { store.settings.gender = b.dataset.g; $$('#sGender button').forEach(x => x.classList.toggle('on', x === b)); store.save(); });
$('#testVoice').onclick = () => speak(`Hi${store.settings.name ? ' ' + store.settings.name : ''}! I'm Sparrow. Ready when you are.`);
$('#exportBtn').onclick = () => {
  const blob = new Blob([JSON.stringify({ items: store.items, settings: { ...store.settings, keys: undefined } }, null, 2)], { type: 'application/json' });
  const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'sparrow-backup.json'; a.click();
};
$('#clearBtn').onclick = () => { if (confirm('Delete all your tasks, meetings, reminders, notes and chat?')) { store.clearAll(); renderChat(); toast('Everything deleted'); } };

async function refreshAiStatus() {
  const st = $('#aiStatus'), btn = $('#aiDownload');
  if (aiReady()) { st.textContent = '✅ Free on-device AI is on. It works offline.'; btn.hidden = true; return; }
  const sup = await deviceSupport();
  if (!sup.ok) { st.textContent = '⚠️ ' + sup.why + ' Everything else still works.'; btn.disabled = true; return; }
  btn.disabled = false; btn.hidden = false;
  st.textContent = store.settings.aiReady
    ? 'Downloaded — it starts the first time you ask something.'
    : 'Your phone can run a free AI. It downloads once (use Wi-Fi), then works offline. Nothing you say leaves your phone.';
}
$('#aiDownload').onclick = async () => {
  const bar = $('#aiProgress'), btn = $('#aiDownload');
  store.settings.model = $('#sModel').value; store.save();
  bar.hidden = false; btn.disabled = true; btn.textContent = 'Downloading…';
  try {
    await loadLocal((p, txt) => { bar.firstElementChild.style.width = Math.round(p * 100) + '%'; $('#aiStatus').textContent = txt.slice(0, 90); });
    btn.textContent = 'Ready ✅'; toast('Free AI ready 🐦'); refreshAiStatus();
  } catch (e) {
    btn.disabled = false; btn.textContent = '⬇️ Try again'; $('#aiStatus').textContent = '⚠️ ' + e.message;
  }
};

// ---------------- toast ----------------
let toastT;
function toast(text, ms = 2600) {
  const t = $('#toast'); t.textContent = text; t.hidden = false;
  clearTimeout(toastT); toastT = setTimeout(() => t.hidden = true, ms);
}

// ---------------- install hint ----------------
function installHint() {
  if (N) return;
  const standalone = matchMedia('(display-mode: standalone)').matches || navigator.standalone;
  if (standalone) return;
  const el = $('#installHint'); el.hidden = false;
  el.innerHTML = isIOS
    ? '📲 <b>Install Sparrow:</b> tap the <b>Share</b> button in Safari, then <b>“Add to Home Screen”</b>.'
    : '📲 <b>Get the full Android app</b> (floating sparrow, “Sparrow…” voice, alarms): <a href="https://github.com/MuhammadTalha257/sparrow/releases/latest/download/Sparrow.apk" style="color:#F9A830">download Sparrow.apk</a> — or tap <b>⋮</b> → <b>Install app</b> for the light version.';
}

// ---------------- Android app events ----------------
window.sparrowEvent = raw => {
  const e = typeof raw === 'string' ? JSON.parse(raw) : raw;
  if (e.type === 'speech') submit(e.text, true);
  else if (e.type === 'ask') submit(e.text, !!e.voice);
  else if (e.type === 'partial') $('#askInput').value = e.text;
  else if (e.type === 'listening') {
    $('#micBtn').classList.toggle('on', e.on); $('#pulse').classList.toggle('on', e.on); setBird('listening', e.on);
    if (e.on) chirp();
    else if ($('#askInput').value && !e.on) {/* result follows as 'speech' */}
  }
  else if (e.type === 'speaking') setBird('talking', e.on);
  else if (e.type === 'toast') toast(e.text);
  else if (e.type === 'status') refreshAndroid();
};
function refreshAndroid() {
  if (!N) return;
  let st = {}; try { st = JSON.parse(N.status()); } catch {}
  $('#aWake').checked = !!st.wakeWord;
  $('#aBubble').checked = !!st.bubble;
  $('#aNotif').checked = !!st.readNotifs;
  const notes = [];
  if (st.bubble && !st.overlay) notes.push('Allow "Display over other apps" for Sparrow to show the floating bird.');
  if (st.readNotifs && !st.notifAccess) notes.push('Allow "Notification access" for Sparrow to read notifications.');
  if (st.wakeWord && !st.mic) notes.push('Allow the microphone so Sparrow can hear you.');
  if (st.wakeWord && st.overlay === false) notes.push('Tip: turn on the floating bird too — Android only lets Sparrow open apps hands-free when it is on.');
  $('#aNote').textContent = notes.join(' ');
}
if (N) {
  $('#androidSection').hidden = false;
  $('#aWake').onchange = e => { N.setWakeWord(e.target.checked); setTimeout(refreshAndroid, 600); };
  $('#aBubble').onchange = e => { N.setBubble(e.target.checked); setTimeout(refreshAndroid, 600); };
  $('#aNotif').onchange = e => { N.setReadNotifications(e.target.checked); setTimeout(refreshAndroid, 600); };
  refreshAndroid(); syncAlarms();
}

// ---------------- start ----------------
renderAll(); renderQuick(); renderChat(); installHint();
bird.classList.add('fly'); setTimeout(() => { bird.classList.remove('fly'); chirp(); }, 1150);
showBriefing(false);
checkDue();
// Morning briefing: spoken once a day the first time you open Sparrow (after a tap — browsers need one)
const todayKey = new Date().toDateString();
if (store.settings.lastBriefDay !== todayKey) {
  const once = e => {
    if (e.target.closest('#birdWrap,#micBtn,#micHeroBtn,#askForm,#settingsBtn,.sheet')) return;   // let those taps do their own thing
    document.removeEventListener('pointerdown', once);
    store.settings.lastBriefDay = todayKey; store.save(); showBriefing(true);
  };
  document.addEventListener('pointerdown', once);
}
if ('Notification' in window && Notification.permission === 'default') {
  document.addEventListener('pointerdown', () => Notification.requestPermission?.().catch(() => {}), { once: true });
}
if ('serviceWorker' in navigator) navigator.serviceWorker.register('sw.js').catch(() => {});
setInterval(renderHeader, 60000);
// Home-screen shortcut: ?ask=… prefills the box
const pre = new URLSearchParams(location.search).get('ask');
if (pre) { $('#askInput').value = pre; $('#askInput').focus(); }
