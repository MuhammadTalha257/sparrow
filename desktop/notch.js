// Zuffi's notch for Windows — the same design as the Mac app (ZuffiSpace.swift · NotchDesign):
//  closed: a small glass tab at the top of the screen with the live weather behind Aurora's face and the temperature;
//  open:   a bigger glass tab (Aurora's face, lips and moves easy to see), the ask bar (menu · text · AI · talk),
//          and under it the menu, a page, a reminder banner or the answer — a dark rounded card like on the Mac.
import { store } from './store.js';
import { weather } from './brain.js';
import { Aurora3D } from './aurora3d.js';
import { PROVIDERS } from './ai.js';

const SVG = {
  grid: '<rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>', wave: '<path d="M4 10v4M8 7v10M12 4v16M16 7v10M20 10v4"/>', back: '<path d="M15 18l-6-6 6-6"/>',
  chat: '<path d="M21 12a8 8 0 0 1-11.6 7.1L4 20l1-4.6A8 8 0 1 1 21 12z"/>', tasks: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="M8 12l3 3 5-6"/>',
  notes: '<path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/><path d="M14 3v6h6"/>', bell: '<path d="M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9M10 21h4"/>',
  flame: '<path d="M12 22c4 0 7-3 7-7 0-5-5-7-5-12-3 2-4 5-4 7-1-1-2-2-2-4-2 2-3 5-3 9 0 4 3 7 7 7z"/>', cal: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>',
  week: '<rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 14h2M11 14h2M15 14h2M3 10h18"/>', timer: '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l3 2M9 2h6"/>',
  home: '<path d="M3 11l9-8 9 8v9a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>', msg: '<path d="M3 21l1.7-5A8.5 8.5 0 1 1 8 19.3z"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="3"/><path d="M3 7l9 6 9-6"/>', gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/>',
  tools: '<path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18v3h3l6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4z"/>', eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>',
  people: '<circle cx="9" cy="8" r="3.5"/><path d="M2 20c0-4 3-6 7-6s7 2 7 6M17 11a3 3 0 1 0 0-6M22 20c0-3-2-5-5-5.5"/>', chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  hare: '<path d="M9 3c-1 0-1.5 2-1.5 4.5S8 11 8 11M15 3c1 0 1.5 2 1.5 4.5S16 11 16 11"/><circle cx="12" cy="15" r="6"/>', copy: '<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>',
};
const ico = (n, s = 15, w = 2) => `<svg viewBox="0 0 24 24" width="${s}" height="${s}" fill="none" stroke="currentColor" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round">${SVG[n]}</svg>`;
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

// The menu — same items, order and icons as the Mac (NotchScreen.menu)
const MENU = [['chat', 'Chat', 'chat'], ['tasks', 'Tasks', 'tasks'], ['notes', 'Notes', 'notes'], ['reminders', 'Reminders', 'bell'], ['habits', 'Habits', 'flame'],
  ['today', 'Today', 'cal'], ['week', 'This week', 'week'], ['focus', 'Focus', 'timer'], ['home', 'Home', 'home'], ['whatsapp', 'WhatsApp', 'msg'], ['gmail', 'Gmail', 'mail'],
  ['settings', 'Settings', 'gear'], ['tools', 'Tools', 'tools'], ['screen', 'My screen', 'eye'], ['meeting', 'Meeting helper', 'people'], ['day', 'Your day', 'chart'], ['pet', 'Pet on screen', 'hare']];
// pages that open in the full Zuffi window for now (the web app's own screens)
const FULL = { tasks: 'plan', notes: 'memory', reminders: 'plan', habits: 'home', today: 'plan', week: 'plan', focus: 'home', home: 'home', gmail: 'home',
  settings: 'settings', tools: 'tools', screen: 'chat', meeting: 'home', day: 'home' };

const CSS = `
html.zn #island, html.zn .isl-ear { display: none !important; }
html.zn, html.zn body { background: transparent !important; }
#zn { position: fixed; top: 0; left: 50%; transform: translateX(-50%); width: 440px; display: flex; flex-direction: column; align-items: center; gap: 6px; z-index: 2147483000;
  font-family: "Segoe UI Variable Text", "Segoe UI", system-ui, sans-serif; color: #fff; -webkit-font-smoothing: antialiased; }
#zn * { box-sizing: border-box; }
#zn button { font: inherit; color: inherit; border: 0; background: none; cursor: pointer; }
.zn-tab { position: relative; width: 200px; height: 64px; border-radius: 0 0 19px 19px; overflow: hidden; cursor: pointer;
  background: linear-gradient(#000 0%, #000 38%, rgba(0,0,0,.85) 62%, var(--tint28) 100%), #000;
  box-shadow: 0 6px 18px var(--tint22); transition: width .42s cubic-bezier(.3,1.25,.4,1), height .42s cubic-bezier(.3,1.25,.4,1), border-radius .42s; }
.zn-tab::before { content: ""; position: absolute; inset: 0; border-radius: inherit; pointer-events: none; z-index: 3;
  background: linear-gradient(135deg, transparent 30%, rgba(255,255,255,.07) 50%, transparent 65%); }
.zn-tab::after { content: ""; position: absolute; inset: 0; border-radius: inherit; pointer-events: none; z-index: 3; padding: 1px;
  background: linear-gradient(to bottom, rgba(255,255,255,0), rgba(255,255,255,.10), var(--tint45));
  -webkit-mask: linear-gradient(#000 0 0) content-box, linear-gradient(#000 0 0); -webkit-mask-composite: xor; mask-composite: exclude; }
html.zn-open .zn-tab { width: 250px; height: 106px; border-radius: 0 0 26px 26px; }
.zn-wx { position: absolute; inset: 0; width: 100%; height: 100%; z-index: 1; -webkit-mask: linear-gradient(transparent, #000 45%); mask: linear-gradient(transparent, #000 45%); }
.zn-face { position: absolute; left: 50%; bottom: -4px; width: 64px; height: 58px; transform: translateX(-50%); z-index: 2; transition: width .42s cubic-bezier(.3,1.25,.4,1), height .42s cubic-bezier(.3,1.25,.4,1); }
html.zn-open .zn-face { width: 92px; height: 82px; bottom: -2px; }
.zn-temp { position: absolute; left: 16px; bottom: 9px; z-index: 2; display: flex; align-items: center; gap: 4px; font-size: 11.5px; font-weight: 700; color: rgba(255,255,255,.88); opacity: 0; transition: opacity .3s; }
html.zn-open .zn-temp, html:not(.zn-open) .zn-temp.show { opacity: 1; }
html:not(.zn-open) .zn-temp { left: 12px; bottom: 7px; font-size: 10.5px; }
.zn-bar, .zn-listen { width: 416px; height: 44px; border-radius: 999px; display: none; align-items: center; gap: 8px; padding: 0 5px 0 6px;
  background: linear-gradient(#221E2B, #141218); box-shadow: 0 10px 28px rgba(0,0,0,.45), inset 0 0 0 1px rgba(255,255,255,.12); }
html.zn-open .zn-bar { display: flex; animation: znDrop .35s cubic-bezier(.3,1.3,.4,1); }
html.zn-open.zn-listening .zn-bar { display: none; } html.zn-open.zn-listening .zn-listen { display: flex; padding-left: 16px; }
@keyframes znDrop { from { opacity: 0; transform: translateY(-12px) scale(.96); } }
.zn-round { width: 32px; height: 32px; border-radius: 50%; display: grid; place-items: center; flex: none; background: rgba(255,255,255,.07); color: #E9E5F2; transition: background .2s; }
.zn-round.on { background: rgba(183,156,255,.28); }
.zn-ask { flex: 1; min-width: 0; height: 100%; background: none; border: 0; outline: none; color: #fff; font: inherit; font-size: 14px; }
.zn-ask::placeholder { color: rgba(255,255,255,.45); }
.zn-prov { height: 28px; padding: 0 10px; border-radius: 999px; background: rgba(255,255,255,.08) !important; font-size: 12px !important; font-weight: 600; white-space: nowrap; max-width: 130px; overflow: hidden; text-overflow: ellipsis; }
.zn-talk { width: 32px; height: 32px; border-radius: 50%; display: grid; place-items: center; flex: none; color: #141218 !important; background: linear-gradient(#fff, #E4DEF5) !important; }
.zn-listen .bars { display: flex; gap: 3px; align-items: center; height: 18px; } .zn-listen .bars i { width: 3px; border-radius: 2px; background: #fff; animation: znBar .5s ease-in-out infinite alternate; }
.zn-listen .bars i:nth-child(2) { animation-delay: .12s } .zn-listen .bars i:nth-child(3) { animation-delay: .24s } .zn-listen .bars i:nth-child(4) { animation-delay: .36s }
@keyframes znBar { from { height: 5px } to { height: 16px } }
.zn-listen b { flex: 1; font-size: 13.5px; } .zn-stop { width: 32px; height: 32px; border-radius: 50%; display: grid; place-items: center; background: #E5484D !important; }
.zn-stop i { width: 10px; height: 10px; border-radius: 2px; background: #fff; }
.zn-card { width: 416px; border-radius: 26px; padding: 16px; display: none; max-height: 430px; overflow: auto;
  background: linear-gradient(#17141F, #0B0A0E); box-shadow: 0 16px 40px rgba(0,0,0,.45), inset 0 0 0 1px rgba(255,255,255,.1); animation: znDrop .35s cubic-bezier(.3,1.3,.4,1); }
.zn-card.on { display: block; }
.zn-card::-webkit-scrollbar { width: 6px } .zn-card::-webkit-scrollbar-thumb { background: rgba(255,255,255,.18); border-radius: 3px }
.zn-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 2px 6px; }
.zn-item { display: flex; align-items: center; gap: 12px; height: 40px; padding: 0 10px; border-radius: 10px; font-size: 14px; font-weight: 600; text-align: left; }
.zn-item:hover { background: rgba(255,255,255,.07) !important; } .zn-item:active { background: rgba(255,255,255,.12) !important; }
.zn-item svg { flex: none; } .zn-item span { flex: 1; }
.zn-switch { width: 30px; height: 18px; border-radius: 9px; background: rgba(255,255,255,.18); position: relative; transition: background .25s; flex: none; }
.zn-switch::after { content: ""; position: absolute; top: 2px; left: 2px; width: 14px; height: 14px; border-radius: 50%; background: #fff; transition: left .25s cubic-bezier(.3,1.4,.5,1); }
.zn-switch.on { background: #7CE0A3; } .zn-switch.on::after { left: 14px; }
.zn-head { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; } .zn-head b { font-size: 15px; flex: 1; }
.zn-back { width: 26px; height: 26px; display: grid; place-items: center; color: #B9B4C6 !important; }
.zn-pill { height: 28px; padding: 0 12px; border-radius: 999px; background: rgba(255,255,255,.08) !important; font-size: 12px !important; font-weight: 600; }
.zn-pill.pri { background: #F2F1F6 !important; color: #141218 !important; }
.zn-msg-u { display: flex; justify-content: flex-end; margin: 6px 0; } .zn-msg-u span { max-width: 80%; background: #F2F1F6; color: #141218; padding: 7px 11px; border-radius: 13px; font-size: 12.5px; white-space: pre-wrap; }
.zn-msg-b { font-size: 12.5px; color: #ECEAF2; margin: 6px 0; white-space: pre-wrap; user-select: text; line-height: 1.45; }
.zn-soft { font-size: 12.5px; color: #8E89A3; }
.zn-think { display: flex; align-items: center; gap: 7px; padding: 4px 0; font-size: 12.5px; font-weight: 600; }
.zn-think .d { display: flex; gap: 3px; } .zn-think .d i { width: 6px; height: 6px; border-radius: 50%; background: linear-gradient(#FF8FB8, #B78BFF); animation: znHop .9s ease-in-out infinite; }
.zn-think .d i:nth-child(2) { animation-delay: .13s } .zn-think .d i:nth-child(3) { animation-delay: .26s }
@keyframes znHop { 0%, 60%, 100% { transform: none } 30% { transform: translateY(-4px) } }
.zn-think .w { background: linear-gradient(90deg, rgba(236,234,242,.45) 0%, #fff 30%, #FFB3CF 50%, rgba(236,234,242,.45) 70%); background-size: 250% 100%;
  -webkit-background-clip: text; background-clip: text; color: transparent; animation: znShine 1.6s linear infinite; }
.zn-think .w.in { animation: znShine 1.6s linear infinite, znWord .35s cubic-bezier(.3,1.3,.4,1); }
@keyframes znShine { from { background-position: 150% 0 } to { background-position: -100% 0 } } @keyframes znWord { from { opacity: 0; transform: translateY(8px) } }
.zn-q { display: flex; justify-content: flex-end; margin-bottom: 8px; } .zn-q span { background: #F2F1F6; color: #141218; padding: 6px 10px; border-radius: 12px; font-size: 12.5px; max-width: 85%; }
.zn-a { font-size: 13.5px; line-height: 1.45; white-space: pre-wrap; user-select: text; }
.zn-acts { display: flex; gap: 14px; margin-top: 10px; font-size: 11.5px; color: #B9B4C6; } .zn-acts button:last-child { margin-left: auto; }
.zn-banner { width: 416px; min-height: 34px; display: none; align-items: center; gap: 8px; padding: 6px 6px 6px 12px; border-radius: 999px; background: #141218; box-shadow: inset 0 0 0 1px rgba(245,185,99,.5); font-size: 12.5px; }
.zn-banner.on { display: flex; animation: znDrop .35s cubic-bezier(.3,1.3,.4,1); } .zn-banner b { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.zn-banner .ok { height: 24px; padding: 0 10px; border-radius: 999px; background: #F5B963 !important; color: #141218 !important; font-weight: 700; font-size: 11.5px; }
.zn-banner .later { height: 24px; padding: 0 10px; border-radius: 999px; background: rgba(255,255,255,.1) !important; font-size: 11.5px; }
.zn-peek { max-width: 380px; padding: 7px 14px; border-radius: 999px; background: rgba(20,18,24,.94); box-shadow: 0 8px 22px rgba(0,0,0,.4), inset 0 0 0 1px rgba(255,255,255,.12);
  font-size: 12.5px; display: none; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.zn-peek.on { display: block; animation: znDrop .35s cubic-bezier(.3,1.3,.4,1); } html.zn-open .zn-peek { display: none; }
`;

// ---------- weather behind Aurora (same painter as the Mac's WeatherPainter) ----------
const KIND = c => c === 0 ? 'clear' : c <= 2 ? 'partly' : c === 3 ? 'cloudy' : c <= 48 ? 'fog' : c <= 57 ? 'drizzle' : c <= 67 || (c >= 80 && c <= 82) ? 'rain'
  : c <= 77 || c === 85 || c === 86 ? 'snow' : c >= 95 ? 'storm' : 'clear';
const TINT = { clear: [255, 184, 77], night: [107, 115, 242], partly: [140, 191, 255], cloudy: [179, 189, 209], fog: [179, 189, 209], drizzle: [89, 158, 255], rain: [89, 158, 255], snow: [217, 237, 255], storm: [158, 115, 255] };
const R = (i, s) => { const x = Math.sin((i * 127 + s * 311) * 12.9898) * 43758.5453; return x - Math.floor(x); };
function paintWeather(cx, w, h, t, kind, day) {
  cx.clearRect(0, 0, w, h);
  const sun = () => {
    const c = [w * 0.86, h * 0.62], pulse = 1 + 0.08 * Math.sin(t * 1.6);
    const g = cx.createRadialGradient(c[0], c[1], 2, c[0], c[1], 26 * pulse); g.addColorStop(0, 'rgba(255,165,0,.45)'); g.addColorStop(1, 'rgba(255,165,0,0)');
    cx.fillStyle = g; cx.beginPath(); cx.arc(c[0], c[1], 26 * pulse, 0, 7); cx.fill();
    cx.strokeStyle = 'rgba(255,204,102,.55)'; cx.lineWidth = 1.4; cx.lineCap = 'round';
    for (let i = 0; i < 10; i++) { const a = i / 10 * Math.PI * 2 + t * 0.25, l = 15 + 2 * Math.sin(t * 2 + i);
      cx.beginPath(); cx.moveTo(c[0] + Math.cos(a) * 9, c[1] + Math.sin(a) * 9); cx.lineTo(c[0] + Math.cos(a) * l, c[1] + Math.sin(a) * l); cx.stroke(); }
    cx.fillStyle = 'rgba(255,217,128,.85)'; cx.beginPath(); cx.arc(c[0], c[1], 6, 0, 7); cx.fill();
  };
  const stars = n => {
    for (let i = 0; i < n; i++) { const tw = 0.35 + 0.65 * Math.max(0, Math.sin(t * (0.8 + R(i, 3) * 1.6) + R(i, 4) * 6)), s = 0.8 + R(i, 5) * 1.3;
      cx.fillStyle = `rgba(255,255,255,${0.75 * tw})`; cx.beginPath(); cx.arc(R(i, 1) * w, h * 0.3 + R(i, 2) * h * 0.65, s / 2, 0, 7); cx.fill(); }
    cx.fillStyle = 'rgba(242,242,242,.8)'; cx.beginPath(); cx.arc(w * 0.87, h * 0.62, 6, 0, 7); cx.fill();
    cx.fillStyle = 'rgba(0,0,0,.9)'; cx.beginPath(); cx.arc(w * 0.87 + 3.5, h * 0.62 - 2, 6, 0, 7); cx.fill();
  };
  const clouds = (n, alpha) => {
    for (let i = 0; i < n; i++) { const span = w + 80, x = ((R(i, 8) * span + t * (4 + R(i, 7) * 5)) % span) - 40, y = h * (0.45 + R(i, 9) * 0.35), s = 0.8 + R(i, 10) * 0.6;
      cx.fillStyle = `rgba(255,255,255,${alpha})`; cx.beginPath(); cx.ellipse(x + 13 * s, y + 5 * s, 13 * s, 5 * s, 0, 0, 7); cx.ellipse(x + 13 * s, y, 7 * s, 6 * s, 0, 0, 7); cx.ellipse(x + 19 * s, y + 2 * s, 6 * s, 5 * s, 0, 0, 7); cx.fill(); }
  };
  const rain = (n, speed, len, alpha) => {
    cx.lineWidth = 1; cx.lineCap = 'round';
    for (let i = 0; i < n; i++) { const sp = speed * (0.75 + R(i, 12) * 0.5), y = ((R(i, 13) * (h + len) + t * sp) % (h + len)) - len, x = R(i, 11) * (w + 20) - 10 - (y / h) * 4;
      cx.strokeStyle = `rgba(179,217,255,${alpha * (0.5 + R(i, 14) * 0.5)})`; cx.beginPath(); cx.moveTo(x, y); cx.lineTo(x - 1.5, y + len); cx.stroke(); }
  };
  const snow = () => { for (let i = 0; i < 26; i++) { const y = ((R(i, 16) * (h + 6) + t * (8 + R(i, 15) * 10)) % (h + 6)) - 3, x = R(i, 17) * w + Math.sin(t * (0.6 + R(i, 18)) + i) * 5, s = 1.4 + R(i, 19) * 1.8;
    cx.fillStyle = `rgba(255,255,255,${0.55 + 0.35 * R(i, 20)})`; cx.beginPath(); cx.arc(x, y, s / 2, 0, 7); cx.fill(); } };
  const fog = () => { for (let i = 0; i < 3; i++) { cx.fillStyle = `rgba(255,255,255,${0.12 + 0.05 * i})`; cx.beginPath(); cx.roundRect(-20 + Math.sin(t * 0.4 + i) * 18, h * (0.5 + i * 0.16), w + 40, 4, 2); cx.fill(); } };
  const bolt = () => { const c = t % 6; if (!(c < 0.06 || (c > 0.11 && c < 0.16))) return;
    cx.fillStyle = 'rgba(204,204,255,.18)'; cx.fillRect(0, 0, w, h); const x = w * (0.2 + R(Math.floor(t / 6), 21) * 0.6);
    cx.strokeStyle = 'rgba(255,255,255,.85)'; cx.lineWidth = 1.4; cx.beginPath(); cx.moveTo(x, h * 0.3); cx.lineTo(x - 4, h * 0.55); cx.lineTo(x + 2, h * 0.58); cx.lineTo(x - 3, h * 0.9); cx.stroke(); };
  switch (kind) {
    case 'clear': day ? sun() : stars(18); break;
    case 'partly': day ? sun() : stars(10); clouds(2, 0.22); break;
    case 'cloudy': clouds(4, 0.26); break;
    case 'fog': fog(); break;
    case 'drizzle': clouds(2, 0.18); rain(14, 38, 5, 0.45); break;
    case 'rain': clouds(2, 0.18); rain(30, 70, 8, 0.55); break;
    case 'snow': snow(); break;
    case 'storm': clouds(3, 0.24); rain(34, 85, 9, 0.55); bolt(); break;
  }
}

export function mountNotch(api) {
  const { D, expand, collapse, getState, Voice, openFull, html } = api;
  const st = document.createElement('style'); st.textContent = CSS; document.head.appendChild(st);
  html.classList.add('zn');
  const zn = document.createElement('div'); zn.id = 'zn';
  zn.innerHTML = `
    <div class="zn-tab" title="Open Zuffi"><canvas class="zn-wx"></canvas><span class="zn-temp"><span class="zn-ico"></span><b></b></span><canvas class="zn-face"></canvas></div>
    <div class="zn-bar">
      <button class="zn-round zn-menu" title="Everything Zuffi can do">${ico('grid', 13)}</button>
      <input class="zn-ask" placeholder="Ask Zuffi anything…" spellcheck="false" autocomplete="off">
      <button class="zn-prov" title="Which AI answers"></button>
      <button class="zn-talk" title="Talk with Zuffi — tap to start, tap again to stop">${ico('wave', 14, 2.6)}</button>
    </div>
    <div class="zn-listen"><span class="bars"><i></i><i></i><i></i><i></i></span><b>Listening…</b><button class="zn-stop" title="Stop"><i></i></button></div>
    <div class="zn-banner"><span>⏰</span><b></b><button class="later">Snooze</button><button class="ok">Got it</button></div>
    <div class="zn-card zn-panel"></div>
    <div class="zn-card zn-answer"></div>
    <div class="zn-peek"></div>`;
  document.body.appendChild(zn);
  const $ = s => zn.querySelector(s);
  const tab = $('.zn-tab'), wx = $('.zn-wx'), panel = $('.zn-panel'), answer = $('.zn-answer'), ask = $('.zn-ask'), peekEl = $('.zn-peek'), banner = $('.zn-banner');
  const aurora = new Aurora3D($('.zn-face'), { framing: 'closeFace' });
  window.ZuffiAurora = aurora;

  // ---------- open / closed follows the island state ----------
  let page = null, asked = '', reply = '', thinking = false;
  const sync = () => {
    const open = getState() === 'expanded';
    html.classList.toggle('zn-open', open);
    if (open) setTimeout(() => ask.focus({ preventScroll: true }), 120);
    else { page = null; render(); }
    setTimeout(report, 460);
  };
  new MutationObserver(sync).observe(html, { attributes: true, attributeFilter: ['class'] });
  tab.onclick = () => (getState() === 'expanded' ? collapse() : expand());
  $('.zn-menu').onclick = () => { page = page ? null : 'grid'; if (page) { reply = ''; asked = ''; } render(); };

  // ---------- where the mouse can click (everything else clicks through to your apps) ----------
  function report() {
    const els = [tab, ...zn.querySelectorAll('.zn-bar, .zn-listen, .zn-card.on, .zn-banner.on, .zn-peek.on')].filter(e => e.offsetParent !== null);
    D.hitRects?.(els.map(e => { const r = e.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height + 2 }; }));
  }
  new ResizeObserver(report).observe(zn); setInterval(report, 1500);
  D.onCursor?.(p => { const r = tab.getBoundingClientRect(); aurora.look(p.x - (r.left + r.width / 2), p.y - (r.top + r.height)); });

  // ---------- weather ----------
  let kind = 'clear', day = true, tint = TINT.clear;
  const applyTint = () => { const [r, g, b] = tint; zn.style.setProperty('--tint28', `rgba(${r},${g},${b},.28)`); zn.style.setProperty('--tint22', `rgba(${r},${g},${b},.22)`); zn.style.setProperty('--tint45', `rgba(${r},${g},${b},.45)`); };
  applyTint();
  async function refreshWeather() {
    try {
      const w = await weather(); if (!w) return;
      kind = KIND(w.code ?? 0); day = w.day !== false;
      tint = TINT[kind === 'clear' || kind === 'partly' ? (day ? kind : 'night') : kind] || TINT.clear; applyTint();
      const icon = { clear: day ? '☀️' : '🌙', partly: day ? '⛅' : '☁️', cloudy: '☁️', fog: '🌫️', drizzle: '🌦️', rain: '🌧️', snow: '🌨️', storm: '⛈️' }[kind];
      $('.zn-ico').textContent = icon; $('.zn-temp b').textContent = `${w.temp}°`; $('.zn-temp').classList.add('show');
    } catch {}
  }
  refreshWeather(); setInterval(refreshWeather, 10 * 60000);
  const wctx = wx.getContext('2d');
  (function draw(ts) {
    const r = wx.getBoundingClientRect(), dpr = devicePixelRatio || 1;
    if (wx.width !== Math.round(r.width * dpr)) { wx.width = Math.round(r.width * dpr); wx.height = Math.round(r.height * dpr); }
    wctx.setTransform(dpr, 0, 0, dpr, 0, 0); paintWeather(wctx, r.width, r.height, ts / 1000, kind, day);
    requestAnimationFrame(draw);
  })(0);

  // ---------- the AI chip ----------
  const provName = () => { const s = store.settings, p = s.provider || 'groq'; return p === 'ollama' ? 'Ollama (local)' : p === 'auto' ? 'Auto' : (PROVIDERS[p]?.name || p).replace(/\s*\(.*$/, ''); };
  const prov = $('.zn-prov'); prov.textContent = provName(); store.onChange?.(() => (prov.textContent = provName()));
  prov.onclick = () => openFull('settings');

  // ---------- asking ----------
  const WORDS = ['Thinking…', 'Reading what you asked…', 'Putting it together…', 'Choosing my words…', 'Almost there…'];
  let wordT = null;
  const think = () => `<div class="zn-think"><span class="d"><i></i><i></i><i></i></span><span class="w in">${WORDS[0]}</span></div>`;
  function send(text) {
    text = String(text || '').trim(); if (!text) return;
    asked = text; reply = ''; thinking = true; page = null; aurora.setMood('thinking'); render();
    const inp = document.querySelector('#askInput'), form = document.querySelector('#askForm');
    if (inp && form) { inp.value = text; form.requestSubmit ? form.requestSubmit() : form.dispatchEvent(new Event('submit', { cancelable: true })); }
  }
  ask.addEventListener('keydown', e => { if (e.key === 'Enter') { const v = ask.value; ask.value = ''; send(v); } if (e.key === 'Escape') collapse(); });
  document.addEventListener('zuffi-said', e => {
    const text = String(e.detail || '');
    thinking = false; aurora.setMood('smile');
    aurora.talk(true, text); clearTimeout(talkT); talkT = setTimeout(() => aurora.talk(false), Math.min(30000, 500 + text.length / 14.5 * 1000));
    if (getState() === 'expanded') { if (asked) reply = text; render(); }
  });
  let talkT = null;
  $('.zn-talk').onclick = () => Voice.toggle();
  $('.zn-stop').onclick = () => Voice.toggle();
  // listening strip follows the voice
  new MutationObserver(() => html.classList.toggle('zn-listening', html.classList.contains('isl-listening'))).observe(html, { attributes: true, attributeFilter: ['class'] });

  // ---------- reminder banner (same as the Mac's, under the bar) ----------
  const alertEl = document.querySelector('#alert');
  if (alertEl) new MutationObserver(() => {
    const on = !alertEl.hidden;
    banner.classList.toggle('on', on);
    if (on) { banner.querySelector('b').textContent = [document.querySelector('#alertTitle')?.textContent, document.querySelector('#alertSub')?.textContent].filter(Boolean).join(' · '); aurora.setMood('surprised'); setTimeout(() => aurora.setMood('smile'), 1500); }
    banner.querySelector('.later').style.display = document.querySelector('#alertSnooze')?.hidden ? 'none' : '';
    report();
  }).observe(alertEl, { attributes: true, attributeFilter: ['hidden'] });
  banner.querySelector('.ok').onclick = () => { document.querySelector('#alertDone')?.click(); aurora.setMood('happy'); setTimeout(() => aurora.setMood('smile'), 2500); };
  banner.querySelector('.later').onclick = () => { document.querySelector('#alertSnooze')?.click(); aurora.setMood('cross'); setTimeout(() => aurora.setMood('smile'), 2200); };

  // ---------- what the card under the bar shows ----------
  function render() {
    clearInterval(wordT);
    panel.classList.toggle('on', !!page);
    answer.classList.toggle('on', !page && !!asked);
    if (page === 'grid') {
      panel.innerHTML = `<div class="zn-grid">${MENU.map(([id, name, icon]) => `<button class="zn-item" data-p="${id}">${ico(icon, 15)}<span>${name}</span>${id === 'pet' ? `<i class="zn-switch ${petOn ? 'on' : ''}"></i>` : ''}</button>`).join('')}</div>`;
    } else if (page === 'chat') {
      const msgs = (store.chat || []).slice(-12);
      panel.innerHTML = `<div class="zn-head"><button class="zn-back" data-p="grid">${ico('back', 13, 2.4)}</button><b>Chat</b><button class="zn-pill" data-a="new">New</button></div>`
        + (msgs.length ? msgs.map(m => m.role === 'user' ? `<div class="zn-msg-u"><span>${esc(m.text)}</span></div>` : `<div class="zn-msg-b">${esc(m.text)}</div>`).join('') : '<p class="zn-soft">Type in the bar above or tap the talk button. This is a new chat.</p>')
        + (thinking ? think() : '');
      setTimeout(() => (panel.scrollTop = panel.scrollHeight), 30);
    }
    if (!page && asked) {
      answer.innerHTML = `<div class="zn-q"><span>${esc(asked)}</span></div>` + (thinking ? think() : `<div class="zn-a">${esc(reply)}</div>
        <div class="zn-acts"><button data-a="copy">Copy</button><button data-a="again">Listen again</button><button data-a="clear" title="Clear">${ico('x', 10, 3)}</button></div>`);
    }
    if (thinking) { let n = 0; wordT = setInterval(() => { const w = zn.querySelector('.zn-think .w'); if (!w) return; n++; w.textContent = WORDS[n % WORDS.length]; w.classList.remove('in'); void w.offsetWidth; w.classList.add('in'); }, 1800); }
    setTimeout(report, 30);
  }
  let petOn = true; D.getSettings?.().then(s => { petOn = s.pet !== false; });
  zn.addEventListener('click', e => {
    const p = e.target.closest('[data-p]'), a = e.target.closest('[data-a]');
    if (p) {
      const id = p.dataset.p;
      if (id === 'pet') { petOn = !petOn; D.setSetting('pet', petOn); render(); }
      else if (id === 'grid' || id === 'chat') { page = id; render(); }
      else if (id === 'whatsapp') { if (D.openApp?.('WhatsApp') === false) window.open('https://web.whatsapp.com'); collapse(); }
      else { openFull(FULL[id] || 'home', id); collapse(); }
    }
    if (a) {
      const act = a.dataset.a;
      if (act === 'new') { (store.chat || []).splice(0); store.save?.(); render(); }
      if (act === 'copy') navigator.clipboard?.writeText(reply);
      if (act === 'again') window.Sparrow?.speak?.(reply);
      if (act === 'clear') { asked = ''; reply = ''; render(); }
    }
  });
  answer.addEventListener('dblclick', () => { asked = ''; reply = ''; render(); });

  // ---------- closed: short messages peek under the tab ----------
  window.ZuffiNotchPeek = (text, ms = 5000) => {
    if (getState() === 'expanded') return;
    peekEl.textContent = text; peekEl.classList.add('on'); report();
    aurora.talk(true, text); setTimeout(() => aurora.talk(false), Math.min(6000, 400 + text.length * 70));
    clearTimeout(peekEl.t); peekEl.t = setTimeout(() => { peekEl.classList.remove('on'); report(); }, ms);
  };
  sync();
  return { send, aurora };
}
