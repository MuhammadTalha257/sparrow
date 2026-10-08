import SwiftUI
import AppKit
import IOKit.ps

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
                SparrowSpriteView(model: sprite, size: 74, deadZone: 40, mood: listening ? .listening : .idle) { VoiceEngine.shared.listenOnce() }
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
    struct Chat: Codable, Identifiable { let id: String; let title: String; let date: Date; let messages: [[String: String]] }
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
                          messages: msgs.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.content] }), at: 0)
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
        case charging(Int), battery(Int), capsLock, shift, cut, copied, needsYou, autoApprove, done
        var color: Color {
            switch self {
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
            }
        }
        var text: String {
            switch self {
            case .charging(let p): return "Charging \(p)%"; case .battery(let p): return "On battery \(p)%"
            case .capsLock: return "Caps Lock"; case .shift: return "Shift"
            case .cut: return "Cut"; case .copied: return "Copied"
            case .needsYou: return "Needs you"; case .autoApprove: return "Auto-approved"; case .done: return "Done"
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
        if k != nil && AppState.shared.mode != .expanded { show() } else if k == nil { panel?.orderOut(nil) }
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
                if ZuffiLook.shared.kind == .bunny && ZuffiBodyArt.shared.available {
                    ZuffiWalker(height: 200, walking: false, pose: .wave)
                } else {
                    ZuffiFace(frame: SparrowSprites.shared.available ? SparrowSprites.shared.reactions[8] : nil, size: 150)
                }
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
