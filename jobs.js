// Sparrow's job agent: reads your CV, finds jobs that fit, writes cover letters, helps you apply, and keeps track.
// You always press Submit yourself — Sparrow never applies on your behalf, so your LinkedIn / Indeed accounts stay safe.
import { store } from './store.js';
import { ask } from './ai.js';
import * as mem from './memory.js';
import * as tools from './tools.js';

const KEY = 'sparrow.jobs.v1';
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const M = window.SparrowHost === 'mac' ? window.SparrowMac : null;
let ui = null;        // helpers from app.js: openPanel, openUrl, toast, addMsg, speak, go, pickFiles, closeSheets

export const data = load();
function load() {
  let d = {};
  try { d = JSON.parse(localStorage.getItem(KEY) || '{}'); } catch {}
  return { profile: null, cvId: null, cvName: '', results: [], query: '', where: '', applied: [], keys: {}, country: '', ...d };
}
function save() { try { localStorage.setItem(KEY, JSON.stringify(data)); } catch {} }

export function initJobs(helpers) { ui = helpers; }

// ---------------------------------------------------------------- AI helpers
const SYSTEM = 'You are a sharp, honest career coach and recruiter. Follow the output format exactly. Never invent experience, employers, degrees or skills the person does not have.';
async function ai(prompt, { maxTokens = 1800 } = {}) {
  try { return (await ask(prompt, null, { noHistory: true, system: SYSTEM, maxTokens })).text; }
  catch (e) {
    // In the Mac app the AI keys may live in Sparrow's own settings instead of this panel.
    if (M) { const t = await M.call('complete', { prompt: SYSTEM + '\n\n' + prompt }); if (t) return t; }
    throw e;
  }
}
function parseJSON(text) {
  const s = String(text || '').replace(/```(?:json)?/g, '');
  for (const [a, b] of [['{', '}'], ['[', ']']]) {
    const i = s.indexOf(a), j = s.lastIndexOf(b);
    if (i >= 0 && j > i) { try { return JSON.parse(s.slice(i, j + 1)); } catch {} }
  }
  return null;
}
const noAI = e => e?.message === 'NO_AI' || /NO_AI/.test(e?.message || '');

// ---------------------------------------------------------------- network (no CORS limits in the Mac app)
async function getJSON(url, headers = {}) {
  if (M) {
    const r = await M.call('http', { url, method: 'GET', headers });
    if (r?.status >= 200 && r.status < 300) return JSON.parse(r.text);
    throw new Error('HTTP ' + (r?.status || 0));
  }
  const r = await fetch(url, { headers }); if (!r.ok) throw new Error('HTTP ' + r.status); return r.json();
}
async function postJSON(url, body) {
  if (M) {
    const r = await M.call('http', { url, headers: {}, body: JSON.stringify(body) });
    if (r?.status >= 200 && r.status < 300) return JSON.parse(r.text);
    throw new Error('HTTP ' + (r?.status || 0));
  }
  const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  if (!r.ok) throw new Error('HTTP ' + r.status); return r.json();
}
const withTimeout = (p, ms = 12000) => Promise.race([p, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms))]);
const strip = h => String(h || '').replace(/<style[\s\S]*?<\/style>/gi, ' ').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/&#39;|&rsquo;/g, "'").replace(/&quot;/g, '"').replace(/\s+/g, ' ').trim();

// ---------------------------------------------------------------- 1. CV analysis
const looksLikeCV = f => /\b(cv|resume|résumé|curriculum)\b/i.test(f.name || '') || (/experience/i.test(f.text || '') && /(education|skills)/i.test(f.text || '') && (f.text || '').length > 600);

export async function findCV() {
  if (data.cvId) { const f = await mem.getFile(data.cvId); if (f?.text) return f; }
  const files = await mem.listFiles();
  const hit = files.find(looksLikeCV);
  return hit ? (await mem.getFile(hit.id)) || hit : null;
}
export function isCV(rec) { return !!rec && looksLikeCV(rec); }

export async function analyseCV(file) {
  file = file || await findCV();
  if (!file?.text) return { ok: false, reply: 'Send me your CV first — drop the PDF or Word file here (or on the Sparrow island), then say "analyse my CV".' };
  const prompt = `Analyse this CV and reply ONLY with JSON in exactly this shape:
{"name":"","email":"","phone":"","location":"","linkedin":"","website":"","headline":"one line, e.g. Frontend Developer (React, TypeScript)","years":0,
"skills":["top 15 hard skills"],"strengths":["4-6 specific strengths, citing the CV"],"gaps":["3-5 honest gaps or risks a recruiter would notice"],
"bestRoles":[{"title":"job title to search","why":"short reason"}],"improvements":["5-7 concrete edits to make the CV stronger"],
"score":0,"summary":"2 sentence honest verdict","searchQuery":"the single best job search keyword, e.g. react developer"}
score = 0-100 for how strong the CV is for its best-fit roles. bestRoles: 4-6 entries. Leave unknown fields as "".

CV:
${file.text.slice(0, 14000)}`;
  let p;
  try { p = parseJSON(await ai(prompt, { maxTokens: 2200 })); }
  catch (e) { return { ok: false, reply: noAI(e) ? 'To analyse your CV I need an AI — add a free Groq or Gemini key in Settings → AI.' : 'I couldn’t analyse it just now: ' + e.message }; }
  if (!p) return { ok: false, reply: 'I read your CV but couldn’t make sense of the result. Try "analyse my CV" again.' };
  p.skills = (p.skills || []).filter(Boolean); p.bestRoles = (p.bestRoles || []).filter(r => r?.title);
  data.profile = { ...p, at: Date.now() }; data.cvId = file.id || data.cvId; data.cvName = file.name || data.cvName; save();
  mem.remember('job', 'CV analysed: ' + (p.headline || file.name), p.summary || '');
  const roles = p.bestRoles.slice(0, 3).map(r => r.title).join(', ');
  return { ok: true, reply: `I read your CV${p.name ? ', ' + p.name.split(' ')[0] : ''}. ${p.summary || ''} Best roles for you: ${roles}. Say "find jobs" and I'll look for them.`.replace(/\s+/g, ' ').trim() };
}

// ---------------------------------------------------------------- 2. job search + ranking
const COUNTRY = () => (data.country || (navigator.language || 'en-GB').split('-')[1] || 'GB').toLowerCase();
const ADZUNA = ['gb', 'us', 'in', 'au', 'ca', 'de', 'fr', 'nl', 'pl', 'sg', 'za', 'nz', 'at', 'be', 'br', 'ch', 'es', 'it', 'mx'];

async function srcAdzuna(q, where) {
  const { adzunaId: id, adzunaKey: key } = data.keys; if (!id || !key) return [];
  const cc = ADZUNA.includes(COUNTRY()) ? COUNTRY() : 'gb';
  const j = await getJSON(`https://api.adzuna.com/v1/api/jobs/${cc}/search/1?app_id=${encodeURIComponent(id)}&app_key=${encodeURIComponent(key)}&results_per_page=30&what=${encodeURIComponent(q)}${where ? '&where=' + encodeURIComponent(where) : ''}&content-type=application/json`);
  return (j.results || []).map(r => ({ title: strip(r.title), company: r.company?.display_name || '', location: r.location?.display_name || where || '', url: r.redirect_url,
    desc: strip(r.description), salary: r.salary_min ? `${Math.round(r.salary_min / 1000)}k–${Math.round((r.salary_max || r.salary_min) / 1000)}k` : '', posted: r.created, source: 'Adzuna' }));
}
async function srcReed(q, where) {
  const key = data.keys.reedKey; if (!key) return [];
  const j = await getJSON(`https://www.reed.co.uk/api/1.0/search?keywords=${encodeURIComponent(q)}${where ? '&locationName=' + encodeURIComponent(where) : ''}&resultsToTake=30`, { Authorization: 'Basic ' + btoa(key + ':') });
  return (j.results || []).map(r => ({ title: r.jobTitle, company: r.employerName, location: r.locationName, url: r.jobUrl, desc: strip(r.jobDescription),
    salary: r.minimumSalary ? `£${Math.round(r.minimumSalary / 1000)}k–${Math.round((r.maximumSalary || r.minimumSalary) / 1000)}k` : '', posted: r.date, source: 'Reed' }));
}
async function srcJooble(q, where) {
  const key = data.keys.joobleKey; if (!key) return [];
  const j = await postJSON(`https://jooble.org/api/${encodeURIComponent(key)}`, { keywords: q, location: where || '' });
  return (j.jobs || []).slice(0, 30).map(r => ({ title: strip(r.title), company: r.company || '', location: r.location || where || '', url: r.link, desc: strip(r.snippet), salary: r.salary || '', posted: r.updated, source: 'Jooble' }));
}
async function srcRemotive(q) {
  const j = await getJSON(`https://remotive.com/api/remote-jobs?search=${encodeURIComponent(q)}&limit=25`);
  return (j.jobs || []).map(r => ({ title: r.title, company: r.company_name, location: 'Remote' + (r.candidate_required_location ? ' · ' + r.candidate_required_location : ''), url: r.url,
    desc: strip(r.description).slice(0, 1500), salary: r.salary || '', posted: r.publication_date, source: 'Remotive' }));
}
async function srcJobicy(q) {
  const tag = q.split(/\s+/).find(w => w.length > 2) || q;
  const j = await getJSON(`https://jobicy.com/api/v2/remote-jobs?count=25&tag=${encodeURIComponent(tag)}`);
  return (j.jobs || []).map(r => ({ title: strip(r.jobTitle), company: r.companyName, location: 'Remote' + (r.jobGeo ? ' · ' + r.jobGeo : ''), url: r.url,
    desc: strip(r.jobExcerpt || r.jobDescription).slice(0, 1500), salary: '', posted: r.pubDate, source: 'Jobicy',
    level: { junior: 'entry', entry: 'entry', midweight: 'mid', mid: 'mid', senior: 'senior', manager: 'lead', director: 'lead' }[String(r.jobLevel || '').toLowerCase().split(/[\s-]/)[0]] || '' }));
}
// The Muse: free, filters by level for real (internship, entry, mid, senior, management) and by city.
const COUNTRY_NAME = { gb: 'United Kingdom', us: 'United States', pk: 'Pakistan', in: 'India', ae: 'United Arab Emirates', ca: 'Canada', au: 'Australia', de: 'Germany', fr: 'France', nl: 'Netherlands', ie: 'Ireland', sa: 'Saudi Arabia' };
async function srcMuse(q, where, level) {
  const lv = { internship: ['Internship'], apprentice: ['Internship', 'Entry Level'], entry: ['Entry Level'], mid: ['Mid Level'], senior: ['Senior Level'], lead: ['management'] }[level] || [];
  const CITY_CC = { london: 'gb', manchester: 'gb', birmingham: 'gb', leeds: 'gb', glasgow: 'gb', edinburgh: 'gb', bristol: 'gb', liverpool: 'gb', cambridge: 'gb', oxford: 'gb',
    lahore: 'pk', karachi: 'pk', islamabad: 'pk', rawalpindi: 'pk', dubai: 'ae', 'abu dhabi': 'ae', riyadh: 'sa', 'new york': 'us', 'san francisco': 'us', toronto: 'ca', sydney: 'au', berlin: 'de', dublin: 'ie' };
  const cc = CITY_CC[(where || '').toLowerCase().trim()] || COUNTRY();
  const city = where && !/remote/i.test(where) ? (where.includes(',') ? where : where.replace(/\b\w/g, c => c.toUpperCase()) + ', ' + (COUNTRY_NAME[cc] || 'United Kingdom')) : '';
  const params = p => ['page=' + p, ...lv.map(l => 'level=' + encodeURIComponent(l)), city ? 'location=' + encodeURIComponent(city) : '', /remote/i.test(where || '') ? 'location=' + encodeURIComponent('Flexible / Remote') : ''].filter(Boolean).join('&');
  const pages = await Promise.all([0, 1, 2].map(p => getJSON('https://www.themuse.com/api/public/jobs?' + params(p)).catch(() => ({ results: [] }))));
  const words = q.toLowerCase().split(/\s+/).filter(w => w.length > 2 && !['jobs', 'job', 'the', 'and'].includes(w));
  return pages.flatMap(j => j.results || []).filter(r => {
    const hay = (r.name + ' ' + (r.categories || []).map(c => c.name).join(' ')).toLowerCase();
    return !words.length || words.some(w => hay.includes(w));
  }).slice(0, 25).map(r => ({ title: r.name, company: r.company?.name || '', location: (r.locations || []).map(l => l.name).join(' · ') || where, url: r.refs?.landing_page,
    desc: strip(r.contents).slice(0, 1500), salary: '', posted: r.publication_date, source: 'The Muse',
    level: { internship: 'internship', 'entry level': 'entry', 'mid level': 'mid', 'senior level': 'senior', management: 'lead' }[String(r.levels?.[0]?.name || '').toLowerCase()] || '' }));
}
async function srcArbeitnow(q, where) {
  const j = await getJSON('https://www.arbeitnow.com/api/job-board-api');
  const words = q.toLowerCase().split(/\s+/).filter(w => w.length > 2 && !['developer', 'engineer', 'jobs', 'job'].includes(w));
  return (j.data || []).filter(r => {
    const hay = (r.title + ' ' + (r.tags || []).join(' ')).toLowerCase();
    return words.some(w => hay.includes(w)) && (!where || r.remote || (r.location || '').toLowerCase().includes(where.toLowerCase()));
  }).slice(0, 20).map(r => ({ title: r.title, company: r.company_name, location: r.remote ? 'Remote' : r.location, url: r.url, desc: strip(r.description).slice(0, 1500), salary: '',
    posted: r.created_at ? new Date(r.created_at * 1000).toISOString() : '', source: 'Arbeitnow' }));
}

// ---------------------------------------------------------------- job levels
export const LEVELS = [['', 'Any level'], ['internship', 'Internship'], ['apprentice', 'Apprenticeship'], ['entry', 'Entry / junior'], ['mid', 'Mid level'], ['senior', 'Senior'], ['lead', 'Lead / manager']];
const LEVEL_WORDS = [
  ['internship', /\b(intern(?:ship)?s?|placements?|work experience)\b/],
  ['apprentice', /\b(apprentice(?:ship)?s?|trainees?)\b/],
  ['entry', /\b(entry[ -]level|entry|junior|jr\.?|graduate|grad|fresher|beginner)\b/],
  ['mid', /\b(mid[ -]?level|mid|intermediate|experienced)\b/],
  ['senior', /\b(senior|sr\.?|expert)\b/],
  ['lead', /\b(lead|principal|staff|head of|manager|director)\b/],
];
/** "senior react developer" → { q: 'react developer', level: 'senior' } */
export function splitLevel(q) {
  for (const [lv, re] of LEVEL_WORDS) if (re.test(q.toLowerCase())) return { q: q.toLowerCase().replace(re, ' ').replace(/\s+(level|role)\b/, '').replace(/\s+/g, ' ').trim(), level: lv };
  return { q, level: '' };
}
function levelOf(title) { const t = (title || '').toLowerCase(); for (const [lv, re] of LEVEL_WORDS) if (re.test(t)) return lv; return ''; }
const RANK = { internship: 0, apprentice: 0, entry: 1, mid: 2, senior: 3, lead: 4 };
/** Keeps jobs that fit the wanted level (titles without a level word stay — most ads don't say). */
function fitsLevel(job, level) {
  if (!level) return true;
  const title = (job.title || '').toLowerCase(), text = title + ' ' + (job.desc || '').toLowerCase().slice(0, 1500);
  const l = job.level || levelOf(job.title);
  const years = +(text.match(/\b(\d{1,2})\s*\+?\s*(?:years|yrs)/) || [])[1] || 0;
  if (['internship', 'apprentice', 'entry'].includes(level)) {
    if (/\b(senior|sr\.?|lead|principal|staff|head of|manager|director|architect|vp)\b/.test(title) || years >= 4) return false;
    if (level === 'apprentice') return l ? ['apprentice', 'internship', 'entry'].includes(l) : /\b(apprentice|trainee|junior|graduate|entry|level 3|level 4)\b/.test(text);
    if (level === 'internship') return l ? ['internship', 'apprentice'].includes(l) : /\b(intern|internship|placement|graduate|student)\b/.test(text);
    return l ? ['entry', 'apprentice', 'internship'].includes(l) || (l === 'mid' && years <= 2) : years <= 2;
  }
  if (level === 'mid') return l ? l === 'mid' || (l === 'senior' && years <= 5) || (l === 'entry' && years >= 2) : !/\b(junior|graduate|intern|apprentice|principal|head of|director)\b/.test(title);
  if (level === 'senior') return l ? l === 'senior' || l === 'lead' : !/\b(junior|jr\.?|graduate|intern|internship|apprentice|trainee|entry)\b/.test(title) && (years >= 4 || /\b(senior|sr\.?|lead|principal|staff)\b/.test(title));
  if (level === 'lead') return l ? l === 'lead' || l === 'senior' : /\b(lead|principal|staff|head of|manager|director|architect)\b/.test(title);
  return true;
}

export function searchLinks(q, where, level = data.level || '') {
  const cc = COUNTRY();
  const li = { internship: 1, apprentice: 1, entry: 2, mid: 3, senior: 4, lead: 5 }[level];
  const ind = { internship: 'ENTRY_LEVEL', apprentice: 'ENTRY_LEVEL', entry: 'ENTRY_LEVEL', mid: 'MID_LEVEL', senior: 'SENIOR_LEVEL', lead: 'SENIOR_LEVEL' }[level];
  const qWord = level === 'apprentice' ? q + ' apprentice' : level === 'internship' ? q + ' internship' : q;
  const indeed = { gb: 'uk.indeed.com', us: 'www.indeed.com', pk: 'pk.indeed.com', in: 'in.indeed.com', ae: 'ae.indeed.com', ca: 'ca.indeed.com', au: 'au.indeed.com', sa: 'sa.indeed.com' }[cc] || 'www.indeed.com';
  const e = encodeURIComponent;
  return [
    ['LinkedIn', `https://www.linkedin.com/jobs/search/?keywords=${e(qWord)}${where ? '&location=' + e(where) : ''}${li ? '&f_E=' + li : ''}&sortBy=R`],
    ['Indeed', `https://${indeed}/jobs?q=${e(qWord)}${where ? '&l=' + e(where) : ''}${ind ? '&sc=' + e(`0kf:explvl(${ind});`) : ''}`],
    ['Google Jobs', `https://www.google.com/search?q=${e((level ? (LEVELS.find(l => l[0] === level)?.[1].split(' ')[0] || '') + ' ' : '') + q + ' jobs' + (where ? ' in ' + where : ''))}&ibp=htl;jobs`],
    ...(cc === 'gb' && level === 'apprentice' ? [['GOV.UK apprenticeships', `https://www.findapprenticeship.service.gov.uk/apprenticeships?searchTerm=${e(q)}${where ? '&location=' + e(where) : ''}`]] : []),
    ...(cc === 'pk' ? [['Rozee.pk', `https://www.rozee.pk/job/jsearch/q/${e(qWord)}`]] : []),
  ];
}

export async function searchJobs(q, where = '', level = null) {
  const p = data.profile;
  const sp = splitLevel((q || '').trim());
  level = level ?? (sp.level || data.level || '');
  q = sp.q || p?.searchQuery || p?.bestRoles?.[0]?.title || '';
  where = (where || '').trim();
  data.level = level;
  if (!q) return { ok: false, reply: 'What kind of job? Try "find React developer jobs in London" — or send me your CV and I’ll work it out.' };
  const word = { internship: 'intern', apprentice: 'apprentice', entry: 'junior', senior: 'senior', lead: 'lead' }[level] || '';
  const kq = word ? word + ' ' + q : q;
  data.results = [];
  const sources = [srcAdzuna(kq, where), srcReed(kq, where), srcJooble(kq, where), srcMuse(q, where, level), srcRemotive(word && level !== 'apprentice' ? kq : q), srcJobicy(q), srcArbeitnow(q, where)];
  const settled = await Promise.allSettled(sources.map(s => withTimeout(s)));
  let jobs = settled.flatMap(r => r.status === 'fulfilled' ? r.value : []).filter(j => j.title && j.url && fitsLevel(j, level));
  const seen = new Set();
  jobs = jobs.filter(j => { const k = (j.title + '|' + j.company).toLowerCase().replace(/\W+/g, ''); if (seen.has(k)) return false; seen.add(k); return true; });
  // Jobs in the place you asked for come before remote ones.
  if (where) jobs.sort((a, b) => (b.location || '').toLowerCase().includes(where.toLowerCase()) - (a.location || '').toLowerCase().includes(where.toLowerCase()));
  jobs = jobs.slice(0, 30);
  data.query = q; data.where = where;
  if (!jobs.length) {
    data.results = []; save();
    const lvName = level ? (LEVELS.find(l => l[0] === level)?.[1] || '').toLowerCase() + ' ' : '';
    return { ok: true, reply: level
      ? `I couldn't find ${lvName}${q} jobs${where ? ' in ' + where : ''} on the free job boards right now. Tap LinkedIn or Indeed below — they're already filtered to ${lvName.trim()}${where ? ' in ' + where : ''}.${!data.keys.reedKey && !data.keys.adzunaId ? ' Adding a free Reed or Adzuna key (Sources tab) gives far more local results.' : ''}`
      : `I couldn't fetch listings for "${q}" right now. I've added LinkedIn and Indeed searches for you to open instead.` };
  }
  jobs = await rank(jobs);
  data.results = jobs.map((j, i) => ({ ...j, id: 'j' + Date.now().toString(36) + i })); save();
  const top = data.results.slice(0, 3).map((j, i) => `${i + 1}. ${j.title} at ${j.company}${j.score != null ? ` (${j.score}% match)` : ''}`).join('; ');
  const lvName = level ? (LEVELS.find(l => l[0] === level)?.[1] || '').toLowerCase() + ' ' : '';
  return { ok: true, reply: `I found ${data.results.length} ${lvName}${q} jobs${where ? ' around ' + where : ''}. I've also lined up LinkedIn and Indeed searches with the same filters. Best matches: ${top}. Say "tailor my CV for job 1" or "apply to job 1".` };
}

/** Scores each job against your CV (AI if available, keyword overlap otherwise). */
async function rank(jobs) {
  const p = data.profile;
  const offline = () => jobs.map(j => {
    if (!p?.skills?.length) return { ...j, score: null, why: '' };
    const hay = (j.title + ' ' + j.desc).toLowerCase();
    const hit = p.skills.filter(s => s && hay.includes(String(s).toLowerCase()));
    return { ...j, score: Math.min(95, 25 + hit.length * 12), why: hit.length ? 'Matches your ' + hit.slice(0, 4).join(', ') : 'Few of your listed skills appear in the ad' };
  }).sort((a, b) => (b.score ?? 0) - (a.score ?? 0));
  if (!p) return offline();
  try {
    const list = jobs.map((j, i) => `[${i}] ${j.title} | ${j.company} | ${j.location}\n${(j.desc || '').slice(0, 320)}`).join('\n\n');
    const out = parseJSON(await ai(`Candidate: ${p.headline}. ${p.years ? p.years + ' years experience. ' : ''}Skills: ${(p.skills || []).join(', ')}. Location: ${p.location || 'unknown'}.
${data.level ? `They want ${LEVELS.find(l => l[0] === data.level)?.[1]} roles — score jobs at a different level lower.\n` : ''}Score how well the candidate fits each job (0-100, be realistic: seniority, must-have skills, location/visa) with ONE short reason (max 14 words) mentioning the key match or gap.
Reply ONLY with JSON: [{"i":0,"score":0,"why":""}, ...] covering every job.

Jobs:
${list}`, { maxTokens: 2500 }));
    if (!Array.isArray(out)) return offline();
    const by = new Map(out.map(o => [o.i, o]));
    return jobs.map((j, i) => ({ ...j, score: Math.round(by.get(i)?.score ?? 0), why: by.get(i)?.why || '' })).sort((a, b) => b.score - a.score);
  } catch { return offline(); }
}

// ---------------------------------------------------------------- 3. tailoring
export function jobAt(n) {
  if (n == null || n === '') return data.results[0];
  if (typeof n === 'string' && n.startsWith('j')) return data.results.find(j => j.id === n) || data.applied.find(j => j.id === n);
  const words = { first: 1, top: 1, best: 1, second: 2, third: 3, fourth: 4, fifth: 5, one: 1, two: 2, three: 3, four: 4, five: 5 };
  const i = (words[String(n).toLowerCase()] || parseInt(n, 10) || 1) - 1;
  return data.results[i];
}

export async function tailor(job) {
  if (!job) return { ok: false, reply: 'Which job? Search first, e.g. "find React jobs in London".' };
  const cv = await findCV(), p = data.profile || {};
  if (!cv?.text) return { ok: false, reply: 'Send me your CV first, then I can tailor it.' };
  let t;
  try {
    t = parseJSON(await ai(`Job: ${job.title} at ${job.company} (${job.location}).
Job ad: ${(job.desc || '').slice(0, 3500)}

Candidate CV:
${cv.text.slice(0, 9000)}

Reply ONLY with JSON:
{"coverLetter":"a warm, specific cover letter, 170-230 words, plain text with paragraphs separated by blank lines, signed with the candidate's name; mention 2-3 real achievements from the CV that match the ad",
"answers":[{"q":"Why do you want this role?","a":""},{"q":"Why are you a good fit?","a":""},{"q":"What are your salary expectations?","a":"a polite, flexible answer"},{"q":"When can you start / notice period?","a":"leave a [placeholder] if unknown"}],
"keywords":["important words from the ad the CV is missing — only ones the candidate could honestly add"],
"pitch":"one sentence elevator pitch for this job"}
Use only facts from the CV.`, { maxTokens: 2200 }));
  } catch (e) { return { ok: false, reply: noAI(e) ? 'Tailoring needs an AI — add a free Groq or Gemini key in Settings → AI.' : 'I couldn’t write it just now: ' + e.message }; }
  if (!t?.coverLetter) return { ok: false, reply: 'I couldn’t write the cover letter just now. Try again in a moment.' };
  job.kit = { ...t, at: Date.now() };
  const a = data.applied.find(x => x.id === job.id); if (a) a.kit = job.kit;
  save();
  return { ok: true, reply: `Done — your cover letter and answers for ${job.title} at ${job.company} are ready. ${t.pitch || ''}`.trim() };
}

/** A copy of your CV rewritten for one job (facts unchanged), saved as a Word-compatible file. */
export async function tailoredCV(job) {
  const cv = await findCV(); if (!cv?.text || !job) return false;
  const text = await ai(`Rewrite this CV for the job below. Keep every fact true: same employers, dates, degrees. Reorder and reword to emphasise what this job needs, add a 3-line profile at the top, and work in these keywords only where honest: ${(job.kit?.keywords || []).join(', ')}.
Format: first line "# Full Name", second line contact details, then sections as "## Heading", bullets as "- ", other lines plain. No commentary.

Job: ${job.title} at ${job.company}. ${(job.desc || '').slice(0, 2500)}

CV:
${cv.text.slice(0, 11000)}`, { maxTokens: 3500 });
  const html = text.split('\n').map(l => l.startsWith('# ') ? `<h1>${esc(l.slice(2))}</h1>` : l.startsWith('## ') ? `<h2>${esc(l.slice(3))}</h2>` : l.startsWith('- ') ? `<li>${esc(l.slice(2))}</li>` : l.trim() ? `<p>${esc(l)}</p>` : '').join('\n')
    .replace(/(<li>[\s\S]*?<\/li>)(?!\s*<li>)/g, '$1</ul>').replace(/(?<!<\/li>\s*)<li>/g, '<ul><li>');
  const doc = `<html><head><meta charset="utf-8"><style>body{font-family:Calibri,Arial,sans-serif;font-size:11pt;line-height:1.35;margin:28px}h1{font-size:20pt;margin:0 0 4px}h2{font-size:12.5pt;border-bottom:1px solid #999;margin:16px 0 6px;text-transform:uppercase;letter-spacing:.5px}p{margin:3px 0}ul{margin:3px 0 3px 18px;padding:0}</style></head><body>${html}</body></html>`;
  const name = `CV - ${(data.profile?.name || 'Me').trim()} - ${job.company || job.title}.doc`.replace(/[\\/:*?"<>|]/g, '');
  await tools.deliver(name, new TextEncoder().encode(doc), 'application/msword');
  return true;
}

// ---------------------------------------------------------------- 4. apply (you press Submit) + 5. tracker
export async function startApply(job) {
  if (!job) return { ok: false, reply: 'Which job? Search first, e.g. "find React jobs in London".' };
  if (job.kit?.coverLetter) { try { await navigator.clipboard.writeText(job.kit.coverLetter); } catch {} }
  ui.openUrl(job.url);
  return { ok: true, reply: `Opening ${job.title} at ${job.company}. ${job.kit?.coverLetter ? 'Your cover letter is copied — paste it in. ' : ''}${M ? 'Click a box in the form and say "Sparrow, type my email" (or name, phone, LinkedIn, cover letter). ' : ''}When you've pressed Submit, tap "I applied" and I'll remind you to follow up.` };
}

export function markApplied(job, days = 7) {
  if (!job || data.applied.some(a => a.url === job.url)) return;
  const when = new Date(); when.setDate(when.getDate() + days); when.setHours(10, 0, 0, 0);
  const rem = store.add({ type: 'reminder', title: `Follow up: ${job.title} at ${job.company}`, when: when.toISOString() });
  data.applied.unshift({ ...job, status: 'Applied', appliedAt: Date.now(), reminderId: rem?.id });
  save();
  mem.remember('job', `Applied: ${job.title} at ${job.company}`, job.url);
}

export function trackerSummary() {
  if (!data.applied.length) return 'You haven’t tracked any applications yet. After you apply, tap "I applied" and I’ll keep them here.';
  const c = s => data.applied.filter(a => a.status === s).length;
  const latest = data.applied.slice(0, 3).map(a => `${a.title} at ${a.company} (${a.status})`).join('; ');
  return `You've applied to ${data.applied.length} job${data.applied.length > 1 ? 's' : ''}: ${c('Interview')} interview${c('Interview') === 1 ? '' : 's'}, ${c('Offer')} offer${c('Offer') === 1 ? '' : 's'}. Latest: ${latest}.`;
}

/** Field values for "Sparrow, type my email" (Mac). */
export function field(name) {
  const p = data.profile || {}, n = String(name || '').toLowerCase();
  const job = data.results.find(j => j.kit) || data.applied.find(j => j.kit);
  if (/cover/.test(n)) return job?.kit?.coverLetter || '';
  if (/pitch|summary|about/.test(n)) return job?.kit?.pitch || p.summary || '';
  if (/first/.test(n)) return (p.name || '').split(' ')[0];
  if (/last|surname/.test(n)) return (p.name || '').split(' ').slice(1).join(' ');
  if (/name/.test(n)) return p.name || store.settings.name || '';
  if (/mail/.test(n)) return p.email || '';
  if (/phone|number|mobile/.test(n)) return p.phone || '';
  if (/linked/.test(n)) return p.linkedin || '';
  if (/site|portfolio|github/.test(n)) return p.website || '';
  if (/city|location|address/.test(n)) return p.location || '';
  if (/title|headline/.test(n)) return p.headline || '';
  return '';
}

// ---------------------------------------------------------------- the panel
const TABS = [['profile', '🧑 My CV'], ['jobs', '🔎 Jobs'], ['applied', '📌 Applied'], ['setup', '⚙️ Sources']];
let tab = 'jobs';

export function openJobs(which) {
  tab = which || (data.profile ? (data.results.length ? 'jobs' : 'jobs') : 'profile');
  const body = ui.openPanel('💼 Job agent', `<div class="seg small scroll" id="jbTabs">${TABS.map(([k, l]) => `<button data-jt="${k}" class="${k === tab ? 'on' : ''}">${l}</button>`).join('')}</div><div id="jbBody"></div>`);
  body.querySelector('#jbTabs').onclick = e => { const b = e.target.closest('[data-jt]'); if (!b) return; tab = b.dataset.jt; body.querySelectorAll('[data-jt]').forEach(x => x.classList.toggle('on', x === b)); render(); };
  render();
}

function busy(text) { const el = document.getElementById('jbBody'); if (el) el.innerHTML = `<div class="jb-busy"><span class="jb-spin"></span>${esc(text)}</div>`; }
function say(text) { ui.toast(text, 4500); }

function render() {
  const el = document.getElementById('jbBody'); if (!el) return;
  if (tab === 'profile') el.innerHTML = profileHTML();
  if (tab === 'jobs') el.innerHTML = jobsHTML();
  if (tab === 'applied') el.innerHTML = appliedHTML();
  if (tab === 'setup') el.innerHTML = setupHTML();
  el.onclick = onClick; el.onchange = onChange;
  const f = el.querySelector('#jbSearch'); if (f) f.onsubmit = async e => { e.preventDefault(); const q = f.q.value.trim(), w = f.w.value.trim(); busy(`Looking for ${q || 'jobs'}${w ? ' in ' + w : ''} and ranking them against your CV…`); const r = await searchJobs(q, w, f.lv.value); render(); if (!r.ok) say(r.reply); };
}

const list = (arr, cls = '') => (arr || []).length ? `<ul class="jb-list ${cls}">${arr.map(x => `<li>${esc(typeof x === 'string' ? x : x.title + (x.why ? ' — ' + x.why : ''))}</li>`).join('')}</ul>` : '';

function profileHTML() {
  const p = data.profile;
  if (!p) return `<div class="jb-empty"><div class="jb-big">📄</div><p><b>Start with your CV.</b> Sparrow reads it, tells you your strengths, gaps and best-fit roles, and uses it to find and rank jobs.</p>
    <button class="btn" data-ja="upload">Upload my CV (PDF or Word)</button><button class="btn ghost" data-ja="analyse">Use a CV I already sent</button></div>`;
  return `<div class="jb-hero"><div><div class="jb-name">${esc(p.name || 'Your profile')}</div><div class="jb-sub">${esc(p.headline || '')}${p.location ? ' · ' + esc(p.location) : ''}</div></div>
      ${p.score ? `<div class="jb-score" style="--v:${+p.score}"><b>${+p.score}</b><span>CV score</span></div>` : ''}</div>
    ${p.summary ? `<p class="jb-summary">${esc(p.summary)}</p>` : ''}
    <h4>💪 Strengths</h4>${list(p.strengths)}
    <h4>🎯 Best-fit roles</h4><div class="jb-chips">${(p.bestRoles || []).map(r => `<button class="chip" data-ja="role" data-q="${esc(r.title)}" title="${esc(r.why || '')}">${esc(r.title)}</button>`).join('')}</div>
    <h4>⚠️ Gaps</h4>${list(p.gaps)}
    <h4>✍️ Make your CV stronger</h4>${list(p.improvements, 'jb-num')}
    ${(p.skills || []).length ? `<h4>🧰 Skills</h4><div class="jb-tags">${p.skills.map(s => `<span>${esc(s)}</span>`).join('')}</div>` : ''}
    <div class="row-btns"><button class="btn" data-ja="find">🔎 Find jobs for me</button><button class="btn ghost" data-ja="upload">Update CV</button></div>
    <p class="small-text">From ${esc(data.cvName || 'your CV')} · analysed ${new Date(p.at).toLocaleDateString()}</p>`;
}

function jobsHTML() {
  const p = data.profile, q = data.query || p?.searchQuery || '', w = data.where || '';
  const links = q ? searchLinks(q, w) : [];
  return `<form id="jbSearch" class="jb-search"><input name="q" placeholder="Job, e.g. React developer" value="${esc(q)}"><input name="w" placeholder="Where? (optional)" value="${esc(w)}">
    <select name="lv" class="jb-level">${LEVELS.map(([v, n]) => `<option value="${v}" ${v === (data.level || '') ? 'selected' : ''}>${n}</option>`).join('')}</select><button class="pill-btn solid">Search</button></form>
    ${!p ? `<p class="small-text">Tip: <a href="#" data-ja="tab-profile">add your CV</a> and I'll rank every job by how well it fits you.</p>` : ''}
    ${links.length ? `<div class="jb-chips"><span class="small-text">Also search on</span>${links.map(([n, u]) => `<button class="chip" data-ja="open" data-u="${esc(u)}">${esc(n)} ↗</button>`).join('')}</div>` : ''}
    ${data.results.length ? data.results.map((j, i) => jobCard(j, i)).join('') : `<div class="jb-empty"><p>${q ? 'Search to see jobs here.' : 'Type a role above, or say “Sparrow, find React jobs in London”.'}</p></div>`}`;
}

function jobCard(j, i) {
  const applied = data.applied.some(a => a.url === j.url);
  const sc = j.score == null ? '' : `<div class="jb-match ${j.score >= 75 ? 'hi' : j.score >= 50 ? 'mid' : 'lo'}">${j.score}%</div>`;
  return `<div class="jb-card" data-id="${j.id}">
    <div class="jb-top">${sc}<div class="jb-tt"><div class="jb-t">${i + 1}. ${esc(j.title)}</div><div class="jb-sub">${esc(j.company)} · ${esc(j.location || '')}${j.salary ? ' · ' + esc(j.salary) : ''}${(j.level || levelOf(j.title)) ? ' · ' + esc(LEVELS.find(l => l[0] === (j.level || levelOf(j.title)))?.[1] || '') : ''}</div></div></div>
    ${j.why ? `<div class="jb-why">${esc(j.why)}</div>` : ''}
    ${j.kit ? kitHTML(j) : ''}
    <div class="jb-acts">
      <button class="pill-btn" data-ja="tailor" data-id="${j.id}">${j.kit ? '↻ Rewrite' : '✨ Cover letter'}</button>
      ${j.kit ? `<button class="pill-btn" data-ja="cv" data-id="${j.id}">📄 Tailored CV</button>` : ''}
      <button class="pill-btn solid" data-ja="apply" data-id="${j.id}">Apply ↗</button>
      ${applied ? '<span class="jb-done">✅ Applied</span>' : `<button class="pill-btn" data-ja="applied" data-id="${j.id}">I applied</button>`}
    </div>
    <div class="jb-src">${esc(j.source)}${j.posted ? ' · ' + new Date(j.posted).toLocaleDateString() : ''}</div></div>`;
}

function kitHTML(j) {
  const k = j.kit;
  return `<details class="jb-kit" open><summary>Cover letter & answers</summary>
    <div class="jb-letter">${esc(k.coverLetter)}</div><button class="pill-btn" data-ja="copy" data-t="letter" data-id="${j.id}">📋 Copy cover letter</button>
    ${(k.answers || []).map((a, n) => `<div class="jb-qa"><b>${esc(a.q)}</b><p>${esc(a.a)}</p><button class="pill-btn" data-ja="copy" data-t="a${n}" data-id="${j.id}">📋 Copy</button></div>`).join('')}
    ${(k.keywords || []).length ? `<p class="small-text">Words from the ad worth adding to your CV (only if true): ${k.keywords.map(esc).join(', ')}</p>` : ''}
  </details>`;
}

function appliedHTML() {
  if (!data.applied.length) return `<div class="jb-empty"><div class="jb-big">📌</div><p>Jobs you apply to appear here, with a reminder to follow up after a week.</p></div>`;
  const S = ['Applied', 'Interview', 'Offer', 'Rejected'];
  const count = s => data.applied.filter(a => a.status === s).length;
  return `<div class="jb-stats">${S.map(s => `<div><b>${count(s)}</b><span>${s}</span></div>`).join('')}</div>
    ${data.applied.map(a => `<div class="jb-card"><div class="jb-tt"><div class="jb-t">${esc(a.title)}</div><div class="jb-sub">${esc(a.company)} · applied ${new Date(a.appliedAt).toLocaleDateString()}</div></div>
      <div class="jb-acts"><select data-status="${a.id}">${S.map(s => `<option ${s === a.status ? 'selected' : ''}>${s}</option>`).join('')}</select>
      <button class="pill-btn" data-ja="open" data-u="${esc(a.url)}">Open ↗</button><button class="pill-btn" data-ja="remove" data-id="${a.id}">🗑️</button></div></div>`).join('')}`;
}

function setupHTML() {
  const k = data.keys;
  return `<p class="small-text">Sparrow already searches free remote-job boards. For local jobs (London, Lahore, Dubai…) add a free key — each takes a minute and costs nothing.</p>
    <label class="field"><span>Country for local jobs</span><select id="jbCountry">${[['', 'Automatic'], ['gb', 'United Kingdom'], ['pk', 'Pakistan'], ['us', 'United States'], ['in', 'India'], ['ae', 'UAE'], ['sa', 'Saudi Arabia'], ['ca', 'Canada'], ['au', 'Australia'], ['de', 'Germany']].map(([v, n]) => `<option value="${v}" ${data.country === v ? 'selected' : ''}>${n}</option>`).join('')}</select></label>
    <h4>Adzuna <small>(UK, US, India, Europe…)</small></h4><p class="small-text">Free at developer.adzuna.com → “Register”. Paste your App ID and Key.</p>
    <label class="field"><span>App ID</span><input id="jkAdId" value="${esc(k.adzunaId || '')}"></label><label class="field"><span>App key</span><input id="jkAdKey" value="${esc(k.adzunaKey || '')}"></label>
    <h4>Reed <small>(UK)</small></h4><p class="small-text">Free at reed.co.uk/developers → “Sign up”.</p>
    <label class="field"><span>API key</span><input id="jkReed" value="${esc(k.reedKey || '')}"></label>
    <h4>Jooble <small>(70+ countries incl. Pakistan, UAE)</small></h4><p class="small-text">Free at jooble.org/api/about.</p>
    <label class="field"><span>API key</span><input id="jkJooble" value="${esc(k.joobleKey || '')}"></label>
    <button class="btn" data-ja="savekeys">Save</button>
    <p class="small-text">LinkedIn and Indeed don’t allow apps to search or apply for you, so Sparrow opens their searches in your browser instead — you stay signed in and safe.</p>`;
}

async function onClick(e) {
  const b = e.target.closest('[data-ja]'); if (!b) return;
  e.preventDefault();
  const a = b.dataset.ja, job = b.dataset.id ? jobAt(b.dataset.id) : null;
  if (a === 'tab-profile') { tab = 'profile'; openJobs('profile'); }
  if (a === 'upload') {
    const [f] = await ui.pickFiles('.pdf,.doc,.docx,.txt,.md', false); if (!f) return;
    busy('Reading your CV…');
    const rec = await mem.addFile(f, true); data.cvId = rec.id; data.cvName = rec.name; save();
    busy('Analysing your CV — strengths, gaps and best roles…');
    const r = await analyseCV(rec); tab = 'profile'; render(); if (!r.ok) say(r.reply);
  }
  if (a === 'analyse') { busy('Analysing your CV…'); const r = await analyseCV(); render(); if (!r.ok) say(r.reply); }
  if (a === 'find' || a === 'role') {
    tab = 'jobs'; document.querySelectorAll('[data-jt]').forEach(x => x.classList.toggle('on', x.dataset.jt === 'jobs'));
    busy('Finding jobs that fit you…'); const r = await searchJobs(b.dataset.q || '', data.profile?.location?.split(',')[0] || ''); render(); if (!r.ok) say(r.reply);
  }
  if (a === 'open') ui.openUrl(b.dataset.u);
  if (a === 'tailor') { b.textContent = 'Writing…'; b.disabled = true; const r = await tailor(job); render(); if (!r.ok) say(r.reply); }
  if (a === 'cv') { b.textContent = 'Writing your CV…'; b.disabled = true; try { await tailoredCV(job); say('Tailored CV saved ✅'); } catch (err) { say(noAI(err) ? 'Add an AI key in Settings → AI first.' : 'Couldn’t make it: ' + err.message); } render(); }
  if (a === 'apply') { const r = await startApply(job); say(r.reply); }
  if (a === 'applied') { markApplied(job); say('Saved ✅ I’ll remind you to follow up in a week.'); render(); }
  if (a === 'copy') { const k = job?.kit; const t = b.dataset.t === 'letter' ? k?.coverLetter : k?.answers?.[+b.dataset.t.slice(1)]?.a; try { await navigator.clipboard.writeText(t || ''); say('Copied'); } catch { say('Couldn’t copy — select the text instead.'); } }
  if (a === 'remove') { const i = data.applied.findIndex(x => x.id === b.dataset.id); if (i >= 0) { const r = data.applied[i].reminderId; if (r) store.remove(r); data.applied.splice(i, 1); save(); render(); } }
  if (a === 'savekeys') {
    const v = id => document.getElementById(id)?.value.trim() || '';
    data.keys = { adzunaId: v('jkAdId'), adzunaKey: v('jkAdKey'), reedKey: v('jkReed'), joobleKey: v('jkJooble') };
    data.country = document.getElementById('jbCountry')?.value || ''; save(); say('Saved ✅');
  }
}
function onChange(e) {
  const s = e.target.closest('[data-status]'); if (!s) return;
  const a = data.applied.find(x => x.id === s.dataset.status); if (!a) return;
  a.status = s.value;
  if (a.status !== 'Applied' && a.reminderId) { store.remove(a.reminderId); a.reminderId = null; }
  save(); render();
}
