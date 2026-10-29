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
    /// A short tip when you say "Not yet".
    @Published var tip: String?
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
    private let size = NSSize(width: 380, height: 470)

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

    private var petWasShown = false
    private func next() {
        guard !queue.isEmpty else {
            current = nil
            // the visit is over: the desktop pet comes back
            if petWasShown { petWasShown = false; PetController.shared.show(greeting: false) }
            return
        }
        let v = queue.removeFirst()
        current = v
        // only ONE Aurora on screen: the desktop pet steps away while she brings the reminder
        if PetController.shared.isShown { petWasShown = true; PetController.shared.hide(remember: false) }
        let m = model
        m.answered = false; m.cross = false; m.bubble = nil; m.danceStart = nil; m.tip = nil
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
        m.later = "Not yet"
        m.emoji = ["water": "💧", "coffee": "☕", "meds": "💊", "meeting": "📅", "task": "✅", "prayer": "🌙", "birthday": "🎂"][v.kind] ?? "⏰"

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let p = panel ?? makePanel()
        panel = p
        // she comes to the front: the middle of your screen (a little low, so she doesn't cover what you're reading)
        let y = Self.walkY(vf, size)
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
            BunnyFaceCenter.shared.show(.love, for: 3)
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
                model.bubble = "Hmph! I'll be back in 10 min."
                model.tip = Self.tip(for: v.kind, title: v.title)
                BunnyFaceCenter.shared.show(.cross, for: 4)
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
        DispatchQueue.main.asyncAfter(deadline: .now() + (quiet ? 0.1 : yes ? 2.6 : 3.6)) {
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

    static func walkY(_ vf: NSRect, _ size: NSSize) -> CGFloat {
        vf.minY + max(6, (vf.height - size.height) * 0.32)
    }

    /// A short, kind tip for "Not yet" — practical, never preachy.
    static func tip(for kind: String, title: String) -> String {
        switch kind {
        case "water": return "A few sips now keeps tiredness and headaches away."
        case "coffee": return "Have it before 3pm so it doesn't spoil your sleep."
        case "meds": return "Taking it on time keeps it working properly."
        case "meeting": return "Leave a couple of minutes early so you're not rushed."
        case "prayer": return "Even a short pause now will help you reset."
        default: return "Just do the first two minutes of it. Starting is the hardest part."
        }
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
        if Aurora3DPrefs.on {
            Walk3DView(model: model)
        } else {
            classic
        }
    }

    private var classic: some View {
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
                        if ZuffiLook.shared.kind == .bunny, Buddy3DPrefs.on {
                            AuroraBunnyView(height: 150, mood: model.walking ? .walking : (model.answered && !model.cross ? .happy : .idle),
                                            walkLeft: model.sprite.walkLeft, followMouse: !model.walking)
                                .frame(width: 170, height: 180)
                        } else if ZuffiBodyArt.shared.available || ZuffiLook.shared.kind != .bunny {
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
        .frame(width: 380, height: 470)
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

/// The 3D Aurora brings a reminder: she stands on her back legs and holds it up. Done → she cheers. Not yet → she gets cross,
/// gives you a tip, and says she'll be back in 10 minutes.
struct Walk3DView: View {
    @ObservedObject var model: WalkModel
    private let ink = Color(hex: "#1B1A18")

    private var pose: AuroraPose {
        if model.walking { return .hop }
        if model.cross { return .cross }
        if model.answered { return .happy }
        return .hold
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            // what she says
            if let b = model.bubble {
                SpeechBubble(fill: model.tip != nil ? Color(hex: "#C2483F") : Color(hex: "#2E9D6A"), border: .clear) {
                    Text(b).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                }
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            } else if !model.walking {
                SpeechBubble(fill: ink, border: .clear) {
                    Text("Hey! Don't forget this").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                }
                .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
            ZStack(alignment: .bottom) {
                RealAurora(width: 112, mood: model.cross ? "oops" : model.answered ? "done" : "idle", speaking: VoiceEngine.shared.speaking, lookAtMouse: !model.walking, walking: model.walking)
                    .frame(width: 230, height: 250, alignment: .bottom)
                    .allowsHitTesting(false)
                if let d = model.danceStart, model.answered, !model.cross {
                    TimelineView(.animation) { tl in JoyBurst(elapsed: tl.date.timeIntervalSince(d)) }.offset(y: -90).allowsHitTesting(false)
                }
                // the card she holds in her front paws
                if !model.walking {
                    card
                        .offset(y: -18)
                        .transition(.scale(scale: 0.6, anchor: .top).combined(with: .opacity))
                }
            }
            .frame(height: 300, alignment: .bottom)
        }
        .frame(width: 380, height: 470)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: model.walking)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.bubble)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.answered)
    }

    @ViewBuilder private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let tip = model.tip {
                Text("ZUFFI'S TIP").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8).foregroundColor(Color(hex: "#8A6A2F"))
                Text(tip).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(ink).fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: model.tint)).frame(width: 7, height: 7)
                    Text("REMINDER").font(.system(size: 10, weight: .heavy, design: .rounded)).tracking(0.8).foregroundColor(Color(hex: "#8A6A2F"))
                }
                Text("\(model.title) \(model.emoji)").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(ink)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !model.sub.isEmpty { Text(model.sub).font(.system(size: 12)).foregroundColor(Color(hex: "#5F5A52")).lineLimit(1) }
                if !model.answered {
                    HStack(spacing: 8) {
                        Button { ZuffiWalk.shared.answer(yes: true) } label: {
                            Text(model.yes).font(.system(size: 13, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ink)).foregroundColor(.white)
                        }.buttonStyle(.plain)
                        Button { ZuffiWalk.shared.answer(yes: false) } label: {
                            Text(model.later).font(.system(size: 13, weight: .bold, design: .rounded)).frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "#F1EEE8"))).foregroundColor(ink)
                        }.buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .rotationEffect(.degrees(-1.5))
    }
}
