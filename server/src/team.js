// The team page: staff sign in with name + PIN (the owner with the admin key) and work their leads from a phone.
export default String.raw`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Zuffi Team</title>
<meta name="theme-color" content="#0D0B1E">
<style>
  :root { --bg:#0D0B1E; --card:rgba(255,255,255,.07); --line:rgba(255,255,255,.12); --text:#fff; --dim:rgba(255,255,255,.6);
          --pink:#F58FA8; --amber:#FBC56A; --orange:#F28A3C; --green:#34D399; --blue:#7CC4FF; --red:#FF7A85; --violet:#C4B5FD; }
  * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
  body { margin:0; font:15px/1.4 ui-rounded, "SF Pro Rounded", system-ui, -apple-system, "Segoe UI", sans-serif; color:var(--text);
         background: radial-gradient(1200px 600px at 10% -10%, #3a1d52 0%, transparent 60%), radial-gradient(900px 500px at 110% 10%, #13305a 0%, transparent 55%), var(--bg); min-height:100vh; }
  header { position:sticky; top:0; z-index:5; display:flex; align-items:center; gap:10px; padding:14px 16px; background:rgba(13,11,30,.8); backdrop-filter:blur(14px); border-bottom:1px solid var(--line); }
  header h1 { font-size:18px; margin:0; flex:1; }
  .wrap { max-width:720px; margin:0 auto; padding:14px 16px 90px; }
  .card { background:var(--card); border:1px solid var(--line); border-radius:16px; padding:14px; margin-bottom:12px; }
  input, select, textarea { width:100%; font:inherit; color:var(--text); background:rgba(0,0,0,.3); border:1px solid var(--line); border-radius:12px; padding:11px 12px; }
  textarea { min-height:84px; resize:vertical; }
  button { font:inherit; font-weight:700; border:0; border-radius:999px; padding:11px 16px; cursor:pointer; color:#1A1008; background:linear-gradient(var(--amber),var(--orange)); }
  button.soft { color:var(--text); background:rgba(255,255,255,.1); border:1px solid var(--line); }
  button:disabled { opacity:.5; }
  .row { display:flex; gap:8px; align-items:center; }
  .chips { display:flex; gap:6px; overflow-x:auto; padding-bottom:4px; margin-bottom:10px; }
  .chip { white-space:nowrap; padding:7px 12px; border-radius:999px; background:rgba(255,255,255,.08); border:1px solid var(--line); font-size:13px; font-weight:700; }
  .chip.on { background:var(--pink); color:#1A1008; border-color:transparent; }
  .lead { display:flex; gap:12px; align-items:center; padding:12px; border-radius:14px; cursor:pointer; }
  .lead:active { background:rgba(255,255,255,.08); }
  .av { width:42px; height:42px; border-radius:50%; display:grid; place-items:center; font-weight:800; flex:none; background:linear-gradient(var(--blue),#3e6ea0); }
  .grow { flex:1; min-width:0; }
  .name { font-weight:800; }
  .sub { color:var(--dim); font-size:13px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
  .pill { display:inline-block; font-size:11px; font-weight:800; padding:3px 8px; border-radius:999px; background:rgba(255,255,255,.12); margin-right:4px; }
  .pill.red { background:rgba(255,122,133,.2); color:var(--red); } .pill.pink { background:var(--pink); color:#1A1008; } .pill.green { background:rgba(52,211,153,.18); color:var(--green); }
  .msgs { display:flex; flex-direction:column; gap:6px; max-height:46vh; overflow:auto; }
  .m { max-width:82%; padding:9px 12px; border-radius:14px; font-size:14px; white-space:pre-wrap; }
  .m.in { background:rgba(255,255,255,.1); align-self:flex-start; } .m.out { background:rgba(245,143,168,.25); align-self:flex-end; }
  .m small { display:block; color:var(--dim); font-size:10.5px; margin-top:3px; }
  .grid { display:grid; grid-template-columns:1fr 1fr; gap:8px; }
  .muted { color:var(--dim); font-size:13px; }
  .toast { position:fixed; left:50%; bottom:24px; transform:translateX(-50%); background:#000c; border:1px solid var(--line); padding:10px 16px; border-radius:999px; font-weight:700; display:none; }
  table { width:100%; border-collapse:collapse; font-size:13px; } td, th { padding:7px 4px; text-align:left; border-bottom:1px solid var(--line); } th { color:var(--dim); font-weight:700; }
  .hidden { display:none !important; }
</style>
</head>
<body>
<header><span style="font-size:22px">🐰</span><h1 id="title">Zuffi Team</h1><button class="soft hidden" id="back" onclick="showList()">Back</button><button class="soft hidden" id="out" onclick="signOut()">Sign out</button></header>
<div class="wrap">
  <section id="login" class="card">
    <h2 style="margin-top:0">Sign in</h2>
    <p class="muted">Team members: your name and the PIN the owner gave you. Owner: use your admin key.</p>
    <input id="lname" placeholder="Your name" autocomplete="username" style="margin-bottom:8px">
    <input id="lpin" placeholder="PIN (or owner's admin key)" type="password" autocomplete="current-password" style="margin-bottom:12px">
    <button onclick="signIn()" style="width:100%">Sign in</button>
    <p class="muted" id="lerr"></p>
  </section>

  <section id="list" class="hidden">
    <div class="chips" id="chips"></div>
    <input id="q" placeholder="Search name, number, area…" oninput="render()" style="margin-bottom:10px">
    <div id="leads"></div>
    <div id="teamBox" class="card hidden"><h3 style="margin-top:0">Team report</h3><div id="team"></div></div>
  </section>

  <section id="detail" class="hidden"></section>
</div>
<div class="toast" id="toast"></div>
<script>
var S = { token: localStorage.getItem("zt") || "", role: localStorage.getItem("zr") || "", name: localStorage.getItem("zn") || "", leads: [], stages: [], filter: "Needs reply", cur: null };
function $(id) { return document.getElementById(id); }
function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]; }); }
function toast(t) { var e = $("toast"); e.textContent = t; e.style.display = "block"; clearTimeout(toast.t); toast.t = setTimeout(function () { e.style.display = "none"; }, 3000); }
function api(path, body) {
  return fetch(path, { method: body ? "POST" : "GET", headers: { "authorization": "Bearer " + S.token, "content-type": "application/json" }, body: body ? JSON.stringify(body) : undefined })
    .then(function (r) { if (r.status === 401) { signOut(); throw new Error("Please sign in again"); } return r.json(); });
}
function today() { var d = new Date(); return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
function stage(s) { s = (s || "").toLowerCase(); if (!s || s === "new") return "New"; for (var i = 0; i < S.stages.length; i++) if (s.indexOf(S.stages[i].toLowerCase()) === 0) return S.stages[i]; return s.charAt(0).toUpperCase() + s.slice(1); }
function isOpen(l) { var st = stage(l.status); return st !== "Won" && st !== "Lost"; }
function needsReply(l) { return !!l.draft || (l.last_inbound_at && (!l.last_contact || l.last_inbound_at.slice(0, 10) > l.last_contact)); }

function signIn() {
  var name = $("lname").value.trim(), pin = $("lpin").value.trim();
  fetch("/api/login", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(name ? { name: name, pin: pin } : { key: pin }) })
    .then(function (r) { return r.json(); }).then(function (j) {
      if (!j.ok) { $("lerr").textContent = j.error || "Couldn't sign in"; return; }
      S.token = j.token; S.role = j.role; S.name = j.name;
      localStorage.setItem("zt", S.token); localStorage.setItem("zr", S.role); localStorage.setItem("zn", S.name);
      load();
    });
}
function signOut() { localStorage.clear(); S.token = ""; $("login").classList.remove("hidden"); $("list").classList.add("hidden"); $("detail").classList.add("hidden"); $("out").classList.add("hidden"); $("back").classList.add("hidden"); $("title").textContent = "Zuffi Team"; }

function load() {
  api("/api/my/leads").then(function (j) {
    S.leads = j.leads || []; S.stages = j.stages || []; S.role = j.role; S.name = j.name;
    $("login").classList.add("hidden"); $("out").classList.remove("hidden");
    $("title").textContent = S.role === "owner" ? "All leads" : "Hi " + S.name;
    if (S.cur) { var l = S.leads.filter(function (x) { return x.phone === S.cur; })[0]; if (l) return openLead(l.phone); }
    showList();
    if (j.team) {
      $("teamBox").classList.remove("hidden");
      $("team").innerHTML = "<table><tr><th>Name</th><th>Open</th><th>7-day contacts</th><th>Won</th><th>Overdue</th></tr>" + j.team.map(function (r) {
        return "<tr><td><b>" + esc(r.name) + "</b></td><td>" + r.open + "</td><td>" + r.contacted7 + "</td><td>" + r.won + "</td><td>" + (r.overdue ? '<span class="pill red">' + r.overdue + "</span>" : '<span class="pill green">0</span>') + "</td></tr>";
      }).join("") + "</table>";
    }
  }).catch(function (e) { toast(e.message); });
}
function showList() { S.cur = null; $("detail").classList.add("hidden"); $("list").classList.remove("hidden"); $("back").classList.add("hidden"); render(); }
function render() {
  var filters = ["Needs reply", "Due today", "Hot", "New", "All"];
  $("chips").innerHTML = filters.map(function (f) { return '<span class="chip' + (S.filter === f ? " on" : "") + '" onclick="S.filter=\'' + f + '\';render()">' + f + "</span>"; }).join("");
  var q = $("q").value.toLowerCase(), t = today();
  var list = S.leads.filter(function (l) {
    if (q && (l.name + l.phone + l.area + l.interest + l.notes).toLowerCase().indexOf(q) < 0) return false;
    if (S.filter === "Needs reply") return isOpen(l) && needsReply(l);
    if (S.filter === "Due today") return isOpen(l) && l.next_follow_up && l.next_follow_up <= t;
    if (S.filter === "Hot") return isOpen(l) && (l.priority || "").toLowerCase() === "hot";
    if (S.filter === "New") return stage(l.status) === "New";
    return true;
  });
  $("leads").innerHTML = list.length ? list.map(function (l) {
    var nm = l.name || ("+" + l.phone), ini = nm.split(" ").slice(0, 2).map(function (w) { return w.charAt(0); }).join("").toUpperCase();
    var over = isOpen(l) && l.next_follow_up && l.next_follow_up < t;
    return '<div class="lead card" onclick="openLead(\'' + l.phone + '\')"><div class="av">' + esc(ini) + '</div><div class="grow"><div class="name">' + esc(nm) + ((l.priority || "").toLowerCase() === "hot" ? " 🔥" : "") +
      '</div><div class="sub">' + esc(l.last_message || l.interest || l.source) + '</div><div style="margin-top:4px">' + (l.draft ? '<span class="pill pink">reply ready</span>' : "") + '<span class="pill">' + esc(stage(l.status)) + "</span>" +
      (over ? '<span class="pill red">overdue</span>' : "") + (S.role === "owner" && l.assigned ? '<span class="pill">' + esc(l.assigned) + "</span>" : "") + "</div></div></div>";
  }).join("") : '<p class="muted" style="text-align:center;padding:30px 0">Nothing here 🎉</p>';
}

function openLead(phone) {
  var l = S.leads.filter(function (x) { return x.phone === phone; })[0]; if (!l) return;
  S.cur = phone;
  $("list").classList.add("hidden"); $("detail").classList.remove("hidden"); $("back").classList.remove("hidden");
  var st = S.stages.map(function (s) { return "<option" + (stage(l.status) === s ? " selected" : "") + ">" + esc(s) + "</option>"; }).join("");
  var pr = ["", "Hot", "Warm", "Cold"].map(function (p) { return '<option value="' + p + '"' + ((l.priority || "") === p ? " selected" : "") + ">" + (p || "Priority") + "</option>"; }).join("");
  $("detail").innerHTML =
    '<div class="card"><div class="row"><div class="av">' + esc((l.name || "?").charAt(0)) + '</div><div class="grow"><div class="name" style="font-size:18px">' + esc(l.name || "+" + l.phone) + '</div><div class="sub">+' + esc(l.phone) + " · " + esc(l.source) + "</div></div>" +
    '<a href="https://wa.me/' + l.phone + '" target="_blank"><button class="soft">WhatsApp</button></a> <a href="tel:+' + l.phone + '"><button class="soft">Call</button></a></div>' +
    '<p class="muted" style="margin:10px 0 0">' + esc([l.interest, l.area, l.budget].filter(Boolean).join(" · ") || "No details yet") + "</p></div>" +
    '<div class="card"><div class="grid"><select id="st" onchange="save({status:this.value})">' + st + '</select><select id="pr" onchange="save({priority:this.value})">' + pr + "</select></div>" +
    '<div class="row" style="margin-top:8px"><span class="muted" style="white-space:nowrap">Follow up</span><input type="date" value="' + esc(l.next_follow_up) + '" onchange="save({next_follow_up:this.value})"></div></div>' +
    '<div class="card"><div class="msgs" id="msgs"><p class="muted">Loading chat…</p></div>' +
    '<textarea id="reply" placeholder="Write a reply…" style="margin-top:10px">' + esc(l.draft || "") + "</textarea>" +
    '<div class="row" style="margin-top:8px"><button onclick="send()" id="sendBtn">Send on WhatsApp</button><button class="soft" onclick="draft()">✨ Write for me</button></div></div>' +
    '<div class="card"><b>Notes</b><p class="muted" style="white-space:pre-wrap">' + esc((l.notes || "").split(" | ").join("\n")) + '</p><div class="row"><input id="note" placeholder="Add a note…"><button class="soft" onclick="addNote()">Add</button></div></div>';
  api("/api/my/messages?phone=" + phone).then(function (j) {
    $("msgs").innerHTML = (j.messages || []).map(function (m) { return '<div class="m ' + (m.direction === "in" ? "in" : "out") + '">' + esc(m.body) + "<small>" + esc(m.at) + (m.staff ? " · " + esc(m.staff) : "") + "</small></div>"; }).join("") || '<p class="muted">No messages yet.</p>';
    var e = $("msgs"); e.scrollTop = e.scrollHeight;
  });
}
function save(f) { f.phone = S.cur; api("/api/my/lead", f).then(function (j) { if (j.ok) { toast("Saved"); mergeLead(j.lead); } else toast(j.error); }); }
function addNote() { var n = $("note").value.trim(); if (!n) return; save({ note: n }); $("note").value = ""; setTimeout(function () { openLead(S.cur); }, 400); }
function mergeLead(l) { S.leads = S.leads.map(function (x) { return x.phone === l.phone ? l : x; }); }
function send() {
  var t = $("reply").value.trim(); if (!t) return;
  $("sendBtn").disabled = true;
  api("/api/my/send", { phone: S.cur, text: t }).then(function (j) { $("sendBtn").disabled = false; if (j.ok) { toast("Sent ✅"); load(); } else toast(j.error || "Not sent"); });
}
function draft() { toast("Writing…"); api("/api/my/draft", { phone: S.cur }).then(function (j) { if (j.draft) $("reply").value = j.draft; }); }
if (S.token) load();
setInterval(function () { if (S.token && !S.cur) load(); }, 60000);
</script>
</body>
</html>`;
