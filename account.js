// Zuffi account: sign in with an email code, keep a signed licence (works offline for a week),
// and tell the rest of the app which plan this device has — free, pro or business.
// The server is the company website (lisansystems.com/api/zuffi). Nothing here holds a card or a password.

const API = () => { try { return localStorage.getItem('zuffiApi') || 'https://lisansystems.com/api/zuffi'; } catch { return 'https://lisansystems.com/api/zuffi'; } };
export const SITE = () => API().replace(/\/api\/zuffi$/, '/zuffi');
const KEY = 'zuffiAccount', DEV = 'zuffiDeviceId', PUB = 'zuffiLicenceKey';
const LS = { get(k) { try { return localStorage.getItem(k); } catch { return null; } }, set(k, v) { try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch {} } };

let st = {}; try { st = JSON.parse(LS.get(KEY) || '{}'); } catch { st = {}; }
// The plan is never read straight from storage: the signed licence is checked again every time Zuffi starts.
const save = () => { const { lic: _a, ...keep } = st; LS.set(KEY, JSON.stringify(keep)); };
const emit = () => {
  document.dispatchEvent(new CustomEvent('zuffi-plan', { detail: { plan: plan(), account: st.account || null } }));
  try { window.SparrowHost === 'mac' && window.SparrowMac?.post('plan', { plan: plan(), email: email(), freeLeads: freeLeads() }); } catch {}
};

export function deviceId() {
  let d = LS.get(DEV);
  if (!d) { d = 'z' + Array.from(crypto.getRandomValues(new Uint8Array(12)), b => b.toString(16).padStart(2, '0')).join(''); LS.set(DEV, d); }
  return d;
}
export function platform() {
  if (window.SparrowNative) return 'android';
  if (window.SparrowHost === 'mac') return 'mac';
  if (window.SparrowDesktop) return window.SparrowDesktop.platform?.() === 'mac' ? 'mac' : 'windows';
  return /iPhone|iPad/.test(navigator.userAgent) ? 'iphone' : 'browser';
}
function deviceName() {
  const p = platform();
  return { android: 'Android phone', iphone: /iPad/.test(navigator.userAgent) ? 'iPad' : 'iPhone', mac: 'Mac', windows: 'Windows PC', browser: 'Web app' }[p];
}

async function call(path, body, method = 'POST') {
  let r;
  try {
    r = await fetch(API() + path, { method, headers: { 'Content-Type': 'application/json', ...(st.token ? { Authorization: 'Bearer ' + st.token } : {}) },
      body: method === 'GET' ? undefined : JSON.stringify(body || {}) });
  } catch { return { ok: false, status: 0, net: true }; }          // really couldn't reach the server
  let j = {}; try { j = await r.json(); } catch {}
  j.status = r.status;
  if (r.status === 401 && st.token) { st.token = ''; st.lic = null; st.account = null; save(); emit(); }
  return j;
}

// ---------- licence: signed by the server, checked here ----------
const b64u = s => Uint8Array.from(atob(s.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((s.length + 3) % 4)), c => c.charCodeAt(0));
async function publicKey(fresh = false) {
  let k = fresh ? null : LS.get(PUB);
  if (!k) { const j = await call('/pubkey', null, 'GET'); if (j.ok && j.key) { k = j.key; LS.set(PUB, k); } }   // fetched once, then kept
  return k;
}
let edOk = null;   // can this browser check Ed25519 signatures? (Chrome 137+, Safari 17+, recent Android WebView)
async function edSupported() {
  if (edOk === null) { try { await crypto.subtle.generateKey({ name: 'Ed25519' }, false, ['sign', 'verify']); edOk = true; } catch { edOk = false; } }
  return edOk;
}
async function verifySig(payload, sig, fresh = false) {
  const k = await publicKey(fresh); if (!k) return false;
  let key;
  try { const raw = Uint8Array.from(atob(k), c => c.charCodeAt(0)); if (raw.length !== 32) throw 0; key = await crypto.subtle.importKey('raw', raw, { name: 'Ed25519' }, false, ['verify']); }
  catch { if (!fresh) { LS.set(PUB, null); return verifySig(payload, sig, true); } return false; }   // a broken saved key: fetch it again once
  try { return await crypto.subtle.verify({ name: 'Ed25519' }, key, b64u(sig), new TextEncoder().encode(payload)); } catch { return false; }
}
async function checkLicence(lic, fromServer = false) {
  if (!lic || !lic.includes('.')) return null;
  const [payload, sig] = lic.split('.');
  let p; try { p = JSON.parse(new TextDecoder().decode(b64u(payload))); } catch { return null; }
  if (p.d !== deviceId()) return null;
  if (await edSupported()) return (await verifySig(payload, sig)) ? p : null;
  // This browser can't check Ed25519 yet: only trust a licence that just came from our server over HTTPS.
  return fromServer ? p : null;
}

/** The plan this device can use right now (works offline until the licence runs out). */
export function plan() {
  const p = st.lic;
  if (!st.token || !p || p.d !== deviceId() || p.exp * 1000 < Date.now()) return 'free';
  return ['trial', 'pro', 'business'].includes(p.p) ? p.p : 'free';
}
/** pro, business or the trial: Zuffi works. 'free' means no plan any more — the app shows the paywall. */
export const isPaid = () => plan() !== 'free';
export const isBusiness = () => plan() === 'business' || plan() === 'trial';   // the trial switches everything on
export const isTrial = () => plan() === 'trial';
export const locked = () => plan() === 'free';
export const trialEnds = () => (plan() === 'trial' && st.lic?.exp) ? new Date(st.lic.exp * 1000) : null;
export const hadTrial = () => !!st.account?.trial_ends_at;
export const signedIn = () => !!st.token;
export const account = () => st.account || null;
export const email = () => st.account?.email || st.email || '';
export const freeLeads = () => st.account?.free_leads || 30;

let expT = 0;
async function take(acct) {
  st.account = acct; st.email = acct?.email || st.email;
  const p = await checkLicence(acct?.licence, true);
  st.lic = p; st.checkedAt = Date.now(); save(); emit();
  if (p?.exp) { clearTimeout(expT); const ms = p.exp * 1000 - Date.now(); if (ms > 0 && ms < 2 ** 31) expT = setTimeout(emit, ms + 500); }   // lock the moment the trial ends
}

/** Ask the server for the latest plan (once a day, at start, and after buying). */
export async function refresh(force = false) {
  if (!st.token) { emit(); return plan(); }
  if (!force && st.checkedAt && Date.now() - st.checkedAt < 6 * 3600e3) { emit(); return plan(); }
  try { const j = await call('/me', null, 'GET'); if (j.ok) await take(j.account); } catch { /* offline: the stored licence still counts */ }
  return plan();
}

/** A clear reason, not always "check your internet". */
function why(j, step) {
  if (j.status === 429) return 'Too many tries — wait a few minutes, then try again.';
  if (j.error) return j.error;
  if (j.net) return 'Couldn’t reach Zuffi — check your internet and try again.';
  if (j.status >= 500) return step === 'verify' ? 'Something went wrong on our side. Your code still works for 10 minutes — please try again in a moment.' : 'Something went wrong on our side. Please try again in a moment.';
  return step === 'verify' ? 'Couldn’t sign in. Check the code and try again.' : 'Couldn’t send the code. Please try again.';
}

export async function startSignIn(addr) {
  const j = await call('/auth/start', { email: String(addr || '').trim() });
  if (j.ok) { st.email = String(addr).trim().toLowerCase(); save(); }
  return j.ok ? { ok: true } : { ok: false, error: why(j, 'send') };
}
/** → {ok} · {ok:false, deviceLimit:[…devices]} · {ok:false, error} */
export async function finishSignIn(code, replace) {
  const j = await call('/auth/verify', { email: st.email, code, device_id: deviceId(), device_name: deviceName(), platform: platform(), ...(replace ? { replace } : {}) });
  if (j.ok && j.account?.licence) { st.token = j.token; await take(j.account); return { ok: true }; }
  if (j.ok) return { ok: false, error: 'Something went wrong on our side. Please try again in a moment.' };
  if (j.error === 'device_limit') return { ok: false, deviceLimit: j.devices, max: j.max };
  return { ok: false, error: why(j, 'verify') };
}
export async function signOut() { try { await call('/logout'); } catch {} st = { email: st.email }; save(); emit(); }
export async function removeDevice(id) { const j = await call('/devices/remove', { device_id: id }); await refresh(true); return j.ok; }

/** Open the website to buy or change a plan — already signed in. */
export async function upgradeUrl(which = 'pro') {
  if (!st.token) return SITE() + '#pricing';
  const j = await call('/handoff', { plan: which });
  return j.ok ? j.url : SITE() + '/account?plan=' + which;
}
export async function manageUrl() {
  const j = await call('/portal');
  if (j.ok) return j.url;
  const h = await call('/handoff', {});
  return h.ok ? h.url : SITE() + '/account';
}

/** Built-in AI for Pro and Business: {text} or throws Error('upgrade' | 'limit' | message). */
export async function ai(messages, maxTokens = 700) {
  if (!isPaid()) throw new Error('upgrade');
  const j = await call('/ai', { messages, max_tokens: maxTokens });
  if (j.ok) return j.text;
  throw new Error(j.status === 402 ? 'upgrade' : j.error === 'limit' ? 'limit' : j.error || 'AI unavailable');
}

// at start: check the saved licence (works offline)
const ready = (async () => {
  delete st.lic;
  if (st.token && st.account?.licence) { st.lic = await checkLicence(st.account.licence); }
  emit();
  if (st.lic?.exp) { const ms = st.lic.exp * 1000 - Date.now(); if (ms > 0 && ms < 2 ** 31) expT = setTimeout(emit, ms + 500); }
})();
export const whenReady = () => ready;

window.zuffiAccount = { plan, isPaid, isBusiness, isTrial, locked, trialEnds, signedIn, account, email, refresh, upgradeUrl, manageUrl, freeLeads, whenReady };
ready.then(() => setTimeout(() => refresh(!!st.token && (!st.lic || plan() === 'free' || plan() === 'trial')), 1500));   // couldn’t check it here → ask the server now
setInterval(() => refresh(), 6 * 3600e3);
