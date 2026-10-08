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
        var list: [NSRunningApplication] = []
        if let a = app, running.contains(a) { list.append(a) }
        for r in running where !list.contains(r) { list.append(r) }
        let ids = list.prefix(5).map { $0.processIdentifier }
        if ids != apps.map({ $0.processIdentifier }) { apps = Array(list.prefix(5)) }
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

// MARK: Home — the panel from the sketch

struct ZuffiHomePanel: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var now = NowUsing.shared
    @ObservedObject private var agents = AgentHub.shared
    @State private var hover: String?

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
        if let last = state.chatHistory.last(where: { $0.role == .assistant }), voice.speaking || Date().timeIntervalSince(state.lastActivity) < 90 {
            return last.content
        }
        if !VoiceEngine.micOn { return "My mic is off — tap it to talk to me" }
        let name = AssistantPrefs.displayName
        return "Hi\(name.isEmpty ? "" : " \(name)")! Say “Hey Zuffi”"
    }

    var body: some View {
        ZStack {
            ZuffiSpaceBackground()
            VStack(spacing: 6) {
                nowLine
                HStack(alignment: .center, spacing: 0) {
                    appDots
                    Spacer(minLength: 0)
                    VStack(spacing: 6) {
                        ZStack {
                            if listening {
                                ForEach(0..<3, id: \.self) { i in
                                    PulseRing(delay: Double(i) / 3)
                                }
                            }
                            ZuffiWalker(height: 128, walking: false, pose: pose)
                                .onTapGesture { VoiceEngine.shared.listenOnce() }
                        }
                        .frame(height: 132)
                        Text(words)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.92))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: 190)
                            .animation(.easeInOut(duration: 0.2), value: words)
                        micRow
                    }
                    Spacer(minLength: 0)
                    optionDots
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
            if let h = hover {
                Text(h).font(.system(size: 10.5, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
        .onAppear { NowUsing.shared.start() }
    }

    // ~~~ the line at the top: what you're using right now
    private var nowLine: some View {
        HStack(spacing: 6) {
            if let a = now.app {
                if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 15, height: 15) }
                Text(a.localizedName ?? "").font(.system(size: 11, weight: .bold, design: .rounded))
                if !now.title.isEmpty {
                    Text("·").foregroundColor(.white.opacity(0.4))
                    Text(now.title).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.7)).lineLimit(1).truncationMode(.middle)
                }
            } else {
                Text("Zuffi").font(.system(size: 11, weight: .bold, design: .rounded))
            }
            if let w = agents.working {
                Text("· \(w.tool) working").font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#7CC4FF")).lineLimit(1)
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10).frame(height: 24)
        .background(Capsule().fill(.ultraThinMaterial).opacity(0.7))
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.6))
        .contentShape(Capsule())
        .onTapGesture { now.app?.activate(options: .activateIgnoringOtherApps) }
        .help("What you're using now — click to go back to it")
    }

    // ● ● ● apps you have open — click to switch
    private var appDots: some View {
        VStack(spacing: 8) {
            ForEach(now.apps, id: \.processIdentifier) { a in
                Button { a.activate(options: .activateIgnoringOtherApps) } label: {
                    Group {
                        if let icon = a.icon { Image(nsImage: icon).resizable().frame(width: 20, height: 20) }
                        else { Image(systemName: "app.fill").font(.system(size: 12)) }
                    }
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.ultraThinMaterial))
                    .overlay(Circle().stroke(a.processIdentifier == now.app?.processIdentifier ? Color(hex: "#F7C948") : Color.white.opacity(0.2), lineWidth: a.processIdentifier == now.app?.processIdentifier ? 1.4 : 0.6))
                }
                .buttonStyle(.plain)
                .onHover { hover = $0 ? "Switch to \(a.localizedName ?? "app")" : nil }
            }
        }
        .frame(width: 34)
    }

    // ● ● ● options: Chat, Agents, Screen, Pet, More, Settings
    private var optionDots: some View {
        VStack(spacing: 8) {
            dot("bubble.left.fill", "Chat", badge: state.unreadReplies) { ZuffiNav.go(.prompt) }
            dot("sparkles", "Agents", badge: agents.approvals.count) { ZuffiNav.go(.agents) }
            dot("eye.fill", "What's on my screen?") { Task { await Assistant.run("what's on my screen", spoken: true) } }
            dot("hare.fill", "Pet on screen") { PetController.shared.toggle() }
            dot("square.grid.2x2.fill", "More") { WebHub.shared.show() }
            dot("gearshape.fill", "Settings") { ZuffiNav.go(.settings) }
        }
        .frame(width: 34)
    }

    private func dot(_ icon: String, _ label: String, badge: Int = 0, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.6))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)").font(.system(size: 8.5, weight: .heavy)).foregroundColor(.white)
                            .frame(minWidth: 14, minHeight: 14).background(Circle().fill(Color(hex: "#F4505E"))).offset(x: 3, y: -3)
                    }
                }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 ? label : nil }
        .help(label)
    }

    private var micRow: some View {
        HStack(spacing: 6) {
            Button { VoiceEngine.shared.setMic(!VoiceEngine.micOn) } label: {
                Label(VoiceEngine.micOn ? "Mic on" : "Mic off", systemImage: VoiceEngine.micOn ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(VoiceEngine.micOn ? .white : Color(hex: "#FF8A8F"))
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().stroke(VoiceEngine.micOn ? Color.white.opacity(0.2) : Color(hex: "#E5484D").opacity(0.6), lineWidth: 0.8))
            }.buttonStyle(.plain).help("Turn the microphone on or off")
            Button { VoiceEngine.shared.listenOnce() } label: {
                Image(systemName: listening ? "waveform" : "mic.circle.fill").font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "#1A1008"))
                    .frame(width: 24, height: 24)
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
        .background(Capsule().fill(.ultraThinMaterial).opacity(0.85))
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
            ZuffiSpaceBackground(intensity: 0.45)
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
                HStack(spacing: 6) {
                    pill("clock.arrow.circlepath", "History") { ZuffiNav.go(.history) }
                    pill("square.grid.2x2.fill", "More") { WebHub.shared.show() }
                    pill("slider.horizontal.3", "All settings") { NotificationCenter.default.post(name: .openFullSettings, object: nil) }
                }
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
