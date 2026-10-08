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

    func arrive(kind: String, title: String, sub: String = "", itemId: String? = nil) {
        queue.append(Visit(kind: kind, title: title, sub: sub, itemId: itemId))
        if current == nil { next() }
    }

    private func next() {
        guard !queue.isEmpty else { current = nil; return }
        let v = queue.removeFirst()
        current = v
        let m = model
        m.answered = false; m.cross = false; m.bubble = nil
        m.title = v.title; m.sub = v.sub
        switch v.kind {
        case "water": m.icon = "waterbottle.fill"; m.tint = "#4FA7FF"; m.yes = "Take"; m.sprite.prop = "waterbottle.fill"
        case "coffee": m.icon = "cup.and.saucer.fill"; m.tint = "#9A6A48"; m.yes = "Take"; m.sprite.prop = "cup.and.saucer.fill"
        case "meds": m.icon = "pills.fill"; m.tint = "#F06A8A"; m.yes = "Take"; m.sprite.prop = "pills.fill"
        case "meeting": m.icon = "person.2.fill"; m.tint = "#8B5CF6"; m.yes = "Got it"; m.sprite.prop = nil
        case "task": m.icon = "checkmark.circle.fill"; m.tint = "#2E8A68"; m.yes = "Done"; m.sprite.prop = nil
        default: m.icon = "bell.fill"; m.tint = "#E2648A"; m.yes = "Done"; m.sprite.prop = nil
        }
        m.later = "Later"

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
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 3.0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
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
            model.bubble = ["water": "Yay! Stay fresh 💗", "coffee": "Enjoy! ☕", "meds": "Well done! 💊", "meeting": "Good luck! ✨"][v.kind] ?? "Done! ✨"
            SoundEngine.shared.play("approve")
            if let id = v.itemId { Task { _ = await WebHub.shared.callJS("return window.Sparrow.completeItem(id)", ["id": id]) } }
        } else {
            if !quiet {
                model.cross = true
                model.sprite.react(3, for: 1.6)                                // surprised "hmph"
                model.bubble = "Hmph! I'll come back in 10 minutes 😤"
            }
            if let id = v.itemId {
                Task { _ = await WebHub.shared.callJS("return window.Sparrow.snoozeItem(id, 10)", ["id": id]) }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
                    MainActor.assumeIsolated { ZuffiWalk.shared.arrive(kind: v.kind, title: v.title, sub: v.sub) }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (quiet ? 0.1 : 1.7)) {
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
            ctx.duration = 2.6
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
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

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if let b = model.bubble {
                Text(b).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(Color.white).shadow(color: .black.opacity(0.2), radius: 4, y: 2))
                    .foregroundColor(Color(hex: "#3A2330"))
                    .transition(.scale.combined(with: .opacity))
            } else {
                // The banner Zuffi carries
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: model.icon).font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                            .frame(width: 30, height: 30).background(Circle().fill(Color(hex: model.tint)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.title).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(2)
                            if !model.sub.isEmpty { Text(model.sub).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                    }
                    if !model.walking && !model.answered {
                        HStack(spacing: 8) {
                            Button { ZuffiWalk.shared.answer(yes: true) } label: {
                                Label(model.yes, systemImage: "checkmark").font(.system(size: 12, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(Capsule().fill(Color(hex: "#E2648A"))).foregroundColor(.white)
                            }.buttonStyle(.plain)
                            Button { ZuffiWalk.shared.answer(yes: false) } label: {
                                Label(model.later, systemImage: "clock").font(.system(size: 12, weight: .bold, design: .rounded))
                                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                                    .background(Capsule().fill(Color(hex: "#FBE3EB"))).foregroundColor(Color(hex: "#C94A74"))
                            }.buttonStyle(.plain)
                        }
                        .transition(.opacity)
                    }
                }
                .padding(12)
                .frame(width: 280)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(hex: model.tint).opacity(0.5), lineWidth: 1.5))
            }
            ZStack(alignment: .bottom) {
                Ellipse().fill(Color.black.opacity(0.18)).frame(width: 74, height: 10).blur(radius: 3).offset(y: 3)
                Group {
                    if model.sprite.reaction != nil || !ZuffiBodyArt.shared.available {
                        // a big reaction face when you answer
                        SparrowSpriteView(model: model.sprite, size: 130, mood: .idle)
                    } else {
                        // the whole bunny, walking on its feet
                        ZuffiWalker(height: 168, walking: model.walking, facingLeft: model.sprite.walkLeft)
                    }
                }
                .colorMultiply(model.cross ? Color(red: 1, green: 0.7, blue: 0.7) : .white)
                .modifier(Shake(amount: model.cross ? 4 : 0))
                .allowsHitTesting(false)
                if let prop = model.sprite.prop, model.sprite.reaction == nil {
                    Image(systemName: prop).font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(prop.contains("water") ? Color(hex: "#4FA7FF") : prop.contains("cup") ? Color(hex: "#9A6A48") : Color(hex: "#F06A8A"))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .rotationEffect(.degrees(-12))
                        .offset(x: model.sprite.walkLeft ? -40 : 40, y: -62)
                }
            }
            .frame(height: 172)
        }
        .frame(width: 360, height: 400)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.walking)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: model.bubble)
    }
}
