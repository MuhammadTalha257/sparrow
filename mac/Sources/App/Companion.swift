import Foundation
import AppKit
import SwiftUI
import EventKit

// MARK: - Notifications

extension Notification.Name {
    /// Something short the pet should say in its speech bubble (object: String)
    static let petSay = Notification.Name("sparrow.petSay")
}

// =====================================================================
// MARK: - Pet mode: the bunny walks out and sits anywhere on screen
// =====================================================================

@MainActor
final class PetModel: ObservableObject {
    let sprite = SparrowSpriteModel()
    /// Something the sparrow carries (SF Symbol): water bottle, coffee cup, pills.
    @Published var prop: String?
    /// Water / coffee / medicine waiting for "Take" or "Later".
    @Published var asking: (kind: String, text: String)?
    @Published var angry = false
    @Published var bubble: String?
    @Published var flying = false
    /// Walking on its feet (in, out, or a little stroll along the bottom of the screen).
    @Published var walking = false
    @Published var walkLeft = false
    /// Paw up — pointing at what it is about to click for you.
    @Published var reaching = false
    @Published var hovering = false
    private var hideBubble: DispatchWorkItem?

    func say(_ text: String, for seconds: Double = 6) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        bubble = clean.count > 140 ? String(clean.prefix(137)) + "…" : clean
        hideBubble?.cancel()
        let w = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.bubble = nil } }
        hideBubble = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }
}

/// Hosting view that reacts to the first click even though the panel never becomes active.
final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PetController {
    static let shared = PetController()
    let model = PetModel()
    private var panel: NSPanel?
    private let size = NSSize(width: 230, height: 330)

    var isShown: Bool { panel?.isVisible == true }

    private init() {
        NotificationCenter.default.addObserver(forName: .petSay, object: nil, queue: .main) { note in
            let text = note.object as? String
            MainActor.assumeIsolated {
                if let text, PetController.shared.isShown { PetController.shared.model.say(text) }
            }
        }
    }

    func toggle() { isShown ? hide() : show() }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isMovable = false
        let host = FirstMouseHostingView(rootView: PetView(model: model))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host
        return p
    }

    /// Where the pet sits: last place the person dropped it, or the bottom-right corner.
    private func homeFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let ud = UserDefaults.standard
        if ud.object(forKey: "petX") != nil {
            let pt = NSPoint(x: ud.double(forKey: "petX"), y: ud.double(forKey: "petY"))
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -40, dy: -40).contains(NSPoint(x: pt.x + size.width / 2, y: pt.y + 40)) }) {
                return NSRect(origin: pt, size: size)
            }
        }
        return NSRect(x: vf.maxX - size.width - 8, y: vf.minY + 8, width: size.width, height: size.height)
    }

    func savePosition() {
        guard let f = panel?.frame else { return }
        UserDefaults.standard.set(f.origin.x, forKey: "petX")
        UserDefaults.standard.set(f.origin.y, forKey: "petY")
    }

    func show(greeting: Bool = true) {
        let p = panel ?? makePanel()
        panel = p
        if greeting { UserDefaults.standard.set(true, forKey: "petVisible") }
        let target = homeFrame()
        guard !p.isVisible else { p.setFrame(target, display: true); return }
        // Hop in from the nearest side of the screen, walking on its feet, and stop on the spot
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let fromLeft = target.midX < screen.frame.midX
        let start = NSRect(x: fromLeft ? screen.frame.minX - size.width : screen.frame.maxX, y: target.minY, width: size.width, height: size.height)
        p.setFrame(start, display: false)
        p.alphaValue = 1
        p.orderFrontRegardless()
        SoundEngine.shared.play("greet")
        walk(p, to: target) {
            let m = PetController.shared.model
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            if m.prop == nil {
                let name = AssistantPrefs.displayName
                m.say("Hey\(name.isEmpty ? "" : " \(name)")! Tap me to talk. Drag me anywhere. 🐰", for: 5)
            }
        }
        startStrolling()
    }

    /// Walks the panel to `target` at a gentle bunny pace, legs stepping the whole way.
    private func walk(_ p: NSPanel, to target: NSRect, then done: @escaping @MainActor () -> Void = {}) {
        let dist = hypot(target.minX - p.frame.minX, target.minY - p.frame.minY)
        model.walkLeft = target.minX < p.frame.minX
        model.walking = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = max(1.5, min(12, Double(dist) / 112))
            ctx.timingFunction = CAMediaTimingFunction(name: .linear)
            p.animator().setFrame(target, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                PetController.shared.model.walking = false
                done()
            }
        })
    }

    /// Every few minutes the bunny strolls a little way along the screen (unless it's busy).
    private var strollTimer: Timer?
    private func startStrolling() {
        strollTimer?.invalidate()
        strollTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 240...420), repeats: false) { _ in
            MainActor.assumeIsolated { PetController.shared.stroll() }
        }
    }
    func stroll() {
        defer { startStrolling() }
        guard let p = panel, p.isVisible, !model.walking, !model.flying, model.asking == nil, !model.hovering,
              UserDefaults.standard.object(forKey: "petStroll") as? Bool ?? true else { return }
        let vf = (p.screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let dx = CGFloat.random(in: 120...320) * (Bool.random() ? 1 : -1)
        var x = p.frame.minX + dx
        if x < vf.minX + 8 || x + size.width > vf.maxX - 8 { x = p.frame.minX - dx }
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        walk(p, to: NSRect(x: x, y: p.frame.minY, width: size.width, height: size.height)) {
            PetController.shared.savePosition()
            PetController.shared.model.sprite.react(8, for: 0.8)
        }
    }

    func hide(remember: Bool = true) {
        if remember { UserDefaults.standard.set(false, forKey: "petVisible") }
        guard let p = panel, p.isVisible else { return }
        strollTimer?.invalidate()
        let f = p.frame
        let screen = p.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let toLeft = f.midX < screen.frame.midX
        let away = NSRect(x: toLeft ? screen.frame.minX - f.width - 10 : screen.frame.maxX + 10, y: f.minY, width: f.width, height: f.height)
        walk(p, to: away) { PetController.shared.panel?.orderOut(nil) }
    }

    /// Water / coffee / medicine time: the sparrow flies in carrying it and asks "Take" or "Later".
    /// Take → happy, flies back. Later → cross, flies back, and asks again in 10 minutes.
    private var wasShownBeforeAsk = false
    private var askTimeout: DispatchWorkItem?
    func deliver(kind: String, text: String) {
        // Water / coffee / medicine: Zuffi walks across the screen carrying it.
        ZuffiWalk.shared.arrive(kind: kind, title: text)
    }

    func answer(take: Bool, quiet: Bool = false) {
        guard let ask = model.asking else { return }
        askTimeout?.cancel()
        model.asking = nil
        if take {
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
            SoundEngine.shared.play("approve")
            model.say(ask.kind == "meds" ? "Well done! 💗" : ask.kind == "coffee" ? "Enjoy your coffee! ☕💗" : "Yay! Stay fresh 💗", for: 2)
        } else {
            if !quiet {
                model.angry = true
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
                model.say("Hmph! 😤 I'll ask again in 10 minutes.", for: 2.2)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
                MainActor.assumeIsolated { PetController.shared.deliver(kind: ask.kind, text: ask.text) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (quiet ? 0 : 1.8)) {
            MainActor.assumeIsolated {
                let me = PetController.shared
                guard me.model.asking == nil else { return }
                me.model.prop = nil
                me.model.angry = false
                if !me.wasShownBeforeAsk { me.hide(remember: false) }
            }
        }
    }

    /// When Zuffi uses the mouse for you, the bunny hops over and "presses" the spot first,
    /// so you can see what it's doing. `p` is in screen points with the origin at the top-left (like CGEvent).
    func reach(_ p: CGPoint) async {
        guard UserDefaults.standard.object(forKey: "petShowsClicks") as? Bool ?? true else { return }
        if !isShown { show(greeting: false) ; try? await Task.sleep(nanoseconds: 700_000_000) }
        guard let panel else { return }
        let primaryH = NSScreen.screens.first?.frame.height ?? 900
        let target = NSPoint(x: p.x, y: primaryH - p.y)                      // to AppKit coordinates
        // stand just below-left of the spot, raised paw near it
        var origin = NSPoint(x: target.x - size.width / 2 - 48, y: target.y - size.height + 70)
        if let vf = (NSScreen.screens.first { $0.frame.contains(target) } ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, vf.minX - 40), vf.maxX - size.width + 40)
            origin.y = min(max(origin.y, vf.minY - 20), vf.maxY - size.height + 20)
        }
        model.walkLeft = origin.x < panel.frame.minX
        model.reaching = true
        panel.ignoresMouseEvents = true          // the click goes to your app, never to the bunny
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrameOrigin(origin)
        }
        try? await Task.sleep(nanoseconds: 520_000_000)
        model.sprite.react(4, for: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { MainActor.assumeIsolated {
            PetController.shared.model.reaching = false
            PetController.shared.panel?.ignoresMouseEvents = false
        } }
    }

    func moveBy(dx: CGFloat, dy: CGFloat) {
        guard let p = panel else { return }
        p.setFrameOrigin(NSPoint(x: p.frame.minX + dx, y: p.frame.minY + dy))
    }
}

/// Drag to move the pet; a click without moving = talk.
struct PetDragArea: NSViewRepresentable {
    var onClick: () -> Void

    final class V: NSView {
        var onClick: (() -> Void)?
        private var last = NSPoint.zero
        private var moved: CGFloat = 0
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { last = NSEvent.mouseLocation; moved = 0 }
        override func mouseDragged(with event: NSEvent) {
            let now = NSEvent.mouseLocation
            let dx = now.x - last.x, dy = now.y - last.y
            last = now
            moved += abs(dx) + abs(dy)
            MainActor.assumeIsolated { PetController.shared.moveBy(dx: dx, dy: dy) }
        }
        override func mouseUp(with event: NSEvent) {
            if moved < 4 { onClick?() } else { MainActor.assumeIsolated { PetController.shared.savePosition() } }
        }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }

    func makeNSView(context: Context) -> V { let v = V(); v.onClick = onClick; return v }
    func updateNSView(_ nsView: V, context: Context) { nsView.onClick = onClick }
}

struct PetView: View {
    @ObservedObject var model: PetModel
    @ObservedObject private var voice = VoiceEngine.shared
    @StateObject private var engine = BotEngine()
    @State private var clicks = 0
    @State private var lastClick = Date.distantPast

    var body: some View {
        VStack(spacing: 6) {
            Spacer(minLength: 0)
            // Speech bubble
            if let text = bubbleText {
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(Color(hex: "#2A1A10"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "#FFF6EA"))
                            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                    )
                    .frame(maxWidth: 210)
                    .transition(.scale(scale: 0.6, anchor: .bottom).combined(with: .opacity))
            }

            ZStack {
                // little perch shadow
                Ellipse().fill(Color.black.opacity(0.22))
                    .frame(width: 74, height: 10).blur(radius: 3).offset(y: 80)
                Group {
                    if ZuffiBodyArt.shared.available || ZuffiLook.shared.kind != .bunny {
                        // the whole bunny, always — walks on its feet, cups its ear when listening, waves on a click
                        ZuffiWalker(height: 168, walking: model.walking, facingLeft: model.walkLeft, pose: petPose)
                            .scaleEffect(x: model.sprite.squash.width, y: model.sprite.squash.height, anchor: .bottom)
                            .allowsHitTesting(false)
                    } else if SparrowSprites.shared.available {
                        SparrowSpriteView(model: model.sprite, size: 118, deadZone: 60, mood: BotCanvasView.mood(voice, AppState.shared))
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: 124, height: 172)
                .colorMultiply(model.angry ? Color(red: 1, green: 0.62, blue: 0.62) : .white)
                .modifier(Shake(amount: model.angry ? 4 : 0))
                if let prop = model.prop {
                    Image(systemName: prop)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(prop.contains("water") ? Color(hex: "#4FA7FF") : prop.contains("cup") ? Color(hex: "#9A6A48") : Color(hex: "#F06A8A"))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .rotationEffect(.degrees(-14))
                        .offset(x: 46, y: 30)
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                PetDragArea { petClicked() }
                    .frame(width: 96, height: 160)
            }
            .frame(width: 140, height: 176)
            .onHover { model.hovering = $0 }

            if model.asking != nil {
                HStack(spacing: 8) {
                    Button { PetController.shared.answer(take: true) } label: {
                        Label("Take", systemImage: "checkmark").font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color(hex: "#E2648A"))).foregroundColor(.white)
                    }.buttonStyle(.plain)
                    Button { PetController.shared.answer(take: false) } label: {
                        Label("Later", systemImage: "clock").font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Capsule().fill(Color.white)).foregroundColor(Color(hex: "#C94A74"))
                    }.buttonStyle(.plain)
                }
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .transition(.scale.combined(with: .opacity))
            }
            // Quick actions on hover
            HStack(spacing: 6) {
                petButton("mic.fill", "Talk") { petClicked() }
                petButton("sun.max.fill", "Today") { TodayWindow.shared.show() }
                petButton("cursorarrow.click.2", "Do something on screen") { ZuffiChat.shared.open(prefill: "On screen, ") }
                petButton("bubble.left.fill", "Chat") {
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
                }
                petButton("xmark", "Hide") { PetController.shared.hide() }
            }
            .opacity(model.hovering && !model.flying && !model.walking && model.asking == nil ? 1 : 0)
            .animation(.easeOut(duration: 0.15), value: model.hovering)
            .onHover { if $0 { model.hovering = true } }
        }
        .frame(width: 230, height: 330)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: bubbleText)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.prop)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.asking == nil)
        .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { n in
            if let e = n.object as? BotEmote { engine.triggerEmote(e, silent: true) }
        }
        .onAppear { engine.setState(.idle, force: true) }
    }

    @State private var waveUntil = Date.distantPast
    private var petPose: ZuffiPose {
        if voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) { return .listen }
        if model.reaching { return .listen }
        if Date() < waveUntil || voice.speaking { return .wave }
        if AppState.shared.stateOverride == .thinking { return .think }
        return .stand
    }

    private var bubbleText: String? {
        if voice.isListening && voice.status == "Listening…" {
            return voice.heard.isEmpty ? "Listening… 👂" : "“\(voice.heard)”"
        }
        return model.bubble
    }

    private func petClicked() {
        // A little reaction on every click (four quick clicks = a bit cross), then listen.
        let now = Date()
        clicks = now.timeIntervalSince(lastClick) < 1.6 ? clicks + 1 : 1
        lastClick = now
        let e: BotEmote = clicks >= 4 ? .annoyed : [.love, .happy, .proud, .wink][(clicks - 1) % 4]
        if clicks >= 4 { clicks = 0 }
        NotificationCenter.default.post(name: .triggerEmote, object: e)
        model.sprite.boop()
        waveUntil = Date().addingTimeInterval(1.6)
        if model.asking == nil { VoiceEngine.shared.listenOnce() }
    }

    private func petButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "#2A1A10"))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(hex: "#FFF6EA")).shadow(color: .black.opacity(0.25), radius: 3, y: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// =====================================================================
// MARK: - Today window: see and manage meetings, reminders and tasks
// =====================================================================

extension Planner {
    struct RItem: Identifiable, Sendable { let id: String; let title: String; let due: Date?; let done: Bool }
    struct EItem: Identifiable, Sendable { let id: String; let title: String; let start: Date; let end: Date; let allDay: Bool; let color: String }

    func ensureAccess() async -> (calendar: Bool, reminders: Bool) {
        let c: Bool
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { c = true }
        else { c = await Planner.askEvents() }        // asked off the main thread: the permission reply arrives on a background queue
        let r: Bool
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { r = true }
        else { r = await Planner.askReminders() }
        return (c, r)
    }

    nonisolated static func openReminderItems() async -> [RItem] {
        await withCheckedContinuation { cont in
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: pred) { list in
                let items = (list ?? []).map { r in
                    RItem(id: r.calendarItemIdentifier, title: r.title ?? "",
                          due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }, done: r.isCompleted)
                }
                cont.resume(returning: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }

    func setDone(_ id: String, _ done: Bool) -> Bool {
        guard let r = Planner.store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        r.isCompleted = done
        do { try Planner.store.save(r, commit: true); return true } catch { return false }
    }

    func deleteReminder(_ id: String) -> Bool {
        guard let r = Planner.store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        do { try Planner.store.remove(r, commit: true); return true } catch { return false }
    }

    func deleteEvent(_ id: String) -> Bool {
        guard let e = Planner.store.event(withIdentifier: id) else { return false }
        do { try Planner.store.remove(e, span: .thisEvent, commit: true); return true } catch { return false }
    }

    func eventItems(from day: Date, days: Int) -> [EItem] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let start = Calendar.current.startOfDay(for: day)
        guard let end = Calendar.current.date(byAdding: .day, value: days, to: start) else { return [] }
        let pred = Planner.store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return Planner.store.events(matching: pred).map { e in
            EItem(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "Event", start: e.startDate, end: e.endDate,
                  allDay: e.isAllDay, color: Self.hex(e.calendar?.cgColor))
        }.sorted { $0.start < $1.start }
    }

    private static func hex(_ c: CGColor?) -> String {
        guard let c, let comps = c.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components,
              comps.count >= 3 else { return "#F9A830" }
        return String(format: "#%02X%02X%02X", Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
    }

    /// Anything typed in the Today window: understood as a meeting / reminder / note,
    /// otherwise saved as a task.
    func quickAdd(_ text: String) async -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        if let r = await handle(t) { return r }
        return await handle("add task " + t) ?? "Couldn't add that."
    }
}

@MainActor
final class TodayModel: ObservableObject {
    @Published var events: [Planner.EItem] = []
    @Published var week: [Planner.EItem] = []
    @Published var tasks: [Planner.RItem] = []
    @Published var access = (calendar: true, reminders: true)
    @Published var message = ""

    func refresh() async {
        access = await Planner.shared.ensureAccess()
        events = Planner.shared.eventItems(from: Date(), days: 1)
        week = Planner.shared.eventItems(from: Date(), days: 7)
        tasks = access.reminders ? await Planner.openReminderItems() : []
    }
}

@MainActor
final class TodayWindow {
    static let shared = TodayWindow()
    private var window: NSWindow?

    func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.post(name: .todayRefresh, object: nil)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Today — Zuffi"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentMinSize = NSSize(width: 380, height: 420)
        w.contentView = NSHostingView(rootView: TodayView())
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Notification.Name { static let todayRefresh = Notification.Name("sparrow.todayRefresh") }

struct TodayView: View {
    @StateObject private var model = TodayModel()
    @State private var tab = 0
    @State private var input = ""
    @State private var busy = false

    private let amber = Color(hex: "#F9A830")
    private let sunset = Color(hex: "#F28A3C")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.system(size: 24, weight: .bold, design: .rounded))
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13)).foregroundColor(.secondary)
                Text(summary).font(.system(size: 13)).padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 12)

            if let next = upNext {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), sunset], startPoint: .top, endPoint: .bottom))
                        Image(systemName: next.icon).font(.system(size: 15, weight: .bold)).foregroundColor(Color(hex: "#1A1008"))
                    }
                    .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("UP NEXT").font(.system(size: 9.5, weight: .heavy)).foregroundColor(sunset)
                        Text(next.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    }
                    Spacer()
                    Text(next.date, style: .relative).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 110, alignment: .trailing)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16).fill(sunset.opacity(0.12)))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(amber.opacity(0.3), lineWidth: 1))
                .padding(.horizontal, 20).padding(.bottom, 12)
            }

            // Add anything
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").foregroundColor(sunset).font(.system(size: 18))
                TextField("Add anything — “meeting with Ali Fri 3pm”, “remind me…”, “buy milk”", text: $input)
                    .textFieldStyle(.plain)
                    .onSubmit { add() }
                if busy { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(amber.opacity(0.35), lineWidth: 1))
            .padding(.horizontal, 20)
            if !model.message.isEmpty {
                Text(model.message).font(.system(size: 11.5)).foregroundColor(.secondary)
                    .padding(.horizontal, 24).padding(.top, 6)
            }

            Picker("", selection: $tab) {
                Text("Today").tag(0); Text("Tasks").tag(1); Text("This week").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 20).padding(.vertical, 12)

            if !model.access.calendar || !model.access.reminders {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zuffi needs permission to show your Calendar and Reminders.")
                        .font(.system(size: 12.5))
                    Button("Open Privacy settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
                .padding(.horizontal, 20)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    switch tab {
                    case 0: todayList
                    case 1: taskList(model.tasks)
                    default: weekList
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 16)
            }

            Divider()
            HStack(spacing: 14) {
                footerButton("calendar", "Calendar", "com.apple.iCal")
                footerButton("checklist", "Reminders", "com.apple.reminders")
                footerButton("note.text", "Notes", "com.apple.Notes")
                Spacer()
                Button { Task { await Routine.shared.nightCheckIn() } } label: {
                    Label("Check-in", systemImage: "moon.stars").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundColor(.secondary).help("Evening check-in: tick what's done, move the rest")
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundColor(.secondary).help("Refresh")
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
        }
        .frame(minWidth: 380, minHeight: 420)
        .background(
            ZStack {
                VisualEffectBlur()
                LinearGradient(colors: [sunset.opacity(0.22), amber.opacity(0.05), .clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .task { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .todayRefresh)) { _ in Task { await model.refresh() } }
    }

    // MARK: Lists

    private var todayList: some View {
        let cal = Calendar.current
        let dueToday = model.tasks.filter { t in t.due.map { cal.isDateInToday($0) || $0 < Date() } ?? false }
        return Group {
            if model.events.isEmpty && dueToday.isEmpty {
                empty("Nothing planned today 🌤️", "Type above, or say “Zuffi, meeting with Ali at 3pm”.")
            }
            if !model.events.isEmpty { sectionTitle("Meetings") }
            ForEach(model.events) { e in eventRow(e, showDay: false) }
            if !dueToday.isEmpty { sectionTitle("Due today") }
            ForEach(dueToday) { t in taskRow(t) }
        }
    }

    private func taskList(_ items: [Planner.RItem]) -> some View {
        Group {
            if items.isEmpty { empty("No open tasks 🎉", "Add one above, e.g. “buy milk tomorrow”.") }
            ForEach(items) { t in taskRow(t) }
        }
    }

    private var weekList: some View {
        let cal = Calendar.current
        let days = Dictionary(grouping: model.week) { cal.startOfDay(for: $0.start) }.keys.sorted()
        return Group {
            if model.week.isEmpty { empty("Your week is clear", "Meetings you add appear here.") }
            ForEach(days, id: \.self) { d in
                sectionTitle(cal.isDateInToday(d) ? "Today" : cal.isDateInTomorrow(d) ? "Tomorrow" : d.formatted(.dateTime.weekday(.wide).day().month()))
                ForEach(model.week.filter { cal.isDate($0.start, inSameDayAs: d) }) { e in eventRow(e, showDay: false) }
            }
        }
    }

    // MARK: Rows

    private func eventRow(_ e: Planner.EItem, showDay: Bool) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: e.color)).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(e.allDay ? "All day" : "\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 11.5)).foregroundColor(.secondary)
            }
            Spacer()
            Button { if Planner.shared.deleteEvent(e.id) { Task { await model.refresh() } } } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundColor(.secondary).help("Delete")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func taskRow(_ t: Planner.RItem) -> some View {
        HStack(spacing: 10) {
            Button {
                if Planner.shared.setDone(t.id, true) {
                    SoundEngine.shared.play("finish")
                    Task { try? await Task.sleep(nanoseconds: 250_000_000); await model.refresh() }
                }
            } label: {
                Image(systemName: "circle").font(.system(size: 17)).foregroundColor(sunset)
            }
            .buttonStyle(.plain).help("Mark as done")
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                if let d = t.due {
                    Text(dueLabel(d)).font(.system(size: 11.5))
                        .foregroundColor(d < Date() ? .red : .secondary)
                }
            }
            Spacer()
            Button { if Planner.shared.deleteReminder(t.id) { Task { await model.refresh() } } } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.plain).foregroundColor(.secondary).help("Delete")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10.5, weight: .bold)).foregroundColor(sunset)
            .padding(.top, 10).padding(.leading, 2)
    }

    private func empty(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(sub).font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 30)
    }

    private func footerButton(_ icon: String, _ title: String, _ bundle: String) -> some View {
        Button {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
        } label: { Label(title, systemImage: icon).font(.system(size: 12)) }
        .buttonStyle(.plain).foregroundColor(.secondary)
    }

    // MARK: Helpers

    private var greeting: String {
        let name = AssistantPrefs.displayName
        let h = Calendar.current.component(.hour, from: Date())
        let hello = h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
        return name.isEmpty ? hello : "\(hello), \(name)"
    }

    private var upNext: (title: String, date: Date, icon: String)? {
        let now = Date()
        let e = model.events.filter { !$0.allDay && $0.start > now }.first
        let t = model.tasks.filter { ($0.due ?? .distantPast) > now }.first
        switch (e, t) {
        case let (e?, t?): return e.start <= t.due! ? (e.title, e.start, "calendar") : (t.title, t.due!, "bell.fill")
        case let (e?, nil): return (e.title, e.start, "calendar")
        case let (nil, t?): return (t.title, t.due!, "bell.fill")
        default: return nil
        }
    }

    private var summary: String {
        let m = model.events.count, t = model.tasks.count
        if m == 0 && t == 0 { return "Your day is clear." }
        var parts: [String] = []
        if m > 0 { parts.append("\(m) meeting\(m == 1 ? "" : "s") today") }
        if t > 0 { parts.append("\(t) open task\(t == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private func dueLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "Today, \(time)" }
        if cal.isDateInTomorrow(d) { return "Tomorrow, \(time)" }
        if d < Date() { return "Overdue · " + d.formatted(.dateTime.day().month()) }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month()) + ", " + time
    }

    private func add() {
        let text = input
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        input = ""; busy = true
        Task {
            let r = await Planner.shared.quickAdd(text)
            model.message = r
            busy = false
            await model.refresh()
        }
    }
}


/// A little side-to-side shake (the sparrow is cross).
struct Shake: ViewModifier {
    var amount: CGFloat
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .offset(x: amount == 0 ? 0 : (on ? amount : -amount))
            .animation(amount == 0 ? .default : .linear(duration: 0.07).repeatCount(12, autoreverses: true), value: on)
            .onChange(of: amount) { _, v in on = v != 0 }
    }
}
