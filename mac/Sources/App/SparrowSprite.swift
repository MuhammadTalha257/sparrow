import SwiftUI
import AppKit
import ImageIO
import SceneKit

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
    private(set) var directions: [CGImage] = []
    private(set) var reactions: [CGImage] = []

    private init() { reload() }
    /// (Re)load the two sheets — in the current outfit (ZuffiSeasons).
    func reload() {
        func cut(_ name: String) -> [CGImage] {
            guard let url = ZuffiSeasons.file(name),
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

    @ObservedObject private var look = ZuffiLook.shared
    @State private var anchor = SpriteAnchor()
    @State private var t = 0.0
    @State private var lean = 0.0           // smooth tilt toward the mouse (degrees)
    private let tick = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    /// Which frame is showing (changes cross-fade).
    private var frameKey: String {
        if let r = model.reaction { return "r\(r)" }
        switch mood {
        case .thinking: return "t\(Int(t * 1.6) % 2)"
        case .speaking: return Int(t * 7) % 3 == 0 ? "s1" : "s0"
        case .walking: return model.walkLeft ? "wl" : "wr"
        default: return "d\(model.direction)"
        }
    }

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
            if sprites.available || ZuffiLook.shared.kind != .bunny {
                // Frames cross-fade (no hard jumps) and the head leans a little toward the mouse in between.
                ZuffiFace(frame: sprites.available ? frame(sprites) : nil, size: size, mood: mood)
                    .id(frameKey)
                    .transition(.opacity)
                    .rotationEffect(.degrees(lean), anchor: .bottom)
                    .offset(x: CGFloat(lean) * size * 0.006)
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
            t += 1.0 / 30.0
            if mood == .idle, let c = anchor.screenCenter {
                model.aim(center: c, mouse: NSEvent.mouseLocation, deadZone: deadZone)
                let target = max(-6, min(6, Double(NSEvent.mouseLocation.x - c.x) / 60))
                lean += (target - lean) * 0.15
            } else { lean += (0 - lean) * 0.15 }
        }
        .animation(.easeInOut(duration: 0.16), value: frameKey)
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

// =====================================================================
// MARK: - 3D buddies (SceneKit): the agents (small pearl robots) and the bunny pet
//
// Drawn in code from round shapes, so every part (head, ears, arms, legs) moves on its own:
// the head turns smoothly toward the mouse, steps are a real walk cycle, nothing jumps between frames.
// Each agent wears its field's colour (eyes stay cyan) and holds its tool. Original designs.
// =====================================================================

enum Buddy3DKind: Equatable { case bunny; case robot(AgentField) }
/// "3D pet" switch (Settings): on by default; the drawn bunny is the fallback.
enum Buddy3DPrefs {
    /// The pet: your Aurora bunny (default) or the classic drawn one.
    static var on: Bool { (UserDefaults.standard.object(forKey: "petAurora") as? Bool ?? true) && AuroraArt.shared.available }
}
enum Buddy3DMood: Equatable { case idle, working, speaking, listening, walking, happy }

struct Buddy3DView: NSViewRepresentable {
    var kind: Buddy3DKind
    var mood: Buddy3DMood = .idle
    var walkLeft = false
    var lookAtMouse = true

    func makeCoordinator() -> Buddy3DCoordinator { Buddy3DCoordinator(kind: kind) }
    func makeNSView(context: Context) -> SCNView { context.coordinator.makeView(lookAtMouse: lookAtMouse) }
    func updateNSView(_ v: SCNView, context: Context) { context.coordinator.set(mood: mood, walkLeft: walkLeft) }
    static func dismantleNSView(_ v: SCNView, coordinator: Buddy3DCoordinator) { coordinator.stop() }
}

/// Builds the model and moves it every frame (SceneKit's render loop). Shared values are guarded by a lock.
final class Buddy3DCoordinator: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    private let kind: Buddy3DKind
    private let lock = NSLock()
    private var mood: Buddy3DMood = .idle
    private var walkLeft = false
    private var targetYaw: CGFloat = 0, targetPitch: CGFloat = 0
    private var yaw: CGFloat = 0, pitch: CGFloat = 0, turn: CGFloat = 0
    private var last: TimeInterval = 0
    private var happySince: TimeInterval = -1
    private var nextBlink: TimeInterval = 2
    private var timer: Timer?
    private weak var view: SCNView?

    // parts
    private let root = SCNNode(), body = SCNNode(), head = SCNNode()
    private var eyes: [SCNNode] = [], ears: [SCNNode] = [], shoulders: [SCNNode] = [], elbows: [SCNNode] = [], hips: [SCNNode] = []
    private var glows: [SCNMaterial] = []
    private var tail: SCNNode?

    init(kind: Buddy3DKind) { self.kind = kind }

    func set(mood m: Buddy3DMood, walkLeft w: Bool) {
        lock.lock(); if m == .happy && mood != .happy { happySince = -2 }; mood = m; walkLeft = w; lock.unlock()
    }

    @MainActor func makeView(lookAtMouse: Bool) -> SCNView {
        let v = SCNView(frame: NSRect(x: 0, y: 0, width: 160, height: 180), options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.preferredFramesPerSecond = 60
        v.rendersContinuously = true
        v.allowsCameraControl = false
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        scene.lightingEnvironment.contents = Self.studioImage()
        scene.lightingEnvironment.intensity = 1.4
        build(scene)
        v.scene = scene
        v.delegate = self
        v.isPlaying = true
        view = v
        if lookAtMouse {
            timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.aim() }
            }
        }
        return v
    }
    func stop() { timer?.invalidate(); timer = nil }

    /// Where the mouse is, relative to the buddy on screen → where the head should look.
    @MainActor private func aim() {
        guard let v = view, let w = v.window else { return }
        let r = w.convertToScreen(v.convert(v.bounds, to: nil))
        let m = NSEvent.mouseLocation
        let dx = m.x - r.midX, dy = m.y - (r.minY + r.height * 0.7)
        let near = hypot(dx, dy) < 30
        lock.lock()
        targetYaw = near ? 0 : max(-0.75, min(0.75, dx / 380))
        targetPitch = near ? 0 : max(-0.35, min(0.3, -dy / 420))
        lock.unlock()
    }

    // MARK: building

    private static func color(_ hex: String) -> NSColor { NSColor(Color(hex: hex)) }
    private func pearl(_ tint: NSColor = NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.98, alpha: 1), rough: CGFloat = 0.24) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = tint; m.metalness.contents = 0.12; m.roughness.contents = rough
        m.clearCoat.contents = 0.8; m.clearCoatRoughness.contents = 0.15
        return m
    }
    private func glow(_ c: NSColor) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .constant
        m.diffuse.contents = c; m.emission.contents = c
        glows.append(m)
        return m
    }
    private func node(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3 = SCNVector3Zero, scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
        g.firstMaterial = m
        let n = SCNNode(geometry: g); n.position = p; n.scale = scale
        return n
    }

    private func build(_ scene: SCNScene) {
        // camera: a soft, slightly-from-above product shot with a little glow (bloom) on the lights
        let cam = SCNCamera()
        cam.fieldOfView = 26; cam.wantsHDR = true; cam.bloomIntensity = 0.7; cam.bloomThreshold = 0.55; cam.bloomBlurRadius = 6
        cam.wantsExposureAdaptation = false; cam.exposureOffset = 0.15
        let cn = SCNNode(); cn.camera = cam; cn.position = SCNVector3(0, 0.15, 8.4)
        cn.look(at: SCNVector3(0, -0.45, 0))
        scene.rootNode.addChildNode(cn)
        func light(_ type: SCNLight.LightType, _ i: CGFloat, _ p: SCNVector3, _ c: NSColor = .white) {
            let l = SCNLight(); l.type = type; l.intensity = i; l.color = c
            let n = SCNNode(); n.light = l; n.position = p; n.look(at: SCNVector3(0, -0.4, 0)); scene.rootNode.addChildNode(n)
        }
        light(.directional, 900, SCNVector3(-3, 5, 6))
        light(.omni, 380, SCNVector3(4, 1, 5), NSColor(calibratedRed: 0.85, green: 0.9, blue: 1, alpha: 1))
        light(.directional, 650, SCNVector3(0, 3, -6))          // rim light
        light(.ambient, 220, SCNVector3Zero)
        // soft round shadow on the "floor"
        let sh = SCNPlane(width: 2.1, height: 0.7)
        let sm = SCNMaterial(); sm.lightingModel = .constant; sm.diffuse.contents = Self.shadowImage(); sm.writesToDepthBuffer = false
        sh.firstMaterial = sm
        let shn = SCNNode(geometry: sh); shn.eulerAngles.x = -.pi / 2; shn.position = SCNVector3(0, -2.02, 0)
        scene.rootNode.addChildNode(shn)

        scene.rootNode.addChildNode(root)
        root.addChildNode(body)
        switch kind {
        case .bunny: buildBunny()
        case .robot(let f): buildRobot(f)
        }
    }

    private func buildRobot(_ field: AgentField) {
        let accent = Self.color(field.colors[0])
        let eye = Self.color("#5EF2FF")
        let white = pearl()
        let dark = SCNMaterial(); dark.lightingModel = .physicallyBased
        dark.diffuse.contents = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.14, alpha: 1); dark.metalness.contents = 0.35; dark.roughness.contents = 0.12
        // body
        body.addChildNode(node(SCNSphere(radius: 0.52), white, SCNVector3(0, -0.98, 0), scale: SCNVector3(1, 1.08, 0.88)))
        body.addChildNode(node(SCNTorus(ringRadius: 0.11, pipeRadius: 0.028), glow(accent), SCNVector3(0, -0.82, 0.44), scale: SCNVector3(1, 1, 1)))
        body.childNodes.last?.eulerAngles.x = .pi / 2
        body.addChildNode(node(SCNSphere(radius: 0.05), glow(accent), SCNVector3(0, -0.82, 0.46)))
        let belt = node(SCNTorus(ringRadius: 0.47, pipeRadius: 0.035), glow(accent.withAlphaComponent(0.95)), SCNVector3(0, -1.22, 0), scale: SCNVector3(1, 1, 0.86))
        body.addChildNode(belt)
        // head (pivot at the neck)
        head.position = SCNVector3(0, -0.42, 0)
        body.addChildNode(head)
        head.addChildNode(node(SCNSphere(radius: 0.74), white, SCNVector3(0, 0.62, 0), scale: SCNVector3(1.1, 0.96, 0.96)))
        head.addChildNode(node(SCNSphere(radius: 0.62), dark, SCNVector3(0, 0.6, 0.36), scale: SCNVector3(1.06, 0.78, 0.5)))
        for x in [-0.24, 0.24] as [CGFloat] {
            let e = node(SCNSphere(radius: 0.13), glow(eye), SCNVector3(x, 0.62, 0.66), scale: SCNVector3(1, 1.12, 0.45))
            e.addChildNode(node(SCNSphere(radius: 0.035), glow(.white), SCNVector3(0.04, 0.05, 0.1)))
            head.addChildNode(e); eyes.append(e)
        }
        head.addChildNode(smile(eye, y: 0.42, z: 0.68))
        head.addChildNode(node(SCNCapsule(capRadius: 0.032, height: 0.3), glow(accent), SCNVector3(0, 1.16, 0.5), scale: SCNVector3(1, 1, 1)))
        head.childNodes.last?.eulerAngles.z = .pi / 2
        head.childNodes.last?.eulerAngles.x = -0.5
        for s in [-1.0, 1.0] as [CGFloat] {
            // ear pods with glowing rings
            let pod = node(SCNCylinder(radius: 0.17, height: 0.16), white, SCNVector3(s * 0.8, 0.62, 0))
            pod.eulerAngles.z = .pi / 2
            head.addChildNode(pod)
            let ring = node(SCNTorus(ringRadius: 0.12, pipeRadius: 0.024), glow(accent), SCNVector3(s * 0.89, 0.62, 0))
            ring.eulerAngles.z = .pi / 2
            head.addChildNode(ring)
            // antennae
            let ant = SCNNode(); ant.position = SCNVector3(s * 0.55, 1.2, -0.05); ant.eulerAngles.z = -s * 0.22
            ant.addChildNode(node(SCNCapsule(capRadius: 0.055, height: 0.42), white, SCNVector3(0, 0.12, 0)))
            ant.addChildNode(node(SCNTorus(ringRadius: 0.05, pipeRadius: 0.012), glow(accent), SCNVector3(0, 0.02, 0)))
            head.addChildNode(ant); ears.append(ant)
            // arms: shoulder → elbow → hand
            let sh = SCNNode(); sh.position = SCNVector3(s * 0.6, -0.68, 0); body.addChildNode(sh); shoulders.append(sh)
            sh.addChildNode(node(SCNSphere(radius: 0.15), white))
            sh.addChildNode(node(SCNTorus(ringRadius: 0.13, pipeRadius: 0.02), glow(accent), SCNVector3(0, -0.06, 0)))
            sh.addChildNode(node(SCNCapsule(capRadius: 0.085, height: 0.34), white, SCNVector3(0, -0.2, 0)))
            let el = SCNNode(); el.position = SCNVector3(0, -0.38, 0); sh.addChildNode(el); elbows.append(el)
            el.addChildNode(node(SCNCapsule(capRadius: 0.08, height: 0.3), white, SCNVector3(0, -0.14, 0)))
            el.addChildNode(node(SCNSphere(radius: 0.095), white, SCNVector3(0, -0.32, 0)))
            if s > 0, let item = tool(for: field, accent: accent) { item.position = SCNVector3(0.02, -0.42, 0.12); el.addChildNode(item) }
            // legs: hip → foot (feet float a little, like a hover robot)
            let hp = SCNNode(); hp.position = SCNVector3(s * 0.22, -1.4, 0); body.addChildNode(hp); hips.append(hp)
            hp.addChildNode(node(SCNCapsule(capRadius: 0.12, height: 0.34), white, SCNVector3(0, -0.15, 0)))
            hp.addChildNode(node(SCNTorus(ringRadius: 0.1, pipeRadius: 0.02), glow(accent), SCNVector3(0, -0.2, 0)))
            hp.addChildNode(node(SCNSphere(radius: 0.16), white, SCNVector3(0, -0.4, 0.04), scale: SCNVector3(1, 0.72, 1.25)))
            hp.addChildNode(node(SCNCylinder(radius: 0.1, height: 0.012), glow(accent), SCNVector3(0, -0.5, 0.04)))
        }
        if let hat = hat(for: field, accent: accent) { head.addChildNode(hat) }
    }

    private func buildBunny() {
        let fur = pearl(NSColor(calibratedRed: 0.99, green: 0.96, blue: 0.95, alpha: 1), rough: 0.85)
        fur.clearCoat.contents = 0
        let pink = pearl(NSColor(calibratedRed: 0.98, green: 0.72, blue: 0.76, alpha: 1), rough: 0.6); pink.clearCoat.contents = 0
        let blush = SCNMaterial(); blush.lightingModel = .constant; blush.diffuse.contents = NSColor(calibratedRed: 1, green: 0.6, blue: 0.68, alpha: 0.45); blush.writesToDepthBuffer = false
        let eyeM = SCNMaterial(); eyeM.lightingModel = .physicallyBased
        eyeM.diffuse.contents = NSColor(calibratedRed: 0.16, green: 0.09, blue: 0.07, alpha: 1); eyeM.roughness.contents = 0.04; eyeM.clearCoat.contents = 1
        body.addChildNode(node(SCNSphere(radius: 0.6), fur, SCNVector3(0, -1.0, 0), scale: SCNVector3(1, 1.02, 0.95)))
        body.addChildNode(node(SCNSphere(radius: 0.42), pearl(.white, rough: 0.9), SCNVector3(0, -1.05, 0.25), scale: SCNVector3(1, 1.05, 0.7)))
        head.position = SCNVector3(0, -0.5, 0); body.addChildNode(head)
        head.addChildNode(node(SCNSphere(radius: 0.8), fur, SCNVector3(0, 0.62, 0), scale: SCNVector3(1.08, 0.98, 0.98)))
        for s in [-1.0, 1.0] as [CGFloat] {
            let e = node(SCNSphere(radius: 0.17), eyeM, SCNVector3(s * 0.29, 0.66, 0.66), scale: SCNVector3(1, 1.12, 0.6))
            e.addChildNode(node(SCNSphere(radius: 0.05), glow(.white), SCNVector3(0.05, 0.06, 0.13)))
            e.addChildNode(node(SCNSphere(radius: 0.022), glow(.white), SCNVector3(-0.05, -0.05, 0.14)))
            head.addChildNode(e); eyes.append(e)
            head.addChildNode(node(SCNSphere(radius: 0.13), blush, SCNVector3(s * 0.43, 0.42, 0.62), scale: SCNVector3(1, 0.6, 0.4)))
            // long ears with pink inside (pivot at the base, so they twitch and flop)
            let ear = SCNNode(); ear.position = SCNVector3(s * 0.3, 1.25, -0.05); ear.eulerAngles.z = -s * 0.16
            ear.addChildNode(node(SCNCapsule(capRadius: 0.18, height: 1.0), fur, SCNVector3(0, 0.42, 0), scale: SCNVector3(1, 1, 0.5)))
            ear.addChildNode(node(SCNCapsule(capRadius: 0.11, height: 0.76), pink, SCNVector3(0, 0.42, 0.06), scale: SCNVector3(1, 1, 0.3)))
            head.addChildNode(ear); ears.append(ear)
            // little arms (paws in front) and big feet
            let sh = SCNNode(); sh.position = SCNVector3(s * 0.32, -0.78, 0.36); body.addChildNode(sh); shoulders.append(sh)
            sh.addChildNode(node(SCNCapsule(capRadius: 0.11, height: 0.34), fur, SCNVector3(0, -0.12, 0.02)))
            let el = SCNNode(); el.position = SCNVector3(0, -0.26, 0.04); sh.addChildNode(el); elbows.append(el)
            el.addChildNode(node(SCNSphere(radius: 0.04), pink, SCNVector3(0, -0.04, 0.08)))
            let hp = SCNNode(); hp.position = SCNVector3(s * 0.3, -1.5, 0.12); body.addChildNode(hp); hips.append(hp)
            hp.addChildNode(node(SCNSphere(radius: 0.2), fur, SCNVector3(0, -0.06, 0.08), scale: SCNVector3(0.9, 0.55, 1.4)))
            hp.addChildNode(node(SCNSphere(radius: 0.07), pink, SCNVector3(0, -0.13, 0.28), scale: SCNVector3(1, 0.4, 0.8)))
        }
        head.addChildNode(node(SCNSphere(radius: 0.065), pink, SCNVector3(0, 0.46, 0.79), scale: SCNVector3(1.25, 0.8, 0.7)))
        head.addChildNode(smile(NSColor(calibratedRed: 0.75, green: 0.35, blue: 0.42, alpha: 1), y: 0.36, z: 0.78))
        let t = node(SCNSphere(radius: 0.2), fur, SCNVector3(0, -1.2, -0.58)); body.addChildNode(t); tail = t
    }

    /// A little crescent smile (extruded path).
    private func smile(_ c: NSColor, y: CGFloat, z: CGFloat) -> SCNNode {
        let p = NSBezierPath()
        p.appendArc(withCenter: .zero, radius: 0.1, startAngle: 200, endAngle: 340, clockwise: false)
        p.appendArc(withCenter: .zero, radius: 0.075, startAngle: 340, endAngle: 200, clockwise: true)
        p.close()
        let s = SCNShape(path: p, extrusionDepth: 0.02)
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = c; m.emission.contents = c
        s.firstMaterial = m
        let n = SCNNode(geometry: s); n.position = SCNVector3(0, y + 0.06, z)
        return n
    }

    /// What each field's robot holds.
    private func tool(for f: AgentField, accent: NSColor) -> SCNNode? {
        let n = SCNNode(), m = glow(accent), w = pearl()
        switch f {
        case .research, .education:
            n.addChildNode(node(SCNTorus(ringRadius: 0.09, pipeRadius: 0.022), m, SCNVector3(0, 0.08, 0)))
            n.childNodes.last?.eulerAngles.x = .pi / 2
            n.addChildNode(node(SCNCapsule(capRadius: 0.022, height: 0.16), w, SCNVector3(0, -0.06, 0)))
        case .marketing:
            let c = node(SCNCone(topRadius: 0.03, bottomRadius: 0.11, height: 0.2), m)
            c.eulerAngles.z = -.pi / 2; n.addChildNode(c)
        case .finance, .data:
            for (i, h) in [0.08, 0.14, 0.2].enumerated() { n.addChildNode(node(SCNBox(width: 0.04, height: CGFloat(h), length: 0.04, chamferRadius: 0.01), m, SCNVector3(Float(i) * 0.055 - 0.055, Float(h / 2), 0))) }
        case .bookings, .project:
            n.addChildNode(node(SCNBox(width: 0.2, height: 0.2, length: 0.03, chamferRadius: 0.02), w))
            n.addChildNode(node(SCNBox(width: 0.2, height: 0.05, length: 0.035, chamferRadius: 0.01), m, SCNVector3(0, 0.08, 0)))
        case .sales:
            n.addChildNode(node(SCNBox(width: 0.22, height: 0.15, length: 0.07, chamferRadius: 0.02), m))
            n.addChildNode(node(SCNTorus(ringRadius: 0.04, pipeRadius: 0.012), w, SCNVector3(0, 0.09, 0)))
        case .customers, .health:
            n.addChildNode(node(SCNSphere(radius: 0.065), m, SCNVector3(-0.045, 0.02, 0)))
            n.addChildNode(node(SCNSphere(radius: 0.065), m, SCNVector3(0.045, 0.02, 0)))
            let c = node(SCNCone(topRadius: 0.1, bottomRadius: 0, height: 0.12), m, SCNVector3(0, -0.06, 0)); n.addChildNode(c)
        case .travel:
            n.addChildNode(node(SCNCapsule(capRadius: 0.035, height: 0.26), w))
            n.childNodes.last?.eulerAngles.z = .pi / 2
            n.addChildNode(node(SCNBox(width: 0.06, height: 0.02, length: 0.26, chamferRadius: 0.01), m))
        case .product:
            n.addChildNode(node(SCNBox(width: 0.18, height: 0.16, length: 0.16, chamferRadius: 0.02), m))
        case .design:
            n.addChildNode(node(SCNCapsule(capRadius: 0.02, height: 0.24), w)); n.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.035, height: 0.07), m, SCNVector3(0, 0.15, 0)))
        case .support:
            n.addChildNode(node(SCNSphere(radius: 0.09), m, SCNVector3.init(0, 0, 0), scale: SCNVector3(1.3, 0.9, 0.5)))
        case .web:
            n.addChildNode(node(SCNSphere(radius: 0.09), m))
            let ring = node(SCNTorus(ringRadius: 0.12, pipeRadius: 0.012), w); ring.eulerAngles.x = 0.5; n.addChildNode(ring)
        default: return nil
        }
        return n
    }

    private func hat(for f: AgentField, accent: NSColor) -> SCNNode? {
        let n = SCNNode(), m = pearl(accent, rough: 0.35)
        switch f {
        case .marketing, .sales:          // cap
            n.addChildNode(node(SCNSphere(radius: 0.62), m, SCNVector3(0, 1.08, 0), scale: SCNVector3(1.12, 0.45, 1.08)))
            n.addChildNode(node(SCNCylinder(radius: 0.36, height: 0.04), m, SCNVector3(0, 1.0, 0.62), scale: SCNVector3(1, 1, 0.9)))
        case .research, .education, .data: // graduation cap
            n.addChildNode(node(SCNBox(width: 0.95, height: 0.05, length: 0.95, chamferRadius: 0.02), pearl(NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.22, alpha: 1)), SCNVector3(0, 1.42, 0)))
            n.childNodes.last?.eulerAngles.y = .pi / 4
            n.addChildNode(node(SCNCylinder(radius: 0.34, height: 0.16), pearl(NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.22, alpha: 1)), SCNVector3(0, 1.32, 0)))
            n.addChildNode(node(SCNCapsule(capRadius: 0.018, height: 0.32), glow(accent), SCNVector3(0.4, 1.3, 0.2)))
        case .travel:                      // pilot cap
            n.addChildNode(node(SCNCylinder(radius: 0.5, height: 0.2), m, SCNVector3(0, 1.32, 0), scale: SCNVector3(1, 1, 1)))
            n.addChildNode(node(SCNCylinder(radius: 0.36, height: 0.03), pearl(NSColor(calibratedRed: 0.1, green: 0.12, blue: 0.2, alpha: 1)), SCNVector3(0, 1.22, 0.4)))
            n.addChildNode(node(SCNSphere(radius: 0.05), glow(NSColor(calibratedRed: 1, green: 0.85, blue: 0.3, alpha: 1)), SCNVector3(0, 1.34, 0.5)))
        case .engineering, .project:       // hard hat
            n.addChildNode(node(SCNSphere(radius: 0.62), pearl(NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.2, alpha: 1)), SCNVector3(0, 1.08, 0), scale: SCNVector3(1.12, 0.55, 1.1)))
        case .design:                      // beret
            n.addChildNode(node(SCNSphere(radius: 0.55), m, SCNVector3(-0.1, 1.24, 0), scale: SCNVector3(1.15, 0.32, 1.1)))
        case .manager:                     // crown
            let gold = pearl(NSColor(calibratedRed: 1, green: 0.8, blue: 0.3, alpha: 1), rough: 0.2); gold.metalness.contents = 0.9
            n.addChildNode(node(SCNTube(innerRadius: 0.3, outerRadius: 0.34, height: 0.16), gold, SCNVector3(0, 1.36, 0)))
            for i in 0..<5 { let a = Float(i) * 2 * .pi / 5; n.addChildNode(node(SCNCone(topRadius: 0, bottomRadius: 0.07, height: 0.16), gold, SCNVector3(sin(a) * 0.32, 1.5, cos(a) * 0.32))) }
        default: return nil
        }
        return n
    }

    // MARK: moving (every frame)

    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        lock.lock()
        let m = mood, left = walkLeft, ty = targetYaw, tp = targetPitch
        if happySince == -2 { happySince = time }
        let hs = happySince
        lock.unlock()
        let dt = CGFloat(last == 0 ? 1 / 60 : min(0.05, time - last)); last = time
        let t = CGFloat(time)
        let robot: Bool = { if case .robot = kind { return true }; return false }()
        let pi = CGFloat.pi

        // the head follows the mouse with easing (no jumps), or looks where it walks
        let walking = m == .walking
        let wantYaw: CGFloat = walking ? 0 : ty, wantPitch: CGFloat = walking ? 0 : (m == .working ? 0.22 : tp)
        let k = min(1, dt * 5)
        yaw += (wantYaw - yaw) * k; pitch += (wantPitch - pitch) * k
        // the whole body turns to show its side while walking
        let wantTurn: CGFloat = walking ? (left ? -1.0 : 1.0) : 0
        turn += (wantTurn - turn) * min(1, dt * 4)
        root.eulerAngles.y = turn

        var y: CGFloat = 0, lean: CGFloat = 0
        let phase = t * (robot ? 7.5 : 6)
        func side(_ i: Int) -> CGFloat { i == 0 ? 1 : -1 }
        switch m {
        case .walking:
            if robot {
                y = abs(sin(phase)) * 0.06
                for (i, h) in hips.enumerated() { h.eulerAngles.x = sin(phase + CGFloat(i) * pi) * 0.55 }
                for (i, s) in shoulders.enumerated() { s.eulerAngles.x = -sin(phase + CGFloat(i) * pi) * 0.45; s.eulerAngles.z = 0 }
                lean = 0.06
            } else {
                // bunny hops: up, a soft squash on landing
                let hop = max(0, sin(phase))
                y = hop * 0.35
                body.scale = SCNVector3(1 + (1 - hop) * 0.04, 1 - (1 - hop) * 0.05, 1)
                for h in hips { h.eulerAngles.x = -hop * 0.5 }
                for e in ears { e.eulerAngles.x = -0.25 + hop * 0.35 }
                lean = 0.12
            }
        case .working:
            y = sin(t * 2.2) * 0.03
            for (i, s) in shoulders.enumerated() { s.eulerAngles.x = -0.9 + sin(t * 9 + CGFloat(i) * 1.7) * 0.12; s.eulerAngles.z = side(i) * 0.25 }
            for (i, e) in elbows.enumerated() { e.eulerAngles.x = -0.7 + sin(t * 11 + CGFloat(i)) * 0.15 }
            for h in hips { h.eulerAngles.x += (0 - h.eulerAngles.x) * k }
        case .happy:
            let d = hs < 0 ? 0 : CGFloat(time - hs)
            y = max(0, sin(d * 7)) * (d < 2.2 ? 0.3 : 0.08)
            for (i, s) in shoulders.enumerated() { s.eulerAngles.z = side(i) * 2.4 + sin(t * 10) * 0.15; s.eulerAngles.x = 0 }
            for h in hips { h.eulerAngles.x += (0 - h.eulerAngles.x) * k }
        case .speaking, .listening:
            y = sin(t * (m == .speaking ? 6 : 2)) * 0.03
            for (i, s) in shoulders.enumerated() { s.eulerAngles.x += (0 - s.eulerAngles.x) * k; s.eulerAngles.z += (side(i) * 0.08 - s.eulerAngles.z) * k }
            for h in hips { h.eulerAngles.x += (0 - h.eulerAngles.x) * k }
        case .idle:
            y = sin(t * 1.8) * (robot ? 0.06 : 0.02)        // robots hover, the bunny breathes
            for (i, s) in shoulders.enumerated() {
                s.eulerAngles.x += (sin(t * 1.3 + CGFloat(i)) * 0.06 - s.eulerAngles.x) * k
                s.eulerAngles.z += (side(i) * 0.1 - s.eulerAngles.z) * k
            }
            for e in elbows { e.eulerAngles.x += (-0.15 - e.eulerAngles.x) * k }
            for h in hips { h.eulerAngles.x += (0 - h.eulerAngles.x) * k }
        }
        if m != .walking { body.scale = SCNVector3(1 + sin(t * 2.2) * 0.008, 1 - sin(t * 2.2) * 0.008, 1) }
        root.position.y = y
        root.eulerAngles.x = lean
        head.eulerAngles = SCNVector3(pitch, yaw, sin(t * 0.9) * 0.04 + (m == .listening ? 0.18 : 0))

        // blink every few seconds; happy eyes squint
        if time > nextBlink + 0.16 { nextBlink = time + 2.5 + Double((sin(t * 3.7) + 1) * 1.5) }
        let blinking = time > nextBlink && time < nextBlink + 0.16
        let eyeY: CGFloat = blinking ? 0.12 : (m == .happy ? 0.55 : 1)
        for e in eyes { e.scale.y += (1.12 * eyeY - e.scale.y) * min(1, dt * 22) }
        // ears / antennae: a little sway, a twitch now and then
        if m != .walking {
            for (i, e) in ears.enumerated() {
                let twitch: CGFloat = sin(t * 0.7 + CGFloat(i) * 2) > 0.97 ? sin(t * 40) * 0.12 : 0
                e.eulerAngles.x = sin(t * 1.4 + CGFloat(i)) * 0.06 + twitch
            }
        }
        tail?.position.x = sin(t * 3) * 0.03
        // working robots: lights pulse
        if robot { let pulse: CGFloat = m == .working ? 0.75 + 0.25 * sin(t * 6) : 1; for g in glows { g.emission.intensity = pulse } }
    }

    // MARK: images made in code (reflections and the soft shadow)

    private static func studioImage() -> NSImage {
        let size = NSSize(width: 256, height: 128)
        let img = NSImage(size: size)
        img.lockFocus()
        NSGradient(colors: [NSColor(calibratedWhite: 1, alpha: 1), NSColor(calibratedWhite: 0.78, alpha: 1), NSColor(calibratedRed: 0.55, green: 0.6, blue: 0.7, alpha: 1)])?
            .draw(in: NSRect(origin: .zero, size: size), angle: -90)
        img.unlockFocus()
        return img
    }
    private static func shadowImage() -> NSImage {
        let size = NSSize(width: 256, height: 96)
        let img = NSImage(size: size)
        img.lockFocus()
        NSGradient(colors: [NSColor(calibratedWhite: 0, alpha: 0.35), NSColor(calibratedWhite: 0, alpha: 0)])?
            .draw(fromCenter: NSPoint(x: 128, y: 48), radius: 0, toCenter: NSPoint(x: 128, y: 48), radius: 120, options: [])
        img.unlockFocus()
        return img
    }
}

// MARK: - The Aurora bunny (the pet): your reference bunny — front, side and back — moving smoothly
//
// Three cut-out views of the same soft, realistic bunny. Movement is continuous (60 fps): the body turns toward the mouse with
// easing, breathes, hops while walking (side view, flipped when going left), wiggles when happy. A soft dark halo keeps it
// visible on white pages.

@MainActor
final class AuroraArt {
    static let shared = AuroraArt()
    let front: NSImage?, side: NSImage?, back: NSImage?
    private init() {
        func load(_ n: String) -> NSImage? {
            (Bundle.main.url(forResource: n, withExtension: "png", subdirectory: "agents/pet") ?? Bundle.main.url(forResource: n, withExtension: "png")).flatMap(NSImage.init(contentsOf:))
        }
        front = load("bunny-front"); side = load("bunny-side"); back = load("bunny-back")
    }
    var available: Bool { front != nil && side != nil }
}

/// Smoothed values kept between frames (a class, so updating them doesn't redraw by itself).
final class AuroraMotion {
    var lookX: CGFloat = 0, lookY: CGFloat = 0
    var facing: CGFloat = 0        // 0 = front … 1 = side
    var last: TimeInterval = 0
}

struct AuroraBunnyView: View {
    var height: CGFloat = 170
    var mood: Buddy3DMood = .idle
    var walkLeft = false
    var followMouse = true
    @State private var motion = AuroraMotion()
    @State private var anchor = SpriteAnchor()

    var body: some View {
        let art = AuroraArt.shared
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let st = step(t)
            ZStack(alignment: .bottom) {
                // ground shadow (shrinks while in the air)
                Ellipse().fill(Color.black.opacity(0.22 - st.hop * 0.12))
                    .frame(width: height * 0.42 * (1 - st.hop * 0.35), height: height * 0.06).blur(radius: 3)
                ZStack {
                    if let f = art.front {
                        Image(nsImage: f).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .opacity(1 - motion.facing)
                    }
                    if let s = art.side {
                        Image(nsImage: s).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                            .scaleEffect(x: walkLeft ? -1 : 1, y: 1)
                            .opacity(motion.facing)
                    }
                }
                .frame(height: height)
                // a soft halo so the white bunny shows on white pages
                .shadow(color: .black.opacity(0.35), radius: 1.2)
                .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
                // turn toward the mouse, breathe, hop
                .rotation3DEffect(.degrees(Double(motion.lookX) * 22), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5)
                .rotation3DEffect(.degrees(Double(motion.lookY) * 10), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                .rotationEffect(.degrees(st.tilt), anchor: .bottom)
                .scaleEffect(x: st.sx, y: st.sy, anchor: .bottom)
                .offset(y: -st.hop * height * 0.16)
            }
            .frame(height: height * 1.12, alignment: .bottom)
        }
        .background(SpriteAnchorReader(anchor: anchor))
    }

    /// One frame of movement.
    private func step(_ t: TimeInterval) -> (hop: CGFloat, sx: CGFloat, sy: CGFloat, tilt: Double) {
        let dt = CGFloat(motion.last == 0 ? 1 / 60 : min(0.05, t - motion.last)); motion.last = t
        // where to look (eased, no jumps)
        var tx: CGFloat = 0, ty: CGFloat = 0
        if followMouse, mood != .walking, let c = anchor.screenCenter {
            let m = NSEvent.mouseLocation
            tx = max(-1, min(1, (m.x - c.x) / 420)); ty = max(-1, min(1, (c.y - m.y) / 520)) * -1
        }
        let k = min(1, dt * 4.5)
        motion.lookX += (tx - motion.lookX) * k; motion.lookY += (ty - motion.lookY) * k
        motion.facing += ((mood == .walking ? 1 : 0) - motion.facing) * min(1, dt * 7)
        let breathe = sin(t * 2.1)
        switch mood {
        case .walking:
            // little hops: up, then a soft squash on landing
            let p = (t / 0.42).truncatingRemainder(dividingBy: 1)
            let hop = CGFloat(sin(p * .pi))
            let land = CGFloat(max(0, 1 - p * 6))
            return (hop, 1 + land * 0.05, 1 - land * 0.07 + hop * 0.03, walkLeft ? -4 * Double(hop) : 4 * Double(hop))
        case .happy:
            let hop = CGFloat(max(0, sin(t * 9)))
            return (hop * 0.8, 1, 1 + hop * 0.03, sin(t * 6) * 7)
        case .speaking:
            return (0, 1 + CGFloat(breathe) * 0.008, 1 + CGFloat(abs(sin(t * 8))) * 0.02, sin(t * 3) * 2)
        case .listening:
            return (0, 1, 1 + CGFloat(breathe) * 0.012, 6)
        case .working:
            return (0, 1, 1 + CGFloat(breathe) * 0.01, sin(t * 2.5) * 3)
        case .idle:
            return (0, 1 - CGFloat(breathe) * 0.006, 1 + CGFloat(breathe) * 0.014, sin(t * 0.8) * 1.2)
        }
    }
}
