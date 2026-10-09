import Foundation
import AppKit
import SwiftUI

// =====================================================================
// MARK: - Zuffi as a personal PA
//
// Everything lives in plain sheets in Documents/Zuffi (open them in Excel or Numbers):
//   Leads.csv         estate agents — every enquiry from Facebook / Instagram / Zameen / WhatsApp / walk-ins
//   Appointments.csv  salons & shops — bookings
//   Clients.csv       salons & shops — your clients
//   <anything>.csv    whatever you ask Zuffi to "save"
//
// Say it like you'd tell a PA:
//   "new lead Ali Raza 0333 1234567 from Facebook, wants 10 marla in DHA, budget 2 crore"
//   "mark Ali as hot" · "called Ali" · "follow up with Ali on Friday" · "note for Ali: wants corner plot"
//   "my leads" · "leads from Facebook" · "hot leads" · "message new leads"  (asks before sending)
//   "book Emma tomorrow at 3pm for a cut" · "move Emma to Friday 2pm" · "cancel Emma's appointment"
//   "<any list or details> … save it"  → a neat sheet (or note) in Documents/Zuffi
// Lead exports you download (Facebook / Instagram lead ads, Zameen, Google Forms) are picked up
// from Downloads by themselves and added to Leads — no copy-paste.
// =====================================================================

@MainActor
final class ZuffiPA {
    static let shared = ZuffiPA()

    private var pendingSends: [(name: String, phone: String, text: String)] = []
    private var pendingWhat = ""

    static let leadHeader = ["Name", "Phone", "Source", "Interest", "Area", "Budget", "Status", "Priority", "Assigned to", "Added", "Last contact", "Next follow-up", "Last message", "Last message at", "Notes"]
    static let apptHeader = ["Date", "Time", "Client", "Phone", "Service", "Staff", "Price", "Status"]
    static let clientHeader = ["Name", "Phone", "Last visit", "Usual service", "Notes"]

    // MARK: Sheets on disk

    struct Book {
        var header: [String]
        var rows: [[String]]
        func i(_ keys: [String]) -> Int? {
            let h = header.map { $0.lowercased() }
            for k in keys { if let x = h.firstIndex(where: { $0 == k }) { return x } }
            for k in keys { if let x = h.firstIndex(where: { $0.contains(k) }) { return x } }
            return nil
        }
        func get(_ r: [String], _ keys: [String]) -> String {
            guard let x = i(keys), x < r.count else { return "" }
            return r[x].trimmingCharacters(in: .whitespaces)
        }
        mutating func set(_ row: Int, _ keys: [String], _ v: String) {
            guard let x = i(keys) else { return }
            while rows[row].count <= x { rows[row].append("") }
            rows[row][x] = v
        }
    }

    static func url(_ name: String) -> URL { ZuffiBusiness.docs.appendingPathComponent("\(name).csv") }

    static func load(_ name: String, header: [String]) -> Book {
        guard let t = try? String(contentsOf: url(name), encoding: .utf8) else { return Book(header: header, rows: []) }
        let all = ZuffiData.parseCSV(t, sep: ",").filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let h = all.first else { return Book(header: header, rows: []) }
        var b = Book(header: h, rows: Array(all.dropFirst()))
        // Add any column Zuffi needs that the sheet doesn't have yet.
        for c in header where b.i([c.lowercased()]) == nil { b.header.append(c) }
        return b
    }

    static func save(_ name: String, _ b: Book) {
        let lines = [b.header] + b.rows.map { r in (0..<b.header.count).map { $0 < r.count ? r[$0] : "" } }
        let csv = lines.map { $0.map(ZuffiData.csvCell).joined(separator: ",") }.joined(separator: "\n") + "\n"
        try? csv.write(to: url(name), atomically: true, encoding: .utf8)
        Task { _ = await ZuffiData.shared.importSheet(url(name)) }
    }

    // MARK: Small parsers

    static func phone(in s: String) -> String? {
        guard let r = s.range(of: #"(\+?\d[\d\s\-]{8,15}\d)"#, options: .regularExpression) else { return nil }
        let p = s[r].filter { $0.isNumber || $0 == "+" }
        return p.count >= 10 ? String(p) : nil
    }
    static func samePhone(_ a: String, _ b: String) -> Bool {
        let x = a.filter(\.isNumber), y = b.filter(\.isNumber)
        guard x.count >= 9, y.count >= 9 else { return false }
        return x.suffix(9) == y.suffix(9)
    }
    static func when(_ s: String) -> Date? {
        guard let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        return d.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))?.date
    }
    static func hasTime(_ s: String) -> Bool {
        s.range(of: #"\b\d{1,2}([:.]\d{2})?\s*(am|pm)\b|\b\d{1,2}[:.]\d{2}\b|\bnoon\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
    static func hm(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }
    static func source(in t: String) -> String? {
        let map: [(String, String)] = [("facebook", "Facebook"), ("fb ", "Facebook"), ("instagram", "Instagram"), ("insta", "Instagram"), ("zameen", "Zameen.com"),
                                       ("graana", "Graana"), ("olx", "OLX"), ("tiktok", "TikTok"), ("google", "Google"), ("youtube", "YouTube"),
                                       ("whatsapp", "WhatsApp"), ("referral", "Referral"), ("referred", "Referral"), ("walk-in", "Walk-in"), ("walk in", "Walk-in"),
                                       ("website", "Website"), ("call", "Phone call")]
        return map.first { t.contains($0.0) }?.1
    }
    static func budget(in t: String) -> String? {
        guard let r = t.range(of: #"(\d+(\.\d+)?)\s*(crore|cr|lakh|lac|lakhs|million|m\b|k\b)"#, options: .regularExpression) else { return nil }
        return String(t[r])
    }
    private func first(_ name: String) -> String { name.split(separator: " ").first.map(String.init) ?? name }
    private var biz: String { ZuffiBusiness.shared.businessName.isEmpty ? "" : ZuffiBusiness.shared.businessName }

    /// The row whose name best matches the words ("ali", "ali raza").
    static func find(_ who: String, in b: Book, nameKeys: [String]) -> Int? {
        let w = who.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,'’s")).replacingOccurrences(of: #"'s$|’s$"#, with: "", options: .regularExpression)
        guard !w.isEmpty else { return nil }
        let names = b.rows.map { b.get($0, nameKeys).lowercased() }
        if let i = names.lastIndex(where: { $0 == w }) { return i }
        if let i = names.lastIndex(where: { $0.hasPrefix(w) || $0.split(separator: " ").contains { $0 == w } }) { return i }
        if let p = phone(in: who), let i = b.rows.lastIndex(where: { samePhone(b.get($0, ["phone", "mobile", "number"]), p) }) { return i }
        return names.lastIndex { $0.contains(w) }
    }

    // MARK: Entry

    func handle(_ raw: String) async -> String? {
        let t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        // Confirming messages Zuffi drafted.
        if !pendingSends.isEmpty {
            if t.range(of: #"^(yes|yep|ok|okay|send( them| it| all)?|go ahead|haan|han|ji|bhej do|confirm)\b"#, options: .regularExpression) != nil { return sendPending() }
            if t.range(of: #"^(no|cancel|don'?t|stop|nahi|mat)\b"#, options: .regularExpression) != nil { pendingSends = []; return "Okay, I won't send them." }
        }

        if let r = await saveData(raw, t) { return r }
        if let r = await leads(raw, t) { return r }
        if let r = await appointments(raw, t) { return r }
        if t.range(of: #"^(connect|link|import) (my )?(facebook|instagram|meta|zameen|social media|ads?|lead ?ads?|leads)\b|^how (do i|to) (connect|link|get) (my )?(leads|ads|facebook|instagram|social)"#, options: .regularExpression) != nil {
            return connectGuide()
        }
        return nil
    }

    // MARK: "save it" → a file

    private func saveData(_ raw: String, _ t: String) async -> String? {
        let cmd = #"(?:^|\s|[.,!])(?:please\s+)?(?:save|store|keep|record|note down|write down|put)\s+(?:it|this|that|these|those|them|all (?:of )?(?:this|that|these)|the (?:data|details|list|info)|this (?:data|list|info|information|detail|details)|my (?:data|details|list))\s*(?:(?:to|in|into|as)\s+(?:an?\s+)?(?:new\s+)?(?:file|sheet|excel|spreadsheet|csv|note|list|record)s?)?(?:\s+(?:as|called|named)\s+([\w \-]{2,40}))?\s*[.!]*$"#
        let start = #"^(?:please\s+)?(?:save|store|keep|record|note down|write down|make (?:a )?(?:file|sheet))(?:\s+(?:this|these|the following|it|my))?(?:\s+(?:data|details|list|info|information|contacts|numbers|leads|clients))?(?:\s+(?:as|called|named|in)\s+([\w \-]{2,40}?))?\s*[:\n]\s*([\s\S]+)$"#
        var data = "", nameHint = ""
        if let re = try? NSRegularExpression(pattern: start, options: [.caseInsensitive]),
           let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            if let r = Range(m.range(at: 1), in: raw) { nameHint = String(raw[r]) }
            if let r = Range(m.range(at: 2), in: raw) { data = String(raw[r]) }
        } else if let re = try? NSRegularExpression(pattern: cmd, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)), let whole = Range(m.range, in: raw) {
            if let r = Range(m.range(at: 1), in: raw) { nameHint = String(raw[r]) }
            data = String(raw[..<whole.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if data.count < 15 {
                // "save it" on its own: the thing before it — your last message, or Zuffi's last answer.
                var h = AppState.shared.chatHistory
                if let l = h.last, l.role == .user, l.content.trimmingCharacters(in: .whitespacesAndNewlines) == raw.trimmingCharacters(in: .whitespacesAndNewlines) { h.removeLast() }
                let prevUser = h.last(where: { $0.role == .user })?.content ?? ""
                let prevBot = h.last(where: { $0.role == .assistant })?.content ?? ""
                let wantsAnswer = t.range(of: #"\b(answer|reply|response|your list|that list|that table)\b"#, options: .regularExpression) != nil
                data = wantsAnswer || prevUser.count < 15 ? (prevBot.isEmpty ? prevUser : prevBot) : prevUser
            }
        } else { return nil }
        data = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard data.count >= 3 else { return "Tell me what to save — paste the details and say “save it”." }
        return await store(data, nameHint: nameHint.trimmingCharacters(in: .whitespaces))
    }

    /// Turns any text into a tidy sheet (rows and columns) — or a note when it isn't a list.
    func store(_ data: String, nameHint: String) async -> String {
        var name = nameHint, header: [String] = [], rows: [[String]] = [], note = ""
        let prompt = """
        Turn the text below into data to save for a small-business owner.
        If it is a list of people, items, numbers, leads, clients, sales, appointments or anything with repeated fields, return
        {"kind":"table","name":"<short file name, 1-3 words, Title Case>","columns":[...],"rows":[[...],...]}
        Use clear column names (e.g. Name, Phone, Area, Budget, Date, Amount). Keep every value; dates as yyyy-MM-dd.
        Otherwise return {"kind":"note","name":"<short title>","text":"<the text, tidied>"}.
        \(nameHint.isEmpty ? "" : "Call it \"\(nameHint)\".")
        Text:
        \(data.prefix(12000))
        """
        if let reply = await AIService.shared.oneShot(prompt), let j = AIService.jsonIn(reply) as? [String: Any] {
            if name.isEmpty { name = (j["name"] as? String) ?? "" }
            if (j["kind"] as? String) == "table", let cols = j["columns"] as? [Any], let rs = j["rows"] as? [[Any]] {
                header = cols.map { "\($0)" }
                rows = rs.map { $0.map { v in v is NSNull ? "" : "\(v)" } }
            } else { note = (j["text"] as? String) ?? data }
        } else {
            // No AI: split lines on tabs / commas / " - " if they look like a table.
            let lines = data.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let sep: String? = lines.allSatisfy { $0.contains("\t") } ? "\t" : lines.count > 1 && lines.allSatisfy { $0.contains(",") } ? "," : nil
            if let sep {
                let split = lines.map { $0.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) } }
                let firstHasDigits = split[0].contains { $0.contains(where: \.isNumber) }
                header = firstHasDigits ? (1...split[0].count).map { "Column \($0)" } : split[0]
                rows = firstHasDigits ? split : Array(split.dropFirst())
            } else if lines.count > 1, lines.allSatisfy({ Self.phone(in: $0) != nil }) {
                header = ["Name", "Phone", "Details"]
                rows = lines.map { l in
                    let p = Self.phone(in: l) ?? ""
                    let rest = l.replacingOccurrences(of: #"(\+?\d[\d\s\-]{8,15}\d)"#, with: "|", options: .regularExpression).components(separatedBy: "|")
                    return [rest.first?.trimmingCharacters(in: CharacterSet(charactersIn: " ,-:")) ?? "", p, rest.dropFirst().joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,-:"))]
                }
            } else { note = data }
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            let f = DateFormatter(); f.dateFormat = "d MMM HH.mm"
            name = (note.isEmpty ? "Saved data " : "Note ") + f.string(from: Date())
        }
        name = ZuffiData.safe(name.prefix(1).uppercased() + name.dropFirst())

        if !note.isEmpty {
            let dir = ZuffiBusiness.docs.appendingPathComponent("Notes", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let u = dir.appendingPathComponent("\(name).txt")
            let old = (try? String(contentsOf: u, encoding: .utf8)).map { $0 + "\n\n" } ?? ""
            try? (old + note).write(to: u, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([u])
            return "Saved ✅ as a note: Documents → Zuffi → Notes → \(name).txt. I'll remember it — just ask."
        }
        guard !header.isEmpty, !rows.isEmpty else { return "I couldn't find anything to save in that." }
        // Same file already there? Add the new rows to it (skip exact duplicates).
        var b = Self.load(name, header: header)
        if FileManager.default.fileExists(atPath: Self.url(name).path) {
            for r in rows {
                let mapped = b.header.map { col -> String in
                    guard let k = header.firstIndex(where: { $0.lowercased() == col.lowercased() }), k < r.count else { return "" }
                    return r[k]
                }
                if !b.rows.contains(mapped) { b.rows.append(mapped) }
            }
        } else { b = Book(header: header, rows: rows) }
        Self.save(name, b)
        NSWorkspace.shared.activateFileViewerSelecting([Self.url(name)])
        return "Saved ✅ \(rows.count) row\(rows.count == 1 ? "" : "s") to Documents → Zuffi → \(name).csv (\(header.prefix(5).joined(separator: ", "))\(header.count > 5 ? "…" : "")). Open it in Excel any time, or ask me about it."
    }

    // MARK: Leads (estate agents and anyone who sells)

    private func leads(_ raw: String, _ t: String) async -> String? {
        // Add: "new lead …", "add lead …", "lead: …", "add Ali 0333… as a lead"
        if t.range(of: #"^(?:new|add|save|log)(?: a)?(?: new)? (?:lead|enquiry|inquiry|buyer|client lead)\b|^lead\s*[:\-]|\bas a (?:new )?lead$"#, options: .regularExpression) != nil {
            return await addLead(raw)
        }
        // Lists / summary
        if t.range(of: #"^(?:show |list |open )?(?:my |all )?(?:leads|pipeline|lead (?:summary|report))(?: summary| report| today| this week)?\??$|^how many leads|^leads? (?:summary|report|status)"#, options: .regularExpression) != nil {
            return pipeline()
        }
        if let m = t.range(of: #"^(?:show |list |my )?(?:leads|enquiries|buyers) (?:from|via|on) (.+?)\??$"#, options: .regularExpression) {
            let src = String(t[m]).replacingOccurrences(of: #"^(?:show |list |my )?(?:leads|enquiries|buyers) (?:from|via|on) "#, with: "", options: .regularExpression)
            let want = src.trimmingCharacters(in: CharacterSet(charactersIn: " ?"))
            return list({ b, r in b.get(r, ["source"]).lowercased().contains(want) }, title: "Leads from \(want.capitalized)")
        }
        if let m = t.range(of: #"^(?:show |list |my )?(new|hot|warm|cold|closed|lost|visited|negotiating) leads\??$"#, options: .regularExpression) {
            let st = String(t[m]).components(separatedBy: " ").first { ["new", "hot", "warm", "cold", "closed", "lost", "visited", "negotiating"].contains($0) } ?? "new"
            return list({ b, r in (b.get(r, ["status"]) + " " + b.get(r, ["priority"])).lowercased().contains(st) }, title: "\(st.capitalized) leads")
        }
        if t.range(of: #"^(?:which |what )?(?:leads|follow[- ]?ups?) (?:are )?(?:due|for) today|^today'?s follow[- ]?ups?|^follow[- ]?ups?(?: due)? today|^who (?:do i|should i|to) follow[- ]?up"#, options: .regularExpression) != nil {
            let today = Calendar.current.startOfDay(for: Date())
            return list({ b, r in ZuffiBusiness.date(b.get(r, ["next follow"])).map { $0 <= today } ?? false }, title: "Follow up today")
        }
        // Message leads: "message new leads", "whatsapp hot leads saying …"
        if let re = try? NSRegularExpression(pattern: #"^(?:message|whatsapp|text|send (?:a )?message to|msg) (?:all |my )?(new|hot|warm|today'?s|facebook|instagram|zameen|all)? ?leads?(?: (?:from )?(facebook|instagram|zameen|tiktok|olx))?(?: (?:saying|that|:)\s*(.+))?$"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
            func g(_ i: Int) -> String { Range(m.range(at: i), in: raw).map { String(raw[$0]) } ?? "" }
            return draftLeadMessages(filter: (g(1) + " " + g(2)).lowercased().trimmingCharacters(in: .whitespaces), custom: g(3))
        }
        // Update a lead (only when the name matches someone in Leads).
        var b = Self.load("Leads", header: Self.leadHeader)
        guard !b.rows.isEmpty else { return nil }
        let patterns: [(String, (inout Book, Int, String) -> String)] = [
            (#"^(?:mark|set|move|update|put) (.+?) (?:as|to|status(?: to)?|in) (new|hot|warm|cold|visited|site visit done|negotiating|token paid|closed|deal done|sold|lost|not interested)$"#, { b, i, v in
                if ["hot", "warm", "cold"].contains(v) { b.set(i, ["priority"], v.capitalized) } else { b.set(i, ["status"], ZuffiCRM.stage(for: v)) }
                b.set(i, ["last contact"], ZuffiBusiness.iso(Date()))
                ZuffiCRM.shared.log(lead: b.get(b.rows[i], ["name"]), staff: b.get(b.rows[i], ["assigned"]), kind: "Updated", detail: v.capitalized)
                return "Updated \(b.get(b.rows[i], ["name"])) → \(v.capitalized)." }),
            (#"^(?:i )?(?:called|spoke to|spoke with|talked to|met|messaged|whatsapped|texted|showed (?:the )?(?:plot|house|property) to) (.+?)(?: today)?$"#, { b, i, _ in
                b.set(i, ["last contact"], ZuffiBusiness.iso(Date())); return "Noted — you were in touch with \(b.get(b.rows[i], ["name"])) today." }),
        ]
        for (p, apply) in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
                  let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let r1 = Range(m.range(at: 1), in: t), let i = Self.find(String(t[r1]), in: b, nameKeys: ["name"]) else { continue }
            let v = m.numberOfRanges > 2 ? Range(m.range(at: 2), in: t).map { String(t[$0]) } ?? "" : ""
            let reply = apply(&b, i, v)
            Self.save("Leads", b)
            return reply
        }
        // "follow up with Ali on Friday at 11", "call Ali back tomorrow"
        if let re = try? NSRegularExpression(pattern: #"^(?:follow[- ]?up with|follow[- ]?up|call back|remind me to call|call) (.+?) (?:back )?((?:on |at |by |in |next |tomorrow|today|this |after ).+)$"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let r1 = Range(m.range(at: 1), in: t), let r2 = Range(m.range(at: 2), in: t),
           let i = Self.find(String(t[r1]), in: b, nameKeys: ["name"]), let d = Self.when(String(t[r2])) {
            let who = b.get(b.rows[i], ["name"])
            b.set(i, ["next follow"], ZuffiBusiness.iso(d))
            Self.save("Leads", b)
            let time = Self.hasTime(String(t[r2])) ? Self.hm(d) : "10:00"
            let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
            _ = await AgentRouter.shared.handle("remind me to call \(who) \(b.get(b.rows[i], ["phone"])) at \(time) on \(f.string(from: d))")
            return "Okay — follow-up with \(who) on \(f.string(from: d)) at \(time). It's in Leads and I'll remind you."
        }
        // "note for Ali: wants a corner plot"
        if let re = try? NSRegularExpression(pattern: #"^(?:add )?note (?:for|on|about) (.+?)\s*[:,\-]\s*(.+)$"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let r1 = Range(m.range(at: 1), in: raw), let r2 = Range(m.range(at: 2), in: raw),
           let i = Self.find(String(raw[r1]), in: b, nameKeys: ["name"]) {
            let old = b.get(b.rows[i], ["notes"])
            b.set(i, ["notes"], (old.isEmpty ? "" : old + " | ") + String(raw[r2]))
            Self.save("Leads", b)
            return "Added to \(b.get(b.rows[i], ["name"]))'s notes."
        }
        return nil
    }

    func addLead(_ raw: String) async -> String {
        let t = raw.lowercased()
        var name = "", phone = Self.phone(in: raw) ?? "", src = Self.source(in: t) ?? "", interest = "", area = "", budget = Self.budget(in: t) ?? "", notes = "", next = ""
        let prompt = """
        Extract one sales lead from this message for a Pakistani/UK small business. Return JSON:
        {"name":"","phone":"","source":"Facebook|Instagram|Zameen.com|WhatsApp|Referral|Walk-in|TikTok|OLX|Website|Phone call|…","interest":"what they want e.g. 10 marla house","area":"","budget":"as said e.g. 2 crore","next_follow_up":"yyyy-MM-dd or empty","notes":""}
        Today is \(ZuffiBusiness.iso(Date())). Message: \(raw)
        """
        if let reply = await AIService.shared.oneShot(prompt), let j = AIService.jsonIn(reply) as? [String: Any] {
            func s(_ k: String) -> String { ((j[k] as? String) ?? "").trimmingCharacters(in: .whitespaces) }
            name = s("name"); if !s("phone").isEmpty { phone = s("phone") }; if !s("source").isEmpty { src = s("source") }
            interest = s("interest"); area = s("area"); if !s("budget").isEmpty { budget = s("budget") }; notes = s("notes"); next = s("next_follow_up")
        } else {
            // Without an AI: the words between "lead" and the number are the name; the rest goes in notes.
            var rest = raw.replacingOccurrences(of: #"^(?i)(?:new|add|save|log)(?: a)?(?: new)? (?:lead|enquiry|inquiry|buyer|client lead)\s*[:\-,]?\s*|^(?i)lead\s*[:\-]\s*"#, with: "", options: .regularExpression)
            if let p = rest.range(of: #"(\+?\d[\d\s\-]{8,15}\d)"#, options: .regularExpression) {
                name = String(rest[..<p.lowerBound]); rest = String(rest[p.upperBound...])
            } else if let c = rest.firstIndex(where: { $0 == "," }) { name = String(rest[..<c]); rest = String(rest[rest.index(after: c)...]) }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,-:")).replacingOccurrences(of: #"(?i)\b(name|is|called)\b"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            notes = rest.trimmingCharacters(in: CharacterSet(charactersIn: " ,-:."))
            for a in ["dha", "bahria", "gulberg", "johar town", "model town", "clifton", "f-7", "f-8", "e-11", "g-11", "b-17", "askari", "wapda town", "valencia", "lake city"] where t.contains(a) { area = a.uppercased() == "DHA" ? "DHA" : a.capitalized; break }
        }
        guard !name.isEmpty || !phone.isEmpty else { return "Who's the lead? Say e.g. “new lead Ali Raza 0333 1234567 from Facebook, wants 10 marla in DHA”." }
        var b = Self.load("Leads", header: Self.leadHeader)
        if !phone.isEmpty, let dup = b.rows.firstIndex(where: { Self.samePhone(b.get($0, ["phone"]), phone) }) {
            if !notes.isEmpty { b.set(dup, ["notes"], b.get(b.rows[dup], ["notes"]) + " | " + notes) }
            b.set(dup, ["last contact"], ZuffiBusiness.iso(Date()))
            Self.save("Leads", b)
            return "\(b.get(b.rows[dup], ["name"])) is already in your leads — I updated the notes."
        }
        let today = ZuffiBusiness.iso(Date())
        var row = Array(repeating: "", count: b.header.count)
        func put(_ k: String, _ v: String) { if let x = b.i([k]) { row[x] = v } }
        put("name", name.capitalized); put("phone", phone); put("source", src); put("interest", interest); put("area", area)
        put("budget", budget); put("status", "New"); put("added", today); put("last contact", today); put("assigned", ZuffiCRM.shared.nextAssignee())
        put("next follow", next.isEmpty ? ZuffiBusiness.iso(Date().addingTimeInterval(86400)) : next); put("notes", notes)
        b.rows.append(row)
        Self.save("Leads", b)
        let total = b.rows.count
        return "Added \(name.isEmpty ? phone : name.capitalized) to Leads ✅\(src.isEmpty ? "" : " (from \(src))") — follow-up set for \(next.isEmpty ? "tomorrow" : next). You have \(total) lead\(total == 1 ? "" : "s"). Say “message new leads” to WhatsApp them."
    }

    private func pipeline() -> String {
        let b = Self.load("Leads", header: Self.leadHeader)
        guard !b.rows.isEmpty else { return "No leads yet. Say “new lead Ali 0333 1234567 from Facebook, wants 10 marla in DHA”, or download your Facebook / Zameen leads and I'll add them by myself." }
        var byStatus: [String: Int] = [:], bySource: [String: Int] = [:]
        let weekAgo = Date().addingTimeInterval(-7 * 86400), today = Calendar.current.startOfDay(for: Date())
        var thisWeek = 0, due = 0
        for r in b.rows {
            byStatus[b.get(r, ["status"]).isEmpty ? "New" : b.get(r, ["status"]).capitalized, default: 0] += 1
            bySource[b.get(r, ["source"]).isEmpty ? "Other" : b.get(r, ["source"]), default: 0] += 1
            if let d = ZuffiBusiness.date(b.get(r, ["added"])), d >= weekAgo { thisWeek += 1 }
            if let d = ZuffiBusiness.date(b.get(r, ["next follow"])), d <= today { due += 1 }
        }
        let st = byStatus.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }.joined(separator: " · ")
        let so = bySource.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value)" }.joined(separator: " · ")
        return "\(b.rows.count) leads — \(thisWeek) new this week, \(due) to follow up today.\nStatus: \(st)\nSources: \(so)\nSay “follow-ups today”, “hot leads” or “message new leads”."
    }

    func followUpsToday() -> String {
        let today = Calendar.current.startOfDay(for: Date())
        return list({ b, r in
            let st = b.get(r, ["status"]).lowercased()
            return !["closed", "lost", "sold", "deal done", "not interested"].contains(st) && (ZuffiBusiness.date(b.get(r, ["next follow"])).map { $0 <= today } ?? false)
        }, title: "Follow up today")
    }

    private func list(_ keep: (Book, [String]) -> Bool, title: String) -> String {
        let b = Self.load("Leads", header: Self.leadHeader)
        let hits = b.rows.filter { keep(b, $0) }
        guard !hits.isEmpty else { return "\(title): none." }
        let lines = hits.suffix(15).reversed().map { r -> String in
            let bits = [b.get(r, ["interest"]), b.get(r, ["area"]), b.get(r, ["budget"])].filter { !$0.isEmpty }.joined(separator: ", ")
            return "• \(b.get(r, ["name"])) \(b.get(r, ["phone"]))" + (bits.isEmpty ? "" : " — \(bits)") + (b.get(r, ["status"]).isEmpty ? "" : " [\(b.get(r, ["status"]))]")
        }
        return "\(title) (\(hits.count)):\n" + lines.joined(separator: "\n")
    }

    private func draftLeadMessages(filter: String, custom: String) -> String {
        let b = Self.load("Leads", header: Self.leadHeader)
        let today = Calendar.current.startOfDay(for: Date())
        let picked = b.rows.filter { r in
            let st = b.get(r, ["status"]).lowercased(), src = b.get(r, ["source"]).lowercased()
            if filter.isEmpty || filter.contains("new") { return st.isEmpty || st == "new" }
            if filter.contains("all") { return !["closed", "lost", "not interested", "sold", "deal done"].contains(st) }
            if filter.contains("today") { return ZuffiBusiness.date(b.get(r, ["next follow"])).map { $0 <= today } ?? false }
            for w in ["hot", "warm", "cold"] where filter.contains(w) { return (st + " " + b.get(r, ["priority"]).lowercased()).contains(w) }
            return filter.split(separator: " ").contains { src.contains($0) }
        }.filter { !b.get($0, ["phone"]).isEmpty }
        guard !picked.isEmpty else { return "No \(filter.isEmpty ? "new" : filter) leads with a phone number." }
        pendingSends = picked.prefix(25).map { r in
            let n = first(b.get(r, ["name"])), want = b.get(r, ["interest"]), area = b.get(r, ["area"])
            let text = custom.isEmpty
                ? "Assalam o Alaikum \(n)! This is \(biz.isEmpty ? "your property agent" : biz). Thank you for your interest\(want.isEmpty ? "" : " in \(want)")\(area.isEmpty ? "" : " in \(area)"). I have some good options for you — when is a good time to talk?"
                : custom.replacingOccurrences(of: "{name}", with: n)
            return (b.get(r, ["name"]), b.get(r, ["phone"]), text)
        }
        pendingWhat = "Leads"
        let sample = pendingSends[0].text
        return "I've written \(pendingSends.count) WhatsApp message\(pendingSends.count == 1 ? "" : "s") (\(pendingSends.prefix(6).map(\.name).joined(separator: ", "))\(pendingSends.count > 6 ? "…" : "")).\nFirst one: “\(sample)”\nSay “send them” to send, or “no” to cancel."
    }

    private func sendPending() -> String {
        let list = pendingSends, what = pendingWhat
        pendingSends = []
        Task { @MainActor in
            var sent = 0
            for r in list {
                let res = await WhatsAppAgent.shared.sendScheduled(to: r.phone, text: r.text)
                if !res.lowercased().contains("couldn") { sent += 1 }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
            if what == "Leads" {
                var b = Self.load("Leads", header: Self.leadHeader)
                for r in list { if let i = b.rows.firstIndex(where: { Self.samePhone(b.get($0, ["phone"]), r.phone) }) {
                    b.set(i, ["last contact"], ZuffiBusiness.iso(Date()))
                    if b.get(b.rows[i], ["status"]).lowercased() == "new" || b.get(b.rows[i], ["status"]).isEmpty { b.set(i, ["status"], "Contacted") }
                } }
                Self.save("Leads", b)
            }
            NotificationCenter.default.post(name: .petSay, object: "Sent \(sent) of \(list.count) WhatsApp messages ✅")
        }
        return "Sending \(list.count) message\(list.count == 1 ? "" : "s") on WhatsApp… keep WhatsApp open."
    }

    // MARK: Appointments (salons, clinics, shops)

    private func appointments(_ raw: String, _ t: String) async -> String? {
        // Book: "book Emma tomorrow at 3pm for a cut", "new appointment for Priya on Friday 2pm colour 07700…"
        if t.range(of: #"^(?:book|new appointment|add appointment|make an appointment|schedule)\b"#, options: .regularExpression) != nil,
           !t.contains("flight"), !t.contains("hotel"), !t.contains("table at"), Self.when(raw) != nil {
            return await book(raw)
        }
        var b = Self.load("Appointments", header: Self.apptHeader)
        guard !b.rows.isEmpty else { return nil }
        // Cancel: "cancel Emma's appointment", "Emma cancelled"
        if let re = try? NSRegularExpression(pattern: #"^(?:cancel) (.+?)(?:'s|’s)? (?:appointment|booking)(.*)$|^(.+?) (?:has )?cancell?ed$"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) {
            let who = Range(m.range(at: 1), in: t).map { String(t[$0]) } ?? Range(m.range(at: 3), in: t).map { String(t[$0]) } ?? ""
            guard let i = upcoming(who, in: b) else { return "I couldn't find an upcoming appointment for \(who)." }
            b.set(i, ["status"], "Cancelled")
            Self.save("Appointments", b)
            let r = b.rows[i]
            return "Cancelled \(b.get(r, ["client", "name"]))'s \(b.get(r, ["service"])) on \(b.get(r, ["date"])) at \(b.get(r, ["time"])). Say “who should rebook?” to fill the gap."
        }
        // Move: "move Emma to Friday 2pm", "reschedule Emma's appointment to tomorrow 11am"
        if let re = try? NSRegularExpression(pattern: #"^(?:move|reschedule|change|shift) (.+?)(?:'s|’s)?(?: appointment| booking)? to (.+)$"#, options: [.caseInsensitive]),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let r1 = Range(m.range(at: 1), in: t), let r2 = Range(m.range(at: 2), in: t) {
            guard let i = upcoming(String(t[r1]), in: b) else { return nil }
            guard let d = Self.when(String(t[r2])) else { return "When to? e.g. “move \(t[r1]) to Friday 2pm”." }
            let old = "\(b.get(b.rows[i], ["date"])) \(b.get(b.rows[i], ["time"]))"
            b.set(i, ["date"], ZuffiBusiness.iso(d))
            if Self.hasTime(String(t[r2])) { b.set(i, ["time"], Self.hm(d)) }
            if let clash = clash(b, date: b.get(b.rows[i], ["date"]), time: b.get(b.rows[i], ["time"]), except: i) { Self.save("Appointments", b); return "Moved — but heads up, \(clash) is also booked then." }
            Self.save("Appointments", b)
            return offerConfirm(b, i, intro: "Moved \(b.get(b.rows[i], ["client", "name"])) from \(old) to \(b.get(b.rows[i], ["date"])) \(b.get(b.rows[i], ["time"])).")
        }
        if t.range(of: #"^(?:this |next )?week'?s (?:appointments|bookings)|^appointments this week"#, options: .regularExpression) != nil {
            let now = Calendar.current.startOfDay(for: Date()), end = now.addingTimeInterval(7 * 86400)
            let wk = b.rows.filter { r in ZuffiBusiness.date(b.get(r, ["date"])).map { $0 >= now && $0 < end } ?? false && !b.get(r, ["status"]).lowercased().contains("cancel") }
                .sorted { b.get($0, ["date"]) + b.get($0, ["time"]) < b.get($1, ["date"]) + b.get($1, ["time"]) }
            guard !wk.isEmpty else { return "No appointments in the next 7 days." }
            return "Next 7 days (\(wk.count)):\n" + wk.prefix(25).map { "• \(b.get($0, ["date"])) \(b.get($0, ["time"])) \(b.get($0, ["client", "name"])) – \(b.get($0, ["service"]))" }.joined(separator: "\n")
        }
        if t.range(of: #"^(?:confirm|send (?:a )?confirmation)(?: to)? (.+)$"#, options: .regularExpression) != nil {
            let who = t.replacingOccurrences(of: #"^(?:confirm|send (?:a )?confirmation)(?: to)? "#, with: "", options: .regularExpression)
            guard let i = upcoming(who, in: b) else { return nil }
            return offerConfirm(b, i, intro: "")
        }
        return nil
    }

    private func upcoming(_ who: String, in b: Book) -> Int? {
        let today = Calendar.current.startOfDay(for: Date())
        let cands = b.rows.indices.filter { i in
            (ZuffiBusiness.date(b.get(b.rows[i], ["date"])).map { $0 >= today } ?? true) && !b.get(b.rows[i], ["status"]).lowercased().contains("cancel")
        }
        let filtered = Book(header: b.header, rows: cands.map { b.rows[$0] })
        if let k = Self.find(who, in: filtered, nameKeys: ["client", "name"]) { return cands[k] }
        return Self.find(who, in: b, nameKeys: ["client", "name"])
    }

    private func clash(_ b: Book, date: String, time: String, except: Int? = nil) -> String? {
        guard !time.isEmpty else { return nil }
        for (i, r) in b.rows.enumerated() where i != except && b.get(r, ["date"]) == date && b.get(r, ["time"]) == time && !b.get(r, ["status"]).lowercased().contains("cancel") {
            return b.get(r, ["client", "name"])
        }
        return nil
    }

    private func book(_ raw: String) async -> String {
        guard let d = Self.when(raw) else { return "When? e.g. “book Emma tomorrow at 3pm for a cut”." }
        var client = "", service = "", staff = "", price = "", phone = Self.phone(in: raw) ?? ""
        let prompt = """
        Extract one appointment booking. Return JSON {"client":"","service":"","staff":"","price":"","phone":""}. Empty string when not said.
        Message: \(raw)
        """
        if let reply = await AIService.shared.oneShot(prompt), let j = AIService.jsonIn(reply) as? [String: Any] {
            func s(_ k: String) -> String {
                if let v = j[k] as? String { return v.trimmingCharacters(in: .whitespaces) }
                if let v = j[k] as? NSNumber { return v.stringValue }
                return ""
            }
            client = s("client"); service = s("service"); staff = s("staff"); price = s("price"); if !s("phone").isEmpty { phone = s("phone") }
        } else {
            let t = raw.replacingOccurrences(of: #"^(?i)(?:book|new appointment|add appointment|make an appointment|schedule)(?: for| in)?\s+"#, with: "", options: .regularExpression)
            client = t.components(separatedBy: CharacterSet(charactersIn: ",")).first?
                .replacingOccurrences(of: #"(?i)\s+(today|tomorrow|on|at|next|this|for|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b.*$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces) ?? ""
            if let r = raw.range(of: #"(?i)\bfor (?:a |an |her |his )?([a-z &]+?)(?:\s+with\s+([a-z]+))?(?:\s*[,.]|$|\s+\d|\s+(?:at|on|tomorrow|today))"#, options: .regularExpression) {
                service = String(raw[r]).replacingOccurrences(of: #"(?i)^for (?:a |an |her |his )?|\s+with\s+[a-z]+|[,.]$|\s+(at|on|tomorrow|today)$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            }
            if let r = raw.range(of: #"(?i)\bwith ([A-Z][a-z]+)"#, options: .regularExpression) { staff = String(raw[r]).replacingOccurrences(of: "with ", with: "", options: .caseInsensitive) }
        }
        guard !client.isEmpty else { return "Who is the booking for? e.g. “book Emma tomorrow at 3pm for a cut”." }
        // Phone from the Clients sheet when not said; add new clients there.
        var clients = Self.load("Clients", header: Self.clientHeader)
        if let ci = Self.find(client, in: clients, nameKeys: ["name", "client"]) {
            if phone.isEmpty { phone = clients.get(clients.rows[ci], ["phone", "mobile"]) }
            client = clients.get(clients.rows[ci], ["name", "client"])
            if service.isEmpty { service = clients.get(clients.rows[ci], ["usual service", "service"]) }
        } else {
            var row = Array(repeating: "", count: clients.header.count)
            if let x = clients.i(["name"]) { row[x] = client.capitalized }
            if let x = clients.i(["phone"]) { row[x] = phone }
            if let x = clients.i(["usual service"]) { row[x] = service }
            clients.rows.append(row)
            Self.save("Clients", clients)
        }
        var b = Self.load("Appointments", header: Self.apptHeader)
        let date = ZuffiBusiness.iso(d), time = Self.hasTime(raw) ? Self.hm(d) : ""
        let clashWith = clash(b, date: date, time: time)
        var row = Array(repeating: "", count: b.header.count)
        func put(_ k: [String], _ v: String) { if let x = b.i(k) { row[x] = v } }
        put(["date"], date); put(["time"], time); put(["client", "name"], client.capitalized); put(["phone"], phone)
        put(["service"], service); put(["staff"], staff); put(["price"], price); put(["status"], "Booked")
        b.rows.append(row)
        Self.save("Appointments", b)
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
        let intro = "Booked ✅ \(client.capitalized)\(service.isEmpty ? "" : " – \(service)") on \(f.string(from: d))\(time.isEmpty ? "" : " at \(time)")\(staff.isEmpty ? "" : " with \(staff)")."
            + (clashWith.map { " Heads up: \($0) is booked at the same time." } ?? "")
            + (time.isEmpty ? " What time?" : "")
        return offerConfirm(b, b.rows.count - 1, intro: intro)
    }

    private func offerConfirm(_ b: Book, _ i: Int, intro: String) -> String {
        let r = b.rows[i], phone = b.get(r, ["phone"])
        guard !phone.isEmpty else { return intro + (intro.isEmpty ? "" : " ") + "Add their phone number and I can WhatsApp a confirmation." }
        let svc = b.get(r, ["service"])
        let text = "Hi \(first(b.get(r, ["client", "name"]))), your \(svc.isEmpty ? "appointment" : svc + " appointment")\(biz.isEmpty ? "" : " at \(biz)") is booked for \(b.get(r, ["date"]))\(b.get(r, ["time"]).isEmpty ? "" : " at \(b.get(r, ["time"]))"). Reply here if you need to change it. See you then!"
        pendingSends = [(b.get(r, ["client", "name"]), phone, text)]
        pendingWhat = "Appointments"
        return (intro.isEmpty ? "" : intro + "\n") + "Send them a WhatsApp confirmation? Say “yes” to send."
    }

    // MARK: Leads that arrive by themselves (downloaded exports)

    /// Looks in Downloads for lead exports (Facebook / Instagram lead ads, Zameen, Google Forms…) and adds new people to Leads.
    func scanDownloads() {
        guard ZuffiCRM.shared.isOn(.leadExports) else { return }
        let dl = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dl, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return }
        var seen = UserDefaults.standard.dictionary(forKey: "leadExportsSeen") as? [String: Double] ?? [:]
        let recent = Date().addingTimeInterval(-3 * 86400)
        var added = 0, sources = Set<String>()
        for u in files where ["csv", "tsv", "txt"].contains(u.pathExtension.lowercased()) {
            guard let m = ZuffiBusiness.mtime(u), m > recent, seen[u.path] != m.timeIntervalSince1970 else { continue }
            seen[u.path] = m.timeIntervalSince1970
            guard let data = try? Data(contentsOf: u), data.count < 5_000_000 else { continue }
            // Facebook's lead download is UTF-16 with tabs; others are UTF-8 CSV.
            let text: String = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) ? (String(data: data, encoding: .utf16) ?? "") : (String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? "")
            guard let firstLine = text.split(whereSeparator: \.isNewline).first?.lowercased() else { continue }
            let sep: Character = firstLine.filter({ $0 == "\t" }).count > firstLine.filter({ $0 == "," }).count ? "\t" : ","
            let h = firstLine.components(separatedBy: String(sep)).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
            let hasPerson = h.contains { $0.contains("phone") || $0.contains("mobile") || $0.contains("whatsapp") }
            let keys = ["campaign", "ad_name", "ad name", "form", "lead", "platform", "inquiry", "enquiry", "created_time", "listing", "property"]
            let leadish = h.contains { col in keys.contains { col.contains($0) } }
                || u.lastPathComponent.lowercased().range(of: "lead|zameen|graana|enquir|inquir|facebook|meta", options: .regularExpression) != nil
            guard hasPerson, leadish else { continue }
            let rows = ZuffiData.parseCSV(text, sep: sep)
            guard rows.count > 1 else { continue }
            let src = Book(header: rows[0].map { $0.lowercased() }, rows: Array(rows.dropFirst()))
            var leads = Self.load("Leads", header: Self.leadHeader)
            let fname = u.lastPathComponent.lowercased()
            for r in src.rows {
                var name = src.get(r, ["full_name", "full name", "name"])
                if name.isEmpty { name = (src.get(r, ["first_name", "first name"]) + " " + src.get(r, ["last_name", "last name"])).trimmingCharacters(in: .whitespaces) }
                let phone = src.get(r, ["phone_number", "phone number", "phone", "mobile", "whatsapp", "contact"]).replacingOccurrences(of: "p:", with: "")
                guard !phone.filter(\.isNumber).isEmpty else { continue }
                if leads.rows.contains(where: { Self.samePhone(leads.get($0, ["phone"]), phone) }) { continue }
                let platform = src.get(r, ["platform"]).lowercased()
                let campaign = src.get(r, ["campaign_name", "campaign", "ad_name", "ad name", "form_name", "form"])
                let source = platform == "ig" || fname.contains("insta") ? "Instagram ad" : fname.contains("zameen") ? "Zameen.com" : fname.contains("graana") ? "Graana"
                    : (platform == "fb" || !platform.isEmpty || h.contains("ad_name") || fname.contains("facebook") || fname.contains("meta")) ? "Facebook ad" : "Import"
                sources.insert(source)
                // Any extra answers from the form go into notes.
                let used = Set(["full_name", "full name", "name", "first_name", "last_name", "phone_number", "phone", "id", "created_time", "ad_id", "adset_id", "campaign_id", "form_id", "is_organic", "platform"])
                let extra = zip(src.header, r).filter { !used.contains($0.0) && !$0.1.trimmingCharacters(in: .whitespaces).isEmpty && !$0.0.hasSuffix("_id") }.prefix(6).map { "\($0.0): \($0.1)" }.joined(separator: "; ")
                var row = Array(repeating: "", count: leads.header.count)
                func put(_ k: String, _ v: String) { if let x = leads.i([k]) { row[x] = v } }
                put("name", name); put("phone", phone); put("source", source + (campaign.isEmpty ? "" : " – \(campaign)"))
                put("status", "New"); put("added", ZuffiBusiness.iso(Date())); put("next follow", ZuffiBusiness.iso(Date())); put("notes", extra)
                put("assigned", ZuffiCRM.shared.nextAssignee())
                put("area", src.get(r, ["area", "city", "location", "sector"])); put("budget", src.get(r, ["budget", "price"])); put("interest", src.get(r, ["interest", "property", "looking", "requirement"]))
                leads.rows.append(row); added += 1
            }
            if added > 0 { Self.save("Leads", leads) }
        }
        UserDefaults.standard.set(seen, forKey: "leadExportsSeen")
        if added > 0 {
            let msg = "\(added) new lead\(added == 1 ? "" : "s") from \(sources.sorted().joined(separator: ", ")) added to your Leads. Say “message new leads” to say hello on WhatsApp."
            NotificationCenter.default.post(name: .petSay, object: msg)
            ZuffiHomeModel.shared.say(msg)
            SoundEngine.shared.play("chime")
        }
    }

    func connectGuide() -> String {
        """
        Here's how your leads reach Zuffi by themselves:
        • Facebook & Instagram ads: Meta Business Suite → All tools → Leads Center (or your Page → Lead forms) → Download → CSV. Save it in Downloads — I add the new people to Leads within a minute, with the campaign name as the source.
        • Zameen / Graana / OLX: download your enquiries as CSV or Excel into Downloads — same thing.
        • WhatsApp: say “check WhatsApp”; to save someone say “new lead <name> <number> from WhatsApp”.
        • Any list you paste here: say “save it” and I'll make a sheet.
        Then: “my leads”, “follow-ups today”, “message new leads”, “mark Ali as hot”, “follow up with Ali on Friday”.
        """
    }
}
