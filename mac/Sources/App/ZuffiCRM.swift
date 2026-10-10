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
    var name = "", phone = "", source = "", interest = "", area = "", budget = "", value = ""
    var status = "New", priority = "", assigned = "", added = "", lastContact = "", nextFollowUp = ""
    var lastMessage = "", lastMessageAt = "", notes = ""
    var draft = ""            // suggested reply (kept in memory)

    var stage: String { ZuffiCRM.stage(for: status) }
    var isOpen: Bool { !["Won", "Lost", "Delivered"].contains(stage) }
    /// A sale happened (counts for revenue).
    var isSale: Bool { ["Won", "Visited", "Regular", "Ordered", "Delivered"].contains(stage) }
    var valueNumber: Double { Double(value.filter { $0.isNumber || $0 == "." }) ?? 0 }
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
    var payType = "Monthly"     // Monthly · Hourly · Commission
    var rate = ""               // salary per month, pay per hour, or commission %
    var start = ""
    var notes = ""
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

    // What Zuffi knows about the business (used in every reply)
    static var infoURL: URL { ZuffiBusiness.docs.appendingPathComponent("Business info.txt") }
    @Published var businessInfo: String = (try? String(contentsOf: ZuffiCRM.infoURL, encoding: .utf8)) ?? "" {
        didSet { try? businessInfo.write(to: Self.infoURL, atomically: true, encoding: .utf8); syncSoon() }
    }
    @Published var todayUpdate = UserDefaults.standard.string(forKey: "crmTodayUpdate") ?? "" {
        didSet { UserDefaults.standard.set(todayUpdate, forKey: "crmTodayUpdate"); UserDefaults.standard.set(ZuffiBusiness.iso(Date()), forKey: "crmTodayUpdateDate"); syncSoon() }
    }
    /// Today's update, only if it was given today.
    var todaysUpdate: String { UserDefaults.standard.string(forKey: "crmTodayUpdateDate") == ZuffiBusiness.iso(Date()) ? todayUpdate : "" }
    @Published var autoSent: [String] = []      // what autopilot sent recently (shown in Inbox)
    private var autoCount: [String: Int] = [:]
    private var recentIn: [String: (text: String, at: Date)] = [:]
    private var outbox: [(key: String, text: String, queued: Date)] = []
    private var outboxRunning = false
    private var syncTask: Task<Void, Never>?
    /// Sends settings to the always-on server a few seconds after you stop typing.
    private func syncSoon() {
        guard !serverURL.isEmpty else { return }
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled { await self.pushTeam() }
        }
    }

    enum Auto: String, CaseIterable, Identifiable {
        case autopilot, watchWhatsApp, draftReplies, autoReply, morningAsk, voiceNotes, leadExports, roundRobin, quietFollowUp, ownerSummary, staffDigest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .autopilot: return "Autopilot — let Zuffi chat with clients"
            case .morningAsk: return "Ask me each morning for today's offers and news"
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
            case .autopilot: return "Zuffi answers every client message by itself, using your business info and today's update, in the client's language. It hands over to you (and doesn't reply) when someone wants to bargain, complains, asks for a person or asks something it doesn't know. It waits until you stop typing before it sends."
            case .morningAsk: return "At your summary hour Zuffi asks “any offers or news today?”. Tell it “today's update: …” and it uses it in replies all day."
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
        var defaultOn: Bool { ![.autopilot, .autoReply, .ownerSummary, .staffDigest].contains(self) }
    }

    func isOn(_ a: Auto) -> Bool { UserDefaults.standard.object(forKey: "auto_" + a.rawValue) as? Bool ?? a.defaultOn }
    func set(_ a: Auto, _ on: Bool) { objectWillChange.send(); UserDefaults.standard.set(on, forKey: "auto_" + a.rawValue); syncSoon() }

    private init() { reload() }

    // MARK: Stages

    var kind: ZuffiBusiness.Pack { ZuffiBusiness.shared.pack ?? .realEstate }
    var isEstate: Bool { kind == .realEstate }
    var stages: [String] {
        switch kind {
        case .realEstate: return ["New", "Contacted", "Site visit", "Negotiating", "Won", "Lost"]
        case .salon, .clinic, .restaurant: return ["New", "Contacted", "Booked", "Visited", "Regular", "Lost"]
        case .shop: return ["New", "Contacted", "Quoted", "Ordered", "Delivered", "Lost"]
        case .services: return ["New", "Contacted", "Quoted", "Negotiating", "Won", "Lost"]
        }
    }
    /// Field names that fit the business.
    var labels: (interest: String, area: String, budget: String, value: String) {
        switch kind {
        case .realEstate: return ("Wants", "Area", "Budget", "Deal value")
        case .salon, .clinic: return ("Service", "Preferred day / staff", "Budget", "Spent")
        case .restaurant: return ("Booking for", "Party size / time", "Budget", "Spent")
        case .shop: return ("Product", "Delivery area", "Budget", "Order value")
        case .services: return ("Job", "Location", "Budget", "Job value")
        }
    }
    /// "PK", "GB" or "OTHER" — picked in My business; decides currency and which business types show.
    @Published var country: String = UserDefaults.standard.string(forKey: "bizCountry")
        ?? (Locale.current.region?.identifier == "PK" ? "PK" : Locale.current.region?.identifier == "GB" ? "GB" : "OTHER") {
        didSet { UserDefaults.standard.set(country, forKey: "bizCountry"); if UserDefaults.standard.string(forKey: "bizCurrency") == nil { objectWillChange.send() } }
    }
    @Published var currencyChoice: String = UserDefaults.standard.string(forKey: "bizCurrency") ?? "" { didSet { UserDefaults.standard.set(currencyChoice, forKey: "bizCurrency") } }
    var currency: String {
        if !currencyChoice.isEmpty { return currencyChoice }
        switch country { case "PK": return "Rs"; case "GB": return "£"; default: return Locale.current.currencySymbol ?? "$" }
    }
    static let currencies = ["Rs", "£", "$", "€", "AED", "SAR", "₹"]
    /// Business types that fit the country.
    var packsForCountry: [ZuffiBusiness.Pack] {
        switch country {
        case "PK": return [.realEstate]
        case "GB": return [.salon, .clinic, .shop, .restaurant, .services, .realEstate]
        default: return ZuffiBusiness.Pack.allCases
        }
    }
    var businessWord: String {
        let country = self.country == "GB" ? "UK" : self.country == "PK" ? "Pakistani" : ""
        switch kind {
        case .realEstate: return "\(country.isEmpty ? "" : country + " ")property agent"
        case .salon: return "\(country.isEmpty ? "" : country + " ")salon / beauty business"
        case .clinic: return "\(country.isEmpty ? "" : country + " ")clinic"
        case .shop: return "\(country.isEmpty ? "" : country + " ")shop"
        case .restaurant: return "\(country.isEmpty ? "" : country + " ")restaurant"
        case .services: return "\(country.isEmpty ? "" : country + " ")service business"
        }
    }

    nonisolated static func stage(for raw: String) -> String {
        let s = raw.lowercased().trimmingCharacters(in: .whitespaces)
        let known = ["New", "Contacted", "Site visit", "Negotiating", "Won", "Lost", "Booked", "Visited", "Regular", "Quoted", "Ordered", "Delivered"]
        if let k = known.first(where: { $0.lowercased() == s }) { return k }
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
            l.interest = b.get(r, ["interest", "wants"]); l.area = b.get(r, ["area"]); l.budget = b.get(r, ["budget"]); l.value = b.get(r, ["value"])
            l.status = b.get(r, ["status"]); l.priority = b.get(r, ["priority"]); l.assigned = b.get(r, ["assigned"])
            l.added = b.get(r, ["added"]); l.lastContact = b.get(r, ["last contact"]); l.nextFollowUp = b.get(r, ["next follow"])
            l.lastMessage = b.get(r, ["last message"]); l.lastMessageAt = b.get(r, ["last message at"]); l.notes = b.get(r, ["notes"])
            l.key = Self.key(name: l.name, phone: l.phone, row: i)
            return l
        }
        let t = ZuffiPA.load("Team", header: Self.teamHeader)
        team = t.rows.map {
            CRMStaff(name: t.get($0, ["name"]), phone: t.get($0, ["phone"]), role: t.get($0, ["role"]), pin: t.get($0, ["pin"]),
                     payType: t.get($0, ["pay type"]).ifBlank("Monthly"), rate: t.get($0, ["rate"]), start: t.get($0, ["start"]), notes: t.get($0, ["notes"]))
        }.filter { !$0.name.isEmpty }
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
            b.set(i, ["interest"], lead.interest); b.set(i, ["area"], lead.area); b.set(i, ["budget"], lead.budget); b.set(i, ["value"], lead.value)
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
        ZuffiPA.save("Team", ZuffiPA.Book(header: Self.teamHeader, rows: list.map { [$0.name, $0.phone, $0.role, $0.pin, $0.payType, $0.rate, $0.start, $0.notes] }))
        team = list
        if !serverURL.isEmpty { Task { await self.pushTeam() } }
    }
    static let teamHeader = ["Name", "Phone", "Role", "PIN", "Pay type", "Rate", "Start date", "Notes"]

    func addStaff(name: String, phone: String, role: String, payType: String = "Monthly", rate: String = "") {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !team.contains(where: { $0.name.lowercased() == n.lowercased() }) else { return }
        saveTeam(team + [CRMStaff(name: n, phone: phone, role: role, pin: String(format: "%04d", Int.random(in: 1000...9999)),
                                  payType: payType, rate: rate, start: ZuffiBusiness.iso(Date()))])
    }
    func updateStaff(_ s: CRMStaff) { saveTeam(team.map { $0.name == s.name ? s : $0 }) }
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
        NotificationReader.shared.refresh()
        ZuffiMoney.shared.tick()
        if isOn(.watchWhatsApp), now.timeIntervalSince(lastWatch) > 8 { lastWatch = now; Task { await self.watchWhatsApp() } }
        if isOn(.voiceNotes) { scanVoiceNotes() }
        if !serverURL.isEmpty, now.timeIntervalSince(lastSync) > 60 { lastSync = now; Task { await self.pullServer() } }
        if isOn(.quietFollowUp) { draftQuietFollowUps() }
        let cal = Calendar.current
        let todayKey = ZuffiBusiness.iso(now)
        if isOn(.morningAsk), ZuffiBusiness.shared.pack != nil, cal.component(.hour, from: now) >= summaryHour, cal.component(.hour, from: now) < 13,
           UserDefaults.standard.string(forKey: "crmMorningAsk") != todayKey, todaysUpdate.isEmpty {
            UserDefaults.standard.set(todayKey, forKey: "crmMorningAsk")
            let msg = "Good morning! Any offers, new items or news for today? Tell me “today's update: …” and I'll share it with clients."
            NotificationCenter.default.post(name: .petSay, object: msg)
            ZuffiHomeModel.shared.say(msg)
            SoundEngine.shared.play("chime")
        }
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
        guard NSWorkspace.shared.runningApplications.contains(where: WhatsAppAgent.isWhatsApp) else {
            whatsAppStatus = WhatsAppAgent.installed ? "WhatsApp is installed but not open — press Open WhatsApp" : "WhatsApp isn't installed on this Mac — press Get WhatsApp"
            return
        }
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

    /// One incoming message (from this Mac, a notification or the server): find or create the lead,
    /// fill in details, write a reply — and with autopilot on, send it.
    func handleIncoming(name rawName: String, preview: String, source: String, phone rawPhone: String = "") async {
        let isNumber = rawName.filter(\.isNumber).count >= 9 && rawName.filter(\.isLetter).isEmpty
        let phone = rawPhone.isEmpty ? (isNumber ? rawName.filter { $0.isNumber || $0 == "+" } : "") : rawPhone
        let name = isNumber ? "" : rawName
        let text = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        // The same message can arrive twice (banner + chat list): ignore the repeat.
        let who = (phone.isEmpty ? name : String(phone.filter(\.isNumber).suffix(10))).lowercased()
        if let r = recentIn[who], Date().timeIntervalSince(r.at) < 600,
           r.text.hasPrefix(String(text.prefix(18))) || text.hasPrefix(String(r.text.prefix(18))) { return }
        recentIn[who] = (text, Date())

        let voice = text.range(of: #"(?i)voice (message|note)|audio|🎤|ptt|^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
        let existing = leads.first { (!phone.isEmpty && ZuffiPA.samePhone($0.phone, phone)) || (!name.isEmpty && $0.name.lowercased() == name.lowercased()) }
        var f: [String: String] = ["name": name, "phone": phone, "last message": voice ? "🎤 Voice note" : text, "last message at": Self.now()]
        if existing == nil { f["source"] = source }
        let pilot = isOn(.autopilot), wantsReply = pilot || isOn(.draftReplies) || isOn(.autoReply)
        // Without replies we still fill in the lead (one quick AI call).
        if !voice, !wantsReply, text.count > 6 {
            let found = await extract(text)
            for (k, v) in found where (f[k] ?? "").isEmpty {
                if existing != nil && !["interest", "area", "budget", "priority"].contains(k) { continue }
                f[k] = v
            }
        }
        let key = addLead(f, note: voice ? "Sent a voice note — save it to Downloads and I'll write it out." : "")
        logMessage(key: key, display: name.isEmpty ? phone : name, dir: "in", text: voice ? "🎤 Voice note" : text)
        if existing == nil {
            SoundEngine.shared.play("chime")
            NotificationCenter.default.post(name: .petSay, object: "New WhatsApp lead: \(name.isEmpty ? phone : name)")
        }
        guard !voice, wantsReply, let lead = leads.first(where: { $0.key == key }) else { return }
        let r = await smartReply(for: lead, incoming: text, first: existing == nil)
        // Details the AI picked up in the same call go into the lead.
        if !r.details.isEmpty {
            edit(key) { b, i in
                for (k, v) in r.details where !v.isEmpty {
                    if k == "priority" { if b.get(b.rows[i], ["priority"]).isEmpty || v == "Hot" { b.set(i, ["priority"], v) } }
                    else if b.get(b.rows[i], [k]).isEmpty { b.set(i, [k], v) }
                }
            }
        }
        guard !r.reply.isEmpty else { return }
        drafts[key] = r.reply
        if let why = r.handoff {
            // Zuffi doesn't know or shouldn't answer: you take over.
            edit(key) { b, i in b.set(i, ["priority"], "Hot") }
            log(lead: lead.display, staff: lead.assigned, kind: "Needs you", detail: why)
            let msg = "\(lead.display) needs you: \(why)"
            NotificationCenter.default.post(name: .petSay, object: msg)
            ZuffiHomeModel.shared.say(msg)
            return
        }
        let countKey = key + ZuffiBusiness.iso(Date())
        if (pilot || (isOn(.autoReply) && existing == nil)), autoCount[countKey, default: 0] < 12 {
            autoCount[countKey, default: 0] += 1
            enqueueAuto(key, r.reply)
        }
    }

    // MARK: Sending without getting in your way

    /// Autopilot messages wait until you stop typing / clicking (max ~2 minutes), then go out,
    /// and the app you were using comes back to the front.
    private func enqueueAuto(_ key: String, _ text: String) {
        outbox.append((key, text, Date()))
        guard !outboxRunning else { return }
        outboxRunning = true
        Task { @MainActor in
            while !self.outbox.isEmpty {
                let idle = [CGEventType.keyDown, .leftMouseDown, .mouseMoved, .scrollWheel]
                    .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 99
                if idle >= 4 || Date().timeIntervalSince(self.outbox[0].queued) > 30 {
                    let item = self.outbox.removeFirst()
                    let front = NSWorkspace.shared.frontmostApplication
                    let res = await self.send(item.key, item.text, auto: true)
                    if let l = self.leads.first(where: { $0.key == item.key }) {
                        self.autoSent.insert("\(ZuffiPA.hm(Date())) → \(l.display): \(item.text.prefix(70))", at: 0)
                        if self.autoSent.count > 30 { self.autoSent.removeLast() }
                    }
                    appendAppLog("agents.log", "autopilot: \(res)")
                    if let front, !WhatsAppAgent.isWhatsApp(front), front.bundleIdentifier != Bundle.main.bundleIdentifier {
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        front.bringForward()
                    }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
            self.outboxRunning = false
        }
    }

    // MARK: Conversation log (so replies know what was said before)

    func logMessage(key: String, display: String, dir: String, text: String) {
        var m = ZuffiPA.load("Messages", header: ["At", "Lead", "Name", "Direction", "Text"])
        m.rows.append([Self.now(), key, display, dir, text])
        if m.rows.count > 8000 { m.rows.removeFirst(m.rows.count - 8000) }
        ZuffiPA.save("Messages", m)
    }
    func history(_ key: String, limit: Int = 10) -> [(dir: String, text: String, at: String)] {
        let m = ZuffiPA.load("Messages", header: ["At", "Lead", "Name", "Direction", "Text"])
        return m.rows.filter { m.get($0, ["lead"]) == key }.suffix(limit).map { (m.get($0, ["direction"]), m.get($0, ["text"]), m.get($0, ["at"])) }
    }

    // MARK: AI helpers

    /// Lead details from free text (a message, a voice note).
    func extract(_ text: String) async -> [String: String] {
        var out: [String: String] = [:]
        if let p = ZuffiPA.phone(in: text) { out["phone"] = p }
        if let b = ZuffiPA.budget(in: text.lowercased()) { out["budget"] = b }
        let prompt = """
        A client wrote to a \(businessWord). Pull out what they want. Return JSON:
        {"name":"","phone":"","interest":"what they want (\(labels.interest.lowercased())), short","area":"\(labels.area.lowercased())","budget":"as said","priority":"hot|warm|cold","notes":"anything else useful, short"}
        hot = ready to buy/book now or asks for a visit/price/availability; cold = just browsing. Empty string if not said.
        Message: \(text.prefix(4000))
        """
        if let r = await AIService.shared.oneShot(prompt), let j = AIService.jsonIn(r) as? [String: Any] {
            for k in ["name", "phone", "interest", "area", "budget", "priority", "notes"] {
                if let v = j[k] as? String, !v.trimmingCharacters(in: .whitespaces).isEmpty { out[k] = k == "priority" ? v.capitalized : v }
            }
        }
        return out
    }

    /// The reply only (for the dashboard's "write a reply for me").
    func draftReply(for l: CRMLead, incoming: String, first: Bool) async -> String {
        await smartReply(for: l, incoming: incoming, first: first).reply
    }

    /// One fast AI call: the reply (using business info, today's update, listings / diary and the conversation so far),
    /// whether a person must answer instead, and any lead details in the message.
    func smartReply(for l: CRMLead, incoming: String, first: Bool) async -> (reply: String, handoff: String?, details: [String: String]) {
        let biz = ZuffiBusiness.shared.businessName
        let firstName = l.name.split(separator: " ").first.map(String.init) ?? ""
        let fallback = !welcomeText.isEmpty ? welcomeText.replacingOccurrences(of: "{name}", with: firstName)
            : isEstate ? "Assalam o Alaikum\(firstName.isEmpty ? "" : " \(firstName)")! Thank you for contacting \(biz.isEmpty ? "us" : biz). Which area are you looking in, what size and what's your budget? I'll send you the best options."
            : "Hi\(firstName.isEmpty ? "" : " \(firstName)")! Thanks for messaging \(biz.isEmpty ? "us" : biz). How can we help you today?"
        var context = ""
        if isEstate, let s = ZuffiData.shared.sheets.first(where: { $0.name.lowercased().hasPrefix("listings") }) {
            context = "AVAILABLE LISTINGS:\n" + ZuffiData.shared.rows(s).prefix(30).map { $0.joined(separator: ", ") }.joined(separator: "\n")
        } else if kind.usesAppointments {
            let upcoming = ZuffiPA.load("Appointments", header: ZuffiPA.apptHeader).rows.filter { ($0.first ?? "") >= ZuffiBusiness.iso(Date()) }.prefix(30)
            if !upcoming.isEmpty { context = "TIMES ALREADY TAKEN:\n" + upcoming.map { $0.prefix(2).joined(separator: " ") }.joined(separator: "\n") }
        }
        let past = history(l.key).dropLast().suffix(8).map { ($0.dir == "in" ? "Client: " : "Business: ") + $0.text }.joined(separator: "\n")
        let system = """
        You are the WhatsApp assistant of \(biz.isEmpty ? "a small business" : biz) (a \(businessWord)). You write as the business ("we").
        Never give yourself a personal name, never say you are an AI, never invent facts. Reply with one JSON object only.
        """
        let prompt = """
        BUSINESS FACTS (the only facts you may use):
        \(businessInfo.isEmpty ? "(none written yet — just greet politely and ask how you can help)" : String(businessInfo.prefix(5000)))
        \(todaysUpdate.isEmpty ? "" : "TODAY'S UPDATE: \(todaysUpdate)")
        \(context)
        CLIENT: \(l.display.isEmpty ? "unknown" : l.display)
        \(past.isEmpty ? "" : "EARLIER IN THIS CHAT:\n\(past)")
        CLIENT'S NEW MESSAGE: \(incoming)

        Write "reply": 1-2 short, natural WhatsApp sentences in the same language and script the client used (English, Urdu or Roman Urdu). \(first ? "Greet them; ask only for what's missing." : "Don't greet again.")
        Set "needs_human" true ONLY if: they bargain or ask for a discount not in today's update, complain, ask for a person or a call, raise payment / refund / legal issues, or the answer isn't in the facts. Then make "reply" a short holding message ("Thanks! Someone from our team will reply shortly.") and put a 3-6 word reason in "why".
        Also fill "lead" with anything the client said: name, interest (\(labels.interest.lowercased())), area, budget, priority (Hot = ready now / asks price, visit or availability; Warm; Cold = just looking). Use "" when not said.
        JSON: {"reply":"","needs_human":false,"why":"","lead":{"name":"","interest":"","area":"","budget":"","priority":""}}
        """
        guard let j = await AIService.shared.fastJSON(prompt, system: system) else {
            return (fallback, first ? nil : "no AI is connected", [:])
        }
        var reply = (j["reply"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Never send JSON or code by mistake.
        if reply.hasPrefix("{") || reply.contains("\"reply\"") || reply.contains("needs_human") { reply = "" }
        let human = (j["needs_human"] as? Bool) ?? ((j["needs_human"] as? String)?.lowercased() == "true")
        let why = (j["why"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var details: [String: String] = [:]
        if let lead = j["lead"] as? [String: Any] {
            for k in ["name", "interest", "area", "budget", "priority"] {
                if let v = (lead[k] as? String)?.trimmingCharacters(in: .whitespaces), !v.isEmpty { details[k] = k == "priority" ? v.capitalized : v }
            }
        }
        if reply.isEmpty { return (fallback, first ? nil : "couldn't write a good reply", details) }
        return (reply, human ? (why.isEmpty ? "needs a person" : why) : nil, details)
    }

    /// Sends a WhatsApp message to a lead (via the server when connected, else WhatsApp on this Mac) and logs it.
    func send(_ key: String, _ text: String, auto: Bool = false) async -> String {
        guard let l = leads.first(where: { $0.key == key }) else { return "Lead not found." }
        let to = l.phone.isEmpty ? l.name : l.phone
        guard !to.isEmpty else { return "No number for this lead." }
        var result = ""
        if !serverURL.isEmpty, !l.phone.isEmpty, let r = await serverSend(phone: l.phone, text: text) { result = r }
        else {
            guard WhatsAppAgent.installed else { return "To send, install WhatsApp on this Mac (Business → Connect WhatsApp)." }
            result = await WhatsAppAgent.shared.sendScheduled(to: to, text: text)
        }
        drafts[key] = nil
        logMessage(key: key, display: l.display, dir: "out", text: text)
        edit(key) { b, i in
            b.set(i, ["last contact"], ZuffiBusiness.iso(Date()))
            b.set(i, ["last message"], "You: " + String(text.prefix(120)))
            if ZuffiCRM.stage(for: b.get(b.rows[i], ["status"])) == "New" { b.set(i, ["status"], "Contacted") }
            if b.get(b.rows[i], ["next follow"]) <= ZuffiBusiness.iso(Date()) { b.set(i, ["next follow"], ZuffiBusiness.iso(Date().addingTimeInterval(Double(self.quietDays) * 86400))) }
        }
        log(lead: l.display, staff: auto ? "Zuffi (autopilot)" : l.assigned, kind: "Message", detail: String(text.prefix(80)))
        return result
    }

    // MARK: Notifications (WhatsApp on this Mac or on your iPhone through iPhone Mirroring)

    func fromNotification(_ texts: [String], descriptions: [String]) {
        guard isOn(.watchWhatsApp) else { return }
        let all = (texts + descriptions).joined(separator: " ").lowercased()
        guard all.contains("whatsapp") else { return }
        let noise = #"(?i)^(whatsapp|whatsapp business|now|just now|\d+[mh] ago|yesterday|reply|mark as read|iphone)$"#
        let parts = texts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.range(of: noise, options: .regularExpression) == nil }
        guard parts.count >= 2 else { return }
        let sender = parts[0], body = parts[1]
        // Group chats ("Group name" + "Ali: hi") and summaries ("3 new messages") are skipped.
        if body.range(of: #"^[^:]{1,30}:\s"#, options: .regularExpression) != nil || sender.range(of: #"(?i)\d+ (new )?messages"#, options: .regularExpression) != nil { return }
        Task { await self.handleIncoming(name: sender, preview: body, source: "WhatsApp") }
    }

    // MARK: Things you tell Zuffi in chat

    /// "today's update: 20% off highlights", "add to business info: we open 10–8", "autopilot on"
    func handle(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()
        if let r = t.range(of: #"(?i)^(?:today'?s?|todays) (?:update|offers?|news|specials?|deals?|discounts?)\s*[:\-–]?\s*|^(?:update|offers?|news) for today\s*[:\-–]?\s*|^daily update\s*[:\-–]?\s*|^aaj ka update\s*[:\-–]?\s*"#, options: .regularExpression) {
            let body = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return todaysUpdate.isEmpty ? "No update for today yet. Tell me e.g. “today's update: 20% off all colour, new stock of 10 marla plots in DHA 9”." : "Today's update: \(todaysUpdate)" }
            todayUpdate = body
            return "Got it ✅ I'll tell clients today: “\(body)”." + (isOn(.autopilot) ? "" : " (Turn on Autopilot in Business → My business if you want me to reply by myself.)")
        }
        if l.range(of: #"^(clear|remove|delete) (today'?s|the) update$"#, options: .regularExpression) != nil { todayUpdate = ""; return "Cleared today's update." }
        if let r = t.range(of: #"(?i)^(?:add to (?:my )?business info|remember for (?:my )?clients|business info|for clients)\s*[:\-–]\s*"#, options: .regularExpression) {
            let body = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return nil }
            businessInfo = businessInfo.isEmpty ? body : businessInfo + "\n" + body
            return "Added to your business info ✅ I'll use it when I answer clients."
        }
        if l.range(of: #"^(turn |switch )?(on|start) (the )?autopilot$|^autopilot on$"#, options: .regularExpression) != nil {
            set(.autopilot, true)
            return businessInfo.isEmpty ? "Autopilot is on — but tell me about your business first (Business → My business), so I answer correctly." : "Autopilot is on ✅ I'll answer clients on WhatsApp and pass the tricky ones to you."
        }
        if l.range(of: #"^(turn |switch )?(off|stop) (the )?autopilot$|^autopilot off$"#, options: .regularExpression) != nil { set(.autopilot, false); return "Autopilot is off — I'll only write drafts for you." }
        return nil
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
        let base = serverURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !base.isEmpty, !serverKey.isEmpty, let url = URL(string: base + "/" + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 20)
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
            if let v = d["next_follow_up"] as? String, !v.isEmpty { f["next follow"] = v }
            let voiceNote = (d["voice_text"] as? String).flatMap { $0.isEmpty ? nil : "🎤 \"\($0)\"" } ?? ""
            let key = addLead(f, note: leads.contains { ZuffiPA.samePhone($0.phone, f["phone"] ?? "") && $0.notes.contains(voiceNote) } ? "" : voiceNote)
            // A team member changed it on their phone: their stage / follow-up / notes win.
            if (d["changed_by"] as? String) == "staff" {
                edit(key) { b, i in
                    for (k, col) in [("status", "status"), ("priority", "priority"), ("assigned", "assigned"), ("next_follow_up", "next follow"), ("notes", "notes"), ("last_contact", "last contact")] {
                        if let v = d[k] as? String, !v.isEmpty { b.set(i, [col], v) }
                    }
                }
            }
            if let draft = d["draft"] as? String, !draft.isEmpty { drafts[key] = draft } else if (d["changed_by"] as? String) == "staff" { drafts[key] = nil }
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
                                                        "owner_phone": ownerPhone, "owner_name": ownerName, "summary_hour": summaryHour, "quiet_days": quietDays,
                                                        "auto": Dictionary(uniqueKeysWithValues: Auto.allCases.map { ($0.rawValue, isOn($0)) }),
                                                        "welcome": welcomeText, "business": ZuffiBusiness.shared.businessName,
                                                        "business_info": businessInfo, "today_update": todaysUpdate, "today_date": ZuffiBusiness.iso(Date()),
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

extension String {
    fileprivate func ifBlank(_ s: String) -> String { isEmpty ? s : self }
}
