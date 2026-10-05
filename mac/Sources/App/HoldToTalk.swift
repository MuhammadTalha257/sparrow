import AppKit

/// Hold the right ⌥ Option key anywhere, speak, let go — Sparrow acts on it.
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
        if let l = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { e in handler(e); return e }) { monitors.append(l) }
        // Global key events need Accessibility permission; ask once so the key works everywhere.
        // Ask once (not on every launch) so the key works everywhere.
        let askedBefore = UserDefaults.standard.bool(forKey: "axAsked")
        let opts = ["AXTrustedCheckOptionPrompt": !askedBefore] as CFDictionary
        UserDefaults.standard.set(true, forKey: "axAsked")
        if !AXIsProcessTrustedWithOptions(opts) { appendAppLog("voice.log", "hold-to-talk: waiting for Accessibility permission") }
    }

    private static func flags(code: UInt16, optionDown: Bool) {
        guard UserDefaults.standard.object(forKey: "holdToTalk") as? Bool ?? true, code == rightOption else { return }
        if optionDown && !down { down = true; VoiceEngine.shared.pushToTalkDown() }
        else if !optionDown && down { down = false; VoiceEngine.shared.pushToTalkUp() }
    }
}
