import Foundation
import AppKit
import Contacts

// =====================================================================
// MARK: - Sparrow's agent team
// One router, several specialists. Everything runs on this Mac, offline,
// in milliseconds — no AI model needed for everyday jobs:
//   "open Spotify and play music, then open Notes and save this"
//   "Ali ka number save karo 0300 1234567"  ·  "spotify kholo aur gaana chalao"
// The router understands English plus Roman Urdu / Hindi / Punjabi (and
// Urdu / Hindi script), splits a request into steps and gives each step to
// the right agent: Contacts, Notes, Messages, Music, Apps & System.
// =====================================================================

@MainActor
final class AgentRouter {
    static let shared = AgentRouter()

    /// Handles a request if any agent can. nil = nobody could (the caller asks the AI instead).
    func handle(_ raw: String) async -> String? {
        let steps = split(raw)
        if steps.count <= 1 { return await single(raw) }
        var replies: [String] = []
        var anyDone = false
        for (i, step) in steps.enumerated() {
            var r = await single(step)
            if r == nil { r = await WebHub.shared.ask(step) }
            if let r { replies.append(r); anyDone = true } else { replies.append("I couldn't do \"\(step)\".") }
            // Give an app a moment to open before the next step talks to it.
            if i < steps.count - 1, step.lowercased().hasPrefix("open") || (r ?? "").hasPrefix("Opening") {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
        return anyDone ? replies.joined(separator: " ") : nil
    }

    private func single(_ raw: String) async -> String? {
        let t = Translit.toCommand(raw)
        if let r = await ContactsAgent.shared.handle(t, original: raw) { return r }
        if let r = MessagesAgent.shared.handle(t) { return r }
        if let r = NotesAgent.shared.handle(t) { return r }
        if let r = MusicAgent.shared.handle(t) { return r }
        return await CommandEngine.shared.handle(t)
    }

    // MARK: Splitting "do this and then that"

    private static let separators = #"\s*(?:,\s*)?\b(?:and then|and after that|after that|then|and also|and|phir|phr|fir|aur phir|aur|us ke baad|uske baad|te fer|te|फिर|और|پھر|اور)\b\s*"#

    func split(_ raw: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: Self.separators, options: .caseInsensitive) else { return [raw] }
        let ns = raw as NSString
        var pieces: [String] = []
        var last = 0
        for m in re.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            pieces.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            pieces.append("\u{1}" + ns.substring(with: m.range))      // keep the separator so it can be glued back
            last = m.range.location + m.range.length
        }
        pieces.append(ns.substring(from: last))
        // Only split where the next part is a real action; "bread and butter" stays together.
        var steps: [String] = []
        var pendingSep = ""
        for p in pieces {
            if p.hasPrefix("\u{1}") { pendingSep = String(p.dropFirst()); continue }
            let part = p.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { continue }
            if steps.isEmpty || isAction(part) { steps.append(part) }
            else { steps[steps.count - 1] += pendingSep + part }
            pendingSep = ""
        }
        return steps.count > 1 && isAction(steps[0]) ? steps : [raw]
    }

    func isAction(_ s: String) -> Bool {
        let t = Translit.toCommand(s).lowercased()
        let starts = ["open ", "launch ", "start ", "quit ", "close ", "play", "pause", "stop music", "next", "previous", "skip",
                      "volume", "mute", "unmute", "search ", "google ", "youtube ", "lock", "dark mode", "light mode", "screenshot",
                      "remind me", "add task", "note", "take a note", "save this", "save that", "save ", "write down", "message ",
                      "text ", "send ", "whatsapp ", "call ", "what's", "what is", "show ", "go to ", "find "]
        return starts.contains { t.hasPrefix($0) }
    }
}

// MARK: - Roman Urdu / Hindi / Punjabi → simple English commands

enum Translit {
    private static let rules: [(String, String)] = [
        // open / close  ("spotify kholo", "chrome band karo", "notes khol de")
        (#"^(.+?)\s+(?:ko\s+)?(?:kholo|khol do|khol de|kholdo|khol|open karo|open kar do|open kardo|open kr do|open kro|chalu karo|start karo|کھولو|کھول دو|खोलो|खोल दो)(?:\s+(?:na|ji|please|yaar))?$"#, "open $1"),
        (#"^(?:kholo|khol do|open karo)\s+(.+)$"#, "open $1"),
        (#"^(.+?)\s+(?:ko\s+)?(?:band karo|band kar do|band kardo|band kr do|band kro|band kar de|بند کرو|बंद करो)(?:\s+(?:na|ji|please))?$"#, "quit $1"),
        // music
        (#"^(?:koi\s+)?(?:gaana|gana|gaane|gane|song|music|songs|gaanay)\s+(?:chalao|chala do|chalado|lagao|laga do|lagado|bajao|baja do|la de|chala de|play karo|play kar do|چلاؤ|لگاؤ|चलाओ|लगाओ|बजाओ)$"#, "play music"),
        (#"^(.+?)\s+(?:wala\s+)?(?:gaana|gana|song)?\s*(?:chalao|chala do|lagao|laga do|bajao|baja do|play karo|play kar do|chala de|la de)\s+(?:spotify|youtube)\s+(?:pe|par|pr|te)$"#, "play $1"),
        (#"^(?:spotify|youtube)\s+(?:pe|par|pr|te)\s+(.+?)\s+(?:chalao|chala do|lagao|laga do|bajao|play karo|chala de|la de)$"#, "play $1"),
        (#"^(.+?)\s+(?:wala\s+)?(?:gaana|gana|song)\s+(?:chalao|chala do|lagao|laga do|bajao|baja do|play karo|chala de|la de)$"#, "play $1"),
        (#"^(?:gaana|gana|music|song)\s+(?:rok do|roko|band karo|ruk jao|pause karo|rok de)$"#, "pause"),
        (#"^(?:rok do|roko|ruk jao|pause karo)$"#, "pause"),
        (#"^(?:agla|agla wala|next)\s+(?:gaana|gana|song)(?:\s+(?:chalao|lagao|karo))?$|^next karo$|^agla$"#, "next song"),
        (#"^(?:pichla|pichhla|previous)\s+(?:gaana|gana|song)(?:\s+(?:chalao|lagao|karo))?$"#, "previous song"),
        // volume
        (#"^(?:awaaz|awaz|aawaz|volume|آواز|आवाज़|आवाज)\s+(?:barhao|badhao|tez karo|ooncha karo|zyada karo|up karo|barha do|badha do|vadhao)$"#, "volume up"),
        (#"^(?:awaaz|awaz|aawaz|volume|آواز|आवाज़|आवाज)\s+(?:kam karo|kam kar do|dheemi karo|ahista karo|down karo|ghatao|ghata do)$"#, "volume down"),
        (#"^(?:awaaz|awaz|volume)\s+band karo$"#, "mute"),
        // notes  ("ye note kar lo", "notes mein likh lo …", "likh lo …")
        (#"^(?:ye|yeh|is ko|isko|isse)\s+(?:note|save|likh)\s+(?:kar lo|karo|kar do|kr lo|kro|lo)$"#, "save this note"),
        (#"^(?:notes?\s+(?:mein|me|main|vich)\s+)?(?:likh lo|likh do|note karo|note kar lo|note kr lo|save karo|save kar lo)\s*[:,]?\s*(.+)$"#, "note $1"),
        (#"^(.+?)\s+(?:note kar lo|note karo|likh lo|likh do|notes mein save karo|notes me save karo)$"#, "note $1"),
        // search
        (#"^(.+?)\s+(?:search karo|search kar do|google karo|talash karo|dhoondo|dhundo|lagao google pe)$"#, "search $1"),
        (#"^(?:search karo|google karo|dhoondo|dhundo)\s+(.+)$"#, "search $1"),
        (#"^youtube\s+(?:pe|par|pr|te)\s+(.+?)\s+(?:dikhao|lagao|chalao|search karo)$"#, "play $1 on youtube"),
        // misc
        (#"^(?:time kya hai|kitne baje hain|kya time hai|ٹائم کیا ہے|समय क्या है|kinne vaje ne)$"#, "what time is it"),
        (#"^(?:battery kitni hai|battery kitni hai\?|battery)$"#, "battery"),
        (#"^(?:screen lock karo|lock karo|lock kar do)$"#, "lock screen"),
        (#"^(?:screenshot lo|screenshot le lo|screenshot karo)$"#, "screenshot"),
    ]

    /// Turns everyday Roman Urdu / Hindi / Punjabi phrasing into the English commands the agents know.
    static func toCommand(_ raw: String) -> String {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?۔"))
            .replacingOccurrences(of: #"^((hey|hi|ok)\s+)?sparrow[,!\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+(please|plz|pls|yaar|ji)$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let lower = t.lowercased()
        for (pattern, template) in rules {
            guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let ns = lower as NSString
            if let m = re.firstMatch(in: lower, range: NSRange(location: 0, length: ns.length)) {
                var out = template
                for i in stride(from: m.numberOfRanges - 1, through: 1, by: -1) where m.range(at: i).location != NSNotFound {
                    // keep the person's own capitals for names and note text
                    let piece = (t as NSString).length == ns.length ? (t as NSString).substring(with: m.range(at: i)) : ns.substring(with: m.range(at: i))
                    out = out.replacingOccurrences(of: "$\(i)", with: piece)
                }
                t = out
                break
            }
        }
        return t
    }
}

// MARK: - Contacts agent  ("save this number 0300 1234567 as Ali", "Ali ka number save karo 0300…", "what's Ali's number")

@MainActor
final class ContactsAgent {
    static let shared = ContactsAgent()
    nonisolated(unsafe) private static let store = CNContactStore()
    private let noAccess = "I need access to Contacts: System Settings → Privacy & Security → Contacts → Sparrow."

    nonisolated private static func askAccess() async -> Bool {
        await withCheckedContinuation { c in store.requestAccess(for: .contacts) { ok, _ in c.resume(returning: ok) } }
    }
    private func access() async -> Bool {
        if CNContactStore.authorizationStatus(for: .contacts) == .authorized { return true }
        return await Self.askAccess()
    }

    private static let phoneRE = #"(\+?\d[\d\s\-]{6,}\d)"#

    func handle(_ t: String, original: String) async -> String? {
        let low = t.lowercased()
        // Save
        let aboutContact = low.contains("number") || low.contains("contact") || low.range(of: #"\bas\b"#, options: .regularExpression) != nil
        let saveWords = aboutContact && (low.hasPrefix("save") || low.hasPrefix("add") || low.contains(" save"))
        if saveWords, let num = firstMatch(Self.phoneRE, in: t) {
            let name = contactName(from: t, number: num)
            guard !name.isEmpty else { return "What name should I save \(num) under? Say \"save \(num) as Ali\"." }
            guard await access() else { return noAccess }
            return save(name: name, number: num)
                ? "📇 Saved \(name) — \(num) in your Contacts."
                : "Sorry, I couldn't save that contact."
        }
        // Look up: "what's Ali's number", "Ali ka number kya hai", "Ali ka number batao"
        if let who = firstMatch(#"^(?:what(?:'s| is)\s+)(.+?)(?:'s| ka| ki)\s+(?:phone\s+)?number\??$"#, in: low)
            ?? firstMatch(#"^(.+?)\s+(?:ka|ki|da|di)\s+(?:phone\s+)?number\s+(?:kya hai|batao|bata do|dikhao|kya ae|ki hai)\??$"#, in: low) {
            guard await access() else { return noAccess }
            let hits = find(who)
            guard let c = hits.first else { return "I couldn't find \(who.capitalized) in your Contacts." }
            let nums = c.phoneNumbers.map { $0.value.stringValue }
            return nums.isEmpty ? "\(full(c)) has no phone number saved." : "\(full(c)): \(nums.joined(separator: ", "))"
        }
        return nil
    }

    /// "save 0300 1234567 as Ali Khan" / "save Ali's number 0300…" / "Ali ka number save karo 0300…"
    private func contactName(from t: String, number: String) -> String {
        var s = t.replacingOccurrences(of: number, with: " ")
        let patterns = [#"\b(?:as|for|naam|name|named|by the name)\s+(.+)$"#,
                        #"^(?:save|add)\s+(.+?)(?:'s|s')?\s+(?:phone\s+)?number"#,
                        #"^(.+?)\s+(?:ka|ki|da|di)\s+(?:phone\s+)?number"#,
                        #"^(?:save|add)\s+(?:this\s+|the\s+)?(?:phone\s+)?(?:number|contact)?\s*(.+)$"#]
        for p in patterns {
            if let n = firstMatch(p, in: s) {
                s = n; break
            }
        }
        let junk = #"\b(save|karo|kar do|kardo|kr do|kro|this|the|number|phone|contact|contacts|to|in|my|please|mein|me|se|naam|name|is|as|ka|ki|ko)\b"#
        return s.replacingOccurrences(of: junk, with: " ", options: [.regularExpression, .caseInsensitive])
            .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.prefix(3)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private func save(name: String, number: String) -> Bool {
        let c = CNMutableContact()
        let parts = name.split(separator: " ").map(String.init)
        c.givenName = parts.first ?? name
        if parts.count > 1 { c.familyName = parts.dropFirst().joined(separator: " ") }
        c.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: number))]
        let req = CNSaveRequest()
        req.add(c, toContainerWithIdentifier: nil)
        do { try Self.store.execute(req); return true } catch { appendAppLog("agents.log", "contact save failed: \(error)"); return false }
    }

    func find(_ name: String) -> [CNContact] {
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let pred = CNContact.predicateForContacts(matchingName: name)
        return (try? Self.store.unifiedContacts(matching: pred, keysToFetch: keys)) ?? []
    }

    func number(for name: String) async -> String? {
        guard await access() else { return nil }
        return find(name).first?.phoneNumbers.first?.value.stringValue
    }

    private func full(_ c: CNContact) -> String { [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " ") }
}

// MARK: - Messages agent  ("message Ali on WhatsApp saying I'm late") — opens a ready draft, you press Send.

@MainActor
final class MessagesAgent {
    static let shared = MessagesAgent()

    func handle(_ t: String) -> String? {
        let re = #"^(?:send\s+)?(?:a\s+)?(?:whatsapp|message|text|msg)\s+(?:to\s+)?(.+?)(?:\s+on\s+(whatsapp|imessage|messages))?\s+(?:saying|that|ke|keh do|bolo|:)\s+(.+)$"#
        guard let r = try? NSRegularExpression(pattern: re, options: .caseInsensitive),
              let m = r.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) else { return nil }
        let ns = t as NSString
        let who = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
        let via = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)).lowercased() : (t.lowercased().hasPrefix("whatsapp") ? "whatsapp" : "messages")
        let body = ns.substring(with: m.range(at: 3))
        let enc = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        Task { @MainActor in
            let num = await ContactsAgent.shared.number(for: who)
            let digits = (num ?? (who.rangeOfCharacter(from: .decimalDigits) != nil ? who : "")).filter { $0.isNumber || $0 == "+" }
            if via == "whatsapp" {
                let url = digits.isEmpty ? "whatsapp://send?text=\(enc)" : "whatsapp://send?phone=\(digits.filter(\.isNumber))&text=\(enc)"
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            } else if let u = URL(string: "sms:\(digits)&body=\(enc)") {
                NSWorkspace.shared.open(u)
            }
        }
        return "✉️ Your message to \(who.capitalized) is ready. Check it and press Send."
    }
}

// MARK: - Notes agent  ("save this note", "open notes and save this")

@MainActor
final class NotesAgent {
    static let shared = NotesAgent()

    func handle(_ t: String) -> String? {
        let low = t.lowercased()
        let isSaveThis = low.range(of: #"^(?:save|keep|put)\s+(?:this|that|it)(?:\s+(?:notes?|text))?(?:\s+(?:for me|in (?:my )?notes|to (?:my )?notes))*$"#,
                                   options: .regularExpression) != nil
            || low == "save this note" || low == "note this" || low == "note that"
        guard isSaveThis else { return nil }
        // "this" = the text you copied, or else Sparrow's last answer.
        var body = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let copiedAt = UserDefaults.standard.integer(forKey: "lastPasteboardSeen")
        if body.isEmpty || NSPasteboard.general.changeCount == copiedAt,
           let last = AppState.shared.chatHistory.last(where: { $0.role == .assistant })?.content, !last.isEmpty {
            body = last
        }
        guard !body.isEmpty else { return "What should the note say? Copy the text first, or say \"note …\"." }
        UserDefaults.standard.set(NSPasteboard.general.changeCount, forKey: "lastPasteboardSeen")
        let esc = body.prefix(4000).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "<br>")
        if CommandEngine.shared.runAppleScript("tell application \"Notes\" to make new note with properties {body:\"\(esc)\"}") != nil {
            return "📝 Saved in your Notes."
        }
        return "I couldn't reach Notes. Allow Sparrow under System Settings → Privacy & Security → Automation."
    }
}

// MARK: - Music agent  ("play Coke Studio" — plays straight from your Apple Music library when it can)

@MainActor
final class MusicAgent {
    static let shared = MusicAgent()

    func handle(_ t: String) -> String? {
        let low = t.lowercased()
        guard low.hasPrefix("play "), !low.hasSuffix(" on youtube"), !low.contains("spotify"),
              !["play music", "play song", "play the music", "play something"].contains(low) else { return nil }
        let running = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        let hasSpotify = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.spotify.client") != nil
        // Spotify users keep the normal Spotify flow.
        if running.contains("com.spotify.client") || (hasSpotify && !running.contains("com.apple.Music")) { return nil }
        var q = String(t.dropFirst(5))
        for a in ["some ", "a song by ", "songs by ", "music by ", "the song "] where q.lowercased().hasPrefix(a) { q = String(q.dropFirst(a.count)) }
        q = q.replacingOccurrences(of: " on apple music", with: "", options: .caseInsensitive)
        let esc = q.replacingOccurrences(of: "\"", with: "")
        let script = """
        tell application "Music"
          set hits to (every track of library playlist 1 whose name contains "\(esc)" or artist contains "\(esc)" or album contains "\(esc)")
          if (count of hits) is 0 then return ""
          play item 1 of hits
          return (name of current track) & " — " & (artist of current track)
        end tell
        """
        if let r = CommandEngine.shared.runAppleScript(script), !r.isEmpty { return "🎵 Playing \(r)." }
        return nil   // not in the library → normal search flow
    }
}

// MARK: - helpers

private func firstMatch(_ pattern: String, in s: String) -> String? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
          let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)), m.numberOfRanges > 1,
          m.range(at: 1).location != NSNotFound else { return nil }
    return (s as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
}
