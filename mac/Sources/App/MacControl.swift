import Foundation
import AppKit

// =====================================================================
// MARK: - Mac control agent
// "shut down the mac", "restart", "sleep", "lock", "turn off wifi", "bluetooth on",
// "brightness up", "hide everything", "put chrome on the left", "close this window",
// "run shortcut Morning", "type hello"… Anything that can't be undone waits 10 s
// and can be cancelled by saying "cancel".
// =====================================================================

@MainActor
final class MacControl {
    static let shared = MacControl()

    private var pending: DispatchWorkItem?
    private var pendingLabel = ""

    var hasPending: Bool { pending != nil }

    func handle(_ raw: String) -> String? {
        var t = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        t = t.replacingOccurrences(of: #"^((hey|hi|ok)\s+)?(sparrow[, ]*)?(please |can you |could you |would you |kindly |just )*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+(please|now|right now|for me)$"#, with: "", options: .regularExpression)
        let has = { (re: String) in t.range(of: re, options: .regularExpression) != nil }
        let machine = #"(the |my |this )?(mac|macbook|computer|laptop|system|pc)"#

        // Cancel a countdown
        if pending != nil, has(#"^(cancel|stop|don'?t|do not|no|wait|abort|ruko|ruk jao|mat karo|nahi|nahin|cancel it|stop it)\b"#) {
            pending?.cancel(); pending = nil
            return "Okay, cancelled — I won't \(pendingLabel)."
        }

        // Power
        if has("^(shut ?down|shut off|turn off|power off|switch off|quit|close)\\s+\(machine)$") || has(#"^(shut ?down|power off)$"#) {
            return countdown("shut down your Mac", script: "tell application \"System Events\" to shut down")
        }
        if has("^(restart|reboot)(\\s+\(machine))?$") {
            return countdown("restart your Mac", script: "tell application \"System Events\" to restart")
        }
        if has("^(log ?out|sign out)(\\s+\(machine))?$|^log me out$") {
            return countdown("log you out", script: "tell application \"System Events\" to log out")
        }
        if has("^(sleep|put\\s+\(machine)\\s+to sleep|\(machine)\\s+(to )?sleep|sleep\\s+\(machine)|go to sleep mac)$") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { _ = MacControl.run("/usr/bin/pmset", ["sleepnow"]) }
            return "Putting your Mac to sleep. Good night!"
        }
        if has("^(lock|lock\\s+\(machine)|lock (the )?screen|lock it)$") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { MainActor.assumeIsolated {
                // Ctrl-Cmd-Q = Lock Screen (needs Accessibility); otherwise sleep the display, which locks it too.
                if CommandEngine.shared.runAppleScript("tell application \"System Events\" to keystroke \"q\" using {control down, command down}") == nil {
                    MacControl.run("/usr/bin/pmset", ["displaysleepnow"])
                }
            } }
            return "Locking your Mac."
        }
        if has(#"^(turn off|switch off|sleep) (the )?(screen|display|monitor)$"#) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { _ = MacControl.run("/usr/bin/pmset", ["displaysleepnow"]) }
            return "Turning off the screen."
        }

        let switching = has(#"\b(turn|switch|enable|disable|disconnect|connect|band|chalu|chalao|karo|kar do)\b"#) || t.hasSuffix(" on") || t.hasSuffix(" off")
        // Wi-Fi
        if switching, has(#"\b(wi-?fi|wifi|wireless)\b"#) {
            if has(#"\b(off|disable|disconnect|band)\b"#) { return wifi(false) }
            if has(#"\b(on|enable|connect|chalu|chalao)\b"#) { return wifi(true) }
        }
        // Bluetooth
        if switching, has(#"\bbluetooth\b"#) {
            if has(#"\b(off|disable|band)\b"#) { return Bluetooth.set(false) ? "Bluetooth is off." : openPane("com.apple.BluetoothSettings", "Bluetooth") }
            if has(#"\b(on|enable|chalu|chalao)\b"#) { return Bluetooth.set(true) ? "Bluetooth is on." : openPane("com.apple.BluetoothSettings", "Bluetooth") }
        }
        // Brightness
        if has(#"\bbrightness\b|\b(screen|display) (brighter|darker|dimmer)\b|^(brighter|dimmer|darker)$"#) {
            let up = has(#"\b(up|increase|brighter|raise|more|full|max)\b"#)
            let steps = has(#"\b(full|max|maximum)\b"#) ? 16 : has(#"\b(min|minimum|lowest)\b"#) ? 16 : 4
            let code = up ? 144 : 145
            _ = CommandEngine.shared.runAppleScript("tell application \"System Events\" to repeat \(steps) times\nkey code \(code)\nend repeat")
            return up ? "Brighter." : "Dimmer."
        }
        // Do Not Disturb / Focus (via the person's Shortcuts if they have one)
        if has(#"\b(do not disturb|dnd|focus mode|focus)\b"#) {
            let on = !has(#"\b(off|disable|stop)\b"#)
            for name in on ? ["Do Not Disturb On", "Turn On Do Not Disturb", "Focus On", "DND On"] : ["Do Not Disturb Off", "Turn Off Do Not Disturb", "Focus Off", "DND Off"] {
                if Self.runShortcut(name) { return on ? "Do Not Disturb is on." : "Do Not Disturb is off." }
            }
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension")!)
            return "I opened Focus settings. Tip: make a Shortcut called “Do Not Disturb On” and I'll switch it for you next time."
        }

        // Apps & windows
        if has(#"^(hide|minimi[sz]e) (everything|all|all apps|all windows)$|^(show|clear) (the )?desktop$|^(clean|empty|clear) (my |the )?screen$"#) {
            _ = CommandEngine.shared.runAppleScript("tell application \"System Events\" to set visible of every process whose visible is true and name is not \"Finder\" to false")
            return "All clear — everything is hidden."
        }
        if let m = first(#"^hide (.+)$"#, t), let app = runningApp(m) {
            app.hide(); return "Hid \(app.localizedName ?? m)."
        }
        if has(#"^(close|shut) (this|the) (window|tab)$|^close (window|tab)$"#) { return keys(has("tab") ? "w" : "w", ["command"], "Closed.") }
        if has(#"^(new|open a new|open new) tab$"#) { return keys("t", ["command"], "New tab.") }
        if has(#"^(minimi[sz]e|minimi[sz]e this|minimi[sz]e (this|the) window)$"#) { return keys("m", ["command"], "Minimised.") }
        if has(#"^(quit|close) (this|the current) (app|application)$"#) {
            if let a = NSWorkspace.shared.frontmostApplication, a.bundleIdentifier != Bundle.main.bundleIdentifier { a.terminate(); return "Closed \(a.localizedName ?? "it")." }
        }
        if has(#"^(full ?screen|make (it|this) full ?screen|maximi[sz]e( this)?( window)?)$"#) { return keys("f", ["control", "command"], "Full screen.") }
        // "put chrome on the left (and notes on the right)", "chrome left half", "split screen chrome and notes"
        if let r = splitScreen(t) { return r }

        // Shortcuts
        if let name = first(#"^(?:run|start|do) (?:the |my )?shortcut (.+)$"#, t) ?? first(#"^(?:run|start) (.+?) shortcut$"#, t) {
            return Self.runShortcut(name) ? "Ran your “\(name.capitalized)” shortcut." : "I couldn't find a Shortcut called “\(name)”."
        }
        // Typing
        let spoken = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^(?i)(hey |ok )?sparrow[, ]*"#, with: "", options: .regularExpression)
        if let text = first(#"^(?:type|likho)\s+(.+)$"#, spoken) {
            let esc = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            if let front = AppState.shared.lastExternalApp { front.activate(options: .activateIgnoringOtherApps) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated {
                _ = CommandEngine.shared.runAppleScript("tell application \"System Events\" to keystroke \"\(esc)\"")
            } }
            return "Typing it now."
        }
        // Screenshot of the whole screen to the Desktop
        if has(#"^(take a |take )?(full )?screenshot( of (the )?(whole |full )?screen)?( to (the )?desktop)?$"#) && has(#"whole|full|desktop"#) {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Sparrow screenshot \(f.string(from: Date())).png").path
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { _ = MacControl.run("/usr/sbin/screencapture", ["-x", path]) }
            return "Screenshot saved to your Desktop."
        }
        return nil
    }

    /// Is this a Mac-control request? (used by hands-free listening)
    func matches(_ raw: String) -> Bool {
        let t = raw.lowercased()
        let words = ["shut down", "shutdown", "shut off", "restart", "reboot", "log out", "sleep", "lock", "wifi", "wi-fi", "bluetooth",
                     "brightness", "do not disturb", "hide everything", "show desktop", "full screen", "split screen", "shortcut", "screenshot"]
        return words.contains { t.contains($0) } || (pending != nil && t.count < 30)
    }

    // MARK: helpers

    private func countdown(_ label: String, script: String) -> String {
        pending?.cancel()
        pendingLabel = label
        let item = DispatchWorkItem {
            MainActor.assumeIsolated {
                MacControl.shared.pending = nil
                if CommandEngine.shared.runAppleScript(script) == nil {
                    AppState.shared.noteMessage = "I need permission to control System Events: System Settings → Privacy & Security → Automation → Zuffi."
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                }
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
        return "Okay — I'll \(label) in 10 seconds. Say “cancel” to stop."
    }

    private func wifi(_ on: Bool) -> String {
        guard let dev = Self.wifiDevice() else { return "I couldn't find Wi-Fi on this Mac." }
        let ok = Self.run("/usr/sbin/networksetup", ["-setairportpower", dev, on ? "on" : "off"])
        return ok ? (on ? "Wi-Fi is on." : "Wi-Fi is off.") : openPane("com.apple.wifi-settings-extension", "Wi-Fi")
    }

    private func openPane(_ id: String, _ name: String) -> String {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(id)")!)
        return "macOS didn't let me switch \(name) directly, so I opened its settings for you."
    }

    private func keys(_ key: String, _ mods: [String], _ reply: String) -> String {
        if let front = AppState.shared.lastExternalApp { front.activate(options: .activateIgnoringOtherApps) }
        let using = mods.map { "\($0) down" }.joined(separator: ", ")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { MainActor.assumeIsolated {
            _ = CommandEngine.shared.runAppleScript("tell application \"System Events\" to keystroke \"\(key)\" using {\(using)}")
        } }
        return reply
    }

    private func runningApp(_ name: String) -> NSRunningApplication? {
        let q = name.lowercased().replacingOccurrences(of: #"^(the |my )"#, with: "", options: .regularExpression)
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        return apps.first { ($0.localizedName ?? "").lowercased() == q } ?? apps.first { ($0.localizedName ?? "").lowercased().contains(q) }
    }

    private func splitScreen(_ t: String) -> String? {
        var pairs: [(String, String)] = []
        if let m = try? NSRegularExpression(pattern: #"^(?:split screen|side by side)\s+(.+?)\s+and\s+(.+)$"#).firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
           let a = Range(m.range(at: 1), in: t), let b = Range(m.range(at: 2), in: t) {
            pairs = [(String(t[a]), "left"), (String(t[b]), "right")]
        } else {
            let re = try! NSRegularExpression(pattern: #"(?:put |move )?([a-z0-9 .]+?)\s+(?:on |to )?(?:the )?(left|right)(?: side| half)?"#)
            for m in re.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                if let a = Range(m.range(at: 1), in: t), let b = Range(m.range(at: 2), in: t) {
                    let name = String(t[a]).replacingOccurrences(of: #"^(and |then )"#, with: "", options: .regularExpression)
                    pairs.append((name, String(t[b])))
                }
            }
            guard t.hasPrefix("put ") || t.hasPrefix("move ") || t.contains(" half") || t.contains(" side") else { return nil }
        }
        guard !pairs.isEmpty, let screen = NSScreen.main else { return nil }
        let vf = screen.visibleFrame, full = screen.frame
        let top = Int(full.maxY - vf.maxY), w = Int(vf.width / 2), h = Int(vf.height), x0 = Int(vf.minX)
        var done: [String] = []
        for (name, side) in pairs {
            guard let app = runningApp(name.trimmingCharacters(in: .whitespaces)) ?? openAndWait(name) else { continue }
            let proc = app.localizedName ?? name
            let x = side == "left" ? x0 : x0 + w
            let script = """
            tell application "System Events" to tell process "\(proc)"
              set frontmost to true
              set position of window 1 to {\(x), \(top)}
              set size of window 1 to {\(w), \(h)}
            end tell
            """
            if CommandEngine.shared.runAppleScript(script) != nil { done.append("\(proc) \(side)") }
        }
        if done.isEmpty { return "I need Accessibility permission to move windows: System Settings → Privacy & Security → Accessibility → Zuffi." }
        return "Done: " + done.joined(separator: ", ") + "."
    }

    private func openAndWait(_ name: String) -> NSRunningApplication? { nil }

    private func first(_ pattern: String, _ s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: s) else { return nil }
        return String(s[r]).trimmingCharacters(in: .whitespaces)
    }

    @discardableResult
    nonisolated static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    nonisolated static func output(_ path: String, _ args: [String]) -> String {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: path); p.arguments = args; p.standardOutput = pipe
        guard (try? p.run()) != nil else { return "" }
        p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    nonisolated static func wifiDevice() -> String? {
        let out = output("/usr/sbin/networksetup", ["-listallhardwareports"])
        let lines = out.components(separatedBy: "\n")
        for (i, l) in lines.enumerated() where l.contains("Wi-Fi") || l.contains("AirPort") {
            if i + 1 < lines.count, let r = lines[i + 1].range(of: "Device: ") { return String(lines[i + 1][r.upperBound...]).trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    nonisolated static func runShortcut(_ name: String) -> Bool {
        let list = output("/usr/bin/shortcuts", ["list"]).components(separatedBy: "\n")
        guard let hit = list.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { return false }
        return run("/usr/bin/shortcuts", ["run", hit])
    }
}

/// Bluetooth power using the same system call as the popular `blueutil` tool.
enum Bluetooth {
    private typealias Setter = @convention(c) (Int32) -> Int32
    static func set(_ on: Bool) -> Bool {
        guard let h = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY),
              let sym = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") else { return false }
        let f = unsafeBitCast(sym, to: Setter.self)
        _ = f(on ? 1 : 0)
        return true
    }
}
