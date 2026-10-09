import Foundation
import AppKit
import Speech

// =====================================================================
// MARK: - Zuffi CRM: the business brain behind the Business dashboard
//
// Data lives in plain sheets in Documents/Zuffi (Excel / Numbers open them):
//   Leads.csv     everyone who contacted the business (WhatsApp, ads, Zameen, walk-ins…)
//   Team.csv      staff: name, phone, role, PIN (for the web dashboard)
//   Activity.csv  what happened, by whom — this is what the team report counts
//
// Automations (each one switchable in the dashboard):
//   • new WhatsApp chats → leads (reads WhatsApp on this Mac; or the always-on server)
//   • a reply drafted for every new enquiry (or sent straight away, if you allow it)
//   • voice notes saved from WhatsApp → text → lead details
//   • new leads shared among the team (round robin)
//   • quiet leads → follow-up drafted
//   • owner's daily summary + each staff member's list, on WhatsApp
// =====================================================================

struct CRMLead: Identifiable, Hashable {
    var id: String { key }
    var key: String
    var name = "", phone = "", source = "", interest = "", area = "", budget = ""
    var status = "New", priority = "", assigned = "", added = "", lastContact = "", nextFollowUp = ""
    var lastMessage = "", lastMessageAt = "", notes = ""
    var draft = ""            // suggested reply (kept in memory)

    var stage: String { ZuffiCRM.stage(for: status) }
    var isOpen: Bool { !["Won", "Lost"].contains(stage) }
    var followDate: Date? { ZuffiBusiness.date(nextFollowUp) }
    var overdue: Bool { isOpen && (followDate.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false) }
    var dueToday: Bool { isOpen && (followDate.map { $0 <= Calendar.current.startOfDay(for: Date()).addingTimeInterval(86399) } ?? false) }
    var display: String { name.isEmpty ? phone : name }
    var initials: String { String(display.split(separator: " ").prefix(2).compactMap(\.first)).uppercased() }
}

struct CRMStaff: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var phone: String
    var role: String
    var pin: String
}

struct CRMActivity: Identifiable, Hashable {
    let id = UUID()
    var date: String, time: String, lead: String, staff: String, kind: String, detail: String
}

struct StaffReport: Identifiable {
    var id: String { name }
    let name: String
    let assigned: Int, open: Int, overdue: Int, contacted7: Int, won: Int, newToday: Int
    let overdueNames: [String]
}

@MainActor
final class ZuffiCRM: ObservableObject {
    static let shared = ZuffiCRM()

    @Published private(set) var leads: [CRMLead] = []
    @Published private(set) var team: [CRMStaff] = []
    @Published private(set) var activity: [CRMActivity] = []
    @Published var drafts: [String: String] = [:]                 // lead key → suggested reply
    @Published var lastWhatsAppCheck: Date?
    @Published var whatsAppStatus = "Not checked yet"
    @Published var serverStatus = ""
    @Published var busy = ""

    private var stamp: Date?
    private var seenRows = Set<String>()
    private var lastWatch = Date.distantPast
    private var lastSync = Date.distantPast
    private var rr = UserDefaults.standard.integer(forKey: "crmRoundRobin")

    // Settings
    @Published var ownerName = UserDefaults.standard.string(forKey: "crmOwnerName") ?? "" { didSet { UserDefaults.standard.set(ownerName, forKey: "crmOwnerName") } }
    @Published var ownerPhone = UserDefaults.standard.string(forKey: "crmOwnerPhone") ?? "" { didSet { UserDefaults.standard.set(ownerPhone, forKey: "crmOwnerPhone") } }
    @Published var serverURL = UserDefaults.standard.string(forKey: "crmServerURL") ?? "" { didSet { UserDefaults.standard.set(serverURL, forKey: "crmServerURL") } }
    @Published var welcomeText = UserDefaults.standard.string(forKey: "crmWelcome") ?? "" { didSet { UserDefaults.standard.set(welcomeText, forKey: "crmWelcome") } }
    @Published var summaryHour = UserDefaults.standard.object(forKey: "crmSummaryHour") as? Int ?? 9 { didSet { UserDefaults.standard.set(summaryHour, forKey: "crmSummaryHour") } }
    @Published var quietDays = UserDefaults.standard.object(forKey: "crmQuietDays") as? Int ?? 2 { didSet { UserDefaults.standard.set(quietDays, forKey: "crmQuietDays") } }

    enum Auto: String, CaseIterable, Identifiable {
        case watchWhatsApp, draftReplies, autoReply, voiceNotes, leadExports, roundRobin, quietFollowUp, ownerSummary, staffDigest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .watchWhatsApp: return "Turn new WhatsApp chats into leads"
            case .draftReplies: return "Write a reply for every new enquiry"
            case .autoReply: return "Send the first reply straight away"
            case .voiceNotes: return "Voice notes → text → lead details"
            case .leadExports: return "Add Facebook / Instagram / Zameen lead downloads"
            case .roundRobin: return "Share new leads among the team"
            case .quietFollowUp: return "Follow up leads that go quiet"
            case .ownerSummary: return "Owner's daily summary on WhatsApp"
            case .staffDigest: return "Each team member gets their list on WhatsApp"
            }
        }
        var detail: String {
            switch self {
            case .watchWhatsApp: return "Zuffi reads unread chats in WhatsApp on this Mac every minute and creates or updates the lead. With the always-on server, this works even when the Mac is off."
            case .draftReplies: return "A ready reply in the client's language, using your listings / services. You check it in Inbox and press Send."
            case .autoReply: return "The welcome message goes out on its own within a minute. Off by default — turn on once you trust the drafts."
            case .voiceNotes: return "Save a voice note from WhatsApp (right-click → Save As, into Downloads) or drop it on the dashboard. Zuffi writes it out and fills in the lead."
            case .leadExports: return "Lead files you download from Meta Leads Center, Zameen, Graana or Google Forms are added within a minute."
            case .roundRobin: return "Each new lead goes to the next team member in turn."
            case .quietFollowUp: return "When a lead hasn't heard from you for the set number of days, a follow-up is written and waits in Inbox."
            case .ownerSummary: return "At the set hour you get: new leads, hot leads, today's follow-ups, and who in the team isn't following up."
            case .staffDigest: return "At the same hour each team member gets their own follow-ups for the day."
            }
        }
        var defaultOn: Bool { ![.autoReply, .ownerSummary, .staffDigest].contains(self) }
    }

    func isOn(_ a: Auto) -> Bool { UserDefaults.standard.object(forKey: "auto_" + a.rawValue) as? Bool ?? a.defaultOn }
    func set(_ a: Auto, _ on: Bool) { objectWillChange.send(); UserDefaults.standard.set(on, forKey: "auto_" + a.rawValue) }

    private init() { reload() }

    // MARK: Stages

    var isEstate: Bool { ZuffiBusiness.shared.pack != .salon }
    var stages: [String] { isEstate ? ["New", "Contacted", "Site visit", "Negotiating", "Won", "Lost"] : ["New", "Contacted", "Booked", "Regular", "Won", "Lost"] }

    static func stage(for raw: String) -> String {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        if s.isEmpty || s == "new" || ["hot", "warm", "cold"].contains(s) { return "New" }
        if s.contains("visit") { return "Site visit" }
        if s.contains("negotiat") || s.contains("offer") { return "Negotiating" }
        if s.contains("token") || s.contains("won") || s.contains("deal") || s.contains("sold") || s.contains("closed") || s.contains("paid") { return "Won" }
        if s.contains("lost") || s.contains("not interested") || s.contains("cancel") || s.contains("junk") { return "Lost" }
        if s.contains("book") { return "Booked" }
        if s.contains("regular") || s.contains("client") { return "Regular" }
        if s.contains("contact") || s.contains("called") || s.contains("replied") || s.contains("follow") { return "Contacted" }
        return raw.capitalized
    }

    // MARK: Load / save

    func reload() {
        let b = ZuffiPA.load("Leads", header: ZuffiPA.leadHeader)
        leads = b.rows.enumerated().map { i, r in
            var l = CRMLead(key: "")
            l.name = b.get(r, ["name"]); l.phone = b.get(r, ["phone", "mobile"]); l.source = b.get(r, ["source"])
            l.interest = b.get(r, ["interest", "wants"]); l.area = b.get(r, ["area"]); l.budget = b.get(r, ["budget"])
            l.status = b.get(r, ["status"]); l.priority = b.get(r, ["priority"]); l.assigned = b.get(r, ["assigned"])
            l.added = b.get(r, ["added"]); l.lastContact = b.get(r, ["last contact"]); l.nextFollowUp = b.get(r, ["next follow"])
            l.lastMessage = b.get(r, ["last message"]); l.lastMessageAt = b.get(r, ["last message at"]); l.notes = b.get(r, ["notes"])
            l.key = Self.key(name: l.name, phone: l.phone, row: i)
            return l
        }
        let t = ZuffiPA.load("Team", header: ["Name", "Phone", "Role", "PIN"])
        team = t.rows.map { CRMStaff(name: t.get($0, ["name"]), phone: t.get($0, ["phone"]), role: t.get($0, ["role"]), pin: t.get($0, ["pin"])) }.filter { !$0.name.isEmpty }
        let a = ZuffiPA.load("Activity", header: ["Date", "Time", "Lead", "Staff", "Kind", "Detail"])
        activity = a.rows.suffix(3000).map { CRMActivity(date: a.get($0, ["date"]), time: a.get($0, ["time"]), lead: a.get($0, ["lead"]), staff: a.get($0, ["staff"]), kind: a.get($0, ["kind"]), detail: a.get($0, ["detail"])) }
        stamp = ZuffiBusiness.mtime(ZuffiPA.url("Leads"))
    }

    static func key(name: String, phone: String, row: Int) -> String {
        let d = phone.filter(\.isNumber)
        if d.count >= 9 { return "p" + d.suffix(10) }
        if !name.isEmpty { return "n" + name.lowercased() }
        return "r\(row)"
    }

    /// Changes one lead in Leads.csv (always on the newest file, so nothing anyone else wrote is lost).
    func edit(_ key: String, _ change: (inout ZuffiPA.Book, Int) -> Void) {
        var b = ZuffiPA.load("Leads", header: ZuffiPA.leadHeader)
        guard let i = b.rows.indices.first(where: { Self.key(name: b.get(b.rows[$0], ["name"]), phone: b.get(b.rows[$0], ["phone", "mobile"]), row: $0) == key }) else { return }
        change(&b, i)
        writeLeads(b)
    }

    private func writeLeads(_ b: ZuffiPA.Book) {
        ZuffiPA.save("Leads", b)
        reload()
        if !serverURL.isEmpty { Task { await self.pushLeads() } }
    }

    @discardableResult
    func addLead(_ f: [String: String], note: String = "") -> String {
        var b = ZuffiPA.load("Leads", header: ZuffiPA.leadHeader)
        let phone = f["phone"] ?? "", name = f["name"] ?? ""
        let today = ZuffiBusiness.iso(Date())
        if let i = b.rows.indices.first(where: { (!phone.isEmpty && ZuffiPA.samePhone(b.get(b.rows[$0], ["phone"]), phone)) || (phone.isEmpty && !name.isEmpty && b.get(b.rows[$0], ["name"]).lowercased() == name.lowercased()) }) {
            for (k, v) in f where !v.isEmpty && b.get(b.rows[i], [k]).isEmpty { b.set(i, [k], v) }
            if let m = f["last message"], !m.isEmpty { b.set(i, ["last message"], m); b.set(i, ["last message at"], f["last message at"] ?? Self.now()) }
            if !note.isEmpty { let o = b.get(b.rows[i], ["notes"]); b.set(i, ["notes"], o.isEmpty ? note : o + " | " + note) }
            writeLeads(b)
            return Self.key(name: b.get(b.rows[i], ["name"]), phone: b.get(b.rows[i], ["phone"]), row: i)
        }
        var row = Array(repeating: "", count: b.header.count)
        func put(_ k: String, _ v: String) { if let x = b.i([k]) { row[x] = v } }
        for (k, v) in f { put(k, v) }
        put("status", f["status"] ?? "New"); put("added", today)
        if (f["next follow"] ?? "").isEmpty { put("next follow", today) }
        if (f["assigned"] ?? "").isEmpty { put("assigned", nextAssignee()) }
        if !note.isEmpty { put("notes", [f["notes"] ?? "", note].filter { !$0.isEmpty }.joined(separator: " | ")) }
        b.rows.append(row)
        writeLeads(b)
        log(lead: name.isEmpty ? phone : name, staff: row[b.i(["assigned"]) ?? 0], kind: "New lead", detail: f["source"] ?? "")
        return Self.key(name: name, phone: phone, row: b.rows.count - 1)
    }

    func setStage(_ key: String, _ stage: String) {
        guard let l = leads.first(where: { $0.key == key }) else { return }
        edit(key) { b, i in b.set(i, ["status"], stage); b.set(i, ["last contact"], ZuffiBusiness.iso(Date())) }
        log(lead: l.display, staff: l.assigned, kind: "Stage", detail: stage)
    }
    func assign(_ key: String, to staff: String) {
        guard let l = leads.first(where: { $0.key == key }) else { return }
        edit(key) { b, i in b.set(i, ["assigned"], staff) }
        log(lead: l.display, staff: staff, kind: "Assigned", detail: staff.isEmpty ? "unassigned" : "to \(staff)")
    }
    func update(_ lead: CRMLead) {
        edit(lead.key) { b, i in
            b.set(i, ["name"], lead.name); b.set(i, ["phone"], lead.phone); b.set(i, ["source"], lead.source)
            b.set(i, ["interest"], lead.interest); b.set(i, ["area"], lead.area); b.set(i, ["budget"], lead.budget)
            b.set(i, ["status"], lead.status); b.set(i, ["priority"], lead.priority); b.set(i, ["assigned"], lead.assigned)
            b.set(i, ["next follow"], lead.nextFollowUp); b.set(i, ["notes"], lead.notes)
        }
    }
    func delete(_ key: String) {
        var b = ZuffiPA.load("Leads", header: ZuffiPA.leadHeader)
        guard let i = b.rows.indices.first(where: { Self.key(name: b.get(b.rows[$0], ["name"]), phone: b.get(b.rows[$0], ["phone"]), row: $0) == key }) else { return }
        b.rows.remove(at: i)
        writeLeads(b)
    }

    func log(lead: String, staff: String, kind: String, detail: String) {
        var a = ZuffiPA.load("Activity", header: ["Date", "Time", "Lead", "Staff", "Kind", "Detail"])
        a.rows.append([ZuffiBusiness.iso(Date()), ZuffiPA.hm(Date()), lead, staff.isEmpty ? (ownerName.isEmpty ? "Owner" : ownerName) : staff, kind, detail])
        if a.rows.count > 5000 { a.rows.removeFirst(a.rows.count - 5000) }
        ZuffiPA.save("Activity", a)
        activity.append(CRMActivity(date: ZuffiBusiness.iso(Date()), time: ZuffiPA.hm(Date()), lead: lead, staff: staff, kind: kind, detail: detail))
    }

    static func now() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: Date()) }

    // MARK: Team

    func saveTeam(_ list: [CRMStaff]) {
        ZuffiPA.save("Team", ZuffiPA.Book(header: ["Name", "Phone", "Role", "PIN"], rows: list.map { [$0.name, $0.phone, $0.role, $0.pin] }))
        team = list
        if !serverURL.isEmpty { Task { await self.pushTeam() } }
    }
    func addStaff(name: String, phone: String, role: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !team.contains(where: { $0.name.lowercased() == n.lowercased() }) else { return }
        saveTeam(team + [CRMStaff(name: n, phone: phone, role: role, pin: String(format: "%04d", Int.random(in: 1000...9999)))])
    }
    func removeStaff(_ s: CRMStaff) {
        saveTeam(team.filter { $0.name != s.name })
        for l in leads where l.assigned == s.name { edit(l.key) { b, i in b.set(i, ["assigned"], "") } }
    }

    /// The team member who gets the next new lead (round robin), or "" when sharing is off / no team.
    func nextAssignee() -> String {
        let agents = team.filter { !$0.role.lowercased().contains("owner") }
        guard isOn(.roundRobin), !agents.isEmpty else { return "" }
        let s = agents[rr % agents.count]
        rr += 1; UserDefaults.standard.set(rr, forKey: "crmRoundRobin")
        return s.name
    }

    func reports() -> [StaffReport] {
        let today = ZuffiBusiness.iso(Date())
        let weekAgo = ZuffiBusiness.iso(Date().addingTimeInterval(-7 * 86400))
        let contactKinds: Set<String> = ["Message", "Stage", "Follow-up", "Called", "Updated", "Note"]
        return team.map { s in
            let mine = leads.filter { $0.assigned == s.name }
            let over = mine.filter(\.overdue)
            return StaffReport(name: s.name, assigned: mine.count, open: mine.filter(\.isOpen).count, overdue: over.count,
                               contacted7: activity.filter { $0.staff == s.name && $0.date >= weekAgo && contactKinds.contains($0.kind) }.count,
                               won: mine.filter { $0.stage == "Won" }.count, newToday: mine.filter { $0.added == today }.count,
                               overdueNames: over.prefix(5).map(\.display))
        }.sorted { $0.overdue > $1.overdue }
    }

    // MARK: Summary

    func summary(for staff: String? = nil) -> String {
        let today = ZuffiBusiness.iso(Date()), yesterday = ZuffiBusiness.iso(Date().addingTimeInterval(-86400))
        let pool = staff.map { s in leads.filter { $0.assigned == s } } ?? leads
        let fresh = pool.filter { $0.added == today || $0.added == yesterday }
        let hot = pool.filter { $0.isOpen && $0.priority.lowercased() == "hot" }
        let due = pool.filter(\.dueToday)
        var lines: [String] = []
        let h = Calendar.current.component(.hour, from: Date())
        lines.append("\(h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening")\(staff.map { " \($0)" } ?? (ownerName.isEmpty ? "" : " \(ownerName)"))! 🐰")
        var bySrc: [String: Int] = [:]
        for l in fresh { bySrc[l.source.isEmpty ? "Other" : l.source.components(separatedBy: " – ").first!, default: 0] += 1 }
        lines.append("📥 \(fresh.count) new lead\(fresh.count == 1 ? "" : "s") since yesterday" + (bySrc.isEmpty ? "" : " (" + bySrc.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: ", ") + ")"))
        if !hot.isEmpty { lines.append("🔥 Hot: " + hot.prefix(6).map { "\($0.display)\($0.phone.isEmpty ? "" : " \($0.phone)")" }.joined(separator: ", ")) }
        lines.append("📞 Follow up today (\(due.count)): " + (due.isEmpty ? "none 🎉" : due.prefix(8).map(\.display).joined(separator: ", ")))
        let won = pool.filter { $0.stage == "Won" && ($0.lastContact >= ZuffiBusiness.iso(Date().addingTimeInterval(-30 * 86400))) }
        if !won.isEmpty { lines.append("🏆 Won in the last 30 days: \(won.count)") }
        if staff == nil, !team.isEmpty {
            lines.append("👥 Team:")
            for r in reports() {
                lines.append("• \(r.name): \(r.open) open, \(r.contacted7) contacts this week, \(r.won) won" + (r.overdue > 0 ? " — ⚠️ \(r.overdue) overdue (\(r.overdueNames.joined(separator: ", ")))" : " ✅"))
            }
            let slow = reports().filter { $0.overdue > 0 }.map(\.name)
            if !slow.isEmpty { lines.append("⚠️ Not following up: " + slow.joined(separator: ", ")) }
            let un = leads.filter { $0.isOpen && $0.assigned.isEmpty }.count
            if un > 0 { lines.append("📌 \(un) lead\(un == 1 ? "" : "s") with nobody assigned") }
        }
        return lines.joined(separator: "\n")
    }

    func sendSummaryNow() async -> String {
        guard !ownerPhone.isEmpty else { return "Add your own WhatsApp number in Automations first." }
        let r = await WhatsAppAgent.shared.sendScheduled(to: ownerPhone, text: summary())
        return r
    }

    // MARK: Automations (called every 30 s)

    func tick() {
        if let m = ZuffiBusiness.mtime(ZuffiPA.url("Leads")), m != stamp { reload() }
        let now = Date()
        if isOn(.watchWhatsApp), now.timeIntervalSince(lastWatch) > 55 { lastWatch = now; Task { await self.watchWhatsApp() } }
        if isOn(.voiceNotes) { scanVoiceNotes() }
        if !serverURL.isEmpty, now.timeIntervalSince(lastSync) > 60 { lastSync = now; Task { await self.pullServer() } }
        if isOn(.quietFollowUp) { draftQuietFollowUps() }
        let cal = Calendar.current
        let todayKey = ZuffiBusiness.iso(now)
        if cal.component(.hour, from: now) == summaryHour, UserDefaults.standard.string(forKey: "crmSummarySent") != todayKey,
           isOn(.ownerSummary) || isOn(.staffDigest) {
            UserDefaults.standard.set(todayKey, forKey: "crmSummarySent")
            Task {
                if self.isOn(.ownerSummary), !self.ownerPhone.isEmpty { _ = await WhatsAppAgent.shared.sendScheduled(to: self.ownerPhone, text: self.summary()) }
                if self.isOn(.staffDigest) {
                    for s in self.team where !s.phone.isEmpty {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        _ = await WhatsAppAgent.shared.sendScheduled(to: s.phone, text: self.summary(for: s.name))
                    }
                }
            }
        }
    }

    // MARK: WhatsApp on this Mac → leads

    func watchWhatsApp() async {
        guard NSWorkspace.shared.runningApplications.contains(where: WhatsAppAgent.isWhatsApp) else { whatsAppStatus = "WhatsApp isn't open on this Mac"; return }
        guard AXIsProcessTrusted() else { whatsAppStatus = "Zuffi needs Accessibility to read WhatsApp"; return }
        let rows = await WhatsAppAgent.unreadRows()
        lastWhatsAppCheck = Date()
        whatsAppStatus = rows.isEmpty ? "Watching — no unread chats" : "Watching — \(rows.count) unread chat\(rows.count == 1 ? "" : "s")"
        for r in rows {
            let sig = r.name + "|" + r.preview
            guard !seenRows.contains(sig) else { continue }
            seenRows.insert(sig)
            if r.name.lowercased().contains("group") { continue }
            await handleIncoming(name: r.name, preview: r.preview, source: "WhatsApp")
        }
    }

    /// One incoming message (from this Mac or the server): find or create the lead, fill details, draft a reply.
    func handleIncoming(name rawName: String, preview: String, source: String, phone rawPhone: String = "") async {
        let isNumber = rawName.filter(\.isNumber).count >= 9 && rawName.filter(\.isLetter).isEmpty
        let phone = rawPhone.isEmpty ? (isNumber ? rawName.filter { $0.isNumber || $0 == "+" } : "") : rawPhone
        let name = isNumber ? "" : rawName
        let voice = preview.range(of: #"(?i)voice (message|note)|audio|🎤|ptt|^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
        let existing = leads.first { (!phone.isEmpty && ZuffiPA.samePhone($0.phone, phone)) || (!name.isEmpty && $0.name.lowercased() == name.lowercased()) }
        var f: [String: String] = ["name": name, "phone": phone, "last message": voice ? "🎤 Voice note" : preview, "last message at": Self.now()]
        if existing == nil {
            f["source"] = source
            if !voice, preview.count > 8 { for (k, v) in await extract(preview) where (f[k] ?? "").isEmpty { f[k] = v } }
        }
        let key = addLead(f, note: voice ? "Sent a voice note — save it to Downloads and I'll write it out." : "")
        if existing == nil {
            SoundEngine.shared.play("chime")
            NotificationCenter.default.post(name: .petSay, object: "New WhatsApp lead: \(name.isEmpty ? phone : name)")
        }
        if isOn(.draftReplies) || isOn(.autoReply), !voice, let lead = leads.first(where: { $0.key == key }) {
            let reply = await draftReply(for: lead, incoming: preview, first: existing == nil)
            drafts[key] = reply
            if isOn(.autoReply), existing == nil, !reply.isEmpty {
                _ = await send(key, reply)
            }
        }
    }

    // MARK: AI helpers

    /// Lead details from free text (a message, a voice note).
    func extract(_ text: String) async -> [String: String] {
        var out: [String: String] = [:]
        if let p = ZuffiPA.phone(in: text) { out["phone"] = p }
        if let b = ZuffiPA.budget(in: text.lowercased()) { out["budget"] = b }
        let prompt = """
        A client wrote to a \(isEstate ? "Pakistani property agent" : "small business (salon / shop)"). Pull out what they want. Return JSON:
        {"name":"","phone":"","interest":"what they want, short","area":"","budget":"as said","priority":"hot|warm|cold","notes":"anything else useful, short"}
        hot = ready to buy/book now or asks for a visit/price; cold = just browsing. Empty string if not said.
        Message: \(text.prefix(4000))
        """
        if let r = await AIService.shared.oneShot(prompt), let j = AIService.jsonIn(r) as? [String: Any] {
            for k in ["name", "phone", "interest", "area", "budget", "priority", "notes"] {
                if let v = j[k] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty { out[k] = k == "priority" ? v.capitalized : v }
            }
        }
        return out
    }

    func draftReply(for l: CRMLead, incoming: String, first: Bool) async -> String {
        let biz = ZuffiBusiness.shared.businessName
        let firstName = l.name.split(separator: " ").first.map(String.init) ?? ""
        let fallback = !welcomeText.isEmpty ? welcomeText.replacingOccurrences(of: "{name}", with: firstName)
            : isEstate ? "Assalam o Alaikum\(firstName.isEmpty ? "" : " \(firstName)")! Thank you for contacting \(biz.isEmpty ? "us" : biz). Which area are you looking in, what size and what's your budget? I'll send you the best options."
            : "Hi\(firstName.isEmpty ? "" : " \(firstName)")! Thanks for messaging \(biz.isEmpty ? "us" : biz). What would you like to book, and which day suits you?"
        var context = ""
        if isEstate, let s = ZuffiData.shared.sheets.first(where: { $0.name.lowercased().hasPrefix("listings") }) {
            context = "Our available listings (CSV):\n" + ZuffiData.shared.rows(s).prefix(40).map { $0.joined(separator: ", ") }.joined(separator: "\n")
        } else if !isEstate {
            context = "Upcoming bookings (to see free times):\n" + ZuffiPA.load("Appointments", header: ZuffiPA.apptHeader).rows.suffix(30).map { $0.joined(separator: ", ") }.joined(separator: "\n")
        }
        let prompt = """
        You write WhatsApp replies for \(biz.isEmpty ? "a business" : biz) (\(isEstate ? "property agent in Pakistan" : "UK small business, e.g. a salon")).
        Reply to the client's message in THEIR language and script (English, Urdu or Roman Urdu). Short, warm, human, 1-3 sentences, no emojis overload.
        \(first ? "This is their first message: greet them and ask only what's missing (area/size/budget or service/day)." : "Continue the conversation helpfully.")
        If you can match their request to a listing or a free time below, mention it briefly. Never invent prices or listings that aren't below.
        Client: \(l.display). What we know: \([l.interest, l.area, l.budget].filter { !$0.isEmpty }.joined(separator: ", "))
        \(context)
        Their message: \(incoming)
        Return ONLY the reply text.
        """
        guard let r = await AIService.shared.oneShot(prompt, system: "You write short WhatsApp replies for a business. Reply with the message text only.") else { return fallback }
        let clean = r.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        return clean.isEmpty ? fallback : clean
    }

    /// Sends a WhatsApp message to a lead (via the server when connected, else WhatsApp on this Mac) and logs it.
    func send(_ key: String, _ text: String) async -> String {
        guard let l = leads.first(where: { $0.key == key }) else { return "Lead not found." }
        let to = l.phone.isEmpty ? l.name : l.phone
        guard !to.isEmpty else { return "No number for this lead." }
        var result = ""
        if !serverURL.isEmpty, !l.phone.isEmpty, let r = await serverSend(phone: l.phone, text: text) { result = r }
        else { result = await WhatsAppAgent.shared.sendScheduled(to: to, text: text) }
        drafts[key] = nil
        edit(key) { b, i in
            b.set(i, ["last contact"], ZuffiBusiness.iso(Date()))
            if ZuffiCRM.stage(for: b.get(b.rows[i], ["status"])) == "New" { b.set(i, ["status"], "Contacted") }
            if b.get(b.rows[i], ["next follow"]) <= ZuffiBusiness.iso(Date()) { b.set(i, ["next follow"], ZuffiBusiness.iso(Date().addingTimeInterval(Double(self.quietDays) * 86400))) }
        }
        log(lead: l.display, staff: l.assigned, kind: "Message", detail: String(text.prefix(80)))
        return result
    }

    private func draftQuietFollowUps() {
        let cut = ZuffiBusiness.iso(Date().addingTimeInterval(-Double(quietDays) * 86400))
        for l in leads where l.isOpen && drafts[l.key] == nil && !l.lastContact.isEmpty && l.lastContact <= cut && (l.followDate.map { $0 <= Date() } ?? true) && !l.phone.isEmpty {
            let first = l.name.split(separator: " ").first.map(String.init) ?? ""
            drafts[l.key] = isEstate
                ? "Assalam o Alaikum \(first), just checking in\(l.interest.isEmpty ? "" : " about the \(l.interest)")\(l.area.isEmpty ? "" : " in \(l.area)"). I have a few new options — shall I send them?"
                : "Hi \(first), just checking in — would you like me to book you in? I have some free times this week."
        }
    }

    // MARK: Voice notes → text → lead

    private var seenAudio: [String: Double] = UserDefaults.standard.dictionary(forKey: "crmSeenAudio") as? [String: Double] ?? [:]

    private func scanVoiceNotes() {
        let dl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dl, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let recent = Date().addingTimeInterval(-86400)
        for u in files where ["opus", "ogg", "m4a", "mp3", "aac", "wav", "oga"].contains(u.pathExtension.lowercased()) && u.lastPathComponent.lowercased().contains("whatsapp") {
            guard let m = ZuffiBusiness.mtime(u), m > recent, seenAudio[u.path] == nil else { continue }
            seenAudio[u.path] = m.timeIntervalSince1970
            UserDefaults.standard.set(seenAudio, forKey: "crmSeenAudio")
            Task { _ = await self.voiceNoteToLead(u) }
        }
    }

    /// Writes out a voice note and turns it into (or adds it to) a lead. Returns a short message.
    func voiceNoteToLead(_ url: URL, for key: String? = nil) async -> String {
        busy = "Listening to the voice note…"
        defer { busy = "" }
        guard let text = await VoiceNotes.transcribe(url), !text.isEmpty else {
            return "I couldn't write out that voice note. Add a free Groq key in Settings → AI models (best for Urdu), then try again."
        }
        let note = "🎤 \"\(text.prefix(600))\""
        if let key, leads.contains(where: { $0.key == key }) {
            let f = await extract(text)
            edit(key) { b, i in
                for (k, v) in f where b.get(b.rows[i], [k]).isEmpty { b.set(i, [k], v) }
                let o = b.get(b.rows[i], ["notes"]); b.set(i, ["notes"], o.isEmpty ? note : o + " | " + note)
                b.set(i, ["last message"], "🎤 " + String(text.prefix(120))); b.set(i, ["last message at"], ZuffiCRM.now())
            }
            return "Added the voice note to the lead: \(text.prefix(140))"
        }
        var f = await extract(text)
        f["source"] = "WhatsApp voice note"
        f["last message"] = "🎤 " + String(text.prefix(120)); f["last message at"] = Self.now()
        if (f["name"] ?? "").isEmpty && (f["phone"] ?? "").isEmpty { f["name"] = "Voice note " + ZuffiPA.hm(Date()) }
        addLead(f, note: note)
        NotificationCenter.default.post(name: .petSay, object: "Voice note written out and saved as a lead 🎤")
        return "Voice note → lead ✅ \(text.prefix(140))"
    }

    // MARK: Always-on server (WhatsApp Business API + Coexistence)

    private var serverKey: String { KeychainStore.shared.get("zuffi-server-key") ?? "" }

    private func api(_ path: String, method: String = "GET", body: Any? = nil) async -> Any? {
        guard let base = URL(string: serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))), !serverKey.isEmpty else { return nil }
        var req = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        req.httpMethod = method
        req.setValue("Bearer \(serverKey)", forHTTPHeaderField: "Authorization")
        if let body { req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    func testServer() async {
        serverStatus = "Checking…"
        if let j = await api("api/status") as? [String: Any] {
            let wa = (j["whatsapp"] as? Bool) == true
            serverStatus = "Connected ✓" + (wa ? " · WhatsApp linked (\(j["number"] as? String ?? ""))" : " · WhatsApp not linked yet")
        } else { serverStatus = "Can't reach the server — check the address and key." }
    }

    /// New messages and leads that arrived at the server (also while this Mac was off).
    func pullServer() async {
        let since = UserDefaults.standard.string(forKey: "crmServerSince") ?? ""
        guard let j = await api("api/leads?since=\(since.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") as? [String: Any],
              let list = j["leads"] as? [[String: Any]] else { return }
        serverStatus = "Connected ✓ · synced \(ZuffiPA.hm(Date()))"
        for d in list {
            var f: [String: String] = [:]
            for (k, col) in [("name", "name"), ("phone", "phone"), ("source", "source"), ("interest", "interest"), ("area", "area"), ("budget", "budget"),
                             ("priority", "priority"), ("assigned", "assigned"), ("status", "status"), ("last_message", "last message"), ("last_message_at", "last message at")] {
                if let v = d[k] as? String, !v.isEmpty { f[col] = v }
            }
            let key = addLead(f, note: (d["voice_text"] as? String).map { "🎤 \"\($0)\"" } ?? "")
            if let draft = d["draft"] as? String, !draft.isEmpty { drafts[key] = draft }
        }
        if let s = j["now"] as? String { UserDefaults.standard.set(s, forKey: "crmServerSince") }
    }

    func pushLeads() async {
        let rows = leads.map { ["name": $0.name, "phone": $0.phone, "status": $0.status, "priority": $0.priority, "assigned": $0.assigned,
                                "next_follow_up": $0.nextFollowUp, "notes": $0.notes, "interest": $0.interest, "area": $0.area, "budget": $0.budget, "source": $0.source] }
        _ = await api("api/leads", method: "PUT", body: ["leads": rows])
    }

    func pushTeam() async {
        _ = await api("api/team", method: "PUT", body: ["team": team.map { ["name": $0.name, "phone": $0.phone, "role": $0.role, "pin": $0.pin] },
                                                        "owner_phone": ownerPhone, "summary_hour": summaryHour,
                                                        "auto": Dictionary(uniqueKeysWithValues: Auto.allCases.map { ($0.rawValue, isOn($0)) }),
                                                        "welcome": welcomeText, "business": ZuffiBusiness.shared.businessName,
                                                        "kind": isEstate ? "estate" : "salon"])
    }

    private func serverSend(phone: String, text: String) async -> String? {
        guard let j = await api("api/send", method: "POST", body: ["to": phone, "text": text]) as? [String: Any] else { return nil }
        return (j["ok"] as? Bool) == true ? "Sent ✅" : (j["error"] as? String)
    }
}

// MARK: - Voice note transcription

enum VoiceNotes {
    /// Groq Whisper (free key, best with Urdu/Punjabi/English mix) → OpenAI → Apple's own speech recognition.
    @MainActor static func transcribe(_ url: URL) async -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var name = url.lastPathComponent
        if url.pathExtension.lowercased() == "opus" { name = url.deletingPathExtension().lastPathComponent + ".ogg" }
        if let k = KeychainStore.shared.get("groq-api-key"), !k.isEmpty,
           let t = await whisper("https://api.groq.com/openai/v1/audio/transcriptions", key: k, model: "whisper-large-v3", file: data, name: name) { return t }
        if let k = KeychainStore.shared.get("openai-api-key"), !k.isEmpty,
           let t = await whisper("https://api.openai.com/v1/audio/transcriptions", key: k, model: "whisper-1", file: data, name: name) { return t }
        return await apple(url)
    }

    nonisolated static func whisper(_ endpoint: String, key: String, model: String, file: Data, name: String) async -> String? {
        let boundary = "zuffi-\(UUID().uuidString)"
        var body = Data()
        func field(_ n: String, _ v: String) { body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".utf8)) }
        field("model", model)
        field("response_format", "json")
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\nContent-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(file)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        guard let u = URL(string: endpoint) else { return nil }
        var req = URLRequest(url: u, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        guard let (d, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = j["text"] as? String else { return nil }
        let clean = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    /// On-device fallback (works for m4a / mp3 / wav; WhatsApp's .opus needs Groq or OpenAI).
    @MainActor static func apple(_ url: URL) async -> String? {
        guard ["m4a", "mp3", "wav", "aac", "caf"].contains(url.pathExtension.lowercased()) else { return nil }
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
        guard ok else { return nil }
        let rec = SFSpeechRecognizer(locale: Locale(identifier: "ur-PK")) ?? SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer()
        guard let rec, rec.isAvailable else { return nil }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            _ = rec.recognitionTask(with: req) { result, error in
                if once.done { return }
                if let result, result.isFinal { once.done = true; c.resume(returning: result.bestTranscription.formattedString) }
                else if error != nil { once.done = true; c.resume(returning: nil) }
            }
        }
    }
}
