// Zuffi Business server — WhatsApp Business Platform (Cloud API + Coexistence) on Cloudflare Workers.
//
//  • /webhook        Meta sends every WhatsApp message here (also messages the business sends from
//                    the WhatsApp Business app on the phone — "smb_message_echoes" — thanks to Coexistence)
//                    and, if a Page is subscribed, Facebook / Instagram Lead Ads ("leadgen").
//  • /api/*          the Zuffi Mac app (admin key) and team members (PIN login) read and update leads.
//  • /               a small mobile page for the team: "my leads", update, reply.
//  • cron (hourly)   owner's daily summary, each staff member's list, follow-ups for quiet leads.
//
// Everything a client says becomes a lead: name, number, what they want, area, budget, how hot.
// Voice notes are written out (Groq Whisper if GROQ_KEY is set, else Workers AI Whisper).

import TEAM_PAGE from "./team.js";

const STAGES_ESTATE = ["New", "Contacted", "Site visit", "Negotiating", "Won", "Lost"];

export default {
  async fetch(req, env, ctx) {
    try {
      return await route(req, env, ctx);
    } catch (e) {
      console.error(e && e.stack || e);
      return json({ ok: false, error: String(e && e.message || e) }, 500);
    }
  },
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(hourly(env));
  },
};

// ───────────────────────────── routing ─────────────────────────────

async function route(req, env, ctx) {
  const url = new URL(req.url);
  const p = url.pathname.replace(/\/+$/, "") || "/";

  if (p === "/webhook" && req.method === "GET") {
    const mode = url.searchParams.get("hub.mode"), token = url.searchParams.get("hub.verify_token");
    if (mode === "subscribe" && token && token === env.VERIFY_TOKEN) return new Response(url.searchParams.get("hub.challenge") || "", { status: 200 });
    return new Response("Forbidden", { status: 403 });
  }
  if (p === "/webhook" && req.method === "POST") {
    const raw = await req.text();
    if (env.APP_SECRET) {
      const sig = (req.headers.get("x-hub-signature-256") || "").replace(/^sha256=/, "");
      const want = await hmacHex(env.APP_SECRET, raw);
      if (!sig || !safeEqual(sig, want)) return new Response("Bad signature", { status: 401 });
    }
    let body; try { body = JSON.parse(raw); } catch { return new Response("Bad JSON", { status: 400 }); }
    ctx.waitUntil(processWebhook(env, body).catch((e) => console.error("webhook", e && e.stack || e)));
    return new Response("OK", { status: 200 });
  }

  if (p === "/" || p === "/team") return new Response(TEAM_PAGE, { headers: { "content-type": "text/html; charset=utf-8" } });

  if (p === "/api/login" && req.method === "POST") {
    const b = await req.json().catch(() => ({}));
    if (b.key && env.ADMIN_KEY && safeEqual(String(b.key), env.ADMIN_KEY)) return json({ ok: true, token: env.ADMIN_KEY, role: "owner", name: (await config(env)).owner_name || "Owner" });
    const cfg = await config(env);
    const s = (cfg.team || []).find((t) => norm(t.name) === norm(b.name || "") && String(t.pin || "") === String(b.pin || ""));
    if (!s) return json({ ok: false, error: "Wrong name or PIN" }, 401);
    return json({ ok: true, token: await staffToken(env, s.name, s.pin), role: "staff", name: s.name });
  }

  if (!p.startsWith("/api/")) return new Response("Not found", { status: 404 });
  const who = await authenticate(req, env);
  if (!who) return json({ ok: false, error: "Not signed in" }, 401);
  const admin = who.role === "owner";

  // ── owner / Mac app ──
  if (p === "/api/status") {
    return json({ ok: true, whatsapp: !!(env.WA_TOKEN && env.PHONE_NUMBER_ID), number: (await config(env)).number || env.PHONE_NUMBER_ID || "", leads: (await env.DB.prepare("SELECT COUNT(*) n FROM leads").first()).n });
  }
  if (p === "/api/leads" && req.method === "GET" && admin) {
    const since = url.searchParams.get("since") || "";
    const { results } = await env.DB.prepare("SELECT * FROM leads WHERE updated_at > ? ORDER BY updated_at LIMIT 500").bind(since).all();
    return json({ ok: true, leads: results, now: results.length ? results[results.length - 1].updated_at : (since || "") });
  }
  if (p === "/api/leads" && req.method === "PUT" && admin) {
    const b = await req.json();
    let n = 0;
    for (const l of b.leads || []) {
      const phone = digits(l.phone);
      if (phone.length < 9) continue;
      await upsertLead(env, phone, pick(l, ["name", "source", "interest", "area", "budget", "status", "priority", "assigned", "next_follow_up", "notes"]), { touch: false });
      n++;
    }
    return json({ ok: true, saved: n });
  }
  if (p === "/api/team" && req.method === "PUT" && admin) {
    const b = await req.json();
    const cfg = await config(env);
    Object.assign(cfg, pick(b, ["team", "owner_phone", "owner_name", "summary_hour", "auto", "welcome", "business", "kind", "quiet_days", "summary_template", "template_lang"]));
    await saveConfig(env, cfg);
    return json({ ok: true });
  }
  if (p === "/api/send" && req.method === "POST" && admin) {
    const b = await req.json();
    return json(await sendAndLog(env, digits(b.to), String(b.text || ""), (await config(env)).owner_name || "Owner"));
  }
  if (p === "/api/report" && admin) {
    return json({ ok: true, summary: await summary(env), team: await teamReport(env) });
  }

  // ── team members (and the owner) ──
  if (p === "/api/my/leads") {
    const q = admin ? env.DB.prepare("SELECT * FROM leads ORDER BY COALESCE(NULLIF(last_message_at,''), added) DESC LIMIT 400")
                    : env.DB.prepare("SELECT * FROM leads WHERE assigned = ? ORDER BY COALESCE(NULLIF(last_message_at,''), added) DESC LIMIT 400").bind(who.name);
    const { results } = await q.all();
    return json({ ok: true, name: who.name, role: who.role, stages: stagesFor(await config(env)), leads: results, team: admin ? await teamReport(env) : undefined });
  }
  if (p === "/api/my/messages") {
    const phone = digits(url.searchParams.get("phone"));
    if (!(await canSee(env, who, phone))) return json({ ok: false, error: "Not your lead" }, 403);
    const { results } = await env.DB.prepare("SELECT * FROM messages WHERE phone = ? ORDER BY at DESC LIMIT 60").bind(phone).all();
    return json({ ok: true, messages: results.reverse() });
  }
  if (p === "/api/my/lead" && req.method === "POST") {
    const b = await req.json();
    const phone = digits(b.phone);
    if (!(await canSee(env, who, phone))) return json({ ok: false, error: "Not your lead" }, 403);
    const lead = await getLead(env, phone);
    const f = pick(b, ["status", "priority", "next_follow_up"]);
    if (admin && b.assigned !== undefined) f.assigned = b.assigned;
    if (b.note) f.notes = (lead.notes ? lead.notes + " | " : "") + `${who.name}: ${b.note}`;
    if (f.status) f.last_contact = today(env);
    await upsertLead(env, phone, { ...f, changed_by: "staff" });
    await log(env, lead.name || phone, who.name, f.status ? "Stage" : b.note ? "Note" : "Updated", f.status || b.note || f.next_follow_up || f.priority || "");
    return json({ ok: true, lead: await getLead(env, phone) });
  }
  if (p === "/api/my/send" && req.method === "POST") {
    const b = await req.json();
    const phone = digits(b.phone);
    if (!(await canSee(env, who, phone))) return json({ ok: false, error: "Not your lead" }, 403);
    return json(await sendAndLog(env, phone, String(b.text || ""), who.name));
  }
  if (p === "/api/my/draft" && req.method === "POST") {
    const b = await req.json();
    const phone = digits(b.phone);
    if (!(await canSee(env, who, phone))) return json({ ok: false, error: "Not your lead" }, 403);
    const lead = await getLead(env, phone);
    return json({ ok: true, draft: await draftReply(env, lead, lead.last_message || "", false) });
  }
  return json({ ok: false, error: "Unknown request" }, 404);
}

// ───────────────────────────── webhook ─────────────────────────────

export async function processWebhook(env, body) {
  for (const entry of body.entry || []) {
    for (const ch of entry.changes || []) {
      const v = ch.value || {};
      if (body.object === "whatsapp_business_account") {
        if (ch.field === "messages") {
          const names = Object.fromEntries((v.contacts || []).map((c) => [c.wa_id, (c.profile && c.profile.name) || ""]));
          if (v.metadata && v.metadata.display_phone_number) {
            const cfg = await config(env);
            if (cfg.number !== v.metadata.display_phone_number) { cfg.number = v.metadata.display_phone_number; await saveConfig(env, cfg); }
          }
          for (const m of v.messages || []) await inbound(env, m, names[m.from] || "");
        } else if (ch.field === "smb_message_echoes") {
          // Sent by the business from the WhatsApp Business app on the phone (Coexistence).
          for (const m of v.message_echoes || []) {
            const to = digits(m.to);
            if (!to) continue;
            const text = textOf(m);
            await recordMessage(env, m.id, to, "out", m.type, text, "Phone app", tsToLocal(env, m.timestamp));
            const lead = await getLead(env, to);
            const f = { last_contact: today(env), last_message: "You: " + text.slice(0, 200), last_message_at: tsToLocal(env, m.timestamp), draft: "" };
            if (!lead.phone) Object.assign(f, { source: "WhatsApp", added: today(env), status: "Contacted" });
            else if (stageOf(lead.status) === "New") f.status = "Contacted";
            await upsertLead(env, to, { ...f, changed_by: "inbound" });
          }
        } else if (ch.field === "history") {
          // First sync of up to 6 months of chats from the WhatsApp Business app.
          for (const h of v.history || []) for (const t of h.threads || []) {
            const phone = digits(t.id);
            if (!phone || (await getLead(env, phone)).phone) continue;
            const last = (t.messages || [])[0];
            await upsertLead(env, phone, { source: "WhatsApp (earlier chat)", status: "Contacted", added: today(env), last_message: last ? textOf(last).slice(0, 200) : "", last_message_at: last ? tsToLocal(env, last.timestamp) : "", changed_by: "inbound" });
          }
        }
      } else if (body.object === "page" && ch.field === "leadgen" && v.leadgen_id) {
        await leadAd(env, v.leadgen_id);
      }
    }
  }
}

async function inbound(env, m, profileName) {
  const phone = digits(m.from);
  if (!phone) return;
  if (await env.DB.prepare("SELECT id FROM messages WHERE id = ?").bind(m.id).first()) return; // Meta may resend
  const cfg = await config(env);
  const auto = { draftReplies: true, autoReply: false, roundRobin: true, voiceNotes: true, ...(cfg.auto || {}) };
  const at = tsToLocal(env, m.timestamp);
  let text = textOf(m), voiceText = "";
  if ((m.type === "audio" || m.type === "voice") && auto.voiceNotes !== false) {
    voiceText = await transcribeMedia(env, (m.audio || m.voice || {}).id).catch((e) => { console.error("voice", e); return ""; });
    text = voiceText ? voiceText : "🎤 Voice note";
  }
  await recordMessage(env, m.id, phone, "in", m.type, voiceText ? "🎤 " + voiceText : text, "", at);

  const lead = await getLead(env, phone);
  const isNew = !lead.phone;
  const f = { last_message: (voiceText ? "🎤 " : "") + text.slice(0, 300), last_message_at: at, last_inbound_at: at, changed_by: "inbound" };
  if (voiceText) f.voice_text = voiceText;
  if (isNew) {
    f.name = profileName;
    const ref = m.referral || {};
    f.source = ref.source_type === "ad" || ref.headline ? `WhatsApp ad${ref.headline ? " – " + ref.headline : ""}` : "WhatsApp";
    f.status = "New"; f.added = today(env); f.next_follow_up = today(env);
    if (auto.roundRobin !== false) f.assigned = await nextAssignee(env, cfg);
  } else if (!lead.name && profileName) f.name = profileName;
  // What do they want?
  if (text && text.length > 6 && text !== "🎤 Voice note") {
    const x = await extract(env, cfg, text);
    for (const k of ["interest", "area", "budget"]) if (x[k] && !(lead[k])) f[k] = x[k];
    if (x.name && !lead.name && !f.name) f.name = x.name;
    if (x.priority && (!lead.priority || x.priority === "Hot")) f.priority = x.priority;
  }
  await upsertLead(env, phone, f);
  if (isNew) await log(env, f.name || phone, f.assigned || "", "New lead", f.source);

  if (auto.draftReplies !== false || auto.autoReply) {
    const fresh = await getLead(env, phone);
    const reply = await draftReply(env, fresh, text, isNew);
    if (reply) {
      if (auto.autoReply && isNew) {
        const r = await sendAndLog(env, phone, reply, "Zuffi (auto)");
        if (!r.ok) await upsertLead(env, phone, { draft: reply });
      } else await upsertLead(env, phone, { draft: reply });
    }
  }
}

async function leadAd(env, leadgenId) {
  if (!env.PAGE_TOKEN) return;
  const r = await fetch(`https://graph.facebook.com/${env.GRAPH_VERSION || "v23.0"}/${leadgenId}?fields=field_data,created_time,ad_name,campaign_name,platform&access_token=${encodeURIComponent(env.PAGE_TOKEN)}`);
  if (!r.ok) return console.error("leadgen", await r.text());
  const d = await r.json();
  const fd = Object.fromEntries((d.field_data || []).map((x) => [String(x.name).toLowerCase(), (x.values || []).join(", ")]));
  const phone = digits(fd.phone_number || fd.phone || fd.whatsapp_number || fd.mobile || "");
  if (phone.length < 9) return;
  const cfg = await config(env);
  const lead = await getLead(env, phone);
  const name = fd.full_name || [fd.first_name, fd.last_name].filter(Boolean).join(" ");
  const extra = Object.entries(fd).filter(([k]) => !["full_name", "first_name", "last_name", "phone_number", "phone", "email"].includes(k)).map(([k, v]) => `${k}: ${v}`).join("; ");
  const f = { changed_by: "inbound", last_message: "📋 Filled in the form" + (extra ? ": " + extra.slice(0, 200) : ""), last_message_at: nowLocal(env) };
  if (!lead.phone) Object.assign(f, {
    name, source: `${d.platform === "ig" ? "Instagram" : "Facebook"} ad${d.campaign_name ? " – " + d.campaign_name : ""}`, status: "New", added: today(env), next_follow_up: today(env),
    assigned: await nextAssignee(env, cfg), notes: [fd.email ? "Email: " + fd.email : "", extra].filter(Boolean).join(" | "),
  });
  await upsertLead(env, phone, f);
  if (!lead.phone) await log(env, name || phone, f.assigned || "", "New lead", f.source);
}

// ───────────────────────────── WhatsApp sending ─────────────────────────────

async function graph(env, path, body) {
  const r = await fetch(`https://graph.facebook.com/${env.GRAPH_VERSION || "v23.0"}/${path}`, {
    method: body ? "POST" : "GET",
    headers: { Authorization: `Bearer ${env.WA_TOKEN}`, ...(body ? { "content-type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, j };
}

async function sendText(env, to, text) {
  if (!env.WA_TOKEN || !env.PHONE_NUMBER_ID) return { ok: false, error: "WhatsApp isn't linked to the server yet." };
  const { ok, j } = await graph(env, `${env.PHONE_NUMBER_ID}/messages`, { messaging_product: "whatsapp", recipient_type: "individual", to, type: "text", text: { preview_url: false, body: text.slice(0, 4000) } });
  if (ok) return { ok: true, id: j.messages && j.messages[0] && j.messages[0].id };
  const code = j.error && j.error.code;
  if (code === 131047 || code === 131026) return { ok: false, code, error: "It's been more than 24 hours since they last wrote — WhatsApp only allows an approved template message now." };
  return { ok: false, code, error: (j.error && (j.error.error_user_msg || j.error.message)) || "WhatsApp refused the message." };
}

async function sendTemplate(env, to, name, lang, param) {
  const { ok, j } = await graph(env, `${env.PHONE_NUMBER_ID}/messages`, {
    messaging_product: "whatsapp", to, type: "template",
    template: { name, language: { code: lang || "en" }, components: [{ type: "body", parameters: [{ type: "text", text: param.replace(/[\n\t]+/g, " · ").replace(/ {4,}/g, " ").slice(0, 1000) }] }] },
  });
  return ok ? { ok: true } : { ok: false, error: j.error && j.error.message };
}

export async function sendAndLog(env, phone, text, staff) {
  if (!phone || !text.trim()) return { ok: false, error: "Nothing to send." };
  const r = await sendText(env, phone, text);
  if (!r.ok) return r;
  const at = nowLocal(env);
  await recordMessage(env, r.id || crypto.randomUUID(), phone, "out", "text", text, staff, at);
  const lead = await getLead(env, phone);
  const f = { last_contact: today(env), last_message: "You: " + text.slice(0, 200), last_message_at: at, draft: "", changed_by: "staff" };
  if (stageOf(lead.status) === "New") f.status = "Contacted";
  const cfg = await config(env);
  if (!lead.next_follow_up || lead.next_follow_up <= today(env)) f.next_follow_up = addDays(env, Number(cfg.quiet_days || 2));
  await upsertLead(env, phone, f);
  await log(env, lead.name || phone, staff, "Message", text.slice(0, 80));
  return { ok: true };
}

// ───────────────────────────── AI ─────────────────────────────

async function ai(env, system, user, wantJSON) {
  try {
    if (env.GROQ_KEY) {
      const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST", headers: { Authorization: `Bearer ${env.GROQ_KEY}`, "content-type": "application/json" },
        body: JSON.stringify({ model: "llama-3.3-70b-versatile", temperature: 0.3, messages: [{ role: "system", content: system }, { role: "user", content: user }], ...(wantJSON ? { response_format: { type: "json_object" } } : {}) }),
      });
      if (r.ok) { const j = await r.json(); return j.choices[0].message.content; }
    }
    if (env.AI) {
      const out = await env.AI.run("@cf/meta/llama-3.3-70b-instruct-fp8-fast", { messages: [{ role: "system", content: system }, { role: "user", content: user }], max_tokens: 700 });
      const res = out && out.response;
      return typeof res === "string" ? res : res ? JSON.stringify(res) : "";
    }
  } catch (e) { console.error("ai", e); }
  return "";
}

function jsonIn(t) {
  if (!t) return {};
  const s = String(t).replace(/```json|```/g, "");
  const a = s.indexOf("{"), b = s.lastIndexOf("}");
  if (a < 0 || b <= a) return {};
  try { return JSON.parse(s.slice(a, b + 1)); } catch { return {}; }
}

export async function extract(env, cfg, text) {
  const estate = (cfg.kind || "estate") === "estate";
  const out = {};
  const bud = text.toLowerCase().match(/(\d+(\.\d+)?)\s*(crore|cr|lakh|lac|million|m\b|k\b)/);
  if (bud) out.budget = bud[0];
  const j = jsonIn(await ai(env, "You pull lead details out of client WhatsApp messages. Reply with JSON only.",
    `A client wrote to a ${estate ? "Pakistani property agent" : "UK small business (salon / shop)"}. Return {"name":"","interest":"what they want, short","area":"","budget":"as said","priority":"Hot|Warm|Cold"}.
Hot = wants to buy/book now, asks for visit, price or availability. Cold = just browsing. Empty string if not said.
Message: ${text.slice(0, 3000)}`, true));
  for (const k of ["name", "interest", "area", "budget", "priority"]) if (j[k] && String(j[k]).trim()) out[k] = String(j[k]).trim();
  if (out.priority) out.priority = out.priority[0].toUpperCase() + out.priority.slice(1).toLowerCase();
  return out;
}

export async function draftReply(env, lead, incoming, first) {
  const cfg = await config(env);
  const estate = (cfg.kind || "estate") === "estate";
  const fname = (lead.name || "").split(" ")[0];
  const fallback = cfg.welcome ? cfg.welcome.replace(/\{name\}/g, fname)
    : estate ? `Assalam o Alaikum${fname ? " " + fname : ""}! Thank you for contacting ${cfg.business || "us"}. Which area are you looking in, what size, and what's your budget? I'll send you the best options.`
      : `Hi${fname ? " " + fname : ""}! Thanks for messaging ${cfg.business || "us"}. What would you like to book, and which day suits you?`;
  const r = await ai(env, "You write short WhatsApp replies for a business. Reply with the message text only.",
    `You reply for ${cfg.business || "a business"} (${estate ? "property agent in Pakistan" : "UK small business, e.g. a salon"}).
Reply in the client's own language and script (English, Urdu or Roman Urdu). 1-3 short, warm, human sentences.
${first ? "First message: greet them and ask only for what's missing (area / size / budget, or service / day)." : "Continue the conversation helpfully."}
Never invent prices, listings or free times. If they ask something only a person can answer, say a team member will reply shortly.
What we know: ${[lead.interest, lead.area, lead.budget].filter(Boolean).join(", ") || "nothing yet"}.
Their message: ${incoming.slice(0, 2000)}`, false);
  const clean = (r || "").trim().replace(/^["“]|["”]$/g, "");
  return clean || fallback;
}

export async function transcribeMedia(env, mediaId) {
  if (!mediaId || !env.WA_TOKEN) return "";
  const meta = await graph(env, mediaId);
  if (!meta.ok || !meta.j.url) return "";
  const r = await fetch(meta.j.url, { headers: { Authorization: `Bearer ${env.WA_TOKEN}` } });
  if (!r.ok) return "";
  const buf = await r.arrayBuffer();
  if (env.GROQ_KEY) {
    const fd = new FormData();
    fd.append("model", "whisper-large-v3");
    fd.append("file", new Blob([buf], { type: meta.j.mime_type || "audio/ogg" }), "voice.ogg");
    const g = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", { method: "POST", headers: { Authorization: `Bearer ${env.GROQ_KEY}` }, body: fd });
    if (g.ok) { const j = await g.json(); if (j.text) return j.text.trim(); }
  }
  if (env.AI) {
    try {
      const out = await env.AI.run("@cf/openai/whisper-large-v3-turbo", { audio: b64(buf) });
      if (out && out.text) return out.text.trim();
    } catch (e) { console.error("whisper-turbo", e); }
    try {
      const out = await env.AI.run("@cf/openai/whisper", { audio: [...new Uint8Array(buf)] });
      if (out && out.text) return out.text.trim();
    } catch (e) { console.error("whisper", e); }
  }
  return "";
}

// ───────────────────────────── team, summary, cron ─────────────────────────────

async function nextAssignee(env, cfg) {
  const agents = (cfg.team || []).filter((t) => !/owner/i.test(t.role || ""));
  if (!agents.length || (cfg.auto && cfg.auto.roundRobin === false)) return "";
  const rr = Number(cfg.rr || 0);
  cfg.rr = rr + 1;
  await saveConfig(env, cfg);
  return agents[rr % agents.length].name;
}

export async function teamReport(env) {
  const cfg = await config(env);
  const t = today(env), week = addDays(env, -7);
  const out = [];
  for (const s of cfg.team || []) {
    const { results: mine } = await env.DB.prepare("SELECT status, next_follow_up, added, name, phone FROM leads WHERE assigned = ?").bind(s.name).all();
    const open = mine.filter((l) => !["Won", "Lost"].includes(stageOf(l.status)));
    const overdue = open.filter((l) => l.next_follow_up && l.next_follow_up < t);
    const c = await env.DB.prepare("SELECT COUNT(*) n FROM activity WHERE staff = ? AND at >= ? AND kind IN ('Message','Stage','Note','Follow-up','Updated')").bind(s.name, week).first();
    out.push({ name: s.name, assigned: mine.length, open: open.length, overdue: overdue.length, overdue_names: overdue.slice(0, 5).map((l) => l.name || l.phone),
      contacted7: c.n, won: mine.filter((l) => stageOf(l.status) === "Won").length, new_today: mine.filter((l) => l.added === t).length });
  }
  return out.sort((a, b) => b.overdue - a.overdue);
}

export async function summary(env, staff) {
  const cfg = await config(env);
  const t = today(env), y = addDays(env, -1);
  const q = staff ? env.DB.prepare("SELECT * FROM leads WHERE assigned = ?").bind(staff) : env.DB.prepare("SELECT * FROM leads");
  const { results: all } = await q.all();
  const open = all.filter((l) => !["Won", "Lost"].includes(stageOf(l.status)));
  const fresh = all.filter((l) => l.added === t || l.added === y);
  const hot = open.filter((l) => (l.priority || "").toLowerCase() === "hot");
  const due = open.filter((l) => l.next_follow_up && l.next_follow_up <= t);
  const waiting = open.filter((l) => l.last_inbound_at && (!l.last_contact || l.last_inbound_at.slice(0, 10) > l.last_contact));
  const src = {};
  for (const l of fresh) { const k = (l.source || "Other").split(" – ")[0]; src[k] = (src[k] || 0) + 1; }
  const lines = [`Good morning${staff ? " " + staff : cfg.owner_name ? " " + cfg.owner_name : ""}! 🐰`];
  lines.push(`📥 ${fresh.length} new lead${fresh.length === 1 ? "" : "s"} since yesterday${Object.keys(src).length ? " (" + Object.entries(src).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${v}`).join(", ") + ")" : ""}`);
  if (waiting.length) lines.push(`💬 Waiting for a reply: ${waiting.slice(0, 6).map((l) => l.name || l.phone).join(", ")}`);
  if (hot.length) lines.push(`🔥 Hot: ${hot.slice(0, 6).map((l) => `${l.name || ""} ${l.phone}`.trim()).join(", ")}`);
  lines.push(`📞 Follow up today (${due.length}): ${due.length ? due.slice(0, 8).map((l) => l.name || l.phone).join(", ") : "none 🎉"}`);
  if (!staff && (cfg.team || []).length) {
    const rep = await teamReport(env);
    lines.push("👥 Team:");
    for (const r of rep) lines.push(`• ${r.name}: ${r.open} open, ${r.contacted7} contacts this week, ${r.won} won${r.overdue ? ` — ⚠️ ${r.overdue} overdue (${r.overdue_names.join(", ")})` : " ✅"}`);
    const slow = rep.filter((r) => r.overdue).map((r) => r.name);
    if (slow.length) lines.push(`⚠️ Not following up: ${slow.join(", ")}`);
    const un = open.filter((l) => !l.assigned).length;
    if (un) lines.push(`📌 ${un} lead${un === 1 ? "" : "s"} with nobody assigned`);
  }
  return lines.join("\n");
}

export async function hourly(env) {
  const cfg = await config(env);
  const auto = cfg.auto || {};
  const hour = Number(localParts(env).hour);
  const t = today(env);
  // Quiet leads → a follow-up waits as a draft.
  if (auto.quietFollowUp !== false) {
    const cut = addDays(env, -Number(cfg.quiet_days || 2));
    const { results } = await env.DB.prepare("SELECT * FROM leads WHERE draft = '' AND last_contact != '' AND last_contact <= ? AND (next_follow_up = '' OR next_follow_up <= ?) AND status NOT IN ('Won','Lost')").bind(cut, t).all();
    const estate = (cfg.kind || "estate") === "estate";
    for (const l of results.slice(0, 50)) {
      const f = (l.name || "").split(" ")[0];
      const d = estate ? `Assalam o Alaikum${f ? " " + f : ""}, just checking in${l.interest ? " about the " + l.interest : ""}${l.area ? " in " + l.area : ""}. I have a few new options — shall I send them?`
        : `Hi${f ? " " + f : ""}, just checking in — would you like me to book you in? I have some free times this week.`;
      await upsertLead(env, l.phone, { draft: d, changed_by: "inbound" });
    }
  }
  if (hour !== Number(cfg.summary_hour ?? 9) || cfg.summary_sent === t) return;
  cfg.summary_sent = t;
  await saveConfig(env, cfg);
  const deliver = async (to, text) => {
    const r = await sendText(env, digits(to), text);
    if (!r.ok && cfg.summary_template) await sendTemplate(env, digits(to), cfg.summary_template, cfg.template_lang || "en", text);
  };
  if (auto.ownerSummary && cfg.owner_phone) await deliver(cfg.owner_phone, await summary(env));
  if (auto.staffDigest) for (const s of cfg.team || []) if (s.phone) await deliver(s.phone, await summary(env, s.name));
}

// ───────────────────────────── storage helpers ─────────────────────────────

const LEAD_COLS = ["name", "source", "interest", "area", "budget", "status", "priority", "assigned", "added", "last_contact", "next_follow_up", "last_message", "last_message_at", "last_inbound_at", "notes", "draft", "voice_text", "changed_by"];

export async function getLead(env, phone) {
  return (await env.DB.prepare("SELECT * FROM leads WHERE phone = ?").bind(phone).first()) || {};
}

export async function upsertLead(env, phone, fields, opts = {}) {
  const f = {};
  for (const k of LEAD_COLS) if (fields[k] !== undefined && fields[k] !== null) f[k] = String(fields[k]);
  const touch = opts.touch !== false;
  const exists = await env.DB.prepare("SELECT phone FROM leads WHERE phone = ?").bind(phone).first();
  if (!exists) {
    const cols = ["phone", ...Object.keys(f), "updated_at"];
    const vals = [phone, ...Object.values(f), stamp(env)];
    await env.DB.prepare(`INSERT INTO leads (${cols.join(",")}) VALUES (${cols.map(() => "?").join(",")})`).bind(...vals).run();
    return;
  }
  const keys = Object.keys(f);
  if (!keys.length) return;
  const sets = keys.map((k) => `${k} = ?`);
  const vals = Object.values(f);
  if (touch) { sets.push("updated_at = ?"); vals.push(stamp(env)); }
  await env.DB.prepare(`UPDATE leads SET ${sets.join(", ")} WHERE phone = ?`).bind(...vals, phone).run();
}

async function recordMessage(env, id, phone, direction, kind, body, staff, at) {
  await env.DB.prepare("INSERT OR IGNORE INTO messages (id, phone, direction, kind, body, staff, at) VALUES (?,?,?,?,?,?,?)").bind(String(id || crypto.randomUUID()), phone, direction, kind || "text", body || "", staff || "", at).run();
}

async function log(env, lead, staff, kind, detail) {
  await env.DB.prepare("INSERT INTO activity (at, lead, staff, kind, detail) VALUES (?,?,?,?,?)").bind(nowLocal(env), lead, staff || "", kind, String(detail || "").slice(0, 200)).run();
}

async function config(env) {
  const row = await env.DB.prepare("SELECT v FROM settings WHERE k = 'config'").first();
  return row ? JSON.parse(row.v) : {};
}
async function saveConfig(env, v) {
  await env.DB.prepare("INSERT INTO settings (k, v) VALUES ('config', ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v").bind(JSON.stringify(v)).run();
}

// ───────────────────────────── auth ─────────────────────────────

async function staffToken(env, name, pin) {
  return "s." + b64url(name) + "." + (await hmacHex(env.ADMIN_KEY || "zuffi", `${name}:${pin}`)).slice(0, 40);
}
async function authenticate(req, env) {
  const tok = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!tok) return null;
  if (env.ADMIN_KEY && safeEqual(tok, env.ADMIN_KEY)) return { role: "owner", name: (await config(env)).owner_name || "Owner" };
  const m = tok.match(/^s\.([^.]+)\.([0-9a-f]+)$/);
  if (!m) return null;
  const name = unb64url(m[1]);
  const s = ((await config(env)).team || []).find((t) => t.name === name);
  if (!s || !safeEqual(tok, await staffToken(env, s.name, s.pin))) return null;
  return { role: "staff", name: s.name };
}
async function canSee(env, who, phone) {
  if (!phone) return false;
  if (who.role === "owner") return true;
  return (await getLead(env, phone)).assigned === who.name;
}

// ───────────────────────────── small helpers ─────────────────────────────

function json(o, status = 200) { return new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json", "access-control-allow-origin": "*" } }); }
function digits(s) { let d = String(s || "").replace(/\D/g, ""); if (d.startsWith("00")) d = d.slice(2); return d; }
function norm(s) { return String(s || "").trim().toLowerCase(); }
function pick(o, keys) { const r = {}; for (const k of keys) if (o && o[k] !== undefined) r[k] = o[k]; return r; }
function stagesFor(cfg) { return (cfg.kind || "estate") === "estate" ? STAGES_ESTATE : ["New", "Contacted", "Booked", "Regular", "Won", "Lost"]; }
export function stageOf(raw) {
  const s = String(raw || "").toLowerCase().trim();
  if (!s || s === "new" || ["hot", "warm", "cold"].includes(s)) return "New";
  if (s.includes("visit")) return "Site visit";
  if (s.includes("negotiat") || s.includes("offer")) return "Negotiating";
  if (/token|won|deal|sold|closed|paid/.test(s)) return "Won";
  if (/lost|not interested|cancel|junk/.test(s)) return "Lost";
  if (s.includes("book")) return "Booked";
  if (s.includes("regular")) return "Regular";
  if (/contact|called|replied|follow/.test(s)) return "Contacted";
  return raw;
}
function textOf(m) {
  switch (m.type) {
    case "text": return (m.text && m.text.body) || "";
    case "interactive": return (m.interactive && ((m.interactive.button_reply && m.interactive.button_reply.title) || (m.interactive.list_reply && m.interactive.list_reply.title))) || "";
    case "button": return (m.button && m.button.text) || "";
    case "image": return "📷 Photo" + (m.image && m.image.caption ? ": " + m.image.caption : "");
    case "video": return "🎬 Video" + (m.video && m.video.caption ? ": " + m.video.caption : "");
    case "document": return "📄 " + ((m.document && (m.document.filename || m.document.caption)) || "Document");
    case "location": return "📍 Location" + (m.location && m.location.name ? ": " + m.location.name : "");
    case "audio": case "voice": return "🎤 Voice note";
    default: return `[${m.type}]`;
  }
}
function localParts(env, date = new Date()) {
  const f = new Intl.DateTimeFormat("en-CA", { timeZone: env.TIMEZONE || "UTC", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false });
  const o = Object.fromEntries(f.formatToParts(date).map((p) => [p.type, p.value]));
  if (o.hour === "24") o.hour = "00";
  return o;
}
function today(env) { const o = localParts(env); return `${o.year}-${o.month}-${o.day}`; }
function nowLocal(env, d) { const o = localParts(env, d); return `${o.year}-${o.month}-${o.day} ${o.hour}:${o.minute}`; }
function stamp(env) { const o = localParts(env); return `${o.year}-${o.month}-${o.day} ${o.hour}:${o.minute}:${o.second}.${String(Date.now() % 1000).padStart(3, "0")}`; }
function addDays(env, n) { const o = localParts(env, new Date(Date.now() + n * 86400000)); return `${o.year}-${o.month}-${o.day}`; }
function tsToLocal(env, ts) { return ts ? nowLocal(env, new Date(Number(ts) * 1000)) : nowLocal(env); }
async function hmacHex(secret, data) {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const s = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(data));
  return [...new Uint8Array(s)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function safeEqual(a, b) { a = String(a); b = String(b); if (a.length !== b.length) return false; let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i); return r === 0; }
function b64(buf) { let s = ""; const u = new Uint8Array(buf); for (let i = 0; i < u.length; i += 0x8000) s += String.fromCharCode(...u.subarray(i, i + 0x8000)); return btoa(s); }
function b64url(s) { return btoa(unescape(encodeURIComponent(s))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); }
function unb64url(s) { try { return decodeURIComponent(escape(atob(s.replace(/-/g, "+").replace(/_/g, "/")))); } catch { return ""; } }

