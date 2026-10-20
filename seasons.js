// Zuffi's outfits and seasons. Pick one, or let Zuffi follow the calendar (Ramadan and Eid follow the Islamic calendar).
// Each season brings an outfit (mascots/outfits/…), a colour for the app, and a little scene on the Home card.
import { store } from './store.js';
import { setSheets } from './mascot.js';

export const EVENTS = [
  { id: 'none',         name: 'Everyday',        icon: '🐰', accent: null,      sky: null,                     fx: null,       says: '' },
  { id: 'winter',       name: 'Winter',          icon: '❄️', accent: '#8EC5FF', sky: ['#13213A', '#2B4A6E'],    fx: 'snow',     says: 'Wrap up warm today.' },
  { id: 'ramadan',      name: 'Ramadan',         icon: '🌙', accent: '#E9C46A', sky: ['#0B1A24', '#1B3546'],    fx: 'lanterns', says: 'Ramadan Mubarak.' },
  { id: 'eid',          name: 'Eid',             icon: '✨', accent: '#4FD1A5', sky: ['#0E2823', '#1D4A3F'],    fx: 'confetti', says: 'Eid Mubarak!', colors: ['#E9C46A', '#4FD1A5', '#FFFFFF'] },
  { id: 'independence', name: '14 August',       icon: '🇵🇰', accent: '#2FA866', sky: ['#0A2414', '#145230'],    fx: 'confetti', says: 'Jashn-e-Azadi Mubarak!', colors: ['#2FA866', '#FFFFFF'] },
  { id: 'christmas',    name: 'Christmas',       icon: '🎄', accent: '#F0525A', sky: ['#1E1115', '#3A1D24'],    fx: 'snow',     says: 'Merry Christmas!' },
  { id: 'halloween',    name: 'Halloween',       icon: '🎃', accent: '#F28A3C', sky: ['#16101D', '#33203B'],    fx: 'embers',   says: 'Happy Halloween!' },
  { id: 'valentine',    name: 'Valentine’s',     icon: '💗', accent: '#F27BA1', sky: ['#25101B', '#47203A'],    fx: 'hearts',   says: 'Happy Valentine’s Day.' },
  { id: 'birthday',     name: 'My birthday',     icon: '🎂', accent: '#B79CFF', sky: ['#19152E', '#352C5E'],    fx: 'confetti', says: 'Happy birthday!', colors: ['#FFD166', '#F27BA1', '#7FD8BE', '#B79CFF'] },
  { id: 'summer',       name: 'Summer',          icon: '🌺', accent: '#FFC857', sky: ['#0E2C3C', '#1B5A70'],    fx: 'sun',      says: 'Stay cool and drink water.' },
];
const byId = id => EVENTS.find(e => e.id === id) || EVENTS[0];

/** Islamic month and day (Umm al-Qura calendar), or null if the device can't tell. */
function hijri(d) {
  try {
    const p = new Intl.DateTimeFormat('en-u-ca-islamic-umalqura', { month: 'numeric', day: 'numeric' }).formatToParts(d);
    const m = +p.find(x => x.type === 'month').value, day = +p.find(x => x.type === 'day').value;
    return m && day ? { m, d: day } : null;
  } catch { return null; }
}
/** Which season it is today: birthday first, then Eid, Ramadan, national days, holidays, then the time of year. */
export function autoEvent(d = new Date()) {
  const s = store.settings, md = (d.getMonth() + 1) * 100 + d.getDate();
  if (s.birthday && s.birthday.slice(5) === `${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`) return 'birthday';
  const h = hijri(d);
  if (h && ((h.m === 10 && h.d <= 3) || (h.m === 12 && h.d >= 10 && h.d <= 13))) return 'eid';
  if (h && h.m === 9) return 'ramadan';
  const pk = /PK|ur/.test((s.country || '') + (navigator.language || '')) || (s.lang === 'ur');
  if (pk && md >= 808 && md <= 815) return 'independence';
  if (md >= 1210 && md <= 1226) return 'christmas';
  if (md >= 1024 && md <= 1031) return 'halloween';
  if (md >= 210 && md <= 214) return 'valentine';
  const south = (s.lastLoc?.lat ?? 30) < 0;
  const m = d.getMonth() + 1;
  if ((!south && (m === 12 || m <= 2)) || (south && m >= 6 && m <= 8)) return 'winter';
  if ((!south && m >= 6 && m <= 8) || (south && (m === 12 || m <= 2))) return 'summer';
  return 'none';
}
export const choice = () => store.settings.outfit || 'auto';
export const current = () => byId(choice() === 'auto' ? autoEvent() : choice());
export const sheetsFor = id => id && id !== 'none'
  ? { directions: `mascots/outfits/zuffi-directions-${id}.webp`, reactions: `mascots/outfits/zuffi-reactions-${id}.webp` }
  : { directions: 'mascots/zuffi-directions.webp', reactions: 'mascots/zuffi-reactions.webp' };

/** The season's colour, when it should win over the chosen colour (null = keep the user's colour). */
export function eventAccent() { const e = current(); return e.accent && store.settings.eventColors === true ? e.accent : null; }

/** Dress Zuffi, colour the app and set the scene on the Home card. */
export function apply() {
  const e = current(), de = document.documentElement;
  de.dataset.event = e.id;
  const sh = sheetsFor(e.id); setSheets(sh.directions, sh.reactions);
  window.zuffiOutfitId = e.id;                                                   // the walking pet on the web / iPhone
  try { window.SparrowNative?.setOutfit?.(e.id); } catch {}                     // Android: the bunny walking over other apps
  try { window.SparrowDesktop?.setSetting?.('outfit', e.id); } catch {}          // Windows: the desktop pet
  const acc = eventAccent();
  window.zuffiEventAccent = acc;
  if (acc) de.style.setProperty('--accent', acc);
  else if (window.zuffiUserAccent) de.style.setProperty('--accent', window.zuffiUserAccent);
  else de.style.removeProperty('--accent');
  if (e.sky) { de.style.setProperty('--sky1', e.sky[0]); de.style.setProperty('--sky2', e.sky[1]); }
  else { de.style.removeProperty('--sky1'); de.style.removeProperty('--sky2'); }
  const host = document.querySelector('.hero-fx');
  if (host && host.dataset.ev !== e.id) { host.dataset.ev = e.id; host.innerHTML = scene(e); }
  const tag = document.querySelector('#lookTag');
  if (tag) { tag.hidden = e.id === 'none'; tag.innerHTML = `<span>${e.icon}</span>${e.name} look`; }
  document.dispatchEvent(new CustomEvent('zuffi-look', { detail: e }));
  return e;
}

// ---------- the little scene behind Zuffi (CSS does the moving; nothing moves with "reduce motion") ----------
const rnd = (a, b) => a + Math.random() * (b - a);
function scene(e) {
  const n = { snow: 26, confetti: 22, hearts: 9, embers: 14, lanterns: 0, sun: 0 }[e.fx] ?? 0;
  let out = '';
  for (let i = 0; i < n; i++) {
    const st = `left:${rnd(0, 100).toFixed(1)}%;animation-delay:-${rnd(0, 12).toFixed(1)}s;animation-duration:${rnd(7, 14).toFixed(1)}s;--s:${rnd(.5, 1.2).toFixed(2)};--x:${rnd(-18, 18).toFixed(0)}px`;
    if (e.fx === 'snow') out += `<i class="fx-snow" style="${st}"></i>`;
    else if (e.fx === 'confetti') out += `<i class="fx-conf" style="${st};background:${e.colors[i % e.colors.length]};--r:${rnd(0, 360).toFixed(0)}deg"></i>`;
    else if (e.fx === 'hearts') out += `<i class="fx-heart" style="${st}">♥</i>`;
    else if (e.fx === 'embers') out += `<i class="fx-ember" style="${st}"></i>`;
  }
  if (e.fx === 'lanterns') out += [5, 33].map((x, i) => `<span class="fx-lantern" style="left:${x}%;--h:${[30, 10][i]}px;animation-delay:-${i * 0.9}s"><b></b></span>`).join('')
    + Array.from({ length: 14 }, () => `<i class="fx-star" style="left:${rnd(2, 98).toFixed(1)}%;top:${rnd(6, 60).toFixed(1)}%;animation-delay:-${rnd(0, 4).toFixed(1)}s"></i>`).join('');
  if (e.fx === 'sun') out += '<span class="fx-sun"></span>';
  return out;
}
