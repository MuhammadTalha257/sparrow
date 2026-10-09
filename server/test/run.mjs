// Offline tests: a real SQLite database stands in for D1, and Meta / Workers AI are faked.
import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { createHmac } from "node:crypto";
import worker, { processWebhook, hourly, stageOf } from "../src/index.js";

const sqlite = new DatabaseSync(":memory:");
sqlite.exec(readFileSync(new URL("../schema.sql", import.meta.url), "utf8"));
const D1 = {
  prepare(sql) {
    let args = [];
    const st = {
      bind(...a) { args = a; return st; },
      async first() { return sqlite.prepare(sql).get(...args) ?? null; },
      async all() { return { results: sqlite.prepare(sql).all(...args) }; },
      async run() { sqlite.prepare(sql).run(...args); return { success: true }; },
    };
    return st;
  },
};
const sent = [];
const AI = {
  async run(model, input) {
    if (model.includes("whisper")) return { text: "Mujhe DHA mein 10 marla plot chahiye, budget 2 crore" };
    const sys = input.messages[0].content;
    if (sys.includes("pull lead details")) return { response: '{"name":"","interest":"10 marla plot","area":"DHA Phase 6","budget":"2 crore","priority":"Hot"}' };
    return { response: "Walaikum Assalam! DHA Phase 6 mein 10 marla ke achay options hain. Kab visit karna chahenge?" };
  },
};
globalThis.fetch = async (url, opts = {}) => {
  url = String(url);
  if (url.includes("/messages") && url.includes("graph.facebook.com")) {
    const b = JSON.parse(opts.body);
    sent.push(b);
    if (b.to === "447000000000") return new Response(JSON.stringify({ error: { code: 131047, message: "Re-engagement message" } }), { status: 400 });
    return new Response(JSON.stringify({ messages: [{ id: "wamid.out" + sent.length }] }));
  }
  if (url.includes("graph.facebook.com") && url.includes("MEDIA1")) return new Response(JSON.stringify({ url: "https://lookaside.fbsbx.com/voice", mime_type: "audio/ogg" }));
  if (url.includes("lookaside")) return new Response(new Uint8Array([1, 2, 3, 4]));
  if (url.includes("LEAD9")) return new Response(JSON.stringify({ platform: "ig", campaign_name: "DHA Plots Oct", field_data: [
    { name: "full_name", values: ["Sana Malik"] }, { name: "phone_number", values: ["+92 345 1112223"] }, { name: "which_area?", values: ["Bahria Town"] }] }));
  throw new Error("unexpected fetch " + url);
};
const env = { DB: D1, AI, ADMIN_KEY: "admin-secret-123", VERIFY_TOKEN: "zuffi-verify", APP_SECRET: "appsecret", WA_TOKEN: "tok", PHONE_NUMBER_ID: "PNID", PAGE_TOKEN: "pt", TIMEZONE: "Asia/Karachi" };
const pending = [];
const ctx = { waitUntil: (p) => pending.push(p) };
const call = async (path, { method = "GET", body, token, headers = {} } = {}) => {
  const r = await worker.fetch(new Request("https://zuffi.test" + path, { method, headers: { ...(token ? { authorization: "Bearer " + token } : {}), "content-type": "application/json", ...headers }, body: body === undefined ? undefined : typeof body === "string" ? body : JSON.stringify(body) }), env, ctx);
  const t = await r.text();
  try { return { status: r.status, j: JSON.parse(t) }; } catch { return { status: r.status, t }; }
};
let fails = 0;
const ok = (c, m) => { console.log((c ? "✓ " : "✗ ") + m); if (!c) fails++; };
const lead = (p) => sqlite.prepare("SELECT * FROM leads WHERE phone = ?").get(p);
const ts = () => String(Math.floor(Date.now() / 1000));
const wa = (field, value) => ({ object: "whatsapp_business_account", entry: [{ id: "WABA", changes: [{ field, value: { messaging_product: "whatsapp", metadata: { display_phone_number: "923001234567", phone_number_id: "PNID" }, ...value } }] }] });

// 1. Meta's webhook check
let r = await call("/webhook?hub.mode=subscribe&hub.verify_token=zuffi-verify&hub.challenge=42");
ok(r.status === 200 && (r.t === "42" || r.j === 42), "webhook verification answers the challenge");
ok((await call("/webhook?hub.mode=subscribe&hub.verify_token=wrong&hub.challenge=42")).status === 403, "wrong verify token refused");

// 2. Owner sets up the team
r = await call("/api/team", { method: "PUT", token: env.ADMIN_KEY, body: { team: [{ name: "Ali", phone: "923331110000", role: "Agent", pin: "1111" }, { name: "Sara", phone: "923332220000", role: "Agent", pin: "2222" }],
  owner_phone: "923009998888", owner_name: "Talha", summary_hour: 9, auto: { draftReplies: true, autoReply: false, roundRobin: true, ownerSummary: true, staffDigest: true }, business: "Talha Estates", kind: "estate" } });
ok(r.j.ok, "team + settings saved");
ok((await call("/api/team", { method: "PUT", token: "nope", body: {} })).status === 401, "API refuses a wrong key");

// 3. Signature check
const payload = JSON.stringify(wa("messages", { contacts: [{ wa_id: "923331234567", profile: { name: "Imran Khan" } }], messages: [{ from: "923331234567", id: "wamid.in1", timestamp: ts(), type: "text", text: { body: "AoA, DHA phase 6 mein 10 marla plot chahiye, budget 2 crore. Visit kab ho sakti hai?" } }] }));
ok((await call("/webhook", { method: "POST", body: payload, headers: { "x-hub-signature-256": "sha256=bad" } })).status === 401, "fake webhook (bad signature) refused");
const sig = "sha256=" + createHmac("sha256", env.APP_SECRET).update(payload).digest("hex");
r = await call("/webhook", { method: "POST", body: payload, headers: { "x-hub-signature-256": sig } });
ok(r.status === 200, "real webhook accepted");
await Promise.all(pending.splice(0));
let L = lead("923331234567");
ok(L && L.name === "Imran Khan", "new WhatsApp chat → lead with the WhatsApp name");
ok(L.interest === "10 marla plot" && L.area === "DHA Phase 6" && L.budget.includes("2 crore") && L.priority === "Hot", "AI filled interest, area, budget, Hot");
ok(L.assigned === "Ali", "round robin gave the first lead to Ali");
ok(L.draft.startsWith("Walaikum"), "a reply is drafted in the client's language");
ok(sent.length === 0, "nothing sent automatically (auto-reply off)");

// 4. Same message again (Meta retries) is ignored
await processWebhook(env, JSON.parse(payload));
ok(sqlite.prepare("SELECT COUNT(*) n FROM messages").get().n === 1, "duplicate webhook ignored");

// 5. Voice note from a new number → written out → lead
await processWebhook(env, wa("messages", { contacts: [{ wa_id: "923451239876", profile: { name: "Bilal" } }], messages: [{ from: "923451239876", id: "wamid.in2", timestamp: ts(), type: "audio", audio: { id: "MEDIA1", voice: true } }] }));
L = lead("923451239876");
ok(L.voice_text.includes("10 marla") && L.last_message.startsWith("🎤"), "voice note written out");
ok(L.area === "DHA Phase 6" && L.assigned === "Sara", "voice note → lead details, given to Sara (round robin)");

// 6. Business replies from the WhatsApp Business app on the phone (Coexistence echo)
await processWebhook(env, wa("smb_message_echoes", { message_echoes: [{ from: "923001234567", to: "923331234567", id: "wamid.echo1", timestamp: ts(), type: "text", text: { body: "Ji, kal 4 baje visit rakh lete hain" } }] }));
L = lead("923331234567");
ok(L.status === "Contacted" && L.last_contact && L.draft === "", "reply sent from the phone app counts as contact, clears the draft");

// 7. Facebook / Instagram Lead Ad
await processWebhook(env, { object: "page", entry: [{ id: "PAGE", changes: [{ field: "leadgen", value: { leadgen_id: "LEAD9" } }] }] });
L = lead("923451112223");
ok(L && L.name === "Sana Malik" && L.source === "Instagram ad – DHA Plots Oct" && L.notes.includes("Bahria"), "Instagram lead form → lead instantly");

// 8. Staff log in and only see their leads
r = await call("/api/login", { method: "POST", body: { name: "sara", pin: "2222" } });
ok(r.j.ok && r.j.role === "staff", "Sara signs in with her PIN");
const sara = r.j.token;
ok((await call("/api/login", { method: "POST", body: { name: "Sara", pin: "9999" } })).status === 401, "wrong PIN refused");
r = await call("/api/my/leads", { token: sara });
ok(r.j.leads.every((l) => l.assigned === "Sara") && r.j.leads.length >= 1, "Sara only sees her own leads");
ok((await call("/api/my/messages?phone=923331234567", { token: sara })).status === 403, "Sara can't open Ali's lead");
r = await call("/api/my/send", { method: "POST", token: sara, body: { phone: "923451239876", text: "Bilal sahab, DHA 6 ke 3 options bhej raha hoon" } });
ok(r.j.ok && sent.at(-1).to === "923451239876", "Sara replies on WhatsApp from her phone page");
L = lead("923451239876");
ok(L.status === "Contacted" && L.next_follow_up > L.last_contact, "sending moves the lead to Contacted and sets the next follow-up");
r = await call("/api/my/lead", { method: "POST", token: sara, body: { phone: "923451239876", status: "Site visit", note: "Visit Sunday 11am" } });
ok(r.j.ok && r.j.lead.status === "Site visit" && r.j.lead.notes.includes("Sara: Visit Sunday"), "Sara moves the stage and adds a note");
r = await call("/api/my/messages?phone=923451239876", { token: sara });
ok(r.j.messages.length === 2 && r.j.messages[0].direction === "in", "chat history shows voice note and reply");

// 9. Mac app sync
r = await call("/api/leads?since=", { token: env.ADMIN_KEY });
ok(r.j.leads.length === 3 && r.j.now, "Mac pulls all leads");
const since = r.j.now;
r = await call("/api/leads?since=" + encodeURIComponent(since), { token: env.ADMIN_KEY });
ok(r.j.leads.length === 0, "nothing new since last pull");
r = await call("/api/leads", { method: "PUT", token: env.ADMIN_KEY, body: { leads: [{ phone: "+92 333 1234567", status: "Negotiating", priority: "Hot" }] } });
ok(r.j.saved === 1 && lead("923331234567").status === "Negotiating", "Mac pushes a stage change");

// 10. 24-hour rule explained
await call("/api/team", { method: "PUT", token: env.ADMIN_KEY, body: { team: [{ name: "Ali", phone: "923331110000", role: "Agent", pin: "1111" }, { name: "Sara", phone: "923332220000", role: "Agent", pin: "2222" }] } });
sqlite.prepare("INSERT INTO leads (phone, name, assigned, status) VALUES ('447000000000','Old UK lead','Ali','Contacted')").run();
r = await call("/api/send", { method: "POST", token: env.ADMIN_KEY, body: { to: "447000000000", text: "Hi" } });
ok(!r.j.ok && r.j.error.includes("24 hours"), "outside the 24h window: clear explanation");

// 11. Team report + owner summary + daily send
r = await call("/api/report", { token: env.ADMIN_KEY });
ok(r.j.summary.includes("Team:") && r.j.team.some((t) => t.name === "Sara" && t.contacted7 >= 2), "team report counts Sara's work");
sqlite.prepare("UPDATE leads SET next_follow_up = '2020-01-01' WHERE phone = '923331234567'").run();
r = await call("/api/report", { token: env.ADMIN_KEY });
ok(r.j.summary.includes("Not following up: Ali"), "summary names who isn't following up");
const before = sent.length;
const cfgRow = JSON.parse(sqlite.prepare("SELECT v FROM settings WHERE k='config'").get().v);
cfgRow.summary_hour = Number(new Intl.DateTimeFormat("en-GB", { timeZone: "Asia/Karachi", hour: "2-digit", hour12: false }).format(new Date())) % 24;
sqlite.prepare("UPDATE settings SET v = ? WHERE k='config'").run(JSON.stringify(cfgRow));
await hourly(env);
ok(sent.length - before === 3 && sent.slice(before).some((m) => m.to === "923009998888" && m.text.body.includes("Good morning")), "daily summary to owner + list to each staff member");
await hourly(env);
ok(sent.length - before === 3, "summary only once a day");
ok(stageOf("token paid") === "Won" && stageOf("site visit done") === "Site visit", "stage names understood");

// 12. Team page is served
r = await call("/");
ok(r.status === 200 && r.t.includes("Zuffi Team"), "team page served");

console.log(fails ? `\n${fails} FAILED` : "\nAll tests passed");
process.exit(fails ? 1 : 0);
