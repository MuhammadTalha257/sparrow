import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Properties (estate agents): your listings, matching buyers, site visits
//
//   Listings.csv  every property you have: plot / house / flat / shop / file, sale or rent,
//                 society & phase, size, price, owner, status (Available / On hold / Sold / Rented)
//   Visits.csv    site visits booked with clients (Zuffi reminds you and can WhatsApp the client)
//   Documents/Zuffi/Properties/<ID>/   photos and papers (allotment letter, NOC, map…)
//
// Say it: "add property 10 marla house DHA phase 6 2.5 crore owner Kamran 0300 1234567"
//         "who wants P-101?" · "properties for Ali" · "mark P-101 sold" · "visit with Ali Sunday 11am for P-101"
// =====================================================================

struct Property: Identifiable, Hashable {
    var id: String          // Property ID, e.g. P-101
    var row = 0
    var title = "", purpose = "Sale", type = "", area = "", block = "", size = "", beds = "", baths = ""
    var price = "", status = "Available", owner = "", ownerPhone = "", features = "", added = "", notes = "", agent = ""
    var priceNumber: Double { ZuffiMoney.number(price) }
    var isAvailable: Bool { status.lowercased().hasPrefix("avail") || status.isEmpty }
    var headline: String {
        let t = title.isEmpty ? [size, type].filter { !$0.isEmpty }.joined(separator: " ") : title
        return [t, [block, area].filter { !$0.isEmpty }.joined(separator: ", ")].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct SiteVisit: Identifiable, Hashable {
    let id: Int
    var date: String, time: String, client: String, phone: String, property: String, staff: String, status: String, notes: String
}

@MainActor
final class ZuffiProperties: ObservableObject {
    static let shared = ZuffiProperties()
    @Published private(set) var list: [Property] = []
    @Published private(set) var visits: [SiteVisit] = []

    static let header = ["Property ID", "Title", "Purpose", "Type", "Area", "Block / Phase", "Size", "Beds", "Baths", "Price", "Status", "Owner", "Owner phone", "Agent", "Features", "Added", "Notes"]
    static let visitHeader = ["Date", "Time", "Client", "Phone", "Property ID", "Staff", "Status", "Notes"]
    static let types = ["Plot", "House", "Flat / Apartment", "Shop", "Office", "Farmhouse", "File", "Commercial plot"]
    static let statuses = ["Available", "On hold", "Token received", "Sold", "Rented"]

    private init() { reload() }
    var cur: String { ZuffiCRM.shared.currency }

    static func folder(_ id: String) -> URL {
        let u = ZuffiBusiness.docs.appendingPathComponent("Properties/\(ZuffiData.safe(id))", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func files(_ id: String) -> [URL] {
        let u = ZuffiBusiness.docs.appendingPathComponent("Properties/\(ZuffiData.safe(id))", isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: u, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func reload() {
        let b = ZuffiPA.load("Listings", header: Self.header)
        list = b.rows.enumerated().compactMap { i, r in
            var p = Property(id: b.get(r, ["property id", "id"]), row: i)
            if p.id.isEmpty { p.id = "P-\(101 + i)" }
            p.title = b.get(r, ["title"]); p.purpose = b.get(r, ["purpose"]).isEmpty ? "Sale" : b.get(r, ["purpose"])
            p.type = b.get(r, ["type"]); p.area = b.get(r, ["area", "society", "location"]); p.block = b.get(r, ["block", "phase"])
            p.size = b.get(r, ["size"]); p.beds = b.get(r, ["beds"]); p.baths = b.get(r, ["baths"]); p.price = b.get(r, ["price", "demand"])
            p.status = b.get(r, ["status"]).isEmpty ? "Available" : b.get(r, ["status"]); p.owner = b.get(r, ["owner"]); p.ownerPhone = b.get(r, ["owner phone"])
            p.features = b.get(r, ["features"]); p.agent = b.get(r, ["agent"]); p.added = b.get(r, ["added"]); p.notes = b.get(r, ["notes"])
            return p
        }
        let v = ZuffiPA.load("Visits", header: Self.visitHeader)
        visits = v.rows.enumerated().map { i, r in
            SiteVisit(id: i, date: v.get(r, ["date"]), time: v.get(r, ["time"]), client: v.get(r, ["client"]), phone: v.get(r, ["phone"]),
                      property: v.get(r, ["property"]), staff: v.get(r, ["staff"]), status: v.get(r, ["status"]).isEmpty ? "Booked" : v.get(r, ["status"]), notes: v.get(r, ["notes"]))
        }
    }

    func nextID() -> String {
        let n = list.compactMap { Int($0.id.filter(\.isNumber)) }.max() ?? 100
        return "P-\(n + 1)"
    }

    func save(_ p: Property) {
        var b = ZuffiPA.load("Listings", header: Self.header)
        let values: [String: String] = ["property id": p.id, "title": p.title, "purpose": p.purpose, "type": p.type, "area": p.area, "block": p.block, "size": p.size,
                                        "beds": p.beds, "baths": p.baths, "price": p.price, "status": p.status, "owner": p.owner, "owner phone": p.ownerPhone,
                                        "features": p.features, "agent": p.agent, "added": p.added.isEmpty ? ZuffiBusiness.iso(Date()) : p.added, "notes": p.notes]
        let i: Int
        if let found = b.rows.indices.first(where: { b.get(b.rows[$0], ["property id", "id"]).lowercased() == p.id.lowercased() }) { i = found }
        else { b.rows.append(Array(repeating: "", count: b.header.count)); i = b.rows.count - 1 }
        for (k, v) in values { b.set(i, [k], v) }
        ZuffiPA.save("Listings", b)
        reload()
    }

    func delete(_ p: Property) {
        var b = ZuffiPA.load("Listings", header: Self.header)
        let header = b
        b.rows.removeAll { header.get($0, ["property id", "id"]).lowercased() == p.id.lowercased() }
        ZuffiPA.save("Listings", b); reload()
    }

    func find(_ words: String) -> Property? {
        let w = words.lowercased().trimmingCharacters(in: .whitespaces)
        return list.first { $0.id.lowercased() == w || $0.id.lowercased().replacingOccurrences(of: "-", with: "") == w.replacingOccurrences(of: "-", with: "") }
            ?? list.first { !w.isEmpty && ($0.title + " " + $0.area + " " + $0.block).lowercased().contains(w) }
    }

    // MARK: Matching (who wants this property / which properties fit this client)

    private func fits(_ p: Property, _ l: CRMLead) -> Int {
        guard p.isAvailable, l.isOpen else { return 0 }
        var score = 0
        let want = (l.interest + " " + l.area + " " + l.notes).lowercased()
        let words = (p.area + " " + p.block).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 2 }
        if words.contains(where: { want.contains($0) }) { score += 3 }
        if !p.type.isEmpty, want.contains(p.type.lowercased().components(separatedBy: " ").first ?? "§") { score += 2 }
        if let sz = p.size.lowercased().split(separator: " ").first, want.contains(String(sz)) { score += 2 }
        if want.contains(p.purpose.lowercased()) { score += 1 }
        let budget = ZuffiMoney.number(l.budget)
        if budget > 0, p.priceNumber > 0 { score += p.priceNumber <= budget * 1.1 ? 3 : -3 }
        return score
    }
    func buyers(for p: Property) -> [CRMLead] {
        ZuffiCRM.shared.leads.map { ($0, fits(p, $0)) }.filter { $0.1 >= 3 }.sorted { $0.1 > $1.1 }.map(\.0)
    }
    func matches(for l: CRMLead) -> [Property] {
        list.map { ($0, fits($0, l)) }.filter { $0.1 >= 3 }.sorted { $0.1 > $1.1 }.map(\.0)
    }

    func shareText(_ p: Property) -> String {
        var t = "🏡 \(p.headline)\n"
        if !p.price.isEmpty { t += "Price: \(p.price.contains(where: \.isLetter) ? p.price : "\(cur) \(ZuffiMoney.pretty(p.priceNumber))")\n" }
        let specs = [p.beds.isEmpty ? "" : "\(p.beds) bed", p.baths.isEmpty ? "" : "\(p.baths) bath", p.purpose == "Rent" ? "For rent" : ""].filter { !$0.isEmpty }
        if !specs.isEmpty { t += specs.joined(separator: " · ") + "\n" }
        if !p.features.isEmpty { t += p.features + "\n" }
        let biz = ZuffiBusiness.shared.businessName
        return t + "Ref \(p.id)\(biz.isEmpty ? "" : " · \(biz)"). Would you like to visit?"
    }

    // MARK: Site visits

    @discardableResult
    func bookVisit(client: String, phone: String, property: String, date: Date, staff: String = "", notes: String = "") -> String {
        var v = ZuffiPA.load("Visits", header: Self.visitHeader)
        v.rows.append([ZuffiBusiness.iso(date), ZuffiPA.hm(date), client, phone, property, staff, "Booked", notes])
        ZuffiPA.save("Visits", v); reload()
        // Move the client on in the pipeline and remind you.
        if let l = ZuffiCRM.shared.leads.first(where: { (!phone.isEmpty && ZuffiPA.samePhone($0.phone, phone)) || $0.name.lowercased() == client.lowercased() }) {
            ZuffiCRM.shared.setStage(l.key, "Site visit")
            ZuffiCRM.shared.edit(l.key) { b, i in b.set(i, ["next follow"], ZuffiBusiness.iso(date)) }
        }
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM"
        let remindAt = date.addingTimeInterval(-3600)
        Task { _ = await AgentRouter.shared.handle("remind me to meet \(client) for site visit \(property) at \(ZuffiPA.hm(remindAt)) on \(f.string(from: remindAt))") }
        return "Site visit booked ✅ \(client) · \(property) · \(f.string(from: date)) at \(ZuffiPA.hm(date)). I'll remind you an hour before."
    }

    func setVisitStatus(_ v: SiteVisit, _ status: String) {
        var b = ZuffiPA.load("Visits", header: Self.visitHeader)
        guard v.id < b.rows.count else { return }
        b.set(v.id, ["status"], status)
        ZuffiPA.save("Visits", b); reload()
    }

    var visitsToday: [SiteVisit] { visits.filter { $0.date == ZuffiBusiness.iso(Date()) && $0.status == "Booked" }.sorted { $0.time < $1.time } }
    var upcomingVisits: [SiteVisit] { visits.filter { $0.date >= ZuffiBusiness.iso(Date()) && $0.status == "Booked" }.sorted { $0.date + $0.time < $1.date + $1.time } }

    // MARK: Things you say

    func handle(_ raw: String) async -> String? {
        guard ZuffiCRM.shared.isEstate else { return nil }
        if let r = PKTools.handle(raw) { return r }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let l = t.lowercased()
        if l.range(of: #"^(?:add|new|save) (?:a )?(?:property|listing|plot|house|flat|file)\b"#, options: .regularExpression) != nil {
            return await smartAdd(t)
        }
        if let m = l.range(of: #"^(?:who wants|buyers for|clients for|match) (.+?)\??$"#, options: .regularExpression) {
            let w = String(l[m]).replacingOccurrences(of: #"^(?:who wants|buyers for|clients for|match) "#, with: "", options: .regularExpression).replacingOccurrences(of: "?", with: "")
            guard let p = find(w) else { return nil }
            let b = buyers(for: p)
            return b.isEmpty ? "No matching buyers for \(p.id) yet." : "Buyers for \(p.id) (\(p.headline)): " + b.prefix(8).map { "\($0.display) \($0.phone)" }.joined(separator: " · ")
        }
        if let m = l.range(of: #"^(?:properties|options|listings) for (.+?)\??$"#, options: .regularExpression) {
            let w = String(l[m]).replacingOccurrences(of: #"^(?:properties|options|listings) for "#, with: "", options: .regularExpression)
            guard let c = ZuffiCRM.shared.leads.first(where: { $0.name.lowercased().hasPrefix(w) }) else { return nil }
            let ps = matches(for: c)
            return ps.isEmpty ? "Nothing in your listings fits \(c.display) yet." : "For \(c.display): " + ps.prefix(6).map { "\($0.id) \($0.headline) \($0.price)" }.joined(separator: " · ")
        }
        if let re = try? NSRegularExpression(pattern: #"^(?:mark|set) (p-?\d+|.+?) (?:as )?(sold|rented|available|on hold|token received)$"#, options: .caseInsensitive),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let r1 = Range(m.range(at: 1), in: t), let r2 = Range(m.range(at: 2), in: t),
           var p = find(String(t[r1])) {
            p.status = String(t[r2]).capitalized
            save(p)
            return "\(p.id) is now \(p.status)."
        }
        if l.range(of: #"^(?:my |all )?(?:properties|listings|inventory)(?: available)?\??$"#, options: .regularExpression) != nil {
            let a = list.filter(\.isAvailable)
            return "\(a.count) available of \(list.count) properties. " + a.prefix(8).map { "\($0.id) \($0.headline) \($0.price)" }.joined(separator: " · ")
        }
        if l.range(of: #"^(?:today'?s |my )?(?:site )?visits(?: today)?\??$"#, options: .regularExpression) != nil {
            let v = upcomingVisits
            return v.isEmpty ? "No site visits booked." : "Site visits: " + v.prefix(8).map { "\($0.date) \($0.time) \($0.client) – \($0.property)" }.joined(separator: " · ")
        }
        // "visit with Ali Sunday 11am for P-101", "site visit Hina tomorrow 4pm DHA 6"
        if l.range(of: #"^(?:book |schedule )?(?:a )?(?:site )?visit (?:with |for )?"#, options: .regularExpression) != nil, let date = ZuffiPA.when(t) {
            let rest = t.replacingOccurrences(of: #"(?i)^(?:book |schedule )?(?:a )?(?:site )?visit (?:with |for )?"#, with: "", options: .regularExpression)
            let client = rest.components(separatedBy: " ").prefix { w in !["today", "tomorrow", "on", "at", "for", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "next"].contains(w.lowercased()) && w.first?.isNumber != true }.joined(separator: " ")
            let pid = t.range(of: #"(?i)\bp-?\d+\b"#, options: .regularExpression).map { String(t[$0]).uppercased() } ?? ""
            let lead = ZuffiCRM.shared.leads.first { !client.isEmpty && $0.name.lowercased().hasPrefix(client.lowercased()) }
            return bookVisit(client: lead?.name ?? client.capitalized, phone: lead?.phone ?? "", property: pid.isEmpty ? (find(rest)?.id ?? "") : pid, date: date, staff: lead?.assigned ?? "")
        }
        return nil
    }

    /// "add property 10 marla house DHA phase 6 2.5 crore owner Kamran 0300…" → a listing (AI fills the fields).
    func smartAdd(_ text: String) async -> String {
        var p = Property(id: nextID())
        p.added = ZuffiBusiness.iso(Date())
        let prompt = """
        A Pakistani property agent is adding a listing. Return JSON:
        {"title":"short, e.g. 10 Marla House","purpose":"Sale|Rent","type":"Plot|House|Flat / Apartment|Shop|Office|Farmhouse|File|Commercial plot","area":"society / town","block":"block or phase","size":"e.g. 10 Marla","beds":"","baths":"","price":"as said, e.g. 2.5 crore","owner":"","owner_phone":"","features":"corner, park facing… short","notes":""}
        Empty string when not said. Text: \(text)
        """
        if let j = await AIService.shared.fastJSON(prompt, system: "You turn a property description into JSON. Reply with JSON only.") {
            func s(_ k: String) -> String { (j[k] as? String ?? "").trimmingCharacters(in: .whitespaces) }
            p.title = s("title"); p.purpose = s("purpose").isEmpty ? "Sale" : s("purpose"); p.type = s("type"); p.area = s("area"); p.block = s("block")
            p.size = s("size"); p.beds = s("beds"); p.baths = s("baths"); p.price = s("price"); p.owner = s("owner"); p.ownerPhone = s("owner_phone")
            p.features = s("features"); p.notes = s("notes")
        } else {
            p.notes = text
            p.price = ZuffiPA.budget(in: text.lowercased()) ?? ""
            p.ownerPhone = ZuffiPA.phone(in: text) ?? ""
            if let r = text.range(of: #"(?i)\d+(\.\d+)?\s*(marla|kanal|sq ?ft|sqft|yards?)"#, options: .regularExpression) { p.size = String(text[r]) }
            p.type = Self.types.first { text.lowercased().contains($0.lowercased().components(separatedBy: " ").first!) } ?? ""
        }
        save(p)
        let b = buyers(for: p)
        return "Added \(p.id): \(p.headline)\(p.price.isEmpty ? "" : " · \(p.price)") ✅" + (b.isEmpty ? "" : "\n\(b.count) client\(b.count == 1 ? "" : "s") may want it: \(b.prefix(5).map(\.display).joined(separator: ", ")). Open Business → Properties to send it to them.")
    }
}

// MARK: - Properties tab

struct BizPropertiesView: View {
    @ObservedObject private var props = ZuffiProperties.shared
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var selected: String?
    @State private var filter = "Available"
    @State private var editing: Property?
    @State private var comparing = Set<String>()
    @State private var showCompare = false
    @State private var smart = ""
    @State private var busy = false
    @State private var agent = ""

    private var shown: [Property] {
        let q = nav.search.lowercased()
        return props.list.filter { p in
            (agent.isEmpty || p.agent == agent) &&
            (filter == "All" || (filter == "Available" ? p.isAvailable : p.status == filter || (filter == "Rent" && p.purpose == "Rent"))) &&
            (q.isEmpty || (p.id + p.title + p.area + p.block + p.type + p.size + p.owner + p.features).lowercased().contains(q))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Quick add: type, size, area, price and the owner’s number", text: $smart).textFieldStyle(.roundedBorder)
                        .onSubmit(quickAdd)
                    Button(busy ? "…" : "Add") { quickAdd() }.disabled(smart.isEmpty || busy)
                }
                HStack {
                    Picker("", selection: $filter) { ForEach(["Available", "On hold", "Sold", "Rent", "All"], id: \.self) { Text($0) } }.pickerStyle(.segmented).labelsHidden()
                    Picker("", selection: $agent) { Text("All agents").tag(""); ForEach(crm.team) { Text($0.name).tag($0.name) } }.labelsHidden().frame(width: 120)
                }
                HStack {
                    Button { editing = Property(id: props.nextID(), added: ZuffiBusiness.iso(Date())) } label: { Label("New property", systemImage: "plus") }
                    Button { importFile() } label: { Label("Import Excel", systemImage: "square.and.arrow.down") }
                    Spacer()
                    if comparing.count >= 2 { Button("Compare \(comparing.count)") { showCompare = true } }
                }.controlSize(.small)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(shown) { p in
                            Button { selected = p.id } label: {
                                HStack(spacing: 10) {
                                    thumb(p).frame(width: 52, height: 52)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(p.id) · \(p.headline)").font(zf(12.5, .bold)).lineLimit(1)
                                        Text([p.price, p.purpose == "Rent" ? "Rent" : "", p.agent.isEmpty ? p.owner : "👤 \(p.agent)"].filter { !$0.isEmpty }.joined(separator: " · ")).font(zf(11)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                                        HStack(spacing: 4) {
                                            statusPill(p.status)
                                            let n = props.buyers(for: p).count
                                            if n > 0 { Text("\(n) buyer\(n == 1 ? "" : "s")").font(zf(10, .bold)).foregroundColor(Color(hex: "#34D399")) }
                                        }
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(get: { comparing.contains(p.id) }, set: { on in
                                        if on { if comparing.count < 3 { comparing.insert(p.id) } } else { comparing.remove(p.id) }
                                    }))
                                        .toggleStyle(.checkbox).labelsHidden().help("Compare (up to 3)")
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(selected == p.id ? Color.white.opacity(0.12) : Color.white.opacity(0.04)))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if shown.isEmpty { Text("No properties here yet. Type one in Quick add, or import your Excel list.").font(zf(11.5)).foregroundColor(.white.opacity(0.5)).padding(.top, 30) }
                    }
                }
            }
            .frame(width: 380).padding(.leading, 18).padding(.bottom, 14)
            Divider().overlay(Color.white.opacity(0.12)).padding(.horizontal, 10)
            if let id = selected, let p = props.list.first(where: { $0.id == id }) {
                PropertyDetail(property: p, edit: { editing = p }).id(p.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "house.lodge.fill").font(zf(40)).foregroundColor(.white.opacity(0.3))
                    Text("\(props.list.filter(\.isAvailable).count) available · \(props.list.count) total").font(zf(15, .bold)).foregroundColor(.white.opacity(0.7))
                    Text("Pick a property to see matching buyers, photos and papers.").font(zf(11.5)).foregroundColor(.white.opacity(0.5))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(item: $editing) { p in PropertyEditor(property: p) }
        .sheet(isPresented: $showCompare) { PropertyCompare(ids: Array(comparing)) }
    }

    private func quickAdd() {
        let t = smart.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        busy = true
        Task { nav.say(await props.smartAdd(t)); smart = ""; busy = false; selected = props.list.last?.id }
    }

    private func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = ["csv", "xlsx"].compactMap { UTType(filenameExtension: $0) }
        p.message = "Pick your property list (Excel or CSV) — Zuffi adds every row"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        Task {
            let rows: [[String]]
            if u.pathExtension.lowercased() == "xlsx" { rows = await ZuffiData.readXLSX(u).first?.1 ?? [] }
            else { rows = ZuffiData.parseCSV((try? String(contentsOf: u, encoding: .utf8)) ?? "", sep: ",") }
            guard let h = rows.first else { return }
            let src = ZuffiPA.Book(header: h.map { $0.lowercased() }, rows: Array(rows.dropFirst()))
            var n = 0
            for r in src.rows {
                var x = Property(id: src.get(r, ["property id", "id", "ref"]).ifEmpty(props.nextID()))
                x.title = src.get(r, ["title", "name"]); x.type = src.get(r, ["type", "category"]); x.area = src.get(r, ["area", "society", "location", "town"])
                x.block = src.get(r, ["block", "phase", "sector"]); x.size = src.get(r, ["size", "marla", "area size"]); x.beds = src.get(r, ["bed"]); x.baths = src.get(r, ["bath"])
                x.price = src.get(r, ["price", "demand", "amount"]); x.status = src.get(r, ["status"]).ifEmpty("Available"); x.owner = src.get(r, ["owner"])
                x.ownerPhone = src.get(r, ["owner phone", "phone", "contact"]); x.purpose = src.get(r, ["purpose"]).ifEmpty("Sale"); x.notes = src.get(r, ["note", "remarks"])
                x.added = ZuffiBusiness.iso(Date())
                if !(x.title + x.area + x.size + x.price).isEmpty { props.save(x); n += 1 }
            }
            nav.say("Imported \(n) propert\(n == 1 ? "y" : "ies") ✅")
        }
    }

    @ViewBuilder private func thumb(_ p: Property) -> some View {
        if let img = ZuffiProperties.files(p.id).first(where: { ["jpg", "jpeg", "png", "heic", "webp"].contains($0.pathExtension.lowercased()) }).flatMap({ NSImage(contentsOf: $0) }) {
            Image(nsImage: img).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [Color(hex: "#7C5CFF").opacity(0.5), Color(hex: "#E2648A").opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Image(systemName: p.type.lowercased().contains("plot") || p.type.lowercased().contains("file") ? "square.dashed" : "house.fill").foregroundColor(.white.opacity(0.85)))
        }
    }
}

func statusPill(_ s: String) -> some View {
    let c: Color = s.lowercased().hasPrefix("avail") ? Color(hex: "#34D399") : s.lowercased().contains("sold") || s.lowercased().contains("rented") ? Color.white.opacity(0.5) : Color(hex: "#FBC56A")
    return Text(s).font(zf(10, .bold)).foregroundColor(c).padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(c.opacity(0.16)))
}

extension String { fileprivate func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

struct PropertyDetail: View {
    let property: Property
    var edit: () -> Void
    @ObservedObject private var props = ZuffiProperties.shared
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var visitFor: CRMLead?
    @State private var visitDate = Date().addingTimeInterval(86400)
    @State private var sending = false

    var body: some View {
        let p = property
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.headline).font(zf(19, .heavy))
                        Text("\(p.id) · \(p.purpose)\(p.price.isEmpty ? "" : " · \(p.price)")").font(zf(12)).foregroundColor(.white.opacity(0.65))
                    }
                    Spacer()
                    Menu { ForEach(ZuffiProperties.statuses, id: \.self) { s in Button(s) { var x = p; x.status = s; props.save(x) } } } label: { statusPill(p.status) }
                        .menuStyle(.borderlessButton).fixedSize()
                    Button("Edit", action: edit)
                }
                HStack(alignment: .top, spacing: 18) {
                    fact("Type", p.type); fact("Size", p.size); fact("Beds", p.beds); fact("Baths", p.baths)
                    fact("Owner", p.owner); fact("Owner phone", p.ownerPhone); fact("Agent", p.agent)
                }
                if !p.features.isEmpty || !p.notes.isEmpty {
                    Text([p.features, p.notes].filter { !$0.isEmpty }.joined(separator: "\n")).font(zf(12)).foregroundColor(.white.opacity(0.8)).textSelection(.enabled)
                }
                // Photos & papers
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Photos & papers", systemImage: "photo.on.rectangle").font(zf(13, .heavy))
                        Spacer()
                        Button("Add files…") { addFiles(p) }
                        Button("Open folder") { NSWorkspace.shared.open(ZuffiProperties.folder(p.id)) }
                    }.controlSize(.small)
                    let files = ZuffiProperties.files(p.id)
                    if files.isEmpty { Text("Add photos, the allotment letter, NOC, map or anything else. Drag files here or press Add files.").font(zf(11)).foregroundColor(.white.opacity(0.5)) }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(files, id: \.self) { u in
                                Button { NSWorkspace.shared.open(u) } label: {
                                    Group {
                                        if let img = NSImage(contentsOf: u), ["jpg", "jpeg", "png", "heic", "webp"].contains(u.pathExtension.lowercased()) {
                                            Image(nsImage: img).resizable().scaledToFill()
                                        } else {
                                            VStack { Image(systemName: "doc.fill").font(zf(20)); Text(u.lastPathComponent).font(zf(9)).lineLimit(2) }.padding(6)
                                        }
                                    }
                                    .frame(width: 90, height: 70).clipShape(RoundedRectangle(cornerRadius: 10))
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    for pr in providers { _ = pr.loadObject(ofClass: URL.self) { @Sendable u, _ in
                        guard let u else { return }
                        Task { @MainActor in try? FileManager.default.copyItem(at: u, to: ZuffiProperties.folder(p.id).appendingPathComponent(u.lastPathComponent)); props.reload() }
                    } }
                    return true
                }
                // Matching buyers
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Clients who may want it", systemImage: "person.2.fill").font(zf(13, .heavy))
                        Spacer()
                        let b = props.buyers(for: p)
                        if !b.isEmpty {
                            Button(sending ? "Sending…" : "WhatsApp it to all \(b.count)") { sendAll(p, b) }.disabled(sending)
                        }
                    }.controlSize(.small)
                    let b = props.buyers(for: p)
                    if b.isEmpty { Text("No matching clients yet — Zuffi checks area, size, type and budget.").font(zf(11)).foregroundColor(.white.opacity(0.5)) }
                    ForEach(b.prefix(12)) { l in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.display).font(zf(12.5, .semibold))
                                Text([l.interest, l.area, l.budget].filter { !$0.isEmpty }.joined(separator: " · ")).font(zf(10.5)).foregroundColor(.white.opacity(0.55))
                            }
                            Spacer()
                            Button("Send") { Task { nav.say(await crm.send(l.key, props.shareText(p))) } }
                            Button("Book visit") { visitFor = l; visitDate = Date().addingTimeInterval(86400) }
                            Button("Open") { nav.selected = l.key; nav.tab = .inbox }
                        }.controlSize(.small)
                    }
                }
                if crm.country == "PK" { PKDealDesk(property: p) }
                // Visits for this property
                let vs = props.visits.filter { $0.property == p.id }.sorted { $0.date + $0.time > $1.date + $1.time }
                if !vs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Site visits", systemImage: "figure.walk").font(zf(13, .heavy))
                        ForEach(vs) { v in
                            HStack {
                                Text("\(v.date) \(v.time) · \(v.client)").font(zf(12))
                                Spacer()
                                Menu(v.status) { ForEach(["Booked", "Done", "No-show", "Cancelled"], id: \.self) { s in Button(s) { props.setVisitStatus(v, s) } } }.fixedSize()
                            }
                        }
                    }
                }
                HStack {
                    Button("Copy details to share") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(props.shareText(p), forType: .string); nav.say("Copied") }
                    Spacer()
                    Button("Delete", role: .destructive) { props.delete(p) }
                }.controlSize(.small)
            }
            .padding(.trailing, 22).padding(.bottom, 22)
        }
        .sheet(item: $visitFor) { l in
            VStack(alignment: .leading, spacing: 12) {
                Text("Site visit: \(l.display) · \(p.id)").font(zf(15, .bold))
                DatePicker("When", selection: $visitDate).datePickerStyle(.compact)
                HStack {
                    Spacer()
                    Button("Cancel") { visitFor = nil }
                    Button("Book") {
                        nav.say(props.bookVisit(client: l.display, phone: l.phone, property: p.id, date: visitDate, staff: l.assigned))
                        visitFor = nil
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 380)
        }
    }

    private func sendAll(_ p: Property, _ b: [CRMLead]) {
        sending = true
        Task {
            for l in b.prefix(15) where !l.phone.isEmpty {
                _ = await crm.send(l.key, props.shareText(p))
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
            sending = false
            nav.say("Sent \(p.id) to \(min(b.count, 15)) clients ✅")
        }
    }

    private func addFiles(_ p: Property) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for u in panel.urls { try? FileManager.default.copyItem(at: u, to: ZuffiProperties.folder(p.id).appendingPathComponent(u.lastPathComponent)) }
        props.reload()
    }

    private func fact(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(zf(10, .bold)).foregroundColor(.white.opacity(0.5))
            Text(v.isEmpty ? "—" : v).font(zf(12.5, .semibold)).lineLimit(2)
        }
    }
}

struct PropertyEditor: View {
    let property: Property
    @Environment(\.dismiss) private var dismiss
    @State private var p = Property(id: "")
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Property \(p.id)").font(zf(17, .heavy))
            Form {
                TextField("Title", text: $p.title)
                Picker("For", selection: $p.purpose) { Text("Sale").tag("Sale"); Text("Rent").tag("Rent") }.pickerStyle(.segmented)
                Picker("Type", selection: $p.type) { Text("—").tag(""); ForEach(ZuffiProperties.types, id: \.self) { Text($0).tag($0) } }
                TextField("Society or area", text: $p.area)
                TextField("Block / phase", text: $p.block)
                TextField("Size (marla, kanal or sq ft)", text: $p.size)
                HStack { TextField("Beds", text: $p.beds); TextField("Baths", text: $p.baths) }
                TextField("Price or demand", text: $p.price)
                Picker("Status", selection: $p.status) { ForEach(ZuffiProperties.statuses, id: \.self) { Text($0).tag($0) } }
                TextField("Owner", text: $p.owner)
                TextField("Owner phone", text: $p.ownerPhone)
                Picker("Agent", selection: $p.agent) { Text("Nobody").tag(""); ForEach(ZuffiCRM.shared.team) { Text($0.name).tag($0.name) } }
                TextField("Features (corner, park facing, possession…)", text: $p.features)
                TextField("Notes", text: $p.notes)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { ZuffiProperties.shared.save(p); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 480)
        .onAppear { p = property }
    }
}

struct PropertyCompare: View {
    let ids: [String]
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var props = ZuffiProperties.shared
    var body: some View {
        let ps = ids.compactMap { id in props.list.first { $0.id == id } }
        let rows: [(String, (Property) -> String)] = [("Type", \.type), ("Area", { [$0.block, $0.area].filter { !$0.isEmpty }.joined(separator: ", ") }), ("Size", \.size),
                                                       ("Beds", \.beds), ("Baths", \.baths), ("Price", \.price), ("For", \.purpose), ("Status", \.status), ("Features", \.features)]
        VStack(alignment: .leading, spacing: 12) {
            Text("Compare properties").font(zf(17, .heavy))
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    ForEach(ps) { p in Text(p.id).font(zf(13, .bold)) }
                }
                ForEach(rows, id: \.0) { r in
                    GridRow {
                        Text(r.0).font(zf(11, .bold)).foregroundColor(.secondary)
                        ForEach(ps) { p in Text(r.1(p).isEmpty ? "—" : r.1(p)).font(zf(12)).frame(width: 170, alignment: .leading) }
                    }
                }
            }
            HStack {
                Button("Copy for a client") {
                    let t = ps.map { props.shareText($0) }.joined(separator: "\n\n")
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20)
    }
}

// MARK: - Pakistan deal desk: sizes, price per marla, installments, token money, commission, transfer papers
//
//   "10 marla in sq ft" · "price per marla P-101" · "installments 1.2 crore 25% down 36 months"
//   "token 5 lakh from Ali for P-101 due in 30 days" · "deals" · "papers for P-101"

struct PKDeal: Codable, Hashable {
    var buyer = "", buyerPhone = "", price = "", token = "", tokenDate = "", dueDate = "", agreementDate = ""
    var stage = "Token received"            // Token received · Agreement signed · Full payment · Transfer done
    var commissionPct = "1", dealerShare = "", docs: [String] = [], notes = ""
    static let stages = ["Token received", "Agreement signed", "Full payment", "Transfer done"]
}

@MainActor
enum PKTools {
    /// Square feet in one marla — societies differ (DHA / LDA 225, some 250, old revenue measure 272.25).
    static var marlaSqft: Double {
        get { let v = UserDefaults.standard.double(forKey: "pkMarlaSqft"); return v > 0 ? v : 225 }
        set { UserDefaults.standard.set(newValue, forKey: "pkMarlaSqft") }
    }

    /// "10 marla" / "1 kanal" / "2250 sq ft" / "500 sq yd" → square feet.
    static func sqft(_ s: String) -> Double? {
        let t = s.lowercased().replacingOccurrences(of: ",", with: "")
        guard let r = t.range(of: #"\d+(\.\d+)?"#, options: .regularExpression), let v = Double(t[r]) else { return nil }
        if t.contains("kanal") { return v * 20 * marlaSqft }
        if t.contains("marla") { return v * marlaSqft }
        if t.range(of: #"(sq\.? ?y|yard|gaz)"#, options: .regularExpression) != nil { return v * 9 }
        if t.range(of: #"(sq\.? ?f|square f|ft)"#, options: .regularExpression) != nil { return v }
        if t.contains("acre") { return v * 43_560 }
        return nil
    }

    static func sizes(_ s: String) -> String? {
        guard let f = sqft(s) else { return nil }
        let m = f / marlaSqft
        func n(_ x: Double) -> String { x >= 100 ? Int(x.rounded()).formatted() : String(format: "%.2f", x).replacingOccurrences(of: ".00", with: "") }
        return "\(n(m)) marla · \(n(m / 20)) kanal · \(n(f)) sq ft · \(n(f / 9)) sq yd (1 marla = \(Int(marlaSqft)) sq ft)"
    }

    static func rs(_ v: Double) -> String {
        if v >= 10_000_000 { return String(format: "%.2f crore", v / 10_000_000).replacingOccurrences(of: ".00", with: "") }
        if v >= 100_000 { return String(format: "%.2f lakh", v / 100_000).replacingOccurrences(of: ".00", with: "") }
        return "Rs " + Int(v.rounded()).formatted()
    }

    static func perMarla(_ p: Property) -> String? {
        let price = p.priceNumber
        guard price > 0, let f = sqft(p.size), f > 0 else { return nil }
        return "\(rs(price / (f / marlaSqft))) per marla · Rs \(Int((price / f).rounded()).formatted()) per sq ft"
    }

    /// Down payment, then equal instalments every `every` months.
    static func installments(price: Double, downPct: Double, months: Int, every: Int = 1, possessionPct: Double = 0) -> String {
        guard price > 0, months > 0 else { return "Tell me the price and how many months, e.g. “installments 1.2 crore 25% down 36 months”." }
        let down = price * downPct / 100, possession = price * possessionPct / 100
        let count = max(1, months / max(1, every))
        let each = (price - down - possession) / Double(count)
        var out = "Total \(rs(price)): down payment \(rs(down)) (\(Int(downPct))%), then \(count) \(every == 1 ? "monthly" : every == 3 ? "quarterly" : "every-\(every)-months") instalments of \(rs(each))"
        if possession > 0 { out += ", and \(rs(possession)) on possession" }
        return out + "."
    }

    /// Papers for a sale/transfer (society file or plot vs. revenue land / registry).
    static func papers(_ p: Property) -> [String] {
        let society = (p.area + " " + p.block).lowercased().range(of: #"dha|bahria|society|town|phase|block|capital smart|gulberg|lda|cda"#, options: .regularExpression) != nil
        var list = ["Seller's CNIC copy", "Buyer's CNIC copy", "Token receipt (bayana) signed by both", "Agreement to sell (iqrarnama) with 2 witnesses",
                    "Original title papers checked", "Utility bills / dues paid"]
        if society || p.type == "File" {
            list += ["Allotment letter / file", "NOC from the society", "Non-demand / dues clearance certificate", "Site plan / map", "Transfer letter & biometric at the society office", "Possession letter"]
        } else {
            list += ["Fard (from the land record centre)", "Registry / sale deed", "Intiqal (mutation) done", "Map approval (if built)"]
        }
        list += ["Taxes paid (seller & buyer advance tax, stamp duty — check current FBR rates)", "Commission received"]
        return list
    }

    static var deals: [String: PKDeal] {
        get { (try? JSONDecoder().decode([String: PKDeal].self, from: UserDefaults.standard.data(forKey: "pkDeals") ?? Data())) ?? [:] }
        set { if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: "pkDeals") } }
    }

    static func commission(_ d: PKDeal) -> Double { ZuffiMoney.number(d.price) * (Double(d.commissionPct) ?? 0) / 100 }

    /// Deals whose full payment is due within 3 days (morning nudge).
    static var dueSoon: [(String, PKDeal)] {
        let soon = ZuffiBusiness.iso(Date().addingTimeInterval(3 * 86400))
        return deals.filter { !$0.value.dueDate.isEmpty && $0.value.dueDate <= soon && $0.value.stage != "Transfer done" && $0.value.stage != "Full payment" }.sorted { $0.value.dueDate < $1.value.dueDate }
    }

    static func handle(_ raw: String) -> String? {
        let l = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ?.!"))
        let props = ZuffiProperties.shared
        if l.range(of: #"^(?:convert )?\d+(\.\d+)? ?(marla|kanal|sq ?ft|sqft|square feet|sq ?yd|yards?|gaz|acres?)( (in|to|into) .+)?$"#, options: .regularExpression) != nil {
            return sizes(l)
        }
        if l.hasPrefix("1 marla is") || l.range(of: #"^(?:set )?marla (?:is |= ?)?(\d+)( sq ?ft)?$"#, options: .regularExpression) != nil,
           let v = Double(l.filter(\.isNumber)), v >= 200, v <= 300 {
            marlaSqft = v; return "Okay — 1 marla = \(Int(v)) sq ft from now on."
        }
        if l.range(of: #"^price per marla"#, options: .regularExpression) != nil {
            let w = l.replacingOccurrences(of: "price per marla", with: "").trimmingCharacters(in: .whitespaces)
            guard let p = props.find(w) else { return "Which property? Say “price per marla P-101”." }
            return perMarla(p).map { "\(p.id): \($0)" } ?? "\(p.id) needs a price and a size first."
        }
        if l.range(of: #"^(?:installments?|instalments?|qist|payment plan)\b"#, options: .regularExpression) != nil {
            let price = ZuffiMoney.number(l.replacingOccurrences(of: #"\d+(\.\d+)?\s*%.*$"#, with: "", options: .regularExpression))
            let pct = l.range(of: #"(\d+(\.\d+)?)\s*%"#, options: .regularExpression).flatMap { Double(l[$0].filter { $0.isNumber || $0 == "." }) } ?? 25
            let months = l.range(of: #"(\d+)\s*(months?|mahine)"#, options: .regularExpression).flatMap { Int(l[$0].filter(\.isNumber)) }
                ?? l.range(of: #"(\d+)\s*(years?|saal)"#, options: .regularExpression).flatMap { Int(l[$0].filter(\.isNumber)).map { $0 * 12 } } ?? 36
            return installments(price: price, downPct: pct, months: months, every: l.contains("quarter") ? 3 : 1)
        }
        // "token 5 lakh from Ali for P-101 due in 30 days"
        if l.range(of: #"^(?:token|bayana|biyana)\b"#, options: .regularExpression) != nil {
            guard let pid = l.range(of: #"\bp-?\d+\b"#, options: .regularExpression).map({ String(l[$0]).uppercased().replacingOccurrences(of: "P", with: "P-").replacingOccurrences(of: "P--", with: "P-") }),
                  var p = props.find(pid) else { return "Say which property, e.g. “token 5 lakh from Ali for P-101 due in 30 days”." }
            var d = deals[p.id] ?? PKDeal()
            if let r = l.range(of: #"(?:token|bayana|biyana)\s+([\d.,]+\s*(?:lakh|lac|crore|k)?)"#, options: .regularExpression) { d.token = String(l[r]).replacingOccurrences(of: #"^(token|bayana|biyana)\s+"#, with: "", options: .regularExpression) }
            if let r = l.range(of: #"from ([a-z]+( [a-z]+)?)"#, options: .regularExpression) {
                let n = String(l[r]).replacingOccurrences(of: "from ", with: "").components(separatedBy: " ").prefix { !["for", "due", "on"].contains($0) }.joined(separator: " ")
                d.buyer = n.capitalized
                d.buyerPhone = ZuffiCRM.shared.leads.first { $0.name.lowercased().hasPrefix(n) }?.phone ?? d.buyerPhone
            }
            let days = l.range(of: #"(\d+)\s*days?"#, options: .regularExpression).flatMap { Int(l[$0].filter(\.isNumber)) } ?? 30
            d.tokenDate = ZuffiBusiness.iso(Date()); d.dueDate = ZuffiBusiness.iso(Date().addingTimeInterval(Double(days) * 86400))
            if d.price.isEmpty { d.price = p.price }
            d.stage = "Token received"
            var all = deals; all[p.id] = d; deals = all
            p.status = "Token received"; props.save(p)
            return "Saved: token \(d.token) from \(d.buyer.isEmpty ? "the buyer" : d.buyer) for \(p.id). Full payment due \(d.dueDate) — I'll remind you 3 days before. Commission at \(d.commissionPct)%: \(rs(commission(d)))."
        }
        if l.range(of: #"^(?:my |open |active )?deals$|^token money$"#, options: .regularExpression) != nil {
            let d = deals.filter { $0.value.stage != "Transfer done" }
            if d.isEmpty { return "No open deals. Say “token 5 lakh from Ali for P-101 due in 30 days” when a token comes in." }
            return "Open deals (\(d.count)): " + d.sorted { $0.value.dueDate < $1.value.dueDate }.map { "\($0.key) · \($0.value.buyer) · \($0.value.stage) · due \($0.value.dueDate.isEmpty ? "—" : $0.value.dueDate)" }.joined(separator: "\n")
        }
        if l.range(of: #"^(?:papers|documents|docs|transfer papers) (?:for |of )?"#, options: .regularExpression) != nil {
            let w = l.replacingOccurrences(of: #"^(?:papers|documents|docs|transfer papers) (?:for |of )?"#, with: "", options: .regularExpression)
            guard let p = props.find(w) else { return nil }
            let done = Set(deals[p.id]?.docs ?? [])
            return "Papers for \(p.id):\n" + papers(p).map { (done.contains($0) ? "✅ " : "▫️ ") + $0 }.joined(separator: "\n")
        }
        return nil
    }
}

/// Property → Deal desk (Pakistan): size in every unit, price per marla, instalments, token & commission, papers checklist.
struct PKDealDesk: View {
    let property: Property
    @State private var deal = PKDeal()
    @State private var down = 25.0
    @State private var months = 36
    @State private var quarterly = false
    @State private var sqft = PKTools.marlaSqft
    @ObservedObject private var nav = BizNav.shared

    var body: some View {
        let p = property
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Deal desk", systemImage: "doc.text.magnifyingglass").font(zf(13, .heavy))
                Spacer()
                Picker("1 marla =", selection: $sqft) { Text("225 sq ft").tag(225.0); Text("250 sq ft").tag(250.0); Text("272.25 sq ft").tag(272.25) }
                    .frame(width: 190).controlSize(.small).onChange(of: sqft) { _, v in PKTools.marlaSqft = v }
            }
            Group {
                if let s = PKTools.sizes(p.size) { Text("📐 " + s) }
                if let pm = PKTools.perMarla(p) { Text("💰 " + pm) }
            }.font(zf(11.5)).foregroundColor(Ink.muted).textSelection(.enabled)
            // Instalments
            HStack(spacing: 10) {
                Text("Instalments").font(zf(11.5, .semibold))
                Stepper("Down \(Int(down))%", value: $down, in: 0...90, step: 5).fixedSize()
                Stepper("\(months) months", value: $months, in: 3...120, step: 3).fixedSize()
                Toggle("Quarterly", isOn: $quarterly).toggleStyle(.checkbox)
            }.font(zf(11.5)).controlSize(.small)
            Text(PKTools.installments(price: p.priceNumber, downPct: down, months: months, every: quarterly ? 3 : 1))
                .font(zf(11.5)).foregroundColor(Ink.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Divider()
            // Token & commission
            HStack(spacing: 8) {
                TextField("Buyer", text: $deal.buyer); TextField("Deal price", text: $deal.price); TextField("Token (bayana)", text: $deal.token)
            }.textFieldStyle(.roundedBorder).font(zf(11.5))
            HStack(spacing: 8) {
                TextField("Token date (yyyy-mm-dd)", text: $deal.tokenDate); TextField("Full payment due (yyyy-mm-dd)", text: $deal.dueDate)
                TextField("Commission %", text: $deal.commissionPct).frame(width: 100); TextField("Dealer share", text: $deal.dealerShare)
            }.textFieldStyle(.roundedBorder).font(zf(11.5))
            HStack {
                Picker("Stage", selection: $deal.stage) { ForEach(PKDeal.stages, id: \.self) { Text($0).tag($0) } }.frame(width: 240).controlSize(.small)
                Text("Commission: \(PKTools.rs(PKTools.commission(deal)))").font(zf(11.5, .semibold))
                Spacer()
                Button("Save deal") {
                    var all = PKTools.deals; all[p.id] = deal; PKTools.deals = all
                    var x = p; x.status = deal.stage == "Transfer done" ? (p.purpose == "Rent" ? "Rented" : "Sold") : "Token received"; ZuffiProperties.shared.save(x)
                    nav.say("Deal saved for \(p.id)")
                }.controlSize(.small)
            }
            Divider()
            // Papers checklist
            Text("Transfer papers").font(zf(11.5, .semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(PKTools.papers(p), id: \.self) { d in
                    Toggle(d, isOn: Binding(get: { deal.docs.contains(d) }, set: { on in
                        if on { deal.docs.append(d) } else { deal.docs.removeAll { $0 == d } }
                        var all = PKTools.deals; all[p.id] = deal; PKTools.deals = all
                    })).toggleStyle(.checkbox).font(zf(11))
                }
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Ink.panelHi))
        .onAppear { deal = PKTools.deals[p.id] ?? PKDeal(price: p.price) }
        .onChange(of: property.id) { _, id in deal = PKTools.deals[id] ?? PKDeal(price: property.price) }
    }
}
