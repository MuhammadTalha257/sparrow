import AppKit
import SwiftUI
import ApplicationServices

/// Hold the right ⌥ Option key anywhere, speak, let go — Zuffi acts on it.
@MainActor
enum HoldToTalk {
    private static var monitors: [Any] = []
    private static var down = false
    static let rightOption: UInt16 = 61

    static func start() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { e in
            let code = e.keyCode
            let optionDown = e.modifierFlags.contains(.option)
            Task { @MainActor in HoldToTalk.flags(code: code, optionDown: optionDown) }
        }
        if let g = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handler) { monitors.append(g) }
        // Hold Z for a moment (when you're not typing in a box): talk to Zuffi about what's on screen.
        if let z = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp], handler: { e in
            let isDown = e.type == .keyDown, rep = e.isARepeat, code = e.keyCode
            let plain = e.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
            Task { @MainActor in HoldToTalk.zKey(code: code, down: isDown, repeat: rep, plain: plain) }
        }) { monitors.append(z) }
        SelectionBar.shared.start()
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in handler(e); return e }) { monitors.append(l) }
        // Global key events need Accessibility permission; ask once so the key works everywhere.
        // Ask once (not on every launch) so the key works everywhere.
        let askedBefore = UserDefaults.standard.bool(forKey: "axAsked")
        let opts = ["AXTrustedCheckOptionPrompt": !askedBefore] as CFDictionary
        UserDefaults.standard.set(true, forKey: "axAsked")
        if !AXIsProcessTrustedWithOptions(opts) { appendAppLog("voice.log", "hold-to-talk: waiting for Accessibility permission") }
    }

    // MARK: hold Z
    private static var zDownAt: Date?
    private static var zActive = false
    private static func zKey(code: UInt16, down: Bool, repeat rep: Bool, plain: Bool) {
        guard code == 6, UserDefaults.standard.object(forKey: "holdZ") as? Bool ?? true else { return }   // 6 = Z
        if down {
            guard plain, !rep, zDownAt == nil else { return }
            if ZuffiAsk.isTyping() { return }                 // typing a word with z in it: leave it alone
            zDownAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                MainActor.assumeIsolated {
                    guard let t = zDownAt, Date().timeIntervalSince(t) >= 0.5, !zActive else { return }
                    zActive = true
                    ZuffiAsk.shared.beginListening()
                }
            }
        } else {
            zDownAt = nil
            if zActive { zActive = false; VoiceEngine.shared.pushToTalkUp() }
        }
    }

    private static func flags(code: UInt16, optionDown: Bool) {
        guard UserDefaults.standard.object(forKey: "holdToTalk") as? Bool ?? true, code == rightOption else { return }
        if optionDown && !down { down = true; VoiceEngine.shared.pushToTalkDown() }
        else if !optionDown && down { down = false; VoiceEngine.shared.pushToTalkUp() }
    }
}


// MARK: - Ask Zuffi about what's on the screen (hold Z, double-click Zuffi, the selection bar)

@MainActor
final class ZuffiAsk: ObservableObject {
    static let shared = ZuffiAsk()
    /// The text that was selected when you started talking (used by the next spoken question).
    var pending: String?
    var pendingAt = Date.distantPast

    /// The words selected in the app in front, through Accessibility.
    static func selectedText() -> String? {
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier { return nil }
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let f = focused else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success,
              let t = (sel as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(4000))
    }

    /// True when the cursor is in a text box (so a held Z is just typing).
    static func isTyping() -> Bool {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let f = focused else { return false }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(f as! AXUIElement, kAXRoleAttribute as CFString, &role)
        let r = (role as? String) ?? ""
        if ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(r) { return true }
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(f as! AXUIElement, kAXValueAttribute as CFString, &settable)
        return settable.boolValue && r != "AXButton"
    }

    /// Hold Z / double-click: remember what's selected, then listen.
    func beginListening() {
        pending = Self.selectedText(); pendingAt = Date()
        BunnyFaceCenter.shared.show(.listening, for: 6)
        VoiceEngine.shared.pushToTalkDown(forScreen: true)
    }
    func listenOnce() {
        pending = Self.selectedText(); pendingAt = Date()
        BunnyFaceCenter.shared.show(.listening, for: 6)
        VoiceEngine.shared.listenOnce(byButton: true, forScreen: true)
    }

    /// Spoken questions come here first: if they are about the screen, answer about it.
    func takeIfAboutScreen(_ said: String) -> (String, String?)? {
        let low = said.lowercased()
        let recent = Date().timeIntervalSince(pendingAt) < 60     // called with Z or a double-click just now
        let sel = recent ? pending : nil
        pending = nil; pendingAt = .distantPast
        if sel != nil { return (said, sel) }
        let explicit = #"\b(on (my|the) screen|this (text|page|email|message|word|line|error|button)|selected|where (do|can|should) i (click|press|find)|which button)"#
        let screenWords = #"\b(this|that|here|explain|translate|mean|meaning|reply|rewrite|read|summar|what does|what is this|click)"#
        if low.range(of: explicit, options: .regularExpression) != nil { return (said, nil) }
        if recent, low.range(of: screenWords, options: .regularExpression) != nil { return (said, nil) }
        return nil
    }

    var userLanguage: String { NikBrain.shared.profile["own"] ?? (UserDefaults.standard.string(forKey: "zuffiLanguage") ?? "English") }

    /// Answer a question about the selection (or the screen), out loud, in the user's language.
    func answer(_ question: String, about selection: String?) async {
        let low = question.lowercased()
        if low.range(of: #"where (do|can|should) i (click|press|find|go)|which button|show me where|point (at|to)"#, options: .regularExpression) != nil {
            await PointerRing.find(question); return
        }
        BunnyFaceCenter.shared.show(.thinking, for: 8)
        var image: (mime: String, base64: String)?
        var context = ""
        if let s = selection, !s.isEmpty { context = "The user selected this text on their screen:\n\"\"\"\n\(s)\n\"\"\"" }
        else if let shot = await ScreenGrab.main() {
            image = (mime: "image/jpeg", base64: shot.jpeg.base64EncodedString())
            context = "A screenshot of the user's screen is attached."
        }
        let r = await AIService.shared.oneShot("""
            \(context)
            The user asks (by voice): "\(question)"
            Answer like a kind, clever friend: short and clear, ready to be read aloud (under 90 words), in \(userLanguage) unless they asked for another language. \
            If they ask to reply or rewrite, give only the text to use. Plain text, no symbols.
            """, system: "You are Zuffi, a friendly helper that lives on the user's computer.\n" + ZuffiVoice.style, image: image) ?? ""
        let reply = r.trimmingCharacters(in: .whitespacesAndNewlines)
        show(reply.isEmpty ? "I couldn't answer that just now — check an AI model is set up (the model button in the notch)." : reply, title: question)
    }

    /// One tap from the selection bar.
    func act(_ kind: String, _ text: String) async {
        if kind == "read" { TutorVoice.shared.speakAuto(text); return }
        BunnyFaceCenter.shared.show(.thinking, for: 8)
        let lang = userLanguage
        let ask: String
        switch kind {
        case "translate": ask = "Translate this into \(lang) (if it is already in \(lang), translate it into English). Give only the translation:\n\(text)"
        case "reply": ask = "Write a short, polite reply to this message, in the same language as the message. Give only the reply text:\n\(text)"
        case "rewrite": ask = "Rewrite this to be clear, correct and polite, same language and meaning. Give only the new text:\n\(text)"
        default: ask = "Explain this simply in \(lang), like a kind friend, in under 90 words. If it asks the reader to do something, say what and by when:\n\(text)"
        }
        let r = await AIService.shared.oneShot(ask, system: "You are Zuffi, a friendly helper.\n" + ZuffiVoice.style) ?? ""
        let out = r.trimmingCharacters(in: .whitespacesAndNewlines)
        if ["reply", "rewrite"].contains(kind), !out.isEmpty {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(out, forType: .string)
        }
        show(out.isEmpty ? "I couldn't do that just now — check an AI model is set up." : out,
             title: ["translate": "Translation", "reply": "Reply — copied, press ⌘V to paste", "rewrite": "Rewritten — copied, press ⌘V to paste"][kind] ?? "Explained",
             speak: kind == "explain" || kind == "translate")
    }

    @Published var answerText = ""
    @Published var answerTitle = ""
    private var panel: NSPanel?
    func show(_ text: String, title: String, speak: Bool = true) {
        answerText = text; answerTitle = title
        BunnyFaceCenter.shared.show(.happy, for: 3)
        if speak { TutorVoice.shared.speakAuto(text) }
        let p = panel ?? {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 260), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .floating
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; p.isMovableByWindowBackground = true
            p.contentView = NSHostingView(rootView: ZuffiAnswerView())
            panel = p; return p
        }()
        let m = NSEvent.mouseLocation
        let s = NSScreen.screens.first { $0.frame.contains(m) } ?? NSScreen.main
        var o = NSPoint(x: m.x - 200, y: m.y - 290)
        if let f = s?.visibleFrame { o.x = min(max(o.x, f.minX + 10), f.maxX - 410); o.y = min(max(o.y, f.minY + 10), f.maxY - 270) }
        p.setFrameOrigin(o)
        p.alphaValue = 0; p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.18; p.animator().alphaValue = 1 }
    }
    func hide() { panel?.orderOut(nil); TutorVoice.shared.stop() }
}

struct ZuffiAnswerView: View {
    @ObservedObject private var a = ZuffiAsk.shared
    @ObservedObject private var voice = TutorVoice.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                LiveBunnyFace(size: 34).clipShape(Circle())
                Text(a.answerTitle).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                Spacer()
                Button { a.hide() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.6)) }.buttonStyle(.plain)
            }
            ScrollView {
                Text(a.answerText).font(.system(size: 14.5, design: .rounded)).foregroundColor(.white).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Button { voice.speaking ? voice.stop() : TutorVoice.shared.speakAuto(a.answerText) } label: { Label(voice.speaking ? "Stop" : "Say it", systemImage: voice.speaking ? "stop.fill" : "speaker.wave.2.fill") }
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(a.answerText, forType: .string) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Spacer()
            }
            .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#C9B8FF"))
        }
        .padding(16).frame(width: 400, height: 260, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: "#0B0A10").opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.1)))
    }
}

// MARK: - The little bar that appears over text you select

@MainActor
final class SelectionBar: ObservableObject {
    static let shared = SelectionBar()
    @Published var text = ""
    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var downAt = NSPoint.zero
    var enabled: Bool { UserDefaults.standard.object(forKey: "selectionBar") as? Bool ?? true }

    func start() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { _ in
            let p = NSEvent.mouseLocation
            Task { @MainActor in SelectionBar.shared.downAt = p; SelectionBar.shared.hide() }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { e in
            let clicks = e.clickCount, p = NSEvent.mouseLocation
            Task { @MainActor in SelectionBar.shared.mouseUp(at: p, clicks: clicks) }
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .scrollWheel], handler: { _ in
            Task { @MainActor in SelectionBar.shared.hide() }
        }) { monitors.append(m) }
    }

    private func mouseUp(at p: NSPoint, clicks: Int) {
        guard enabled else { return }
        // only after dragging over text or double / triple clicking a word
        let dragged = hypot(p.x - downAt.x, p.y - downAt.y) > 6
        guard dragged || clicks >= 2 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            MainActor.assumeIsolated {
                guard let t = ZuffiAsk.selectedText(), t.count >= 2 else { return }
                SelectionBar.shared.show(t, at: p)
            }
        }
    }

    func show(_ t: String, at p: NSPoint) {
        text = t
        let w: CGFloat = 330, h: CGFloat = 44
        let pn = panel ?? {
            let pn = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            pn.isOpaque = false; pn.backgroundColor = .clear; pn.hasShadow = true; pn.level = .popUpMenu
            pn.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            pn.contentView = NSHostingView(rootView: SelectionBarView())
            panel = pn; return pn
        }()
        var o = NSPoint(x: p.x - w / 2, y: p.y + 14)
        if let f = (NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main)?.visibleFrame {
            o.x = min(max(o.x, f.minX + 6), f.maxX - w - 6); o.y = min(o.y, f.maxY - h - 6)
        }
        pn.setFrameOrigin(o)
        pn.alphaValue = 0; pn.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; pn.animator().alphaValue = 1 }
    }
    func hide() { panel?.orderOut(nil) }
}

struct SelectionBarView: View {
    @ObservedObject private var bar = SelectionBar.shared
    var body: some View {
        HStack(spacing: 2) {
            LiveBunnyFace(size: 26).clipShape(Circle()).padding(.leading, 6).padding(.trailing, 2)
            item("Explain", "explain"); item("Translate", "translate"); item("Reply", "reply"); item("Rewrite", "rewrite")
            Button { go("read") } label: { Image(systemName: "speaker.wave.2.fill").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 30) }
                .buttonStyle(.plain).foregroundColor(.white).help("Read it aloud")
        }
        .frame(height: 40).padding(.trailing, 4)
        .background(Capsule().fill(Color(hex: "#0B0A10").opacity(0.96)))
        .overlay(Capsule().stroke(Color.white.opacity(0.1)))
        .frame(width: 330, height: 44)
    }
    private func item(_ t: String, _ k: String) -> some View {
        Button { go(k) } label: { Text(t).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundColor(.white).padding(.horizontal, 9).frame(height: 30).contentShape(Rectangle()) }
            .buttonStyle(.plain)
    }
    private func go(_ k: String) {
        let t = bar.text
        bar.hide()
        Task { await ZuffiAsk.shared.act(k, t) }
    }
}

// MARK: - "Where do I click?" — a soft ring around the right spot

@MainActor
enum PointerRing {
    private static var panel: NSPanel?
    static func find(_ question: String) async {
        BunnyFaceCenter.shared.show(.thinking, for: 8)
        guard let shot = await ScreenGrab.main() else { ZuffiAsk.shared.show("I can't see the screen — allow Zuffi in System Settings → Privacy & Security → Screen Recording.", title: "Where to click"); return }
        let r = await AIService.shared.oneShot("""
            The user asks: "\(question)". Look at the screenshot and find the ONE button, link or field they should use.
            JSON only: {"x": 0-1000 (centre, across), "y": 0-1000 (centre, down), "say": "one short sentence telling them where it is", "found": true}
            If it isn't on screen, {"found": false, "say": "what to do instead"}.
            """, system: "You find things on screenshots precisely. Reply with JSON only.", image: (mime: "image/jpeg", base64: shot.jpeg.base64EncodedString()))
        guard let r, let j = AIService.jsonIn(r) as? [String: Any] else { ZuffiAsk.shared.show("I couldn't work out where — try asking a bit differently.", title: "Where to click"); return }
        let say = (j["say"] as? String) ?? ""
        if (j["found"] as? Bool) ?? false, let x = (j["x"] as? NSNumber)?.doubleValue, let y = (j["y"] as? NSNumber)?.doubleValue {
            let cg = shot.point(x: x, y: y)                                   // top-left origin
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            ring(at: NSPoint(x: cg.x, y: top - cg.y))
        }
        ZuffiAsk.shared.show(say.isEmpty ? "Here it is." : say, title: "Where to click")
    }

    static func ring(at p: NSPoint) {
        panel?.orderOut(nil)
        let size: CGFloat = 120
        let pn = NSPanel(contentRect: NSRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pn.isOpaque = false; pn.backgroundColor = .clear; pn.hasShadow = false; pn.ignoresMouseEvents = true
        pn.level = .screenSaver; pn.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        pn.contentView = NSHostingView(rootView: RingView())
        pn.orderFrontRegardless(); panel = pn
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { MainActor.assumeIsolated { if PointerRing.panel === pn { pn.orderOut(nil); PointerRing.panel = nil } } }
    }
}

private struct RingView: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: "#8E7CFF"), lineWidth: 4).frame(width: 64, height: 64)
            Circle().stroke(Color(hex: "#8E7CFF").opacity(pulse ? 0 : 0.8), lineWidth: 3).frame(width: pulse ? 116 : 64, height: pulse ? 116 : 64)
        }
        .frame(width: 120, height: 120)
        .onAppear { withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { pulse = true } }
    }
}

// MARK: - Meeting helper: a private panel only you see (left out of screen sharing and recordings)

@MainActor
final class MeetingHelper: ObservableObject {
    static let shared = MeetingHelper()
    @Published var on = false
    @Published var they = ""
    @Published var translated = ""
    @Published var suggest = ""
    @Published var notes: [String] = []
    private var timer: Timer?
    private var lastLen = 0
    private var panel: NSPanel?

    func toggle() { on ? stop() : start() }
    func start() {
        guard !on else { return }
        on = true; they = ""; translated = ""; suggest = ""; notes = []; lastLen = 0
        RoomListener.shared.start()
        showPanel()
        timer = Timer.scheduledTimer(withTimeInterval: 9, repeats: true) { _ in Task { @MainActor in await MeetingHelper.shared.think() } }
    }
    func stop() {
        on = false; timer?.invalidate(); timer = nil
        RoomListener.shared.stop()
        panel?.orderOut(nil)
    }

    private func think() async {
        let t = RoomListener.shared.transcript
        guard t.count > lastLen + 25 else { return }
        let fresh = String(t.suffix(min(900, t.count - lastLen + 300)))
        lastLen = t.count
        let lang = ZuffiAsk.shared.userLanguage
        let r = await AIService.shared.oneShot("""
            Live meeting. The latest words heard: "\(fresh)"
            Help the user follow and answer. JSON only:
            {"they":"the latest thing the other person said or asked, cleaned up (short)","translated":"that, in \(lang)","suggest":"a short, natural answer the user could say, in the meeting's language (empty if nothing to answer)","note":"one key point to remember (empty if none)"}
            """, system: "You help someone follow a meeting in real time. Be brief. JSON only.")
        guard let r, let j = AIService.jsonIn(r) as? [String: Any] else { return }
        if let s = j["they"] as? String, !s.isEmpty { they = s }
        if let s = j["translated"] as? String, !s.isEmpty { translated = s }
        suggest = (j["suggest"] as? String) ?? ""
        if let n = j["note"] as? String, !n.isEmpty, !notes.contains(n) { notes.append(n); if notes.count > 8 { notes.removeFirst() } }
    }

    private func showPanel() {
        if let p = panel { p.orderFrontRegardless(); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 420), styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true; p.level = .floating
        p.isMovableByWindowBackground = true
        p.sharingType = .none                       // private: not shown in screen sharing or recordings
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: MeetingHelperView())
        if let f = NSScreen.main?.visibleFrame { p.setFrameOrigin(NSPoint(x: f.maxX - 340, y: f.maxY - 460)) }
        p.orderFrontRegardless(); panel = p
    }
}

struct MeetingHelperView: View {
    @ObservedObject private var m = MeetingHelper.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ZUFFI · PRIVATE").font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(Color(hex: "#B9AEFF"))
                Spacer()
                Button { m.stop() } label: { Text("Stop").font(.system(size: 11, weight: .semibold)) }.buttonStyle(.plain).foregroundColor(.white.opacity(0.7))
            }
            Text("Only you see this — it's left out of screen sharing.").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.45))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if m.they.isEmpty { Text("Listening… Zuffi hears the call through your Mac's microphone (with headphones on, it only hears you).").font(.system(size: 12.5)).foregroundColor(.white.opacity(0.6)) }
                    if !m.they.isEmpty { label("They said"); Text(m.they).font(.system(size: 13.5)).foregroundColor(.white) }
                    if !m.translated.isEmpty { label("In \(ZuffiAsk.shared.userLanguage)"); Text(m.translated).font(.system(size: 13.5)).foregroundColor(.white) }
                    if !m.suggest.isEmpty { label("You could say"); Text(m.suggest).font(.system(size: 13.5)).foregroundColor(Color(hex: "#CFE9D8")).textSelection(.enabled) }
                    if !m.notes.isEmpty { label("Notes"); ForEach(m.notes, id: \.self) { Text("• " + $0).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.85)) } }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14).frame(minWidth: 280, minHeight: 300, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: "#0B0A10").opacity(0.94)))
    }
    private func label(_ s: String) -> some View { Text(s).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.45)) }
}
