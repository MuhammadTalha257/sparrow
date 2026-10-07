import SwiftUI
import AppKit
import ImageIO

// =====================================================================
// MARK: - The pink sparrow (page-mascot sprites)
// Two 3×3 sheets — nine head directions and nine expressions — cut once and
// shared by the island, the desktop pet and the greeting. The head turns
// toward the mouse anywhere on screen; a click gives a little reaction
// (four quick clicks = dizzy), like the web version.
// =====================================================================

@MainActor
final class SparrowSprites {
    static let shared = SparrowSprites()
    let directions: [CGImage]
    let reactions: [CGImage]

    private init() {
        func cut(_ name: String) -> [CGImage] {
            let base = Bundle.main.resourceURL?.appendingPathComponent("web/mascots")
            guard let url = base?.appendingPathComponent(name),
                  let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return [] }
            let w = img.width / 3, h = img.height / 3
            return (0..<9).compactMap { i in img.cropping(to: CGRect(x: (i % 3) * w, y: (i / 3) * h, width: w, height: h)) }
        }
        directions = cut("zuffi-directions.webp")
        reactions = cut("zuffi-reactions.webp")
    }
    var available: Bool { directions.count == 9 && reactions.count == 9 }
}

/// Which way the head points and which face it pulls.
@MainActor
final class SparrowSpriteModel: ObservableObject {
    // directions: 0 up-left · 1 up · 2 up-right · 3 left · 4 center · 5 right · 6 down-left · 7 down · 8 down-right
    @Published var direction = 4
    // reactions: 0 blink · 1 heart · 2 sparkle · 3 surprised · 4 starstruck · 5 bashful · 6 sleepy · 7 dizzy · 8 delighted
    @Published var reaction: Int?
    @Published var squash = CGSize(width: 1, height: 1)
    /// Something the sparrow carries (SF Symbol name): water bottle, coffee cup, pills.
    @Published var prop: String?
    /// Facing while walking across the screen.
    @Published var walkLeft = false

    private var sector = -1
    private var boops = 0
    private var lastBoop = Date.distantPast
    private var work: [DispatchWorkItem] = []

    private static let clockwise = [5, 8, 7, 6, 3, 0, 1, 2]     // right, down-right, down, down-left, left, up-left, up, up-right
    private static let sectorSize = Double.pi * 2 / 8

    /// center & mouse in screen coordinates (y up).
    func aim(center: CGPoint, mouse: CGPoint, deadZone: CGFloat) {
        let dx = Double(mouse.x - center.x), dy = Double(center.y - mouse.y)     // y down, like the web version
        if hypot(dx, dy) < Double(deadZone) { sector = -1; if direction != 4 { direction = 4 }; return }
        let angle = atan2(dy, dx)
        if sector != -1 {
            let diff = atan2(sin(angle - Double(sector) * Self.sectorSize), cos(angle - Double(sector) * Self.sectorSize))
            if abs(diff) < Self.sectorSize / 2 + 0.12 { return }
        }
        sector = (Int((angle / Self.sectorSize).rounded()) + 8) % 8
        let d = Self.clockwise[sector]
        if direction != d { direction = d }
    }

    private func later(_ s: Double, _ f: @escaping @MainActor () -> Void) {
        let w = DispatchWorkItem { MainActor.assumeIsolated { f() } }
        work.append(w)
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }
    private func clear() { work.forEach { $0.cancel() }; work = [] }

    private func bounce() {
        withAnimation(.easeOut(duration: 0.08)) { squash = CGSize(width: 1.10, height: 0.86) }
        later(0.08) { withAnimation(.interpolatingSpring(stiffness: 260, damping: 9)) { self.squash = CGSize(width: 1, height: 1) } }
    }

    func react(_ r: Int, for seconds: Double = 0.9) {
        clear()
        reaction = r
        bounce()
        later(seconds) { self.reaction = nil }
    }

    /// A click: blink → a happy face (heart, sparkle, delighted…); four quick clicks → dizzy.
    func boop() {
        clear()
        let now = Date()
        boops = now.timeIntervalSince(lastBoop) < 1.6 ? boops + 1 : 1
        lastBoop = now
        bounce()
        if boops >= 4 { boops = 0; reaction = 7; later(1.1) { self.reaction = nil }; return }
        reaction = 0
        let payoff = [1, 2, 8, 4, 5][(boops - 1) % 5]
        later(0.12) { self.reaction = payoff }
        later(0.64) { self.reaction = nil }
    }

    /// The old emotes (from talking, reminders, the island) shown with the new faces.
    func show(_ e: BotEmote) {
        switch e {
        case .love: react(1, for: 1.2)
        case .surprised: react(3)
        case .proud: react(4)
        case .wink: react(0, for: 0.4)
        case .yawn: react(6, for: 1.4)
        case .happy: react(8)
        case .annoyed: react(5)
        }
    }
}

/// Reports where it sits on screen, so the head can turn toward the mouse.
@MainActor
final class SpriteAnchor {
    weak var view: NSView?
    var screenCenter: CGPoint? {
        guard let v = view, let w = v.window else { return nil }
        let r = w.convertToScreen(v.convert(v.bounds, to: nil))
        return CGPoint(x: r.midX, y: r.midY)
    }
}
struct SpriteAnchorReader: NSViewRepresentable {
    let anchor: SpriteAnchor
    func makeNSView(context: Context) -> NSView { let v = PassThroughView(); anchor.view = v; return v }
    func updateNSView(_ nsView: NSView, context: Context) { anchor.view = nsView }
    final class PassThroughView: NSView { override func hitTest(_ point: NSPoint) -> NSView? { nil } }
}

/// What Zuffi is doing right now — drives the little animations (listening waves, thinking sparkles…).
enum SpriteMood: Equatable { case idle, listening, thinking, speaking, walking }

struct SparrowSpriteView: View {
    @ObservedObject var model: SparrowSpriteModel
    var size: CGFloat
    var deadZone: CGFloat = 50
    /// Gentle bob while Zuffi talks or listens.
    var lively: Bool = false
    var mood: SpriteMood = .idle
    var onTap: (() -> Void)? = nil

    @State private var anchor = SpriteAnchor()
    @State private var t = 0.0
    private let tick = Timer.publish(every: 1.0 / 20.0, on: .main, in: .common).autoconnect()

    /// The frame to show: reactions win; then the mood's own frames; else where the mouse is.
    private func frame(_ sprites: SparrowSprites) -> CGImage {
        if let r = model.reaction { return sprites.reactions[r] }
        switch mood {
        case .thinking: return sprites.directions[Int(t * 1.6) % 2 == 0 ? 0 : 2]        // looks up-left, up-right… pondering
        case .speaking: return Int(t * 7) % 3 == 0 ? sprites.reactions[8] : sprites.directions[4]   // little mouth movements
        case .listening: return sprites.directions[4]
        case .walking: return sprites.directions[model.walkLeft ? 3 : 5]
        case .idle: return sprites.directions[model.direction]
        }
    }

    var body: some View {
        let sprites = SparrowSprites.shared
        ZStack {
            if mood == .listening {
                // sound waves around the bunny while it listens
                ForEach(0..<3) { i in
                    let p = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle().stroke(Color(hex: "#F58FA8").opacity(0.55 * (1 - p)), lineWidth: 2)
                        .frame(width: size * (0.55 + 0.6 * p), height: size * (0.55 + 0.6 * p))
                }
            }
            if mood == .thinking {
                // twinkling sparkles while it thinks
                ForEach(0..<4) { i in
                    let a = t * 1.3 + Double(i) * .pi / 2
                    Image(systemName: i % 2 == 0 ? "sparkle" : "star.fill")
                        .font(.system(size: size * (i % 2 == 0 ? 0.13 : 0.08)))
                        .foregroundColor(Color(hex: i % 2 == 0 ? "#F7B32B" : "#F58FA8"))
                        .opacity(0.5 + 0.5 * sin(t * 4 + Double(i)))
                        .offset(x: cos(a) * size * 0.46, y: -size * 0.34 + sin(a) * size * 0.12)
                }
            }
            if sprites.available {
                Image(decorative: frame(sprites), scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: size, height: size)
            }
            if let prop = model.prop {
                Image(systemName: prop)
                    .font(.system(size: size * 0.30, weight: .semibold))
                    .foregroundStyle(propColor(prop))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .rotationEffect(.degrees(-12 + sin(t * 3) * 6))
                    .offset(x: size * 0.30, y: size * 0.24)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(x: model.squash.width, y: model.squash.height, anchor: UnitPoint(x: 0.5, y: 0.78))
        .offset(y: mood == .walking ? -abs(CGFloat(sin(t * 10))) * size * 0.06 : (lively || mood == .speaking) ? CGFloat(sin(t * 9)) * size * 0.015 : 0)
        .rotationEffect(.degrees(mood == .walking ? sin(t * 10) * 4 : 0), anchor: .bottom)
        .background(SpriteAnchorReader(anchor: anchor))
        .contentShape(Rectangle())
        .onTapGesture { model.boop(); onTap?() }
        .onReceive(tick) { _ in
            t += 0.05
            if mood == .idle, let c = anchor.screenCenter { model.aim(center: c, mouse: NSEvent.mouseLocation, deadZone: deadZone) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { n in
            if let e = n.object as? BotEmote { model.show(e) }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.prop)
    }

    private func propColor(_ name: String) -> Color {
        if name.contains("water") || name.contains("drop") { return Color(hex: "#4FA7FF") }
        if name.contains("cup") { return Color(hex: "#9A6A48") }
        return Color(hex: "#F06A8A")
    }
}

extension Notification.Name {
    /// Opens the island on a given view (note, prompt, upload…).
    static let hookExpand = Notification.Name("notchBuddy.hookExpand")
}
