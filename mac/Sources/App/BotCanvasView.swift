import SwiftUI

/// SwiftUI wrapper: TimelineView drives a Canvas that calls BotEngine.draw().
/// Uses a shared engine per-task; the main bot uses AppState's shared engine.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0

    // One engine per view instance (main bot)
    @StateObject private var engine = BotEngine()
    @ObservedObject private var voice = VoiceEngine.shared

    @StateObject private var sprite = SparrowSpriteModel()

    /// Zuffi's mood from what's happening: listening, thinking, speaking.
    static func mood(_ voice: VoiceEngine, _ state: AppState) -> SpriteMood {
        if voice.speaking || LiveSession.shared.speakingNow { return .speaking }
        if voice.status.hasPrefix("Listening") || LiveSession.shared.listeningNow { return .listening }
        if [.thinking, .working, .searching].contains(state.effectiveState) || LiveSession.shared.workingNow { return .thinking }
        return .idle
    }

    var body: some View {
        // The bunny everywhere — except the file-drop "mailbox" animation, which is drawn.
        if SparrowSprites.shared.available, state.view != .upload, state.view != .uploading, state.mode != .hidden {
            GeometryReader { g in
                SparrowSpriteView(model: sprite, size: min(g.size.width, g.size.height - particleOverhang),
                                  deadZone: 40, mood: Self.mood(voice, state))
                    .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                    .allowsHitTesting(false)          // the island watches clicks itself and sends a "slap"
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in sprite.boop() }
        } else {
            drawnBird
        }
    }

    private var drawnBird: some View {
        TimelineView(.animation(paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let dtRaw = min(0.05, now - engine.lastTime)
                let dt = dtRaw
                engine.lookX = lookX(state: state, size: size)
                engine.lookY = lookY(state: state, size: size)
                engine.particleOverhang = particleOverhang
                // Widen slot when file is hovering over the mailbox (morph > 0.5)
                // Open mouth (hover=0.20R) when file dragged over box; close when not
                if engine.morph > 0.3 {
                    engine.slotHTarget = state.fileDragOver ? 0.20 : 0
                } else {
                    engine.slotHTarget = 0
                    if engine.morph < 0.05 { engine.slotH = 0; engine.slotHVel = 0 }
                }
                // Always Zuffi's own colours (like the pet).
                engine.bodyColor = nil
                engine.update(dt: dt)
                // Wings, like the pet: fast while flying in, flapping while listening to you, tucked otherwise
                if now < SparrowFlight.until { engine.hands = 0.65 + 0.35 * CGFloat(sin(now * 38)) }
                else if voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) {
                    engine.hands = 0.35 + 0.25 * CGFloat(sin(now * 18)) + CGFloat(voice.level) * 0.3
                } else if engine.hands > 0.01 && now > engine.waveUntil { engine.hands *= 0.85 }
                engine.drawHandsBehind(context: context, size: size)
                engine.draw(context: context, size: size)
                engine.drawHandsAndExtras(context: context, size: size)
            }
        }
        .onChange(of: state.effectiveState) { _, newState in
            engine.setState(newState)
        }
        .onChange(of: state.view) { _, newView in
            // Morph up when upload view is active
            if state.mode == .expanded && newView == .upload {
                engine.anim("morph", keys: [TweenKey(target: 1, duration: 550, ease: Ease.inOut)])
            } else if newView != .upload && newView != .uploading && engine.morph > 0.01 {
                // Any other view (not mid-gulp): morph back
                engine.anim("morph", keys: [TweenKey(target: 0, duration: 550, ease: Ease.inOut)])
            }
        }
        .onChange(of: state.mode) { _, newMode in
            // Hard-reset morph when island collapses
            if newMode != .expanded {
                engine.tweens.removeValue(forKey: "morph")
                engine.locks.remove("morph")
                engine.morph = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
            if let emote = notif.object as? BotEmote {
                engine.triggerEmote(emote)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
            engine.slap()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
            engine.blink()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
            if let v = notif.object as? CGFloat {
                engine.tgEs = v
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in
            engine.gulp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .botMorphTo)) { notif in
            if let target = notif.object as? CGFloat {
                let dur: CGFloat = target > 0.5 ? 550 : 650
                engine.anim("morph", keys: [TweenKey(target: target, duration: dur, ease: Ease.inOut)])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            engine.greet()
        }
        .onAppear {
            engine.setState(state.effectiveState, force: true)
        }
    }

    private func lookX(state: AppState, size: CGSize) -> CGFloat {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let (botCx, _, _, _) = botPosition(mode: state.mode, view: state.view,
                                            islandW: islandW, islandH: islandH,
                                            uploadProgress: state.uploadProgress)
        // Island is centered on screen; bot is at botCx within island coords
        let botScreenX = screen.frame.midX - islandW / 2 + botCx
        return tanh((state.mousePosition.x - botScreenX) / 260)
    }

    private func lookY(state: AppState, size: CGSize) -> CGFloat {
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? IslandConst.chatHeight
            : islandH
        let (_, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                             islandW: islandW, islandH: actualH,
                                             uploadProgress: state.uploadProgress)
        // Island top = screen top → bot screen Y = botCy from island top
        return -tanh((state.mousePosition.y - botCy) / 200)
    }
}

/// Mini bot canvas (for agent pills/column)
struct MiniBotCanvasView: View {
    let task: AgentTask
    @StateObject private var engine: BotEngine

    init(task: AgentTask) {
        self.task = task
        _engine = StateObject(wrappedValue: {
            let e = BotEngine()
            e.isMini = true
            e.bodyColor = cgColorFromHex(task.color)
            return e
        }())
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let dt = min(0.05, now - engine.lastTime)
                engine.update(dt: dt)
                engine.draw(context: context, size: size)
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onAppear {
            engine.setState(task.state, force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
            }
            // Direct eye override takes priority (e.g. .wide eyes for Research)
            if let eye = task.miniEye {
                engine.permanentEye = eye
                engine.eyeOverride = eye
                engine.eyeOverrideUntil = .greatestFiniteMagnitude
            }
        }
    }
}

// MARK: - CGColor from hex string

func cgColorFromHex(_ hex: String) -> CGColor? {
    let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    guard let val = UInt64(h, radix: 16) else { return nil }
    let r = CGFloat((val >> 16) & 0xFF) / 255
    let g = CGFloat((val >> 8)  & 0xFF) / 255
    let b = CGFloat( val        & 0xFF) / 255
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

extension CGColor {
    static func from(_ hex: String) -> CGColor {
        cgColorFromHex(hex) ?? CGColor(gray: 0.5, alpha: 1)
    }
}


/// When the sparrow is flying (e.g. arriving when Zuffi opens), its wings flap fast.
enum SparrowFlight {
    nonisolated(unsafe) static var until: Double = 0
    static func fly(for seconds: Double) { until = Date().timeIntervalSinceReferenceDate + seconds }
}

/// A little sparrow (same character as the big one) in any colour — used on app tiles and the header.
/// The little Zuffi logo (bunny face) used in the header, app tiles and cards.
struct LittleSparrow: View {
    let color: String?
    var size: CGFloat = 26
    @State private var bump = false

    init(color: String?, size: CGFloat = 26) {
        self.color = color
        self.size = size
    }

    var body: some View {
        let sprites = SparrowSprites.shared
        ZuffiFace(frame: sprites.available ? sprites.directions[4] : nil, size: size * 1.25)
            .frame(width: size, height: size)
            .scaleEffect(bump ? 1.2 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: bump)
            .onReceive(NotificationCenter.default.publisher(for: .littleSparrowReact)) { n in
                if (n.object as? String) == color { bump = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { bump = false } }
            }
    }
}

extension Notification.Name { static let littleSparrowReact = Notification.Name("sparrow.littleReact") }
