// Instant WhatsApp answers for ANY business — no AI needed, works on a slow computer, never makes things up.
// It reads the business details (the form, or whatever the owner wrote), works out what the customer is asking about
// (opening hours, where, prices / services, payment, booking, delivery / parking, contact, or one of the owner's own
// questions & answers) and replies with the owner's own lines. If it isn't sure, it returns null and the AI (or a
// polite "we'll get back to you") takes over. The Mac app has the same rules in Swift (ZuffiCRM.swift → BizQuickAnswer).

const INTENTS = [
  ['hours', /\b(open|opening|opens|timing|timings|hours|close|closing|closed|when are you|what time|kab (khulta|khulti|band)|kab tak|waqt|today open|sunday|saturday|weekend|holiday)\b/,
    /\b(open|hours|closed|mon|tue|wed|thu|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d\s?(am|pm)|timing|24\/7)\b/],
  ['location', /\b(where|address|location|located|kahan|kidhar|directions|postcode|map|pin|find you|reach you)\b/,
    /\b(address|area|street|st\.?|road|rd\.?|located|postcode|location|near|block|phase|sector|floor|plaza|mall)\b/],
  ['price', /\b(price|prices|pricing|cost|costs|how much|kitna|kitne|kitni|rate|rates|charges?|fees?|menu|list|services?|offer|offers|packages?|what do you (do|sell|have)|products?|qeemat|paisay)\b/,
    /(£|\$|€|\brs\.?\b|\bpkr\b|\bprice|\bfrom\b|\bper\b|\bservices?\b|\bproducts?\b|\bmenu\b|\d+\s?(lakh|crore|k)\b)/],
  ['payment', /\b(pay|paying|payment|card|cash|bank|transfer|installments?|instalments?|qist|emi|payment plan|finance|easypaisa|jazzcash|deposit)\b/,
    /\b(payment|pay|cash|card|bank|instal|install|transfer|deposit|finance|qist|easypaisa|jazzcash)\b/],
  ['booking', /\b(book|booking|appointment|reserve|reservation|slot|available|availability|visit|viewing|come in|walk.?in)\b/,
    /\b(book|booking|appointment|deposit|visit|walk.?in|reserve|slot)\b/],
  ['delivery', /\b(deliver|delivery|shipping|courier|post|parking|park)\b/, /\b(deliver|delivery|shipping|courier|parking|park)\b/],
  ['contact', /\b(your number|phone|call you|contact|landline|email)\b/, /\b(phone|whatsapp|call|number|email|contact)\b/],
];
const GREET = /^(hi+|hello|hey|salam|assalam[uo]? ?(o )?alaikum|aoa|good (morning|afternoon|evening)|hiya|yo)[\s!.,]*$/i;
const STOP = new Set('the a an and or to of for in on at is are do does you your we our i me my it this that can could would please with from have has what how much get know about want tell any there hai hain aap kya kar sakta sakti mil ka ki ke ko se pe par bhi'.split(' '));
// The form's own labels: when a line starts with one of these, it IS the answer (no guessing from other lines).
const LABELS = { hours: /^(opening )?hours|^timings?/i, location: /^address|^location|^area/i, payment: /^payment/i, booking: /^how to book|^booking/i,
  delivery: /^delivery|^parking/i, contact: /^phone|^whatsapp|^contact/i };
// Complaints, refunds, a person, bargaining → the owner answers (Zuffi sends a holding message instead).
const HANDOVER = /\b(refund|complain|complaint|angry|terrible|worst|disappointed|went wrong|broken|damaged|cheated|fraud|lawyer|legal|manager|owner|real person|human|speak to|call me|discount|less price|kam karo|kam kar|final price|last price|bargain)\b/i;
const words = s => String(s || '').toLowerCase().replace(/[^\p{L}\p{N}£$€ ]/gu, ' ').split(/\s+/).filter(w => w.length > 2 && !STOP.has(w));

const langOf = t => /[؀-ۿ]/.test(t) ? 'urdu' : /\b(kya|hai|hain|aap|ap|kitna|kitne|kab|kahan|chahiye|mujhe|bhai|btau|batao|gi|ji|krna|karna|nahi|acha|theek|shukriya)\b/i.test(t) ? 'roman' : 'en';

/** The owner's lines, cleaned: "Label: value" lines and plain lines, without the example text. */
function lines(info) {
  return String(info || '').split(/\n/).map(l => l.trim()).filter(l => l && !/^— More notes —$/.test(l) && !/^business:/i.test(l));
}

/** Questions & answers the owner wrote ("Do you do walk-ins? Yes, if a chair is free."). */
function faqs(info) {
  const out = [], ls = lines(info);
  for (let i = 0; i < ls.length; i++) {
    const l = ls[i], q = l.indexOf('?');
    if (q > 3 && q < l.length - 2) out.push({ q: l.slice(0, q + 1), a: l.slice(q + 1).replace(/^[\s\-–:]+/, '') });
    else if (q === l.length - 1 && ls[i + 1] && !ls[i + 1].includes('?')) out.push({ q: l, a: ls[i + 1] });
  }
  return out;
}

/**
 * msg: the customer's message · info: business details · biz: business name · first: first message from this person
 * today: today's offer / update. → reply text, or null when not sure.
 */
export function answer(msg, info, { biz = '', first = false, today = '' } = {}) {
  const m = String(msg || '').toLowerCase().trim();
  if (!m || !String(info || '').trim() || /\[address\]/.test(info)) return null;   // nothing real to answer from (or still the example)
  const lang = langOf(msg);
  const hello = first ? (lang === 'roman' ? `Assalam o Alaikum! ${biz ? biz + ' ' : ''}se rabta karne ka shukriya. ` : lang === 'urdu' ? 'السلام علیکم! رابطہ کرنے کا شکریہ۔ ' : `Hi! Thanks for messaging${biz ? ' ' + biz : ''}. `) : '';
  const bye = lang === 'roman' ? ' Aur kuch poochna ho to batayein 🙏' : lang === 'urdu' ? ' مزید کچھ پوچھنا ہو تو بتائیں 🙏' : ' Anything else I can help with?';

  if (HANDOVER.test(m)) return null;
  if (GREET.test(m)) return first ? hello + (lang === 'roman' ? 'Bataiye, hum aap ki kya madad kar sakte hain?' : lang === 'urdu' ? 'بتائیے ہم آپ کی کیا مدد کر سکتے ہیں؟' : 'How can we help you today?') : null;

  const ls = lines(info);
  // 1) one of the owner's own questions & answers
  const mw = words(m);
  let best = null, bestScore = 0;
  for (const f of faqs(info)) {
    const qw = words(f.q); if (!qw.length) continue;
    const hit = qw.filter(w => mw.includes(w)).length, score = hit / qw.length;
    if (hit >= 2 && score > bestScore) { best = f; bestScore = score; }
  }
  if (best && bestScore >= 0.5) return hello + best.a + bye;

  // 2) what are they asking about? (several at once is fine: "services and the payment plan")
  const asked = INTENTS.filter(([, re]) => re.test(m));
  const parts = [];
  // a specific thing they named ("haircut price", "10 marla house") → that line
  const priceLines = ls.filter(l => INTENTS[2][2].test(l.toLowerCase()));
  const generic = new Set(['price', 'prices', 'services', 'service', 'from', 'products', 'rate', 'rates', 'cost', 'list', 'menu', 'offer']);
  const scored = priceLines.map(l => ({ l, n: words(l).filter(w => mw.includes(w) && !generic.has(w)).length })).filter(x => x.n > 0);
  const top = Math.max(0, ...scored.map(x => x.n));
  // the line(s) that match best — "10 marla house" picks the house, not every line with "marla"
  const named = top ? scored.filter(x => x.n === top).map(x => x.l) : [];
  if (named.length && named.length <= 4) parts.push(named.join('\n'));
  for (const [id, , lineRe] of asked) {
    if (id === 'price' && named.length && named.length <= 4) continue;
    // "Label: value" lines first, then any line that talks about it
    const labelled = LABELS[id] ? ls.filter(l => LABELS[id].test(l)) : [];
    let found = labelled.length ? labelled : ls.filter(l => lineRe.test(l.toLowerCase()));
    if (id === 'price') {
      // the whole services list (the lines under "Services…:" or every line with a price)
      const i = ls.findIndex(l => /^(services|products|menu|prices)[^:]*:\s*$/i.test(l));
      if (i >= 0) { const list = []; for (let k = i + 1; k < ls.length && !/^[A-Z][^:]{2,40}:\s/.test(ls[k]) && !/:\s*$/.test(ls[k]); k++) list.push(ls[k]); if (list.length) found = list; }
      found = found.slice(0, 8);
      if (found.length > 1) found = [(lang === 'roman' ? 'Hamari services aur rates:' : lang === 'urdu' ? 'ہماری سروسز اور ریٹس:' : 'Here’s what we offer:'), ...found.map(l => '• ' + l)];
    } else found = found.slice(0, 2);
    if (found.length) parts.push(found.join('\n'));
  }
  if (!parts.length) return null;
  const offer = today && asked.some(([id]) => id === 'price' || id === 'booking') ? `\nToday: ${today}` : '';
  return ((hello ? hello.trim() + '\n' : '') + [...new Set(parts)].join('\n') + offer + '\n' + bye.trim()).trim();
}
