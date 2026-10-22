import SwiftUI
import AppKit

// =====================================================================
// MARK: - Zuffi walks across the screen with your reminders
//
// A meeting, task or reminder is due → the bunny hops in from the left edge carrying a
// banner ("Meeting with Ahmed · 10:00"). Water, coffee or medicine → it carries the bottle,
// cup or pills. You answer (Done / Take, or Later) → it reacts and hops out to the right.
// Several at once queue up politely, one after another.
// =====================================================================

@MainActor
final class WalkModel: ObservableObject {
    let sprite = SparrowSpriteModel()
    @Published var walking = false
    @Published var title = ""
    @Published var sub = ""
    @Published var icon = "bell.fill"
    @Published var tint = "#E2648A"
    @Published var yes = "Done"
    @Published var later = "Later"
    @Published var answered = false
    @Published var cross = false
    @Published var bubble: String?
    /// The little emoji at the end of the message (💧, 🌙, 📅…) — like the website.
    @Published var emoji = "⏰"
    /// When the happy dance started (nil = not dancing).
    @Published var danceStart: Date?
}

@MainActor
final class ZuffiWalk {
    static let shared = ZuffiWalk()

    struct Visit { let kind: String; let title: String; let sub: String; let itemId: String? }

    let model = WalkModel()
    private var panel: NSPanel?
    private var queue: [Visit] = []
    private var current: Visit?
    private var timeout: DispatchWorkItem?
    private let size = NSSize(width: 360, height: 400)

    /// Water, coffee and medicine: only one of each is ever waiting (they used to pile up while the Mac slept or you were away).
    private static let health: Set<String> = ["water", "coffee", "meds"]
    private var laterWork: [String: DispatchWorkItem] = [:]
    private func isHealth(_ v: Visit) -> Bool { v.itemId == nil && Self.health.contains(v.kind) }

    /// "Never show the pet on screen" / "the pet brings reminders" — some people don't want a bunny walking across their work.
    static var petNever: Bool { UserDefaults.standard.bool(forKey: "petNever") }
    static var petBringsReminders: Bool { !petNever && (UserDefaults.standard.object(forKey: "petReminders") as? Bool ?? true) }

    func arrive(kind: String, title: String, sub: String = "", itemId: String? = nil) {
        // Pet switched off for reminders → a quiet card at the notch instead.
        guard Self.petBringsReminders else {
            let emoji = ["water": "💧", "coffee": "☕️", "meds": "💊", "meeting": "📅", "prayer": "🌙", "task": "✅"][kind] ?? "⏰"
            AppState.shared.noteMessage = "\(emoji) \(title)\(sub.isEmpty ? "" : " · \(sub)")"
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
            SoundEngine.shared.play("chime")
            return
        }
        let v = Visit(kind: kind, title: title, sub: sub, itemId: itemId)
        if isHealth(v) {
            if let c = current, isHealth(c), c.kind == kind { return }          // already here with it
            queue.removeAll { isHealth($0) && $0.kind == kind }                // keep just the newest
            laterWork[kind]?.cancel(); laterWork[kind] = nil
        }
        queue.append(v)
        if current == nil { next() }
    }

    private func next() {
        guard !queue.isEmpty else { current = nil; return }
        let v = queue.removeFirst()
        current = v
        let m = model
        m.answered = false; m.cross = false; m.bubble = nil; m.danceStart = nil
        m.title = v.title; m.sub = v.sub
        switch v.kind {
        case "water": m.icon = "waterbottle.fill"; m.tint = "#4FA7FF"; m.yes = "Take"; m.sprite.prop = "waterbottle.fill"
        case "coffee": m.icon = "cup.and.saucer.fill"; m.tint = "#9A6A48"; m.yes = "Take"; m.sprite.prop = "cup.and.saucer.fill"
        case "meds": m.icon = "pills.fill"; m.tint = "#F06A8A"; m.yes = "Take"; m.sprite.prop = "pills.fill"
        case "meeting": m.icon = "person.2.fill"; m.tint = "#8B5CF6"; m.yes = "Got it"; m.sprite.prop = nil
        case "prayer": m.icon = "moon.stars.fill"; m.tint = "#2E8A68"; m.yes = "Thanks"; m.sprite.prop = nil
        case "task": m.icon = "checkmark.circle.fill"; m.tint = "#2E8A68"; m.yes = "Done"; m.sprite.prop = nil
        default: m.icon = "bell.fill"; m.tint = "#E2648A"; m.yes = "Done"; m.sprite.prop = nil
        }
        m.later = "Later"
        m.emoji = ["water": "💧", "coffee": "☕", "meds": "💊", "meeting": "📅", "task": "✅", "prayer": "🌙", "birthday": "🎂"][v.kind] ?? "⏰"

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let p = panel ?? makePanel()
        panel = p
        let y = vf.minY + 6
        p.setFrame(NSRect(x: vf.minX - size.width, y: y, width: size.width, height: size.height), display: false)
        p.alphaValue = 1
        p.orderFrontRegardless()
        m.sprite.walkLeft = false
        m.walking = true
        SoundEngine.shared.play("greet")
        let inDist = (vf.midX - size.width / 2) - (vf.minX - size.width)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = max(4, min(11, Double(inDist) / 112))        // a calm bunny stroll, not a dash
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            p.animator().setFrame(NSRect(x: vf.midX - size.width / 2, y: y, width: size.width, height: size.height), display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                let me = ZuffiWalk.shared
                me.model.walking = false
                me.model.sprite.react(1, for: 1.2)
            }
        })
        // No answer in 3 minutes → Later, quietly.
        timeout?.cancel()
        let w = DispatchWorkItem { MainActor.assumeIsolated { ZuffiWalk.shared.answer(yes: false, quiet: true) } }
        timeout = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 180, execute: w)
    }

    func answer(yes: Bool, quiet: Bool = false) {
        guard let v = current, !model.answered else { return }
        model.answered = true
        timeout?.cancel()
        if yes {
            model.sprite.react(v.kind == "meeting" ? 4 : 1, for: 1.6)       // starstruck / heart
            model.bubble = ["water": "Yay! Stay fresh 💗", "coffee": "Enjoy your coffee! ☕💗", "meds": "Well done! 💊💗", "meeting": "Good luck! 🍀", "prayer": "I’ll nudge you again at the next prayer 💗", "task": "Yay, done! 🎉"][v.kind] ?? "Done! ✨"
            model.danceStart = Date()        // the happy dance
            SoundEngine.shared.play("approve")
            if let id = v.itemId { Task { _ = await WebHub.shared.callJS("return window.Sparrow.completeItem(id)", ["id": id]) } }
            if isHealth(v) {
                // taken: forget any extra ones and start the timer again from now, so the next one comes after your interval
                queue.removeAll { isHealth($0) && $0.kind == v.kind }
                laterWork[v.kind]?.cancel(); laterWork[v.kind] = nil
                Task { _ = await WebHub.shared.callJS("return window.Sparrow.healthTaken(kind)", ["kind": v.kind]) }
            }
        } else {
            if !quiet {
                model.cross = true
                model.sprite.react(3, for: 1.6)                                // surprised "hmph"
                model.bubble = "Hmph! I'll come back in 10 minutes 😤"
            }
            if let id = v.itemId {
                Task { _ = await WebHub.shared.callJS("return window.Sparrow.snoozeItem(id, 10)", ["id": id]) }
            } else if !(quiet && isHealth(v)) && v.kind != "prayer" {   // prayers: the on-time one comes anyway
                // "Later" → back in 10 minutes (once). No answer at all → the next normal reminder comes on time instead.
                let w = DispatchWorkItem { MainActor.assumeIsolated { ZuffiWalk.shared.arrive(kind: v.kind, title: v.title, sub: v.sub) } }
                laterWork[v.kind]?.cancel(); laterWork[v.kind] = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 600, execute: w)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (quiet ? 0.1 : yes ? 2.4 : 1.7)) {
            MainActor.assumeIsolated { ZuffiWalk.shared.leave() }
        }
    }

    private func leave() {
        guard let p = panel else { next(); return }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        model.cross = false
        model.sprite.walkLeft = false
        model.walking = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = max(4, min(11, Double(vf.maxX + 10 - p.frame.minX) / 112))
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            p.animator().setFrame(NSRect(x: vf.maxX + 10, y: p.frame.minY, width: size.width, height: size.height), display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                let me = ZuffiWalk.shared
                me.panel?.orderOut(nil)
                me.model.walking = false
                me.model.sprite.prop = nil
                me.current = nil
                me.next()
            }
        })
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        let host = FirstMouseHostingView(rootView: WalkView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        return p
    }
}

struct WalkView: View {
    @ObservedObject var model: WalkModel
    @State private var pressed = false

    // Website look: a dark pill that says it, with the buttons inside; then a white reply bubble.
    private let ink = Color(hex: "#0C0C0C")

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if let b = model.bubble {
                SpeechBubble(fill: .white, border: Color.black.opacity(0.12)) {
                    Text(b).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(ink)
                        .multilineTextAlignment(.center).padding(.horizontal, 16).padding(.vertical, 10)
                }
                .frame(maxWidth: 300)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            } else if !model.walking {
                SpeechBubble(fill: ink, border: .clear) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(model.title) \(model.emoji)").font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#F5F5F5")).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            if !model.sub.isEmpty { Text(model.sub).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).lineLimit(1) }
                        }
                        if !model.answered {
                            Button { withAnimation(.easeOut(duration: 0.15)) { pressed = true }; ZuffiWalk.shared.answer(yes: true) } label: {
                                Text(model.yes).font(.system(size: 12, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Capsule().fill(pressed ? Color(hex: "#7EE2A8") : Color(hex: "#F5F5F5")))
                                    .foregroundColor(ink).scaleEffect(pressed ? 0.9 : 1)
                            }.buttonStyle(.plain)
                            Button { ZuffiWalk.shared.answer(yes: false) } label: {
                                Text(model.later).font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))
                                    .foregroundColor(.white.opacity(0.85))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
                }
                .frame(maxWidth: 330)
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
                .onAppear { pressed = false }
            }
            // The bunny: bobs while she walks, dances when you say yes
            TimelineView(.animation) { tl in
                let t: Double = tl.date.timeIntervalSinceReferenceDate
                let d: Double = model.danceStart.map { tl.date.timeIntervalSince($0) } ?? -1
                let dancing = d >= 0 && d < 2.2
                let k: Double = dancing ? d / 2.2 : 0
                let hopPhase: Double = dancing ? d * .pi * 2 / 0.55 : 0                       // a hop every 0.55 s
                let hop: Double = dancing ? abs(sin(hopPhase / 2)) * 40 * (1 - k * 0.35) : 0  // high, joyful hops
                let squash: Double = dancing ? max(0, cos(hopPhase / 2) * cos(hopPhase / 2) - 0.75) * 0.5 : 0
                let tilt: Double = dancing ? sin(hopPhase / 2 + .pi / 2) * 11 : 0             // wiggle side to side
                let spin: Double = dancing && d > 1.1 && d < 1.65 ? (d - 1.1) / 0.55 * 360 : 0   // a little twirl mid-dance
                let bob: Double = model.walking ? -pow(sin(t * .pi / 0.28), 2) * 6 : 0
                ZStack(alignment: .bottom) {
                    Ellipse().fill(Color.black.opacity(0.18)).frame(width: 74 * (1 - hop / 120), height: 10).blur(radius: 3).offset(y: 3)
                    Group {
                        if ZuffiBodyArt.shared.available || ZuffiLook.shared.kind != .bunny {
                            ZuffiWalker(height: 168, walking: model.walking, facingLeft: model.sprite.walkLeft,
                                        pose: model.answered && !model.cross ? .wave : .stand)
                        } else {
                            SparrowSpriteView(model: model.sprite, size: 130, mood: model.walking ? .walking : .idle)
                        }
                    }
                    .scaleEffect(x: 1 + squash, y: 1 - squash, anchor: .bottom)
                    .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0))
                    .rotationEffect(.degrees(tilt), anchor: .bottom)
                    .offset(y: -hop + bob)
                    .colorMultiply(model.cross ? Color(red: 1, green: 0.7, blue: 0.7) : .white)
                    .modifier(Shake(amount: model.cross ? 4 : 0))
                    .allowsHitTesting(false)
                    if dancing { JoyBurst(elapsed: d) }   // hearts and sparkles float up
                }
            }
            .frame(height: 230, alignment: .bottom)
        }
        .frame(width: 360, height: 400)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.walking)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.bubble)
    }
}

/// Hearts and sparkles floating up around the bunny while she dances.
struct JoyBurst: View {
    let elapsed: Double
    private static let marks = ["💗", "✨", "🌸", "💖", "⭐️", "💗", "🎉", "✨", "💕"]
    var body: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { i in
                let p: Double = progress(i)
                Text(Self.marks[i])
                    .font(.system(size: CGFloat(16 + (i % 3) * 4)))
                    .offset(x: xOffset(i, p), y: CGFloat(-60.0 - p * 150.0))
                    .opacity(p <= 0 ? 0 : 1 - p)
                    .scaleEffect(CGFloat(0.6 + p * 0.6))
            }
        }
    }
    private func progress(_ i: Int) -> Double { max(0, min(1, (elapsed - Double(i) * 0.16) / 1.3)) }
    private func xOffset(_ i: Int, _ p: Double) -> CGFloat {
        let side: Double = i % 2 == 0 ? -1 : 1
        let spread: Double = 28 + Double(i * 9 % 46)
        let sway: Double = sin(p * 6 + Double(i)) * 8
        return CGFloat(side * spread + sway)
    }
}

/// A rounded bubble with a little tail pointing down at the bunny.
struct SpeechBubble<Content: View>: View {
    let fill: Color
    let border: Color
    @ViewBuilder let content: Content
    var body: some View {
        content
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(border, lineWidth: 1))
            .overlay(alignment: .bottom) {
                BubbleTail().fill(fill).frame(width: 14, height: 8).offset(y: 7)
            }
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
    }
}
struct BubbleTail: Shape {
    func path(in r: CGRect) -> Path { var p = Path(); p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.closeSubpath(); return p }
}
