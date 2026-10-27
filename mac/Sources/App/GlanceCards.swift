import SwiftUI
import AppKit
import IOKit.ps
import Darwin

// =====================================================================
// MARK: - Home cards (like the Glance video): weather, calendar, agents
// plus the glowing notch edge, chat history and the "hey" pop-up.
// =====================================================================

// MARK: Weather — several cities, hourly forecast (Open-Meteo, free, no key)

@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    struct City: Codable, Equatable, Identifiable { var id: String { name }; let name: String; let lat: Double; let lon: Double }
    struct Hour: Identifiable { let id: Int; let time: Date; let temp: Int; let code: Int }
    struct Report { let temp: Int; let code: Int; let hi: Int; let lo: Int; let hours: [Hour]; let at: Date }

    @Published var cities: [City] = []
    @Published var index = 0
    @Published var reports: [String: Report] = [:]
    @Published var adding = false

    private var lastFetch: [String: Date] = [:]

    private init() {
        if let d = UserDefaults.standard.data(forKey: "zuffiCities"), let c = try? JSONDecoder().decode([City].self, from: d) { cities = c }
        Task { await self.bootstrap() }
    }

    var current: City? { cities.isEmpty ? nil : cities[min(index, cities.count - 1)] }

    private func save() { if let d = try? JSONEncoder().encode(cities) { UserDefaults.standard.set(d, forKey: "zuffiCities") } }

    private func bootstrap() async {
        if cities.isEmpty, let here = await Weather.location() {
            cities = [City(name: here.city, lat: here.lat, lon: here.lon)]
            save()
        }
        await refresh()
    }

    func refresh(force: Bool = false) async {
        for c in cities {
            if !force, let t = lastFetch[c.name], Date().timeIntervalSince(t) < 1800 { continue }
            lastFetch[c.name] = Date()
            if let r = await fetch(c) { reports[c.name] = r }
        }
    }

    func add(_ name: String) async -> Bool {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "1")]
        guard let url = comps.url, let j = Self.json(await Self.data(url)), let r = (j["results"] as? [[String: Any]])?.first,
              let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double else { return false }
        let c = City(name: r["name"] as? String ?? name, lat: lat, lon: lon)
        if !cities.contains(c) { cities.append(c); save() }
        index = cities.firstIndex(of: c) ?? index
        if let rep = await fetch(c) { reports[c.name] = rep }
        return true
    }

    func remove(_ c: City) {
        cities.removeAll { $0 == c }; index = 0; save()
    }

    private func fetch(_ c: City) async -> Report? {
        let useF = Locale.current.measurementSystem == .us
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(c.lat)), .init(name: "longitude", value: String(c.lon)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "hourly", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "2"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "temperature_unit", value: useF ? "fahrenheit" : "celsius"),
        ]
        guard let url = comps.url, let j = Self.json(await Self.data(url)), let cur = j["current"] as? [String: Any],
              let t = (cur["temperature_2m"] as? NSNumber)?.doubleValue else { return nil }
        let code = (cur["weather_code"] as? NSNumber)?.intValue ?? 0
        var hours: [Hour] = []
        if let h = j["hourly"] as? [String: Any], let times = h["time"] as? [NSNumber], let temps = h["temperature_2m"] as? [NSNumber],
           let codes = h["weather_code"] as? [NSNumber] {
            let now = Date().timeIntervalSince1970 - 1800
            var n = 0
            for (i, tm) in times.enumerated() where tm.doubleValue >= now && n < 6 && i < temps.count && i < codes.count {
                hours.append(Hour(id: i, time: Date(timeIntervalSince1970: tm.doubleValue), temp: Int(temps[i].doubleValue.rounded()), code: codes[i].intValue))
                n += 1
            }
        }
        let d = j["daily"] as? [String: Any]
        let hi = ((d?["temperature_2m_max"] as? [NSNumber])?.first?.doubleValue).map { Int($0.rounded()) } ?? Int(t)
        let lo = ((d?["temperature_2m_min"] as? [NSNumber])?.first?.doubleValue).map { Int($0.rounded()) } ?? Int(t)
        return Report(temp: Int(t.rounded()), code: code, hi: hi, lo: lo, hours: hours, at: Date())
    }

    nonisolated static func data(_ url: URL) async -> Data? {
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Zuffi", forHTTPHeaderField: "User-Agent")
        guard let (d, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return d
    }
    static func json(_ d: Data?) -> [String: Any]? { d.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } }

    static func symbol(_ code: Int, night: Bool = false) -> String {
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
    static func isNight(_ d: Date) -> Bool { let h = Calendar.current.component(.hour, from: d); return h < 6 || h >= 19 }
}

struct WeatherCard: View {
    @ObservedObject var w = WeatherStore.shared
    @State private var newCity = ""

    var body: some View {
        GlanceCard(tint: "#4FA7FF") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill").font(.system(size: 8))
                    Text(w.current?.name ?? "Weather").font(.system(size: 11, weight: .bold, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 2)
                    if w.cities.count > 1 {
                        HStack(spacing: 3) {
                            ForEach(w.cities.indices, id: \.self) { i in
                                Circle().fill(Color.white.opacity(i == w.index ? 0.9 : 0.3)).frame(width: 4, height: 4)
                                    .onTapGesture { w.index = i }
                            }
                        }
                    }
                    Button { w.adding.toggle() } label: { Image(systemName: w.adding ? "xmark" : "plus").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).help("Add a city")
                }
                .foregroundColor(.white.opacity(0.85))
                if w.adding {
                    TextField("City name", text: $newCity)
                        .textFieldStyle(.plain).font(.system(size: 11))
                        .padding(6).background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.3)))
                        .onSubmit {
                            let n = newCity; newCity = ""
                            Task { if await w.add(n) { w.adding = false } }
                        }
                    if let c = w.current, w.cities.count > 1 {
                        Button("Remove \(c.name)") { w.remove(c) }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    }
                } else if let c = w.current, let r = w.reports[c.name] {
                    HStack(alignment: .center, spacing: 8) {
                        Image(systemName: WeatherStore.symbol(r.code, night: WeatherStore.isNight(Date())))
                            .symbolRenderingMode(.multicolor).font(.system(size: 26))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(r.temp)°").font(.system(size: 26, weight: .bold, design: .rounded))
                            Text("H \(r.hi)°  L \(r.lo)°").font(.system(size: 9.5, weight: .medium)).foregroundColor(.white.opacity(0.6))
                        }
                    }
                    HStack(spacing: 0) {
                        ForEach(r.hours) { h in
                            VStack(spacing: 2) {
                                Text(h.time.formatted(.dateTime.hour(.defaultDigits(amPM: .narrow)))).font(.system(size: 8.5)).foregroundColor(.white.opacity(0.55))
                                Image(systemName: WeatherStore.symbol(h.code, night: WeatherStore.isNight(h.time))).symbolRenderingMode(.multicolor).font(.system(size: 10))
                                Text("\(h.temp)°").font(.system(size: 9.5, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else {
                    Text("Loading the weather…").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                    Spacer(minLength: 0)
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 12).onEnded { v in
            guard w.cities.count > 1 else { return }
            w.index = (w.index + (v.translation.width < 0 ? 1 : w.cities.count - 1)) % w.cities.count
        })
        .task { await w.refresh() }
    }
}

// MARK: Calendar — month grid, today's events, New event

struct CalendarCard: View {
    @State private var events: [Planner.EItem] = []
    @State private var adding = false
    @State private var text = ""
    @State private var note = ""
    private let cal = Calendar.current

    var body: some View {
        GlanceCard(tint: "#F4505E") {
            HStack(alignment: .top, spacing: 10) {
                monthGrid.frame(width: 118)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Date().formatted(.dateTime.weekday(.wide))).font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "#F4505E"))
                    if adding {
                        TextField("Lunch with Sara tomorrow 1pm", text: $text)
                            .textFieldStyle(.plain).font(.system(size: 10.5))
                            .padding(5).background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3)))
                            .onSubmit {
                                let t = text; text = ""
                                Task { note = await Planner.shared.quickAdd(t); adding = false; load() }
                            }
                    } else {
                        let upcoming = events.filter { $0.end > Date() }.prefix(3)
                        if upcoming.isEmpty {
                            Text(note.isEmpty ? "Nothing else today" : note).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)).lineLimit(2)
                        }
                        ForEach(Array(upcoming)) { e in
                            HStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: e.color)).frame(width: 3, height: 22)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(e.title).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                                    Text(e.allDay ? "All day" : e.start.formatted(.dateTime.hour().minute())).font(.system(size: 9)).foregroundColor(.white.opacity(0.55))
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Button { adding.toggle() } label: {
                        Label(adding ? "Cancel" : "New event", systemImage: adding ? "xmark" : "plus")
                            .font(.system(size: 10, weight: .bold, design: .rounded)).foregroundColor(.white)
                            .padding(.horizontal, 8).frame(height: 20).background(Capsule().fill(Color(hex: "#F4505E").opacity(0.75)))
                    }.buttonStyle(.plain)
                }
            }
        }
        .onAppear { load() }
        .onTapGesture(count: 2) { TodayWindow.shared.show() }
    }

    private func load() {
        events = Planner.shared.eventItems(from: Date(), days: 1)
    }

    private var monthGrid: some View {
        let today = Date()
        let comps = cal.dateComponents([.year, .month], from: today)
        let first = cal.date(from: comps) ?? today
        let days = cal.range(of: .day, in: .month, for: today)?.count ?? 30
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let cells: [Int?] = Array(repeating: nil, count: lead) + (1...days).map { Optional($0) }
        let day = cal.component(.day, from: today)
        let symbols = cal.veryShortWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        return VStack(alignment: .leading, spacing: 2) {
            Text(today.formatted(.dateTime.month(.wide))).font(.system(size: 10.5, weight: .bold, design: .rounded))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 2), count: 7), spacing: 1) {
                ForEach(0..<7, id: \.self) { i in Text(ordered[i]).font(.system(size: 7, weight: .bold)).foregroundColor(.white.opacity(0.4)) }
                ForEach(cells.indices, id: \.self) { i in
                    if let d = cells[i] {
                        Text("\(d)").font(.system(size: 7.5, weight: d == day ? .heavy : .regular))
                            .foregroundColor(d == day ? .white : .white.opacity(d < day ? 0.35 : 0.75))
                            .frame(width: 14, height: 12)
                            .background(Circle().fill(d == day ? Color(hex: "#F4505E") : .clear).frame(width: 13, height: 13))
                    } else { Color.clear.frame(width: 14, height: 12) }
                }
            }
        }
    }
}

// MARK: Agents mini card for Home

struct AgentsMiniCard: View {
    @ObservedObject var hub = AgentHub.shared
    var body: some View {
        GlanceCard(tint: "#F28A3C") {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles").foregroundColor(Color(hex: "#F7C948"))
                    Text("Agents").font(.system(size: 11, weight: .bold, design: .rounded))
                    Spacer()
                    if !hub.approvals.isEmpty {
                        Text("\(hub.approvals.count)").font(.system(size: 9.5, weight: .heavy)).foregroundColor(.black)
                            .padding(.horizontal, 5).background(Capsule().fill(Color(hex: "#F7C948")))
                    }
                }
                if let a = hub.approvals.first {
                    Text("\(a.project) needs you").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(a.detail).font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.7)).lineLimit(2)
                } else if let s = hub.working {
                    Text("\(s.tool) · \(s.project)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    if let st = s.startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { tl in
                            Text("Working… \(Int(tl.date.timeIntervalSince(st)))s").font(.system(size: 10.5)).foregroundColor(Color(hex: "#7CC4FF"))
                        }
                    }
                    Text(s.lastStep).font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                } else if let s = hub.sessions.first {
                    Text("\(s.tool) · \(s.project)").font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(s.lastReply.isEmpty ? "Ready" : s.lastReply).font(.system(size: 10)).foregroundColor(.white.opacity(0.7)).lineLimit(3)
                } else {
                    Text("Claude Code, Codex and GitHub show up here.").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                if let l = (hub.claudeLimits.first ?? hub.codexLimits.first) {
                    Text("\(l.label): \(Int(100 - l.usedPercent))% left").font(.system(size: 9.5, weight: .semibold)).foregroundColor(.white.opacity(0.55))
                }
            }
        }
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { AppState.shared.view = .agents } }
    }
}

struct GlanceCard<Content: View>: View {
    var tint: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: tint).opacity(0.22), Color.white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 0.7))
            .contentShape(Rectangle())
    }
}

/// Home: the bunny saying hi, then weather, calendar and agents side by side.
struct GlanceHomeView: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 8) {
            TalkCard().frame(width: 118)
            WeatherCard().frame(width: 150)
            CalendarCard().frame(width: 204)
            AgentsMiniCard()
        }
        .padding(.vertical, 2)
    }
}

/// Tap the bunny (or the mic) to talk.
struct TalkCard: View {
    @StateObject private var sprite = SparrowSpriteModel()
    @ObservedObject private var voice = VoiceEngine.shared
    private var listening: Bool { voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) }
    var body: some View {
        GlanceCard(tint: "#E2648A") {
            VStack(spacing: 4) {
                LiveBunnyFace(size: 74, mood: listening ? .listening : nil)
                    .contentShape(Rectangle()).onTapGesture { VoiceEngine.shared.listenOnce() }
                    .frame(height: 76)
                Text(listening ? (voice.heard.isEmpty ? "Listening…" : "“\(voice.heard)”") : "Say “Zuffi…”")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded)).lineLimit(2).multilineTextAlignment(.center)
                Button { VoiceEngine.shared.listenOnce() } label: {
                    Label("Talk", systemImage: listening ? "waveform" : "mic.fill")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "#1A1008"))
                        .padding(.horizontal, 10).frame(height: 22)
                        .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)))
                }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Chat history (kept on this Mac)

@MainActor
final class ChatArchive: ObservableObject {
    static let shared = ChatArchive()
    struct Chat: Codable, Identifiable { let id: String; let title: String; let date: Date; let messages: [[String: String]]; var with: String? = nil }
    @Published private(set) var chats: [Chat] = []
    private var url: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Zuffi")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("chats.json")
    }
    private init() {
        if let d = try? Data(contentsOf: url), let c = try? JSONDecoder().decode([Chat].self, from: d) { chats = c }
    }
    func archive(_ msgs: [ChatMessage]) {
        guard !msgs.isEmpty else { return }
        let first = msgs.first { $0.role == .user }?.content ?? msgs[0].content
        let title = String(first.prefix(60))
        chats.insert(Chat(id: UUID().uuidString, title: title, date: Date(),
                          messages: msgs.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }, with: ZuffiChat.shared.whoTitle), at: 0)
        if chats.count > 200 { chats.removeLast(chats.count - 200) }
        save()
    }
    func delete(_ c: Chat) { chats.removeAll { $0.id == c.id }; save() }
    func open(_ c: Chat) {
        let s = AppState.shared
        s.newChat()
        s.chatHistory = c.messages.map { ChatMessage(role: $0["role"] == "user" ? .user : .assistant, content: $0["content"] ?? "") }
        delete(c)          // it's the live chat again; New chat files it back
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { s.view = .prompt }
    }
    private func save() { if let d = try? JSONEncoder().encode(chats) { try? d.write(to: url, options: .atomic) } }
}

struct HistoryIslandView: View {
    @ObservedObject var archive = ChatArchive.shared
    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                TextField("Search your chats", text: $search).textFieldStyle(.plain).font(.system(size: 11.5))
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            let list = archive.chats.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains { ($0["content"] ?? "").localizedCaseInsensitiveContains(search) } }
            if list.isEmpty {
                Text(archive.chats.isEmpty ? "Your past chats appear here after you start a New chat." : "No chats match.")
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).padding(.top, 6)
                Spacer(minLength: 0)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(list) { c in
                            HStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 10)).foregroundColor(Color(hex: "#F9A830"))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                                    Text("\(c.date.formatted(.relative(presentation: .named))) · \(c.messages.count) messages").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.5))
                                }
                                Spacer()
                                Button { archive.delete(c) } label: { Image(systemName: "trash").font(.system(size: 9.5)) }
                                    .buttonStyle(.plain).foregroundColor(.white.opacity(0.4))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)))
                            .contentShape(Rectangle())
                            .onTapGesture { archive.open(c) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Glowing notch edge (charging, Caps Lock, Shift, Cut, needs you, auto-approve)

@MainActor
final class EdgeGlow: ObservableObject {
    static let shared = EdgeGlow()

    enum Kind: Equatable {
        case charging(Int), battery(Int), capsLock, shift, cut, copied, needsYou, autoApprove, done, notify(String), music(String)
        /// Big moments light up the open island too; key presses only show when it's closed.
        var showsWhenOpen: Bool { switch self { case .charging, .battery, .notify, .music, .needsYou, .done: return true; default: return false } }
        var color: Color {
            switch self {
            case .notify: return IslandConst.accent
            case .music: return Color(hex: "#F472B6")
            case .charging, .autoApprove, .done: return Color(hex: "#34D399")
            case .battery(let p): return p <= 20 ? Color(hex: "#F4505E") : Color(hex: "#34D399")
            case .capsLock, .shift: return Color(hex: "#7CC4FF")
            case .cut: return Color(hex: "#F4505E")
            case .copied: return Color(hex: "#A78BFA")
            case .needsYou: return Color(hex: "#F7C948")
            }
        }
        var icon: String {
            switch self {
            case .charging: return "bolt.fill"; case .battery: return "battery.75"
            case .capsLock: return "capslock.fill"; case .shift: return "shift.fill"
            case .cut: return "scissors"; case .copied: return "doc.on.doc.fill"
            case .needsYou: return "sparkles"; case .autoApprove: return "checkmark.seal.fill"; case .done: return "checkmark.circle.fill"
            case .notify: return "bell.fill"; case .music: return "music.note"
            }
        }
        var text: String {
            switch self {
            case .charging(let p): return "Charging \(p)%"; case .battery(let p): return "On battery \(p)%"
            case .capsLock: return "Caps Lock"; case .shift: return "Shift"
            case .cut: return "Cut"; case .copied: return "Copied"
            case .needsYou: return "Needs you"; case .autoApprove: return "Auto-approved"; case .done: return "Done"
            case .notify(let t): return String(t.prefix(28)); case .music(let t): return String(t.prefix(28))
            }
        }
    }

    @Published private(set) var kind: Kind?
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "edgeGlow") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "edgeGlow"); if !enabled { panel?.orderOut(nil) } }
    }
    private var sticky: Kind?
    private var flashUntil = Date.distantPast
    private var panel: NSPanel?
    private var timer: Timer?
    private var lastPower: Bool?
    private var lastChange = NSPasteboard.general.changeCount
    private var xDownAt = Date.distantPast
    private var shiftSince: Date?
    private var caps = false
    private var powerTick = 0

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { _ in MainActor.assumeIsolated { EdgeGlow.shared.tick() } }
    }

    /// Something that stays until cleared (Needs you).
    func set(_ k: Kind?) { sticky = k; render() }
    /// A short glow (Done, Cut, charger plugged in…).
    func flash(_ k: Kind, seconds: Double = 2.2) {
        guard enabled else { return }
        flashKind = k; flashUntil = Date().addingTimeInterval(seconds); render()
    }
    private var flashKind: Kind?

    private func tick() {
        guard enabled else { return }
        // Caps Lock / Shift
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let capsNow = flags.contains(.maskAlphaShift)
        if capsNow != caps { caps = capsNow; render() }
        if flags.contains(.maskShift) && !flags.contains(.maskCommand) {
            if shiftSince == nil { shiftSince = Date() }
            if let s = shiftSince, Date().timeIntervalSince(s) > 0.45, flashKind != .shift || Date() > flashUntil.addingTimeInterval(-0.5) { flash(.shift, seconds: 0.6) }
        } else { shiftSince = nil }
        // Cut / Copy
        if CGEventSource.keyState(.combinedSessionState, key: 7) && flags.contains(.maskCommand) { xDownAt = Date() }   // ⌘X
        let pb = NSPasteboard.general.changeCount
        if pb != lastChange {
            lastChange = pb
            if Date().timeIntervalSince(xDownAt) < 1.2 { flash(.cut, seconds: 1.4) }
            else if flags.contains(.maskCommand) { flash(.copied, seconds: 1.2) }
        }
        // Charger (checked every ~4 s, not every tick)
        powerTick += 1
        if powerTick % 32 == 0, let pw = Self.power() {
            if let was = lastPower, was != pw.0 { flash(pw.0 ? .charging(pw.1) : .battery(pw.1), seconds: 3) }
            lastPower = pw.0
        }
        if flashKind != nil && Date() > flashUntil { flashKind = nil; render() }
    }

    private func render() {
        let k: Kind? = (Date() <= flashUntil ? flashKind : nil) ?? sticky ?? (caps ? .capsLock : nil)
        if k != kind { kind = k }
        guard enabled else { return }
        if k != nil && AppState.shared.mode == .hidden { show() } else { panel?.orderOut(nil) }
    }

    private func show() {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let st = AppState.shared
        let w = st.notchWidth + 300, h = max(st.notchHeight, 24) + 30
        let frame = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        if panel == nil {
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: EdgeGlowView(glow: self))
            panel = p
        }
        panel?.setFrame(frame, display: true)
        panel?.orderFrontRegardless()
    }

    nonisolated static func power() -> (Bool, Int)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let pct = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            return (d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue, pct)
        }
        return nil
    }
}

struct EdgeGlowView: View {
    @ObservedObject var glow: EdgeGlow
    var body: some View {
        let st = AppState.shared
        let nw = st.hasNotch ? st.notchWidth : 180, nh = st.hasNotch ? st.notchHeight : 6
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let pulse = 0.65 + 0.35 * sin(t * 4)
            ZStack(alignment: .top) {
                if let k = glow.kind {
                    NotchOutline(width: nw + 6, height: nh + 3)
                        .stroke(k.color, lineWidth: 2.5)
                        .shadow(color: k.color.opacity(pulse), radius: 8)
                        .shadow(color: k.color.opacity(0.6 * pulse), radius: 16)
                        .frame(width: nw + 6, height: nh + 3)
                    if k == .needsYou {
                        ForEach(0..<7, id: \.self) { i in
                            let a = t * 1.6 + Double(i) * 0.9
                            Image(systemName: "sparkle").font(.system(size: CGFloat(6 + (i % 3) * 3)))
                                .foregroundColor(Color(hex: "#F7C948"))
                                .opacity(0.4 + 0.6 * abs(sin(a)))
                                .offset(x: CGFloat(cos(a * 0.7)) * (nw / 2 + 14), y: nh + 4 + CGFloat(abs(sin(a))) * 12)
                        }
                    }
                    HStack(spacing: 4) {
                        Image(systemName: k.icon).font(.system(size: 10, weight: .bold))
                        Text(k.text).font(.system(size: 10.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(k.color)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(Color.black.opacity(0.82)))
                    .overlay(Capsule().stroke(k.color.opacity(0.6), lineWidth: 1))
                    .offset(x: nw / 2 + 62, y: max(2, (nh - 20) / 2))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.easeOut(duration: 0.25), value: glow.kind)
    }
}

/// The notch's own outline: straight sides down from the top, rounded bottom corners.
struct NotchOutline: Shape {
    var width: CGFloat, height: CGFloat
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = min(10, height / 2)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

// MARK: - "Hey!" — the bunny pops up when Zuffi opens

@MainActor
final class ZuffiHello {
    static let shared = ZuffiHello()
    private var panel: NSPanel?
    let model = HelloModel()

    func show() {
        // Only the notch says hi: a small note from Aurora, then it folds away.
        let name = AssistantPrefs.displayName
        let st = AppState.shared
        st.noteIsAlert = false; st.noteAction = nil
        st.noteMessage = "Zuffi · Aurora\nHi\(name.isEmpty ? "" : " \(name)")! I'm here whenever you need me. Say \u{201C}Hey Zuffi\u{201D} or click the notch."
        BunnyFaceCenter.shared.show(.happy, for: 5)
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        SoundEngine.shared.play("greet")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            MainActor.assumeIsolated { if AppState.shared.view == .note { NotificationCenter.default.post(name: .islandCollapse, object: nil) } }
        }
    }

    func showOld() {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
        let size = NSSize(width: 260, height: 300)
        let f = NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - 34, width: size.width, height: size.height)
        let p = panel ?? {
            let p = NSPanel(contentRect: f, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.ignoresMouseEvents = true
            p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: HelloView(model: model))
            return p
        }()
        panel = p
        p.setFrame(f, display: true)
        p.alphaValue = 1
        p.orderFrontRegardless()
        model.phase = 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { model.phase = 1 }
        SoundEngine.shared.play("greet")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            MainActor.assumeIsolated {
                let me = ZuffiHello.shared
                withAnimation(.easeIn(duration: 0.4)) { me.model.phase = 2 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    MainActor.assumeIsolated {
                        me.panel?.orderOut(nil)
                        // then the island opens on Home, with the tabs
                        NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview)
                    }
                }
            }
        }
    }
}

@MainActor
final class HelloModel: ObservableObject { @Published var phase = 0 }   // 0 hidden · 1 out saying hey · 2 tucking into the notch

struct HelloView: View {
    @ObservedObject var model: HelloModel
    @State private var wave = false

    var body: some View {
        let name = AssistantPrefs.displayName
        VStack(spacing: 8) {
            Text(name.isEmpty ? "Hey! 👋" : "Hey \(name)! 👋")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: "#3A2330"))
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.25), radius: 8, y: 3))
                .scaleEffect(model.phase == 1 ? 1 : 0.2, anchor: .bottom)
                .opacity(model.phase == 1 ? 1 : 0)
            Group {
                Aurora3DView(pose: .happy, lookAtMouse: false).frame(width: 200, height: 210)
            }
            .rotationEffect(.degrees(wave ? 6 : -6), anchor: .bottom)
            .animation(.easeInOut(duration: 0.28).repeatCount(6, autoreverses: true), value: wave)
            .scaleEffect(model.phase == 1 ? 1 : 0.15, anchor: .top)
            .offset(y: model.phase == 2 ? -260 : 0)
            .opacity(model.phase == 0 ? 0 : 1)
        }
        .frame(width: 260, height: 300, alignment: .top)
        .onChange(of: model.phase) { _, p in if p == 1 { wave.toggle() } }
    }
}


// =====================================================================
// MARK: - Mac status at the notch (battery, your devices, CPU / memory / disk) + small notifications
// One look up: the Mac's battery, AirPods / Magic keyboard & mouse batteries, and how busy the Mac is.
// Small notch notifications: new email, plugged in / fully charged / low battery, a device connecting.
// They fold away by themselves and never pop up over something you're doing in Zuffi.
// =====================================================================
@MainActor
final class MacStatus: ObservableObject {
    static let shared = MacStatus()
    struct Device: Identifiable, Equatable {
        var id: String { name }
        let name: String; let kind: String
        let main: Int?; let left: Int?; let right: Int?; let caseLevel: Int?
        var lowest: Int? { [main, left, right].compactMap { $0 }.min() }
        var summary: String {
            if left != nil || right != nil { return [left.map { "L \($0)%" }, right.map { "R \($0)%" }, caseLevel.map { "case \($0)%" }].compactMap { $0 }.joined(separator: " · ") }
            return main.map { "\($0)%" } ?? "connected"
        }
        var icon: String {
            let n = name.lowercased()
            if n.contains("airpods max") { return "airpodsmax" }
            if n.contains("airpods pro") { return "airpodspro" }
            if n.contains("airpods") { return "airpods" }
            if n.contains("keyboard") { return "keyboard" }
            if n.contains("mouse") { return "magicmouse" }
            if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
            return kind.lowercased().contains("head") ? "headphones" : "dot.radiowaves.left.and.right"
        }
    }
    @Published var battery: Int?
    @Published var charging = false
    @Published var plugged = false
    @Published var minutesLeft: Int?
    @Published var devices: [Device] = []
    @Published var cpu = 0
    @Published var memory = 0
    @Published var diskFreeGB = 0

    var toastsOn: Bool {
        get { UserDefaults.standard.object(forKey: "notchToasts") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "notchToasts"); objectWillChange.send() }
    }
    private var timer: Timer?
    private var n = 0
    private var knownDevices: Set<String>?
    private var knownMail: Set<String>?
    private var warned: Set<Int> = []
    private var toldFull = false
    private var wasPlugged: Bool?
    private var prevTicks: [Double]?

    func start() {
        guard timer == nil else { return }
        refreshPower(); refreshSystem()
        Task { await refreshDevices() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in MainActor.assumeIsolated { MacStatus.shared.tick() } }
    }
    private func tick() {
        n += 1
        refreshPower(); refreshSystem()
        if n % 4 == 0 { Task { await self.refreshDevices() } }
        if n % 3 == 2 { Task { await self.checkMail() } }   // about every 45 s
    }

    // ---- battery ----
    func refreshPower() {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0, mx = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let pct = mx > 0 ? Int((Double(cur) / Double(mx) * 100).rounded()) : cur
            let chg = d[kIOPSIsChargingKey] as? Bool ?? false
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let m = (chg ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
            battery = pct; charging = chg; plugged = onAC; minutesLeft = m > 0 ? m : nil
            notifyPower(pct: pct, onAC: onAC)
            return
        }
    }
    private func notifyPower(pct: Int, onAC: Bool) {
        defer { wasPlugged = onAC }
        if onAC { warned = [] }
        if let was = wasPlugged, was != onAC {
            if onAC { toast("Battery · charging", "\(pct)%\(minutesLeft.map { " — about \(Self.hm($0)) to full" } ?? "")", icon: "battery") }
            else { toast("Battery · on battery", "\(pct)%\(minutesLeft.map { " — about \(Self.hm($0)) left" } ?? "")", icon: "battery") }
        }
        if onAC && pct >= 100 && !toldFull { toldFull = true; toast("Battery · fully charged", "100% — you can unplug.", icon: "battery") }
        if pct < 95 { toldFull = false }
        for level in [20, 10] where !onAC && pct <= level && !warned.contains(level) {
            warned.insert(level)
            toast("Battery · \(pct)% left", minutesLeft.map { "About \(Self.hm($0)) — time to plug in." } ?? "Time to plug in.", icon: "battery")
            break
        }
    }
    static func hm(_ m: Int) -> String { m >= 60 ? "\(m / 60) h\(m % 60 > 0 ? " \(m % 60) min" : "")" : "\(m) min" }

    // ---- AirPods, Magic keyboard / mouse / trackpad ----
    func refreshDevices() async {
        let out: String = await Task.detached {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
        guard let j = (try? JSONSerialization.jsonObject(with: Data(out.utf8))) as? [String: Any],
              let top = (j["SPBluetoothDataType"] as? [[String: Any]])?.first else { return }
        let pct: (Any?) -> Int? = { ($0 as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) } }
        var list: [Device] = []
        for entry in (top["device_connected"] as? [[String: Any]]) ?? [] {
            for (name, v) in entry {
                guard let d = v as? [String: Any] else { continue }
                list.append(Device(name: name, kind: d["device_minorType"] as? String ?? "",
                                   main: pct(d["device_batteryLevelMain"]), left: pct(d["device_batteryLevelLeft"]),
                                   right: pct(d["device_batteryLevelRight"]), caseLevel: pct(d["device_batteryLevelCase"])))
            }
        }
        let names = Set(list.map(\.name))
        if let known = knownDevices {
            for d in list where !known.contains(d.name) { toast("\(d.name) · connected", d.summary, icon: d.icon) }
            for d in list where (d.lowest ?? 100) <= 10 && devices.first(where: { $0.name == d.name })?.lowest ?? 100 > 10 {
                toast("\(d.name) · low battery", d.summary, icon: d.icon)
            }
        }
        knownDevices = names
        devices = list
    }

    // ---- how busy the Mac is ----
    func refreshSystem() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if kr == KERN_SUCCESS {
            let t = info.cpu_ticks
            let now = [Double(t.0), Double(t.1), Double(t.2), Double(t.3)]   // user, system, idle, nice
            if let p = prevTicks {
                let busy = (now[0] - p[0]) + (now[1] - p[1]) + (now[3] - p[3]), idle = now[2] - p[2]
                if busy + idle > 0 { cpu = Int((busy / (busy + idle) * 100).rounded()) }
            }
            prevTicks = now
        }
        var vm = vm_statistics64()
        var c2 = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let k2 = withUnsafeMutablePointer(to: &vm) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(c2)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &c2) } }
        if k2 == KERN_SUCCESS {
            let page = Double(getpagesize())
            let used = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
            memory = Int((used / Double(ProcessInfo.processInfo.physicalMemory) * 100).rounded())
        }
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let free = v.volumeAvailableCapacityForImportantUsage { diskFreeGB = Int(free / 1_000_000_000) }
    }

    // ---- new email (only while the Mail app is open; nothing is sent anywhere) ----
    func checkMail() async {
        guard toastsOn, !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.mail").isEmpty else { return }
        let r = await MailAgent.shared.inbox(limit: 5)
        guard let mails = r["mails"] as? [[String: Any]] else { return }
        let ids = Set(mails.compactMap { $0["id"] as? String })
        // Every new email (Gmail, Outlook, iCloud… — every account added to Mail) shows at the notch.
        if let known = knownMail {
            let fresh = mails.filter { !known.contains($0["id"] as? String ?? "") }
            if let m = fresh.first {
                AppState.shared.noteRef = m["id"] as? String
                if fresh.count == 1 {
                    toast("Mail · \(m["from"] as? String ?? "New email")", m["subject"] as? String ?? "", icon: "envelope", action: "mail")
                } else {
                    let who = fresh.prefix(3).compactMap { $0["from"] as? String }.joined(separator: ", ")
                    toast("Mail · \(fresh.count) new emails", "From \(who)\(fresh.count > 3 ? " and more" : "") — newest: \(m["subject"] as? String ?? "")", icon: "envelope", action: "mail")
                }
            }
        }
        knownMail = (knownMail ?? []).union(ids)
    }

    /// A small notification at the notch. Skipped while you're using Zuffi, recording notes, or if you turned them off.
    func toast(_ head: String, _ body: String, icon: String, action: String? = nil) {
        guard toastsOn, !MeetingNotes.shared.active else { return }
        let st = AppState.shared
        if st.mode == .expanded && st.view != .note { return }
        st.noteIsAlert = false
        st.noteAction = action
        st.noteMessage = "\(String(head.prefix(58)))\n\(body)"
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        BunnyFaceCenter.shared.show(.surprised, for: 2.5)
        NotchInbox.shared.add(String(head.prefix(58)), body, icon: icon, action: action)
        if !head.lowercased().contains("charg") && !head.lowercased().contains("battery") { EdgeGlow.shared.flash(.notify(head), seconds: 2.6) }
    }
}

/// Home panel: battery, weather, your devices and the Mac's load — one row, details on hover.
struct StatusChips: View {
    @ObservedObject private var st = MacStatus.shared
    @ObservedObject private var weather = WeatherStore.shared
    var body: some View {
        HStack(spacing: 5) {
            if let b = st.battery {
                chip(st.charging ? "battery.100percent.bolt" : b > 70 ? "battery.100percent" : b > 40 ? "battery.75percent" : b > 20 ? "battery.25percent" : "battery.0percent",
                     "\(b)%", tint: b <= 20 && !st.plugged ? Color(hex: "#FF6B6B") : st.charging ? Color(hex: "#3DDC97") : .white)
                    .help("\(b)%\(st.charging ? " · charging" : st.plugged ? " · plugged in" : "")\(st.minutesLeft.map { st.charging ? " · \(MacStatus.hm($0)) to full" : " · \(MacStatus.hm($0)) left" } ?? "")")
            }
            if let c = weather.current, let r = weather.reports[c.name] {
                chip(WeatherStore.symbol(r.code, night: WeatherStore.isNight(Date())), "\(r.temp)°", tint: .white).help("\(c.name): \(r.temp)°, high \(r.hi)° low \(r.lo)°")
            }
            ForEach(st.devices.filter { $0.lowest != nil }.prefix(2)) { d in
                chip(d.icon, "\(d.lowest ?? 0)%", tint: (d.lowest ?? 100) <= 15 ? Color(hex: "#FF6B6B") : .white).help("\(d.name): \(d.summary)")
            }
            chip("cpu", "\(st.cpu)%", tint: st.cpu > 85 ? Color(hex: "#FFB547") : .white)
                .help("Processor \(st.cpu)% · memory \(st.memory)% · \(st.diskFreeGB) GB free")
        }
        .onAppear { MacStatus.shared.start() }
    }
    private func chip(_ icon: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9.5, weight: .semibold))
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundColor(tint.opacity(0.9))
        .padding(.horizontal, 7).frame(height: 20)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.6))
    }
}


// MARK: - Light on the island's own edge (charging sweep, notifications, music) — like Pulse

struct IslandRim: View {
    let width: CGFloat, height: CGFloat, cornerRadius: CGFloat, topRadius: CGFloat
    let open: Bool
    @ObservedObject private var glow = EdgeGlow.shared
    var body: some View {
        if let k = glow.kind, glow.enabled, !open || k.showsWhenOpen {
            let shape = IslandShape(width: width, height: height, cornerRadius: cornerRadius, topRadius: topRadius)
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let pulse = 0.55 + 0.45 * sin(t * 4)
                let a = CGFloat((t * 0.55).truncatingRemainder(dividingBy: 1))
                ZStack {
                    shape.stroke(k.color.opacity(0.35 + 0.35 * pulse), lineWidth: 2)
                    shape.stroke(k.color.opacity(0.6 * pulse), lineWidth: 5).blur(radius: 5)
                    if case .charging = k {
                        // a bright bead of light running round the edge, the way a charger fills up
                        shape.trim(from: a, to: min(1, a + 0.18)).stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .shadow(color: k.color, radius: 6)
                        if a + 0.18 > 1 {
                            shape.trim(from: 0, to: a + 0.18 - 1).stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).shadow(color: k.color, radius: 6)
                        }
                    }
                }
                .frame(width: width, height: height)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

// MARK: - Now playing (Spotify or Apple Music) with controls in the notch

@MainActor
final class NowPlaying: ObservableObject {
    static let shared = NowPlaying()
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var app = ""
    @Published private(set) var playing = false
    @Published private(set) var artURL: URL?
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    /// macOS said no to controlling Spotify / Music → show how to allow it.
    @Published var needsPermission = false
    private var timer: Timer?
    private var busy = false
    var hasTrack: Bool { !title.isEmpty }

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { _ in MainActor.assumeIsolated { NowPlaying.shared.poll() } }
    }

    private static func running(_ id: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty }

    func poll() {
        guard !busy else { return }
        // Never launches Spotify or Music — only asks them if they're already open.
        let spot = Self.running("com.spotify.client"), music = Self.running("com.apple.Music")
        guard spot || music else { if hasTrack { clear() }; return }
        busy = true
        let name = spot ? "Spotify" : "Music"
        let script = spot
            ? "tell application \"Spotify\"\nif player state is stopped then return \"\"\nset t to current track\nreturn (name of t) & linefeed & (artist of t) & linefeed & (player state as string) & linefeed & (player position as string) & linefeed & ((duration of t) / 1000 as string) & linefeed & (artwork url of t)\nend tell"
            : "tell application \"Music\"\nif player state is stopped then return \"\"\nset t to current track\nreturn (name of t) & linefeed & (artist of t) & linefeed & (player state as string) & linefeed & (player position as string) & linefeed & (duration of t as string) & linefeed & \"\"\nend tell"
        // In-process AppleScript (the same way Zuffi already talks to Spotify / Music) — a few milliseconds.
        apply(Self.run(script), app: name)
    }

    private func apply(_ out: String?, app name: String) {
        busy = false
        guard let out, !out.isEmpty else { if hasTrack { clear() }; return }
        let p = out.components(separatedBy: "\n")
        guard p.count >= 5 else { return }
        let newTitle = p[0]
        let num: (String) -> Double = { Double($0.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) ?? 0 }
        if newTitle != title, !newTitle.isEmpty, p[2] == "playing" { EdgeGlow.shared.flash(.music(newTitle), seconds: 2.4) }
        title = newTitle; artist = p[1]; app = name; playing = p[2] == "playing"
        position = num(p[3]); duration = num(p[4])
        artURL = p.count > 5 && !p[5].isEmpty ? URL(string: p[5].trimmingCharacters(in: .whitespacesAndNewlines)) : nil
    }

    private func clear() { title = ""; artist = ""; playing = false; artURL = nil; position = 0; duration = 0 }

    func send(_ cmd: String) {   // "playpause", "next track", "previous track"
        let target = app.isEmpty ? (Self.running("com.spotify.client") ? "Spotify" : "Music") : app
        if cmd == "playpause" { playing.toggle() }
        _ = Self.run("tell application \"\(target)\" to \(cmd)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { MainActor.assumeIsolated { NowPlaying.shared.poll() } }
    }

    private static var warned = false
    static func run(_ source: String) -> String? {
        var err: NSDictionary?
        let r = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err {
            let n = err[NSAppleScript.errorNumber] as? Int ?? 0
            if !warned { warned = true; appendAppLog("music.log", "AppleScript error \(n): \(err[NSAppleScript.errorMessage] ?? "")") }
            if n == -1743 { NowPlaying.shared.needsPermission = true }       // not allowed to control the app
            return nil
        }
        NowPlaying.shared.needsPermission = false
        return r?.stringValue
    }

    nonisolated static func osa(_ script: String) -> String? {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Music page: artwork, title, a progress line and the three buttons.
struct NowPlayingCard: View {
    @ObservedObject private var np = NowPlaying.shared
    var body: some View {
        VStack(spacing: 8) {
            if np.hasTrack {
                HStack(spacing: 10) {
                    Group {
                        if let u = np.artURL {
                            AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { art }
                        } else { art }
                    }
                    .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.title).font(.system(size: 12.5, weight: .bold, design: .rounded)).lineLimit(1)
                        Text(np.artist).font(.system(size: 11)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                        Text(np.app).font(.system(size: 9.5, weight: .semibold)).foregroundColor(Color(hex: np.app == "Spotify" ? "#1ED760" : "#FA586A"))
                    }
                    Spacer(minLength: 0)
                    if np.playing { MusicBars().frame(width: 16, height: 14) }
                }
                if np.duration > 0 {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.15))
                            Capsule().fill(Color.white.opacity(0.85)).frame(width: g.size.width * CGFloat(min(1, np.position / np.duration)))
                        }
                    }.frame(height: 3)
                }
                HStack(spacing: 22) {
                    control("backward.fill") { np.send("previous track") }
                    control(np.playing ? "pause.fill" : "play.fill", big: true) { np.send("playpause") }
                    control("forward.fill") { np.send("next track") }
                }
            } else {
                Image(systemName: "music.note").font(.system(size: 26)).foregroundColor(Color(hex: "#F472B6"))
                Text(np.needsPermission ? "Let Zuffi see your music" : "Nothing playing").font(.system(size: 12, weight: .semibold, design: .rounded))
                Text(np.needsPermission ? "System Settings → Privacy & Security → Automation → Zuffi → turn on Music and Spotify." : "Play something in Spotify or Music — it shows here with controls.").font(.system(size: 10)).foregroundColor(.white.opacity(0.55)).multilineTextAlignment(.center)
                Button {
                    if np.needsPermission, let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(u) }
                    else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Music.app")) }
                } label: {
                    Text(np.needsPermission ? "Open Settings" : "Open Music").font(.system(size: 10.5, weight: .bold)).padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(Color.white.opacity(0.14)))
                }.buttonStyle(.plain)
            }
        }
        .foregroundColor(.white)
        .onAppear { NowPlaying.shared.start() }
    }
    private var art: some View {
        LinearGradient(colors: [Color(hex: "#F472B6"), Color(hex: "#7C5CFF")], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(Image(systemName: "music.note").font(.system(size: 18, weight: .bold)).foregroundColor(.white))
    }
    private func control(_ icon: String, big: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: big ? 17 : 13, weight: .bold))
                .frame(width: big ? 38 : 30, height: big ? 38 : 30)
                .background(Circle().fill(Color.white.opacity(big ? 0.2 : 0.08)))
        }.buttonStyle(.plain)
    }
}

/// Three little bars bouncing while music plays.
struct MusicBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(Color(hex: "#F472B6"))
                        .frame(width: 3.5, height: 4 + 10 * CGFloat(abs(sin(t * (4 + Double(i)) + Double(i)))))
                }
            }
        }
    }
}

// MARK: - The notch home's pages (swipe sideways; nothing moves by itself)

@MainActor
final class NotchGlance: ObservableObject {
    static let shared = NotchGlance()
    struct Prayer { let name: String; let at: Date }
    @Published private(set) var prayers: [Prayer] = []
    @Published private(set) var reminder: (title: String, at: Date)?
    private var last = Date.distantPast

    func refresh() {
        guard Date().timeIntervalSince(last) > 60, WebHub.shared.isReady else { return }
        last = Date()
        Task {
            guard let r = await WebHub.shared.callJS("return window.Sparrow && window.Sparrow.glance ? window.Sparrow.glance() : null") as? [String: Any] else { return }
            let ps = (r["prayers"] as? [[String: Any]] ?? []).compactMap { d -> Prayer? in
                guard let n = d["n"] as? String, let at = d["at"] as? Double else { return nil }
                return Prayer(name: n, at: Date(timeIntervalSince1970: at / 1000))
            }
            self.prayers = ps
            if let m = r["reminder"] as? [String: Any], let t = m["title"] as? String, let at = m["at"] as? Double {
                self.reminder = (t, Date(timeIntervalSince1970: at / 1000))
            } else { self.reminder = nil }
        }
    }
    var nextPrayer: Prayer? { prayers.first { $0.at > Date() } }
}

struct NotchTodayPage: View {
    @ObservedObject private var g = NotchGlance.shared
    @ObservedObject private var weather = WeatherStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let n = g.nextPrayer {
                HStack(spacing: 8) {
                    tile("moon.stars.fill", "#8B7CF6")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(n.name) at \(Self.hm(n.at))").font(.system(size: 12, weight: .bold, design: .rounded))
                        Text("in \(Self.until(n.at))").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<g.prayers.prefix(5).count, id: \.self) { i in
                        let p = g.prayers[i]
                        VStack(spacing: 1) {
                            Text(String(p.name.prefix(3))).font(.system(size: 8.5, weight: .bold))
                            Text(Self.hm(p.at)).font(.system(size: 8.5)).monospacedDigit()
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(p.name == n.name ? 0.22 : 0.07)))
                        .opacity(p.at < Date() ? 0.5 : 1)
                    }
                }
            }
            if let r = g.reminder {
                HStack(spacing: 8) {
                    tile("bell.fill", "#F7C948")
                    VStack(alignment: .leading, spacing: 0) {
                        Text(r.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                        Text(r.at < Date() ? "Overdue" : Self.until(r.at) == "now" ? "Now" : "in \(Self.until(r.at))").font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            if let c = weather.current, let w = weather.reports[c.name] {
                HStack(spacing: 8) {
                    tile(WeatherStore.symbol(w.code, night: WeatherStore.isNight(Date())), "#38BDF8")
                    Text("\(c.name) \(w.temp)° · high \(w.hi)°").font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                }
            }
            if g.nextPrayer == nil && g.reminder == nil && weather.current == nil {
                Text("Nothing coming up. Turn on prayer times or add a reminder and they’ll show here.").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6))
            }
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { NotchGlance.shared.refresh() }
    }
    private func tile(_ icon: String, _ hex: String) -> some View {
        Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: hex).gradient))
    }
    static func hm(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }
    static func until(_ d: Date) -> String {
        let m = Int(d.timeIntervalSinceNow / 60)
        if m <= 0 { return "now" }
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }
}

struct NotchMePage: View {
    @ObservedObject private var plan = ZuffiPlan.shared
    var body: some View {
        let p = plan.profile
        let name = (p["name"] ?? "").isEmpty ? "You" : p["name"]!
        VStack(spacing: 6) {
            Text(String(name.prefix(1)).uppercased()).font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(width: 40, height: 40)
                .background(Circle().fill(LinearGradient(colors: [IslandConst.accent, Color(hex: "#F472B6")], startPoint: .topLeading, endPoint: .bottomTrailing)))
            Text(name).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
            if let b = Self.birthday(p["dob"]) { Text(b).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.7)) }
            if let c = p["city"], !c.isEmpty { Text(c).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)) }
            Button { ZuffiNav.go(.profile) } label: {
                Text("See my details").font(.system(size: 10.5, weight: .bold)).padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(Color.white.opacity(0.14)))
            }.buttonStyle(.plain)
        }
        .foregroundColor(.white)
    }
    /// "Birthday in 12 days" (or today!).
    static func birthday(_ iso: String?) -> String? {
        guard let iso, iso.count == 10 else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let dob = f.date(from: iso) else { return nil }
        let cal = Calendar.current
        var c = cal.dateComponents([.month, .day], from: dob); c.year = cal.component(.year, from: Date())
        guard var next = cal.date(from: c) else { return nil }
        if cal.startOfDay(for: next) < cal.startOfDay(for: Date()) { next = cal.date(byAdding: .year, value: 1, to: next) ?? next }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: next)).day ?? 0
        return days == 0 ? "🎂 Happy birthday!" : "🎂 Birthday in \(days) day\(days == 1 ? "" : "s")"
    }
}


/// When something is playing: a slim row on Zuffi's home page — song, back · play/pause · next (no need to swipe).
struct MiniMusicBar: View {
    @ObservedObject private var np = NowPlaying.shared
    var body: some View {
        if np.hasTrack {
            HStack(spacing: 8) {
                if np.playing { MusicBars().frame(width: 12, height: 11) } else { Image(systemName: "music.note").font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: "#F472B6")) }
                Text(np.title).font(.system(size: 10.5, weight: .semibold, design: .rounded)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ForEach([("backward.fill", "previous track"), (np.playing ? "pause.fill" : "play.fill", "playpause"), ("forward.fill", "next track")], id: \.1) { b in
                    Button { np.send(b.1) } label: {
                        Image(systemName: b.0).font(.system(size: b.1 == "playpause" ? 12 : 9.5, weight: .bold)).frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(b.1 == "playpause" ? 0.18 : 0.08)))
                    }.buttonStyle(.plain)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8).frame(height: 28)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}
