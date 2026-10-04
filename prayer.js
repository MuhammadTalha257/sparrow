// Prayer times, calculated on the device (no internet needed once the location is known).
// Standard astronomical method (sun declination + equation of time), as used by most prayer apps.

export const METHODS = {
  Auto: { name: 'Automatic — official times for where you are' },
  Karachi: { name: 'University of Islamic Sciences, Karachi', fajr: 18, isha: 18 },
  MWL: { name: 'Muslim World League', fajr: 18, isha: 17 },
  ISNA: { name: 'ISNA (North America)', fajr: 15, isha: 15 },
  Egypt: { name: 'Egyptian General Authority', fajr: 19.5, isha: 17.5 },
  Makkah: { name: 'Umm al-Qura, Makkah', fajr: 18.5, ishaMin: 90 },
  Gulf: { name: 'Gulf region', fajr: 19.5, ishaMin: 90 },
};
export const NAMES = ['Fajr', 'Sunrise', 'Dhuhr', 'Asr', 'Maghrib', 'Isha'];

const rad = d => d * Math.PI / 180, deg = r => r * 180 / Math.PI;
const sin = d => Math.sin(rad(d)), cos = d => Math.cos(rad(d)), tan = d => Math.tan(rad(d));
const asin = x => deg(Math.asin(x)), acos = x => deg(Math.acos(x)), atan2 = (y, x) => deg(Math.atan2(y, x));
const acot = x => deg(Math.atan(1 / x));
const fix = (a, b) => { a = a - b * Math.floor(a / b); return a < 0 ? a + b : a; };
const fixAngle = a => fix(a, 360), fixHour = a => fix(a, 24);

function julian(y, m, d) {
  if (m <= 2) { y -= 1; m += 12; }
  const A = Math.floor(y / 100), B = 2 - A + Math.floor(A / 4);
  return Math.floor(365.25 * (y + 4716)) + Math.floor(30.6001 * (m + 1)) + d + B - 1524.5;
}
function sunPosition(jd) {
  const D = jd - 2451545.0;
  const g = fixAngle(357.529 + 0.98560028 * D);
  const q = fixAngle(280.459 + 0.98564736 * D);
  const L = fixAngle(q + 1.915 * sin(g) + 0.020 * sin(2 * g));
  const e = 23.439 - 0.00000036 * D;
  const RA = atan2(cos(e) * sin(L), cos(L)) / 15;
  return { decl: asin(sin(e) * sin(L)), eqt: q / 15 - fixHour(RA) };
}

/**
 * Prayer times for a date and place. Returns { Fajr: Date, Sunrise: Date, ... }.
 * method: key of METHODS; asr: 'Hanafi' | 'Shafi'
 */
// ---------- Automatic: the official method for your area, checked online (aladhan.com) and kept for offline days ----------
const OKEY = 'sparrow-prayer-online';
let ONLINE = {};
try { ONLINE = JSON.parse(localStorage.getItem(OKEY) || '{}'); } catch {}
const dayId = (d, lat, lng) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}|${lat.toFixed(2)}|${lng.toFixed(2)}`;

/** Best calculation method for a place (used offline). */
export function autoMethod(lat, lng) {
  if (lat > 23 && lat < 37.5 && lng > 60 && lng < 78) return 'Karachi';        // Pakistan, Afghanistan
  if (lat > 6 && lat < 36 && lng > 68 && lng < 98) return 'Karachi';           // India, Bangladesh
  if (lat > 15 && lat < 33 && lng > 34 && lng < 56) return 'Makkah';           // Saudi Arabia, Gulf
  if (lat > 22 && lat < 32 && lng > 24 && lng < 37) return 'Egypt';
  if (lng < -50 && lat > 10) return 'ISNA';                                    // North America
  return 'MWL';
}

/** Fetches official times for today and the next two days (silently does nothing offline). */
export async function refreshOnline(lat, lng, asr = 'Hanafi') {
  const out = {};
  for (let i = 0; i < 3; i++) {
    const d = new Date(); d.setDate(d.getDate() + i);
    const id = dayId(d, lat, lng);
    if (ONLINE[id]) { out[id] = ONLINE[id]; continue; }
    try {
      const ds = `${String(d.getDate()).padStart(2, '0')}-${String(d.getMonth() + 1).padStart(2, '0')}-${d.getFullYear()}`;
      const r = await fetch(`https://api.aladhan.com/v1/timings/${ds}?latitude=${lat}&longitude=${lng}&school=${asr === 'Hanafi' ? 1 : 0}`);
      const t = (await r.json())?.data?.timings;
      if (t) out[id] = Object.fromEntries(NAMES.map(n => [n, String(t[n]).slice(0, 5)]));
    } catch { return false; }
  }
  ONLINE = out;
  try { localStorage.setItem(OKEY, JSON.stringify(out)); } catch {}
  return true;
}

export function prayerTimes(date, lat, lng, method = 'Karachi', asr = 'Hanafi') {
  if (method === 'Auto') {
    const hit = ONLINE[dayId(date, lat, lng)];
    if (hit) {
      const out = {};
      for (const n of NAMES) { const [h, m] = hit[n].split(':').map(Number); const d = new Date(date); d.setHours(h, m, 0, 0); out[n] = d; }
      return out;
    }
    method = autoMethod(lat, lng);
  }
  const M = METHODS[method] || METHODS.Karachi;
  const tz = -date.getTimezoneOffset() / 60;
  const jDate = julian(date.getFullYear(), date.getMonth() + 1, date.getDate()) - lng / (15 * 24);
  const midDay = t => fixHour(12 - sunPosition(jDate + t).eqt);
  const angleTime = (angle, t, ccw) => {
    const { decl } = sunPosition(jDate + t);
    const noon = midDay(t);
    const T = acos((-sin(angle) - sin(decl) * sin(lat)) / (cos(decl) * cos(lat))) / 15;
    return noon + (ccw ? -T : T);
  };
  const asrTime = (factor, t) => {
    const { decl } = sunPosition(jDate + t);
    return angleTime(-acot(factor + tan(Math.abs(lat - decl))), t);
  };

  // two passes for accuracy
  let t = { Fajr: 5, Sunrise: 6, Dhuhr: 12, Asr: 13, Sunset: 18, Isha: 18 };
  for (let i = 0; i < 2; i++) {
    const p = Object.fromEntries(Object.entries(t).map(([k, v]) => [k, v / 24]));
    t = {
      Fajr: angleTime(M.fajr, p.Fajr, true),
      Sunrise: angleTime(0.833, p.Sunrise, true),
      Dhuhr: midDay(p.Dhuhr),
      Asr: asrTime(asr === 'Hanafi' ? 2 : 1, p.Asr),
      Sunset: angleTime(0.833, p.Sunset),
      Isha: M.ishaMin ? NaN : angleTime(M.isha, p.Isha),
    };
  }
  // high latitudes (e.g. UK summer): fall back to the "angle-based" share of the night
  const night = fixHour(t.Sunrise - t.Sunset);
  const fajrMax = night * M.fajr / 60;
  if (isNaN(t.Fajr) || fixHour(t.Sunrise - t.Fajr) > fajrMax) t.Fajr = t.Sunrise - fajrMax;
  if (M.ishaMin) t.Isha = t.Sunset + M.ishaMin / 60;
  else {
    const ishaMax = night * M.isha / 60;
    if (isNaN(t.Isha) || fixHour(t.Isha - t.Sunset) > ishaMax) t.Isha = t.Sunset + ishaMax;
  }
  t.Maghrib = t.Sunset;
  t.Dhuhr += 1 / 60;   // a minute after the sun passes the middle

  const out = {};
  for (const n of NAMES) {
    const h = fixHour(t[n] + tz - lng / 15);
    const d = new Date(date); d.setHours(0, 0, 0, 0);
    d.setTime(d.getTime() + Math.round(h * 60) * 60000);
    out[n] = d;
  }
  return out;
}

/** The next prayer from now: { name, at } (skips Sunrise). */
export function nextPrayer(lat, lng, method, asr, now = new Date()) {
  for (let day = 0; day < 2; day++) {
    const d = new Date(now); d.setDate(d.getDate() + day);
    const t = prayerTimes(d, lat, lng, method, asr);
    for (const n of NAMES) if (n !== 'Sunrise' && t[n] > now) return { name: n, at: t[n] };
  }
  return null;
}
