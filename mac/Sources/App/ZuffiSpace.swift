import SwiftUI
import AppKit
import WebKit
import ApplicationServices
import UniformTypeIdentifiers

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
        case "settings": NotificationCenter.default.post(name: .openFullSettings, object: nil)
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
    private let H: CGFloat = 156
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

    static let cats: [(String, String)] = [("study", "Study & languages"), ("tryon", "Try-On"), ("business", "Business"), ("files", "Files & PDF"), ("everyday", "Every day"), ("create", "Create"), ("devices", "This Mac & devices")]
    static let all: [NotchFeature] = [
        NotchFeature(id: "study", cat: "study", icon: "graduationcap.fill", tint: "#4F6BFF", name: "Study from any file", sub: "Notes, flashcards and a quiz from slides, PDFs or photos"),
        NotchFeature(id: "lecture", cat: "study", icon: "waveform.badge.mic", tint: "#E5577E", name: "Lecture notes", sub: "Record a class — get notes and exam questions"),
        NotchFeature(id: "explain", cat: "study", icon: "lightbulb.fill", tint: "#F7C948", name: "Explain my screen", sub: "Homework explained step by step"),
        NotchFeature(id: "deadlines", cat: "study", icon: "calendar.badge.clock", tint: "#F08A3E", name: "Deadlines & exams", sub: "Countdown, study plan and reminders"),
        NotchFeature(id: "languages", cat: "study", icon: "character.bubble.fill", tint: "#7C5CFF", name: "Learn a language", sub: "50 languages — speak with Nik, your senior teacher"),
        NotchFeature(id: "meeting", cat: "study", icon: "person.2.wave.2.fill", tint: "#8E7CFF", name: "Meeting helper", sub: "Private notes, translation and answer ideas — only you see it"),
        NotchFeature(id: "readalong", cat: "study", icon: "text.viewfinder", tint: "#5B4BD6", name: "Read with Nik", sub: "Select a line on screen — Nik reads it and shows how to say each word"),
        NotchFeature(id: "tryon-nails", cat: "tryon", icon: "hand.raised.fingers.spread.fill", tint: "#F27BA6", name: "Nail try-on", sub: "Any design on your own nails, live"),
        NotchFeature(id: "tryon-hair", cat: "tryon", icon: "comb.fill", tint: "#A86B3C", name: "Hair colour try-on", sub: "See a new hair colour on you"),
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
            if !ZuffiFocus.agents, ["business", "aiteam", "agentbrowser", "agents", "jobs", "walink", "tryon-nails", "tryon-hair"].contains(f.id) { return false }
            if !ZuffiFocus.learn, ["study", "languages", "readalong", "lecture", "deadlines"].contains(f.id) { return false }
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
        case "study", "lecture", "explain", "deadlines":
            ZuffiHub.shared.show(.study); NotificationCenter.default.post(name: .islandCollapse, object: nil)
            if id == "lecture" { StudyHub.shared.toggleLecture() }
            if id == "explain" { Task { await StudyHub.shared.explainScreen() } }
        case "languages": LearnNav.languages(); NotificationCenter.default.post(name: .islandCollapse, object: nil)
        case "meeting": MeetingHelper.shared.toggle(); NotificationCenter.default.post(name: .islandCollapse, object: nil)
        case "readalong": Task { await NikReader.shared.readMarked() }; NotificationCenter.default.post(name: .islandCollapse, object: nil)
        case "tryon-nails", "tryon-hair":
            TryOnCamera.shared.mode = id == "tryon-hair" ? "hair" : "nails"
            ZuffiHub.shared.show(.tryon); NotificationCenter.default.post(name: .islandCollapse, object: nil)
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
                    Button { UserDefaults.standard.set("Profile", forKey: "settingsTab"); ZuffiHub.shared.show(.settings); NotificationCenter.default.post(name: .islandCollapse, object: nil) } label: {
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
    @State private var shown = false
    @State private var risen = false
    @State private var waving = false
    @FocusState private var askFocus: Bool

    @ObservedObject private var tutor = TutorVoice.shared
    @ObservedObject private var asker = ZuffiAsk.shared
    @State private var askedQ = ""
    @State private var reply = ""
    @State private var thinking = false
    /// The small screen under the bar: nil = closed, "grid" = all features, or one feature's page.
    @ObservedObject private var nav = NotchNav.shared
    private var page: String? { nav.page }
    @AppStorage("notchShowsAurora") private var showsAurora = true

    private let W: CGFloat = IslandConst.homeW
    private var H: CGFloat { state.homeBig ? IslandConst.homeBigH : state.homeTall ? IslandConst.homeTallH : IslandConst.homeShortH }
    private var agents: [TeamAgent] { [ZuffiTeam.manager] + team.hiredAgents.filter { $0.id != ZuffiTeam.manager.id } }
    private let pillFill = Color.white.opacity(0.10), pillLine = Color.white.opacity(0.22)
    private var listening: Bool { voice.isListening && (voice.pushToTalk || voice.status.hasPrefix("Listening")) }
    private var answering: Bool { thinking || !reply.isEmpty }
    private var mood: String { thinking ? "thinking" : waving ? "hello" : AuroraFace.mood(voice, state) }

    /// Like Taby: three separate pieces — the small black tab with Aurora's face under the notch, the chat bar
    /// floating just below it, and (only when needed) the panel or answer card below that. Nothing else covers the screen.
    private var tabW: CGFloat { max(state.notchWidth + 24, 196) }
    private var tabH: CGFloat { showsAurora ? max(state.notchHeight, 24) + 72 : max(state.notchHeight, 24) + 6 }
    private var faceTab: some View {
        ZStack(alignment: .bottom) {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 24, bottomTrailing: 24, topTrailing: 0), style: .continuous)
                .fill(Color.black)
            if showsAurora {
                RealAuroraIcon(size: 76, mood: mood, speaking: voice.speaking || tutor.speaking)
                    .frame(width: 76, height: 70, alignment: .top).clipped()
                    .padding(.bottom, 2)
                    .offset(y: risen ? 0 : 30).opacity(risen ? 1 : 0)
                    .overlay(Color.clear.contentShape(Rectangle())
                        .onTapGesture(count: 2) { ZuffiAsk.shared.listenOnce() }
                        .help("Double-click Aurora to talk"))
            }
        }
        .frame(width: tabW, height: tabH)
        .contentShape(Rectangle()).movesIsland()
    }

    private var bar: some View {
        Group { if listening { listenStrip } else { askBar } }
            .frame(width: W - 24)
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
    }

    @ViewBuilder private var below: some View {
        if let p = page {
            VStack(spacing: 8) {
                if answering && p != "chat" { replyLine }
                NotchScreen(page: p, go: { target in withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) { nav.page = target } },
                            ask: { text in ask = text; askFocus = true })
            }
                .frame(width: W - 24)
                .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                .padding(.bottom, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
        } else if answering {
            answerCard.frame(width: W - 24).shadow(color: .black.opacity(0.45), radius: 16, y: 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var core: some View {
        VStack(spacing: 10) {
            faceTab
            bar
            below
        }
        .frame(width: W, height: H, alignment: .top)
        .opacity(shown ? 1 : 0)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: answering)
        .animation(.easeInOut(duration: 0.2), value: listening)
    }

    var body: some View {
        core
        .onAppear {
            if Date().timeIntervalSince(asker.answerAt) < 4 { askedQ = asker.answerTitle; reply = asker.answerText; thinking = false }
            shown = false; risen = false
            withAnimation(.easeOut(duration: 0.2)) { shown = true }
            // she comes up from behind the edge, then smiles
            withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.08)) { risen = true }
            waving = true      // she says hi with a little wave
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { MainActor.assumeIsolated { waving = false } }
        }
        .onDisappear { shown = false; risen = false; state.homeTall = false; state.homeBig = false; nav.page = nil }
        .onChange(of: answering) { _, a in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { state.homeTall = a }
        }
        .onChange(of: nav.page) { _, p in withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { state.homeBig = p != nil } }
        // what you said shows straight away; Zuffi's answer (spoken or written) lands in the card
        .onChange(of: voice.lastHeard) { _, h in
            guard !h.isEmpty else { return }
            askedQ = h; reply = ""; thinking = true
            let at = voice.lastHeardAt
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                MainActor.assumeIsolated {
                    guard thinking, VoiceEngine.shared.lastHeardAt == at else { return }
                    thinking = false
                    let said = VoiceEngine.shared.lastSpoken
                    reply = VoiceEngine.shared.lastSpokenAt > at && !said.isEmpty ? said : "Done."
                }
            }
        }
        .onChange(of: asker.answerAt) { _, _ in
            let title = asker.answerTitle
            if ["Translation", "Explained"].contains(title) || title.hasPrefix("Reply") || title.hasPrefix("Rewritten") { if askedQ.isEmpty { askedQ = title } }
            else { askedQ = title }
            reply = asker.answerText; thinking = false
        }
        .onChange(of: voice.lastSpoken) { _, said in
            if thinking, said.count >= 18 { reply = said; thinking = false }
        }
        .onChange(of: reply) { _, r in if !r.isEmpty { Task { await ZuffiData.shared.refresh() } } }
        .onChange(of: nav.pendingChat) { _, q in
            guard let q, !q.isEmpty else { return }
            nav.pendingChat = nil
            sendChat(q, spoken: true)
        }
        .onChange(of: voice.missedAt) { _, _ in
            askedQ = "…"; thinking = false
            reply = "I didn't hear anything. Hold Z (or tap the mic) and talk a little closer to the Mac."
        }
    }

    // the slim ask bar: menu · text · model · mic
    private var askBar: some View {
        HStack(spacing: 8) {
            Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { nav.page = nav.page == nil ? "grid" : nil } } label: {
                Image(systemName: page == nil ? "square.grid.2x2" : "xmark").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: "#E9E5F2"))
                    .frame(width: 30, height: 30).background(Circle().fill(page == nil ? Color.clear : Color(hex: "#B79CFF").opacity(0.25)))
            }.buttonStyle(.plain).help("Everything Zuffi can do")
            TextField("", text: $ask, prompt: Text(answering ? "Ask a follow-up…" : "Ask Zuffi anything…").foregroundColor(.white.opacity(0.45)))
                .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(.white)
                .focused($askFocus).onSubmit { send() }
            ProviderMenu(state: state, tint: .white)
            // mic on / off: "Hey Zuffi" listening
            Button { VoiceEngine.shared.setMic(!voice.micEnabled) } label: {
                Image(systemName: voice.micEnabled ? "mic.fill" : "mic.slash.fill").font(.system(size: 11, weight: .bold))
                    .foregroundColor(voice.micEnabled ? Color(hex: "#7CE0A3") : Color(hex: "#FF7A7A"))
                    .frame(width: 26, height: 26).background(Circle().fill(Color.white.opacity(0.08)))
            }.buttonStyle(.plain).help(voice.micEnabled ? "Mic on — Zuffi hears “Hey Zuffi”. Click to turn off." : "Mic off — click to turn on")
            // talk now
            Button { ZuffiAsk.shared.listenOnce() } label: {
                Image(systemName: "waveform").font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#141218"))
                    .frame(width: 30, height: 30).background(Circle().fill(Color(hex: "#F2F1F6")))
            }.buttonStyle(.plain).help("Talk to Zuffi now (or hold Z)")
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(height: 44)
        .background(Capsule().fill(Color(hex: "#141218")))
        .overlay(Capsule().stroke(Color.white.opacity(0.10)))
    }

    // while you hold Z or say "Hey Zuffi"
    private var listenStrip: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(Color.white).frame(width: 3, height: 5 + 11 * CGFloat(abs(sin(t * 7 + Double(i) * 0.9))))
                    }
                }.frame(height: 18)
            }
            Text(voice.pushToTalk ? "Listening… let go of Z to send" : "Listening…").font(.system(size: 13.5, weight: .semibold)).foregroundColor(.white)
            Spacer(minLength: 0)
            Button { VoiceEngine.shared.pushToTalkUp() } label: {
                RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 10, height: 10)
                    .frame(width: 30, height: 30).background(Circle().fill(Color(hex: "#E5484D")))
            }.buttonStyle(.plain).help("Stop")
        }
        .padding(.leading, 16).padding(.trailing, 6).frame(height: 44)
        .background(Capsule().fill(Color(hex: "#141218")))
    }

    // the answer hangs under the bar
    private var answerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer(minLength: 40)
                        Text(askedQ).font(.system(size: 12.5)).foregroundColor(Color(hex: "#141218"))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#F2F1F6")))
                    }
                    if thinking {
                        Text("Hmm, let me think…").font(.system(size: 13.5)).foregroundColor(.white.opacity(0.6))
                    } else {
                        Text(reply).font(.system(size: 13.5)).foregroundColor(.white).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if !thinking {
                HStack(spacing: 14) {
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(reply, forType: .string) }
                    Button("Listen again") { VoiceEngine.shared.speak(reply) }
                    Spacer()
                    Button { reply = ""; askedQ = "" } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }.help("Clear")
                }
                .buttonStyle(.plain).font(.system(size: 11.5, weight: .medium)).foregroundColor(Color(hex: "#B9B4C6"))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: "#0F0E13")))
        .onTapGesture(count: 2) { reply = ""; askedQ = "" }      // double-click the card to put it away
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08)))
        .padding(.bottom, 12)
    }

    // nothing asked yet: a friendly line and two doors
    private var restRow: some View {
        VStack(spacing: 10) {
            Text(todayLine).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
            HStack(spacing: 8) {
                pill("Dashboard") { ZuffiHub.shared.show(.home) }
                pill("Settings") { UserDefaults.standard.set("Profile", forKey: "settingsTab"); ZuffiHub.shared.show(.settings) }
            }
        }
    }

    private func pill(_ t: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Text(t).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 14).frame(height: 28).background(Capsule().fill(Color.white.opacity(0.09)))
        }.buttonStyle(.plain)
    }

    private var todayLine: String {
        let n = inbox.notes.count
        let first = (ZuffiPlan.shared.profile["name"] ?? "").components(separatedBy: " ").first ?? ""
        let h = Calendar.current.component(.hour, from: Date())
        let hello = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return n > 0 ? "\(n) message\(n == 1 ? "" : "s") waiting · \(inbox.notes.first?.head ?? "")" : "\(hello)\(first.isEmpty ? "" : ", \(first)") · select text or hold Z to ask"
    }

    // MARK: row 1
    private var topRow: some View {
        HStack(spacing: 14) {
            // Aurora in a colour ring; the badge turns the mic on or off
            ZStack(alignment: .bottomTrailing) {
                // Aurora hides behind the "wall" (the bottom edge), pops up with a smile and waves hello
                Aurora3DView(pose: waving ? .wave : .sit, lookAtMouse: true, framing: .full, expression: waving ? .happy : BunnyMood.now(voice, state))
                    .frame(width: 104, height: 112)
                    .offset(y: risen ? 4 : 96)
                    .frame(width: 92, height: 92, alignment: .bottom)
                    .clipped()
                    .allowsHitTesting(false)
                Color.clear.frame(width: 92, height: 92).contentShape(Rectangle())
                    .onTapGesture(count: 2) { ZuffiAsk.shared.listenOnce() }
                    .help("Double-click Zuffi to talk")
                Button { VoiceEngine.shared.setMic(!voice.micEnabled) } label: {
                    Image(systemName: voice.isListening ? "waveform" : voice.micEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(voice.micEnabled ? .white : Color(hex: "#FF8A80"))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Color(red: 0.1, green: 0.1, blue: 0.12)))
                        .overlay(Circle().stroke(Color.white.opacity(0.22)))
                }.buttonStyle(.plain).help(voice.micEnabled ? "Mic on — click to turn off" : "Mic off — click to turn on")
            }
            .frame(width: 92, height: 92)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble").font(.system(size: 12)).foregroundColor(.white.opacity(0.75))
                    TextField("Ask Zuffi anything…", text: $ask)
                        .textFieldStyle(.plain).font(.system(size: 13)).foregroundColor(.white)
                        .focused($askFocus)
                        .onSubmit { send() }
                    ProviderMenu(state: state)
                }
                .padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(Color.white.opacity(0.12)))
                HStack(spacing: 0) {
                    chip("square.grid.2x2.fill", "Dashboard") { ZuffiHub.shared.show(.home) }
                    chip("sparkles", "Features") { ZuffiNav.go(.features) }
                    chip("hare.fill", "Pet") { PetController.shared.toggle() }
                    Button { UserDefaults.standard.set("Profile", forKey: "settingsTab"); ZuffiHub.shared.show(.settings) } label: {
                        HStack(spacing: 4) {
                            ProfileAvatar(size: 18)
                            Text((ZuffiPlan.shared.profile["name"] ?? "Me").components(separatedBy: " ").first ?? "Me").font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.85)).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Your profile & settings")
                }
                .frame(height: 30)
            }

            if !ZuffiFocus.agents {
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        quick("arrow.triangle.2.circlepath", "Convert a file") { NotchFeaturesList.open("convert") }
                        quick("eye.fill", "What's on my screen?") { NotchFeaturesList.open("screen") }
                        quick("graduationcap.fill", "Study") { NotchFeaturesList.open("study") }
                        quick("person.wave.2.fill", "Nik, your teacher") { NotchFeaturesList.open("languages") }
                    }
                    Button {
                        let q = ask.trimmingCharacters(in: .whitespacesAndNewlines)
                        if q.isEmpty { ZuffiChat.shared.open() } else { ask = ""; ZuffiChat.shared.ask(q) }
                    } label: {
                        Text("Open chat").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: "#111111"))
                            .frame(maxWidth: .infinity).frame(height: 36).background(Capsule().fill(Color.white))
                    }.buttonStyle(.plain)
                }
                .frame(width: 136)
            } else {
            VStack(spacing: 10) {
                HStack(spacing: -6) {
                    ForEach(Array(agents.prefix(4))) { a in
                        RobotFace(agent: a, size: 24, working: team.status(a) == .working)
                            .frame(width: 30, height: 32)
                            .background(Circle().fill(Color(hex: "#1B1D26")).frame(width: 30, height: 30))
                            .overlay(Circle().stroke(Color.black, lineWidth: 2).frame(width: 30, height: 30))
                            .help(AgentEdits.name(a))
                    }
                    if agents.count > 4 {
                        Text("+\(agents.count - 4)").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#2A2140"))
                            .frame(width: 30, height: 30).background(Circle().fill(Color(hex: "#D9CCF5")))
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    }
                }
                .onTapGesture { ZuffiHub.shared.show(.office) }
                Button {
                    let q = ask.trimmingCharacters(in: .whitespacesAndNewlines)
                    if q.isEmpty { askFocus = true } else { ask = ""; MissionControl.shared.assign(q) }
                } label: {
                    Text("Give a task").font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: "#111111"))
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(Capsule().fill(Color.white))
                }.buttonStyle(.plain)
            }
            .frame(width: 136)
            }
        }
    }

    private func quick(_ icon: String, _ help: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .frame(width: 29, height: 32).background(Capsule().fill(Color.white.opacity(0.14)))
        }.buttonStyle(.plain).help(help)
    }

    private func chip(_ icon: String, _ label: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                Text(label).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
            }
            .foregroundColor(.white.opacity(0.85)).frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func send() {
        let q = ask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        ask = ""
        if ZuffiPlan.shared.isLocked { ZuffiPlan.shared.openAccount(); return }
        // On the Chat page everything goes into the chat (with the agent you picked)
        if page == "chat" { sendChat(q, spoken: false); return }
        // about the screen ("where do I click", "explain this page") → Zuffi looks at the screen
        if let hit = ZuffiAsk.shared.takeIfAboutScreen(q) {
            Task { await ZuffiAsk.shared.answer(hit.0, about: hit.1) }; return
        }
        let before = askedQ.isEmpty || reply.isEmpty ? "" : "Earlier they asked: \"\(askedQ)\" and you said: \"\(reply)\"\n"
        askedQ = q; reply = ""; thinking = true
        BunnyFaceCenter.shared.show(.thinking, for: 8)
        Task { @MainActor in
            // 1 · her own pages and your data: open / edit / delete / done / move
            if let r = await ZuffiCommand.handle(q) {
                thinking = false
                if r.isEmpty { askedQ = "" } else { reply = r }
                BunnyFaceCenter.shared.show(.happy, for: 2)
                return
            }
            // 2 · reminders, tasks, notes, habits, apps, music… (same brain as when you talk)
            let short = q.split(separator: " ").count <= 6
            if short, let r = await WebHub.shared.ask(q) { done(r); return }
            if let plan = await SmartPlanner.shared.plan(q), !plan.commands.isEmpty {
                done(await SmartPlanner.shared.run(plan)); return
            }
            if !short, let r = await WebHub.shared.ask(q) { done(r); return }
            // 3 · a question: a short, friendly answer
            let r = await AIService.shared.oneShot("""
                \(before)The user asks: "\(q)"
                Answer like a kind, clever friend: short and clear (under 110 words), in the language they wrote in. Plain text, no symbols or lists unless really needed. \
                You may begin with ONE small natural reaction when it truly fits — "Oh!", "Ah,", "Hmm," or "Haha,".
                """, system: ZuffiVoice.persona + "\n" + ZuffiVoice.style) ?? ""
            let out = r.trimmingCharacters(in: .whitespacesAndNewlines)
            thinking = false
            reply = out.isEmpty ? ZuffiAsk.noBrainLine : out
            if !out.isEmpty { ZuffiHelpLog.shared.add("Answered", out); BunnyFaceCenter.shared.show(.happy, for: 2) }
        }
    }
    private func done(_ r: String) {
        thinking = false
        reply = r.isEmpty ? "Done!" : r
        BunnyFaceCenter.shared.show(.happy, for: 2)
        ZuffiHelpLog.shared.add("Done", reply)
    }
    /// Chat page: the message goes to the chat (Zuffi or the agent you picked) and the answer appears there.
    private func sendChat(_ q: String, spoken: Bool) {
        if page != "chat" { nav.page = "chat" }
        state.chatHistory.append(ChatMessage(role: .user, content: q))
        state.stateOverride = .thinking
        BunnyFaceCenter.shared.show(.thinking, for: 8)
        Task { @MainActor in
            let before = state.chatHistory.count
            await AIService.shared.chat(query: q, context: state.promptContext, state: state)
            state.stateOverride = nil
            if state.chatHistory.count >= before, let last = state.chatHistory.last, last.role == .assistant {
                BunnyFaceCenter.shared.show(.happy, for: 2)
                if spoken || UserDefaults.standard.bool(forKey: AssistantPrefs.speakReplies) { VoiceEngine.shared.speak(last.content) }
            }
        }
    }
    /// A one-line answer above an open page ("Done — I deleted …").
    private var replyLine: some View {
        HStack(alignment: .top, spacing: 8) {
            if thinking { ProgressView().controlSize(.mini).tint(.white) }
            Text(thinking ? "Hmm, one sec…" : reply).font(.system(size: 12.5)).foregroundColor(Color(hex: "#ECEAF2")).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            Button { reply = ""; askedQ = ""; thinking = false } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundColor(NS.soft) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#1B1922")))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
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
                        RobotFace(agent: a, size: 26, working: st == .working)
                            .overlay(alignment: .bottomTrailing) { Circle().fill(st == .working ? Color(hex: "#F5B963") : ZuffiTeam.color(st)).frame(width: 7, height: 7).overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1)) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AgentEdits.name(a)).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                            Text(st == .working ? (run?.steps.last?.text ?? "Working…") : a.id == ZuffiTeam.manager.id ? "Your manager" : st == .active ? "Ready" : st.rawValue)
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
                if !working.isEmpty {
                    HStack(spacing: -5) {
                        ForEach(working.prefix(3)) { r in
                            if ZuffiFocus.agents, let a = team.agent(r.agent) { RobotFace(agent: a, size: 15, working: true) }
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

// MARK: - The open notch's living background: follows today's outfit (snow at Christmas, embers at Halloween, confetti for Eid…)

struct NotchSeasonBackground: View {
    private let season = ZuffiSeasons.find(ZuffiSeasons.activeId())
    private var sky: [Color] {
        season.sky.isEmpty ? [Color(hex: "#120F22"), Color(hex: "#0B0C14")] : season.sky.map { Color(hex: $0) }
    }
    private var glow: [Color] {
        switch season.fx {
        case "snow": return [Color(hex: "#8EC5FF"), Color(hex: "#C9E2FF")]
        case "embers": return [Color(hex: "#F28A3C"), Color(hex: "#9B5CF6")]
        case "hearts": return [Color(hex: "#F27BA1"), Color(hex: "#FFB3C7")]
        case "confetti": return [Color(hex: season.accent ?? "#B79CFF"), Color(hex: "#FFD27A")]
        case "sun": return [Color(hex: "#FFC857"), Color(hex: "#5AD1E6")]
        case "stars": return [Color(hex: "#E9C46A"), Color(hex: "#6E8BFF")]
        default: return [Color(hex: "#F58FA8"), Color(hex: "#6E8BFF")]
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                // sky
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                // two soft glows drifting slowly
                for (i, c) in glow.enumerated() {
                    let x = size.width * (0.25 + 0.5 * Double(i)) + 40 * sin(t * 0.21 + Double(i) * 2.1)
                    let y = size.height * 0.6 + 18 * cos(t * 0.17 + Double(i))
                    var g = ctx; g.addFilter(.blur(radius: 38)); g.opacity = 0.42
                    g.fill(Path(ellipseIn: CGRect(x: x - 110, y: y - 60, width: 220, height: 120)), with: .color(c))
                }
                // the season's little effect
                let n = 26
                for k in 0..<n {
                    let seed = Double(k) * 12.9898
                    let px = (sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)
                    let fx = abs(px) * size.width
                    let speed = 6 + abs(sin(seed * 3)) * 10
                    let phase = (t * speed / size.height + abs(cos(seed))).truncatingRemainder(dividingBy: 1)
                    switch season.fx {
                    case "snow":
                        let y = phase * size.height, x = fx + 6 * sin(t + seed)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 3)), with: .color(.white.opacity(0.75)))
                    case "embers":
                        let y = size.height * (1 - phase), x = fx + 5 * sin(t * 1.3 + seed)
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.6, height: 2.6)), with: .color(Color(hex: "#FFB066").opacity(0.5 + 0.4 * (1 - phase))))
                    case "confetti":
                        let y = phase * size.height, x = fx + 8 * sin(t * 0.9 + seed)
                        let cols = [Color(hex: "#FFD27A"), Color(hex: "#F58FA8"), Color(hex: "#7CDBF2"), Color(hex: season.accent ?? "#B79CFF")]
                        var p = Path(CGRect(x: -2.5, y: -1.2, width: 5, height: 2.4))
                        p = p.applying(CGAffineTransform(rotationAngle: t * 2 + seed)).applying(CGAffineTransform(translationX: x, y: y))
                        ctx.fill(p, with: .color(cols[k % cols.count].opacity(0.8)))
                    case "hearts":
                        let y = size.height * (1 - phase), x = fx
                        ctx.draw(Text("♥").font(.system(size: 8)).foregroundColor(Color(hex: "#FF8FB1").opacity(0.7)), at: CGPoint(x: x, y: y))
                    case "stars", "sun", nil:
                        // gentle twinkling stars
                        let y = abs(cos(seed * 1.7)).truncatingRemainder(dividingBy: 1) * size.height
                        let a = 0.25 + 0.55 * (0.5 + 0.5 * sin(t * 1.6 + seed))
                        ctx.fill(Path(ellipseIn: CGRect(x: fx, y: y, width: 1.8, height: 1.8)), with: .color(.white.opacity(a)))
                    default:
                        break
                    }
                }
                // keep it dark enough to read white text on
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.28)))
            }
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Aurora's drawn face for the notch: big, expressive, with paws and lip-sync (from the Zuffi 2.0 design)

struct AuroraFace: NSViewRepresentable {
    var mood: String = "idle"          // idle · hello · listening · thinking · looking · pointing · done · love · surprised · oops · sleepy
    var speaking = false
    var rise = true                     // pops up from behind the bottom edge when it appears

    final class Web: WKWebView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
    func makeNSView(context: Context) -> WKWebView {
        let w = Web(frame: .zero)
        w.setValue(false, forKey: "drawsBackground")
        w.loadHTMLString(AuroraFaceArt.html, baseURL: nil)
        return w
    }
    func updateNSView(_ w: WKWebView, context: Context) {
        w.evaluateJavaScript("window.zf && window.zf('\(mood)', \(speaking ? "true" : "false"), \(rise ? "true" : "false"))", completionHandler: nil)
    }

    /// Aurora's face from what Zuffi is doing right now.
    @MainActor static func mood(_ voice: VoiceEngine, _ state: AppState) -> String {
        if voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) { return "listening" }
        if state.stateOverride == .thinking { return "thinking" }
        switch BunnyFaceCenter.shared.flash {
        case .some(.laugh): return "laugh"
        case .some(.happy): return "done"
        case .some(.love): return "love"
        case .some(.surprised): return "surprised"
        case .some(.cross): return "angry"
        case .some(.sad): return "oops"
        case .some(.thinking), .some(.busy): return "thinking"
        case .some(.listening): return "listening"
        case .some(.sleepy): return "sleepy"
        default: return "idle"
        }
    }
}

enum AuroraFaceArt {
    static let html = #"""
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;background:transparent;overflow:hidden}
svg{width:100%;height:100%;display:block}
#all{transition:transform .55s cubic-bezier(.34,1.56,.64,1)}
body.down #all{transform:translateY(120px)}
#bob{transform-box:fill-box;transform-origin:50% 100%;animation:idle 4s ease-in-out infinite}
@keyframes idle{0%,100%{transform:translateY(0) rotate(0)}50%{transform:translateY(-2px) rotate(.6deg)}}
body.talk #bob{animation:nod .9s ease-in-out infinite}
@keyframes nod{0%,100%{transform:translateY(0) rotate(-1deg)}50%{transform:translateY(2px) rotate(1deg)}}
.eye{transform-box:fill-box;transform-origin:center;transition:transform .08s}
body.blink .eye{transform:scaleY(.08)}
#earL,#earR{transform-box:fill-box;transform-origin:50% 100%;transition:transform .4s cubic-bezier(.34,1.56,.64,1)}
body.m-listening #earL{transform:rotate(-8deg) scaleY(1.08)}body.m-listening #earR{transform:rotate(8deg) scaleY(1.08)}
body.m-oops #earL,body.m-sleepy #earL{transform:rotate(-58deg)}body.m-oops #earR,body.m-sleepy #earR{transform:rotate(58deg)}
body.m-surprised #earL{transform:rotate(-6deg) scaleY(1.12)}body.m-surprised #earR{transform:rotate(6deg) scaleY(1.12)}
#pupils{transition:transform .3s}
body.m-thinking #pupils,body.m-pointing #pupils{transform:translate(5px,-3px)}
body.m-listening #pupils{transform:translate(0,-4px)}
.wave{transform-box:fill-box;transform-origin:40% 95%;animation:wave .6s ease-in-out infinite}
@keyframes wave{0%,100%{transform:rotate(-16deg)}50%{transform:rotate(10deg)}}
.pop{transform-box:fill-box;transform-origin:center;animation:pop .5s cubic-bezier(.34,1.56,.64,1)}
@keyframes pop{0%{transform:scale(.4);opacity:0}100%{transform:scale(1);opacity:1}}
.g{display:none}
</style></head><body class="down">
<svg viewBox="0 0 260 210" xmlns="http://www.w3.org/2000/svg">
<defs>
<radialGradient id="fur" cx="0.45" cy="0.35" r="0.75"><stop offset="0" stop-color="#FBF4F2"/><stop offset="0.65" stop-color="#F2E4E2"/><stop offset="1" stop-color="#DCC5C1"/></radialGradient>
<radialGradient id="bib" cx="0.5" cy="0.4" r="0.6"><stop offset="0" stop-color="#FFFDFC"/><stop offset="1" stop-color="#F8EEEC" stop-opacity="0"/></radialGradient>
<linearGradient id="earIn" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F4B3BD"/><stop offset="1" stop-color="#FAD4DA"/></linearGradient>
<radialGradient id="eyeG" cx="0.4" cy="0.35" r="0.7"><stop offset="0" stop-color="#6B4330"/><stop offset="0.6" stop-color="#2B1A12"/><stop offset="1" stop-color="#140B07"/></radialGradient>
<filter id="fuzz" x="-10%" y="-10%" width="120%" height="120%"><feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="4" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="6" xChannelSelector="R" yChannelSelector="G"/></filter>
<g id="paw"><ellipse rx="17" ry="20" fill="url(#fur)" filter="url(#fuzz)"/><path d="M-9,-12 L-7,-4 M0,-15 L0,-6 M9,-12 L7,-4" stroke="#CDB3AE" stroke-width="2" stroke-linecap="round"/><ellipse cy="6" rx="7" ry="6" fill="#F4B3BD" opacity="0.85"/></g>
</defs>
<g id="all"><g id="bob">
<g id="earL"><g transform="rotate(-12 96 70)"><ellipse cx="96" cy="40" rx="17" ry="44" fill="url(#fur)" filter="url(#fuzz)"/><ellipse cx="96" cy="44" rx="8" ry="32" fill="url(#earIn)"/></g></g>
<g id="earR"><g transform="rotate(14 164 70)"><ellipse cx="164" cy="40" rx="17" ry="44" fill="url(#fur)" filter="url(#fuzz)"/><ellipse cx="164" cy="44" rx="8" ry="32" fill="url(#earIn)"/></g></g>
<path d="M130,62 C182,62 210,96 210,136 C210,176 176,198 130,198 C84,198 50,176 50,136 C50,96 78,62 130,62 Z" fill="url(#fur)" filter="url(#fuzz)"/>
<ellipse cx="112" cy="160" rx="30" ry="22" fill="url(#bib)"/><ellipse cx="148" cy="160" rx="30" ry="22" fill="url(#bib)"/>
<ellipse cx="86" cy="150" rx="13" ry="8" fill="#F4B3BD" opacity="0.55"/><ellipse cx="174" cy="150" rx="13" ry="8" fill="#F4B3BD" opacity="0.55"/>
<!-- eyes -->
<g id="eOpen"><g class="eye"><ellipse cx="104" cy="126" rx="12" ry="15" fill="url(#eyeG)"/></g><g class="eye"><ellipse cx="156" cy="126" rx="12" ry="15" fill="url(#eyeG)"/></g>
<g id="pupils"><circle cx="99" cy="119" r="4.5" fill="#fff"/><circle cx="108" cy="132" r="2" fill="#fff" opacity=".8"/><circle cx="151" cy="119" r="4.5" fill="#fff"/><circle cx="160" cy="132" r="2" fill="#fff" opacity=".8"/></g></g>
<g id="eBig" class="g"><ellipse cx="104" cy="124" rx="15" ry="19" fill="url(#eyeG)"/><circle cx="98" cy="115" r="5.5" fill="#fff"/><ellipse cx="156" cy="124" rx="15" ry="19" fill="url(#eyeG)"/><circle cx="150" cy="115" r="5.5" fill="#fff"/></g>
<g id="eHappy" class="g"><path d="M92,128 Q104,114 116,128 M144,128 Q156,114 168,128" stroke="#2B1A12" stroke-width="5" fill="none" stroke-linecap="round"/></g>
<g id="eClosed" class="g"><path d="M92,126 Q104,134 116,126 M144,126 Q156,134 168,126" stroke="#2B1A12" stroke-width="4" fill="none" stroke-linecap="round"/></g>
<g id="bWorry" class="g"><path d="M90,112 L116,105 M170,112 L144,105" stroke="#8C6E68" stroke-width="4" stroke-linecap="round"/></g>
<path d="M124,142 C124,138 136,138 136,142 C136,146 132,149 130,149 C128,149 124,146 124,142 Z" fill="#E98AA0"/>
<!-- mouths -->
<g id="m_smile"><path d="M130,149 L130,154 M130,154 C126,160 119,160 116,155 M130,154 C134,160 141,160 144,155" stroke="#5A3A48" stroke-width="2.6" fill="none" stroke-linecap="round"/></g>
<g id="m_grin" class="g"><path d="M114,152 Q130,174 146,152 Z" fill="#5A3A48"/><ellipse cx="130" cy="163" rx="7" ry="4" fill="#E98AA0"/></g>
<g id="m_o" class="g"><ellipse cx="130" cy="159" rx="6" ry="7" fill="#5A3A48"/></g>
<g id="m_a" class="g"><path d="M118,152 Q130,174 142,152 Z" fill="#5A3A48"/><ellipse cx="130" cy="163" rx="6" ry="3.5" fill="#E98AA0"/></g>
<g id="m_e" class="g"><path d="M115,154 Q130,160 145,154 Q130,168 115,154 Z" fill="#5A3A48"/></g>
<g id="m_m" class="g"><path d="M119,157 L141,157" stroke="#5A3A48" stroke-width="3.5" stroke-linecap="round"/></g>
<g id="m_flat" class="g"><path d="M120,158 Q125,154 130,158 Q135,162 140,158" stroke="#5A3A48" stroke-width="2.6" fill="none" stroke-linecap="round"/></g>
<g id="m_frown" class="g"><path d="M118,162 Q130,152 142,162" stroke="#5A3A48" stroke-width="2.6" fill="none" stroke-linecap="round"/></g>
<!-- paws and little extras -->
<g id="pRest"><use href="#paw" transform="translate(76,198)"/><use href="#paw" transform="translate(184,198)"/></g>
<g id="pWave" class="g"><use href="#paw" transform="translate(76,198)"/><g class="wave"><use href="#paw" transform="translate(208,146) rotate(-18)"/></g><path d="M232,104 l6,-6 M236,118 l9,-2 M228,94 l2,-8" stroke="#F7D47A" stroke-width="3" stroke-linecap="round"/></g>
<g id="pEar" class="g"><use href="#paw" transform="translate(54,114) rotate(24)"/><use href="#paw" transform="translate(184,198)"/><path d="M22,86 q-8,10 0,20 M12,80 q-12,16 0,32" stroke="#8E7CFF" stroke-width="3" fill="none" stroke-linecap="round"/></g>
<g id="pChin" class="g"><use href="#paw" transform="translate(160,182) rotate(-30)"/><use href="#paw" transform="translate(76,198)"/><circle cx="206" cy="78" r="6" fill="#B9AEDD"/><circle cx="222" cy="58" r="9" fill="#B9AEDD"/></g>
<g id="pGlass" class="g"><circle cx="156" cy="126" r="26" fill="#fff" fill-opacity="0.18" stroke="#E9C98A" stroke-width="6"/><path d="M175,145 L200,176" stroke="#8A6A45" stroke-width="9" stroke-linecap="round"/><use href="#paw" transform="translate(206,183)"/><use href="#paw" transform="translate(76,198)"/></g>
<g id="pPoint" class="g"><use href="#paw" transform="translate(216,149) rotate(-80)"/><use href="#paw" transform="translate(76,198)"/><path d="M244,140 L256,140 M244,150 L258,154 M244,130 L256,124" stroke="#8E7CFF" stroke-width="3" stroke-linecap="round"/></g>
<g id="pUp" class="g"><use href="#paw" transform="translate(48,119) rotate(20)"/><use href="#paw" transform="translate(212,119) rotate(-20)"/><path d="M30,70 l4,-10 l4,10 l10,4 l-10,4 l-4,10 l-4,-10 l-10,-4 Z M218,62 l3,-8 l3,8 l8,3 l-8,3 l-3,8 l-3,-8 l-8,-3 Z" fill="#F7D47A"/></g>
<g id="pHeart" class="g"><path d="M130,206 C96,184 100,158 116,158 C124,158 128,164 130,168 C132,164 136,158 144,158 C160,158 164,184 130,206 Z" fill="#F06B8E"/><use href="#paw" transform="translate(98,183)"/><use href="#paw" transform="translate(162,183)"/></g>
<g id="fxExcl" class="g"><path d="M222,40 l0,26 M222,76 l0,4" stroke="#F7D47A" stroke-width="7" stroke-linecap="round"/></g>
<g id="fxDrop" class="g"><path d="M186,116 q6,10 0,16 q-6,-6 0,-16 Z" fill="#9FD3F5"/></g>
<g id="fxZ" class="g"><path d="M196,70 h16 l-16,18 h16 M218,44 h10 l-10,12 h10" stroke="#B9AEDD" stroke-width="3.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/></g>
</g></g>
</svg>
<script>
var MOODS={
 idle:{eyes:'eOpen',mouth:'m_smile',paws:'pRest'},
 hello:{eyes:'eOpen',mouth:'m_grin',paws:'pWave'},
 listening:{eyes:'eOpen',mouth:'m_o',paws:'pEar'},
 thinking:{eyes:'eOpen',mouth:'m_flat',paws:'pChin'},
 looking:{eyes:'eOpen',mouth:'m_smile',paws:'pGlass'},
 pointing:{eyes:'eOpen',mouth:'m_smile',paws:'pPoint'},
 done:{eyes:'eHappy',mouth:'m_grin',paws:'pUp'},
 love:{eyes:'eHappy',mouth:'m_smile',paws:'pHeart'},
 surprised:{eyes:'eBig',mouth:'m_o',paws:'pRest',fx:'fxExcl'},
 oops:{eyes:'eOpen',mouth:'m_frown',paws:'pRest',fx:'fxDrop',brow:true},
 sleepy:{eyes:'eClosed',mouth:'m_flat',paws:'pRest',fx:'fxZ'}
};
var cur='', want='idle', speaking=false, flapT=null, hello=true;
function only(prefix,list,on){list.forEach(function(id){var e=document.getElementById(id);if(e)e.style.display=(id===on)?'inline':'none';});}
var EYES=['eOpen','eBig','eHappy','eClosed'], MOUTHS=['m_smile','m_grin','m_o','m_a','m_e','m_m','m_flat','m_frown'], PAWS=['pRest','pWave','pEar','pChin','pGlass','pPoint','pUp','pHeart'], FX=['fxExcl','fxDrop','fxZ'];
function apply(m){
  var s=MOODS[m]||MOODS.idle;
  only('e',EYES,s.eyes); only('p',PAWS,s.paws); only('f',FX,s.fx||'');
  document.getElementById('bWorry').style.display=s.brow?'inline':'none';
  if(!speaking) only('m',MOUTHS,s.mouth);
  document.body.className=document.body.className.replace(/m-\w+/g,'').trim()+' m-'+m;
  var p=document.getElementById(s.paws); if(p){p.classList.remove('pop'); void p.getBBox(); p.classList.add('pop');}
}
function flap(){
  if(!speaking) return;
  var r=Math.random(); only('m',MOUTHS,r<.32?'m_a':r<.55?'m_e':r<.75?'m_o':r<.9?'m_m':'m_smile');
  flapT=setTimeout(flap,85+Math.random()*95);
}
var risen=false;
window.zf=function(m,sp,rise){
  if(rise&&!risen){ risen=true; hello=true; setTimeout(function(){document.body.classList.remove('down');},60); }
  if(!rise&&risen){ risen=false; document.body.classList.add('down'); return; }
  if(!rise) return;
  want=m;
  if(hello){ hello=false; cur='hello'; apply('hello'); setTimeout(function(){ cur=want; if(!speaking) apply(want); else apply(want); },1900); }
  else if(cur!=='hello' && m!==cur){ cur=m; apply(m); }
  if(sp&&!speaking){ speaking=true; document.body.classList.add('talk'); flap(); }
  if(!sp&&speaking){ speaking=false; clearTimeout(flapT); document.body.classList.remove('talk'); apply(cur||'idle'); }
};
function blink(){ if(['eOpen'].indexOf((MOODS[cur]||MOODS.idle).eyes)>=0){document.body.classList.add('blink');setTimeout(function(){document.body.classList.remove('blink');},120);} setTimeout(blink,2600+Math.random()*2800); }
setTimeout(blink,1800);
</script></body></html>
"""#
}


// MARK: - "Hey Zuffi" / hold Z: Aurora drops down from the notch on her own (like a little face peeking down), talks, then hides

@MainActor
final class FaceDrop {
    static let shared = FaceDrop()
    private var panel: NSPanel?
    private var timer: Timer?
    private var hideAt = Date.distantPast
    private var showing = false
    private var openedForVoice = false
    private var voiceHold = Date.distantPast

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in MainActor.assumeIsolated { FaceDrop.shared.tick() } }
    }

    private func tick() {
        let v = VoiceEngine.shared, st = AppState.shared
        let busy = (v.isListening && (v.status.hasPrefix("Listening") || v.pushToTalk)) || v.speaking || st.stateOverride == .thinking || TutorVoice.shared.speaking
        // the open notch already shows her face; with the new notch the closed tab shows her too (no second "notch")
        if NotchDesign.on {
            if showing { hide() }
            // Like Taby: when you talk to her, the notch itself opens (her face, the listening strip, then the answer) —
            // no extra window. It stays open while she listens, thinks and talks, then folds away.
            let thinkingNow = BunnyFaceCenter.shared.flash == .thinking || BunnyFaceCenter.shared.flash == .busy
            let hearing = v.isListening && (v.status.hasPrefix("Listening") || v.pushToTalk)
            // only for a conversation with her (not a reminder being read out), and not while the chat window is open
            let talkedRecently = Date().timeIntervalSince(max(v.lastHeardAt, ZuffiAsk.shared.pendingAt, ZuffiAsk.shared.answerAt)) < 45
            let active = !ZuffiChat.shared.isOpen && (hearing || ((busy || thinkingNow) && talkedRecently))
            if active {
                voiceHold = Date().addingTimeInterval(8)
                if st.mode != .expanded { ZuffiNav.go(.overview); openedForVoice = true }
                if openedForVoice { st.isPinned = true }
            } else if openedForVoice, Date() > voiceHold {
                openedForVoice = false
                st.isPinned = false
                NotificationCenter.default.post(name: .islandCollapse, object: nil)
            }
            return
        }
        if st.mode == .expanded { if showing { hide() }; return }
        if busy { hideAt = Date().addingTimeInterval(2.2); if !showing { show() } }
        else if showing && Date() > hideAt { hide() }
    }

    private func show() {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let w: CGFloat = 250, h: CGFloat = 206
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.ignoresMouseEvents = true
            p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: FaceDropView())
            panel = p; return p
        }()
        let top = screen.frame.maxY, mid = screen.frame.midX
        p.setFrame(NSRect(x: mid - w / 2, y: top - 30, width: w, height: 30), display: false)
        p.alphaValue = 1; p.orderFrontRegardless()
        showing = true
        FaceDropModel.shared.open = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42; ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.64, 1)
            p.animator().setFrame(NSRect(x: mid - w / 2, y: top - h, width: w, height: h), display: true)
        }
    }

    private func hide() {
        guard let p = panel, let screen = p.screen ?? NSScreen.main else { return }
        showing = false
        FaceDropModel.shared.open = false
        let f = p.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.32; ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().setFrame(NSRect(x: f.minX, y: screen.frame.maxY - 30, width: f.width, height: 30), display: true)
        }, completionHandler: { MainActor.assumeIsolated { if !FaceDrop.shared.showing { FaceDrop.shared.panel?.orderOut(nil) } } })
    }
}

@MainActor
final class FaceDropModel: ObservableObject {
    static let shared = FaceDropModel()
    @Published var open = false
}

struct FaceDropView: View {
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var tutor = TutorVoice.shared
    @ObservedObject private var faces = BunnyFaceCenter.shared
    @ObservedObject private var m = FaceDropModel.shared
    var body: some View {
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 40, bottomTrailing: 40, topTrailing: 0), style: .continuous)
                .fill(Color(hex: "#050507"))
            RealAuroraHead(width: 116, mood: AuroraFace.mood(voice, state), speaking: voice.speaking || tutor.speaking)
                .padding(.top, 28)
                .offset(y: m.open ? 0 : 60)
                .animation(.spring(response: 0.45, dampingFraction: 0.62), value: m.open)
        }
        .frame(width: 250, height: 206, alignment: .top)
        .clipped()
    }
}

// MARK: - Aurora, the real picture, brought to life as a puppet
// The picture (200 × 420) is cut into layers: two ears that move on their own, the head, the body.
// Her eyes are redrawn on top so they can follow the mouse, blink and smile; her mouth opens while she talks.

/// Where this view is on the screen, so Aurora's eyes can follow the mouse from wherever she is.
@MainActor
final class AuroraProbe {
    weak var view: NSView?
    var lx: CGFloat = 0, ly: CGFloat = 0
    func look() -> CGPoint {
        let m = NSEvent.mouseLocation
        var c = CGPoint(x: NSScreen.main?.frame.midX ?? 0, y: NSScreen.main?.frame.maxY ?? 0)
        if let v = view, let w = v.window { let r = w.convertToScreen(v.convert(v.bounds, to: nil)); c = CGPoint(x: r.midX, y: r.midY) }
        let tx = max(-1, min(1, (m.x - c.x) / 380)), ty = max(-1, min(1, -(m.y - c.y) / 260))
        lx += (tx - lx) * 0.18; ly += (ty - ly) * 0.18
        return CGPoint(x: lx, y: ly)
    }
}
struct AuroraProbeView: NSViewRepresentable {
    let probe: AuroraProbe
    func makeNSView(context: Context) -> NSView { let v = NSView(); probe.view = v; return v }
    func updateNSView(_ v: NSView, context: Context) { probe.view = v }
}

/// One frame of Aurora's body language.
struct AuroraLook {
    var earL: Double = 0, earR: Double = 0      // degrees; negative = left ear leans out
    var tilt: Double = 0                         // head tilt
    var nod: CGFloat = 0                         // head up/down (picture units)
    var turn: CGFloat = 0                        // head slides toward where she looks
    var hop: CGFloat = 0                         // whole body up (picture units)
    var breathe: CGFloat = 1
    var look = CGPoint.zero                      // -1 … 1
    var lid: CGFloat = 0                         // 0 open … 1 closed
    var happyEyes = false
    var eyeScale: CGFloat = 1
    var mouth: CGFloat = 0                       // 0 closed … 1 wide
    var mouthO = false
    var blush: Double = 0.18
    var dots = false, hearts = false, zzz = false
    var armL: Double = 0, armR: Double = 0      // front legs swing from the shoulder (left: + = out, right: - = out)
    var pawL: CGFloat = 0, pawR: CGFloat = 0     // in the notch: how far each paw rises over the edge (0 … 1)

    /// The mouth shape for the letter being said right now (vowels open, m/b/p closed, o/u round).
    static func viseme(_ text: String, at sec: Double) -> (open: CGFloat, round: Bool, emph: Bool) {
        let cps = 14.5
        let chars = Array(text.lowercased())
        let x = sec * cps
        let i = Int(x)
        guard sec >= 0, i < chars.count else { return (0.06, false, false) }
        func v(_ c: Character) -> (CGFloat, Bool) {
            switch c {
            case "a", "ā", "آ", "ا": return (1, false)
            case "o", "ó": return (0.85, true)
            case "e", "i", "y", "ی", "े": return (0.55, false)
            case "u", "w", "و": return (0.5, true)
            case "m", "b", "p", "م", "ب", "پ": return (0, false)
            case "f", "v": return (0.15, false)
            case " ", ",", ".", "!", "?", "\n", "…", "—": return (0.05, false)
            default: return (0.32, false)
            }
        }
        let f = CGFloat(x - Double(i))
        let a = v(chars[i]), b = i + 1 < chars.count ? v(chars[i + 1]) : (CGFloat(0), false)
        let near = chars[max(0, i - 3)..<min(chars.count, i + 4)]
        return (a.0 * (1 - f) + b.0 * f, f < 0.5 ? a.1 : b.1, near.contains("!") || near.contains("?"))
    }

    @MainActor static func make(t: Double, mood: String, speaking: Bool, walking: Bool, look: CGPoint) -> AuroraLook {
        var p = AuroraLook()
        p.look = look
        p.breathe = 1 + 0.012 * CGFloat(sin(t * 2 * .pi / 3.4))
        // ears: a slow sway, and every few seconds one ear flicks
        let sway = 2.2 * sin(t * 0.9)
        let flickT = t.truncatingRemainder(dividingBy: 6.3)
        let flick = flickT < 0.32 ? 11 * sin(flickT / 0.32 * .pi) : 0
        let flickR = Int(t / 6.3) % 2 == 0
        p.earL = sway - (flickR ? 0 : flick)
        p.earR = -sway + (flickR ? flick : 0)
        p.tilt = 1.2 * sin(t * 0.7) + Double(look.x) * 3
        p.turn = look.x * 5
        p.nod = look.y * 3
        // blink about every 4 s (sometimes twice)
        let c = t.truncatingRemainder(dividingBy: 4.2)
        let b1: CGFloat = c < 0.15 ? CGFloat(sin(c / 0.15 * .pi)) : 0
        let b2: CGFloat = (Int(t / 4.2) % 3 == 0 && c > 0.3 && c < 0.45) ? CGFloat(sin((c - 0.3) / 0.15 * .pi)) : 0
        p.lid = max(b1, b2)

        switch mood {
        case "listening":
            p.earL = 7 + 1.5 * sin(t * 6); p.earR = -7 - 1.5 * sin(t * 6 + 1)   // ears up and pointed at you
            p.tilt = -9 + 1.5 * sin(t * 1.4); p.eyeScale = 1.08; p.blush = 0.25
        case "thinking":
            p.earL = -3; p.earR = 16 + 2 * sin(t * 1.3)                          // one ear flops over
            p.tilt = 7 + sin(t * 1.1); p.look = CGPoint(x: 0.75, y: -0.85); p.lid = max(p.lid, 0.18); p.dots = true
        case "done", "hello":
            p.happyEyes = true; p.blush = 0.42
            p.earL = 6 * sin(t * 9); p.earR = -6 * sin(t * 9 + 0.6)
            p.hop = CGFloat(abs(sin(t * 5.5))) * 9
        case "love":
            p.happyEyes = true; p.blush = 0.55; p.hearts = true
            p.earL = 4 * sin(t * 4); p.earR = -4 * sin(t * 4); p.tilt = 5 * sin(t * 1.6)
        case "surprised":
            p.earL = 9; p.earR = -9; p.eyeScale = 1.18; p.lid = 0; p.mouthO = true; p.mouth = 0.6; p.hop = 3
        case "oops":
            p.earL = -24; p.earR = 24; p.lid = max(p.lid, 0.42); p.tilt = -5; p.nod = 4; p.blush = 0.1
        case "sleepy":
            p.earL = -16; p.earR = 16; p.lid = max(0.72, p.lid); p.tilt = 6 * sin(t * 0.5); p.zzz = true
        default: break
        }
        if speaking {
            // talking: lips follow the actual words, head nods, ears bounce, paws move like she's explaining
            let v = VoiceEngine.shared
            let since = Date().timeIntervalSince(v.audioStartedAt)
            if since >= 0, since < 60, !v.lastSpoken.isEmpty, v.audioStartedAt >= v.lastSpokenAt.addingTimeInterval(-0.5) {
                let vis = AuroraLook.viseme(v.lastSpoken, at: since)
                p.mouth = vis.open; p.mouthO = vis.round
                if vis.emph { p.armL = 34 + 8 * sin(t * 4); p.armR = -34 - 8 * sin(t * 4 + 1); p.pawL = 1; p.pawR = 1; p.eyeScale = 1.06 }
            } else {
                let syl = abs(sin(t * 11.0)) * 0.6 + abs(sin(t * 6.9 + 1.3)) * 0.4
                p.mouth = CGFloat(syl * (0.4 + 0.6 * abs(sin(t * 1.7)))); p.mouthO = false
            }
            p.nod += CGFloat(1.8 * sin(t * 5.2))
            p.tilt += 2.5 * sin(t * 2.3)
            p.earL += 3 * sin(t * 5.2); p.earR -= 3 * sin(t * 5.2 + 0.4)
            if p.armL == 0 {
                // "explaining" hands: one paw lifts and moves, then the other
                let phase = Int(t / 2.6) % 3
                let g = max(0, sin(t * 3.4))
                p.armL = phase != 1 ? 10 + 22 * g : 6
                p.armR = phase != 0 ? -(10 + 22 * max(0, sin(t * 3.4 + 1.6))) : -6
                p.pawL = phase != 1 ? CGFloat(0.35 + 0.65 * g) : 0.2
                p.pawR = phase != 0 ? CGFloat(0.35 + 0.65 * max(0, sin(t * 3.4 + 1.6))) : 0.2
            }
        }
        switch mood {
        case "hello": p.armR = -70 + 16 * sin(t * 12); p.pawR = 1; p.pawL = 0.3       // waves
        case "listening": p.armL = 8; p.armR = -8; p.pawL = 0.45; p.pawR = 0.45       // paws up, attentive
        case "done", "love": p.armL = 26 + 10 * sin(t * 9); p.armR = -26 - 10 * sin(t * 9); p.pawL = 0.8; p.pawR = 0.8  // cheers
        case "oops": p.armL = -4; p.armR = 4
        default: break
        }
        if walking { p.hop = max(p.hop, CGFloat(abs(sin(t * 7))) * 12); p.earL -= 6 * sin(t * 14); p.earR += 6 * sin(t * 14) }
        return p
    }
}

struct RealAurora: View {
    /// Width of the whole picture (it is 200 × 420). The face sits between y≈100 and y≈270 of the picture.
    var width: CGFloat = 120
    var mood: String = "idle"
    var speaking = false
    var lookAtMouse = true
    var walking = false
    /// Only her head is on show (the notch): her paws peek over the bottom edge and gesture there.
    var notchPaws = false
    @State private var probe = AuroraProbe()

    static let picW: CGFloat = 200, picH: CGFloat = 420
    /// Height to show so everything from the ear tips down to the chin is visible.
    static func faceHeight(_ width: CGFloat) -> CGFloat { width / picW * 272 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let pose = AuroraLook.make(t: t, mood: mood, speaking: speaking, walking: walking, look: lookAtMouse ? probe.look() : .zero)
            puppet(pose, t: t)
        }
        .background(AuroraProbeView(probe: probe).frame(width: 1, height: 1))
        .frame(width: width, height: width * Self.picH / Self.picW, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var s: CGFloat { width / Self.picW }
    private var H: CGFloat { width * Self.picH / Self.picW }

    @ViewBuilder private func picture() -> some View {
        if let img = AuroraArt.shared.front {
            Image(nsImage: img).resizable().interpolation(.high).antialiased(true).frame(width: width, height: H)
        } else {
            Color.clear.frame(width: width, height: H)
        }
    }
    /// A soft vertical band of the picture (y in picture units).
    private func band(_ fadeInFrom: CGFloat, _ fadeInTo: CGFloat, _ fadeOutFrom: CGFloat, _ fadeOutTo: CGFloat) -> some View {
        LinearGradient(stops: [
            .init(color: .clear, location: fadeInFrom / Self.picH), .init(color: .black, location: fadeInTo / Self.picH),
            .init(color: .black, location: fadeOutFrom / Self.picH), .init(color: .clear, location: fadeOutTo / Self.picH),
        ], startPoint: .top, endPoint: .bottom).frame(width: width, height: H)
    }

    private func puppet(_ p: AuroraLook, t: Double) -> some View {
        let headAnchor = UnitPoint(x: 0.47, y: 255 / Self.picH)
        return ZStack(alignment: .topLeading) {
            // body (stays put, breathes) — the front legs are drawn on their own so they can gesture
            picture().mask(band(262, 284, 430, 431))
            if p.armL != 0 || p.armR != 0 {
                ForEach([48.0, 150.0], id: \.self) { x in
                    Ellipse().fill(Color(red: 0.80, green: 0.76, blue: 0.74)).frame(width: 46 * s, height: 72 * s).blur(radius: 5 * s)
                        .offset(x: (CGFloat(x) - 23) * s, y: (284) * s)
                }
            }
            arm(left: true, angle: p.armL)
            arm(left: false, angle: p.armR)
            // head: ears behind, then the face
            ZStack(alignment: .topLeading) {
                picture()
                    .mask(band(-1, 0, 100, 120).frame(width: width / 2).frame(width: width, alignment: .leading))
                    .rotationEffect(.degrees(p.earL), anchor: UnitPoint(x: 52 / Self.picW, y: 112 / Self.picH))
                picture()
                    .mask(band(-1, 0, 100, 120).frame(width: width / 2).frame(width: width, alignment: .trailing))
                    .rotationEffect(.degrees(p.earR), anchor: UnitPoint(x: 148 / Self.picW, y: 112 / Self.picH))
                picture().mask(band(96, 113, 270, 286))
                // cheeks
                ForEach([40.0, 146.0], id: \.self) { x in
                    Ellipse().fill(Color(red: 1, green: 0.62, blue: 0.68).opacity(p.blush)).frame(width: 24 * s, height: 13 * s).blur(radius: 3 * s)
                        .offset(x: (CGFloat(x) - 12) * s, y: (226 - 6) * s)
                }
                eye(cx: 50, p)
                eye(cx: 140, p)
                mouth(p)
            }
            .offset(x: p.turn * s, y: p.nod * s)
            .rotationEffect(.degrees(p.tilt), anchor: headAnchor)
            if notchPaws {
                ForEach([true, false], id: \.self) { left in
                    let lift = left ? p.pawL : p.pawR
                    let wave = (!left && mood == "hello") ? sin(t * 12) * 12 : 0
                    Self.paw(width: width, left: left)
                        .rotationEffect(.degrees((left ? -1 : 1) * (8 + 10 * Double(lift)) + wave), anchor: .bottom)
                        .offset(x: (left ? 34 : 122) * s, y: (262 - 26 * lift) * s)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: lift)
                }
            }
            // little extras
            if p.dots {
                HStack(spacing: 4 * s) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(Color.white.opacity(0.9)).frame(width: 9 * s, height: 9 * s)
                            .offset(y: -5 * s * CGFloat(max(0, sin(t * 5 - Double(i) * 0.7))))
                    }
                }.offset(x: 152 * s, y: 112 * s)
            }
            if p.hearts {
                ForEach(0..<2, id: \.self) { i in
                    let k = (t * 0.6 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                    Image(systemName: "heart.fill").font(.system(size: (14 + 6 * Double(i)) * s)).foregroundColor(Color(hex: "#FF7FA6"))
                        .opacity(1 - k).offset(x: (i == 0 ? 150 : 22) * s, y: (120 - 50 * k) * s)
                }
            }
            if p.zzz {
                Text("z").font(.system(size: 18 * s, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.8))
                    .offset(x: 160 * s, y: (110 - 20 * (t * 0.5).truncatingRemainder(dividingBy: 1)) * s)
            }
        }
        .scaleEffect(x: 1 + (p.breathe - 1) * 0.5, y: p.breathe, anchor: .bottom)
        .offset(y: -p.hop * s)
        .frame(width: width, height: H, alignment: .topLeading)
    }

    /// A front leg cut from the picture, swinging from the shoulder.
    private func arm(left: Bool, angle: Double) -> some View {
        let cx: CGFloat = left ? 48 : 150, cy: CGFloat = 320
        return picture()
            .mask(Ellipse().frame(width: 56 * s, height: 86 * s).blur(radius: 2.5 * s)
                .offset(x: (cx - 28) * s, y: (cy - 43) * s)
                .frame(width: width, height: H, alignment: .topLeading))
            .rotationEffect(.degrees(angle), anchor: UnitPoint(x: (left ? 52 : 146) / Self.picW, y: 286 / Self.picH))
    }

    /// One paw, cut from the picture — used where only her head shows (the notch), peeking over the edge.
    static func paw(width: CGFloat, left: Bool) -> some View {
        let s = width / picW
        let c = CGPoint(x: left ? 57 : 146, y: 343)
        return Group {
            if let img = AuroraArt.shared.front {
                Image(nsImage: img).resizable().interpolation(.high).frame(width: width, height: width * picH / picW)
                    .offset(x: -(c.x - 22) * s, y: -(c.y - 20) * s)
                    .frame(width: 44 * s, height: 40 * s, alignment: .topLeading)
                    .clipped()
                    .mask(Ellipse().blur(radius: 1.5 * s))
            }
        }
    }

    // Her eye, redrawn so it can look around, blink and smile. Sits exactly over the eye in the picture.
    private func eye(cx: CGFloat, _ p: AuroraLook) -> some View {
        let w: CGFloat = 44, h: CGFloat = 41
        let fur = LinearGradient(colors: [Color(red: 0.86, green: 0.82, blue: 0.81), Color(red: 0.76, green: 0.71, blue: 0.70)], startPoint: .top, endPoint: .bottom)
        return ZStack {
            if p.happyEyes {
                Ellipse().fill(fur).frame(width: w + 4, height: h + 4).blur(radius: 1.2 * s)
                Path { q in
                    q.move(to: CGPoint(x: 6, y: 26)); q.addQuadCurve(to: CGPoint(x: 38, y: 26), control: CGPoint(x: 22, y: 6))
                }
                .stroke(Color(red: 0.16, green: 0.09, blue: 0.08), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .frame(width: w, height: h).scaleEffect(s)
                .frame(width: w * s, height: h * s)
            } else {
                // white-ish rim, dark outline, glossy brown iris, pupil, two glints
                Ellipse().fill(Color(red: 0.93, green: 0.88, blue: 0.86)).frame(width: w * s, height: h * s)
                Ellipse().fill(Color(red: 0.17, green: 0.10, blue: 0.09)).frame(width: (w - 3) * s, height: (h - 3) * s)
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Color(red: 0.05, green: 0.03, blue: 0.03), Color(red: 0.25, green: 0.15, blue: 0.12), Color(red: 0.47, green: 0.31, blue: 0.25)],
                                             center: .center, startRadius: 0, endRadius: 17 * s))
                        .frame(width: 34 * s, height: 34 * s)
                    Circle().fill(Color.black.opacity(0.92)).frame(width: 15 * s, height: 15 * s)
                    Ellipse().fill(Color.white.opacity(0.96)).frame(width: 11 * s, height: 9 * s).offset(x: -6 * s, y: -7 * s)
                    Circle().fill(Color.white.opacity(0.8)).frame(width: 4 * s, height: 4 * s).offset(x: 7 * s, y: 6 * s)
                }
                .offset(x: p.look.x * 5 * s, y: p.look.y * 4 * s)
                .frame(width: (w - 6) * s, height: (h - 6) * s)
                .clipShape(Ellipse())
                // upper eyelid
                Ellipse().fill(fur).frame(width: (w + 2) * s, height: (h + 2) * s)
                    .mask(Rectangle().frame(height: (h + 2) * s * p.lid).frame(width: (w + 2) * s, height: (h + 2) * s, alignment: .top))
                if p.lid > 0.12 {
                    Capsule().fill(Color(red: 0.2, green: 0.12, blue: 0.11)).frame(width: (w - 8) * s, height: 2 * s)
                        .offset(y: (-(h + 2) / 2 + (h + 2) * p.lid) * s)
                }
            }
        }
        .scaleEffect(p.eyeScale)
        .frame(width: (w + 4) * s, height: (h + 4) * s)
        .offset(x: (cx - (w + 4) / 2) * s, y: (196 - (h + 4) / 2) * s)
    }

    private func mouth(_ p: AuroraLook) -> some View {
        let m = p.mouth
        let mw: CGFloat = p.mouthO ? 11 : 12 + 7 * m, mh: CGFloat = p.mouthO ? 12 : 2 + 13 * m
        return Group {
            if m > 0.05 || p.mouthO {
                ZStack(alignment: .bottom) {
                    Ellipse().fill(Color(red: 0.30, green: 0.09, blue: 0.13))
                    Ellipse().fill(Color(red: 0.93, green: 0.48, blue: 0.55)).frame(width: mw * 0.6 * s, height: mh * 0.45 * s).offset(y: -0.5 * s)
                }
                .frame(width: mw * s, height: mh * s)
                .clipShape(Ellipse())
                .offset(x: (92 - mw / 2) * s, y: 239 * s)
            }
        }
    }
}

/// Just Aurora's head (ears to chin), never cut — the real 3D Aurora, close up.
struct RealAuroraHead: View {
    var width: CGFloat = 110
    var mood: String = "idle"
    var speaking = false
    var body: some View {
        Aurora3DView(pose: mood == "hello" ? .wave : .sit, lookAtMouse: true, framing: .face,
                     expression: RealAuroraIcon.feeling(mood), speaking: speaking)
            .frame(width: width * 1.3, height: RealAurora.faceHeight(width) + 12)
            .allowsHitTesting(false)
    }
}

/// Closed: a small black tab under the notch with Aurora's face peeking out (eyes to chin; ears tuck behind the notch).
struct CompactAuroraTab: View {
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var faces = BunnyFaceCenter.shared
    @ObservedObject private var tutor = TutorVoice.shared
    let width: CGFloat
    let height: CGFloat
    let notchH: CGFloat
    var body: some View {
        // her head close-up; the ear tips tuck behind the notch, the face shows below it
        let side = max(60, (height - notchH) * 1.9)
        if UserDefaults.standard.object(forKey: "notchShowsAurora") as? Bool ?? true {
        Aurora3DView(pose: .sit, lookAtMouse: true, framing: .face,
                     expression: RealAuroraIcon.feeling(AuroraFace.mood(voice, state)), speaking: voice.speaking || tutor.speaking)
            .frame(width: side, height: side)
            .offset(y: height - side * 0.92)
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            .allowsHitTesting(false)
        }
    }
}

/// Aurora as a round-ish icon (sidebar, cards, reminders): her face, alive, for any size.
struct RealAuroraIcon: View {
    var size: CGFloat
    var mood: String = "idle"
    var speaking = false
    /// A notch mood word → the 3D Aurora's feeling.
    static func feeling(_ m: String) -> BunnyMood {
        switch m {
        case "listening": return .listening
        case "thinking": return .thinking
        case "done", "hello": return .happy
        case "laugh": return .laugh
        case "angry": return .cross
        case "love": return .love
        case "surprised": return .surprised
        case "oops": return .sad
        case "sleepy": return .sleepy
        default: return .smile
        }
    }
    static func word(_ m: BunnyMood) -> String {
        switch m {
        case .happy, .laugh: return "done"
        case .love: return "love"
        case .surprised: return "surprised"
        case .sad, .cross: return "oops"
        case .thinking, .busy: return "thinking"
        case .listening: return "listening"
        case .sleepy: return "sleepy"
        default: return "idle"
        }
    }
    var body: some View {
        Aurora3DView(pose: .sit, lookAtMouse: true, framing: .face, expression: Self.feeling(mood), speaking: speaking)
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }
}

// MARK: - The small screen under the notch (like Taby): every feature as a tile, each opening right here

/// Which apps you used and when — counted once a minute while you're at the Mac, kept only on this Mac.
@MainActor
final class AppUsage: ObservableObject {
    static let shared = AppUsage()
    struct Day: Codable { var apps: [String: Int] = [:]; var hours: [Int] = Array(repeating: 0, count: 24) }
    @Published private(set) var days: [String: Day] = TeamStore.load("app-usage", [String: Day]())
    private var timer: Timer?
    static var on: Bool { UserDefaults.standard.object(forKey: "trackDay") as? Bool ?? true }
    static func key(_ d: Date = Date()) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d) }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in MainActor.assumeIsolated { AppUsage.shared.tick() } }
    }
    private func tick() {
        guard Self.on else { return }
        // only while you're really there (a key or the mouse in the last 2 minutes)
        let idle = min(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved),
                       CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown))
        guard idle < 120, let app = NSWorkspace.shared.frontmostApplication?.localizedName else { return }
        let k = Self.key()
        var d = days[k] ?? Day()
        d.apps[app, default: 0] += 1
        d.hours[Calendar.current.component(.hour, from: Date())] += 1
        days[k] = d
        if days.count > 14 { for old in days.keys.sorted().prefix(days.count - 14) { days[old] = nil } }
        TeamStore.save("app-usage", days)
    }
    var today: Day { days[Self.key()] ?? Day() }
    /// The two-to-eight hour window you're usually most active in (over the last two weeks).
    var bestWindow: String? {
        var h = Array(repeating: 0, count: 24)
        for d in days.values { for i in 0..<24 { h[i] += d.hours[i] } }
        guard h.reduce(0, +) > 30 else { return nil }
        var best = (0, 0), bestSum = -1
        for len in [4, 6, 8] { for s in 0...(24 - len) { let sum = h[s..<(s + len)].reduce(0, +) * 10 / len; if sum > bestSum { bestSum = sum; best = (s, s + len) } } }
        return String(format: "%02d:00–%02d:00", best.0, best.1)
    }
    func clear() { days = [:]; TeamStore.save("app-usage", days) }
}

// Your tasks, notes, reminders and habits — the same list Zuffi's brain keeps (so voice and screen always agree).
@MainActor
final class ZuffiData: ObservableObject {
    static let shared = ZuffiData()
    struct Item: Identifiable, Hashable {
        let id: String; let type: String; var title: String; var text: String
        var when: Date?; var done: Bool; var target: Int; var count: Int; var every: Int; var rep: String
    }
    struct Health: Hashable { var on = false; var every = 120 }
    @Published private(set) var items: [Item] = []
    @Published private(set) var health: [String: Health] = [:]

    func of(_ types: Set<String>, done: Bool = false) -> [Item] { items.filter { types.contains($0.type) && $0.done == done } }

    func refresh() async {
        let js = """
        const S = window.Sparrow; if (!S || !S.store) return [];
        const k = new Date().toISOString().slice(0, 10);
        return S.store.items.filter(i => ['task','note','reminder','meeting','habit'].includes(i.type)).map(i => ({
          id: String(i.id), type: i.type, title: i.title || '', text: i.text || '', when: i.when ? new Date(i.when).getTime() : 0,
          done: !!i.done, target: +i.target || 0, count: (i.log || {})[k] || 0, every: +i.every || 0, rep: i.repeat ? (i.repeat.freq || '') : '' }));
        """
        if let arr = await WebHub.shared.callJS(js) as? [[String: Any]] {
            items = arr.compactMap { d in
                guard let id = d["id"] as? String, let type = d["type"] as? String else { return nil }
                let w = (d["when"] as? Double) ?? 0
                return Item(id: id, type: type, title: d["title"] as? String ?? "", text: d["text"] as? String ?? "",
                            when: w > 0 ? Date(timeIntervalSince1970: w / 1000) : nil, done: d["done"] as? Bool ?? false,
                            target: (d["target"] as? Int) ?? Int((d["target"] as? Double) ?? 0), count: (d["count"] as? Int) ?? Int((d["count"] as? Double) ?? 0),
                            every: (d["every"] as? Int) ?? Int((d["every"] as? Double) ?? 0), rep: d["rep"] as? String ?? "")
            }
        }
        if let h = await WebHub.shared.callJS("return window.Sparrow && window.Sparrow.getHealth ? window.Sparrow.getHealth() : {}") as? [String: Any] {
            var out: [String: Health] = [:]
            for k in ["water", "coffee", "meds"] {
                let v = h[k] as? [String: Any] ?? [:]
                out[k] = Health(on: v["on"] as? Bool ?? false, every: (v["every"] as? Int) ?? Int((v["every"] as? Double) ?? 120))
            }
            health = out
        }
    }
    private func run(_ js: String, _ args: [String: Any]) async {
        _ = await WebHub.shared.callJS("const S = window.Sparrow; if (!S || !S.store) return false; " + js + "; try { S.go && S.go(null) } catch (e) {} return true;", args)
        await refresh()
    }
    func add(_ type: String, title: String, text: String = "", when: Date? = nil, rep: String = "", target: Int = 0, every: Int = 0) async {
        var f: [String: Any] = ["type": type, "title": title]
        if !text.isEmpty { f["text"] = text }
        if let when { f["when"] = ISO8601DateFormatter().string(from: when) }
        if !rep.isEmpty { f["repeat"] = rep == "weekdays" ? ["freq": "weekly", "days": [1, 2, 3, 4, 5]] as [String: Any] : ["freq": rep] }
        if type == "habit" { f["target"] = max(1, target); f["log"] = [String: Int](); if every > 0 { f["every"] = every } }
        await run("S.store.add(f)", ["f": f])
    }
    func update(_ id: String, title: String? = nil, text: String? = nil, when: Date?? = nil, target: Int? = nil) async {
        var p: [String: Any] = [:]
        if let title { p["title"] = title }
        if let text { p["text"] = text }
        if let when { p["when"] = when.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(); p["notified"] = false }
        if let target { p["target"] = max(1, target) }
        await run("S.store.update(id, p)", ["id": id, "p": p])
    }
    func remove(_ id: String) async { await run("S.store.remove(id)", ["id": id]) }
    func complete(_ id: String, _ done: Bool = true) async { await run("S.store.update(id, { done: d, doneAt: d ? new Date().toISOString() : null })", ["id": id, "d": done]) }
    func bump(_ id: String, by n: Int = 1) async {
        await run("const h = S.store.items.find(i => String(i.id) === id); if (h) { const k = new Date().toISOString().slice(0, 10); const log = Object.assign({}, h.log || {}); log[k] = Math.max(0, (log[k] || 0) + n); S.store.update(h.id, { log }); }", ["id": id, "n": n])
    }
    func setHealth(_ kind: String, on: Bool, every: Int) async {
        _ = await WebHub.shared.callJS("return window.Sparrow.setHealth(h)", ["h": [kind: ["on": on, "mode": "every", "every": max(15, every)]]])
        await refresh()
    }
}

/// A simple focus timer: work without distractions, then a break. She tells you when it's done.
@MainActor
final class FocusTimer: ObservableObject {
    static let shared = FocusTimer()
    @Published var endsAt: Date?
    @Published var minutes = 25
    @Published private(set) var doneToday = UserDefaults.standard.integer(forKey: "focus-" + AppUsage.key())
    private var timer: Timer?
    var running: Bool { (endsAt ?? .distantPast) > Date() }
    func start(_ m: Int) {
        minutes = m; endsAt = Date().addingTimeInterval(Double(m) * 60)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(m) * 60, repeats: false) { _ in MainActor.assumeIsolated { FocusTimer.shared.finish() } }
        VoiceEngine.shared.speak("Okay! \(m) minutes of focus. I'll keep quiet and tell you when it's time for a break.")
    }
    func stop() { timer?.invalidate(); timer = nil; endsAt = nil }
    private func finish() {
        endsAt = nil; doneToday += 1
        UserDefaults.standard.set(doneToday, forKey: "focus-" + AppUsage.key())
        BunnyFaceCenter.shared.show(.happy, for: 3)
        let name = AssistantPrefs.displayName
        VoiceEngine.shared.speak("Yay\(name.isEmpty ? "" : ", \(name)")! Great focus. Time for a short break — stretch and drink some water.")
    }
}

// MARK: shared look

enum NS {
    static let soft = Color(hex: "#9E99AC")
    static let card = Color(hex: "#16141B")
    static let ink = Color(hex: "#141218")
}
struct NSCard<C: View>: View {
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NS.card))
    }
}
struct NSPill: View {
    let title: String
    var primary = false
    var color = "#F2F1F6"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(primary ? NS.ink : .white).lineLimit(1)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(primary ? Color(hex: color) : Color.white.opacity(0.09)))
        }.buttonStyle(.plain)
    }
}
struct NSField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}
    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(NS.soft.opacity(0.8)))
            .textFieldStyle(.plain).font(.system(size: 12.5)).foregroundColor(.white)
            .padding(.horizontal, 12).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
            .onSubmit(onSubmit)
    }
}
struct NSRow: View {
    let title: String
    let detail: String
    var tint: Color? = nil
    var body: some View {
        HStack { Text(title).font(.system(size: 12.5)).foregroundColor(.white).lineLimit(1); Spacer(); Text(detail).font(.system(size: 11.5)).foregroundColor(tint ?? NS.soft) }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(NS.card))
    }
}
struct NSLabel: View {
    let t: String
    var body: some View { Text(t).font(.system(size: 10.5, weight: .bold)).tracking(1).foregroundColor(Color(hex: "#6F6A80")).padding(.top, 4) }
}
struct NSIconButton: View {
    let icon: String
    var tint: Color = NS.soft
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundColor(tint).frame(width: 24, height: 24) }
            .buttonStyle(.plain).help(help)
    }
}
func nsWhen(_ d: Date?) -> String {
    guard let d else { return "no time" }
    let c = Calendar.current
    let t = d.formatted(date: .omitted, time: .shortened)
    if c.isDateInToday(d) { return "today \(t)" }
    if c.isDateInTomorrow(d) { return "tomorrow \(t)" }
    return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " " + t
}

// MARK: the small screen

struct NotchScreen: View {
    let page: String
    let go: (String?) -> Void
    let ask: (String) -> Void
    @ObservedObject private var data = ZuffiData.shared

    struct Item: Identifiable { let id: String; let name: String; let icon: String }
    /// The menu, in the order you asked for (two columns, like Taby).
    static let menu: [Item] = [
        Item(id: "chat", name: "Chat", icon: "bubble.left"), Item(id: "tasks", name: "Tasks", icon: "checkmark.square"),
        Item(id: "notes", name: "Notes", icon: "square.and.pencil"), Item(id: "reminders", name: "Reminders", icon: "bell"),
        Item(id: "habits", name: "Habits", icon: "flame"), Item(id: "today", name: "Today", icon: "calendar"),
        Item(id: "week", name: "This week", icon: "calendar.day.timeline.left"), Item(id: "focus", name: "Focus", icon: "timer"),
        Item(id: "home", name: "Home", icon: "house"), Item(id: "whatsapp", name: "WhatsApp", icon: "message"),
        Item(id: "settings", name: "Settings", icon: "gearshape"), Item(id: "tools", name: "Tools", icon: "wrench.and.screwdriver"),
        Item(id: "screen", name: "My screen", icon: "eye"), Item(id: "meeting", name: "Meeting helper", icon: "person.2.wave.2"),
        Item(id: "day", name: "Your day", icon: "chart.bar"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if page == "grid" {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], alignment: .leading, spacing: 2) {
                    ForEach(Self.menu) { m in
                        Button { go(m.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.icon).font(.system(size: 14, weight: .medium)).foregroundColor(.white).frame(width: 20)
                                Text(m.name).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10).frame(height: 40).contentShape(Rectangle())
                        }.buttonStyle(NSHover())
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Button { go("grid") } label: { Image(systemName: "chevron.left").font(.system(size: 12, weight: .bold)).foregroundColor(Color(hex: "#B9B4C6")).frame(width: 26, height: 26) }
                        .buttonStyle(.plain).help("Menu")
                    Text(Self.menu.first { $0.id == page }?.name ?? "").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                    Spacer()
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) { pageView }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: "#0B0A0E")))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.09)))
        .task(id: page) { await data.refresh() }
    }

    @ViewBuilder private var pageView: some View {
        switch page {
        case "chat": ChatPage(ask: ask)
        case "tasks": TasksPage()
        case "notes": NotesPage()
        case "reminders": RemindersPage()
        case "habits": HabitsPage()
        case "today": TodayPage(go: go)
        case "week": WeekPage()
        case "focus": FocusPage()
        case "home": HomePage(go: go, ask: ask)
        case "whatsapp": WhatsAppPage()
        case "settings": SettingsPage()
        case "tools": ToolsPage(ask: ask)
        case "screen": ScreenPage(ask: ask)
        case "meeting": MeetingPage()
        case "day": DayPage()
        default: EmptyView()
        }
    }
}

struct NSHover: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0.0)))
    }
}

// MARK: pages

struct ChatPage: View {
    let ask: (String) -> Void
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var chat = ZuffiChat.shared
    @ObservedObject private var archive = ChatArchive.shared
    @State private var history = NotchNav.shared.wantsHistory
    var body: some View {
        let _ = { NotchNav.shared.wantsHistory = false }()
        HStack(spacing: 6) {
            Menu {
                Button("Zuffi — everyday help") { chat.who = .zuffi }
                Divider()
                ForEach(ZuffiTeam.shared.agentGroups, id: \.0) { g in
                    Menu(g.0) { ForEach(g.1) { a in Button(a.name) { chat.who = .agent(a.id) } } }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Talking to: \(chat.whoTitle)").font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(NS.soft)
                }.padding(.horizontal, 10).frame(height: 28).background(Capsule().fill(Color.white.opacity(0.08)))
            }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("Pick Zuffi or any of the specialist agents")
            Spacer()
            NSPill(title: history ? "Back to chat" : "History") { history.toggle() }
            NSPill(title: "New", primary: true) { state.newChat(); history = false }
        }
        if history {
            if archive.chats.isEmpty { Text("Your past chats will be kept here.").font(.system(size: 12.5)).foregroundColor(NS.soft) }
            ForEach(archive.chats.prefix(30)) { c in
                Button { open(c) } label: { NSRow(title: c.title, detail: c.date.formatted(.dateTime.day().month(.abbreviated))) }.buttonStyle(.plain)
                    .contextMenu { Button("Delete", role: .destructive) { archive.delete(c) } }
            }
        } else {
            if state.chatHistory.isEmpty {
                Text("Type in the bar above or hold Z and talk. This is a new chat.").font(.system(size: 12.5)).foregroundColor(NS.soft)
            }
            ForEach(state.chatHistory.suffix(12)) { m in
                if m.role == .user {
                    HStack { Spacer(minLength: 50); Text(m.content).font(.system(size: 12.5)).foregroundColor(NS.ink).padding(.horizontal, 11).padding(.vertical, 7).background(RoundedRectangle(cornerRadius: 13).fill(Color(hex: "#F2F1F6"))).textSelection(.enabled) }
                } else {
                    Text(m.content).font(.system(size: 12.5)).foregroundColor(Color(hex: "#ECEAF2")).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if state.stateOverride == .thinking { Text("Hmm, thinking…").font(.system(size: 12)).foregroundColor(NS.soft) }
        }
    }
    /// Continue an old chat right here.
    private func open(_ c: ChatArchive.Chat) {
        state.newChat()
        state.chatHistory = c.messages.map { ChatMessage(role: $0["role"] == "user" ? .user : .assistant, content: $0["content"] ?? "") }
        archive.delete(c)
        history = false
    }
}

struct TasksPage: View {
    @ObservedObject private var data = ZuffiData.shared
    @State private var new = ""
    @State private var editing: String?
    @State private var editText = ""
    var body: some View {
        HStack(spacing: 6) {
            NSField(placeholder: "New task…", text: $new) { add() }
            NSPill(title: "Add", primary: true, color: "#7CE0A3") { add() }
        }
        let open = data.of(["task"])
        if open.isEmpty { Text("No tasks. Add one here or say “add task: call the supplier”.").font(.system(size: 12)).foregroundColor(NS.soft) }
        ForEach(open) { t in
            HStack(spacing: 8) {
                NSIconButton(icon: "circle", tint: .white, help: "Done") { Task { await data.complete(t.id) } }
                if editing == t.id {
                    NSField(placeholder: "Task", text: $editText) { Task { await data.update(t.id, title: editText); editing = nil } }
                } else {
                    Text(t.title).font(.system(size: 12.5)).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture { editing = t.id; editText = t.title }
                    if let w = t.when { Text(nsWhen(w)).font(.system(size: 10.5)).foregroundColor(NS.soft) }
                }
                NSIconButton(icon: "trash", help: "Delete") { Task { await data.remove(t.id) } }
            }
            .padding(.horizontal, 8).padding(.vertical, 6).background(RoundedRectangle(cornerRadius: 12).fill(NS.card))
        }
        let done = data.of(["task"], done: true)
        if !done.isEmpty {
            NSLabel(t: "DONE (\(done.count))")
            ForEach(done.prefix(5)) { t in
                HStack(spacing: 8) {
                    NSIconButton(icon: "checkmark.circle.fill", tint: Color(hex: "#7CE0A3"), help: "Not done") { Task { await data.complete(t.id, false) } }
                    Text(t.title).font(.system(size: 12)).foregroundColor(NS.soft).strikethrough().frame(maxWidth: .infinity, alignment: .leading)
                    NSIconButton(icon: "trash", help: "Delete") { Task { await data.remove(t.id) } }
                }.padding(.horizontal, 8)
            }
        }
        Text("Tap a task to edit it.").font(.system(size: 10.5)).foregroundColor(NS.soft)
    }
    private func add() { let t = new.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }; new = ""; Task { await data.add("task", title: t) } }
}

struct NotesPage: View {
    @ObservedObject private var data = ZuffiData.shared
    @State private var editing: String?      // "new" or an id
    @State private var title = ""
    @State private var text = ""
    @State private var search = ""
    var body: some View {
        if editing != nil {
            NSField(placeholder: "Title", text: $title)
            TextEditor(text: $text).font(.system(size: 12.5)).foregroundColor(.white).scrollContentBackground(.hidden)
                .padding(6).frame(height: 170).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            HStack(spacing: 6) {
                NSPill(title: "Save", primary: true, color: "#FFD479") { save() }
                NSPill(title: "Cancel") { editing = nil }
                Spacer()
                if let id = editing, id != "new" { NSPill(title: "Delete") { Task { await data.remove(id) }; editing = nil } }
            }
        } else {
            HStack(spacing: 6) {
                NSField(placeholder: "Search notes", text: $search)
                NSPill(title: "+ New note", primary: true, color: "#FFD479") { editing = "new"; title = ""; text = "" }
            }
            let notes = data.of(["note"]).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.text.localizedCaseInsensitiveContains(search) }
            if notes.isEmpty { Text("No notes yet. Write one, or say “save a note: …”.").font(.system(size: 12)).foregroundColor(NS.soft) }
            ForEach(notes) { n in
                Button { editing = n.id; title = n.title; text = n.text } label: {
                    NSCard {
                        Text(n.title.isEmpty ? "Note" : n.title).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                        if !n.text.isEmpty { Text(n.text).font(.system(size: 11.5)).foregroundColor(NS.soft).lineLimit(2) }
                    }
                }.buttonStyle(.plain)
            }
        }
    }
    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces), body = text
        guard !t.isEmpty || !body.isEmpty else { editing = nil; return }
        let id = editing; editing = nil
        Task { if let id, id != "new" { await data.update(id, title: t, text: body) } else { await data.add("note", title: t.isEmpty ? String(body.prefix(40)) : t, text: body) } }
    }
}

struct RemindersPage: View {
    @ObservedObject private var data = ZuffiData.shared
    @State private var editing: String?
    @State private var title = ""
    @State private var when = Date().addingTimeInterval(3600)
    @State private var rep = ""
    var body: some View {
        if editing != nil {
            NSField(placeholder: "Remind me to…", text: $title)
            DatePicker("When", selection: $when).labelsHidden().datePickerStyle(.compact).colorScheme(.dark)
            Picker("Repeat", selection: $rep) {
                Text("Once").tag(""); Text("Every day").tag("daily"); Text("Weekdays").tag("weekdays"); Text("Every week").tag("weekly"); Text("Every month").tag("monthly")
            }.pickerStyle(.segmented).labelsHidden().colorScheme(.dark)
            HStack(spacing: 6) {
                NSPill(title: "Save", primary: true, color: "#F5A524") { save() }
                NSPill(title: "Cancel") { editing = nil }
                Spacer()
                if let id = editing, id != "new" { NSPill(title: "Delete") { Task { await data.remove(id) }; editing = nil } }
            }
        } else {
            NSPill(title: "+ New reminder", primary: true, color: "#F5A524") { editing = "new"; title = ""; when = Date().addingTimeInterval(3600); rep = "" }
            let list = data.of(["reminder", "meeting"]).sorted { ($0.when ?? .distantFuture) < ($1.when ?? .distantFuture) }
            if list.isEmpty { Text("No reminders. Add one, or say “remind me to call Ali at 5”.").font(.system(size: 12)).foregroundColor(NS.soft) }
            ForEach(list) { r in
                Button { editing = r.id; title = r.title; when = r.when ?? Date().addingTimeInterval(3600); rep = r.rep } label: {
                    HStack(spacing: 8) {
                        Image(systemName: r.type == "meeting" ? "person.2" : "bell").font(.system(size: 11)).foregroundColor(Color(hex: "#F5A524"))
                        Text(r.title).font(.system(size: 12.5)).foregroundColor(.white).lineLimit(1)
                        Spacer()
                        Text(nsWhen(r.when) + (r.rep.isEmpty ? "" : " · \(r.rep)")).font(.system(size: 11)).foregroundColor(NS.soft)
                    }.padding(.horizontal, 12).padding(.vertical, 10).background(RoundedRectangle(cornerRadius: 12).fill(NS.card))
                }.buttonStyle(.plain)
            }
            NSLabel(t: "HEALTH REMINDERS")
            HealthRows()
            Text("Tap a reminder to change or delete it. When one is due, Zuffi tells you; say “snooze” for 10 more minutes.").font(.system(size: 10.5)).foregroundColor(NS.soft)
        }
    }
    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }
        let id = editing; editing = nil
        Task {
            if let id, id != "new" { await data.remove(id) }       // changed: replace it (keeps time + repeat right)
            await data.add("reminder", title: t, when: when, rep: rep)
        }
    }
}

struct HealthRows: View {
    @ObservedObject private var data = ZuffiData.shared
    var body: some View {
        ForEach([("water", "Drink water", "drop.fill"), ("coffee", "Coffee break", "cup.and.saucer.fill"), ("meds", "Medicine", "pills.fill")], id: \.0) { k in
            let h = data.health[k.0] ?? ZuffiData.Health()
            HStack(spacing: 8) {
                Image(systemName: k.2).font(.system(size: 11)).foregroundColor(Color(hex: "#38BDF8")).frame(width: 16)
                Text(k.1).font(.system(size: 12.5)).foregroundColor(.white)
                Spacer()
                Menu("every \(h.every >= 60 ? "\(h.every / 60) h" : "\(h.every) min")") {
                    ForEach([30, 60, 90, 120, 180, 240], id: \.self) { m in Button(m >= 60 ? "\(m / 60) h\(m % 60 == 30 ? " 30" : "")" : "\(m) min") { Task { await data.setHealth(k.0, on: true, every: m) } } }
                }.menuStyle(.button).buttonStyle(.plain).font(.system(size: 11)).foregroundColor(NS.soft).fixedSize()
                Toggle("", isOn: Binding(get: { h.on }, set: { v in Task { await data.setHealth(k.0, on: v, every: h.every) } })).toggleStyle(.switch).controlSize(.mini).labelsHidden()
            }.padding(.horizontal, 12).padding(.vertical, 8).background(RoundedRectangle(cornerRadius: 12).fill(NS.card))
        }
    }
}

struct HabitsPage: View {
    @ObservedObject private var data = ZuffiData.shared
    @State private var new = ""
    @State private var target = 1
    @State private var tips = ""
    @State private var loading = false
    var body: some View {
        HStack(spacing: 6) {
            NSField(placeholder: "New habit (e.g. Read 20 minutes)", text: $new) { add() }
            Stepper("\(target)×", value: $target, in: 1...20).font(.system(size: 11)).foregroundColor(.white).fixedSize()
            NSPill(title: "Add", primary: true, color: "#FF9F5A") { add() }
        }
        let habits = data.of(["habit"])
        if habits.isEmpty { Text("Add habits you want to keep. Zuffi remembers them, cheers you on and finds tips and news for them.").font(.system(size: 12)).foregroundColor(NS.soft) }
        ForEach(habits) { h in
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(h.title).font(.system(size: 12.5)).foregroundColor(.white)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(Color(hex: "#FF9F5A")).frame(width: g.size.width * min(1, CGFloat(h.count) / CGFloat(max(1, h.target))))
                        }
                    }.frame(height: 5)
                }
                Text("\(h.count)/\(max(1, h.target))").font(.system(size: 11.5).monospacedDigit()).foregroundColor(NS.soft)
                NSIconButton(icon: "plus.circle.fill", tint: Color(hex: "#FF9F5A"), help: "Done one more") { Task { await data.bump(h.id) } }
                NSIconButton(icon: "trash", help: "Delete") { Task { await data.remove(h.id) } }
            }.padding(.horizontal, 12).padding(.vertical, 9).background(RoundedRectangle(cornerRadius: 12).fill(NS.card))
        }
        if !habits.isEmpty {
            NSPill(title: loading ? "Finding…" : "Tips & news for my habits", primary: true, color: "#F2F1F6") { Task { await findTips(habits.map(\.title)) } }
        }
        if !tips.isEmpty { NSCard { Text(tips).font(.system(size: 12.5)).foregroundColor(Color(hex: "#ECEAF2")).textSelection(.enabled) } }
    }
    private func add() { let t = new.trimmingCharacters(in: .whitespaces); guard !t.isEmpty else { return }; new = ""; let n = target; target = 1; Task { await data.add("habit", title: t, target: n) } }
    private func findTips(_ titles: [String]) async {
        loading = true; defer { loading = false }
        let r = await AIService.shared.oneShot("My habits: \(titles.joined(separator: ", ")). Give me 3 short, practical tips to keep them up this week, and 1–2 recent, genuinely useful findings or news related to them (only if you're sure; say if you can't check today's news). Warm and short, in \(ZuffiAsk.shared.userLanguage).",
                                               system: "You are Zuffi, a friendly helper.\n" + ZuffiVoice.style) ?? ""
        tips = r.isEmpty ? ZuffiAsk.noBrainLine : r.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct TodayPage: View {
    let go: (String?) -> Void
    @ObservedObject private var data = ZuffiData.shared
    @ObservedObject private var day = DashToday.shared
    @ObservedObject private var inbox = NotchInbox.shared
    var body: some View {
        let today = data.items.filter { !$0.done && $0.when.map { Calendar.current.isDateInToday($0) } == true && $0.type != "note" }.sorted { $0.when! < $1.when! }
        let undated = data.of(["task"]).filter { $0.when == nil }
        if today.isEmpty && day.events.isEmpty && undated.isEmpty { Text("Nothing planned today. Enjoy it! Add a task or reminder any time.").font(.system(size: 12.5)).foregroundColor(NS.soft) }
        ForEach(today) { i in NSRow(title: i.title, detail: i.when!.formatted(date: .omitted, time: .shortened), tint: Color(hex: "#F5A524")) }
        ForEach(day.events.prefix(4)) { e in NSRow(title: e.title, detail: e.allDay ? "all day" : e.start.formatted(date: .omitted, time: .shortened), tint: Color(hex: "#B79CFF")) }
        if !undated.isEmpty { NSLabel(t: "TASKS"); ForEach(undated.prefix(4)) { t in NSRow(title: t.title, detail: "to do") } }
        let habits = data.of(["habit"])
        if !habits.isEmpty { NSLabel(t: "HABITS"); ForEach(habits.prefix(4)) { h in NSRow(title: h.title, detail: "\(h.count)/\(max(1, h.target))", tint: Color(hex: "#FF9F5A")) } }
        if !inbox.notes.isEmpty { NSPill(title: "\(inbox.notes.count) message\(inbox.notes.count == 1 ? "" : "s") waiting", primary: true, color: "#25D366") { go("whatsapp") } }
    }
}

struct WeekPage: View {
    @ObservedObject private var data = ZuffiData.shared
    var body: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let events = Planner.shared.eventItems(from: start, days: 7)
        ForEach(0..<7, id: \.self) { i in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            let items = data.items.filter { !$0.done && $0.type != "note" && $0.when.map { cal.isDate($0, inSameDayAs: d) } == true }
            let evs = events.filter { cal.isDate($0.start, inSameDayAs: d) }
            if !items.isEmpty || !evs.isEmpty || i == 0 {
                NSLabel(t: i == 0 ? "TODAY" : i == 1 ? "TOMORROW" : d.formatted(.dateTime.weekday(.wide)).uppercased())
                if items.isEmpty && evs.isEmpty { Text("Free").font(.system(size: 12)).foregroundColor(NS.soft) }
                ForEach(items) { it in NSRow(title: it.title, detail: it.when!.formatted(date: .omitted, time: .shortened), tint: Color(hex: "#F5A524")) }
                ForEach(evs) { e in NSRow(title: e.title, detail: e.allDay ? "all day" : e.start.formatted(date: .omitted, time: .shortened), tint: Color(hex: "#B79CFF")) }
            }
        }
    }
}

struct FocusPage: View {
    @ObservedObject private var focus = FocusTimer.shared
    var body: some View {
        if let end = focus.endsAt, end > Date() {
            NSCard {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let left = max(0, Int(end.timeIntervalSinceNow))
                    Text(String(format: "%02d:%02d", left / 60, left % 60)).font(.system(size: 40, weight: .bold).monospacedDigit()).foregroundColor(.white)
                }
                Text("Focus time. Zuffi keeps quiet and tells you when it's break time.").font(.system(size: 12)).foregroundColor(NS.soft)
                NSPill(title: "Stop") { focus.stop() }
            }
        } else {
            Text("Pick how long you want to focus.").font(.system(size: 12.5)).foregroundColor(Color(hex: "#CFCBD8"))
            HStack(spacing: 6) {
                ForEach([15, 25, 50], id: \.self) { m in NSPill(title: "\(m) min", primary: m == 25, color: "#38BDF8") { focus.start(m) } }
            }
        }
        NSRow(title: "Focus sessions today", detail: "\(focus.doneToday)")
    }
}

struct HomePage: View {
    let go: (String?) -> Void
    let ask: (String) -> Void
    @ObservedObject private var data = ZuffiData.shared
    @ObservedObject private var inbox = NotchInbox.shared
    var body: some View {
        let h = Calendar.current.component(.hour, from: Date())
        let first = (ZuffiPlan.shared.profile["name"] ?? "").components(separatedBy: " ").first ?? ""
        Text("\(h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening")\(first.isEmpty ? "" : ", \(first)")!").font(.system(size: 17, weight: .bold)).foregroundColor(.white)
        let next = data.of(["reminder", "meeting", "task"]).filter { ($0.when ?? .distantPast) > Date() }.min { $0.when! < $1.when! }
        if let n = next { NSRow(title: "Next: \(n.title)", detail: nsWhen(n.when), tint: Color(hex: "#F5A524")) }
        HStack(spacing: 8) {
            NSCard { Text("\(data.of(["task"]).count)").font(.system(size: 17, weight: .bold)).foregroundColor(.white); Text("tasks").font(.system(size: 10.5)).foregroundColor(NS.soft) }
            NSCard { Text("\(inbox.notes.count)").font(.system(size: 17, weight: .bold)).foregroundColor(.white); Text("messages").font(.system(size: 10.5)).foregroundColor(NS.soft) }
            NSCard { Text("\(data.of(["habit"]).filter { $0.count >= max(1, $0.target) }.count)/\(data.of(["habit"]).count)").font(.system(size: 17, weight: .bold)).foregroundColor(.white); Text("habits done").font(.system(size: 10.5)).foregroundColor(NS.soft) }
        }
        NSLabel(t: "QUICK")
        HStack(spacing: 6) {
            NSPill(title: "+ Task") { go("tasks") }
            NSPill(title: "+ Note") { go("notes") }
            NSPill(title: "+ Reminder") { go("reminders") }
            NSPill(title: "Focus 25", primary: true, color: "#38BDF8") { FocusTimer.shared.start(25); go("focus") }
        }
    }
}

struct WhatsAppPage: View {
    @ObservedObject private var inbox = NotchInbox.shared
    @State private var replying: UUID?
    @State private var text = ""
    @State private var sent = ""
    var body: some View {
        let msgs = inbox.notes.filter { $0.action == "whatsapp" || $0.head.hasPrefix("WhatsApp") }
        if msgs.isEmpty { Text("No new WhatsApp messages. Link WhatsApp in All settings to see them here.").font(.system(size: 12.5)).foregroundColor(NS.soft) }
        if !sent.isEmpty { Text(sent).font(.system(size: 11.5)).foregroundColor(Color(hex: "#7CE0A3")) }
        ForEach(msgs) { n in
            NSCard {
                Text(n.head).font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#25D366")).lineLimit(1)
                Text(n.body).font(.system(size: 12.5)).foregroundColor(.white).lineLimit(3)
                if replying == n.id {
                    NSField(placeholder: "Your reply…", text: $text) { send(n) }
                    HStack(spacing: 6) {
                        NSPill(title: "Send", primary: true, color: "#25D366") { send(n) }
                        NSPill(title: "Write it for me") { Task { await writeForMe(n) } }
                        NSPill(title: "Cancel") { replying = nil }
                    }
                } else {
                    HStack(spacing: 6) {
                        NSPill(title: "Reply", primary: true, color: "#25D366") { replying = n.id; text = "" }
                        NSPill(title: "Explain") { Task { await ZuffiAsk.shared.act("explain", n.body) } }
                        NSPill(title: "Read it") { VoiceEngine.shared.speak(n.head.replacingOccurrences(of: "WhatsApp · ", with: "WhatsApp from ") + ". " + n.body) }
                    }
                }
            }
        }
    }
    private func who(_ n: NotchInbox.Note) -> String { n.head.components(separatedBy: " · ").dropFirst().joined(separator: " · ") }
    private func send(_ n: NotchInbox.Note) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        let to = who(n); replying = nil; text = ""
        Task { @MainActor in
            let ok = await WhatsAppLink.shared.send(to: to, text: t)
            if !ok { _ = await WhatsAppAgent.shared.sendScheduled(to: to, text: t) }
            sent = "Sent to \(to) ✓"
        }
    }
    private func writeForMe(_ n: NotchInbox.Note) async {
        let r = await AIService.shared.oneShot("Write a short, natural WhatsApp reply to this message from \(who(n)): \"\(n.body)\". Same language and tone. Reply with the message text only.",
                                               system: "You write short replies for the user. Text only, no quotes.") ?? ""
        text = r.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }
}

struct SettingsPage: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var voice = VoiceEngine.shared
    @AppStorage("notchShowsAurora") private var showsAurora = true
    @AppStorage("readNotifications") private var readAloud = true
    @AppStorage("trackDay") private var trackDay = true
    @State private var name = ZuffiPlan.shared.profile["name"] ?? ""
    @State private var city = ZuffiPlan.shared.profile["city"] ?? ""
    @State private var job = ZuffiPlan.shared.profile["job"] ?? ""
    @State private var lang = UserDefaults.standard.string(forKey: "zuffiLanguage") ?? "English"
    @State private var saved = false
    var body: some View {
        NSLabel(t: "PROFILE")
        NSField(placeholder: "Your name", text: $name)
        HStack(spacing: 6) { NSField(placeholder: "City", text: $city); NSField(placeholder: "What you do", text: $job) }
        HStack(spacing: 6) {
            Picker("", selection: $lang) { ForEach(["English", "Urdu", "Hindi", "Punjabi", "Arabic", "Spanish", "French", "German", "Turkish", "Chinese"], id: \.self) { Text($0).tag($0) } }
                .labelsHidden().frame(width: 140).colorScheme(.dark)
            NSPill(title: saved ? "Saved ✓" : "Save profile", primary: true, color: "#B79CFF") { saveProfile() }
        }
        NSLabel(t: "AI MODEL")
        HStack { Text("Answers come from").font(.system(size: 12.5)).foregroundColor(.white); Spacer(); ProviderMenu(state: state, tint: .white) }
        NSPill(title: "Add or change AI keys") { UserDefaults.standard.set("AI models", forKey: "settingsTab"); ZuffiHub.shared.show(.settings) }
        NSLabel(t: "GENERAL")
        HStack(spacing: 6) {
            Text("The notch shows").font(.system(size: 12.5)).foregroundColor(.white); Spacer()
            NSPill(title: "Aurora", primary: showsAurora) { showsAurora = true }
            NSPill(title: "Just the text field", primary: !showsAurora) { showsAurora = false }
        }
        toggle("“Hey Zuffi” (mic on)", Binding(get: { voice.micEnabled }, set: { VoiceEngine.shared.setMic($0) }))
        toggle("Hold Z to talk", Binding(get: { UserDefaults.standard.object(forKey: "holdZ") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "holdZ") }))
        toggle("Her natural voice", Binding(get: { UserDefaults.standard.object(forKey: "neuralVoice") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "neuralVoice") }))
        toggle("Read notifications out loud (messages, mail…)", Binding(get: { UserDefaults.standard.bool(forKey: AssistantPrefs.readNotes) },
                                                                       set: { UserDefaults.standard.set($0, forKey: AssistantPrefs.readNotes); NotificationReader.shared.setEnabled($0) }))
        toggle("Say reminders out loud (off = just show them)", $readAloud)
        NSLabel(t: "HEALTH")
        HealthRows()
        NSLabel(t: "PRIVACY")
        toggle("Count my day (only on this Mac)", $trackDay)
        HStack(spacing: 6) {
            NSPill(title: "All settings") { UserDefaults.standard.set("Profile", forKey: "settingsTab"); ZuffiHub.shared.show(.settings) }
            NSPill(title: "Start fresh…") { ZuffiReset.confirmAndRun() }
        }
    }
    private func toggle(_ t: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) { Text(t).font(.system(size: 12.5)).foregroundColor(.white) }.toggleStyle(.switch).controlSize(.small)
    }
    private func saveProfile() {
        var p: [String: Any] = ZuffiPlan.shared.profile
        p["name"] = name; p["city"] = city; p["job"] = job
        ZuffiPlan.shared.saveProfile(p)
        UserDefaults.standard.set(lang, forKey: "zuffiLanguage")
        saved = true
    }
}

struct ToolsPage: View {
    let ask: (String) -> Void
    @ObservedObject private var state = AppState.shared
    @State private var formats: [String] = []
    @State private var status = ""
    var body: some View {
        if let f = state.droppedFile {
            NSCard {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill").foregroundColor(Color(hex: "#9FB4FF"))
                    Text(f.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    NSIconButton(icon: "xmark", help: "Remove") { state.droppedFile = nil; formats = []; status = "" }
                }
                Text("What should I do with it?").font(.system(size: 12)).foregroundColor(NS.soft)
                HStack(spacing: 6) {
                    NSPill(title: "Summarise", primary: true, color: "#9FB4FF") { Task { await summarise(f.url, f.name) } }
                    NSPill(title: "Translate") { Task { await translate(f.url) } }
                    NSPill(title: "Ask about it") { state.promptContext = .file(name: f.name, fileURL: f.url); NotchNav.shared.page = "chat"; ask("") }
                }
                if !formats.isEmpty {
                    Text("Convert to").font(.system(size: 11)).foregroundColor(NS.soft)
                    HStack(spacing: 6) { ForEach(formats, id: \.self) { fmt in NSPill(title: ChooseView.label(fmt)) { Task { await convert(f, to: fmt) } } } }
                }
            }
            if !status.isEmpty { Text(status).font(.system(size: 12)).foregroundColor(Color(hex: "#CFCBD8")).textSelection(.enabled) }
        } else {
            NSCard {
                Text("Drop a file or picture on the notch, or choose one. Then convert it (PDF, Word, JPG, PNG…), sum it up, translate it or ask about it.").font(.system(size: 12.5)).foregroundColor(Color(hex: "#CFCBD8"))
                NSPill(title: "Choose a file", primary: true, color: "#9FB4FF") { pick() }
            }
        }
        EmptyView().task(id: state.droppedFile?.url) { await loadFormats() }
    }
    private func pick() {
        let p = NSOpenPanel(); p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        state.droppedFile = DroppedFile(url: u, name: u.lastPathComponent)
    }
    private func loadFormats() async {
        guard let f = state.droppedFile else { formats = []; return }
        var r = NativeConvert.formats(for: f.url)
        if r.isEmpty { r = await WebHub.shared.callJS("return window.Sparrow && window.Sparrow.formatsFor ? window.Sparrow.formatsFor(n) : []", ["n": f.name]) as? [String] ?? [] }
        formats = Array(r.prefix(5))
    }
    private func convert(_ f: DroppedFile, to fmt: String) async {
        status = "Converting to \(ChooseView.label(fmt))…"
        var made: (Data, String)?
        if let native = NativeConvert.convert(f.url, to: fmt) {
            switch native { case .success(let m): made = (m.data, m.name); case .failure(let e): status = e.localizedDescription; return }
        } else if let data = try? Data(contentsOf: f.url) {
            let r = await WebHub.shared.callJS("return await window.Sparrow.convertB64(n, b, t)", ["n": f.name, "b": data.base64EncodedString(), "t": fmt]) as? [String: Any]
            if let n = r?["name"] as? String, let b = r?["b64"] as? String, let d = Data(base64Encoded: b) { made = (d, n) } else { status = (r?["error"] as? String) ?? "That didn't work — try another format."; return }
        }
        guard let (out, name) = made else { return }
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        var dest = dir.appendingPathComponent(name), n = 2
        while FileManager.default.fileExists(atPath: dest.path) { dest = dir.appendingPathComponent("\((name as NSString).deletingPathExtension) \(n).\((name as NSString).pathExtension)"); n += 1 }
        do { try out.write(to: dest); NSWorkspace.shared.activateFileViewerSelecting([dest]); status = "✓ \(dest.lastPathComponent) is in your Downloads." } catch { status = "I couldn't save it in Downloads." }
    }
    private func summarise(_ u: URL, _ name: String) async {
        status = "Reading it…"
        let text = await StudyText.extract(u)
        let r = await AIService.shared.oneShot("Here is a file called \(name):\n\"\"\"\n\(text.prefix(12000))\n\"\"\"\nSum it up simply in \(ZuffiAsk.shared.userLanguage): what it is, the key points, and anything the reader must do (and by when).",
                                               system: "You are Zuffi, a friendly helper.\n" + ZuffiVoice.style) ?? ""
        status = r.isEmpty ? ZuffiAsk.noBrainLine : r
    }
    private func translate(_ u: URL) async {
        status = "Translating…"
        let text = await StudyText.extract(u)
        let r = await AIService.shared.oneShot("Translate this into \(ZuffiAsk.shared.userLanguage) (if it is already in it, into English). Keep it clear:\n\(text.prefix(8000))", system: "You translate accurately.") ?? ""
        status = r.isEmpty ? ZuffiAsk.noBrainLine : r
    }
}

struct ScreenPage: View {
    let ask: (String) -> Void
    var body: some View {
        NSCard {
            Text("Zuffi looks at your screen and explains it, or shows you where to click. Tip: select text first, then hold Z and ask.").font(.system(size: 12.5)).foregroundColor(Color(hex: "#CFCBD8"))
            HStack(spacing: 6) {
                NSPill(title: "Explain my screen", primary: true, color: "#FF8FB1") { Task { await ZuffiAsk.shared.answer("Explain what's on my screen", about: ZuffiAsk.selectedText()) } }
                NSPill(title: "Where do I click…") { ask("Where do I click to ") }
                NSPill(title: "Translate selection") { if let s = ZuffiAsk.selectedText(), !s.isEmpty { Task { await ZuffiAsk.shared.act("translate", s) } } else { ask("Translate: ") } }
            }
        }
    }
}

struct MeetingPage: View {
    @ObservedObject private var meeting = MeetingHelper.shared
    var body: some View {
        NSCard {
            Text("A small private window that follows the call: what they said, the same in your language, and a short answer you could give. It isn't shown when you share your screen.").font(.system(size: 12.5)).foregroundColor(Color(hex: "#CFCBD8"))
            NSPill(title: meeting.on ? "Stop meeting helper" : "Start meeting helper", primary: true, color: "#C9B8FF") { meeting.toggle() }
        }
    }
}

struct DayPage: View {
    @ObservedObject private var usage = AppUsage.shared
    @ObservedObject private var log = ZuffiHelpLog.shared
    @AppStorage("trackDay") private var trackDay = true
    var body: some View {
        let t = usage.today
        let active = t.apps.values.reduce(0, +)
        HStack(spacing: 8) {
            NSCard { Text(NotchScreenUtil.hm(active)).font(.system(size: 17, weight: .bold)).foregroundColor(.white); Text("active today").font(.system(size: 10.5)).foregroundColor(NS.soft) }
            NSCard { Text("\(log.today.count)").font(.system(size: 17, weight: .bold)).foregroundColor(.white); Text("helps today").font(.system(size: 10.5)).foregroundColor(NS.soft) }
        }
        NSCard {
            Text(usage.bestWindow.map { "You're usually most active \($0)" } ?? "Zuffi learns when you work best over the next days.").font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
            HStack(alignment: .bottom, spacing: 3) {
                let mx = max(1, t.hours[7..<23].max() ?? 1)
                ForEach(7..<23, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#B79CFF")).frame(height: max(3, 60 * CGFloat(t.hours[i]) / CGFloat(mx))) }
            }.frame(height: 62)
            HStack { Text("07:00"); Spacer(); Text("12:00"); Spacer(); Text("17:00"); Spacer(); Text("22:00") }.font(.system(size: 9.5)).foregroundColor(NS.soft)
        }
        ForEach(Array(t.apps.sorted { $0.value > $1.value }.prefix(5).enumerated()), id: \.offset) { _, a in NSRow(title: a.key, detail: NotchScreenUtil.hm(a.value)) }
        Toggle(isOn: $trackDay) { Text("Count my day (only on this Mac)").font(.system(size: 12.5)).foregroundColor(.white) }.toggleStyle(.switch).controlSize(.small)
    }
}

enum NotchScreenUtil { static func hm(_ m: Int) -> String { m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" } }


/// Which page of the notch's small screen is open — anything (a voice command, a dropped file) can open one.
@MainActor
final class NotchNav: ObservableObject {
    static let shared = NotchNav()
    @Published var page: String?
    /// "open my chat history" → the Chat page opens on History.
    var wantsHistory = false
    /// "ask the lawyer agent …" → this question is sent in the chat once it's open.
    @Published var pendingChat: String?
    /// After a voice change, keep the page in step if it's the one showing.
    func openIfShowing(_ p: String) { if page == p { Task { await ZuffiData.shared.refresh() } } }
    /// Open the notch on this page ("tasks", "notes", "tools"…).
    func open(_ p: String) {
        page = p
        if !(AppState.shared.mode == .expanded && IslandConst.isWideHome(AppState.shared.view)) { ZuffiNav.go(.overview) }
    }
}
