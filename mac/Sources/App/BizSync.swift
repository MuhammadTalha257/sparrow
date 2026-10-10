import Foundation
import AppKit
import CryptoKit
import SwiftUI

// =====================================================================
// MARK: - Business sync: Mac ⇄ phone ⇄ tablet ⇄ Windows (same data everywhere)
//
// The business sheets (Leads, Team, Money, Due, Hours, Payroll, Listings, Visits, Appointments,
// Clients) and the business settings (name, type, country, currency, business info, today's update)
// are shared by every device that scanned the same QR code.
//
// • A "group" is a random channel + a 256-bit key. The QR code holds both (after the # of a link,
//   so it never reaches any server). Whoever scans it joins.
// • Changes travel through the free ntfy.sh relay, end-to-end encrypted (AES-GCM, same as the
//   iPhone link): the relay only sees scrambled bytes. It keeps them ~12 hours, so a device that was
//   off catches up when it opens; after longer it asks the others for everything ("hello").
// • Each row has a key (phone for leads, name for staff, property ID…) and a time. The newest
//   change to a row wins; deleted rows leave a small "tombstone" so they don't come back.
// • The same rules live in bizsync.js (phone / tablet / Windows app). Keep the two in step.
// =====================================================================

@MainActor
final class BizSync: ObservableObject {
    static let shared = BizSync()

    static let relay = "https://ntfy.sh"
    static let sheets = ["Leads", "Team", "Money", "Due", "Hours", "Payroll", "Listings", "Visits", "Appointments", "Clients"]
    static let cfgKeys = ["name", "kind", "country", "currency", "info", "today"]

    @Published private(set) var connected = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var devices: [String: Date] = [:]     // other devices seen → when
    @Published private(set) var recent: [String] = []

    private var streamTask: Task<Void, Never>?
    private var scanTimer: Timer?
    private var changeTask: Task<Void, Never>?
    private var seen: [String] = []
    private var state = SyncState()
    private var stamps: [String: Date] = [:]
    private var applying = false

    let deviceID: String = {
        if let d = UserDefaults.standard.string(forKey: "bizSyncDevice") { return d }
        let d = "mac-" + UUID().uuidString.prefix(8).lowercased()
        UserDefaults.standard.set(d, forKey: "bizSyncDevice"); return d
    }()
    var deviceName: String { Host.current().localizedName ?? "Mac" }

    // MARK: Group (channel + key)

    var linked: Bool { topic != nil && key != nil }
    private var topic: String? { UserDefaults.standard.string(forKey: "bizSyncTopic") }
    private var key: SymmetricKey? {
        guard let s = UserDefaults.standard.string(forKey: "bizSyncKey"), let d = Data(b64url: s), d.count == 32 else { return nil }
        return SymmetricKey(data: d)
    }
    /// The link inside the QR code: opens Zuffi on a phone and joins.
    var pairingURL: String {
        guard let t = topic, let k = UserDefaults.standard.string(forKey: "bizSyncKey") else { return "" }
        return "\(PhoneLink.webApp)#biz=\(t).\(k)"
    }

    /// Makes a new group with this Mac's data in it.
    func create() {
        var b = [UInt8](repeating: 0, count: 15)
        _ = SecRandomCopyBytes(kSecRandomDefault, b.count, &b)
        let t = "zb" + Data(b).b64url.replacingOccurrences(of: "-", with: "x").replacingOccurrences(of: "_", with: "y")
        let k = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }.b64url
        UserDefaults.standard.set(t, forKey: "bizSyncTopic"); UserDefaults.standard.set(k, forKey: "bizSyncKey")
        UserDefaults.standard.removeObject(forKey: "bizSyncLastID")
        state = SyncState(); saveState()
        objectWillChange.send()
        log("made a new link code")
        restart()
    }

    /// Joins a group from a pasted link / code ("…#biz=zb….KEY").
    @discardableResult func join(_ text: String) -> Bool {
        guard let r = text.range(of: #"biz=(zb[A-Za-z0-9]{16,})\.([A-Za-z0-9_-]{40,})"#, options: .regularExpression) else { return false }
        let parts = text[r].dropFirst(4).split(separator: ".")
        guard parts.count == 2, let d = Data(b64url: String(parts[1])), d.count == 32 else { return false }
        UserDefaults.standard.set(String(parts[0]), forKey: "bizSyncTopic"); UserDefaults.standard.set(String(parts[1]), forKey: "bizSyncKey")
        UserDefaults.standard.removeObject(forKey: "bizSyncLastID")
        UserDefaults.standard.set(0.0, forKey: "bizSyncLastHeard")
        state = SyncState(); saveState()
        objectWillChange.send()
        log("joined a link code")
        restart()
        return true
    }

    func unlink() {
        stop()
        for k in ["bizSyncTopic", "bizSyncKey", "bizSyncLastID", "bizSyncLastHeard"] { UserDefaults.standard.removeObject(forKey: k) }
        devices = [:]
        objectWillChange.send()
        log("unlinked")
    }

    // MARK: Start / stop

    func startIfLinked() {
        loadState()
        if linked { start() }
    }

    private func restart() { stop(); start() }

    private func start() {
        guard linked, streamTask == nil else { return }
        scan(push: true)
        scanTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in Task { @MainActor in BizSync.shared.scan(push: true) } }
        streamTask = Task { [weak self] in
            var delay: UInt64 = 2
            var first = true
            while !Task.isCancelled {
                guard let self else { return }
                if first {
                    first = false
                    // Been away longer than the relay keeps messages (or never synced)? Ask everyone for everything.
                    let heard = UserDefaults.standard.double(forKey: "bizSyncLastHeard")
                    let stale = Date().timeIntervalSince1970 - heard > 11 * 3600
                    if await self.post(["t": stale ? "hello" : "here"]),
                       stale || UserDefaults.standard.bool(forKey: "bizSyncDirty") {
                        UserDefaults.standard.set(false, forKey: "bizSyncDirty")
                        await self.pushAll(only: true)
                    }
                }
                let ok = await self.listenOnce()
                self.connected = false
                if Task.isCancelled { break }
                delay = ok ? 2 : min(delay * 2, 60)
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }

    private func stop() {
        streamTask?.cancel(); streamTask = nil
        scanTimer?.invalidate(); scanTimer = nil
        connected = false
    }

    /// Something on this Mac saved a sheet — send it soon.
    func changed() {
        guard linked, !applying else { return }
        changeTask?.cancel()
        changeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if !Task.isCancelled { self.scan(push: true) }
        }
    }

    func syncNow() {
        scan(push: true)
        Task { await post(["t": "hello"]) }
    }

    // MARK: Listening

    private func listenOnce() async -> Bool {
        guard let t = topic else { return false }
        let since = UserDefaults.standard.string(forKey: "bizSyncLastID") ?? "12h"
        guard let url = URL(string: "\(Self.relay)/\(t)-biz/json?since=\(since)") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 600
        let began = Date()
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            connected = true
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let d = line.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      o["event"] as? String == "message" else { continue }
                if let id = o["id"] as? String { UserDefaults.standard.set(id, forKey: "bizSyncLastID") }
                if let body = o["message"] as? String { await handle(body) }
            }
        } catch {
            if !Task.isCancelled { log("connection dropped") }
        }
        return Date().timeIntervalSince(began) > 30
    }

    private func handle(_ sealed: String) async {
        guard let o = open(sealed), let id = o["id"] as? String, !seen.contains(id) else { return }
        seen.append(id); if seen.count > 400 { seen.removeFirst(100) }
        guard let from = o["from"] as? String, from != deviceID else { return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "bizSyncLastHeard")
        devices[(o["dev"] as? String) ?? from] = Date()
        switch o["t"] as? String {
        case "hello":
            log("📱 \((o["dev"] as? String) ?? "a device") asked for everything")
            try? await Task.sleep(nanoseconds: UInt64.random(in: 200_000_000...1_500_000_000))
            scan(push: false)
            await pushAll(only: false)
        case "ops":
            guard let sheet = o["sheet"] as? String, Self.sheets.contains(sheet), let ops = o["ops"] as? [[String: Any]] else { return }
            scan(push: true)               // never lose an unsent change on this Mac
            let n = apply(sheet, ops)
            if n > 0 { log("⬇︎ \(n) change\(n == 1 ? "" : "s") to \(sheet) from \((o["dev"] as? String) ?? "a device")"); lastSync = Date() }
        case "cfg":
            guard let c = o["cfg"] as? [String: Any] else { return }
            scan(push: true)
            applyCfg(c)
        default: break
        }
    }

    // MARK: Keys (identical to bizsync.js)

    nonisolated static func rowKey(_ sheet: String, _ r: [String: String]) -> String {
        func get(_ c: String) -> String {
            for (k, v) in r where k.lowercased() == c { return v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            return ""
        }
        func whole() -> String {
            "r|" + r.keys.sorted().map { r[$0]!.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }.joined(separator: "|")
        }
        switch sheet {
        case "Leads", "Clients":
            let d = get("phone").filter { $0.isASCII && $0.isNumber }
            if d.count >= 9 { return "p" + String(d.suffix(9)) }
            let n = get("name")
            return n.isEmpty ? whole() : "n" + n
        default:
            let cols: [String]
            switch sheet {
            case "Team": cols = ["name"]
            case "Listings": cols = ["property id"]
            case "Due": cols = ["client", "for", "due date"]
            case "Appointments": cols = ["date", "time", "client"]
            case "Visits": cols = ["date", "time", "client", "property id"]
            case "Hours": cols = ["date", "name"]
            case "Payroll": cols = ["month", "name"]
            case "Money": cols = ["date", "type", "category", "amount", "party", "method", "note"]
            default: cols = []
            }
            let parts = cols.map(get)
            return parts.allSatisfy(\.isEmpty) ? whole() : "k|" + parts.joined(separator: "|")
        }
    }

    /// Keys for every row of a sheet, numbering repeats ("…#2") so identical rows stay separate.
    nonisolated static func keys(_ sheet: String, _ rows: [[String: String]]) -> [String] {
        var count: [String: Int] = [:]
        return rows.map { r in
            let k = rowKey(sheet, r)
            let n = (count[k] ?? 0) + 1; count[k] = n
            return n == 1 ? k : "\(k)#\(n)"
        }
    }

    /// Rows as {column: value} (empty cells left out), with their line number in the sheet.
    private static func indexed(_ b: ZuffiPA.Book) -> [(Int, [String: String])] {
        var out: [(Int, [String: String])] = []
        for (n, r) in b.rows.enumerated() {
            var o: [String: String] = [:]
            for (i, h) in b.header.enumerated() where i < r.count && !h.isEmpty {
                let v = r[i]
                if !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { o[h] = v }
            }
            if !o.isEmpty { out.append((n, o)) }
        }
        return out
    }
    private static func objects(_ b: ZuffiPA.Book) -> [[String: String]] { indexed(b).map(\.1) }

    private static func canon(_ o: [String: String]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys]) else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    private static func now() -> Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    // MARK: Local changes → ops

    /// Looks at every sheet; anything different from what the others have becomes an op.
    func scan(push: Bool) {
        guard linked, !applying else { return }
        var outgoing: [(String, [[String: Any]])] = []
        let t = Self.now()
        for sheet in Self.sheets {
            let url = ZuffiPA.url(sheet)
            let m = ZuffiBusiness.mtime(url)
            if let m, stamps[sheet] == m, state.sheets[sheet] != nil { continue }
            stamps[sheet] = m
            let rows = m == nil ? [] : Self.objects(ZuffiPA.load(sheet, header: []))
            let keys = Self.keys(sheet, rows)
            var known = state.sheets[sheet] ?? [:]
            var ops: [[String: Any]] = []
            var present = Set<String>()
            for (k, r) in zip(keys, rows) {
                present.insert(k)
                let c = Self.canon(r)
                if known[k]?.j != c {
                    known[k] = SyncState.Row(j: c, at: t)
                    state.tomb[sheet]?[k] = nil
                    ops.append(["k": k, "at": t, "r": r])
                }
            }
            for k in known.keys where !present.contains(k) {
                known[k] = nil
                state.tomb[sheet, default: [:]][k] = t
                ops.append(["k": k, "at": t, "r": NSNull()])
            }
            state.sheets[sheet] = known
            if !ops.isEmpty { outgoing.append((sheet, ops)) }
        }
        // Settings
        var cfgOut: [String: Any] = [:]
        for (k, v) in currentCfg() where state.cfg[k]?.j != v {
            state.cfg[k] = SyncState.Row(j: v, at: t)
            cfgOut[k] = ["v": v, "at": t]
        }
        if outgoing.isEmpty && cfgOut.isEmpty { return }
        saveState()
        guard push else { return }
        Task {
            var ok = true
            for (sheet, ops) in outgoing { ok = await self.sendOps(sheet, ops) && ok }
            if !cfgOut.isEmpty { ok = await self.post(["t": "cfg", "cfg": cfgOut]) && ok }
            if ok { self.lastSync = Date() } else { UserDefaults.standard.set(true, forKey: "bizSyncDirty") }   // offline: send it all later
        }
    }

    /// Sends everything this Mac knows (when someone new joins, or asks).
    private func pushAll(only nonEmpty: Bool) async {
        let cutoff = Self.now() - 90 * 86400_000
        for sheet in Self.sheets {
            var ops: [[String: Any]] = []
            for (k, row) in state.sheets[sheet] ?? [:] {
                guard let d = row.j.data(using: .utf8), let r = try? JSONSerialization.jsonObject(with: d) else { continue }
                ops.append(["k": k, "at": row.at, "r": r])
            }
            for (k, at) in state.tomb[sheet] ?? [:] where at > cutoff { ops.append(["k": k, "at": at, "r": NSNull()]) }
            if ops.isEmpty && nonEmpty { continue }
            if !ops.isEmpty { await sendOps(sheet, ops) }
        }
        let cfg = state.cfg.mapValues { ["v": $0.j, "at": $0.at] as [String: Any] }
        if !cfg.isEmpty { await post(["t": "cfg", "cfg": cfg]) }
    }

    /// Splits big lists so each message stays small for the relay.
    @discardableResult
    private func sendOps(_ sheet: String, _ ops: [[String: Any]]) async -> Bool {
        let msg: [String: Any] = ["t": "ops", "sheet": sheet, "ops": ops]
        if ops.count > 1, (packed(msg)?.count ?? 0) > 3700 {
            let half = ops.count / 2
            let a = await sendOps(sheet, Array(ops[..<half]))
            let b = await sendOps(sheet, Array(ops[half...]))
            return a && b
        }
        return await post(msg)
    }

    // MARK: Ops from other devices → sheets

    private func apply(_ sheet: String, _ ops: [[String: Any]]) -> Int {
        var known = state.sheets[sheet] ?? [:]
        var tomb = state.tomb[sheet] ?? [:]
        var fresh: [(String, [String: String]?)] = []
        for op in ops {
            guard let k = op["k"] as? String, let at = (op["at"] as? NSNumber)?.doubleValue else { continue }
            let mine = max(known[k]?.at ?? 0, tomb[k] ?? 0)
            guard at > mine else { continue }
            if let r = op["r"] as? [String: Any] {
                let row = r.compactMapValues { $0 as? String }
                known[k] = SyncState.Row(j: Self.canon(row), at: at); tomb[k] = nil
                fresh.append((k, row))
            } else {
                if known[k] == nil && tomb[k] != nil { tomb[k] = at; continue }
                known[k] = nil; tomb[k] = at
                fresh.append((k, nil))
            }
        }
        state.sheets[sheet] = known; state.tomb[sheet] = tomb
        guard !fresh.isEmpty else { saveState(); return 0 }

        // Write them into the sheet on disk.
        var b = ZuffiPA.load(sheet, header: Self.defaultHeader(sheet))
        if b.header.isEmpty { b.header = Self.defaultHeader(sheet) }
        for (k, row) in fresh {
            let now = Self.indexed(b)
            let keysNow = Self.keys(sheet, now.map(\.1))
            let at = keysNow.firstIndex(of: k).map { now[$0].0 }
            if let row {
                for col in row.keys where !b.header.contains(col) { b.header.append(col) }
                let line = b.header.map { row[$0] ?? "" }
                if let at { b.rows[at] = line } else { b.rows.append(line) }
            } else if let at {
                b.rows.remove(at: at)
            }
        }
        applying = true
        ZuffiPA.save(sheet, b)
        applying = false
        stamps[sheet] = ZuffiBusiness.mtime(ZuffiPA.url(sheet))
        // What's on disk now is what everyone has (row keys may renumber after a delete of a repeat).
        let rows = Self.objects(ZuffiPA.load(sheet, header: []))
        var settled: [String: SyncState.Row] = [:]
        for (k, r) in zip(Self.keys(sheet, rows), rows) { settled[k] = SyncState.Row(j: Self.canon(r), at: known[k]?.at ?? Self.now()) }
        state.sheets[sheet] = settled
        saveState()
        reloadEverything()
        return fresh.count
    }

    private func reloadEverything() {
        ZuffiCRM.shared.reload()
        ZuffiMoney.shared.reload()
        ZuffiProperties.shared.reload()
    }

    static func defaultHeader(_ sheet: String) -> [String] {
        switch sheet {
        case "Leads": return ZuffiPA.leadHeader
        case "Team": return ZuffiCRM.teamHeader
        case "Money": return ZuffiMoney.moneyHeader
        case "Due": return ZuffiMoney.dueHeader
        case "Hours": return ZuffiMoney.hoursHeader
        case "Payroll": return ZuffiMoney.payrollHeader
        case "Listings": return ZuffiProperties.header
        case "Visits": return ZuffiProperties.visitHeader
        case "Appointments": return ZuffiPA.apptHeader
        case "Clients": return ZuffiPA.clientHeader
        default: return []
        }
    }

    // MARK: Business settings

    private func currentCfg() -> [String: String] {
        let crm = ZuffiCRM.shared
        return ["name": ZuffiBusiness.shared.businessName, "kind": ZuffiBusiness.shared.pack?.rawValue ?? "",
                "country": crm.country, "currency": crm.currencyChoice, "info": crm.businessInfo, "today": crm.todayUpdate]
    }

    private func applyCfg(_ c: [String: Any]) {
        let crm = ZuffiCRM.shared, biz = ZuffiBusiness.shared
        var changed = false
        applying = true
        for k in Self.cfgKeys {
            guard let e = c[k] as? [String: Any], let v = e["v"] as? String, let at = (e["at"] as? NSNumber)?.doubleValue,
                  at > (state.cfg[k]?.at ?? 0) else { continue }
            state.cfg[k] = SyncState.Row(j: v, at: at)
            changed = true
            switch k {
            case "name": biz.businessName = v; UserDefaults.standard.set(v, forKey: "zuffiBusinessName")
            case "kind": if let p = ZuffiBusiness.Pack(rawValue: v) { biz.pack = p; UserDefaults.standard.set(v, forKey: "zuffiPack") }
            case "country": if !v.isEmpty { crm.country = v }
            case "currency": crm.currencyChoice = v
            case "info": if crm.businessInfo != v { crm.businessInfo = v }
            case "today": if crm.todayUpdate != v { crm.todayUpdate = v }
            default: break
            }
        }
        applying = false
        if changed { saveState(); log("⬇︎ business settings updated"); lastSync = Date() }
    }

    // MARK: Relay + encryption (flag byte: 1 = raw DEFLATE, 0 = plain JSON; then AES-GCM)

    private func packed(_ obj: [String: Any]) -> String? {
        guard let key else { return nil }
        var o = obj
        o["v"] = 1; o["from"] = deviceID; o["dev"] = deviceName
        o["id"] = o["id"] ?? UUID().uuidString
        o["at"] = Int(Self.now())
        guard let json = try? JSONSerialization.data(withJSONObject: o) else { return nil }
        var plain = Data([0]) + json
        if let z = try? (json as NSData).compressed(using: .zlib) as Data, z.count < json.count { plain = Data([1]) + z }
        return (try? AES.GCM.seal(plain, using: key))?.combined?.b64url
    }

    @discardableResult
    private func post(_ obj: [String: Any]) async -> Bool {
        guard let t = topic, let body = packed(obj), let url = URL(string: "\(Self.relay)/\(t)-biz") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private func open(_ s: String) -> [String: Any]? {
        guard let key, let d = Data(b64url: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let box = try? AES.GCM.SealedBox(combined: d), let plain = try? AES.GCM.open(box, using: key), let flag = plain.first else { return nil }
        var json = plain.dropFirst()
        if flag == 1 { guard let u = try? (Data(json) as NSData).decompressed(using: .zlib) as Data else { return nil }; json = u[...] }
        return try? JSONSerialization.jsonObject(with: Data(json)) as? [String: Any]
    }

    // MARK: Saved state

    struct SyncState: Codable {
        struct Row: Codable { var j: String; var at: Double }
        var sheets: [String: [String: Row]] = [:]
        var tomb: [String: [String: Double]] = [:]
        var cfg: [String: Row] = [:]
    }
    private static var stateURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zuffi", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("business-sync.json")
    }
    private func loadState() {
        if let d = try? Data(contentsOf: Self.stateURL), let s = try? JSONDecoder().decode(SyncState.self, from: d) { state = s }
    }
    private func saveState() {
        if let d = try? JSONEncoder().encode(state) { try? d.write(to: Self.stateURL, options: .atomic) }
    }

    private func log(_ s: String) {
        appendAppLog("sync.log", s)
        recent.insert("\(ZuffiPA.hm(Date()))  \(s)", at: 0)
        if recent.count > 10 { recent.removeLast() }
    }
}

// MARK: - Dashboard box: "Your phone, tablet and other computers"

struct BizSyncBox: View {
    @ObservedObject private var sync = BizSync.shared
    @State private var showCode = false
    @State private var paste = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "qrcode").foregroundColor(Color(hex: "#F58FA8"))
                Text("Same business on your phone, tablet & other computers").font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                if sync.linked {
                    HStack(spacing: 5) {
                        Circle().fill(sync.connected ? Color(hex: "#34D399") : Color(hex: "#FBBF24")).frame(width: 7, height: 7)
                        Text(sync.connected ? "Live" : "Connecting…").font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 9).frame(height: 22).liquidGlass(Capsule())
                }
            }
            Text("Scan the code with Zuffi on your phone (Business → Devices → Scan). Leads, money, staff, properties and your business info stay the same on every device — change something on one and the others update by themselves.")
                .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
            if !sync.linked {
                HStack(spacing: 8) {
                    Button { sync.create(); showCode = true } label: {
                        Label("Link my phone", systemImage: "qrcode").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "#1A1008"))
                            .padding(.horizontal, 14).frame(height: 31)
                            .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)))
                    }.buttonStyle(.plain)
                    TextField("…or paste a link code from another device", text: $paste).textFieldStyle(.plain)
                        .padding(.horizontal, 12).frame(height: 31).liquidGlass(Capsule())
                        .onSubmit { if sync.join(paste) { paste = "" } }
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    if showCode, let img = PhoneLink.qrImage(sync.pairingURL) {
                        Image(nsImage: img).interpolation(.none).resizable().frame(width: 170, height: 170)
                            .padding(8).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        if sync.devices.isEmpty {
                            Text("No other device yet — scan the code on your phone.").font(.system(size: 11.5)).foregroundColor(.white.opacity(0.6))
                        }
                        ForEach(sync.devices.sorted { $0.value > $1.value }, id: \.key) { d in
                            HStack(spacing: 6) {
                                Image(systemName: d.key.lowercased().contains("mac") ? "laptopcomputer" : "iphone").frame(width: 16)
                                Text(d.key).font(.system(size: 12, weight: .semibold, design: .rounded))
                                Text(d.value.formatted(.relative(presentation: .named))).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5))
                            }
                        }
                        if let l = sync.lastSync { Text("Last change synced \(l.formatted(.relative(presentation: .named)))").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5)) }
                        HStack(spacing: 6) {
                            Button(showCode ? "Hide code" : "Show link code") { showCode.toggle() }.controlSize(.small)
                            Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(sync.pairingURL, forType: .string) }.controlSize(.small)
                            Button("Sync now") { sync.syncNow() }.controlSize(.small)
                            Button("Unlink") { sync.unlink() }.controlSize(.small)
                        }
                        if showCode {
                            Text("Keep this code private — anyone who scans it sees your business data.").font(.system(size: 10)).foregroundColor(Color(hex: "#FBBF24"))
                        }
                        ForEach(sync.recent.prefix(4), id: \.self) { Text($0).font(.system(size: 10, design: .monospaced)).foregroundColor(.white.opacity(0.45)).lineLimit(1) }
                    }
                }
            }
        }
    }
}
