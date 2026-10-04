import SwiftUI
import AppKit

// =====================================================================
// MARK: - Sparrow home: glass cards, a glowing sparrow, and app tiles
// with little sparrows dressed in each app's colours.
// =====================================================================

/// Sparrow's look: round and fluffy — coloured cap and wings, cream face, shiny eyes,
/// pink cheeks and a little orange beak. Used big (the mascot) and small (app tiles, tinted).
struct SparrowFigure: View {
    var color: Color = Color(hex: "#8A6650")
    var size: CGFloat = 26
    var blink: CGFloat = 1          // 1 = open, ~0.1 = closed
    var wing: Double = 0            // flap angle in degrees
    var sparkle = false

    var body: some View {
        let s = size
        let dark = color.opacity(0.95)
        ZStack {
            // wings (behind)
            Ellipse().fill(LinearGradient(colors: [color.opacity(0.85), dark], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.34, height: s * 0.52)
                .rotationEffect(.degrees(28 + wing), anchor: .top)
                .offset(x: -s * 0.44, y: s * 0.12)
            Ellipse().fill(LinearGradient(colors: [color.opacity(0.85), dark], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.34, height: s * 0.52)
                .rotationEffect(.degrees(-28 - wing), anchor: .top)
                .offset(x: s * 0.44, y: s * 0.12)
            // head tuft
            Ellipse().fill(color).frame(width: s * 0.13, height: s * 0.24)
                .rotationEffect(.degrees(-18)).offset(x: -s * 0.03, y: -s * 0.5)
            Ellipse().fill(color).frame(width: s * 0.1, height: s * 0.18)
                .rotationEffect(.degrees(22)).offset(x: s * 0.07, y: -s * 0.47)
            // body: coloured cap over a cream face
            ZStack {
                Circle().fill(LinearGradient(colors: [color.opacity(0.8), color], startPoint: .top, endPoint: .bottom))
                Ellipse().fill(LinearGradient(colors: [Color(hex: "#FFFDF9"), Color(hex: "#F3E8DC")], startPoint: .top, endPoint: .bottom))
                    .frame(width: s * 0.9, height: s * 0.8)
                    .offset(y: s * 0.16)
                // soft shine
                Ellipse().fill(Color.white.opacity(0.22)).frame(width: s * 0.42, height: s * 0.16).offset(x: -s * 0.12, y: -s * 0.34)
            }
            .frame(width: s, height: s)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.18), radius: s * 0.04, y: s * 0.03)
            // eyes with highlights
            HStack(spacing: s * 0.22) {
                eye(s); eye(s)
            }
            .offset(y: s * 0.06)
            // cheeks
            HStack(spacing: s * 0.42) {
                Ellipse().fill(Color(hex: "#F7A1AE").opacity(0.75)).frame(width: s * 0.14, height: s * 0.09)
                Ellipse().fill(Color(hex: "#F7A1AE").opacity(0.75)).frame(width: s * 0.14, height: s * 0.09)
            }
            .offset(y: s * 0.19)
            // beak
            BeakShape()
                .fill(LinearGradient(colors: [Color(hex: "#FFB547"), Color(hex: "#F28A1C")], startPoint: .top, endPoint: .bottom))
                .frame(width: s * 0.15, height: s * 0.1)
                .offset(y: s * 0.17)
            if sparkle {
                Image(systemName: "sparkle")
                    .font(.system(size: s * 0.2, weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [Color(hex: "#FFE29A"), Color(hex: "#F9A830")], startPoint: .top, endPoint: .bottom))
                    .offset(x: s * 0.52, y: -s * 0.3)
                    .shadow(color: Color(hex: "#F9A830"), radius: 3)
            }
        }
        .frame(width: s * 1.35, height: s * 1.3)
    }

    private func eye(_ s: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(hex: "#17110D"))
            Circle().fill(Color.white).frame(width: s * 0.045, height: s * 0.045).offset(x: s * 0.025, y: -s * 0.03)
        }
        .frame(width: s * 0.13, height: s * 0.13)
        .scaleEffect(x: 1, y: blink)
    }
}

private struct BeakShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.minY - r.height * 0.25))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// A small sparrow in any colour (app tiles).
struct MiniSparrow: View {
    let color: Color
    var size: CGFloat = 26
    var body: some View { SparrowFigure(color: color, size: size) }
}

/// The big, living sparrow: breathes, blinks, flaps when listening or talking,
/// and flies in from the side the first time it appears.
struct SparrowMascot: View {
    @ObservedObject var state: AppState
    var size: CGFloat
    @ObservedObject private var voice = VoiceEngine.shared
    @State private var arrived = SparrowMascot.hasFlownIn
    nonisolated(unsafe) static var hasFlownIn = false

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let busy = voice.isListening || state.effectiveState == .working || state.effectiveState == .thinking
            let flying = !arrived
            let flapSpeed = flying ? 22.0 : busy ? 9.0 : 1.6
            let flapAmp = flying ? 34.0 : busy ? 16.0 : 4.0
            let wing = sin(t * flapSpeed) * flapAmp
            let bob = sin(t * 2.1) * size * (busy ? 0.035 : 0.022)
            let phase = t.truncatingRemainder(dividingBy: 4.3)
            let blink: CGFloat = phase < 0.13 ? 0.12 : 1
            SparrowFigure(size: size, blink: blink, wing: wing, sparkle: true)
                .scaleEffect(1 + (busy ? CGFloat(sin(t * 4)) * 0.025 : 0))
                .offset(y: bob)
        }
        .offset(x: arrived ? 0 : 260, y: arrived ? 0 : -70)
        .rotationEffect(.degrees(arrived ? 0 : -14))
        .scaleEffect(arrived ? 1 : 0.55)
        .opacity(arrived ? 1 : 0)
        .onAppear {
            guard !arrived else { return }
            SparrowMascot.hasFlownIn = true
            withAnimation(.spring(response: 1.1, dampingFraction: 0.62).delay(0.15)) { arrived = true }
        }
    }
}

/// One app tile: brand-coloured glass, a sparrow in the app's colours, the name and an arrow.
struct SparrowAppTile: View {
    let item: QuickItem
    @State private var hovered = false

    var body: some View {
        let brand = Color(hex: item.color)
        Button { QuickItems.open(item) } label: {
            HStack(spacing: 7) {
                MiniSparrow(color: brand, size: 19)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                Text(item.name)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(hovered ? 1 : 0.75))
                    .offset(x: hovered ? 2 : 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [brand.opacity(hovered ? 0.62 : 0.5), brand.opacity(0.22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.35), brand.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .shadow(color: brand.opacity(hovered ? 0.55 : 0.25), radius: hovered ? 9 : 5, y: 2)
            .scaleEffect(hovered ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open \(item.name)")
    }
}

/// The right-hand card: four favourite apps.
struct SparrowAppGrid: View {
    var body: some View {
        let items = Array(QuickItems.all.prefix(4))
        GlassCard {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(items) { SparrowAppTile(item: $0) }
            }
            .padding(7)
        }
    }
}

/// The left-hand card: the app you're using, whether Sparrow is listening, and a quick action.
/// The sparrow itself (with its golden glow) is drawn on top by the island at the left of this card.
struct SparrowContextCard: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared

    private var appName: String? {
        guard let a = state.lastExternalApp, a.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return a.localizedName
    }

    var body: some View {
        GlassCard(glow: true) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 100)          // room for the sparrow
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#34D399")).frame(width: 7, height: 7)
                            .shadow(color: Color(hex: "#34D399"), radius: 3)
                        Text(appName ?? "Sparrow")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(appName == nil ? "Assistant" : "In use")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    }
                    HStack(spacing: 5) {
                        Circle().fill(voice.isListening ? Color(hex: "#34D399") : Color(hex: "#A39486")).frame(width: 6, height: 6)
                        Text(voice.isListening ? "Listening · just talk to me" : (voice.status.isEmpty ? "Ready · tap the mic or say “Sparrow”" : voice.status))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                    HStack(spacing: 7) {
                        Button {
                            if let a = state.lastExternalApp { a.activate(options: .activateIgnoringOtherApps) }
                            else { state.view = .prompt }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: appName == nil ? "sparkles" : "macwindow")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(appName.map { "Open \($0)" } ?? "Ask Sparrow anything")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).opacity(0.7)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.09)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        Button { VoiceEngine.shared.listenOnce() } label: {
                            Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(voice.isListening ? Color(hex: "#F9A830") : .white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.white.opacity(0.09)))
                                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Talk to Sparrow")
                    }
                }
                .padding(.trailing, 12)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Frosted glass card with a soft border (and an optional golden glow behind the sparrow).
struct GlassCard<Content: View>: View {
    var glow = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.11), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
            if glow {
                RadialGradient(colors: [Color(hex: "#F9A830").opacity(0.42), .clear], center: UnitPoint(x: 0.17, y: 0.55), startRadius: 2, endRadius: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Circle()
                    .stroke(LinearGradient(colors: [Color(hex: "#FFD27A"), Color(hex: "#F28A3C").opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.6)
                    .frame(width: 78, height: 78)
                    .shadow(color: Color(hex: "#F9A830").opacity(0.8), radius: 6)
                    .offset(x: 19)
            }
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
            .onChanged { _ in IslandDrag.changed() }
            .onEnded { _ in IslandDrag.ended() })
    }
}

// MARK: - Opening hello: the sparrow flies in and says good morning / afternoon / evening

struct SparrowGreetingView: View {
    @ObservedObject var state: AppState
    @State private var landed = false
    @State private var showText = false
    @State private var done = false

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let wing = sin(t * (landed ? 3 : 24)) * (landed ? 8 : 38)
            HStack(spacing: 14) {
                SparrowFigure(size: 62, blink: t.truncatingRemainder(dividingBy: 3.6) < 0.12 ? 0.12 : 1, wing: wing, sparkle: landed)
                    .offset(x: landed ? 0 : 340, y: landed ? CGFloat(sin(t * 2.2)) * 2 : -46)
                    .rotationEffect(.degrees(landed ? 0 : -16))
                    .scaleEffect(landed ? 1 : 0.5)
                if showText {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(SparrowHeaderText.greeting + "!")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [Color.white, Color(hex: "#FFD9A0")], startPoint: .top, endPoint: .bottom))
                        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · I'm listening 🐦")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            SparrowMascot.hasFlownIn = true
            SoundEngine.shared.play("chime")
            withAnimation(.spring(response: 1.0, dampingFraction: 0.6)) { landed = true }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.75)) { showText = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.6) {
                guard !done else { return }
                done = true
                NotificationCenter.default.post(name: .greetComplete, object: nil)
            }
        }
    }
}

// MARK: - Hide Sparrow into a little bubble (✕), click the bubble to bring it back

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
            onDrag: { SparrowBubble.shared.drag() },
            onEnd: { SparrowBubble.shared.dragEnded() })
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
                SparrowFigure(size: 30, blink: t.truncatingRemainder(dividingBy: 4) < 0.12 ? 0.12 : 1, wing: sin(t * 1.8) * 5)
                    .offset(y: CGFloat(sin(t * 2)) * 1.5)
            }
            .frame(width: 52, height: 52)
            .scaleEffect(hovered ? 1.08 : 1)
        }
        .frame(width: 64, height: 64)
        .contentShape(Circle())
        .onHover { hovered = $0 }
        .help("Click to bring Sparrow back · drag to move")
        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in onDrag() }.onEnded { _ in onEnd() })
    }
}
