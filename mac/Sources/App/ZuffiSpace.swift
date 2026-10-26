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
    @ObservedObject private var look = ZuffiLook.shared
    private static let dots: [(CGFloat, CGFloat, CGFloat, Double)] = {
        var g = SystemRandomNumberGenerator()
        return (0..<46).map { _ in
            (CGFloat.random(in: 0...1, using: &g), CGFloat.random(in: 0...1, using: &g),
             CGFloat.random(in: 0.6...1.8, using: &g), Double.random(in: 0...6.28, using: &g))
        }
    }()

    // Graphite on normal days (no more purple); the season's sky, colour and little effects when Zuffi dresses up.
    var body: some View {
        let s = look.season
        let top = Color(hex: s.sky.first ?? "#0B0B0D"), bottom = Color(hex: s.sky.last ?? "#16171C")
        let accent = Color(hex: s.accent ?? "#EDB24E")
        TimelineView(.animation(minimumInterval: 1 / 24, paused: false)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                    Gradient(colors: [top.opacity(0.92 * intensity), bottom.opacity(0.9 * intensity)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                // one soft glow in the season's colour, low behind Zuffi
                var glow = ctx
                glow.addFilter(.blur(radius: min(size.width, size.height) * 0.22))
                let r = min(size.width, size.height) * 0.42 * (1 + 0.06 * sin(t * 0.4))
                glow.fill(Path(ellipseIn: CGRect(x: size.width * 0.5 - r, y: size.height * 0.78 - r * 0.6, width: r * 2, height: r * 1.2)),
                          with: .color(accent.opacity((s.id == "none" ? 0.10 : 0.22) * intensity)))
                for (i, (x, y, sz, ph)) in Self.dots.enumerated() {
                    switch s.fx ?? "" {
                    case "snow":
                        let yy = (y + CGFloat(t * 0.035 * Double(sz))).truncatingRemainder(dividingBy: 1.05)
                        let xx = x * size.width + CGFloat(sin(t * 0.8 + ph) * 6)
                        ctx.fill(Path(ellipseIn: CGRect(x: xx, y: yy * size.height, width: sz * 2.2, height: sz * 2.2)), with: .color(.white.opacity(0.8 * intensity)))
                    case "confetti":
                        let yy = (y + CGFloat(t * 0.05 * Double(sz))).truncatingRemainder(dividingBy: 1.05)
                        let cols = s.id == "independence" ? ["#2FA866", "#FFFFFF"] : s.id == "eid" ? ["#E9C46A", "#4FD1A5", "#FFFFFF"] : ["#FFD166", "#F27BA1", "#7FD8BE", "#B79CFF"]
                        var c = ctx; c.translateBy(x: x * size.width, y: yy * size.height); c.rotate(by: .radians(t * 2 + ph))
                        c.fill(Path(roundedRect: CGRect(x: -2.5, y: -4, width: 5, height: 8), cornerRadius: 1.5), with: .color(Color(hex: cols[i % cols.count]).opacity(0.85 * intensity)))
                    case "hearts", "embers":
                        let yy = 1 - (y + CGFloat(t * 0.03 * Double(sz))).truncatingRemainder(dividingBy: 1.1)
                        if s.fx == "hearts" && i % 3 == 0 {
                            ctx.draw(Text("♥").font(.system(size: 8 + sz * 4)).foregroundColor(Color(hex: "#FF8FB1").opacity(0.55 * intensity)), at: CGPoint(x: x * size.width, y: yy * size.height))
                        } else if s.fx == "embers" && i % 2 == 0 {
                            ctx.fill(Path(ellipseIn: CGRect(x: x * size.width, y: yy * size.height, width: sz * 2, height: sz * 2)), with: .color(Color(hex: "#FFB067").opacity(0.7 * intensity)))
                        }
                    case "stars":
                        let a = 0.3 + 0.7 * abs(sin(t * 1.1 + ph))
                        ctx.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height * 0.7, width: sz, height: sz)), with: .color(Color(hex: "#FFF6D8").opacity(a * intensity)))
                    case "sun":
                        if i == 0 {
                            var sun = ctx; sun.addFilter(.blur(radius: 30))
                            let rr = size.width * 0.32 * (1 + 0.05 * sin(t * 0.5))
                            sun.fill(Path(ellipseIn: CGRect(x: size.width * 0.86 - rr, y: -rr * 0.6, width: rr * 2, height: rr * 2)), with: .color(Color(hex: "#FFD66E").opacity(0.35 * intensity)))
                        }
                    default:
                        // everyday: a few very quiet stars
                        if i % 3 == 0 {
                            let a = 0.15 + 0.35 * abs(sin(t * 0.9 + ph))
                            ctx.fill(Path(ellipseIn: CGRect(x: x * size.width, y: y * size.height, width: sz, height: sz)), with: .color(.white.opacity(a * intensity)))
                        }
                    }
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
        HomeAction(id: "more", icon: "square.grid.2x2.fill", label: "All features", tint: "#4C8DFF"),
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
        HomeAction(id: "save", icon: "square.and.arrow.down.fill", label: "Save some data", tint: "#FDE68A"),
        HomeAction(id: "business", icon: "briefcase.fill", label: "Business", tint: "#F58FA8"),
        HomeAction(id: "convert", icon: "arrow.triangle.2.circlepath", label: "Convert a file", tint: "#38BDF8"),
        HomeAction(id: "record", icon: "record.circle", label: "Record my screen", tint: "#F87171"),
        HomeAction(id: "meeting", icon: "waveform.badge.mic", label: "Meeting notes", tint: "#F472B6"),
        HomeAction(id: "profile", icon: "person.crop.circle.fill", label: "Me (profile)", tint: "#C4B5FD"),
        HomeAction(id: "room", icon: "person.3.sequence.fill", label: "Room mode (follow the conversation)", tint: "#F4505E"),
    ]
    static func find(_ id: String) -> HomeAction? { all.first { $0.id == id } }
    static let defaultLeft = ["chat", "settings", "more", "profile"]
    /// Only the important ones beside Zuffi; everything else is in All features. One Business button, no calendar/appointment buttons.
    static let defaultRight = ["convert", "record", "screen", "business"]
    /// Bumped when the home buttons are re-thought, so old saved choices (appointments, bookings…) are replaced once.
    static let layoutVersion = 3
    @MainActor static func migrate() {
        let d = UserDefaults.standard
        guard d.integer(forKey: "homeButtonsVersion") < layoutVersion else { return }
        d.set(layoutVersion, forKey: "homeButtonsVersion")
        d.removeObject(forKey: "homeLeft"); d.removeObject(forKey: "homeRight")
    }

    @MainActor static var left: [String] {
        get { migrate(); return (UserDefaults.standard.stringArray(forKey: "homeLeft") ?? defaultLeft).filter { find($0) != nil } }
        set { UserDefaults.standard.set(newValue, forKey: "homeLeft") }
    }
    @MainActor static var right: [String] {
        get {
            migrate()
            // "Just me" or no Business plan → the Business button becomes Agents
            let biz = ZuffiPlan.shared.isBusiness && !ZuffiPlan.shared.isPersonal
            return (UserDefaults.standard.stringArray(forKey: "homeRight") ?? defaultRight)
                .map { $0 == "business" && !biz ? "agents" : $0 }.filter { find($0) != nil }
        }
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

    /// Choose a file → it lands in the notch like a dropped file (Ask · Convert · More · Email).
    @MainActor static func pickAndDrop() {
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.message = "Choose a file for Zuffi"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let url = p.url else { return }
        // Straight to the formats — no drop animation (the notch was closed while you picked, so it would play on a black notch).
        let st = AppState.shared
        st.droppedFile = DroppedFile(url: url, name: url.lastPathComponent)
        st.promptContext = .file(name: url.lastPathComponent, fileURL: url)
        st.chooseMode = "convert"
        UploadSequenceEngine.shared.deactivate()
        // after the file window closes, open the notch on the formats (a moment later, so nothing folds it straight back)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { ZuffiNav.go(.choose) } }
    }

    @MainActor static func run(_ id: String, home: ZuffiHomeModel) {
        if ZuffiPlan.shared.isLocked && id != "settings" { ZuffiPlan.shared.openAccount(); return }
        switch id {
        case "chat": ZuffiChat.shared.open()
        case "settings": ZuffiNav.go(.settings)
        case "more": ZuffiNav.go(.features)
        case "convert": pickAndDrop()
        case "record": Task { await Assistant.run(ScreenRecorder.shared.isRecording ? "stop recording" : "record my screen", spoken: false) }
        case "meeting": Task { await Assistant.run(MeetingNotes.shared.active ? "stop meeting notes" : "take meeting notes", spoken: true) }
        case "profile": ZuffiNav.go(.profile)
        case "room": RoomListener.shared.toggle()
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
    @ObservedObject private var usage = AIUsage.shared
    @ObservedObject private var planBox = ZuffiPlan.shared
    @ObservedObject private var room = RoomListener.shared
    @ObservedObject private var music = NowPlaying.shared
    @StateObject private var head = SparrowSpriteModel()
    @State private var hover: String?
    @State private var entered = false

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
            let c = zClean(last.content)
            if !c.isEmpty { return c }
        }
        if !voice.micEnabled { return "My mic is off — tap “Mic off” or my face to talk" }
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
                    pager.frame(width: W - 20 - side * 2)
                    column(home.right, round: false).frame(width: side)
                }
                .frame(width: W - 20)
                Spacer(minLength: 0)
                // battery, weather, AirPods & co, and how busy the Mac is (AI usage lives in Settings → AI)
                StatusChips().padding(.bottom, 3).help(usage.notchLine)
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
        .onAppear { NowUsing.shared.start(); NowPlaying.shared.start(); NotchGlance.shared.refresh(); home.reloadButtons(); entered = true }
        .onDisappear { entered = false }
    }

    // Zuffi · Today (prayers, next reminder, weather) · Music · Me — swipe sideways or tap the dots; it never moves by itself.
    @State private var page: Int? = 0
    private static let pages = ["Zuffi", "Today", "Music", "Me"]
    private var pager: some View {
        let pw = W - 20 - side * 2
        return VStack(spacing: 5) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    VStack(spacing: 6) {
                        // the little bunny head that follows your cursor
                        Group {
                            if true {
                                LiveBunnyFace(size: room.on ? 60 : 96)
                                    .contentShape(Rectangle()).onTapGesture { VoiceEngine.shared.listenOnce() }
                            } else {
                                SparrowSpriteView(model: head, size: room.on ? 56 : 92, deadZone: 40, mood: mood) { VoiceEngine.shared.listenOnce() }
                            }
                        }
                            .frame(width: room.on ? 60 : 96, height: room.on ? 60 : 96)
                            .frame(width: pw - 8)
                            .overlay(alignment: .topTrailing) { NotchAgentsRow().padding(.trailing, 6) }
                        if room.on {
                            RoomModeCard().frame(width: pw - 8)
                        } else if NowPlaying.shared.hasTrack {
                            // music playing: one line of Zuffi's words + the music controls
                            Text(words).font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.94))
                                .multilineTextAlignment(.center).lineLimit(1).frame(width: pw - 8)
                            MiniMusicBar().frame(width: pw - 6)
                        } else {
                            Text(words)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.94))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .frame(width: pw - 8)
                                .animation(.easeInOut(duration: 0.2), value: words)
                        }
                    }
                    .frame(width: pw, height: 158).id(0)
                    NotchTodayPage().padding(.horizontal, 8).frame(width: pw, height: 158).id(1)
                    NowPlayingCard().padding(.horizontal, 8).frame(width: pw, height: 158).id(2)
                    NotchMePage().frame(width: pw, height: 158).id(3)
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $page)
            .frame(width: pw, height: 158)
            HStack(spacing: 6) {
                ForEach(0..<Self.pages.count, id: \.self) { i in
                    Capsule().fill(Color.white.opacity((page ?? 0) == i ? 0.9 : 0.3))
                        .frame(width: (page ?? 0) == i ? 14 : 5, height: 5)
                        .contentShape(Rectangle().inset(by: -4))
                        .onTapGesture { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { page = i } }
                        .help(Self.pages[i])
                }
            }
            .animation(.easeOut(duration: 0.2), value: page)
        }
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
                    .buttonStyle(NotePress())
                    // opening the notch: the buttons pop in one after another, from the bunny outwards
                    .scaleEffect(entered ? 1 : 0.5).opacity(entered ? 1 : 0)
                    .offset(x: entered ? 0 : (round ? 18 : -18))
                    .animation(.spring(response: 0.42, dampingFraction: 0.7).delay(0.05 + Double(i) * 0.045), value: entered)
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
            Button { VoiceEngine.shared.setMic(!voice.micEnabled) } label: {
                Label(voice.micEnabled ? "Mic on" : "Mic off", systemImage: voice.micEnabled ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(voice.micEnabled ? .white : Color(hex: "#FF8A8F"))
                    .padding(.horizontal, 10).frame(height: 28)
                    .liquidGlass(Capsule(), tint: voice.micEnabled ? nil : Color(hex: "#E5484D"), interactive: true)
                    .contentShape(Capsule())
            }.buttonStyle(.plain).help("Turn the microphone on or off")
            Button { ZuffiChat.shared.open() } label: {
                Label("Chat", systemImage: "bubble.left.fill").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 12).frame(height: 28)
                    .liquidGlass(Capsule(), interactive: true)
            }.buttonStyle(.plain)
            if !ZuffiPlan.shared.isPersonal { Button { BusinessDashboard.shared.show() } label: {
                Label("Business", systemImage: planBox.isBusiness ? "briefcase.fill" : "lock.fill").font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 10).frame(height: 28)
                    .liquidGlass(Capsule(), tint: Color(hex: "#C77DFF"), glow: Color(hex: "#F58FA8"), interactive: true)
            }.buttonStyle(.plain).help("Your leads, WhatsApp inbox, team and automations") }
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
                Button { if let u = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") { NSWorkspace.shared.open(u) } } label: {
                    NotchListRowLabel(icon: "envelope.badge.fill", tint: "#2F80ED", title: "Add Gmail / Outlook to Mail", sub: "Then every new email shows here")
                }.buttonStyle(.plain)
                row("bell.badge", "Notifications at the notch (email, battery, devices)", on: Binding(get: { MacStatus.shared.toastsOn }, set: { MacStatus.shared.toastsOn = $0 }))
                if ZuffiFocus.whatsapp && ZuffiPlan.shared.isBusiness && !ZuffiPlan.shared.isPersonal {
                    row("message.fill", "WhatsApp linked to Zuffi (new messages instantly)", on: Binding(get: { WhatsAppLink.shared.enabled }, set: { $0 ? WhatsAppLink.shared.showWindow() : (WhatsAppLink.shared.enabled = false) }))
                    row("speaker.wave.2.bubble.left.fill", "Read new WhatsApp messages out loud", on: Binding(get: { WhatsAppLink.shared.readAloud }, set: { WhatsAppLink.shared.readAloud = $0 }))
                    row("arrowshape.turn.up.left.2.fill", "Auto-reply to customers on WhatsApp", on: Binding(get: { ZuffiCRM.shared.isOn(.autopilot) }, set: { ZuffiCRM.shared.set(.autopilot, $0) }))
                }
                row("person.3.sequence.fill", "Room mode — follow the conversation (nothing saved)", on: Binding(get: { RoomListener.shared.on }, set: { $0 ? RoomListener.shared.start() : RoomListener.shared.stop() }))
                row("waveform.badge.mic", "Ask to take notes when a call starts", on: Binding(get: { MeetingWatcher.shared.enabled }, set: { MeetingWatcher.shared.enabled = $0 }))
                row("bell.badge.fill", "Read notifications out loud", on: Binding(
                    get: { UserDefaults.standard.bool(forKey: AssistantPrefs.readNotes) },
                    set: { UserDefaults.standard.set($0, forKey: AssistantPrefs.readNotes); NotificationReader.shared.setEnabled($0) }))
                row("hare.fill", "Cute bunny voice", on: $bunny)
                row("light.max", "Glow around the notch", on: $glow.enabled)
                row("rectangle.topthird.inset.filled", "Show Zuffi by the notch when closed", on: Binding(
                    get: { IslandStateMachine.alwaysShowZuffi },
                    set: { UserDefaults.standard.set($0, forKey: "alwaysShowZuffi"); AppState.shared.syncMode() }))
                if !ZuffiWalk.petNever {
                    row("figure.walk", "Zuffi on screen (pet)", on: Binding(get: { PetController.shared.isShown }, set: { $0 ? PetController.shared.show() : PetController.shared.hide() }))
                    row("bell.and.waves.left.and.right", "The pet brings reminders (water, meetings…)", on: Binding(get: { ZuffiWalk.petBringsReminders }, set: { UserDefaults.standard.set($0, forKey: "petReminders") }))
                }
                Button { ZuffiModeWindow.shared.show() } label: {
                    NotchListRowLabel(icon: "person.2.fill", tint: "#F59E3B", title: "Zuffi is for: \(ZuffiPlan.shared.mode?.title ?? "not chosen")", sub: "Personal assistant, business, freelancer, company or creator — change")
                }.buttonStyle(.plain)
                row("waveform", "Music bars & working agents under the notch", on: Binding(get: { UserDefaults.standard.object(forKey: "notchHang") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "notchHang") }))
                row("rectangle.connected.to.line.below", "Show the Manager window when tasks are given out", on: Binding(get: { MissionControl.shared.enabled }, set: { UserDefaults.standard.set($0, forKey: "missionWindow") }))
                row("person.3.sequence.fill", "Show AI agents on screen while they work", on: Binding(get: { AgentStage.shared.enabled }, set: { AgentStage.shared.enabled = $0 }))
                row("eye.slash.fill", "Never show the pet on screen", on: Binding(get: { ZuffiWalk.petNever }, set: { UserDefaults.standard.set($0, forKey: "petNever"); if $0 { PetController.shared.hide() } }))
                AuroraColorPicker()
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).opacity(0.8))
                homeButtons
                HStack(spacing: 6) {
                    pill("clock.arrow.circlepath", "History") { ZuffiNav.go(.history) }
                    pill("person.crop.circle.fill", "Me") { ZuffiNav.go(.profile) }
                    pill("square.grid.2x2.fill", "Features") { ZuffiNav.go(.features) }
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
        let _ = listening
        LiveBunnyFace(size: height)
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

// MARK: All features — a Settings-style list inside the notch (replaces the big dashboard window on the Mac)

struct NotchFeature: Identifiable {
    let id: String, cat: String, icon: String, tint: String, name: String, sub: String
    var business = false
}

struct NotchFeaturesList: View {
    @ObservedObject private var plan = ZuffiPlan.shared
    @State private var query = ""

    static let cats: [(String, String)] = [("business", "Business"), ("files", "Files & PDF"), ("everyday", "Every day"), ("create", "Create"), ("devices", "This Mac & devices")]
    static let all: [NotchFeature] = [
        NotchFeature(id: "business", cat: "business", icon: "briefcase.fill", tint: "#F58FA8", name: "Business", sub: "Your AI team: posts, reviews, competitors, weekly report", business: true),
        NotchFeature(id: "aiteam", cat: "business", icon: "person.3.sequence.fill", tint: "#5B6CFF", name: "AI Team", sub: "Hire specialists, give them jobs — led by a Team Manager", business: true),
        NotchFeature(id: "agentbrowser", cat: "devices", icon: "safari.fill", tint: "#7C3AED", name: "Agents at work", sub: "Watch your helpers work in their own browser tabs — pause or take over"),
        NotchFeature(id: "convert", cat: "files", icon: "arrow.triangle.2.circlepath", tint: "#38BDF8", name: "Convert a file", sub: "JPG, PNG, WebP, PDF, text"),
        NotchFeature(id: "sign", cat: "files", icon: "signature", tint: "#22A06B", name: "Sign a PDF", sub: "Draw your signature, done"),
        NotchFeature(id: "merge", cat: "files", icon: "square.stack.3d.up.fill", tint: "#E25A5A", name: "Merge PDFs", sub: "Join several into one"),
        NotchFeature(id: "images", cat: "files", icon: "photo.on.rectangle", tint: "#F08A3E", name: "Photos → PDF", sub: "Pictures into one PDF"),
        NotchFeature(id: "pages", cat: "files", icon: "doc.on.doc.fill", tint: "#D9A21B", name: "Keep pages", sub: "Pick the pages you need"),
        NotchFeature(id: "rotate", cat: "files", icon: "rotate.right.fill", tint: "#0EA5E9", name: "Rotate PDF", sub: "Turn pages the right way"),
        NotchFeature(id: "office", cat: "files", icon: "doc.richtext.fill", tint: "#2B6CD8", name: "Word, Excel & PowerPoint", sub: "Describe it — get the file"),
        NotchFeature(id: "data", cat: "files", icon: "tablecells.fill", tint: "#34D399", name: "My data (Excel)", sub: "Sheets Zuffi keeps for you"),
        NotchFeature(id: "planday", cat: "everyday", icon: "calendar", tint: "#4F6BFF", name: "Plan my day", sub: "Fits tasks around your calendar"),
        NotchFeature(id: "today", cat: "everyday", icon: "sun.max.fill", tint: "#FBC56A", name: "Today", sub: "Prayer times, reminders, weather"),
        NotchFeature(id: "meeting", cat: "everyday", icon: "waveform.badge.mic", tint: "#E5577E", name: "Meeting notes", sub: "Record a call, get a clean summary"),
        NotchFeature(id: "room", cat: "everyday", icon: "person.3.sequence.fill", tint: "#F4505E", name: "Room mode", sub: "Follows the talk in the room, shows topics — nothing saved"),
        NotchFeature(id: "memory", cat: "everyday", icon: "brain.head.profile", tint: "#8B7CF6", name: "Memory", sub: "Notes, chats and files Zuffi remembers"),
        NotchFeature(id: "history", cat: "everyday", icon: "clock.arrow.circlepath", tint: "#C4B5FD", name: "Past chats", sub: "Everything you asked"),
        NotchFeature(id: "focus", cat: "everyday", icon: "scope", tint: "#E0A23B", name: "Focus timer", sub: "25 minutes of deep work"),
        NotchFeature(id: "snippets", cat: "everyday", icon: "text.badge.plus", tint: "#14A39A", name: "Snippets", sub: "Text you paste often"),
        NotchFeature(id: "activity", cat: "everyday", icon: "arrow.uturn.backward.circle.fill", tint: "#7A8496", name: "Activity & undo", sub: "What Zuffi did — undo anything"),
        NotchFeature(id: "agents", cat: "everyday", icon: "sparkles", tint: "#F7C948", name: "Agents", sub: "Jobs Zuffi is doing for you"),
        NotchFeature(id: "jobs", cat: "everyday", icon: "briefcase", tint: "#A161E8", name: "Job agent", sub: "Find jobs, tailor your CV"),
        NotchFeature(id: "picture", cat: "create", icon: "wand.and.stars", tint: "#A161E8", name: "Make a picture", sub: "Images and posters from words"),
        NotchFeature(id: "studio", cat: "create", icon: "camera.filters", tint: "#E5577E", name: "Photo studio", sub: "Brighten, resize, add your logo"),
        NotchFeature(id: "blur", cat: "create", icon: "eye.slash.fill", tint: "#64748B", name: "Blur private info", sub: "Faces, emails and numbers in a picture"),
        NotchFeature(id: "reels", cat: "create", icon: "film.fill", tint: "#EF5A5A", name: "Quick reels", sub: "Trim, caption, ready to post"),
        NotchFeature(id: "record", cat: "devices", icon: "record.circle", tint: "#F87171", name: "Record my screen", sub: "With sound — saved in Movies"),
        NotchFeature(id: "screen", cat: "devices", icon: "eye.fill", tint: "#7CC4FF", name: "What's on my screen?", sub: "Zuffi looks and explains"),
        NotchFeature(id: "walink", cat: "business", icon: "message.fill", tint: "#25D366", name: "Link WhatsApp", sub: "Messages instantly, leads, auto-replies", business: true),
        NotchFeature(id: "send", cat: "devices", icon: "paperplane.fill", tint: "#2F6FEB", name: "Send to my devices", sub: "Files and links to your phone"),
        NotchFeature(id: "sync", cat: "devices", icon: "arrow.triangle.2.circlepath.circle.fill", tint: "#14A37F", name: "Sync devices", sub: "Same Zuffi everywhere"),
        NotchFeature(id: "find", cat: "devices", icon: "magnifyingglass", tint: "#7A8496", name: "Find files", sub: "Search by what you remember"),
        NotchFeature(id: "tidy", cat: "devices", icon: "tray.full.fill", tint: "#D9628F", name: "Tidy Downloads", sub: "Sort the mess in one tap"),
        NotchFeature(id: "clipboard", cat: "devices", icon: "doc.on.clipboard.fill", tint: "#8B6CF0", name: "Clipboard", sub: "Everything you copied"),
        NotchFeature(id: "watch", cat: "devices", icon: "folder.badge.gearshape", tint: "#0891B2", name: "Watch a folder", sub: "Act when new files arrive"),
        NotchFeature(id: "pet", cat: "devices", icon: "hare.fill", tint: "#FFB7C5", name: "Zuffi on screen", sub: "A little friend on your desktop"),
    ]

    private var visible: [NotchFeature] {
        let biz = plan.isBusiness && !plan.isPersonal
        let words = query.lowercased().split(separator: " ").map(String.init)
        return Self.all.filter { f in
            if f.business && !biz { return false }
            if f.id == "walink" && !ZuffiFocus.whatsapp { return false }
            if f.id == "jobs" && biz { return false }
            let hay = (f.name + " " + f.sub).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.55))
                TextField("Search features", text: $query).textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(.white)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.09)))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    let list = visible
                    ForEach(0..<Self.cats.count, id: \.self) { ci in
                        let rows = list.filter { $0.cat == Self.cats[ci].0 }
                        if !rows.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Self.cats[ci].1.uppercased()).font(.system(size: 9.5, weight: .heavy)).tracking(0.6)
                                    .foregroundColor(.white.opacity(0.45)).padding(.leading, 6)
                                VStack(spacing: 0) {
                                    ForEach(0..<rows.count, id: \.self) { i in
                                        NotchListRow(icon: rows[i].icon, tint: rows[i].tint, title: rows[i].name, sub: rows[i].sub) { Self.open(rows[i].id) }
                                        if i < rows.count - 1 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 44) }
                                    }
                                }
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                            }
                        }
                    }
                    if list.isEmpty { Text("Nothing matches “\(query)”.").font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).padding(8) }
                }
                .padding(.bottom, 8)
            }
        }
    }

    /// Native when Zuffi can do it in the notch; otherwise a small window with just that one tool.
    @MainActor static func open(_ id: String) {
        if ZuffiPlan.shared.isLocked { ZuffiPlan.shared.openAccount(); return }
        let home = ZuffiHomeModel.shared
        switch id {
        case "room": RoomListener.shared.toggle(); ZuffiNav.go(.overview)   // from the list → back to home, where the room card shows
        case "walink": WhatsAppLink.shared.showWindow(); NotificationCenter.default.post(name: .islandCollapse, object: nil)
        case "aiteam": BusinessDashboard.shared.show(.aiTeam); NotificationCenter.default.post(name: .islandCollapse, object: nil)
        case "agentbrowser": AgentBrowser.shared.show(); NotificationCenter.default.post(name: .islandCollapse, object: nil)
        case "business", "convert", "record", "screen", "agents", "data", "history", "pet", "meeting", "today":
            // Only fold the notch for things that open their own window; the rest show their answer in the notch.
            if id == "screen" || id == "record" || id == "meeting" { ZuffiNav.go(.overview) }
            HomeAction.run(id, home: home)
            if ["business", "pet", "today"].contains(id) { NotificationCenter.default.post(name: .islandCollapse, object: nil) }
        default:
            WebHub.shared.showTool(id)
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }
}

/// One row in a notch list: coloured icon tile, title, a short line, chevron.
struct NotchListRow: View {
    let icon: String, tint: String, title: String, sub: String
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: tint).gradient))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Text(sub).font(.system(size: 10)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 9.5, weight: .bold)).foregroundColor(.white.opacity(0.35))
            }
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: Me — the details from the welcome form, in the notch

struct ZuffiProfilePanel: View {
    @ObservedObject private var plan = ZuffiPlan.shared

    private var p: [String: String] { plan.profile }
    private func val(_ k: String) -> String? { let v = p[k]?.trimmingCharacters(in: .whitespaces) ?? ""; return v.isEmpty ? nil : v }

    private var rows: [(String, String, String, String)] {   // icon, tint, label, value
        var r: [(String, String, String, String)] = []
        if let d = val("dob") { r.append(("gift.fill", "#F472B6", "Birthday", Self.niceDate(d))) }
        if let c = val("city") { r.append(("mappin.circle.fill", "#38BDF8", "City", c)) }
        if let c = val("country") { r.append(("globe", "#34D399", "Country", c == "PK" ? "Pakistan" : c == "GB" ? "United Kingdom" : c)) }
        r.append(("person.2.fill", "#C4B5FD", "Zuffi is for", p["type"] == "business" ? "My business" : "Just me"))
        if let b = val("business") { r.append(("briefcase.fill", "#F58FA8", "Business", b)) }
        if let k = val("kind") { r.append(("tag.fill", "#FBC56A", "Type", Self.kindName(k))) }
        if let role = val("role") { r.append(("person.text.rectangle.fill", "#7CC4FF", "My role", role)) }
        if let h = val("hours") { r.append(("clock.fill", "#A7F3D0", "Hours", h)) }
        if let h = val("help") { r.append(("hand.raised.fill", "#FDE68A", "Help me with", h.replacingOccurrences(of: ",", with: ", "))) }
        if let j = val("job") { r.append(("bag.fill", "#7CC4FF", "Work", j)) }
        if let h = val("hobbies") { r.append(("figure.run", "#34D399", "Hobbies", h)) }
        if let f = val("family") { r.append(("heart.fill", "#F472B6", "Family", f)) }
        if let f = val("fav") { r.append(("star.fill", "#FBC56A", "Favourites", f)) }
        if let n = val("notes") { r.append(("note.text", "#E5E7EB", "Notes", n)) }
        return r
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    let name = val("name") ?? "You"
                    Text(String(name.prefix(1)).uppercased()).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(LinearGradient(colors: [IslandConst.accent, Color(hex: "#F472B6")], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white).lineLimit(1)
                        Text(plan.isBusiness ? "Business plan" : plan.isPaid ? "Pro plan" : "Free").font(.system(size: 10.5, weight: .semibold)).foregroundColor(.white.opacity(0.6))
                    }
                    Spacer()
                    Button { WebHub.shared.showTool("profile"); NotificationCenter.default.post(name: .islandCollapse, object: nil) } label: {
                        Label("Edit", systemImage: "pencil").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color.white.opacity(0.14)))
                    }.buttonStyle(.plain)
                }
                .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))

                if p.isEmpty {
                    Text("Tell Zuffi about you once and she’ll remember it — your birthday, city, work and what you want help with.")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center).padding(8)
                } else {
                    VStack(spacing: 0) {
                        ForEach(0..<rows.count, id: \.self) { i in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: rows[i].0).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                                    .frame(width: 24, height: 24).background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: rows[i].1).gradient))
                                Text(rows[i].2).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).frame(width: 78, alignment: .leading).padding(.top, 4)
                                Text(rows[i].3).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
                                    .textSelection(.enabled)
                            }
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            if i < rows.count - 1 { Divider().overlay(Color.white.opacity(0.08)).padding(.leading, 42) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.07)))
                }
                Text("Only on your devices. Zuffi uses this to answer questions about you.").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.4))
            }
        }
    }

    static func niceDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let o = DateFormatter(); o.dateStyle = .long; return o.string(from: d)
    }
    static func kindName(_ k: String) -> String {
        ["realEstate": "Estate agent", "salon": "Salon / barber", "clinic": "Clinic", "shop": "Shop", "restaurant": "Restaurant / café", "services": "Trades & services", "freelancer": "Freelancer"][k] ?? k
    }
}

// =====================================================================
// MARK: - The notch, new design: one wide glass panel
//
// Row 1 — Aurora's face in a colour ring · "Ask Zuffi" box + what's playing · your agents' faces + "Give a task".
// Row 2 — the notification bar (newest message, how many more).
// Row 3 — each agent and what it's doing right now.
// =====================================================================

/// The last few notifications that came to the notch (so the bar can show the newest and how many more).
@MainActor
final class NotchInbox: ObservableObject {
    static let shared = NotchInbox()
    struct Note: Identifiable { let id = UUID(); let head: String; let body: String; let icon: String; let action: String?; let at: Date }
    @Published private(set) var notes: [Note] = []
    func add(_ head: String, _ body: String, icon: String, action: String?) {
        notes.insert(Note(head: head, body: body, icon: icon, action: action, at: Date()), at: 0)
        if notes.count > 12 { notes.removeLast(notes.count - 12) }
    }
    func clear() { notes.removeAll() }
}

enum NotchDesign {
    /// The wide glass notch (on by default). Off = the older tall home panel.
    static var on: Bool { UserDefaults.standard.object(forKey: "notchWide") as? Bool ?? true }
}

struct NotchHomeView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var music = NowPlaying.shared
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var inbox = NotchInbox.shared
    @ObservedObject private var hang = NotchHang.shared
    @State private var ask = ""
    @FocusState private var askFocus: Bool

    private let W = IslandConst.width(for: .overview)
    private let H = IslandConst.viewLayouts[.overview]!.height
    private var agents: [TeamAgent] { team.hiredAgents.isEmpty ? team.focusAgents : team.hiredAgents }
    private let pillFill = Color.white.opacity(0.12), pillLine = Color.white.opacity(0.16)

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear.frame(width: W, height: H).contentShape(Rectangle()).movesIsland()
            VStack(spacing: 12) {
                topRow
                noteBar
                agentTiles
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 44)
            .frame(width: W, height: H, alignment: .top)
        }
        .frame(width: W, height: H)
        .onAppear { NowPlaying.shared.start() }
    }

    // MARK: row 1
    private var topRow: some View {
        HStack(spacing: 16) {
            // Aurora in a colour ring, with the mic badge
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(AngularGradient(colors: [Color(hex: "#F5B963"), Color(hex: "#F58FA8"), Color(hex: "#B79CFF"), Color(hex: "#F5B963")], center: .center))
                    .frame(width: 66, height: 66)
                Circle().fill(RadialGradient(colors: [Color(hex: "#FFF6F7"), Color(hex: "#F3DDE2")], center: .center, startRadius: 2, endRadius: 34))
                    .frame(width: 60, height: 60).offset(x: -3, y: -3)
                LiveBunnyFace(size: 54).offset(x: -6, y: -6)
                Button { VoiceEngine.shared.listenOnce() } label: {
                    Image(systemName: voice.isListening ? "waveform" : "mic.fill").font(.system(size: 9.5, weight: .bold)).foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color(red: 0.12, green: 0.12, blue: 0.14).opacity(0.9)))
                        .overlay(Circle().stroke(Color.white.opacity(0.18)))
                }.buttonStyle(.plain).help("Talk to Zuffi")
            }
            .frame(width: 66, height: 66)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble").font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                    TextField("Ask Zuffi or give a job…", text: $ask)
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.white)
                        .focused($askFocus)
                        .onSubmit { send() }
                }
                .padding(.horizontal, 12).frame(height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pillFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(pillLine))
                Button { if music.hasTrack { music.send("playpause") } } label: {
                    HStack(spacing: 8) {
                        if music.playing || hang.audio { NotchBars(count: 7, width: 2, height: 12) } else { Image(systemName: "music.note").font(.system(size: 11)).foregroundColor(.white.opacity(0.6)) }
                        Text(music.hasTrack ? "\(music.title)\(music.artist.isEmpty ? "" : " · \(music.artist)")" : (hang.audio ? "Sound is playing" : "Nothing playing"))
                            .font(.system(size: 13)).foregroundColor(.white.opacity(music.hasTrack || hang.audio ? 1 : 0.6)).lineLimit(1)
                        Spacer(minLength: 4)
                        if music.hasTrack { Image(systemName: music.playing ? "pause.fill" : "play.fill").font(.system(size: 10)).foregroundColor(.white.opacity(0.8)) }
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(pillFill))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(pillLine))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                HStack(spacing: -7) {
                    ForEach(Array(agents.prefix(4))) { a in
                        AgentAvatar(agent: a, size: 28).clipShape(Circle())
                            .overlay(Circle().stroke(Color(hex: "#121318"), lineWidth: 2))
                            .help(a.name)
                    }
                    if agents.count > 4 {
                        Text("+\(agents.count - 4)").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#2A2140"))
                            .frame(width: 28, height: 28).background(Circle().fill(Color(hex: "#D9CCF5")))
                            .overlay(Circle().stroke(Color(hex: "#121318"), lineWidth: 2))
                    }
                }
                Button {
                    let q = ask.trimmingCharacters(in: .whitespacesAndNewlines)
                    if q.isEmpty { askFocus = true } else { ask = ""; MissionControl.shared.assign(q) }
                } label: {
                    Text("Give a task").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: "#111111"))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(Capsule().fill(Color.white))
                }.buttonStyle(.plain)
            }
            .frame(width: 150)
        }
    }

    private func send() {
        let q = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        ask = ""
        ZuffiChat.shared.ask(q)
    }

    // MARK: row 2 — notifications
    private var noteBar: some View {
        let n = inbox.notes.first
        let tint: Color = n?.action == "whatsapp" ? Color(hex: "#25D366") : n?.action == "mail" ? Color(hex: "#5B8CFF") : Color(hex: "#F5B963")
        return Button {
            if let n {
                state.noteAction = n.action; state.noteIsAlert = false
                state.noteMessage = "\(n.head)\n\(n.body)"
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
            }
        } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(n == nil ? Color.white.opacity(0.14) : tint).frame(width: 22, height: 22)
                    .overlay(Image(systemName: n?.icon ?? "bell").font(.system(size: 11, weight: .semibold)).foregroundColor(.white))
                if let n {
                    Text(n.head).font(.system(size: 12, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Text(n.body).font(.system(size: 12)).foregroundColor(.white.opacity(0.74)).lineLimit(1)
                } else {
                    Text("No new notifications").font(.system(size: 12)).foregroundColor(.white.opacity(0.6))
                }
                Spacer(minLength: 4)
                if inbox.notes.count > 1 {
                    Text("+\(inbox.notes.count - 1)").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#1A1206"))
                        .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(Color(hex: "#F5B963")))
                }
                if n != nil { Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.7)) }
            }
            .padding(.leading, 10).padding(.trailing, 12).frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(pillLine))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: row 3 — what each agent is doing
    private var agentTiles: some View {
        HStack(spacing: 8) {
            ForEach(Array(agents.prefix(4))) { a in
                let st = team.status(a)
                let run = team.runs.first { $0.agent == a.id }
                Button {
                    if st == .working { MissionControl.shared.show() } else { team.use(a); ZuffiChat.shared.open() }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(st == .working ? Color(hex: "#F5B963") : ZuffiTeam.color(st)).frame(width: 8, height: 8)
                            .opacity(st == .working ? 0.6 + 0.4 * abs(sin(Date().timeIntervalSinceReferenceDate * 3)) : 1)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(a.name).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                            Text(st == .working ? (run?.steps.last?.text ?? "Working…") : st == .active ? "Ready" : st.rawValue)
                                .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.74)).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.14)))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).help(a.description)
            }
        }
    }

    // MARK: small shortcuts
    private var footer: some View {
        HStack(spacing: 18) {
            shortcut("bubble.left.fill", "Chat") { ZuffiChat.shared.open() }
            shortcut("square.grid.2x2.fill", "Dashboard") { ZuffiHub.shared.show(.home) }
            shortcut("sparkles", "Features") { ZuffiNav.go(.features) }
            shortcut("hare.fill", PetController.shared.isShown ? "Hide pet" : "Show pet") { PetController.shared.toggle() }
            shortcut(voice.micEnabled ? "mic.fill" : "mic.slash.fill", voice.micEnabled ? "Mic on" : "Mic off") { VoiceEngine.shared.setMic(!voice.micEnabled) }
            shortcut("gearshape.fill", "Settings") { ZuffiHub.shared.show(.settings) }
        }
    }
    private func shortcut(_ icon: String, _ label: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.78))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// Closed notch: two glass wings beside the camera — Aurora's face on the left; music bars, working agents or a quiet dot on the right.
struct CompactWings: View {
    @ObservedObject var state: AppState
    @ObservedObject private var hang = NotchHang.shared
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var music = NowPlaying.shared
    let width: CGFloat
    let height: CGFloat
    let notch: CGFloat
    var body: some View {
        let working = team.runs.filter { $0.status == "Working" && Date().timeIntervalSince($0.started) < 900 }
        HStack(spacing: 0) {
            HStack { LiveBunnyFace(size: 24) }
                .frame(width: (width - notch) / 2, height: height)
                .contentShape(Rectangle())
            Color.clear.frame(width: notch)
            HStack(spacing: 6) {
                if hang.audio || music.playing {
                    NotchBars(count: 7, width: 2.5, height: 14)
                } else if !working.isEmpty {
                    HStack(spacing: -5) {
                        ForEach(working.prefix(3)) { r in
                            if let a = team.agent(r.agent) { AgentAvatar(agent: a, size: 16).clipShape(Circle()).overlay(Circle().stroke(Color.black, lineWidth: 1.5)) }
                        }
                    }
                    Text("\(working.count)").font(.system(size: 10.5, weight: .bold)).foregroundColor(.white.opacity(0.85))
                } else {
                    Circle().fill(Color(hex: "#3FC48C")).frame(width: 7, height: 7)
                }
            }
            .frame(width: (width - notch) / 2, height: height)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

/// Aurora's fur colour: a few ready colours, or any colour you like.
struct AuroraColorPicker: View {
    @State private var hex = AuroraColor.hex
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aurora's colour").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.65))
            HStack(spacing: 8) {
                ForEach(AuroraColor.presets, id: \.hex) { c in
                    Button { set(c.hex) } label: {
                        Circle().fill(Color(hex: c.hex)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(hex.lowercased() == c.hex.lowercased() ? Color(hex: "#3A6DF0") : Color.white.opacity(0.3), lineWidth: hex.lowercased() == c.hex.lowercased() ? 2.5 : 0.8))
                    }.buttonStyle(.plain).help(c.name)
                }
                ColorPicker("", selection: Binding(get: { Color(hex: hex) }, set: { c in
                    if let n = NSColor(c).usingColorSpace(.sRGB) { set(String(format: "#%02X%02X%02X", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))) }
                }), supportsOpacity: false).labelsHidden().help("Any colour")
            }
        }
    }
    private func set(_ h: String) {
        hex = h; AuroraColor.hex = h
        if PetController.shared.isShown { PetController.shared.hide(remember: false); PetController.shared.show(greeting: false) }
    }
}
