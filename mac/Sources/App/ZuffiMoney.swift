import Foundation
import AppKit
import SwiftUI

// =====================================================================
// MARK: - Money: income, expenses, payments due, staff hours and salaries
//
// Sheets in Documents/Zuffi (open them in Excel / Numbers any time):
//   Money.csv     every rupee / pound in and out (category, who, how paid)
//   Due.csv       payments clients owe: installments, tokens, invoices (due date, paid or not)
//   Hours.csv     hours each team member worked
//   Payroll.csv   salaries paid each month
//
// Say it to Zuffi:
//   "expense 5000 petrol" · "spent £40 on supplies" · "income 2 lakh commission from Ali"
//   "Hina installment 5 lakh due 15 November" · "Hina paid installment" · "payments due"
//   "Sara worked 7 hours today" · "pay salaries" · "profit this month" · "this month's expenses"
// =====================================================================

struct MoneyEntry: Identifiable, Hashable {
    let id: Int
    var date: String, type: String, category: String, amount: Double, party: String, method: String, note: String, by: String
}

struct DuePayment: Identifiable, Hashable {
    let id: Int
    var client: String, phone: String, what: String, amount: Double, due: String, status: String, paidOn: String
    var isPaid: Bool { status.lowercased() == "paid" }
    var overdue: Bool { !isPaid && due < ZuffiBusiness.iso(Date()) }
}

struct PayLine: Identifiable {
    var id: String { name }
    let name: String, payType: String, rate: Double, hours: Double, commission: Double, advances: Double, gross: Double, net: Double, paid: Bool
}

@MainActor
final class ZuffiMoney: ObservableObject {
    static let shared = ZuffiMoney()

    @Published private(set) var entries: [MoneyEntry] = []
    @Published private(set) var dues: [DuePayment] = []
    @Published private(set) var hours: [(date: String, name: String, hours: Double, note: String)] = []
    @Published private(set) var payroll: [(month: String, name: String, amount: Double, paidOn: String)] = []

    static let moneyHeader = ["Date", "Type", "Category", "Amount", "Party", "Method", "Note", "Added by"]
    static let dueHeader = ["Client", "Phone", "For", "Amount", "Due date", "Status", "Paid on"]
    static let hoursHeader = ["Date", "Name", "Hours", "Note"]
    static let payrollHeader = ["Month", "Name", "Amount", "Paid on"]

    private init() { reload() }

    var crm: ZuffiCRM { ZuffiCRM.shared }
    var cur: String { crm.currency }

    // MARK: Categories that fit the business

    var incomeCategories: [String] {
        crm.isEstate ? ["Commission", "Token / advance", "Installment received", "Rent collected", "Other income"]
                     : ["Sales", "Services", "Products", "Deposits", "Other income"]
    }
    var expenseCategories: [String] {
        crm.isEstate ? ["Salaries", "Office rent", "Marketing & ads", "Portal fees (Zameen etc.)", "Dealer share", "Fuel & travel", "Utilities & bills", "Advance to staff", "Other"]
                     : ["Wages", "Rent", "Stock & supplies", "Utilities", "Marketing", "Equipment", "Card / booking fees", "VAT & tax", "Advance to staff", "Other"]
    }
    var methods: [String] { crm.country == "PK" ? ["Cash", "Bank", "JazzCash", "Easypaisa", "Cheque"] : ["Card", "Cash", "Bank transfer", "Online"] }

    // MARK: Load / save

    func reload() {
        let m = ZuffiPA.load("Money", header: Self.moneyHeader)
        entries = m.rows.enumerated().map { i, r in
            MoneyEntry(id: i, date: m.get(r, ["date"]), type: m.get(r, ["type"]), category: m.get(r, ["category"]), amount: Self.number(m.get(r, ["amount"])),
                       party: m.get(r, ["party"]), method: m.get(r, ["method"]), note: m.get(r, ["note"]), by: m.get(r, ["added by"]))
        }
        let d = ZuffiPA.load("Due", header: Self.dueHeader)
        dues = d.rows.enumerated().map { i, r in
            DuePayment(id: i, client: d.get(r, ["client"]), phone: d.get(r, ["phone"]), what: d.get(r, ["for"]), amount: Self.number(d.get(r, ["amount"])),
                       due: d.get(r, ["due date"]), status: d.get(r, ["status"]).isEmpty ? "Due" : d.get(r, ["status"]), paidOn: d.get(r, ["paid on"]))
        }
        let h = ZuffiPA.load("Hours", header: Self.hoursHeader)
        hours = h.rows.map { (h.get($0, ["date"]), h.get($0, ["name"]), Self.number(h.get($0, ["hours"])), h.get($0, ["note"])) }
        let p = ZuffiPA.load("Payroll", header: Self.payrollHeader)
        payroll = p.rows.map { (p.get($0, ["month"]), p.get($0, ["name"]), Self.number(p.get($0, ["amount"])), p.get($0, ["paid on"])) }
    }

    @discardableResult
    func add(type: String, category: String, amount: Double, party: String = "", method: String = "", note: String = "", date: String = ZuffiBusiness.iso(Date())) -> String {
        var m = ZuffiPA.load("Money", header: Self.moneyHeader)
        m.rows.append([date, type, category, Self.plain(amount), party, method, note, crm.ownerName.isEmpty ? "Owner" : crm.ownerName])
        ZuffiPA.save("Money", m)
        reload()
        return "\(type == "Income" ? "Income" : "Expense") saved ✅ \(cur) \(Self.pretty(amount)) · \(category)\(party.isEmpty ? "" : " · \(party)")."
    }

    func delete(_ e: MoneyEntry) {
        var m = ZuffiPA.load("Money", header: Self.moneyHeader)
        guard e.id < m.rows.count else { return }
        m.rows.remove(at: e.id)
        ZuffiPA.save("Money", m); reload()
    }

    func addDue(client: String, phone: String, what: String, amount: Double, due: String) {
        var d = ZuffiPA.load("Due", header: Self.dueHeader)
        d.rows.append([client, phone, what, Self.plain(amount), due, "Due", ""])
        ZuffiPA.save("Due", d); reload()
    }

    /// Marks a payment received and adds it to income.
    func markPaid(_ p: DuePayment) {
        var d = ZuffiPA.load("Due", header: Self.dueHeader)
        guard p.id < d.rows.count else { return }
        d.set(p.id, ["status"], "Paid"); d.set(p.id, ["paid on"], ZuffiBusiness.iso(Date()))
        ZuffiPA.save("Due", d)
        add(type: "Income", category: crm.isEstate ? (p.what.lowercased().contains("token") ? "Token / advance" : "Installment received") : "Sales",
            amount: p.amount, party: p.client, note: p.what)
    }

    func logHours(_ name: String, _ h: Double, date: String = ZuffiBusiness.iso(Date()), note: String = "") {
        var t = ZuffiPA.load("Hours", header: Self.hoursHeader)
        t.rows.append([date, name, Self.plain(h), note])
        ZuffiPA.save("Hours", t); reload()
    }

    // MARK: Numbers

    static func number(_ s: String) -> Double {
        let t = s.lowercased().replacingOccurrences(of: ",", with: "")
        guard let r = t.range(of: #"\d+(\.\d+)?"#, options: .regularExpression), let v = Double(t[r]) else { return 0 }
        if t.contains("crore") || t.range(of: #"\d\s*cr\b"#, options: .regularExpression) != nil { return v * 10_000_000 }
        if t.contains("lakh") || t.contains("lac") { return v * 100_000 }
        if t.range(of: #"\d\s*(k|thousand|hazar|hazaar)\b"#, options: .regularExpression) != nil { return v * 1000 }
        if t.range(of: #"\d\s*(m|million)\b"#, options: .regularExpression) != nil { return v * 1_000_000 }
        return v
    }
    static func plain(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
    static func pretty(_ v: Double) -> String { Int(v.rounded()).formatted() }

    var month: String { String(ZuffiBusiness.iso(Date()).prefix(7)) }
    func inMonth(_ m: String) -> [MoneyEntry] { entries.filter { $0.date.hasPrefix(m) } }
    func income(_ m: String) -> Double { inMonth(m).filter { $0.type == "Income" }.reduce(0) { $0 + $1.amount } }
    func expenses(_ m: String) -> Double { inMonth(m).filter { $0.type != "Income" }.reduce(0) { $0 + $1.amount } }
    func byCategory(_ m: String, type: String) -> [(String, Double)] {
        var d: [String: Double] = [:]
        for e in inMonth(m) where (type == "Income") == (e.type == "Income") { d[e.category.isEmpty ? "Other" : e.category, default: 0] += e.amount }
        return d.sorted { $0.value > $1.value }
    }
    var dueOpen: [DuePayment] { dues.filter { !$0.isPaid }.sorted { $0.due < $1.due } }

    // MARK: Payroll

    func payLines(_ m: String) -> [PayLine] {
        crm.team.map { s in
            let rate = Self.number(s.rate)
            let hrs = hours.filter { $0.name == s.name && $0.date.hasPrefix(m) }.reduce(0) { $0 + $1.hours }
            // Commission: % of the value of deals / sales this person closed this month.
            let sales = crm.leads.filter { $0.assigned == s.name && $0.isSale && $0.lastContact.hasPrefix(m) }.reduce(0) { $0 + $1.valueNumber }
            let commission = s.payType == "Commission" ? sales * rate / 100 : 0
            let gross = s.payType == "Hourly" ? rate * hrs : s.payType == "Commission" ? commission : rate
            let adv = inMonth(m).filter { $0.category.lowercased().contains("advance") && $0.party == s.name }.reduce(0) { $0 + $1.amount }
            let paid = payroll.contains { $0.month == m && $0.name == s.name }
            return PayLine(name: s.name, payType: s.payType, rate: rate, hours: hrs, commission: commission, advances: adv, gross: gross, net: max(0, gross - adv), paid: paid)
        }
    }

    /// Pays everyone not yet paid this month: a Payroll line + a Salaries / Wages expense each.
    func paySalaries(_ only: String? = nil) -> String {
        let lines = payLines(month).filter { !$0.paid && $0.net > 0 && (only == nil || $0.name.lowercased() == only!.lowercased()) }
        guard !lines.isEmpty else { return only == nil ? "Everyone with pay set is already paid for this month 👍" : "\(only!) is already paid, or has no pay set (Team tab)." }
        var p = ZuffiPA.load("Payroll", header: Self.payrollHeader)
        for l in lines {
            p.rows.append([month, l.name, Self.plain(l.net), ZuffiBusiness.iso(Date())])
            var m = ZuffiPA.load("Money", header: Self.moneyHeader)
            m.rows.append([ZuffiBusiness.iso(Date()), "Expense", crm.isEstate ? "Salaries" : "Wages", Self.plain(l.net), l.name, "", "Pay for \(month)", crm.ownerName.isEmpty ? "Owner" : crm.ownerName])
            ZuffiPA.save("Money", m)
        }
        ZuffiPA.save("Payroll", p); reload()
        let total = lines.reduce(0) { $0 + $1.net }
        return "Paid ✅ " + lines.map { "\($0.name) \(cur) \(Self.pretty($0.net))" }.joined(separator: ", ") + ". Total \(cur) \(Self.pretty(total)), saved under expenses."
    }

    func summaryText(_ m: String? = nil) -> String {
        let mm = m ?? month
        let inc = income(mm), exp = expenses(mm)
        var t = "\(monthName(mm)): income \(cur) \(Self.pretty(inc)), expenses \(cur) \(Self.pretty(exp)), \(inc - exp >= 0 ? "profit" : "loss") \(cur) \(Self.pretty(abs(inc - exp)))."
        let top = byCategory(mm, type: "Expense").prefix(3)
        if !top.isEmpty { t += "\nBiggest costs: " + top.map { "\($0.0) \(cur) \(Self.pretty($0.1))" }.joined(separator: ", ") + "." }
        let due = dueOpen
        if !due.isEmpty { t += "\nStill to collect: \(cur) \(Self.pretty(due.reduce(0) { $0 + $1.amount })) from \(due.count) payment\(due.count == 1 ? "" : "s")" + (due.filter(\.overdue).isEmpty ? "." : " (\(due.filter(\.overdue).count) overdue).") }
        return t
    }
    func monthName(_ m: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        guard let d = f.date(from: m) else { return m }
        f.dateFormat = "MMMM yyyy"; return f.string(from: d)
    }

    // MARK: Things you say

    func handle(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()
        // Summaries
        if l.range(of: #"^(?:show |what'?s |what is )?(?:my |the )?(?:profit|money|accounts?|income and expenses?|p ?& ?l|kitna kamaya|hisaab)(?: this month| for this month| summary)?\??$|^(?:this month'?s|monthly) (?:profit|summary|accounts?)$"#, options: .regularExpression) != nil {
            return summaryText()
        }
        if l.range(of: #"^(?:show |list )?(?:this month'?s |my )?expenses(?: this month)?\??$"#, options: .regularExpression) != nil {
            let c = byCategory(month, type: "Expense")
            return c.isEmpty ? "No expenses this month yet." : "Expenses in \(monthName(month)) (\(cur) \(Self.pretty(expenses(month)))): " + c.map { "\($0.0) \(cur) \(Self.pretty($0.1))" }.joined(separator: " · ")
        }
        if l.range(of: #"^(?:show |list |any )?(?:payments?|installments?|money) (?:due|to collect|pending)\??$|^who (?:owes|has to pay)"#, options: .regularExpression) != nil {
            let d = dueOpen
            return d.isEmpty ? "Nobody owes you anything right now 🎉" : "To collect (\(d.count)): " + d.prefix(10).map { "\($0.client) \(cur) \(Self.pretty($0.amount)) \($0.what) – \($0.due)\($0.overdue ? " ⚠️" : "")" }.joined(separator: " · ")
        }
        if l.range(of: #"^(?:pay|paid) (?:all )?(?:the )?(?:salaries|salary|wages|staff)$|^salaries? (?:de do|pay kar do)$"#, options: .regularExpression) != nil { return paySalaries() }
        if let m = l.range(of: #"^pay (.+?)'?s? (?:salary|wages)$"#, options: .regularExpression) {
            let who = String(l[m]).replacingOccurrences(of: #"^pay |'?s? (?:salary|wages)$"#, with: "", options: .regularExpression)
            return paySalaries(crm.team.first { $0.name.lowercased().hasPrefix(who) }?.name ?? who)
        }
        // Hours: "Sara worked 7 hours today", "Ali 8 hours yesterday"
        if let re = try? NSRegularExpression(pattern: #"^(.+?) (?:worked |did )?(\d+(?:\.\d+)?) ?(?:hours?|hrs?|ghante)(?: (today|yesterday))?$"#, options: .caseInsensitive),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let r1 = Range(m.range(at: 1), in: t), let r2 = Range(m.range(at: 2), in: t) {
            let who = String(t[r1]).trimmingCharacters(in: .whitespaces)
            guard let s = crm.team.first(where: { $0.name.lowercased() == who.lowercased() || $0.name.lowercased().hasPrefix(who.lowercased()) }) else { return nil }
            let day = Range(m.range(at: 3), in: t).map { String(t[$0]).lowercased() } == "yesterday" ? ZuffiBusiness.iso(Date().addingTimeInterval(-86400)) : ZuffiBusiness.iso(Date())
            logHours(s.name, Double(t[r2]) ?? 0, date: day)
            let total = hours.filter { $0.name == s.name && $0.date.hasPrefix(month) }.reduce(0) { $0 + $1.hours }
            return "Logged \(t[r2]) hours for \(s.name) ✅ (\(Self.plain(total)) hours this month)."
        }
        // Payment due: "Hina installment 5 lakh due 15 November", "Ali owes 50000 due Friday"
        if l.range(of: #"\bdue\b"#, options: .regularExpression) != nil, l.range(of: #"(installment|token|advance|owes|invoice|payment|rent|balance|qist)"#, options: .regularExpression) != nil {
            let amount = Self.number(t)
            guard amount > 0 else { return nil }
            let dueDate = ZuffiPA.when(String(t[(t.range(of: "due", options: .caseInsensitive)?.upperBound ?? t.startIndex)...])).map(ZuffiBusiness.iso) ?? ZuffiBusiness.iso(Date().addingTimeInterval(7 * 86400))
            let words = t.components(separatedBy: " ")
            let client = words.prefix { !$0.lowercased().contains("installment") && !$0.lowercased().contains("token") && !$0.lowercased().contains("owes") && !$0.lowercased().contains("advance") && $0.first?.isNumber != true }.joined(separator: " ")
            let what = ["installment", "token", "advance", "invoice", "rent", "balance", "qist"].first { l.contains($0) }?.capitalized ?? "Payment"
            let phone = crm.leads.first { !client.isEmpty && $0.name.lowercased().hasPrefix(client.lowercased()) }?.phone ?? ""
            addDue(client: client.isEmpty ? "Client" : client.capitalized, phone: phone, what: what, amount: amount, due: dueDate)
            return "Saved: \(client.capitalized) — \(what) \(cur) \(Self.pretty(amount)) due \(dueDate). I'll remind you the day before."
        }
        // "Hina paid installment", "Ali paid 50000"
        if let re = try? NSRegularExpression(pattern: #"^(.+?) (?:paid|has paid|ne de diya|ne diye)\b(.*)$"#, options: .caseInsensitive),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let r1 = Range(m.range(at: 1), in: t),
           !["i", "we", "maine", "hum", "i have", "i've", "you", "already"].contains(String(t[r1]).lowercased()) {
            let who = String(t[r1]).lowercased()
            if let p = dueOpen.first(where: { $0.client.lowercased().hasPrefix(who) }) {
                markPaid(p)
                return "Marked \(p.client)'s \(p.what.lowercased()) of \(cur) \(Self.pretty(p.amount)) as paid ✅ and added it to income."
            }
            let amount = Self.number(t)
            if amount > 0, crm.leads.contains(where: { $0.name.lowercased().hasPrefix(who) }) || crm.team.isEmpty == false && !crm.team.contains(where: { $0.name.lowercased().hasPrefix(who) }) {
                return add(type: "Income", category: incomeCategories.first ?? "Sales", amount: amount, party: String(t[r1]).capitalized)
            }
        }
        // Expense: "expense 5000 petrol", "spent £40 on supplies", "paid 2000 for electricity bill"
        if l.range(of: #"^(?:add )?(?:an )?(?:expense|kharcha|kharch)\b|^(?:i )?(?:spent|paid)\b|^bought\b"#, options: .regularExpression) != nil {
            let amount = Self.number(t)
            guard amount > 0 else { return "How much? e.g. “expense 5000 petrol”." }
            let note = t.replacingOccurrences(of: #"(?i)^(?:add )?(?:an )?(?:expense|kharcha|kharch|i spent|spent|i paid|paid|bought)\s*(?:of\s*)?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)(rs\.?|pkr|£|\$|€)?\s*\d[\d,\.]*\s*(k|lakh|lac|crore|thousand)?\s*(?:on|for)?\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let staff = crm.team.first { note.lowercased().contains($0.name.lowercased()) }
            return add(type: "Expense", category: category(for: note, staff: staff != nil), amount: amount, party: staff?.name ?? "", note: note)
        }
        // Income: "income 2 lakh commission from Ali", "received 50000 rent from Bilal", "sale 45"
        if l.range(of: #"^(?:add )?(?:income|received|got|sale|sold|aamdani)\b"#, options: .regularExpression) != nil {
            let amount = Self.number(t)
            guard amount > 0 else { return nil }
            var party = ""
            if let r = t.range(of: #"(?i)\bfrom\s+(.+)$"#, options: .regularExpression) { party = String(t[r]).replacingOccurrences(of: #"(?i)^from\s+"#, with: "", options: .regularExpression) }
            let cat = incomeCategories.first { l.contains($0.lowercased().components(separatedBy: " ").first ?? "§") } ?? incomeCategories.first ?? "Sales"
            return add(type: "Income", category: cat, amount: amount, party: party.capitalized, note: t)
        }
        return nil
    }

    private func category(for note: String, staff: Bool) -> String {
        let n = note.lowercased()
        let map: [(String, [String])] = [
            ("Fuel & travel", ["petrol", "fuel", "diesel", "uber", "careem", "taxi", "travel"]),
            ("Utilities & bills", ["electric", "bijli", "gas", "water", "internet", "wifi", "phone bill", "bill"]),
            ("Utilities", ["electric", "gas", "water", "internet", "broadband", "energy"]),
            ("Office rent", ["office rent"]), ("Rent", ["rent"]),
            ("Marketing & ads", ["facebook", "ads", "marketing", "boost", "instagram"]), ("Marketing", ["ads", "marketing", "facebook", "instagram", "flyer"]),
            ("Portal fees (Zameen etc.)", ["zameen", "graana", "olx"]),
            ("Stock & supplies", ["stock", "supplies", "products", "shampoo", "colour", "color", "dye"]),
            ("Equipment", ["chair", "dryer", "equipment", "laptop", "printer"]),
            ("Advance to staff", ["advance"]), ("Salaries", ["salary", "tankhwa"]), ("Wages", ["wage", "salary"]),
            ("VAT & tax", ["vat", "tax", "hmrc"]), ("Dealer share", ["dealer"]),
        ]
        let allowed = Set(expenseCategories)
        for (cat, words) in map where allowed.contains(cat) && words.contains(where: { n.contains($0) }) { return cat }
        if staff { return allowed.contains("Advance to staff") && n.contains("advance") ? "Advance to staff" : (crm.isEstate ? "Salaries" : "Wages") }
        return "Other"
    }

    // MARK: Reminders (called from the CRM tick)

    func tick() {
        let key = "moneyDueReminded"
        let today = ZuffiBusiness.iso(Date())
        guard UserDefaults.standard.string(forKey: key) != today, Calendar.current.component(.hour, from: Date()) >= 9 else { return }
        UserDefaults.standard.set(today, forKey: key)
        let tomorrow = ZuffiBusiness.iso(Date().addingTimeInterval(86400))
        let soon = dueOpen.filter { $0.due <= tomorrow }
        guard !soon.isEmpty else { return }
        let msg = "Payments to collect: " + soon.prefix(5).map { "\($0.client) \(cur) \(Self.pretty($0.amount))\($0.overdue ? " (overdue)" : $0.due == today ? " (today)" : " (tomorrow)")" }.joined(separator: ", ")
        NotificationCenter.default.post(name: .petSay, object: msg)
        ZuffiHomeModel.shared.say(msg)
    }
}
