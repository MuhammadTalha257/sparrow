import AppKit
import ScreenCaptureKit
import CoreGraphics
import SwiftUI

// =====================================================================
// MARK: - Screen agent: Zuffi's eyes and hands
//
// "Zuffi, on screen, find the latest Arijit Singh song on YouTube and play it"
//   1. Eyes  — a picture of the main screen (ScreenCaptureKit; Zuffi's own windows left out)
//   2. Brain — the AI looks at it and picks ONE next step (click here, type this, press ⌘L…)
//   3. Hands — the Mac does it (CGEvent mouse + keyboard)
//   …and again, until the task is done. A pink glow shows while Zuffi is in control;
//   Esc (or "stop") ends it at once. Anything that sends, buys, pays, posts or deletes
//   stops and asks you first. Passwords, codes and CAPTCHAs are always handed back to you.
//
// Written for Zuffi (inspired by how open agents such as nanoMuse and UI-TARS work: the
// screenshot → model → action loop, ScreenCaptureKit for the picture, CGEvent for the hands).
// =====================================================================

@MainActor
final class ScreenAgent {
    static let shared = ScreenAgent()

    private(set) var running = false
    private(set) var task = ""
    private var stopRequested = false
    private var pendingConfirm: CheckedContinuation<Bool, Never>?
    private(set) var pendingQuestion: String?
    private var report: CheckedContinuation<String, Never>?
    private var escMonitor: Any?
    private var lastOwnKeyAt = Date.distantPast
    private let maxSteps = 30
    private var confirmToken = 0

    var awaitingConfirmation: Bool { pendingConfirm != nil }

    // MARK: Permissions

    static var canSee: Bool { CGPreflightScreenCaptureAccess() }
    static var canAct: Bool { AXIsProcessTrusted() }

    static func askToSee() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }
    /// Old entries from earlier builds (when the app was "Sparrow") can look switched on but no longer match
    /// this app. Clear Zuffi's own entries, then ask again so macOS adds the right one.
    static func fixPermissions() async {
        let id = Bundle.main.bundleIdentifier ?? "app.sparrowai.Sparrow"
        for service in ["ScreenCapture", "Accessibility"] {
            _ = await LocalAISetup.run("/usr/bin/tccutil", ["reset", service, id])
        }
        appendAppLog("agents.log", "permissions reset for \(id)")
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        _ = CGRequestScreenCaptureAccess()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// macOS only applies a new Screen Recording permission after the app restarts.
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    static func askToAct() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private static let seeHelp = "I can't see the screen yet. Open Zuffi Settings → Screen and press Fix permissions, switch Zuffi on in the list, then press Restart Zuffi."
    private static let actHelp = "I need permission to use the mouse and keyboard: System Settings → Privacy & Security → Accessibility → switch on Zuffi (off and on again after an update)."

    // MARK: Look (no actions)

    /// "What's on my screen?" — one picture, one answer.
    func describe(_ question: String) async -> String {
        guard Self.canSee else { Self.askToSee(); return Self.seeHelp }
        guard let shot = await ScreenGrab.main() else { return Self.seeHelp }
        let q = question.isEmpty ? "What's on my screen? Describe it briefly and helpfully." : question
        let prompt = "This is a screenshot of the user's Mac screen. Answer their question about it in 1–3 short spoken sentences, in the same language they used. Read any important text exactly. Question: \(q)"
        if let a = await ScreenBrain.ask(prompt: prompt, jpeg: shot.jpeg) { return a }
        return "I took a look but couldn't get an answer from the AI. Check your AI key in Settings → AI."
    }

    // MARK: Do a task on the screen

    /// Starts (or continues) a task. Returns when it's finished, stopped, or waiting for your OK.
    func run(_ task: String) async -> String {
        if running {
            return pendingQuestion.map { "I'm waiting for you: \($0) Say yes or no." } ?? "I'm already working on: \(self.task). Say stop to cancel."
        }
        guard Self.canSee else { Self.askToSee(); return Self.seeHelp }
        guard Self.canAct else { Self.askToAct(); return Self.actHelp }
        guard ScreenBrain.ready else { return "Add a Gemini or Claude key in Settings → AI so I can see and use the screen." }
        self.task = task
        running = true; stopRequested = false
        appendAppLog("agents.log", "screen task: \(task)")
        ScreenGlow.shared.show("Starting: \(task)")
        startEscWatch()
        return await withCheckedContinuation { (c: CheckedContinuation<String, Never>) in
            report = c
            Task { await self.loop() }
        }
    }

    func stop() {
        guard running else { return }
        stopRequested = true
        pendingConfirm?.resume(returning: false); pendingConfirm = nil
    }

    func confirm(_ yes: Bool) {
        guard let c = pendingConfirm else { return }
        pendingConfirm = nil
        pendingQuestion = nil
        ScreenGlow.shared.update(yes ? "Okay — doing it" : "Okay — not doing that")
        c.resume(returning: yes)
    }

    /// Sends a progress or final message to whoever asked.
    private func deliver(_ text: String) {
        if let r = report { report = nil; r.resume(returning: text) }
        else {
            // The first answer already went back (we paused to ask); tell the person on the Mac.
            AppState.shared.noteMessage = "🖥️ " + text
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
            NotificationCenter.default.post(name: .petSay, object: text)
            VoiceEngine.shared.speak(text)
        }
    }

    private func finish(_ text: String) {
        running = false
        stopEscWatch()
        ScreenGlow.shared.hide()
        appendAppLog("agents.log", "screen task end: \(text)")
        deliver(text)
    }

    private func loop() async {
        var history: [String] = []
        var lastAction = ""
        var repeats = 0
        for step in 1...maxSteps {
            if stopRequested { finish("Stopped."); return }
            guard let shot = await ScreenGrab.main() else { finish(Self.seeHelp); return }
            if stopRequested { finish("Stopped."); return }
            ScreenGlow.shared.update("Step \(step) · looking…")
            guard let move = await ScreenBrain.next(task: task, history: history, jpeg: shot.jpeg) else {
                finish("I couldn't reach the AI to decide the next step. Check your internet and AI key."); return
            }
            if stopRequested { finish("Stopped."); return }
            let label = move.say.isEmpty ? move.action : move.say
            ScreenGlow.shared.update("Step \(step) · \(label)")

            switch move.action {
            case "done":
                finish(move.answer.isEmpty ? "Done." : move.answer); return
            case "ask":
                // Logins, passwords, codes, CAPTCHAs, or a real choice only you can make.
                finish(move.answer.isEmpty ? "I need you to take over here." : move.answer); return
            default: break
            }

            // Ask before anything that can't be undone.
            if move.risky || Self.looksRisky(move) {
                let q = "Shall I \(label.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")))?"
                pendingQuestion = q
                ScreenGlow.shared.update("Waiting for your OK: \(label)")
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
                let first = report != nil
                deliver(q + " Say yes or no.")
                if !first { VoiceEngine.shared.listenAfterSpeech = true }
                confirmToken += 1
                let token = confirmToken
                let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                    pendingConfirm = c
                    // No answer in 5 minutes → don't do it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                        MainActor.assumeIsolated { if ScreenAgent.shared.confirmToken == token { ScreenAgent.shared.confirm(false) } }
                    }
                }
                if !ok || stopRequested { finish("Okay, I didn't do it and stopped there."); return }
            }

            let note = await perform(move, on: shot)
            history.append("\(step). \(move.action) \(move.describe) → \(note)")
            if history.count > 12 { history.removeFirst() }
            let sig = "\(move.action)|\(move.x)|\(move.y)|\(move.text)|\(move.keys)"
            repeats = sig == lastAction ? repeats + 1 : 0
            lastAction = sig
            if repeats >= 2 { history.append("(The same action did nothing three times — try a different way.)") }
            try? await Task.sleep(nanoseconds: move.action == "wait" ? 0 : 700_000_000)
        }
        finish("I took \(maxSteps) steps and didn't finish. Tell me more precisely what to do, or finish it yourself.")
    }

    private static func looksRisky(_ m: ScreenMove) -> Bool {
        let words = (m.say + " " + m.text).lowercased()
        let risky = #"\b(send|sent|buy|purchase|pay|payment|checkout|place order|order now|delete|remove permanently|empty trash|post|publish|tweet|submit|transfer|confirm purchase|unsubscribe|sign out of all)\b"#
        guard ["click", "double_click", "keys", "type"].contains(m.action) else { return false }
        if m.action == "type", !m.submit { return false }
        return words.range(of: risky, options: .regularExpression) != nil
    }

    private func perform(_ m: ScreenMove, on shot: ScreenShot) async -> String {
        func pt(_ x: Double, _ y: Double) -> CGPoint { shot.point(x: x, y: y) }
        switch m.action {
        case "click": Hands.click(pt(m.x, m.y)); return "clicked"
        case "double_click": Hands.click(pt(m.x, m.y), count: 2); return "double-clicked"
        case "right_click": Hands.click(pt(m.x, m.y), right: true); return "right-clicked"
        case "move": Hands.move(pt(m.x, m.y)); return "moved"
        case "drag": Hands.drag(pt(m.x, m.y), pt(m.x2, m.y2)); return "dragged"
        case "scroll":
            if m.x > 0 || m.y > 0 { Hands.move(pt(m.x, m.y)) }
            Hands.scroll(lines: m.amount == 0 ? 5 : m.amount); return "scrolled"
        case "type":
            if m.x > 0 || m.y > 0 { Hands.click(pt(m.x, m.y)); try? await Task.sleep(nanoseconds: 250_000_000) }
            if m.clear { lastOwnKeyAt = Date(); Hands.keys("cmd+a"); Hands.keys("delete") }
            Hands.type(m.text)
            if m.submit { lastOwnKeyAt = Date(); Hands.keys("enter") }
            return "typed"
        case "keys": lastOwnKeyAt = Date(); return Hands.keys(m.keys) ? "pressed \(m.keys)" : "unknown keys \(m.keys)"
        case "open_app":
            return await AgentRouter.shared.handle("open \(m.text)") ?? "couldn't open \(m.text)"
        case "open_url":
            let s = m.text.hasPrefix("http") ? m.text : "https://" + m.text
            if let u = safeWebURL(s) { NSWorkspace.shared.open(u); try? await Task.sleep(nanoseconds: 1_500_000_000); return "opened \(u.host ?? s)" }
            return "not a web address"
        case "wait":
            try? await Task.sleep(nanoseconds: UInt64(min(10, max(1, m.amount == 0 ? 2 : m.amount))) * 1_000_000_000); return "waited"
        default: return "unknown action"
        }
    }

    // Esc anywhere stops Zuffi (except the Esc Zuffi presses itself).
    private func startEscWatch() {
        stopEscWatch()
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            guard e.keyCode == 53 else { return }
            MainActor.assumeIsolated {
                let me = ScreenAgent.shared
                if Date().timeIntervalSince(me.lastOwnKeyAt) > 0.6 { me.stop() }
            }
        }
    }
    private func stopEscWatch() { if let m = escMonitor { NSEvent.removeMonitor(m) }; escMonitor = nil }
}

// MARK: - Eyes

struct ScreenShot {
    let jpeg: Data
    let frame: CGRect          // the display in global points (top-left origin, like CGEvent)
    /// Model coordinates (0–1000 across and down) → a point the mouse can go to.
    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: frame.minX + frame.width * min(1000, max(0, x)) / 1000,
                y: frame.minY + frame.height * min(1000, max(0, y)) / 1000)
    }
}

enum ScreenGrab {
    /// The main display, without Zuffi's own windows (island, pet, glow).
    static func main() async -> ScreenShot? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mainID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else { return nil }
            let me = ProcessInfo.processInfo.processIdentifier
            let mine = content.applications.filter { $0.processID == me }
            let filter = SCContentFilter(display: display, excludingApplications: mine, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            let k = min(1.0, 1440.0 / Double(max(display.width, display.height)))
            cfg.width = max(1, Int(Double(display.width) * k))
            cfg.height = max(1, Int(Double(display.height) * k))
            cfg.showsCursor = true
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            guard let jpeg = ImageShrink.jpeg(img, maxSide: 1440) else { return nil }
            return ScreenShot(jpeg: jpeg, frame: CGDisplayBounds(display.displayID))
        } catch {
            appendAppLog("agents.log", "screen capture failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - Hands

enum Hands {
    private static var src: CGEventSource? { CGEventSource(stateID: .hidSystemState) }

    static func move(_ p: CGPoint) {
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    static func click(_ p: CGPoint, count: Int = 1, right: Bool = false) {
        move(p); usleep(80_000)
        let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = right ? .right : .left
        for n in 1...max(1, count) {
            let d = CGEvent(mouseEventSource: src, mouseType: down, mouseCursorPosition: p, mouseButton: button)
            let u = CGEvent(mouseEventSource: src, mouseType: up, mouseCursorPosition: p, mouseButton: button)
            d?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
            u?.setIntegerValueField(.mouseEventClickState, value: Int64(n))
            d?.post(tap: .cghidEventTap); usleep(30_000); u?.post(tap: .cghidEventTap); usleep(60_000)
        }
    }

    static func drag(_ a: CGPoint, _ b: CGPoint) {
        move(a); usleep(80_000)
        CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: a, mouseButton: .left)?.post(tap: .cghidEventTap)
        for i in 1...12 {
            let t = CGFloat(i) / 12
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
            usleep(15_000)
        }
        CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: b, mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    /// Positive = down.
    static func scroll(lines: Double) {
        let n = Int32(max(-30, min(30, lines)))
        CGEvent(scrollWheelEvent2Source: src, units: .line, wheelCount: 1, wheel1: -n, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    /// Any language, typed as characters (no clipboard).
    static func type(_ text: String) {
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(units.count, i + 16)])
            let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let u = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            chunk.withUnsafeBufferPointer { b in
                d?.keyboardSetUnicodeString(stringLength: b.count, unicodeString: b.baseAddress)
                u?.keyboardSetUnicodeString(stringLength: b.count, unicodeString: b.baseAddress)
            }
            d?.post(tap: .cghidEventTap); u?.post(tap: .cghidEventTap)
            usleep(12_000)
            i += 16
        }
    }

    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "enter": 36, "return": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "esc": 53, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126, "pageup": 116, "pagedown": 121, "home": 115, "end": 119, "forwarddelete": 117,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    /// "cmd+l", "enter", "cmd+shift+t", "ctrl+tab"…
    @discardableResult
    static func keys(_ combo: String) -> Bool {
        var flags: CGEventFlags = []
        var key: CGKeyCode?
        for part in combo.lowercased().replacingOccurrences(of: " ", with: "").split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command", "meta", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "alt", "option", "opt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            default: key = codes[part]
            }
        }
        guard let k = key else { return false }
        let d = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: true)
        let u = CGEvent(keyboardEventSource: src, virtualKey: k, keyDown: false)
        d?.flags = flags; u?.flags = flags
        d?.post(tap: .cghidEventTap); usleep(20_000); u?.post(tap: .cghidEventTap)
        return true
    }
}

// MARK: - Brain

struct ScreenMove {
    var action = "done"
    var x = 0.0, y = 0.0, x2 = 0.0, y2 = 0.0
    var text = "", keys = "", say = "", answer = ""
    var amount = 0.0
    var submit = false, clear = false, risky = false

    init(_ d: [String: Any]) {
        func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? Double(d[k] as? String ?? "") ?? 0 }
        func s(_ k: String) -> String { d[k] as? String ?? "" }
        func b(_ k: String) -> Bool { d[k] as? Bool ?? false }
        action = s("action").lowercased(); x = n("x"); y = n("y"); x2 = n("x2"); y2 = n("y2")
        text = s("text"); keys = s("keys"); say = s("say"); answer = s("answer"); amount = n("amount")
        submit = b("submit"); clear = b("clear"); risky = b("risky")
    }
    var describe: String {
        switch action {
        case "type": return "\"\(text.prefix(40))\""
        case "keys": return keys
        case "open_app", "open_url": return text
        case "scroll": return "\(amount)"
        default: return x > 0 || y > 0 ? "(\(Int(x)),\(Int(y))) \(say)" : say
        }
    }
}

@MainActor
enum ScreenBrain {
    static var geminiKey: String? { KeychainStore.shared.get("gemini-api-key").flatMap { $0.isEmpty ? nil : $0 } }
    static var claudeKey: String? { KeychainStore.shared.get("anthropic-api-key").flatMap { $0.isEmpty ? nil : $0 } }
    static var ready: Bool { geminiKey != nil || claudeKey != nil }

    static let rules = """
    You are Zuffi, operating the user's Mac to finish their task. Every turn you get a fresh screenshot of the main screen.
    Coordinates: x and y from 0 to 1000 across the width and down the height of the screenshot (0,0 = top-left). Point at the CENTRE of the thing to click.
    Reply with ONE next action as JSON:
      {"say": "short label of what you're doing, e.g. 'Click the search box'", "action": one of
       "click" | "double_click" | "right_click" | "move" | "drag" (x,y → x2,y2) | "scroll" (amount: lines, positive = down; optional x,y to scroll over) |
       "type" (text; optional x,y to click first; "clear": true to replace what's there; "submit": true to press Enter after) |
       "keys" (keys like "cmd+l", "enter", "cmd+t", "esc", "tab", "down") | "open_app" (text = app name) | "open_url" (text = address) |
       "wait" (amount = seconds) | "done" (answer = what you did / what you found, 1–2 sentences, user's language) |
       "ask" (answer = what you need from the user),
       "x": …, "y": …, "risky": true/false}
    Rules:
    - Prefer the fastest reliable way: open_app / open_url / keyboard shortcuts (cmd+l for a browser address bar, cmd+f to find) over hunting for icons.
    - "risky": true for anything that sends, posts, buys, pays, books, deletes, submits a form, changes account settings or can't be undone. Zuffi asks the user first.
    - Never type passwords, card numbers, one-time codes or answer CAPTCHAs: use "ask" so the user does it. Decline non-essential cookies.
    - If something didn't work, try another way; don't repeat the same action again and again.
    - Use "done" as soon as the task is finished, or to answer a question about the screen.
    """

    static func next(task: String, history: [String], jpeg: Data) async -> ScreenMove? {
        let past = history.isEmpty ? "Nothing yet — this is the first step." : history.joined(separator: "\n")
        let prompt = "\(rules)\n\nTASK: \(task)\n\nSTEPS SO FAR:\n\(past)\n\nLook at the current screenshot and reply with the next action JSON only."
        guard let raw = await ask(prompt: prompt, jpeg: jpeg, json: true) else { return nil }
        return parse(raw).map(ScreenMove.init)
    }

    static func parse(_ raw: String) -> [String: Any]? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") { s = String(s[a...b]) }
        return (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]
    }

    /// One picture + one instruction → the model's text. Gemini first, Claude if there's no Gemini key.
    static func ask(prompt: String, jpeg: Data, json: Bool = false) async -> String? {
        if let k = geminiKey, let r = await gemini(prompt, jpeg, json, k) { return r }
        if let k = claudeKey { return await claude(prompt, jpeg, k) }
        return nil
    }

    private static func gemini(_ prompt: String, _ jpeg: Data, _ json: Bool, _ key: String) async -> String? {
        var gen: [String: Any] = ["temperature": 0.2]
        if json { gen["responseMimeType"] = "application/json" }
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt], ["inline_data": ["mime_type": "image/jpeg", "data": jpeg.base64EncodedString()]]]]],
            "generationConfig": gen,
        ]
        var model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
        for attempt in 0..<3 {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return nil }
            var req = URLRequest(url: url, timeoutInterval: 40)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, resp) = try? await URLSession.shared.data(for: req) else { continue }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if code == 200,
               let parts = ((o["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty { return text }
            }
            appendAppLog("ai.log", "screen brain: Gemini \(code) \(String(data: data, encoding: .utf8)?.prefix(160) ?? "")")
            if code == 404 || code == 400, attempt == 0, let pick = try? await AIService.newestGemini(key: key) {
                model = pick; UserDefaults.standard.set(pick, forKey: "geminiResolved"); continue
            }
            if code == 429 || code == 503 || code == 500 { try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_500_000_000); continue }
            return nil
        }
        return nil
    }

    private static func claude(_ prompt: String, _ jpeg: Data, _ key: String) async -> String? {
        let body: [String: Any] = [
            "model": UserDefaults.standard.string(forKey: "claudeModel") ?? "claude-sonnet-5-5",
            "max_tokens": 600,
            "messages": [["role": "user", "content": [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ["type": "text", "text": prompt],
            ]]],
        ]
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 40)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let content = o["content"] as? [[String: Any]] else { return nil }
        let text = content.compactMap { $0["text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }
}

// MARK: - The pink glow while Zuffi is in control (click-through; never in its own screenshots)

@MainActor
final class GlowModel: ObservableObject { @Published var text = "" }

@MainActor
final class ScreenGlow {
    static let shared = ScreenGlow()
    private var panel: NSPanel?
    private let model = GlowModel()

    func show(_ text: String) {
        model.text = text
        let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main ?? NSScreen.screens[0]
        let p = panel ?? {
            let p = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
            p.level = .screenSaver
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            p.contentView = NSHostingView(rootView: GlowView(model: model))
            return p
        }()
        panel = p
        p.setFrame(screen.frame, display: true)
        p.orderFrontRegardless()
    }
    func update(_ text: String) { model.text = text }
    func hide() { panel?.orderOut(nil) }
}

struct GlowView: View {
    @ObservedObject var model: GlowModel
    @State private var pulse = false
    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(LinearGradient(colors: [Color(hex: "#FFB6C8"), Color(hex: "#EF7598"), Color(hex: "#FFB6C8")], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 5)
                .shadow(color: Color(hex: "#EF7598").opacity(pulse ? 0.9 : 0.4), radius: pulse ? 18 : 8)
                .padding(2)
            HStack(spacing: 8) {
                Circle().fill(Color(hex: "#EF7598")).frame(width: 8, height: 8).opacity(pulse ? 1 : 0.4)
                Text(model.text).lineLimit(1).font(.system(size: 13, weight: .semibold, design: .rounded))
                Text("· Esc to stop").font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color(hex: "#EF7598").opacity(0.6), lineWidth: 1))
            .padding(.bottom, 26)
            .frame(maxWidth: 640)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true } }
    }
}

// MARK: - Settings → Screen

struct ScreenSettingsView: View {
    @State private var see = ScreenAgent.canSee
    @State private var act = ScreenAgent.canAct
    @State private var trying = false
    @State private var result = ""
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "cursorarrow.click.2").font(.system(size: 24)).foregroundColor(Color(hex: "#E2648A"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zuffi can see and use your screen").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Say “Zuffi, what's on my screen?” or “Zuffi, on screen, find the latest Arijit Singh song on YouTube and play it”. A pink glow shows while Zuffi is in control — press Esc or say “stop” to take over.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    row("Screen Recording", "so Zuffi can see the screen", see) { ScreenAgent.askToSee() }
                    Divider()
                    row("Accessibility", "so Zuffi can click and type", act) { ScreenAgent.askToAct() }
                    HStack {
                        Button("Fix permissions") { Task { await ScreenAgent.fixPermissions() } }
                        Button("Restart Zuffi") { ScreenAgent.relaunch() }
                        Spacer()
                    }.controlSize(.small)
                    Text("Allowed in System Settings but Zuffi still says no? Press Fix permissions: it clears old “Sparrow” entries and asks again. Switch Zuffi on in the list, then press Restart Zuffi.")
                        .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !see || !act {
                        Text("After every Zuffi update macOS may forget these: switch Zuffi off and on again in that list, then reopen Zuffi.")
                            .font(.system(size: 10)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(6)
            }
            HStack {
                Button(trying ? "Looking…" : "Try it: what's on my screen?") {
                    trying = true; result = ""
                    Task { result = await ScreenAgent.shared.describe(""); trying = false }
                }.disabled(trying)
                Spacer()
            }
            if !result.isEmpty { Text(result).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            Text("Zuffi always asks before sending, buying, paying, posting or deleting, and hands passwords, codes and CAPTCHAs back to you. Screenshots go only to the AI you chose (Gemini, or Claude if there's no Gemini key) and are not saved.")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(timer) { _ in see = ScreenAgent.canSee; act = ScreenAgent.canAct }
    }

    private func row(_ title: String, _ why: String, _ ok: Bool, ask: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundColor(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(why).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            if !ok { Button("Allow…", action: ask).controlSize(.small) }
        }
    }
}
