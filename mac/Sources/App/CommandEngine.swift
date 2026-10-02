import Foundation
import AppKit
import IOKit.ps

/// Understands everyday commands ("open Spotify", "volume 40", "pause music"…)
/// instantly and offline — no AI model and no API key needed.
@MainActor
final class CommandEngine {
    static let shared = CommandEngine()

    // MARK: Entry

    func handle(_ raw: String) async -> String? {
        var text = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        // Drop polite / wake-word prefixes ("hey sparrow, please open…")
        let fillers = ["hey sparrow", "hi sparrow", "ok sparrow", "sparrow", "please", "can you", "could you",
                       "would you", "will you", "kindly", "i want to", "i'd like to", "i need to", "just", ","]
        var changed = true
        while changed {
            changed = false
            for f in fillers where text.hasPrefix(f + " ") || text.hasPrefix(f + ",") || text == f {
                text = String(text.dropFirst(f.count)).trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
                changed = true
            }
        }
        if text.hasSuffix(" please") { text = String(text.dropLast(7)) }
        guard !text.isEmpty else { return nil }

        if ["help", "what can you do", "commands", "what can i say"].contains(text) { return helpText }

        // Meetings, reminders, tasks, notes → Calendar / Reminders / Notes
        if let r = await Planner.shared.handle(raw) { return r }

        // Media
        if let r = media(text) { return r }
        // Volume
        if let r = volume(text) { return r }
        // Web searches
        if let r = search(text) { return r }
        // Quit apps
        for p in ["quit ", "close ", "exit ", "kill "] where text.hasPrefix(p) {
            return quit(String(text.dropFirst(p.count)))
        }
        // Open apps / sites / folders / settings
        for p in ["open ", "launch ", "start ", "run ", "go to ", "show me ", "show "] where text.hasPrefix(p) {
            return open(String(text.dropFirst(p.count)))
        }
        // System
        if let r = system(text) { return r }
        return nil
    }

    private let helpText = """
    Things I can do instantly, no setup needed:
    • meeting with Ali Friday 3pm → your Calendar
    • remind me to call mum at 6pm tomorrow → your Reminders
    • add task buy milk · note wifi password is 1234 → Notes
    • what's on today? · my tasks · done buy milk
    • open Spotify / open Gmail / open Downloads / open github.com
    • quit Chrome
    • play, pause, next song, previous song, play lofi on Spotify
    • volume 40 / volume up / mute
    • search best pizza near me / youtube cat videos
    • battery / what time is it / today's date
    • lock screen / dark mode / bluetooth settings
    For anything else, just ask. Your chosen AI answers.
    """

    /// Cheap check used by voice to decide how long to wait before acting.
    func looksLikeCommand(_ t: String) -> Bool {
        let starts = ["open ", "launch ", "start ", "quit ", "close ", "play", "pause", "stop music", "next", "previous",
                      "skip", "volume", "mute", "unmute", "louder", "quieter", "search ", "google ", "youtube ",
                      "lock", "dark mode", "light mode", "battery", "time", "what time", "date", "screenshot", "go to ",
                      "remind me", "add task", "task ", "note ", "take a note", "meeting", "what's on", "my day", "done "]
        return starts.contains { t.hasPrefix($0) }
    }

    // MARK: Open

    private static let websites: [String: String] = [
        "gmail": "https://mail.google.com", "google mail": "https://mail.google.com", "email": "https://mail.google.com",
        "youtube": "https://www.youtube.com", "google": "https://www.google.com",
        "google drive": "https://drive.google.com", "drive": "https://drive.google.com",
        "google docs": "https://docs.google.com", "google sheets": "https://sheets.google.com",
        "google calendar": "https://calendar.google.com", "google maps": "https://maps.google.com", "maps web": "https://maps.google.com",
        "github": "https://github.com", "gitlab": "https://gitlab.com", "stackoverflow": "https://stackoverflow.com",
        "chatgpt": "https://chatgpt.com", "gemini": "https://gemini.google.com", "claude web": "https://claude.ai",
        "perplexity web": "https://www.perplexity.ai",
        "facebook": "https://www.facebook.com", "instagram": "https://www.instagram.com", "twitter": "https://x.com",
        "x": "https://x.com", "linkedin": "https://www.linkedin.com", "reddit": "https://www.reddit.com",
        "tiktok": "https://www.tiktok.com", "netflix": "https://www.netflix.com", "amazon": "https://www.amazon.co.uk",
        "whatsapp web": "https://web.whatsapp.com", "outlook web": "https://outlook.live.com",
        "notion web": "https://www.notion.so", "figma": "https://www.figma.com", "canva": "https://www.canva.com",
        "vercel": "https://vercel.com/dashboard", "bbc": "https://www.bbc.co.uk", "wikipedia": "https://www.wikipedia.org",
    ]

    private static let appAliases: [String: String] = [
        "vs code": "visual studio code", "vscode": "visual studio code", "code": "visual studio code",
        "settings": "system settings", "system preferences": "system settings", "preferences": "system settings",
        "chrome": "google chrome", "brave": "brave browser", "word": "microsoft word", "excel": "microsoft excel",
        "powerpoint": "microsoft powerpoint", "outlook": "microsoft outlook", "teams": "microsoft teams",
        "onenote": "microsoft onenote", "zoom": "zoom.us", "files": "finder", "app store": "app store",
        "photos": "photos", "camera": "photo booth", "calculator": "calculator", "notes": "notes",
        "messages": "messages", "imessage": "messages", "facetime": "facetime", "calendar": "calendar",
        "reminders": "reminders", "terminal": "terminal", "activity monitor": "activity monitor",
        "task manager": "activity monitor", "whatsapp": "whatsapp", "music": "music", "apple music": "music",
        "mail": "mail", "safari": "safari", "maps": "maps", "claude": "claude", "spotify": "spotify",
        // common speech-recognition mishearings
        "cloud": "claude", "clode": "claude", "clawed": "claude", "cloud app": "claude", "crome": "google chrome",
        "spot if i": "spotify", "what's app": "whatsapp", "whats app": "whatsapp", "vs": "visual studio code",
        "v s code": "visual studio code", "fine der": "finder", "safety": "safari",
    ]

    private static let settingsPanes: [String: String] = [
        "wifi": "com.apple.wifi-settings-extension", "wi-fi": "com.apple.wifi-settings-extension",
        "bluetooth": "com.apple.BluetoothSettings", "sound": "com.apple.Sound-Settings.extension",
        "display": "com.apple.Displays-Settings.extension", "displays": "com.apple.Displays-Settings.extension",
        "battery": "com.apple.Battery-Settings.extension", "notifications": "com.apple.Notifications-Settings.extension",
        "privacy": "com.apple.settings.PrivacySecurity.extension", "security": "com.apple.settings.PrivacySecurity.extension",
        "keyboard": "com.apple.Keyboard-Settings.extension", "network": "com.apple.Network-Settings.extension",
        "wallpaper": "com.apple.Wallpaper-Settings.extension", "login items": "com.apple.LoginItems-Settings.extension",
    ]

    private func open(_ rawTarget: String) -> String {
        var target = rawTarget.trimmingCharacters(in: .whitespaces)
        for a in ["the ", "my ", "app ", "application "] where target.hasPrefix(a) { target = String(target.dropFirst(a.count)) }
        for s in [" app", " application", " please"] where target.hasSuffix(s) { target = String(target.dropLast(s.count)) }
        guard !target.isEmpty else { return "Open what? Try \"open Spotify\"." }

        // Settings panes: "bluetooth settings", "wifi settings"
        if target.hasSuffix(" settings") || target.hasSuffix(" preferences") {
            let pane = target.replacingOccurrences(of: " settings", with: "").replacingOccurrences(of: " preferences", with: "")
            if let id = Self.settingsPanes[pane], let url = URL(string: "x-apple.systempreferences:\(id)") {
                NSWorkspace.shared.open(url)
                return "Opening \(pane.capitalized) settings."
            }
        }

        // Folders
        let fm = FileManager.default
        let folders: [String: URL?] = [
            "downloads": fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            "documents": fm.urls(for: .documentDirectory, in: .userDomainMask).first,
            "desktop": fm.urls(for: .desktopDirectory, in: .userDomainMask).first,
            "pictures": fm.urls(for: .picturesDirectory, in: .userDomainMask).first,
            "movies": fm.urls(for: .moviesDirectory, in: .userDomainMask).first,
            "home": fm.homeDirectoryForCurrentUser, "home folder": fm.homeDirectoryForCurrentUser,
            "applications": URL(fileURLWithPath: "/Applications"),
            "trash": fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"),
        ]
        let folderKey = target.replacingOccurrences(of: " folder", with: "")
        if let entry = folders[folderKey], let url = entry {
            NSWorkspace.shared.open(url)
            return "Opening your \(folderKey.capitalized) folder."
        }

        // Explicit web wording: "gmail website", "youtube in browser"
        var webOnly = false
        for s in [" website", " site", " in browser", " in the browser", " web"] where target.hasSuffix(s) {
            target = String(target.dropLast(s.count)); webOnly = true
        }

        // Installed apps
        if !webOnly, let app = findApp(target) {
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: app.url, configuration: cfg, completionHandler: nil)
            return "Opening \(app.name)."
        }

        // Known websites
        if let site = Self.websites[target] ?? Self.websites[target + " web"], let url = URL(string: site) {
            NSWorkspace.shared.open(url)
            return "Opening \(target.capitalized) in your browser."
        }

        // Anything that looks like a domain
        if target.contains("."), !target.contains(" ") {
            let s = target.hasPrefix("http") ? target : "https://" + target
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
                return "Opening \(target)."
            }
        }

        return "I couldn't find \"\(rawTarget)\" on your Mac. Check the name, or say \"search \(rawTarget)\"."
    }

    private struct FoundApp { let name: String; let url: URL }

    struct AppEntry: Hashable { let name: String; let url: URL }

    /// Every installed app, A–Z (for the Settings list).
    func allApps() -> [AppEntry] {
        buildIndex()
        var seenNames = Set<String>()
        return appIndex
            .filter { seenNames.insert($0.key).inserted }
            .map { AppEntry(name: $0.name, url: $0.url) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var appIndex: [(key: String, name: String, url: URL)] = []
    private var indexBuilt = Date.distantPast

    private func buildIndex() {
        guard Date().timeIntervalSince(indexBuilt) > 120 else { return }
        var out: [(key: String, name: String, url: URL)] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications",
                    "/System/Applications/Utilities", home + "/Applications", "/System/Library/CoreServices/Applications"]
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let name = String(item.dropLast(4))
                out.append((key: name.lowercased(), name: name, url: URL(fileURLWithPath: dir).appendingPathComponent(item)))
            }
        }
        // Finder lives outside those folders
        out.append((key: "finder", name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")))
        appIndex = out
        indexBuilt = Date()
    }

    private func findApp(_ query: String) -> FoundApp? {
        buildIndex()
        let q = Self.appAliases[query] ?? query
        if let e = appIndex.first(where: { $0.key == q }) { return FoundApp(name: e.name, url: e.url) }
        if let e = appIndex.first(where: { $0.key.hasPrefix(q) }) { return FoundApp(name: e.name, url: e.url) }
        if q.count >= 3, let e = appIndex.first(where: { $0.key.contains(q) }) { return FoundApp(name: e.name, url: e.url) }
        let squashed = q.replacingOccurrences(of: " ", with: "")
        if let e = appIndex.first(where: { $0.key.replacingOccurrences(of: " ", with: "") == squashed }) {
            return FoundApp(name: e.name, url: e.url)
        }
        return nil
    }

    // MARK: Quit

    private func quit(_ rawTarget: String) -> String {
        var target = rawTarget.trimmingCharacters(in: .whitespaces)
        for a in ["the ", "my "] where target.hasPrefix(a) { target = String(target.dropFirst(a.count)) }
        let q = Self.appAliases[target] ?? target
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
        guard let app = running.first(where: { ($0.localizedName ?? "").lowercased() == q })
                ?? running.first(where: { ($0.localizedName ?? "").lowercased().hasPrefix(q) })
                ?? running.first(where: { q.count >= 3 && ($0.localizedName ?? "").lowercased().contains(q) }) else {
            return "\(rawTarget.capitalized) isn't open."
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return "I'll stay right here. 🐦" }
        _ = app.terminate()
        return "Closing \(app.localizedName ?? rawTarget)."
    }

    // MARK: Media

    private func mediaApp() -> String {
        let running = NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier }
        if running.contains("com.spotify.client") { return "Spotify" }
        if running.contains("com.apple.Music") { return "Music" }
        let hasSpotify = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
        return hasSpotify ? "Spotify" : "Music"
    }

    private func media(_ t: String) -> String? {
        let player = mediaApp()
        // "play lofi on spotify" / "play some jazz"
        if t.hasPrefix("play "), t != "play music", t != "play song", t != "play the music" {
            var q = String(t.dropFirst(5))
            if q.hasSuffix(" on youtube") {
                q = String(q.dropLast(11))
                openURL("https://www.youtube.com/results?search_query=" + enc(q))
                return "Searching YouTube for \(q)."
            }
            q = q.replacingOccurrences(of: " on spotify", with: "").replacingOccurrences(of: " on apple music", with: "")
            for a in ["some ", "a song by ", "songs by ", "music by "] where q.hasPrefix(a) { q = String(q.dropFirst(a.count)) }
            if player == "Spotify", let url = URL(string: "spotify:search:" + enc(q)) {
                NSWorkspace.shared.open(url)
                return "Searching Spotify for \(q). Pick a track to start it."
            }
            openURL("https://music.apple.com/search?term=" + enc(q))
            return "Searching Apple Music for \(q)."
        }
        let actions: [(words: [String], script: String, reply: String)] = [
            (["play", "play music", "play song", "resume", "resume music", "unpause", "play the music"], "play", "Playing."),
            (["pause", "pause music", "stop music", "stop the music", "pause the music", "stop playing"], "pause", "Paused."),
            (["next", "next song", "next track", "skip", "skip song", "skip this song"], "next track", "Next song."),
            (["previous", "previous song", "previous track", "last song", "go back a song"], "previous track", "Previous song."),
        ]
        for a in actions where a.words.contains(t) {
            if runAppleScript("tell application \"\(player)\" to \(a.script)") != nil { return a.reply }
            return "I couldn't control \(player). Allow Sparrow under System Settings → Privacy & Security → Automation."
        }
        if ["what's playing", "what is playing", "what song is this", "current song", "now playing"].contains(t) {
            let script = player == "Spotify"
                ? "tell application \"Spotify\" to if player state is playing then return (name of current track) & \" — \" & (artist of current track)"
                : "tell application \"Music\" to if player state is playing then return (name of current track) & \" — \" & (artist of current track)"
            if let r = runAppleScript(script), !r.isEmpty { return "Now playing: \(r)" }
            return "Nothing is playing right now."
        }
        return nil
    }

    // MARK: Volume

    private func volume(_ t: String) -> String? {
        guard t.contains("volume") || t == "mute" || t == "unmute" || t.hasPrefix("mute ") || t == "louder" || t == "quieter" else { return nil }
        if t == "mute" || t.hasPrefix("mute ") {
            _ = runAppleScript("set volume with output muted"); return "Muted."
        }
        if t == "unmute" {
            _ = runAppleScript("set volume without output muted"); return "Sound back on."
        }
        let current = Int(runAppleScript("output volume of (get volume settings)") ?? "") ?? 50
        var target: Int?
        if let n = t.split(whereSeparator: { !$0.isNumber }).compactMap({ Int($0) }).first { target = n }
        else if t.contains("up") || t == "louder" || t.contains("increase") || t.contains("raise") { target = current + 15 }
        else if t.contains("down") || t == "quieter" || t.contains("decrease") || t.contains("lower") { target = current - 15 }
        else if t.contains("max") || t.contains("full") { target = 100 }
        guard let v = target.map({ max(0, min(100, $0)) }) else { return "The volume is at \(current)%." }
        _ = runAppleScript("set volume without output muted")
        _ = runAppleScript("set volume output volume \(v)")
        return "Volume set to \(v)%."
    }

    // MARK: Search

    private func search(_ t: String) -> String? {
        for p in ["youtube ", "search youtube for ", "search on youtube for ", "find on youtube "] where t.hasPrefix(p) {
            let q = String(t.dropFirst(p.count))
            openURL("https://www.youtube.com/results?search_query=" + enc(q))
            return "Searching YouTube for \(q)."
        }
        for p in ["search for ", "search the web for ", "search ", "google ", "look up ", "find online "] where t.hasPrefix(p) {
            let q = String(t.dropFirst(p.count))
            guard !q.isEmpty else { return nil }
            openURL("https://www.google.com/search?q=" + enc(q))
            return "Searching the web for \(q)."
        }
        return nil
    }

    // MARK: System

    private func system(_ t: String) -> String? {
        if ["battery", "battery level", "how much battery", "battery status", "what's my battery", "how is my battery"].contains(t) {
            return Self.batteryText()
        }
        if ["time", "what time is it", "what's the time", "tell me the time", "current time"].contains(t) {
            let f = DateFormatter(); f.timeStyle = .short
            return "It's \(f.string(from: Date()))."
        }
        if ["date", "what's the date", "what is the date", "today's date", "what day is it", "what's today"].contains(t) {
            let f = DateFormatter(); f.dateStyle = .full
            return "Today is \(f.string(from: Date()))."
        }
        if ["lock", "lock screen", "lock my mac", "lock the screen", "lock computer", "sleep screen", "turn off screen"].contains(t) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            p.arguments = ["displaysleepnow"]
            try? p.run()
            return "Locking the screen."
        }
        if ["dark mode", "light mode", "toggle dark mode", "switch to dark mode", "switch to light mode",
            "turn on dark mode", "turn off dark mode"].contains(t) {
            let value: String
            if t.contains("light") || t.contains("turn off") { value = "false" }
            else if t == "toggle dark mode" { value = "not dark mode" }
            else { value = "true" }
            if runAppleScript("tell application \"System Events\" to tell appearance preferences to set dark mode to \(value)") != nil {
                return value == "false" ? "Light mode on." : "Dark mode on."
            }
            return "I need permission: System Settings → Privacy & Security → Automation → Sparrow → System Events."
        }
        if ["empty trash", "empty the trash"].contains(t) {
            return "To keep your files safe, I won't empty the Trash. You can do it from Finder."
        }
        if ["screenshot", "take a screenshot", "take screenshot", "screen shot"].contains(t) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-i", "-c"]
            try? p.run()
            return "Select an area. The screenshot goes to your clipboard."
        }
        return nil
    }

    static func batteryText() -> String {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return "This computer has no battery."
        }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  let cap = d[kIOPSCurrentCapacityKey as String] as? Int,
                  let max = d[kIOPSMaxCapacityKey as String] as? Int, max > 0 else { continue }
            let pct = cap * 100 / max
            let charging = (d[kIOPSIsChargingKey as String] as? Bool) == true
            let plugged = (d[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue
            var s = "Battery is at \(pct)%"
            if charging { s += " and charging" } else if plugged { s += ", plugged in" }
            if let mins = d[kIOPSTimeToEmptyKey as String] as? Int, mins > 0, !plugged {
                s += ", about \(mins / 60)h \(mins % 60)m left"
            }
            return s + "."
        }
        return "This computer has no battery."
    }

    // MARK: Helpers

    @discardableResult
    func runAppleScript(_ source: String) -> String? {
        var err: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let out = script.executeAndReturnError(&err)
        if err != nil { return nil }
        return out.stringValue ?? ""
    }

    private func openURL(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
    private func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
}
