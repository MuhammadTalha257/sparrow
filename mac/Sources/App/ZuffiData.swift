import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Your data (Excel / CSV sheets) and daily messages
//
// Give Zuffi a spreadsheet ("store this data") and it keeps it on this Mac.
// Later just ask: "analyse my sales sheet", "predict next month",
// "what's Ali's number?", "who owes the most?" — Zuffi reads the sheet to answer.
// "Every day at 9am send 'Good morning' to 03001234567 on WhatsApp" sets up a
// daily message that Zuffi sends for you.
// =====================================================================

@MainActor
final class ZuffiData: ObservableObject {
    static let shared = ZuffiData()

    struct Sheet: Identifiable, Codable, Equatable {
        var id: String { file }
        let name: String
        let file: String          // csv file name in the Data folder
        let columns: [String]
        let rows: Int
        let added: Date
    }

    struct Daily: Identifiable, Codable, Equatable {
        var id = UUID().uuidString
        var hour: Int
        var minute: Int
        var to: String            // a number or a contact name
        var text: String
        var lastSent: String = "" // yyyy-MM-dd
    }

    @Published private(set) var sheets: [Sheet] = []
    @Published var dailies: [Daily] = []

    static var folder: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Zuffi/Data", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var indexURL: URL { Self.folder.appendingPathComponent("index.json") }
    private var dailyURL: URL { Self.folder.appendingPathComponent("daily.json") }
    private var timer: Timer?

    private init() {
        if let d = try? Data(contentsOf: indexURL), let s = try? JSONDecoder().decode([Sheet].self, from: d) { sheets = s }
        if let d = try? Data(contentsOf: dailyURL), let s = try? JSONDecoder().decode([Daily].self, from: d) { dailies = s }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in MainActor.assumeIsolated { ZuffiData.shared.checkDaily() } }
    }

    private func saveIndex() { if let d = try? JSONEncoder().encode(sheets) { try? d.write(to: indexURL, options: .atomic) } }
    private func saveDaily() { if let d = try? JSONEncoder().encode(dailies) { try? d.write(to: dailyURL, options: .atomic) } }

    static func isSheet(_ url: URL) -> Bool { ["xlsx", "csv", "tsv", "numbers", "xls"].contains(url.pathExtension.lowercased()) }

    // MARK: Import

    func choose() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [UTType(filenameExtension: "xlsx"), .commaSeparatedText, .tabSeparatedText, UTType(filenameExtension: "csv")].compactMap { $0 }
        p.allowsMultipleSelection = true
        p.message = "Pick spreadsheets for Zuffi to keep"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK else { return }
        Task { for u in p.urls { _ = await importSheet(u) } }
    }

    /// Imports an .xlsx (every sheet) or .csv/.tsv. Returns a short message for the person.
    func importSheet(_ url: URL) async -> String {
        let base = url.deletingPathExtension().lastPathComponent
        var tables: [(String, [[String]])] = []
        switch url.pathExtension.lowercased() {
        case "xlsx":
            tables = await Self.readXLSX(url)
        case "csv", "tsv":
            guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) else { return "I couldn't read \(url.lastPathComponent)." }
            tables = [(base, Self.parseCSV(text, sep: url.pathExtension.lowercased() == "tsv" ? "\t" : ","))]
        default:
            return "Save it as .xlsx or .csv first (in Numbers: File → Export To → Excel), then give it to me."
        }
        var made: [String] = []
        for (sheetName, rowsIn) in tables {
            let rows = rowsIn.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
            guard let header = rows.first, rows.count > 1 else { continue }
            let name = tables.count > 1 ? "\(base) – \(sheetName)" : base
            let file = Self.safe(name) + ".csv"
            let csv = rows.map { $0.map(Self.csvCell).joined(separator: ",") }.joined(separator: "\n")
            try? csv.write(to: Self.folder.appendingPathComponent(file), atomically: true, encoding: .utf8)
            sheets.removeAll { $0.file == file }
            sheets.insert(Sheet(name: name, file: file, columns: header, rows: rows.count - 1, added: Date()), at: 0)
            made.append("\(name) (\(rows.count - 1) rows)")
        }
        saveIndex()
        return made.isEmpty ? "That sheet looks empty." : "Saved to your data: \(made.joined(separator: ", ")). Ask me anything about it."
    }

    func remove(_ s: Sheet) {
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(s.file))
        sheets.removeAll { $0 == s }
        saveIndex()
    }

    func rows(_ s: Sheet) -> [[String]] {
        guard let t = try? String(contentsOf: Self.folder.appendingPathComponent(s.file), encoding: .utf8) else { return [] }
        return Self.parseCSV(t, sep: ",")
    }

    // MARK: Give the AI the data it needs

    /// Sheets the question is about: named, or sharing words with their columns, or any data question.
    func relevant(to q: String) -> [Sheet] {
        guard !sheets.isEmpty else { return [] }
        let l = q.lowercased()
        let named = sheets.filter { l.contains($0.name.lowercased()) || $0.name.lowercased().split(separator: " ").contains { $0.count > 3 && l.contains($0) } }
        if !named.isEmpty { return named }
        let words = Set(l.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 2 })
        let byColumn = sheets.filter { s in s.columns.contains { c in words.contains(c.lowercased()) || words.contains(where: { c.lowercased().contains($0) && $0.count > 3 }) } }
        if !byColumn.isEmpty { return Array(byColumn.prefix(2)) }
        let dataWords = ["sheet", "excel", "data", "spreadsheet", "table", "analy", "predict", "forecast", "trend", "total", "average", "number of", "phone", "customer", "sales", "list", "row", "column", "crore", "lakh", "marla", "kanal", "plot", "bed", "buyer", "listing", "property", "house", "flat", "apartment", "appointment", "client", "booking", "takings", "revenue", "income", "profit", "earn", "owe", "stock", "inventory"]
        return dataWords.contains(where: { l.contains($0) }) ? Array(sheets.prefix(2)) : []
    }

    /// The question plus the sheets it needs (with a few figures worked out), for the AI.
    func augment(_ q: String) -> String {
        let use = relevant(to: q)
        guard !use.isEmpty else { return q }
        var out = "The person keeps these spreadsheets in Zuffi. Use them to answer (analyse, total, compare, find numbers, predict from trends — say briefly how you worked it out).\n"
        var budget = 60_000
        for s in use {
            let r = rows(s)
            guard let header = r.first else { continue }
            out += "\n### Sheet \"\(s.name)\" — \(r.count - 1) rows. Columns: \(header.joined(separator: " | "))\n"
            out += Self.stats(header: header, rows: Array(r.dropFirst()))
            var body = ""
            for row in r.prefix(600) {
                let line = row.joined(separator: " | ") + "\n"
                if body.count + line.count > budget { body += "… (\(r.count) rows in all)\n"; break }
                body += line
            }
            budget -= body.count
            out += body
        }
        return out + "\n\nQuestion: " + q
    }

    static func stats(header: [String], rows: [[String]]) -> String {
        var s = ""
        for (i, h) in header.enumerated() {
            let nums = rows.compactMap { i < $0.count ? Double($0[i].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "£", with: "").replacingOccurrences(of: "Rs", with: "").trimmingCharacters(in: .whitespaces)) : nil }
            guard nums.count >= max(2, rows.count / 2) else { continue }
            let sum = nums.reduce(0, +)
            s += "• \(h): total \(fmt(sum)), average \(fmt(sum / Double(nums.count))), min \(fmt(nums.min()!)), max \(fmt(nums.max()!))\n"
        }
        return s
    }
    private static func fmt(_ d: Double) -> String { d == d.rounded() ? String(Int(d)) : String(format: "%.2f", d) }

    // MARK: Daily messages

    /// "every day at 9am send good morning to 0300… (on whatsapp)" → set up; returns a reply, or nil if it isn't that.
    func handleCommand(_ raw: String) -> String? {
        if let r = ZuffiBusiness.shared.handle(raw) { return r }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let re = #"(?i)^(?:every ?day|daily|each day|roz)\s*(?:at\s*)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?[, ]+(?:send|text|message|whatsapp)\s+[\"“']?(.+?)[\"”']?\s+to\s+(.+?)(?:\s+on\s+whats ?app)?\.?$"#
        guard let rx = try? NSRegularExpression(pattern: re),
              let m = rx.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) else {
            if t.lowercased().range(of: #"(stop|cancel|delete).*(daily|every ?day).*(message|text)"#, options: .regularExpression) != nil {
                let n = dailies.count; dailies = []; saveDaily()
                return n == 0 ? "You don't have any daily messages." : "Stopped \(n) daily message\(n == 1 ? "" : "s")."
            }
            return nil
        }
        func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : (t as NSString).substring(with: m.range(at: i)) }
        var h = Int(g(1)) ?? 9
        let min = Int(g(2)) ?? 0
        let ap = g(3).lowercased()
        if ap == "pm" && h < 12 { h += 12 }
        if ap == "am" && h == 12 { h = 0 }
        let d = Daily(hour: h % 24, minute: min % 60, to: g(5), text: g(4))
        dailies.append(d); saveDaily()
        return "Done — every day at \(String(format: "%02d:%02d", d.hour, d.minute)) I'll send “\(d.text)” to \(d.to) on WhatsApp. Say “stop daily messages” to cancel."
    }

    func removeDaily(_ d: Daily) { dailies.removeAll { $0.id == d.id }; saveDaily() }

    private func checkDaily() {
        ZuffiBusiness.shared.tick()
        let now = Date(), cal = Calendar.current
        let today = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate])
        let h = cal.component(.hour, from: now), m = cal.component(.minute, from: now)
        for i in dailies.indices where dailies[i].lastSent != today {
            let d = dailies[i]
            guard h > d.hour || (h == d.hour && m >= d.minute) else { continue }
            guard h * 60 + m - (d.hour * 60 + d.minute) < 90 else { dailies[i].lastSent = today; continue }   // Mac was asleep: skip, don't spam late
            dailies[i].lastSent = today
            saveDaily()
            Task {
                let r = await WhatsAppAgent.shared.sendScheduled(to: d.to, text: d.text)
                appendAppLog("agents.log", "daily message: \(r)")
                NotificationCenter.default.post(name: .petSay, object: r)
            }
        }
    }

    // MARK: File formats

    static func safe(_ s: String) -> String {
        String(s.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "_" }).trimmingCharacters(in: .whitespaces)
    }
    static func csvCell(_ s: String) -> String {
        s.contains(",") || s.contains("\"") || s.contains("\n") ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    static func parseCSV(_ text: String, sep: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], cell = "", quoted = false
        var it = Array(text).makeIterator()
        var pending: Character? = nil
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() { if n == "\"" { cell.append("\"") } else { quoted = false; pending = n } } else { quoted = false }
                } else { cell.append(c) }
            } else if c == "\"" { quoted = true }
            else if c == sep { row.append(cell); cell = "" }
            else if c == "\n" || c == "\r\n" { row.append(cell); rows.append(row); row = []; cell = "" }
            else if c == "\r" { continue }
            else { cell.append(c) }
        }
        if !cell.isEmpty || !row.isEmpty { row.append(cell); rows.append(row) }
        return rows
    }

    /// .xlsx is a zip of XML files: read the shared strings and each worksheet.
    nonisolated static func unzip(_ url: URL, _ entry: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", url.path, entry]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 && !d.isEmpty ? d : nil
    }

    nonisolated static func readXLSX(_ url: URL) async -> [(String, [[String]])] {
        await Task.detached(priority: .userInitiated) { () -> [(String, [[String]])] in
            let shared = unzip(url, "xl/sharedStrings.xml").map { XLSXShared.parse($0) } ?? []
            var names: [String] = []
            if let wb = unzip(url, "xl/workbook.xml") { names = XLSXNames.parse(wb) }
            var out: [(String, [[String]])] = []
            for i in 1...max(1, min(12, names.count)) {
                guard let d = unzip(url, "xl/worksheets/sheet\(i).xml") else { continue }
                out.append((i <= names.count ? names[i - 1] : "Sheet\(i)", XLSXSheet.parse(d, shared: shared)))
            }
            return out
        }.value
    }
}

// MARK: Tiny XML readers for .xlsx

final class XLSXShared: NSObject, XMLParserDelegate {
    var items: [String] = []; private var cur = ""; private var inT = false; private var inSI = false
    static func parse(_ d: Data) -> [String] { let h = XLSXShared(); let p = XMLParser(data: d); p.delegate = h; p.parse(); return h.items }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if e == "si" { inSI = true; cur = "" } else if e == "t" { inT = true }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inT && inSI { cur += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "t" { inT = false } else if e == "si" { items.append(cur); inSI = false }
    }
}

final class XLSXNames: NSObject, XMLParserDelegate {
    var names: [String] = []
    static func parse(_ d: Data) -> [String] { let h = XLSXNames(); let p = XMLParser(data: d); p.delegate = h; p.parse(); return h.names }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        if e == "sheet", let n = attributes["name"] { names.append(n) }
    }
}

final class XLSXSheet: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [[String]] = []
    private var row: [Int: String] = [:]; private var col = 0; private var type = ""; private var val = ""; private var inV = false; private var inIS = false
    init(shared: [String]) { self.shared = shared }
    static func parse(_ d: Data, shared: [String]) -> [[String]] {
        let h = XLSXSheet(shared: shared); let p = XMLParser(data: d); p.delegate = h; p.parse(); return h.rows
    }
    private static func colIndex(_ ref: String) -> Int {
        var n = 0
        for ch in ref.unicodeScalars { guard ch.value >= 65 && ch.value <= 90 else { break }; n = n * 26 + Int(ch.value - 64) }
        return max(0, n - 1)
    }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        switch e {
        case "row": row = [:]
        case "c": col = Self.colIndex(attributes["r"] ?? ""); type = attributes["t"] ?? ""; val = ""
        case "v": inV = true
        case "is": inIS = true
        case "t": if inIS { inV = true }
        default: break
        }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if inV { val += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        switch e {
        case "v", "t": inV = false
        case "is": inIS = false
        case "c":
            var v = val
            if type == "s", let i = Int(val), i < shared.count { v = shared[i] }
            if type == "b" { v = val == "1" ? "TRUE" : "FALSE" }
            row[col] = v
        case "row":
            if let mx = row.keys.max() { rows.append((0...mx).map { row[$0] ?? "" }) }
        default: break
        }
    }
}

// MARK: - Panel: My data

struct ZuffiDataPanel: View {
    @ObservedObject private var data = ZuffiData.shared
    @State private var note = ""
    @State private var newTime = Date()
    @State private var newTo = ""
    @State private var newText = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                BusinessPackCard()
                Divider().overlay(Color.white.opacity(0.15))
                Button { data.choose() } label: {
                    Label("Add an Excel or CSV sheet", systemImage: "tablecells.badge.ellipsis")
                        .font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "#1A1008"))
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)))
                }.buttonStyle(.plain)
                Text("Then just ask: “analyse my sales”, “predict next month”, “what's Ali's number?”")
                    .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                if !note.isEmpty { Text(note).font(.system(size: 10.5)).foregroundColor(Color(hex: "#7CE0A8")) }
                ForEach(data.sheets) { s in
                    HStack(spacing: 8) {
                        Image(systemName: "tablecells.fill").foregroundColor(Color(hex: "#34D399"))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                            Text("\(s.rows) rows · \(s.columns.prefix(4).joined(separator: ", "))").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                        }
                        Spacer()
                        Button("Analyse") { ask("Analyse my sheet \(s.name): key numbers, trends and anything unusual. Then predict what comes next.") }
                            .buttonStyle(.plain).font(.system(size: 10.5, weight: .bold)).foregroundColor(Color(hex: "#F7C948"))
                        Button { data.remove(s) } label: { Image(systemName: "trash").font(.system(size: 10)) }.buttonStyle(.plain).foregroundColor(.white.opacity(0.4))
                    }
                    .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial).opacity(0.8))
                }
                Divider().overlay(Color.white.opacity(0.15))
                Text("DAILY MESSAGES (WhatsApp)").font(.system(size: 9, weight: .heavy)).kerning(1).foregroundColor(.white.opacity(0.5))
                ForEach(data.dailies) { d in
                    HStack {
                        Text(String(format: "%02d:%02d", d.hour, d.minute)).font(.system(size: 11, weight: .bold, design: .monospaced))
                        Text("“\(d.text)” → \(d.to)").font(.system(size: 11)).lineLimit(1)
                        Spacer()
                        Button { data.removeDaily(d) } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundColor(.white.opacity(0.4))
                    }
                }
                HStack(spacing: 6) {
                    DatePicker("", selection: $newTime, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 80)
                    TextField("Number or name", text: $newTo).textFieldStyle(.roundedBorder).frame(width: 110)
                }
                HStack(spacing: 6) {
                    TextField("Message", text: $newText).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let c = Calendar.current
                        let d = ZuffiData.Daily(hour: c.component(.hour, from: newTime), minute: c.component(.minute, from: newTime), to: newTo, text: newText)
                        guard !newTo.isEmpty, !newText.isEmpty else { return }
                        data.dailies.append(d); newTo = ""; newText = ""
                        ZuffiData.shared.persistDailies()
                    }.controlSize(.small)
                }
            }
        }
    }

    private func ask(_ q: String) {
        let s = AppState.shared
        s.chatHistory.append(ChatMessage(role: .user, content: q))
        s.stateOverride = .thinking
        Task { await AIService.shared.chat(query: q, context: nil, state: s) }
        ZuffiNav.go(.prompt)
    }
}

extension ZuffiData {
    func persistDailies() { if let d = try? JSONEncoder().encode(dailies) { try? d.write(to: ZuffiData.folder.appendingPathComponent("daily.json"), options: .atomic) } }
}
