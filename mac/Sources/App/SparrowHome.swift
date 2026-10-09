import SwiftUI
import AppKit

// =====================================================================
// MARK: - Zuffi home: glass cards, a glowing sparrow, and app tiles
// with little sparrows dressed in each app's colours.
// =====================================================================


// MARK: - The orb: Zuffi's own living light, behind the sparrow in the middle
/// Soft ribbons of warm light circling a dark glass core. Calm when idle, it swells and
/// flows faster when you talk to Zuffi (it follows your voice) or while Zuffi is speaking.
struct SparrowOrb: View {
    @ObservedObject private var voice = VoiceEngine.shared
    var size: CGFloat = 112

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let active = voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk)
            let energy = CGFloat(active ? 0.55 + Double(voice.level) * 1.4 : 0.25)
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let R = min(sz.width, sz.height) * 0.36
                ctx.blendMode = .plusLighter
                let palette: [Color] = [Color(hex: "#FFB347"), Color(hex: "#FF7A59"), Color(hex: "#FFD27A"), Color(hex: "#5EE7DF"), Color(hex: "#F9A830")]
                for i in 0..<26 {
                    let fi = Double(i)
                    var path = Path()
                    let steps = 90
                    for k in 0...steps {
                        let a = Double(k) / Double(steps) * .pi * 2
                        let wob = sin(a * 3 + t * (0.8 + fi * 0.05) + fi) * 0.55 + sin(a * 5 - t * 1.3 + fi * 0.7) * 0.3 + sin(a * 9 + t * 2.1 + fi * 1.9) * 0.15
                        let r = R * (1.0 + 0.05 * CGFloat(fi.truncatingRemainder(dividingBy: 5))) + CGFloat(wob) * R * 0.16 * (0.6 + energy)
                        let p = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                        k == 0 ? path.move(to: p) : path.addLine(to: p)
                    }
                    path.closeSubpath()
                    let col = palette[i % palette.count]
                    ctx.stroke(path, with: .color(col.opacity(0.10 + 0.10 * Double(energy))), lineWidth: 1.1)
                }
                ctx.blendMode = .normal
                // dark glass core where the sparrow sits
                let core = Path(ellipseIn: CGRect(x: c.x - R * 0.86, y: c.y - R * 0.86, width: R * 1.72, height: R * 1.72))
                ctx.fill(core, with: .radialGradient(Gradient(colors: [Color(hex: "#2A2F40").opacity(0.95), Color(hex: "#141824").opacity(0.98)]),
                                                     center: CGPoint(x: c.x - R * 0.2, y: c.y - R * 0.3), startRadius: 2, endRadius: R))
                ctx.stroke(core, with: .color(Color.white.opacity(0.10)), lineWidth: 0.8)
            }
            .blur(radius: 0.4)
            .background(
                Circle().fill(RadialGradient(colors: [Color(hex: "#F9A830").opacity(0.18 + 0.2 * Double(energy)), .clear],
                                             center: .center, startRadius: 10, endRadius: size * 0.6))
            )
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// One app tile: a little sparrow in the app's colours, the name, an arrow. Tap → the sparrow smiles, the app opens.
struct SparrowAppTile: View {
    let item: QuickItem
    @State private var hovered = false
    @State private var pressed = false

    var body: some View {
        let brand = Color(hex: item.color)
        Button {
            NotificationCenter.default.post(name: .littleSparrowReact, object: item.color)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { MainActor.assumeIsolated { pressed = false; QuickItems.open(item) } }
        } label: {
            HStack(spacing: 5) {
                LittleSparrow(color: item.color, size: 22)
                Text(item.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(.white.opacity(hovered ? 0.95 : 0.55))
            }
            .padding(.leading, 5).padding(.trailing, 7)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(LinearGradient(colors: [brand.opacity(hovered ? 0.5 : 0.36), brand.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(brand.opacity(hovered ? 0.7 : 0.35), lineWidth: 0.7))
            .shadow(color: brand.opacity(hovered ? 0.45 : 0), radius: 7, y: 1)
            .scaleEffect(pressed ? 0.94 : (hovered ? 1.03 : 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open \(item.name)")
    }
}

/// The right-hand side: four favourite apps.
struct SparrowAppGrid: View {
    var body: some View {
        let items = Array(QuickItems.all.prefix(4))
        VStack(alignment: .leading, spacing: 5) {
            Text("QUICK OPEN")
                .font(.system(size: 8.5, weight: .heavy, design: .rounded)).kerning(1)
                .foregroundColor(.white.opacity(0.45))
                .padding(.leading, 3)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(items) { SparrowAppTile(item: $0) }
            }
        }
        .padding(.vertical, 6)
    }
}

/// The left-hand side: hello, what Zuffi is doing, and two quick buttons.
struct SparrowContextCard: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared

    private var appName: String? {
        guard let a = state.lastExternalApp, a.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return a.localizedName
    }
    private var listening: Bool { voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(listening ? "I'm listening…" : (voice.heard.isEmpty ? "Hi! Say “Zuffi…”" : "“\(voice.heard)”"))
                .font(.system(size: 14.5, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(2)
                .animation(.easeInOut(duration: 0.2), value: listening)
            HStack(spacing: 5) {
                Circle().fill(listening ? Color(hex: "#34D399") : Color(hex: "#F9A830")).frame(width: 6, height: 6)
                    .shadow(color: listening ? Color(hex: "#34D399") : .clear, radius: 3)
                Text(listening ? "Go ahead — I'm all ears" : "or hold ⌥ and talk")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Button { VoiceEngine.shared.listenOnce() } label: {
                    Label("Talk", systemImage: listening ? "waveform" : "mic.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#1A1008"))
                        .padding(.horizontal, 11).frame(height: 25)
                        .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)))
                }
                .buttonStyle(.plain)
                Button {
                    if let a = state.lastExternalApp { a.bringForward() } else { state.view = .prompt }
                } label: {
                    Text(appName.map { "Back to \($0)" } ?? "Type instead")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                        .padding(.horizontal, 10).frame(height: 25)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Home: hello on the left, the sparrow inside its orb in the middle, favourite apps on the right.
struct SparrowHomeView: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 8) {
            SparrowContextCard(state: state).frame(width: 226)
            ZuffiMini(state: state, height: 96).frame(width: 150)
            SparrowAppGrid()
        }
    }
}

/// Frosted glass card with a soft border.
struct GlassCard<Content: View>: View {
    var glow = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.11), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
            content()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        )
    }
}

// MARK: - Move the island by dragging it

@MainActor
enum IslandDrag {
    private static var startMouse: NSPoint?
    private static var startOrigin: NSPoint?

    static var panel: NSWindow? { NSApp.windows.first { $0 is IslandPanel } }

    static func changed() {
        guard let p = panel else { return }
        let m = NSEvent.mouseLocation
        if startMouse == nil { startMouse = m; startOrigin = p.frame.origin }
        guard let sm = startMouse, let so = startOrigin else { return }
        var o = NSPoint(x: so.x + m.x - sm.x, y: so.y + m.y - sm.y)
        if let s = p.screen ?? NSScreen.main {
            let f = s.frame
            o.x = min(max(o.x, f.minX - 40), f.maxX - p.frame.width + 40)
            o.y = min(max(o.y, f.minY), f.maxY - p.frame.height)
        }
        p.setFrameOrigin(o)
    }

    static func ended() {
        startMouse = nil; startOrigin = nil
        guard let p = panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "islandOrigin")
    }

    /// Where the person last left the island (nil = default place).
    static var savedOrigin: NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: "islandOrigin"), !s.isEmpty else { return nil }
        return NSPointFromString(s)
    }
}

extension View {
    /// Drag this area to move the whole island anywhere on screen.
    func movesIsland() -> some View {
        gesture(DragGesture(minimumDistance: 3)
            .onChanged { _ in MainActor.assumeIsolated { IslandDrag.changed() } }
            .onEnded { _ in MainActor.assumeIsolated { IslandDrag.ended() } })
    }
}

// MARK: - Opening hello: the sparrow flies in (Zuffi says hello out loud — no text)

struct SparrowGreetingView: View {
    @ObservedObject var state: AppState
    @State private var landed = false
    @State private var hello = false
    @State private var done = false

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 5 ? "Up late? I'm here." : h < 12 ? "Good morning!" : h < 17 ? "Good afternoon!" : "Good evening!"
    }

    var body: some View {
        ZStack {
            // The same moving space sky as Zuffi's home: drifting orbs, twinkling stars.
            ZuffiSpaceBackground(intensity: 1)
            HStack(spacing: 16) {
                ZuffiMini(state: state, height: 92)
                    .frame(width: 96, height: 96)
                    .offset(x: landed ? 0 : 320, y: landed ? 0 : -40)
                    .rotationEffect(.degrees(landed ? 0 : -14))
                    .scaleEffect(landed ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hi, I'm Zuffi").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(.white)
                    Text(greeting + " Click me or say “Zuffy” any time.").font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75))
                }
                .opacity(hello ? 1 : 0).offset(x: hello ? 0 : 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            SoundEngine.shared.play("chime")
            withAnimation(.spring(response: 0.9, dampingFraction: 0.62)) { landed = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.55)) { hello = true }
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_200_000_000)
                guard !done else { return }
                done = true
                NotificationCenter.default.post(name: .greetComplete, object: nil)
            }
        }
    }
}


// MARK: - Hide Zuffi into a little bubble (✕), click the bubble to bring it back

@MainActor
final class SparrowBubble {
    static let shared = SparrowBubble()
    private var panel: NSPanel?
    private var dragStart: NSPoint?
    private var originStart: NSPoint?
    private var moved = false

    var isHidden: Bool { panel?.isVisible == true }

    func hideIsland() {
        guard let island = IslandDrag.panel else { return }
        let p = panel ?? makePanel()
        // the bubble sits where the island was
        let f = island.frame
        let saved = UserDefaults.standard.string(forKey: "bubbleOrigin").map { NSPointFromString($0) }
        p.setFrameOrigin(saved ?? NSPoint(x: f.maxX - 110, y: f.maxY - 70))
        island.orderOut(nil)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 }
        SoundEngine.shared.play("close")
    }

    func restore() {
        panel?.orderOut(nil)
        IslandDrag.panel?.orderFrontRegardless()
        SoundEngine.shared.play("pop")
        NotificationCenter.default.post(name: .hookReveal, object: nil)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        let view = BubbleView(
            onDrag: { MainActor.assumeIsolated { SparrowBubble.shared.drag() } },
            onEnd: { MainActor.assumeIsolated { SparrowBubble.shared.dragEnded() } })
        p.contentView = NSHostingView(rootView: view)
        panel = p
        return p
    }

    fileprivate func drag() {
        guard let p = panel else { return }
        let m = NSEvent.mouseLocation
        if dragStart == nil { dragStart = m; originStart = p.frame.origin; moved = false }
        guard let s = dragStart, let o = originStart else { return }
        if abs(m.x - s.x) + abs(m.y - s.y) > 4 { moved = true }
        if moved { p.setFrameOrigin(NSPoint(x: o.x + m.x - s.x, y: o.y + m.y - s.y)) }
    }

    fileprivate func dragEnded() {
        defer { dragStart = nil; originStart = nil }
        if moved, let p = panel { UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "bubbleOrigin") }
        else { restore() }
    }
}

private struct BubbleView: View {
    let onDrag: () -> Void
    let onEnd: () -> Void
    @State private var hovered = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: "#2B3244").opacity(0.92), Color(hex: "#1B2131").opacity(0.92)], startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().stroke(LinearGradient(colors: [Color(hex: "#FFD27A"), Color(hex: "#F28A3C").opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
                    .shadow(color: Color(hex: "#F9A830").opacity(hovered ? 0.7 : 0.35), radius: hovered ? 10 : 6)
                LittleSparrow(color: nil, size: 30)
                    .offset(y: CGFloat(sin(t * 2)) * 1.5)
            }
            .frame(width: 52, height: 52)
            .scaleEffect(hovered ? 1.08 : 1)
        }
        .frame(width: 64, height: 64)
        .contentShape(Circle())
        .onHover { hovered = $0 }
        .help("Click to bring Zuffi back · drag to move")
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in onDrag() }.onEnded { _ in onEnd() })
    }
}
