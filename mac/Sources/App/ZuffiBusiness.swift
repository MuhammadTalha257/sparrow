import Foundation
import AppKit
import SwiftUI

// =====================================================================
// MARK: - Ready-made packs for the people Zuffi is for first
//
// Estate agents (Pakistan): a Listings sheet and a Buyers sheet.
//   "which 3-bed in DHA under 2 crore?"  · "who to call today?"  · "who hasn't replied?"
//   Every morning Zuffi says who has gone quiet ("Ali hasn't replied in 3 days").
// Salons & small shops (UK): an Appointments sheet and a Clients sheet.
//   "today's appointments" · "send tomorrow's reminders" · "who should rebook?" · "this week's takings"
// The sheets live in Documents/Zuffi — edit them in Excel or Numbers (keep them as .csv),
// and Zuffi reads the new version by itself.
// =====================================================================

@MainActor
final class ZuffiBusiness: ObservableObject {
    static let shared = ZuffiBusiness()
    enum Pack: String { case realEstate, salon }

    @Published var pack: Pack? = Pack(rawValue: UserDefaults.standard.string(forKey: "zuffiPack") ?? "")
    @Published var businessName: String = UserDefaults.standard.string(forKey: "zuffiBusinessName") ?? ""
    private var pendingReminders: [(name: String, phone: String, text: String)] = []
    private var stamps: [String: Date] = [:]

    static var docs: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Zuffi", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Set up

    func install(_ p: Pack) async -> String {
        pack = p
        UserDefaults.standard.set(p.rawValue, forKey: "zuffiPack")
        var files: [(String, String)] = []
        let today = Self.iso(Date()), tomorrow = Self.iso(Date().addingTimeInterval(86400)), ago4 = Self.iso(Date().addingTimeInterval(-4 * 86400))
        switch p {
        case .realEstate:
            files = [
                ("Listings", "Property ID,Area,Type,Beds,Size,Price (PKR),Status,Owner,Owner phone,Notes\nP-101,DHA Phase 6,House,3,10 Marla,19500000,Available,Kamran,03001234567,Corner\nP-102,Bahria Town,Apartment,2,1100 sqft,9500000,Available,Sana,03211234567,Park facing\n"),
                ("Buyers", "Name,Phone,Budget (PKR),Wants,Area,Last contact,Next follow-up,Notes\nAli Raza,03331234567,20000000,3 bed house,DHA,\(ago4),\(today),Wants to visit on Sunday\nHina Khan,03451234567,10000000,2 bed apartment,Bahria Town,\(today),\(tomorrow),\n"),
            ]
            HomeAction.right = ["callToday", "quiet", "data", "whatsapp"]
        case .salon:
            files = [
                ("Appointments", "Date,Time,Client,Phone,Service,Staff,Price (£),Status\n\(today),10:00,Emma Clarke,07700900123,Cut & blow dry,Sophie,45,Booked\n\(tomorrow),14:30,Priya Patel,07700900456,Colour,Jade,85,Booked\n"),
                ("Clients", "Name,Phone,Last visit,Usual service,Notes\nEmma Clarke,07700900123,\(today),Cut & blow dry,\nOlivia Brown,07700900789,\(Self.iso(Date().addingTimeInterval(-50 * 86400))),Highlights,Prefers Saturdays\n"),
            ]
            HomeAction.right = ["appointments", "reminders", "rebook", "data"]
        }
        ZuffiHomeModel.shared.reloadButtons()
        var made: [String] = []
        for (name, csv) in files {
            let url = Self.docs.appendingPathComponent("\(name).csv")
            if !FileManager.default.fileExists(atPath: url.path) { try? csv.write(to: url, atomically: true, encoding: .utf8) }
            _ = await ZuffiData.shared.importSheet(url)
            stamps[url.path] = Self.mtime(url)
            made.append(name)
        }
        NSWorkspace.shared.open(Self.docs)
        return p == .realEstate
            ? "Done! I made your Listings and Buyers sheets in Documents → Zuffi (with two examples). Fill them in with Excel or Numbers and keep them as .csv — I'll read them by myself. Ask me “who to call today?”"
            : "Done! I made your Appointments and Clients sheets in Documents → Zuffi (with two examples). Fill them in with Excel or Numbers and keep them as .csv — I'll read them by myself. Ask me “today's appointments” or “send tomorrow's reminders”."
    }

    /// Every half minute: re-read sheets you've edited; at 10:00 tell you who has gone quiet / who to call.
    func tick() {
        for name in ["Listings", "Buyers", "Appointments", "Clients"] {
            let url = Self.docs.appendingPathComponent("\(name).csv")
            guard let m = Self.mtime(url) else { continue }
            if let old = stamps[url.path], old == m { continue }
            let first = stamps[url.path] == nil
            stamps[url.path] = m
            if !first || !ZuffiData.shared.sheets.contains(where: { $0.name == name }) { Task { _ = await ZuffiData.shared.importSheet(url) } }
        }
        let cal = Calendar.current, now = Date()
        let key = "zuffiMorningNudge"
        guard pack != nil, cal.component(.hour, from: now) == 10, UserDefaults.standard.string(forKey: key) != Self.iso(now) else { return }
        UserDefaults.standard.set(Self.iso(now), forKey: key)
        let msg = pack == .realEstate ? quietBuyers(short: true) : todays(offset: 0, short: true)
        if !msg.isEmpty {
            NotificationCenter.default.post(name: .petSay, object: msg)
            ZuffiHomeModel.shared.say(msg)
            SoundEngine.shared.play("chime")
        }
    }

    // MARK: Questions Zuffi answers by itself

    func handle(_ raw: String) -> String? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.contains("estate agent") && (t.contains("set me up") || t.contains("i am") || t.contains("i'm")) { Task { _ = await install(.realEstate) }; return "Setting you up as an estate agent…" }
        if t.contains("salon") && (t.contains("set me up") || t.contains("i run") || t.contains("i have")) { Task { _ = await install(.salon) }; return "Setting up your salon…" }
        if !pendingReminders.isEmpty, t.range(of: #"^(yes|send( them| it)?|ok|go ahead|haan|bhej do)\b"#, options: .regularExpression) != nil {
            let list = pendingReminders; pendingReminders = []
            Task {
                for r in list {
                    _ = await WhatsAppAgent.shared.sendScheduled(to: r.phone, text: r.text)
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                }
                NotificationCenter.default.post(name: .petSay, object: "Sent \(list.count) reminder\(list.count == 1 ? "" : "s") ✅")
            }
            return "Sending \(list.count) reminder\(list.count == 1 ? "" : "s") on WhatsApp…"
        }
        if t.range(of: #"(who|whom) (to|should i) (call|follow ?up)|call (list )?today|follow ?ups? (for )?today|buyers to call"#, options: .regularExpression) != nil { return callToday() }
        if t.range(of: #"(quiet|gone quiet|not replied|hasn'?t replied|haven'?t replied|no reply)"#, options: .regularExpression) != nil { return quietBuyers(short: false) }
        if t.range(of: #"(today'?s|todays) (appointments|clients|bookings)|appointments today|who('s| is) (coming|in) today"#, options: .regularExpression) != nil { return todays(offset: 0, short: false) }
        if t.range(of: #"(tomorrow'?s|tomorrows) (appointments|clients|bookings)|appointments tomorrow"#, options: .regularExpression) != nil { return todays(offset: 1, short: false) }
        if t.range(of: #"(send|text|message).*(reminders?).*(tomorrow)|tomorrow'?s reminders"#, options: .regularExpression) != nil { return prepareReminders() }
        if t.range(of: #"(who should|clients? to|due to) (re)?book|rebook"#, options: .regularExpression) != nil { return rebook() }
        return nil
    }

    // MARK: Estate agents

    func callToday() -> String {
        guard let (h, rows) = table("Buyers") else { return "Set yourself up first: say “set me up as an estate agent” (or add a Buyers sheet)." }
        let name = Self.col(h, ["name", "buyer", "client"]), phone = Self.col(h, ["phone", "mobile", "number", "contact no"])
        let next = Self.col(h, ["next", "follow"]), last = Self.col(h, ["last contact", "last call", "last"])
        let today = Calendar.current.startOfDay(for: Date())
        var out: [String] = []
        for r in rows {
            let n = Self.cell(r, name)
            guard !n.isEmpty else { continue }
            let due = Self.date(Self.cell(r, next)).map { $0 <= today } ?? false
            let quiet = Self.date(Self.cell(r, last)).map { today.timeIntervalSince($0) >= 3 * 86400 } ?? false
            if due || quiet { out.append("\(n) \(Self.cell(r, phone))".trimmingCharacters(in: .whitespaces) + (due ? "" : " (quiet)")) }
        }
        return out.isEmpty ? "Nobody to call today — you're on top of it! 🎉" : "Call today (\(out.count)): " + out.prefix(12).joined(separator: " · ")
    }

    func quietBuyers(short: Bool) -> String {
        guard let (h, rows) = table("Buyers") else { return short ? "" : "Say “set me up as an estate agent” first." }
        let name = Self.col(h, ["name", "buyer", "client"]), last = Self.col(h, ["last contact", "last call", "last"])
        let today = Calendar.current.startOfDay(for: Date())
        let quiet: [(String, Int)] = rows.compactMap { r in
            guard let d = Self.date(Self.cell(r, last)) else { return nil }
            let days = Int(today.timeIntervalSince(Calendar.current.startOfDay(for: d)) / 86400)
            return days >= 3 ? (Self.cell(r, name), days) : nil
        }.sorted { $0.1 > $1.1 }
        if quiet.isEmpty { return short ? "" : "Everyone has been in touch in the last 3 days. 👍" }
        let list = quiet.prefix(6).map { "\($0.0) hasn't replied in \($0.1) days" }
        return (short ? "Good morning! " : "") + list.joined(separator: ". ") + "."
    }

    // MARK: Salons & shops

    func todays(offset: Int, short: Bool) -> String {
        guard let (h, rows) = table("Appointments") else { return short ? "" : "Say “set me up as a salon” first (or add an Appointments sheet)." }
        let date = Self.col(h, ["date", "day"]), time = Self.col(h, ["time"]), client = Self.col(h, ["client", "name", "customer"]), service = Self.col(h, ["service", "treatment"])
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(Double(offset) * 86400))
        let list = rows.filter { Self.date(Self.cell($0, date)).map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
            .sorted { Self.cell($0, time) < Self.cell($1, time) }
        let when = offset == 0 ? "today" : "tomorrow"
        if list.isEmpty { return short ? "" : "No appointments \(when)." }
        let lines = list.map { "\(Self.cell($0, time)) \(Self.cell($0, client))" + (Self.cell($0, service).isEmpty ? "" : " – \(Self.cell($0, service))") }
        return "\(list.count) appointment\(list.count == 1 ? "" : "s") \(when): " + lines.joined(separator: " · ")
    }

    func prepareReminders() -> String {
        guard let (h, rows) = table("Appointments") else { return "Say “set me up as a salon” first." }
        let date = Self.col(h, ["date", "day"]), time = Self.col(h, ["time"]), client = Self.col(h, ["client", "name", "customer"])
        let phone = Self.col(h, ["phone", "mobile", "number"]), service = Self.col(h, ["service", "treatment"])
        let day = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        let biz = businessName.isEmpty ? "us" : businessName
        pendingReminders = rows.compactMap { r in
            guard Self.date(Self.cell(r, date)).map({ Calendar.current.isDate($0, inSameDayAs: day) }) ?? false,
                  !Self.cell(r, phone).isEmpty else { return nil }
            let first = Self.cell(r, client).split(separator: " ").first.map(String.init) ?? ""
            let svc = Self.cell(r, service)
            return (Self.cell(r, client), Self.cell(r, phone),
                    "Hi \(first), just a reminder of your \(svc.isEmpty ? "appointment" : svc + " appointment") with \(biz) tomorrow at \(Self.cell(r, time)). Reply if you need to change it. See you soon!")
        }
        if pendingReminders.isEmpty { return "No appointments with a phone number tomorrow." }
        return "I've written \(pendingReminders.count) WhatsApp reminder\(pendingReminders.count == 1 ? "" : "s") for tomorrow (\(pendingReminders.map(\.name).joined(separator: ", "))). Say “send them” to send."
    }

    func rebook() -> String {
        guard let (h, rows) = table("Clients") else { return "Say “set me up as a salon” first (or add a Clients sheet)." }
        let name = Self.col(h, ["name", "client"]), last = Self.col(h, ["last visit", "last"]), phone = Self.col(h, ["phone", "mobile"])
        let today = Date()
        let due = rows.compactMap { r -> String? in
            guard let d = Self.date(Self.cell(r, last)), today.timeIntervalSince(d) >= 42 * 86400 else { return nil }
            return "\(Self.cell(r, name)) (\(Int(today.timeIntervalSince(d) / 86400 / 7)) weeks) \(Self.cell(r, phone))"
        }
        return due.isEmpty ? "Everyone has been in within the last 6 weeks. 💇" : "Due to rebook (\(due.count)): " + due.prefix(10).joined(separator: " · ")
    }

    // MARK: helpers

    private func table(_ name: String) -> ([String], [[String]])? {
        guard let s = ZuffiData.shared.sheets.first(where: { $0.name.lowercased() == name.lowercased() || $0.name.lowercased().hasPrefix(name.lowercased()) }) else { return nil }
        let r = ZuffiData.shared.rows(s)
        guard let h = r.first else { return nil }
        return (h.map { $0.lowercased() }, Array(r.dropFirst()))
    }
    static func col(_ h: [String], _ keys: [String]) -> Int? {
        for k in keys { if let i = h.firstIndex(where: { $0.contains(k) }) { return i } }
        return nil
    }
    static func cell(_ r: [String], _ i: Int?) -> String { guard let i, i < r.count else { return "" }; return r[i].trimmingCharacters(in: .whitespaces) }
    static func iso(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }
    static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB")
        for fmt in ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "d MMM yyyy", "d MMMM yyyy", "MMM d, yyyy", "dd.MM.yyyy", "yyyy/MM/dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: t) { return d }
        }
        if let serial = Double(t), serial > 30000, serial < 80000 {          // an Excel date number
            return Date(timeIntervalSince1970: (serial - 25569) * 86400)
        }
        return nil
    }
    static func mtime(_ u: URL) -> Date? { (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date }
}

// MARK: - Panel bit: pick your business

struct BusinessPackCard: View {
    @ObservedObject private var biz = ZuffiBusiness.shared
    @State private var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR BUSINESS").font(.system(size: 9, weight: .heavy)).kerning(1).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 6) {
                packButton("house.fill", "Estate agent", .realEstate)
                packButton("scissors", "Salon / shop", .salon)
            }
            TextField("Business name (for messages)", text: Binding(get: { biz.businessName }, set: { biz.businessName = $0; UserDefaults.standard.set($0, forKey: "zuffiBusinessName") }))
                .textFieldStyle(.roundedBorder).font(.system(size: 11))
            if biz.pack == .realEstate {
                quick(["Who to call today?", "Who hasn't replied?", "Which 3-bed in DHA under 2 crore?"])
            } else if biz.pack == .salon {
                quick(["Today's appointments", "Send tomorrow's reminders", "Who should rebook?", "This week's takings"])
            }
            if !note.isEmpty { Text(note).font(.system(size: 10.5)).foregroundColor(Color(hex: "#7CE0A8")).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func packButton(_ icon: String, _ title: String, _ p: ZuffiBusiness.Pack) -> some View {
        Button { Task { note = await biz.install(p) } } label: {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(biz.pack == p ? Color(hex: "#1A1008") : .white)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(Capsule().fill(biz.pack == p ? AnyShapeStyle(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.1))))
        }.buttonStyle(.plain)
    }

    private func quick(_ qs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(qs, id: \.self) { q in
                Button {
                    let s = AppState.shared
                    s.chatHistory.append(ChatMessage(role: .user, content: q))
                    s.stateOverride = .thinking
                    Task { await AIService.shared.chat(query: q, context: nil, state: s) }
                    ZuffiChat.shared.open()
                } label: {
                    Text("“\(q)”").font(.system(size: 10.5)).foregroundColor(Color(hex: "#F7C948"))
                }.buttonStyle(.plain)
            }
        }
    }
}
