import SwiftUI
import AppKit
import ApplicationServices

// =====================================================================
// MARK: - The new Zuffi design (from the hand-drawn sketch)
//
//  ┌──────────── now using: Claude · GitHub ────────────┐
//  │ ●  (apps you have open)          (options) ●       │
//  │ ●              Zuffi                       ●       │
//  │ ●         words Zuffi says                 ●       │
//  └────────────────────────────────────────────────────┘
//  Chat, Settings, Agents, History open as their own tall glass panels;
//  opening one closes the other first. Home floats in a little space sky.
// =====================================================================

extension Notification.Name {
    /// Close whatever panel is open, then open this one (object: IslandView).
    static let zuffiSwitch = Notification.Name("zuffi.switch")
}

@MainActor
enum ZuffiNav {
    static func go(_ v: IslandView) {
        if v == .prompt { ZuffiChat.shared.open(); return }
        if v == .prompt, AppState.shared.promptContext == nil {
            #if !APPSTORE
            AppState.shared.promptContext = WindowContextCapture.captureActive(from: AppState.shared.lastExternalApp)
            #endif
        }
        if v == .prompt { AppState.shared.unreadReplies = 0 }
        NotificationCenter.default.post(name: .zuffiSwitch, object: v)
    }
}

// MARK: Space sky — drifting orbs and twinkling stars

struct ZuffiSpaceBackground: View {
    var intensity: Double = 1
    private static let stars: [(CGFloat, CGFloat, CGFloat, Double)] = {
        var g = SystemRandomNumberGenerator()
        return (0..<70).map { _ in
            (CGFloat.random(in: 0...1, using: &g), CGFloat.random(in: 0...1, using: &g),
             CGFloat.random(in: 0.6...1.8, using: &g), Double.random(in: 0...6.28, using: &g))
        }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                // deep sky
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(hex: "#0B0A1F").opacity(0.75 * intensity), Color(hex: "#1B1240").opacity(0.7 * intensity), Color(hex: "#2A1235").opacity(0.7 * intensity)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                // orbs (soft nebula lights)
                var orb = ctx
                orb.addFilter(.blur(radius: min(size.width, size.height) * 0.16))
                let orbs: [(String, Double, Double, Double)] = [("#E2648A", 0.55, 0.0, 0.62), ("#7C5CFF", 0.42, 2.2, 0.7), ("#3BA8FF", 0.34, 4.1, 0.52), ("#F7A072", 0.27, 1.1, 0.42)]
                for (hex, sp, ph, r) in orbs {
                    let x = size.width * (0.5 + 0.42 * cos(t * sp + ph))
                    let y = size.height * (0.5 + 0.38 * sin(t * sp * 1.3 + ph))
                    let rad = min(size.width, size.height) * r * 0.5 * (1 + 0.18 * sin(t * sp * 2 + ph))
                    orb.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(Color(hex: hex).opacity(0.42 * intensity)))
                }
                // stars
                for (x, y, r, ph) in Self.stars {
                    let a = 0.35 + 0.65 * abs(sin(t * 1.3 + ph))
                    ctx.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height, width: r, height: r)), with: .color(.white.opacity(a * intensity)))
                }
                // a shooting star every ~9 s
                let cyc = t.truncatingRemainder(dividingBy: 9)
                if cyc < 0.9 {
                    let p = cyc / 0.9
                    let sx = size.width * (0.15 + 0.7 * p), sy = size.height * (0.12 + 0.25 * p)
                    var line = Path(); line.move(to: CGPoint(x: sx, y: sy)); line.addLine(to: CGPoint(x: sx - 34, y: sy - 12))
                    ctx.stroke(line, with: .linearGradient(Gradient(colors: [.white.opacity(0.9 * (1 - p)), .clear]), startPoint: CGPoint(x: sx, y: sy), endPoint: CGPoint(x: sx - 34, y: sy - 12)), lineWidth: 1.4)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: What you're using right now (top line) + the apps you have open (left dots)

@MainActor
final class NowUsing: ObservableObject {
    static let shared = NowUsing()
    @Published var app: NSRunningApplication?
    @Published var title = ""
    @Published var apps: [NSRunningApplication] = []
    private var timer: Timer?
    fileprivate var titleBusy = false

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in MainActor.assumeIsolated { NowUsing.shared.refresh() } }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NowUsing.shared.refresh() }
        }
    }

    func refresh() {
        let me = Bundle.main.bundleIdentifier
        if let f = NSWorkspace.shared.frontmostApplication, f.bundleIdentifier != me { app = f }
        else if app == nil { app = AppState.shared.lastExternalApp }
        if let pid = app?.processIdentifier, !titleBusy {
            titleBusy = true
            Task.detached(priority: .utility) {
                let t = NowUsing.windowTitle(pid: pid)
                await MainActor.run { NowUsing.shared.titleBusy = false; if NowUsing.shared.title != t { NowUsing.shared.title = t } }
            }
        }
        let withWindows = Self.pidsWithWindows()
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.bundleIdentifier != me && withWindows.contains($0.processIdentifier)
        }
        // what you use most (front first), up to 5
        let list = running
        let ids = list.prefix(8).map { $0.processIdentifier }
        if ids != apps.map({ $0.processIdentifier }) { apps = Array(list.prefix(8)) }
    }

    /// Apps that really have a window open (on screen, minimised or hidden) — not ones running with nothing open.
    static func pidsWithWindows() -> Set<pid_t> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out = Set<pid_t>()
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == 0, let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let b = w[kCGWindowBounds as String] as? [String: Any], let wd = b["Width"] as? Double, let ht = b["Height"] as? Double,
                  wd > 120, ht > 80 else { continue }
            if (w[kCGWindowAlpha as String] as? Double ?? 1) <= 0.01 { continue }
            out.insert(pid)
        }
        return out
    }

    /// The focused window's title ("GitHub — Claude", "Inbox — Gmail") — needs Accessibility; empty otherwise.
    nonisolated static func windowTitle(pid: pid_t) -> String {
        guard AXIsProcessTrusted() else { return "" }
        let ax = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(ax, 0.3)      // a busy app must never freeze Zuffi
        var win: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedWindowAttribute as CFString, &win) == .success, let w = win else { return "" }
        var t: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success else { return "" }
        return (t as? String) ?? ""
    }
}

// MARK: Home buttons you can choose (left and right of Zuffi)

struct HomeAction: Identifiable {
    let id: String
    let icon: String
    let label: String
    let tint: String

    static let all: [HomeAction] = [
        HomeAction(id: "chat", icon: "bubble.left.fill", label: "Chat", tint: "#F58FA8"),
        HomeAction(id: "settings", icon: "gearshape.fill", label: "Settings", tint: "#A9B2C6"),
        HomeAction(id: "more", icon: "square.grid.2x2.fill", label: "More", tint: "#F7C948"),
        HomeAction(id: "pet", icon: "hare.fill", label: "Zuffi on screen", tint: "#FFB7C5"),
        HomeAction(id: "screen", icon: "eye.fill", label: "What's on my screen?", tint: "#7CC4FF"),
        HomeAction(id: "agents", icon: "sparkles", label: "Agents", tint: "#F7C948"),
        HomeAction(id: "data", icon: "tablecells.fill", label: "My data (Excel)", tint: "#34D399"),
        HomeAction(id: "today", icon: "sun.max.fill", label: "Today", tint: "#FBC56A"),
        HomeAction(id: "history", icon: "clock.arrow.circlepath", label: "History", tint: "#C4B5FD"),
        HomeAction(id: "weather", icon: "cloud.sun.fill", label: "Weather", tint: "#7CC4FF"),
        HomeAction(id: "music", icon: "music.note", label: "Play music", tint: "#F472B6"),
        HomeAction(id: "camera", icon: "camera.fill", label: "Look through the camera", tint: "#A7F3D0"),
        HomeAction(id: "notes", icon: "note.text", label: "Take a note", tint: "#FDE68A"),
        HomeAction(id: "newchat", icon: "square.and.pencil", label: "New chat", tint: "#F58FA8"),
        HomeAction(id: "lock", icon: "lock.fill", label: "Lock screen", tint: "#A9B2C6"),
        HomeAction(id: "whatsapp", icon: "message.fill", label: "WhatsApp", tint: "#34D399"),
        HomeAction(id: "callToday", icon: "phone.fill", label: "Who to call today", tint: "#34D399"),
        HomeAction(id: "quiet", icon: "hourglass", label: "Buyers gone quiet", tint: "#FBC56A"),
        HomeAction(id: "appointments", icon: "calendar", label: "Today's appointments", tint: "#F58FA8"),
        HomeAction(id: "reminders", icon: "bell.badge.fill", label: "Send tomorrow's reminders", tint: "#7CC4FF"),
        HomeAction(id: "rebook", icon: "arrow.clockwise.heart.fill", label: "Clients to rebook", tint: "#C4B5FD"),
        HomeAction(id: "leads", icon: "person.2.fill", label: "My leads", tint: "#34D399"),
        HomeAction(id: "newLead", icon: "person.badge.plus", label: "Add a lead", tint: "#7CE0A8"),
        HomeAction(id: "messageLeads", icon: "paperplane.fill", label: "Message new leads", tint: "#7CC4FF"),
        HomeAction(id: "book", icon: "calendar.badge.plus", label: "Book an appointment", tint: "#F58FA8"),
        HomeAction(id: "week", icon: "calendar.day.timeline.left", label: "This week's bookings", tint: "#FBC56A"),
        HomeAction(id: "save", icon: "square.and.arrow.down.fill", label: "Save some data", tint: "#FDE68A"),
        HomeAction(id: "team", icon: "person.3.fill", label: "Zuffi's team", tint: "#C4B5FD"),
        HomeAction(id: "business", icon: "briefcase.fill", label: "Business dashboard", tint: "#F58FA8"),
        HomeAction(id: "inbox", icon: "tray.full.fill", label: "WhatsApp inbox", tint: "#34D399"),
    ]
    static func find(_ id: String) -> HomeAction? { all.first { $0.id == id } }
    static let defaultLeft = ["chat", "settings", "more", "pet"]
    static let defaultRight = ["screen", "agents", "data", "today"]

    @MainActor static var left: [String] {
        get { (UserDefaults.standard.stringArray(forKey: "homeLeft") ?? defaultLeft).filter { find($0) != nil } }
        set { UserDefaults.standard.set(newValue, forKey: "homeLeft") }
    }
    @MainActor static var right: [String] {
        get { (UserDefaults.standard.stringArray(forKey: "homeRight") ?? defaultRight).filter { find($0) != nil } }
        set { UserDefaults.standard.set(newValue, forKey: "homeRight") }
    }

    /// Asks Zuffi in the chat window (for answers that are lists).
    @MainActor static func ask(_ q: String) {
        let s = AppState.shared
        s.chatHistory.append(ChatMessage(role: .user, content: q))
        s.stateOverride = .thinking
        ZuffiChat.shared.open()
        Task { await AIService.shared.chat(query: q, context: nil, state: s) }
    }

    @MainActor static func run(_ id: String, home: ZuffiHomeModel) {
        switch id {
        case "chat": ZuffiChat.shared.open()
        case "settings": ZuffiNav.go(.settings)
        case "more": WebHub.shared.show()
        case "pet": PetController.shared.toggle()
        case "screen": home.say("Let me look…"); Task { await Assistant.run("what's on my screen", spoken: true) }
        case "agents": ZuffiNav.go(.agents)
        case "data": ZuffiNav.go(.data)
        case "today": TodayWindow.shared.show()
        case "history": ZuffiNav.go(.history)
        case "weather": Task { await Assistant.run("what's the weather", spoken: true) }
        case "music": Task { await Assistant.run("play music", spoken: true) }
        case "camera": Task { await Assistant.run("what do you see through the camera", spoken: true) }
        case "notes": ZuffiChat.shared.open(prefill: "Note: ")
        case "newchat": AppState.shared.newChat(); ZuffiChat.shared.open()
        case "lock": Task { await Assistant.run("lock screen", spoken: false) }
        case "whatsapp": Task { await Assistant.run("any new whatsapp messages", spoken: true) }
        case "callToday": home.say(ZuffiBusiness.shared.callToday())
        case "quiet": home.say(ZuffiBusiness.shared.quietBuyers(short: false))
        case "appointments": home.say(ZuffiBusiness.shared.todays(offset: 0, short: false))
        case "reminders": let r = ZuffiBusiness.shared.prepareReminders(); home.say(r); VoiceEngine.shared.speak(r)
        case "rebook": home.say(ZuffiBusiness.shared.rebook())
        case "leads": BusinessDashboard.shared.show(.pipeline)
        case "newLead": ZuffiChat.shared.open(prefill: "New lead ")
        case "messageLeads": ask("message new leads")
        case "book": ZuffiChat.shared.open(prefill: "Book ")
        case "week": ask("this week's appointments")
        case "save": ZuffiChat.shared.open(prefill: "Save this: ")
        case "team": ask("show my team")
        case "business": BusinessDashboard.shared.show()
        case "inbox": BusinessDashboard.shared.show(.inbox)
        default: break
        }
    }
}

@MainActor
final class ZuffiHomeModel: ObservableObject {
    static let shared = ZuffiHomeModel()
    @Published var chatOpen = false
    @Published var draft = ""
    @Published var flash: String?
    @Published var left = HomeAction.left
    @Published var right = HomeAction.right
    func say(_ s: String) { flash = s; DispatchQueue.main.asyncAfter(deadline: .now() + (s.count > 60 ? 12 : 3)) { MainActor.assumeIsolated { if ZuffiHomeModel.shared.flash == s { ZuffiHomeModel.shared.flash = nil } } } }
    func reloadButtons() { left = HomeAction.left; right = HomeAction.right }
}

// MARK: Home — the panel from the sketch (fixed geometry, so nothing can push the buttons off the sides)

struct ZuffiHomePanel: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var now = NowUsing.shared
    @ObservedObject private var agents = AgentHub.shared
    @ObservedObject private var home = ZuffiHomeModel.shared
    @StateObject private var head = SparrowSpriteModel()
    @State private var hover: String?

    private let W = IslandConst.width(for: .overview)
    private let H = IslandConst.viewLayouts[.overview]!.height
    private let side: CGFloat = 46

    private var listening: Bool { voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) }
    private var mood: SpriteMood {
        if listening { return .listening }
        if voice.speaking { return .speaking }
        if state.stateOverride != nil { return .thinking }
        return .idle
    }
    private var words: String {
        if listening { return voice.heard.isEmpty ? "I'm listening…" : "“\(voice.heard)”" }
        if state.stateOverride != nil { return "Let me think…" }
        if let f = home.flash { return f }
        if let last = state.chatHistory.last(where: { $0.role == .assistant }), voice.speaking || Date().timeIntervalSince(state.lastActivity) < 90 {
            return last.content
        }
        if !VoiceEngine.micOn { return "My mic is off — tap Mic to talk to me" }
        let name = AssistantPrefs.displayName
        return "Hi\(name.isEmpty ? "" : " \(name)")! Say “Hey Zuffi”"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZuffiSpaceBackground().frame(width: W, height: H)
            Color.clear.frame(width: W, height: H).contentShape(Rectangle()).movesIsland()
            VStack(spacing: 8) {
                appsRow.frame(width: W - 20)
                HStack(alignment: .center, spacing: 0) {
                    column(home.left, round: true).frame(width: side)
                    VStack(spacing: 6) {
                        // the little bunny head that follows your cursor
                        SparrowSpriteView(model: head, size: 96, deadZone: 40, mood: mood) { VoiceEngine.shared.listenOnce() }
                            .frame(width: 100, height: 100)
                        Text(words)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.94))
                            .multilineTextAlignment(.center)
                            .lineLimit(4)
                            .frame(width: W - 20 - side * 2 - 8)
                            .animation(.easeInOut(duration: 0.2), value: words)
                    }
                    .frame(width: W - 20 - side * 2)
                    column(home.right, round: false).frame(width: side)
                }
                .frame(width: W - 20)
                Spacer(minLength: 0)
                bottomRow.frame(width: W - 20)
            }
            .padding(.top, 8).padding(.bottom, 12)
            .frame(width: W, height: H)
            if let h = hover {
                Text(h).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(Color.black.opacity(0.7)))
                    .padding(.top, 42)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: W, height: H)
        .clipped()
        .onAppear { NowUsing.shared.start(); home.reloadButtons() }
    }

    // the apps you have open (with a window) — click one to jump to it
    private var appsRow: some View {
        HStack(spacing: 4) {
            if now.apps.isEmpty { Text("Zuffi").font(.system(size: 11, weight: .bold, design: .rounded)) }
            ForEach(now.apps, id: \.processIdentifier) { a in
                let cur = a.processIdentifier == now.app?.processIdentifier
                Button { a.bringForward() } label: {
                    HStack(spacing: 4) {
                        if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 18, height: 18) }
                        if cur { Text(a.localizedName ?? "").font(.system(size: 10.5, weight: .bold, design: .rounded)).lineLimit(1).fixedSize() }
                    }
                    .padding(.horizontal, cur ? 7 : 3).frame(height: 26)
                    .background(Capsule().fill(LinearGradient(colors: [Color.white.opacity(cur ? 0.32 : 0), Color.white.opacity(cur ? 0.12 : 0)], startPoint: .top, endPoint: .bottom)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(cur ? 0.35 : 0), lineWidth: 0.7))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 ? (a.localizedName ?? "") + (cur && !now.title.isEmpty ? " · " + now.title : "") : nil }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6).frame(height: 34)
        .liquidGlass(Capsule(), glow: Color(hex: "#7C5CFF"))
    }

    // four buttons on each side — you choose them in Settings
    private func column(_ ids: [String], round: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(ids.prefix(4).enumerated()), id: \.offset) { i, id in
                if let a = HomeAction.find(id) {
                    Button { HomeAction.run(id, home: home) } label: {
                        Image(systemName: a.icon).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: a.tint))
                            .frame(width: round ? 34 : 42, height: round ? 34 : 28)
                            .modifier(SideGlass(round: round, square: i >= 2, tint: Color(hex: a.tint)))
                            .overlay(alignment: .topTrailing) { badge(id) }
                    }
                    .buttonStyle(.plain)
                    .onHover { hover = $0 ? a.label : nil }
                    .help(a.label)
                }
            }
        }
    }

    private func shape(round: Bool, square: Bool) -> AnyShape {
        if round { return square ? AnyShape(RoundedRectangle(cornerRadius: 9, style: .continuous)) : AnyShape(Circle()) }
        return AnyShape(Capsule())
    }

    @ViewBuilder private func badge(_ id: String) -> some View {
        let n = id == "chat" ? state.unreadReplies : id == "agents" ? agents.approvals.count : 0
        if n > 0 {
            Text("\(n)").font(.system(size: 8.5, weight: .heavy)).foregroundColor(.white)
                .frame(minWidth: 14, minHeight: 14).background(Circle().fill(Color(hex: "#F4505E"))).offset(x: 4, y: -4)
        }
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            Button { VoiceEngine.shared.setMic(!VoiceEngine.micOn) } label: {
                Label(VoiceEngine.micOn ? "Mic" : "Off", systemImage: VoiceEngine.micOn ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(VoiceEngine.micOn ? .white : Color(hex: "#FF8A8F"))
                    .padding(.horizontal, 10).frame(height: 28)
                    .liquidGlass(Capsule(), tint: VoiceEngine.micOn ? nil : Color(hex: "#E5484D"), interactive: true)
            }.buttonStyle(.plain).help("Turn the microphone on or off")
            Button { ZuffiChat.shared.open() } label: {
                Label("Chat", systemImage: "bubble.left.fill").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 12).frame(height: 28)
                    .liquidGlass(Capsule(), interactive: true)
            }.buttonStyle(.plain)
            Button { BusinessDashboard.shared.show() } label: {
                Label("Business", systemImage: "briefcase.fill").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 10).frame(height: 28)
                    .liquidGlass(Capsule(), tint: Color(hex: "#C77DFF"), glow: Color(hex: "#F58FA8"), interactive: true)
            }.buttonStyle(.plain).help("Your leads, WhatsApp inbox, team and automations")
            Button { VoiceEngine.shared.listenOnce() } label: {
                Image(systemName: listening ? "waveform" : "mic.circle.fill").font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1008"))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)))
            }.buttonStyle(.plain).help("Talk to Zuffi").disabled(!VoiceEngine.micOn)
        }
    }
}

struct PulseRing: View {
    var delay: Double
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let p = (tl.date.timeIntervalSinceReferenceDate * 0.7 + delay).truncatingRemainder(dividingBy: 1)
            Circle().stroke(Color(hex: "#F58FA8").opacity(0.6 * (1 - p)), lineWidth: 2)
                .frame(width: 70 + 90 * p, height: 70 + 90 * p)
        }
    }
}

// MARK: Top bar for the tall panels (Chat, Settings, Agents, History)

struct ZuffiPanelBar: View {
    let title: String
    let icon: String
    var trailing: AnyView? = nil
    var body: some View {
        HStack(spacing: 8) {
            Button { ZuffiNav.go(.overview) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26).liquidGlass(Circle(), interactive: true)
            }.buttonStyle(.plain).help("Back to Zuffi")
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#F7C948"))
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            if let trailing { trailing }
            Button { NotificationCenter.default.post(name: .islandCollapse, object: nil) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 26).liquidGlass(Circle(), interactive: true)
            }.buttonStyle(.plain).help("Close")
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10).frame(height: 38)
        .background(Capsule().fill(.ultraThinMaterial).opacity(0.85).movesIsland())
        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.6))
    }
}

/// A tall glass panel: bar on top, content below, with a faint sky behind.
struct ZuffiTallPanel<Content: View>: View {
    let title: String
    let icon: String
    var view: IslandView = .settings
    var trailing: AnyView? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        // Fixed size = the island's own size, so nothing inside can spill past the edges.
        let W = IslandConst.width(for: view)
        let H = IslandConst.viewLayouts[view]?.height ?? 400
        ZStack(alignment: .top) {
            ZuffiSpaceBackground().frame(width: W, height: H)
            VStack(spacing: 8) {
                ZuffiPanelBar(title: title, icon: icon, trailing: trailing).frame(width: W - 20)
                content().frame(width: W - 20, height: H - 20 - 38 - 8)
            }
            .padding(10)
            .frame(width: W, height: H, alignment: .top)
        }
        .frame(width: W, height: H)
        .clipped()
    }
}

// MARK: Settings panel (quick switches; everything else in "All settings")

struct ZuffiQuickSettings: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var look = ZuffiLook.shared
    @ObservedObject private var glow = EdgeGlow.shared
    @AppStorage("bunnyVoice") private var bunny = true
    @AppStorage(AssistantPrefs.wakeWord) private var wake = true

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                row("mic.fill", "Microphone", on: Binding(get: { VoiceEngine.micOn }, set: { VoiceEngine.shared.setMic($0) }))
                row("video.fill", "Camera", on: Binding(get: { VoiceEngine.cameraOn }, set: { VoiceEngine.shared.setCamera($0) }))
                row("ear.fill", "Answer to “Hey Zuffi”", on: Binding(get: { wake }, set: { wake = $0; if $0 { VoiceEngine.shared.setMic(VoiceEngine.micOn) } }))
                row("speaker.wave.2.fill", "Sounds", on: $state.soundEnabled)
                row("bell.badge.fill", "Read notifications out loud", on: Binding(
                    get: { UserDefaults.standard.bool(forKey: AssistantPrefs.readNotes) },
                    set: { UserDefaults.standard.set($0, forKey: AssistantPrefs.readNotes); NotificationReader.shared.setEnabled($0) }))
                row("hare.fill", "Cute bunny voice", on: $bunny)
                row("light.max", "Glow around the notch", on: $glow.enabled)
                row("rectangle.topthird.inset.filled", "Show Zuffi by the notch when closed", on: Binding(
                    get: { IslandStateMachine.alwaysShowZuffi },
                    set: { UserDefaults.standard.set($0, forKey: "alwaysShowZuffi"); AppState.shared.syncMode() }))
                row("figure.walk", "Zuffi on screen (pet)", on: Binding(get: { PetController.shared.isShown }, set: { $0 ? PetController.shared.show() : PetController.shared.hide() }))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fur colour").font(.system(size: 10.5, weight: .bold)).foregroundColor(.white.opacity(0.6))
                    HStack(spacing: 6) {
                        ForEach(ZuffiLook.furs) { f in
                            Circle().fill(Color(hex: f.multiply)).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(look.fur == f.id ? Color(hex: "#F7C948") : Color.white.opacity(0.25), lineWidth: look.fur == f.id ? 2 : 0.6))
                                .onTapGesture { look.kind = .bunny; look.fur = f.id }.help(f.name)
                        }
                    }
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).opacity(0.8))
                homeButtons
                HStack(spacing: 6) {
                    pill("clock.arrow.circlepath", "History") { ZuffiNav.go(.history) }
                    pill("square.grid.2x2.fill", "More") { WebHub.shared.show() }
                    pill("slider.horizontal.3", "All settings") { NotificationCenter.default.post(name: .openFullSettings, object: nil) }
                }
            }
        }
    }

    @ObservedObject private var home = ZuffiHomeModel.shared

    /// Choose the buttons beside Zuffi on the home screen.
    private var homeButtons: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buttons beside Zuffi").font(.system(size: 10.5, weight: .bold)).foregroundColor(.white.opacity(0.6))
            slots("Left", ids: home.left) { i, id in var l = home.left; while l.count < 4 { l.append(HomeAction.defaultLeft[l.count]) }; l[i] = id; HomeAction.left = l; home.reloadButtons() }
            slots("Right", ids: home.right) { i, id in var r = home.right; while r.count < 4 { r.append(HomeAction.defaultRight[r.count]) }; r[i] = id; HomeAction.right = r; home.reloadButtons() }
            Button("Reset to the usual ones") { HomeAction.left = HomeAction.defaultLeft; HomeAction.right = HomeAction.defaultRight; home.reloadButtons() }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).opacity(0.8))
    }

    private func slots(_ title: String, ids: [String], set: @escaping (Int, String) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundColor(.white.opacity(0.7)).frame(width: 34, alignment: .leading)
            ForEach(0..<4, id: \.self) { i in
                let cur = i < ids.count ? HomeAction.find(ids[i]) : nil
                Menu {
                    ForEach(HomeAction.all) { a in
                        Button { set(i, a.id) } label: { Label(a.label, systemImage: a.icon) }
                    }
                } label: {
                    Image(systemName: cur?.icon ?? "plus").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(hex: cur?.tint ?? "#FFFFFF"))
                        .frame(width: 32, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(cur?.label ?? "Choose a button")
            }
        }
    }

    private func row(_ icon: String, _ title: String, on: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F7C948")).frame(width: 20)
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
            Spacer()
            Toggle("", isOn: on).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).opacity(0.8))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 0.6))
    }

    private func pill(_ icon: String, _ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(t, systemImage: icon).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 28)
                .background(Capsule().fill(.ultraThinMaterial)).overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.6))
        }.buttonStyle(.plain)
    }
}


/// The little bunny head in the notch when Zuffi is closed — it turns to follow your cursor.
struct ZuffiMini: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared
    @StateObject private var sprite = SparrowSpriteModel()
    var height: CGFloat
    var body: some View {
        let listening = voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk)
        SparrowSpriteView(model: sprite, size: height, deadZone: 20,
                          mood: listening ? .listening : voice.speaking ? .speaking : state.stateOverride != nil ? .thinking : .idle)
            .allowsHitTesting(false)
    }
}

// MARK: - Bring an app to the front (works on macOS 14+, where a background app can't simply "activate" another)

extension NSRunningApplication {
    @MainActor func bringForward() {
        unhide()
        if let url = bundleURL {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            let pid = processIdentifier
            // macOS calls this back on a background queue — it must not touch the main actor.
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { @Sendable app, _ in
                if app == nil { DispatchQueue.main.async { _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) } }
            }
        } else {
            activate(options: [.activateAllWindows])
        }
    }
}
