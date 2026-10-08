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
        if v == .prompt {
            ZuffiHomeModel.shared.chatOpen = true
            AppState.shared.unreadReplies = 0
            NotificationCenter.default.post(name: .zuffiSwitch, object: IslandView.overview)
            return
        }
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
        TimelineView(.animation(minimumInterval: 1 / 24)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                // deep sky
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [Color(hex: "#0B0A1F").opacity(0.75 * intensity), Color(hex: "#1B1240").opacity(0.7 * intensity), Color(hex: "#2A1235").opacity(0.7 * intensity)]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                // orbs (soft nebula lights)
                var orb = ctx
                orb.addFilter(.blur(radius: min(size.width, size.height) * 0.16))
                let orbs: [(String, Double, Double, Double)] = [("#E2648A", 0.13, 0.0, 0.55), ("#7C5CFF", 0.09, 2.2, 0.62), ("#3BA8FF", 0.07, 4.1, 0.45), ("#F7A072", 0.05, 1.1, 0.35)]
                for (hex, sp, ph, r) in orbs {
                    let x = size.width * (0.5 + 0.38 * cos(t * sp + ph))
                    let y = size.height * (0.5 + 0.34 * sin(t * sp * 1.3 + ph))
                    let rad = min(size.width, size.height) * r * 0.5
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
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != me && $0.bundleIdentifier != "com.apple.finder" }
        // what you use most (front first), up to 5
        let list = running
        let ids = list.prefix(8).map { $0.processIdentifier }
        if ids != apps.map({ $0.processIdentifier }) { apps = Array(list.prefix(8)) }
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

    @MainActor static func run(_ id: String, home: ZuffiHomeModel) {
        switch id {
        case "chat": withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { home.chatOpen.toggle() }
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
        case "notes": withAnimation { home.chatOpen = true }; home.draft = "Note: "
        case "newchat": AppState.shared.newChat(); withAnimation { home.chatOpen = true }
        case "lock": Task { await Assistant.run("lock screen", spoken: false) }
        case "whatsapp": Task { await Assistant.run("any new whatsapp messages", spoken: true) }
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
    func say(_ s: String) { flash = s; DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated { if ZuffiHomeModel.shared.flash == s { ZuffiHomeModel.shared.flash = nil } } } }
    func reloadButtons() { left = HomeAction.left; right = HomeAction.right }
}

// MARK: Home — the panel from the sketch

struct ZuffiHomePanel: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var now = NowUsing.shared
    @ObservedObject private var agents = AgentHub.shared
    @ObservedObject private var home = ZuffiHomeModel.shared
    @State private var hover: String?
    @State private var react: Int?
    @FocusState private var typing: Bool

    private var mood: SpriteMood {
        if listening { return .listening }
        if voice.speaking { return .speaking }
        if state.stateOverride != nil { return .thinking }
        return .idle
    }

    private var listening: Bool { voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) }
    private var pose: ZuffiPose {
        if listening { return .listen }
        if voice.speaking { return .wave }
        if state.stateOverride != nil { return .think }
        return .stand
    }
    private var words: String {
        if listening { return voice.heard.isEmpty ? "I'm listening…" : "“\(voice.heard)”" }
        if state.stateOverride != nil { return "Let me think…" }
        if let f = home.flash { return f }
        if let last = state.chatHistory.last(where: { $0.role == .assistant }), voice.speaking || home.chatOpen || Date().timeIntervalSince(state.lastActivity) < 90 {
            return last.content
        }
        if !VoiceEngine.micOn { return "My mic is off — tap it to talk to me" }
        let name = AssistantPrefs.displayName
        return "Hi\(name.isEmpty ? "" : " \(name)")! Say “Hey Zuffi”"
    }

    var body: some View {
        ZStack {
            ZuffiSpaceBackground()
            // drag anywhere on the sky to move Zuffi
            Color.clear.contentShape(Rectangle()).movesIsland()
            VStack(spacing: 6) {
                appsRow
                ZStack {
                    VStack(spacing: 4) {
                        ZStack {
                            if listening { ForEach(0..<3, id: \.self) { i in PulseRing(delay: Double(i) / 3) } }
                            ZuffiBust(size: home.chatOpen ? 108 : 132, mood: mood, react: $react)
                                .onTapGesture {
                                    react = [1, 8, 4, 5][Int.random(in: 0..<4)]
                                    SoundEngine.shared.play("love")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { react = nil }
                                }
                        }
                        .frame(height: home.chatOpen ? 110 : 134)
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(words)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.94))
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: 196, maxHeight: home.chatOpen ? 64 : 48)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .leading) { column(home.left, round: true) }
                .overlay(alignment: .trailing) { column(home.right, round: false) }
                if home.chatOpen { chatLine.transition(.move(edge: .bottom).combined(with: .opacity)) } else { micRow }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
            if let h = hover {
                Text(h).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(Color.black.opacity(0.65)))
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 34)
                    .transition(.opacity).allowsHitTesting(false)
            }
        }
        .onAppear { NowUsing.shared.start(); home.reloadButtons() }
        .onChange(of: home.chatOpen) { _, open in if open { typing = true } }
    }

    // the open apps along the top — click one to jump to it (the one you're in is highlighted)
    private var appsRow: some View {
        HStack(spacing: 5) {
            if now.apps.isEmpty {
                Text("Zuffi").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            ForEach(now.apps, id: \.processIdentifier) { a in
                let cur = a.processIdentifier == now.app?.processIdentifier
                Button { a.activate(options: .activateIgnoringOtherApps) } label: {
                    HStack(spacing: 4) {
                        if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                        if cur { Text(a.localizedName ?? "").font(.system(size: 10.5, weight: .bold, design: .rounded)).lineLimit(1) }
                    }
                    .padding(.horizontal, cur ? 7 : 4).frame(height: 24)
                    .background(Capsule().fill(Color.white.opacity(cur ? 0.18 : 0.0)))
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 ? (a.localizedName ?? "") + (cur && !now.title.isEmpty ? " · " + now.title : "") : nil }
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6).frame(height: 30)
        .background(Capsule().fill(.ultraThinMaterial).opacity(0.75))
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // the buttons beside Zuffi (left: round, right: soft capsules) — choose them in Settings
    private func column(_ ids: [String], round: Bool) -> some View {
        VStack(spacing: 9) {
            ForEach(Array(ids.prefix(4).enumerated()), id: \.element) { i, id in
                if let a = HomeAction.find(id) {
                    Button { HomeAction.run(id, home: home) } label: {
                        Image(systemName: a.icon).font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color(hex: a.tint))
                            .frame(width: round ? (i < 2 ? 34 : 32) : 40, height: round ? (i < 2 ? 34 : 30) : 28)
                            .background(shape(round: round, square: i >= 2).fill(.ultraThinMaterial))
                            .overlay(shape(round: round, square: i >= 2).stroke(
                                LinearGradient(colors: [Color.white.opacity(0.45), Color(hex: a.tint).opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 0.9))
                            .shadow(color: Color(hex: a.tint).opacity(0.35), radius: 6)
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

    // a single line opens under Zuffi: type, or add a picture / file
    private var chatLine: some View {
        HStack(spacing: 6) {
            Button { attach(images: false) } label: { Image(systemName: "paperclip").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.plain).help("Add a file (PDF, Excel, Word…)")
            Button { attach(images: true) } label: { Image(systemName: "photo").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.plain).help("Add a picture")
            if case .file(let name, _)? = state.promptContext {
                Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1).padding(.horizontal, 6).frame(height: 18)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }
            TextField("Ask Zuffi…", text: $home.draft)
                .textFieldStyle(.plain).font(.system(size: 12.5)).focused($typing)
                .onSubmit(send)
            Button { VoiceEngine.shared.listenOnce() } label: { Image(systemName: listening ? "waveform" : "mic.fill").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.plain).disabled(!VoiceEngine.micOn).help("Talk")
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#1A1008"))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)))
            }.buttonStyle(.plain)
        }
        .foregroundColor(.white.opacity(0.85))
        .padding(.horizontal, 10).frame(height: 36)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 0.8))
    }

    private func attach(images: Bool) {
        let p = NSOpenPanel()
        p.allowedContentTypes = images ? [.image] : [.item]
        p.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        state.promptContext = .file(name: u.lastPathComponent, fileURL: u)
        typing = true
    }

    private func send() {
        let q = home.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty || state.promptContext != nil else { return }
        home.draft = ""
        state.chatHistory.append(ChatMessage(role: .user, content: q.isEmpty ? "Here's a file" : q))
        state.stateOverride = .thinking
        let ctx = state.promptContext
        Task { await AIService.shared.chat(query: q, context: ctx, state: state) }
    }

    private var micRow: some View {
        HStack(spacing: 6) {
            Button { VoiceEngine.shared.setMic(!VoiceEngine.micOn) } label: {
                Label(VoiceEngine.micOn ? "Mic on" : "Mic off", systemImage: VoiceEngine.micOn ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(VoiceEngine.micOn ? .white : Color(hex: "#FF8A8F"))
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(VoiceEngine.micOn ? Color.white.opacity(0.2) : Color(hex: "#E5484D").opacity(0.6), lineWidth: 0.8))
            }.buttonStyle(.plain).help("Turn the microphone on or off")
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { home.chatOpen = true } } label: {
                Label("Type", systemImage: "keyboard").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8))
            }.buttonStyle(.plain)
            Button { VoiceEngine.shared.listenOnce() } label: {
                Image(systemName: listening ? "waveform" : "mic.circle.fill").font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1008"))
                    .frame(width: 26, height: 26)
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
                    .frame(width: 26, height: 26).background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.6))
            }.buttonStyle(.plain).help("Back to Zuffi")
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#F7C948"))
            Text(title).font(.system(size: 13, weight: .bold, design: .rounded))
            Spacer()
            if let trailing { trailing }
            Button { NotificationCenter.default.post(name: .islandCollapse, object: nil) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .frame(width: 26, height: 26).background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.6))
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
    var trailing: AnyView? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            ZuffiSpaceBackground()
            VStack(spacing: 8) {
                ZuffiPanelBar(title: title, icon: icon, trailing: trailing)
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(10)
        }
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
