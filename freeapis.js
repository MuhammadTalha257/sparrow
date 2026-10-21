// Free, no-key web services Zuffi uses (all from the public-apis list, all work in the browser):
//   news   → Wikipedia "In the news" (api.wikimedia.org) + Hacker News (tech)
//   money  → open.er-api.com exchange rates (incl. PKR, GBP, USD, AED, SAR, EUR…)
//   words  → dictionaryapi.dev (English meanings)
//   days   → Nager.Date public holidays (UK and many more)
// Each result is cached for a while so Zuffi stays fast and polite to these free services.

const cache = new Map();
async function getJSON(url, ttlMin = 30) {
  const hit = cache.get(url);
  if (hit && Date.now() - hit.at < ttlMin * 60e3) return hit.v;
  const ctl = new AbortController(); const tm = setTimeout(() => ctl.abort(), 8000);
  try {
    const r = await fetch(url, { signal: ctl.signal });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const v = await r.json(); cache.set(url, { at: Date.now(), v }); return v;
  } finally { clearTimeout(tm); }
}
const strip = html => String(html || '').replace(/<[^>]+>/g, '').replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/\s+/g, ' ').trim();

// ---------------- news ----------------
/** Today's world headlines (Wikipedia "In the news"), short and plain. → [{ title, link }] */
export async function worldNews(max = 5) {
  const d = new Date(), p = n => String(n).padStart(2, '0');
  for (let back = 0; back < 3; back++) {   // the feed for today may not be ready early in the morning
    const x = new Date(d.getTime() - back * 86400e3);
    try {
      const j = await getJSON(`https://api.wikimedia.org/feed/v1/wikipedia/en/featured/${x.getFullYear()}/${p(x.getMonth() + 1)}/${p(x.getDate())}`, 60);
      const list = (j.news || []).map(n => ({ title: strip(n.story), link: n.links?.[0]?.content_urls?.desktop?.page || '' })).filter(n => n.title);
      if (list.length) return list.slice(0, max);
    } catch {}
  }
  return [];
}
/** The top tech stories (Hacker News). → [{ title, link }] */
export async function techNews(max = 5) {
  try {
    const ids = (await getJSON('https://hacker-news.firebaseio.com/v0/topstories.json', 30)).slice(0, max);
    const items = await Promise.all(ids.map(id => getJSON(`https://hacker-news.firebaseio.com/v0/item/${id}.json`, 120).catch(() => null)));
    return items.filter(i => i?.title).map(i => ({ title: i.title, link: i.url || `https://news.ycombinator.com/item?id=${i.id}` }));
  } catch { return []; }
}
/** One or two sentences for the morning briefing. */
export async function newsLine() {
  const w = await worldNews(2).catch(() => []);
  if (!w.length) return '';
  return 'In the news: ' + w.map(n => n.title.replace(/\.$/, '')).join('. ') + '.';
}

// ---------------- money ----------------
const CUR = {
  pound: 'GBP', pounds: 'GBP', gbp: 'GBP', '£': 'GBP', sterling: 'GBP', rupee: 'PKR', rupees: 'PKR', pkr: 'PKR', rs: 'PKR', 'rs.': 'PKR',
  dollar: 'USD', dollars: 'USD', usd: 'USD', '$': 'USD', euro: 'EUR', euros: 'EUR', eur: 'EUR', '€': 'EUR', dirham: 'AED', dirhams: 'AED', aed: 'AED',
  riyal: 'SAR', riyals: 'SAR', sar: 'SAR', 'indian rupee': 'INR', inr: 'INR', yen: 'JPY', jpy: 'JPY', yuan: 'CNY', cny: 'CNY', lira: 'TRY', try: 'TRY',
  'canadian dollar': 'CAD', cad: 'CAD', 'australian dollar': 'AUD', aud: 'AUD', taka: 'BDT', bdt: 'BDT', ringgit: 'MYR', myr: 'MYR', qar: 'QAR', riyal_q: 'QAR',
};
const code = w => CUR[String(w || '').toLowerCase().trim()] || (/^[a-z]{3}$/i.test(w || '') ? w.toUpperCase() : null);
export async function convertMoney(amount, from, to) {
  const j = await getJSON(`https://open.er-api.com/v6/latest/${from}`, 180);
  const r = j.rates?.[to]; if (!r) throw new Error('rate');
  return { value: amount * r, rate: r, when: j.time_last_update_utc || '' };
}
const fmtMoney = (v, c) => `${v >= 100 ? Math.round(v).toLocaleString() : v.toFixed(2)} ${c}`;

// ---------------- words ----------------
export async function define(word) {
  const j = await getJSON(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`, 1440);
  const m = j?.[0]?.meanings || [];
  const out = m.slice(0, 2).map(x => `(${x.partOfSpeech}) ${x.definitions?.[0]?.definition || ''}`).filter(Boolean);
  return out.length ? out : null;
}

// ---------------- holidays ----------------
export async function nextHolidays(country = 'GB', max = 3) {
  const y = new Date().getFullYear(), today = new Date().toISOString().slice(0, 10);
  const all = [...(await getJSON(`https://date.nager.at/api/v3/PublicHolidays/${y}/${country}`, 1440).catch(() => [])), ...(await getJSON(`https://date.nager.at/api/v3/PublicHolidays/${y + 1}/${country}`, 1440).catch(() => []))];
  const seen = new Set();
  return all.filter(h => h.date >= today && !seen.has(h.date + h.name) && seen.add(h.date + h.name)).slice(0, max);
}

/**
 * Plain-language questions these services can answer straight away (no AI needed).
 * → { reply, links? } or null if it's not one of these.
 */
export async function answer(text, { country = 'GB' } = {}) {
  const t = String(text || '').toLowerCase().replace(/^(zuffi,?\s*)?(please\s+)?/, '').replace(/[?!.]+$/, '').trim();

  // news
  if (/^(what'?s|what is|any) (the )?(new|news|latest|happening)( today| in the world| now)?$|^(today'?s |latest |world )?(news|headlines)( today)?$|^tell me the news$|^what'?s new about$|^kya khabar hai$|^khabrein$/.test(t)) {
    const w = await worldNews(5);
    if (!w.length) return { reply: 'I couldn’t get the news right now — check your internet and try again.' };
    return { reply: 'Here’s what’s in the news:\n' + w.map(n => '• ' + n.title).join('\n'), links: w };
  }
  if (/^(tech|technology|ai|startup) news$|^what'?s new in (tech|technology|ai)$/.test(t)) {
    const w = await techNews(5);
    if (!w.length) return { reply: 'I couldn’t get tech news right now.' };
    return { reply: 'Top in tech right now:\n' + w.map(n => '• ' + n.title).join('\n'), links: w };
  }

  // money: "100 pounds to rupees", "convert 50 usd to pkr", "dollar rate", "pound rate in pakistan"
  let m = t.match(/^(?:convert\s+)?([\d,.]+)\s*([a-z£$€.]+(?: dollar| rupee)?)\s+(?:to|in|into)\s+([a-z£$€.]+(?: dollar| rupee)?)$/);
  if (m) {
    const a = parseFloat(m[1].replace(/,/g, '')), f = code(m[2]), to = code(m[3]);
    if (a && f && to) { try { const r = await convertMoney(a, f, to); return { reply: `${fmtMoney(a, f)} is about ${fmtMoney(r.value, to)} (1 ${f} = ${r.rate.toFixed(r.rate < 1 ? 4 : 2)} ${to}).` }; } catch { return { reply: 'I couldn’t get exchange rates right now.' }; } }
  }
  m = t.match(/^(?:what'?s |what is |today'?s )?(?:the )?([a-z£$€]+) rate(?: today)?(?: in ([a-z]+))?$/);
  if (m && code(m[1])) {
    const f = code(m[1]), to = m[2] === 'pakistan' ? 'PKR' : m[2] === 'uk' || m[2] === 'england' ? 'GBP' : (f === 'PKR' ? 'GBP' : 'PKR');
    try { const r = await convertMoney(1, f, to); return { reply: `1 ${f} = ${r.rate.toFixed(r.rate < 1 ? 4 : 2)} ${to} today.` }; } catch { return { reply: 'I couldn’t get exchange rates right now.' }; }
  }

  // meanings
  m = t.match(/^(?:define|meaning of|what does (.+) mean|what is the meaning of)\s*(.*)$/);
  if (m) {
    const w = (m[1] || m[2] || '').replace(/^the word\s+/, '').trim();
    if (w && w.split(' ').length <= 3) {
      const d = await define(w).catch(() => null);
      if (d) return { reply: `“${w}”: ` + d.join(' · ') };
    }
  }

  // holidays
  if (/^(next|upcoming) (bank |public )?holidays?$|^when is the next (bank |public )?holiday$|^bank holidays?$/.test(t)) {
    const h = await nextHolidays(country).catch(() => []);
    if (!h.length) return { reply: 'I couldn’t find upcoming public holidays for your country.' };
    return { reply: 'Coming up: ' + h.map(x => `${x.localName || x.name} on ${new Date(x.date + 'T12:00').toLocaleDateString([], { weekday: 'short', day: 'numeric', month: 'short' })}`).join('; ') + '.' };
  }
  return null;
}
