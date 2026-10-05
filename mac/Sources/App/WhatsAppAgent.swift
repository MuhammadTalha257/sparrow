import Foundation
import AppKit
import ApplicationServices

// =====================================================================
// MARK: - WhatsApp agent
//   "any new WhatsApp messages?"                → how many, and who (from WhatsApp's own chat list)
//   "WhatsApp Ahmed saying I'm on my way"        → a draft, shown + read out
//   "reply to Ahmed on WhatsApp: see you at 6"   → same
//   "send" → Sparrow opens the chat with the text and presses Enter · "change it…" · "cancel"
// WhatsApp has no official Mac API, so Sparrow uses what the Mac offers: the
// whatsapp:// link to open a chat with text, and Accessibility (the same
// permission Sparrow uses for typing) to read the chat list and press Send.
// Nothing is ever sent without "send".
// =====================================================================

@MainActor
final class WhatsAppAgent {
    static let shared = WhatsAppAgent()

    struct Draft { let name: String; let phone: String; var text: String; let made: Date }
    private(set) var draft: Draft?
    private var lastName: String?

    func dropDraft() { draft = nil }

    private static let checkRE = #"^(?:check|read|show|open)?\s*(?:my |any |the |new |unread |latest )*(?:whats ?app|whatsapp)(?: messages?| chats?| texts?)?(?:\s+(?:messages?|now|today))?\??$|^(?:any|do i have|have i got|got any)\s+(?:new |unread )*(?:whats ?app|whatsapp)(?: messages?| chats?)?\??$|^(?:any )?(?:new |unread )*(?:messages?|msgs?) (?:on|in) (?:whats ?app|whatsapp)\??$|^who (?:messaged|texted) me(?: on whats ?app)?\??$"#
    private static let sendRE = #"^(?:send\s+)?(?:a\s+)?(?:whats ?app|whatsapp|message|msg|text|reply(?: to)?|respond to|write to|tell)\s+(?:to\s+)?(.+?)(?:\s+(?:on|via|in) (?:whats ?app|whatsapp))?\s*(?:saying|that|and say|and tell (?:him|her|them)|to say|ke|keh do|bolo|:|,)\s*(.+)$"#

    private static func clean(_ raw: String, keepCase: Bool = false) -> String {
        let s = Translit.toCommand(raw)
            .replacingOccurrences(of: #"^(?:can you|could you|please|will you)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        return keepCase ? s : s.lowercased()
    }
    private static func mentionsWA(_ t: String) -> Bool { t.contains("whatsapp") || t.contains("whats app") }

    func claims(_ raw: String) -> Bool {
        let t = Self.clean(raw)
        if draft != nil, Self.isSend(t) || Self.isCancel(t) || Self.isChange(t) != nil { return true }
        if t.range(of: Self.checkRE, options: .regularExpression) != nil { return true }
        // "WhatsApp Ahmed saying…", "message Ahmed on WhatsApp…", or a reply right after Sparrow read out WhatsApp chats
        if t.range(of: Self.sendRE, options: .regularExpression) != nil {
            return Self.mentionsWA(t) || (AgentRouter.lastChannel == .whatsapp && t.hasPrefix("reply"))
        }
        return false
    }

    func handle(_ raw: String) async -> String? {
        let t = Self.clean(raw), o = Self.clean(raw, keepCase: true)
        if let d = draft, Date().timeIntervalSince(d.made) > 600 { draft = nil }
        if let d = draft {
            if Self.isSend(t) { return await send(d) }
            if Self.isCancel(t) { draft = nil; return "Okay, I won't send it." }
            if Self.isChange(t) != nil, let change = Self.isChange(o) { return await redraft(d, change) }
        }
        if t.range(of: Self.checkRE, options: .regularExpression) != nil { return await checkNew() }
        guard let m = Self.match(Self.sendRE, o) else { return nil }
        var who = m[0].replacingOccurrences(of: #"\s+(?:on|via|in) (?:whats ?app|whatsapp)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        if ["him", "her", "them", "back", "it"].contains(who.lowercased()), let l = lastName { who = l }
        return await makeDraft(to: who, saying: m[1])
    }

    // MARK: Reading

    func checkNew() async -> String {
        AgentRouter.lastChannel = .whatsapp
        guard NSWorkspace.shared.runningApplications.contains(where: Self.isWhatsApp) else {
            return "WhatsApp isn't open. Say \"open WhatsApp\" and ask me again."
        }
        guard AXIsProcessTrusted() else {
            // Shows macOS's own prompt (and adds Sparrow to the list if it isn't there).
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            return "macOS hasn't given me Accessibility yet. In System Settings → Privacy & Security → Accessibility, select Sparrow, press the minus button to remove it, then quit and reopen Sparrow and allow it again. After an update macOS keeps the old switch, which no longer counts."
        }
        let badge = await Self.dockBadge()
        let rows = await Self.unreadRows()
        if rows.isEmpty {
            if let b = badge, let n = Int(b), n > 0 { return "You have \(n) unread WhatsApp message\(n == 1 ? "" : "s"). Open WhatsApp to see who." }
            return "No new WhatsApp messages. All caught up! ✨"
        }
        lastName = rows.first?.name
        VoiceEngine.shared.listenAfterSpeech = true
        let head = badge.flatMap(Int.init).map { "You have \($0) unread WhatsApp message\($0 == 1 ? "" : "s")." } ?? "New on WhatsApp:"
        let list = rows.prefix(5).map { r in r.preview.isEmpty ? "\(r.name)." : "\(r.name): \(r.preview.prefix(90))." }.joined(separator: " ")
        return "\(head) \(list) Want to reply to anyone?"
    }

    // MARK: Writing

    private func makeDraft(to who: String, saying what: String) async -> String {
        AgentRouter.lastChannel = .whatsapp
        let phone = await Self.phone(for: who)
        guard !phone.isEmpty else {
            return "I don't have a number for \(who.capitalized). Say \"save \(who) number 0300…\" and try again."
        }
        lastName = who
        var text = what.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"^(?:tell|let) (?:him|her|them)(?: know)?(?: that)?\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: #"\bi\b"#, with: "I", options: .regularExpression)
        if let f = text.first { text = f.uppercased() + text.dropFirst() }
        MailAgent.shared.dropDraft()
        draft = Draft(name: who.capitalized, phone: phone, text: text, made: Date())
        return present(draft!)
    }

    private func redraft(_ d: Draft, _ change: String) async -> String {
        var text = d.text
        if SmartPlanner.shared.isAvailable,
           let s = await SmartPlanner.shared.complete("Rewrite this WhatsApp message as asked. Keep it short and natural, like a real chat message. Return ONLY the message.\nRequest: \(change)\nMessage: \(d.text)") {
            text = s.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        } else if let extra = Self.match(#"^(?:also (?:say|tell|add|mention)|add)\s+(?:that\s+)?(.+)$"#, change)?.first {
            text += " " + extra
        }
        draft = Draft(name: d.name, phone: d.phone, text: text, made: Date())
        return present(draft!)
    }

    private func present(_ d: Draft) -> String {
        VoiceEngine.shared.listenAfterSpeech = true
        return "WhatsApp to \(d.name): \"\(d.text)\". Say send, tell me what to change, or cancel."
    }

    private func send(_ d: Draft) async -> String {
        let enc = d.text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? d.text
        guard let url = URL(string: "whatsapp://send?phone=\(d.phone)&text=\(enc)") else { return "I couldn't open WhatsApp." }
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            return "WhatsApp isn't installed on this Mac. Get it from the App Store, then try again."
        }
        draft = nil
        NSWorkspace.shared.open(url)
        // Give WhatsApp time to open the chat and fill in the text, then press Enter.
        guard AXIsProcessTrusted() else { return "Your message to \(d.name) is ready in WhatsApp. Press Enter to send it." }
        try? await Task.sleep(nanoseconds: NSWorkspace.shared.runningApplications.contains(where: Self.isWhatsApp) ? 1_600_000_000 : 4_500_000_000)
        if let app = NSWorkspace.shared.runningApplications.first(where: Self.isWhatsApp) {
            app.activate(options: [])
            try? await Task.sleep(nanoseconds: 350_000_000)
            Self.pressReturn()
            appendAppLog("agents.log", "whatsapp: sent to \(d.name)")
            return "Sent to \(d.name) on WhatsApp! ✅"
        }
        return "Your message to \(d.name) is ready in WhatsApp. Press Enter to send it."
    }

    // MARK: Words (shared with the mail agent's style)

    private static func isSend(_ t: String) -> Bool {
        t.range(of: #"^(?:yes|yeah|yep|ok|okay|sure|perfect|great|good)?[, ]*(?:send|send it|send that|send now|send the message|go ahead|looks good|bhej do|bhejo|bhej de|send kar do|send karo|haan bhej do|haan|ji haan|भेज दो|بھیج دو)$|^(?:yes|yeah|yep|haan)$"#, options: .regularExpression) != nil
    }
    private static func isCancel(_ t: String) -> Bool {
        t.range(of: #"^(?:no|nope|cancel|cancel it|don'?t send(?: it)?|do not send|never ?mind|forget it|discard(?: it)?|rehne do|mat bhejo|nahi|nahin|नहीं|نہیں)$"#, options: .regularExpression) != nil
    }
    private static func isChange(_ t: String) -> String? {
        if let m = match(#"^(?:change it|change that|edit it|rewrite it)[:, ]*(?:to |so (?:that )?)?(.*)$"#, t) { return m[0].isEmpty ? "make it a bit better" : m[0] }
        if t.range(of: #"^(?:make it|also (?:say|tell|add|mention|ask)|add (?:that|a line|something)|mention|shorter|longer|more (?:formal|casual|polite|friendly)|(?:write it |say it )?in (?:urdu|english|hindi|punjabi|roman urdu)|translate|add an? emoji)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return t }
        return nil
    }
    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        return (1..<max(1, m.numberOfRanges)).map { m.range(at: $0).location == NSNotFound ? "" : (s as NSString).substring(with: m.range(at: $0)).trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Numbers

    /// The contact's number in WhatsApp's international form (digits only, with country code).
    private static func phone(for who: String) async -> String {
        let raw: String
        if who.filter(\.isNumber).count >= 7 { raw = who } else { raw = await ContactsAgent.shared.number(for: who) ?? "" }
        var d = raw.filter { $0.isNumber || $0 == "+" }
        if d.isEmpty { return "" }
        if d.hasPrefix("+") { return String(d.dropFirst()) }
        if d.hasPrefix("00") { return String(d.dropFirst(2)) }
        if d.hasPrefix("0") {
            let codes = ["PK": "92", "GB": "44", "IN": "91", "US": "1", "CA": "1", "AE": "971", "SA": "966", "BD": "880", "TR": "90", "DE": "49", "FR": "33", "AU": "61"]
            let cc = codes[Locale.current.region?.identifier ?? "PK"] ?? "92"
            d = cc + d.dropFirst()
        }
        return d
    }

    // MARK: The Mac side (Accessibility)

    nonisolated static func isWhatsApp(_ a: NSRunningApplication) -> Bool {
        (a.bundleIdentifier ?? "").lowercased().contains("whatsapp") || a.localizedName == "WhatsApp"
    }

    nonisolated private static func pressReturn() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 36, keyDown: false)
        down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
    }

    nonisolated private static func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    nonisolated private static func str(_ e: AXUIElement, _ name: String) -> String? {
        (attr(e, name) as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
    nonisolated private static func children(_ e: AXUIElement) -> [AXUIElement] {
        (attr(e, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
    }

    /// The red number on WhatsApp's Dock icon.
    nonisolated static func dockBadge() async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { cont.resume(returning: nil); return }
                var queue = [AXUIElementCreateApplication(dock.processIdentifier)], seen = 0
                while !queue.isEmpty && seen < 400 {
                    let e = queue.removeFirst(); seen += 1
                    if let title = str(e, kAXTitleAttribute as String), title.lowercased().contains("whatsapp") {
                        cont.resume(returning: str(e, "AXStatusLabel")); return
                    }
                    queue += children(e)
                }
                cont.resume(returning: nil)
            }
        }
    }

    struct Row: Sendable { let name: String; let preview: String }

    /// Unread chats from WhatsApp's chat list: rows whose spoken description mentions "unread".
    nonisolated static func unreadRows() async -> [Row] {
        await withCheckedContinuation { (cont: CheckedContinuation<[Row], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let app = NSWorkspace.shared.runningApplications.first(where: isWhatsApp) else { cont.resume(returning: []); return }
                var queue = [AXUIElementCreateApplication(app.processIdentifier)], seen = 0
                var rows: [Row] = [], used = Set<String>()
                while !queue.isEmpty && seen < 5000 && rows.count < 8 {
                    let e = queue.removeFirst(); seen += 1
                    let label = [str(e, kAXDescriptionAttribute as String), str(e, kAXTitleAttribute as String), str(e, kAXValueAttribute as String),
                                 str(e, "AXLabel")].compactMap { $0 }.joined(separator: ", ")
                    if label.lowercased().contains("unread"), label.count > 12, let row = parse(label), !used.contains(row.name) {
                        used.insert(row.name); rows.append(row); continue
                    }
                    queue += children(e)
                }
                cont.resume(returning: rows)
            }
        }
    }

    /// "Ahmed Khan, Are you coming?, 2:31 PM, 3 unread messages" → name + preview (best effort across WhatsApp versions).
    nonisolated private static func parse(_ label: String) -> Row? {
        let parts = label.components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let noise = #"unread|^\d{1,2}[:.]\d{2}|^(yesterday|today|monday|tuesday|wednesday|thursday|friday|saturday|sunday)$|^\d+/\d+/\d+$|^(message|chat|pinned|muted|typing…?|online|delivered|read|sent)$|^\d+$"#
        let useful = parts.filter { $0.range(of: noise, options: [.regularExpression, .caseInsensitive]) == nil }
        guard let name = useful.first, name.count <= 60 else { return nil }
        return Row(name: name, preview: useful.dropFirst().first ?? "")
    }
}
