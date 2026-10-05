import Foundation
import AppKit

// =====================================================================
// MARK: - Mail agent: Sparrow reads and answers your email
// Works with every account added to the Mac's Mail app (Gmail, Outlook,
// iCloud, Yahoo…) — System Settings → Internet Accounts. Sparrow never sees
// a password; it simply asks Mail.
//   "any new emails?"                     → who wrote and what they want
//   "read the email from Ahmed"           → reads it out
//   "reply to Ahmed saying I'll send it tomorrow" → drafts a reply, shows + reads it
//   "send" / "change it: make it shorter" / "cancel"
// Nothing is ever sent without "send".
// =====================================================================

@MainActor
final class MailAgent {
    static let shared = MailAgent()

    struct Mail { let id: String; let sender: String; let subject: String; let date: String; let body: String; let account: String
        var name: String { MailAgent.name(of: sender) }
        var address: String { MailAgent.address(of: sender) }
    }
    struct Draft { let mail: Mail; var body: String; let made: Date }

    private var recent: [Mail] = []          // last list we read out, newest first
    private var lastMail: Mail?              // "reply to it", "read it"
    private(set) var draft: Draft?

    // MARK: Understanding

    private static let checkRE = #"^(?:check|read|show|any|do i have|have i got|got any|what are|what's in)?\s*(?:my |any |the |new |unread |latest |recent )*(?:e-?mails?|mails?|inbox)(?:\s+(?:today|now|please))?\??$|^(?:check|open) (?:my )?inbox$|^(?:any(?:thing)?|something) new in (?:my )?(?:e-?mail|mail|inbox)\??$|^(?:who|has anyone) (?:e-?mailed|wrote to) me\??$"#
    private static let readRE  = #"^(?:read|open|what does|what did|show)(?: me)? (?:the |that |this )?(?:e-?mail|mail|message)?\s*(?:from|by|of)\s+(.+?)(?:\s+(?:say|says|said))?\??$|^(?:read|open) (?:it|that|that one|this one|the last one|the latest one|the first one)$"#
    private static let replyRE = #"^(?:reply|respond|write back)(?: to)?\s+(.+?)\s*(?:saying|say|that|and say|and tell (?:him|her|them)|to say|:|,)\s*(.+)$"#
    private static let replyBareRE = #"^(?:reply|respond|write back)(?: to)?\s+(.+)$"#
    private static let pronounRE = #"^(?:it|him|her|them|that|this|back|that one|this one|the last one|the first one|(?:that|this|the|the last|the latest|his|her) (?:e-?mail|mail|message|one))$"#

    /// Does this belong to the mail agent? Checked before a request is split into steps, so "and" inside a reply stays in it.
    func dropDraft() { draft = nil }

    func claims(_ raw: String) -> Bool {
        let t = Self.clean(raw)
        if t.contains("whatsapp") || t.contains("whats app") { return false }
        if draft != nil, Self.isSend(t) || Self.isCancel(t) || Self.isChange(t) != nil { return true }
        return t.range(of: Self.replyRE, options: .regularExpression) != nil
            || (t.range(of: Self.replyBareRE, options: .regularExpression) != nil && (t.contains("email") || t.contains("mail") || lastMail != nil))
            || t.range(of: Self.checkRE, options: [.regularExpression, .caseInsensitive]) != nil
            || t.range(of: Self.readRE, options: .regularExpression) != nil
    }

    func handle(_ raw: String) async -> String? {
        let t = Self.clean(raw), o = Self.clean(raw, keepCase: true)
        if draft != nil, Date().timeIntervalSince(draft!.made) > 600 { draft = nil }      // a draft waits 10 minutes
        if let d = draft {
            if Self.isSend(t) { return await send(d) }
            if Self.isCancel(t) { draft = nil; return "Okay, I won't send it." }
            if Self.isChange(t) != nil, let change = Self.isChange(o) { return await redraft(d, change) }
        }
        if let m = Self.match(Self.replyRE, o) {
            return await reply(to: m[0], saying: m[1])
        }
        if let m = Self.match(Self.replyBareRE, t), t.range(of: Self.checkRE, options: [.regularExpression, .caseInsensitive]) == nil {
            let who = m[0].replacingOccurrences(of: #"^(?:the |this |that )?(?:e-?mail|mail|message)\s*(?:from\s+)?"#, with: "", options: .regularExpression)
            guard let mail = await find(who) else { return notFound(who) }
            lastMail = mail
            VoiceEngine.shared.listenAfterSpeech = true
            return "What should I tell \(mail.name)?"
        }
        if let m = Self.match(Self.readRE, t) {
            let who = m.first ?? ""
            let mail: Mail?
            if who.isEmpty { mail = t.contains("first") ? recent.first : (lastMail ?? recent.first) } else { mail = await find(who) }
            guard let mail else { return who.isEmpty ? "Which email? Try \"read the email from Ahmed\"." : notFound(who) }
            return await read(mail)
        }
        if t.range(of: Self.checkRE, options: [.regularExpression, .caseInsensitive]) != nil { return await checkNew() }
        return nil
    }

    // MARK: Jobs

    func checkNew() async -> String {
        AgentRouter.lastChannel = .mail
        guard let res = await Self.osa(Self.listScript(limit: 6)) else { return Self.mailProblem }
        let (total, mails) = Self.parseList(res)
        recent = mails
        lastMail = mails.first
        if total == 0 || mails.isEmpty { return "No new emails. Your inbox is all caught up! ✨" }
        let head = total == 1 ? "You have 1 new email." : "You have \(total) new emails\(total > mails.count ? ". Here are the latest \(mails.count)" : "")."
        // A friendly one-line gist of each, when the fast AI is reachable; sender + subject otherwise.
        if SmartPlanner.shared.isAvailable {
            let list = mails.enumerated().map { i, m in "\(i + 1). From \(m.name), subject \"\(m.subject)\": \(m.body.prefix(400))" }.joined(separator: "\n")
            let prompt = """
            Summarise each email below in ONE short spoken sentence (max 14 words), starting with the sender's first name, \
            saying what they want or tell. No numbering, no emojis, no quotes. One sentence per line, same order.
            \(list)
            """
            if let s = await SmartPlanner.shared.complete(prompt) {
                let lines = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !lines.isEmpty { VoiceEngine.shared.listenAfterSpeech = true; return ([head] + lines.prefix(mails.count)).joined(separator: " ") + " Want me to reply to any?" }
            }
        }
        let gist = mails.map { "\($0.name): \($0.subject.isEmpty ? "no subject" : $0.subject)." }.joined(separator: " ")
        VoiceEngine.shared.listenAfterSpeech = true
        return "\(head) \(gist) Want me to reply to any?"
    }

    private func read(_ mail: Mail) async -> String {
        AgentRouter.lastChannel = .mail
        lastMail = mail
        _ = await Self.osa("""
        tell application "Mail"
          try
            set read status of (first message of inbox whose id is \(mail.id)) to true
          end try
        end tell
        """)
        var text = mail.body.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if text.count > 320, SmartPlanner.shared.isAvailable,
           let s = await SmartPlanner.shared.complete("In 2 short spoken sentences, tell me what this email from \(mail.name) says and what they want. No emojis.\nSubject: \(mail.subject)\n\(mail.body.prefix(2500))") {
            text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if text.count > 320 { text = String(text.prefix(320)) + "…" }
        VoiceEngine.shared.listenAfterSpeech = true
        return "\(mail.name) wrote about \"\(mail.subject)\". \(text) Should I reply?"
    }

    private func reply(to who: String, saying what: String) async -> String {
        let mail: Mail?
        if who.lowercased().range(of: Self.pronounRE, options: .regularExpression) != nil { mail = lastMail ?? recent.first } else { mail = await find(who) }
        guard let mail else { return notFound(who) }
        lastMail = mail
        AgentRouter.lastChannel = .mail
        WhatsAppAgent.shared.dropDraft()
        let body = await compose(for: mail, instruction: what, previous: nil)
        draft = Draft(mail: mail, body: body, made: Date())
        return present(draft!)
    }

    private func redraft(_ d: Draft, _ change: String) async -> String {
        let body = await compose(for: d.mail, instruction: change, previous: d.body)
        draft = Draft(mail: d.mail, body: body, made: Date())
        return present(draft!)
    }

    private func present(_ d: Draft) -> String {
        // The draft is shown on the island and read out; Sparrow then listens for "send", "change…" or "cancel".
        VoiceEngine.shared.listenAfterSpeech = true
        return "Here's my reply to \(d.mail.name): \"\(d.body)\". Say send, tell me what to change, or cancel."
    }

    private func send(_ d: Draft) async -> String {
        let me = AssistantPrefs.displayName
        let quoted = d.mail.body.split(separator: "\n", omittingEmptySubsequences: false).prefix(40).map { "> " + $0 }.joined(separator: "\n")
        let full = d.body + "\n\nOn \(d.mail.date), \(d.mail.sender) wrote:\n" + quoted
        let subject = d.mail.subject.lowercased().hasPrefix("re:") ? d.mail.subject : "Re: " + d.mail.subject
        let from = d.mail.account.isEmpty ? "" : ", sender:\(Self.q(d.mail.account))"
        let script = """
        tell application "Mail"
          set m to make new outgoing message with properties {subject:\(Self.q(subject)), content:\(Self.q(full)), visible:false\(from)}
          tell m to make new to recipient at end of to recipients with properties {address:\(Self.q(d.mail.address))}
          send m
        end tell
        return "ok"
        """
        guard await Self.osa(script) == "ok" else { return "I couldn't send it. Check that Mail is set up, then try again." }
        draft = nil
        appendAppLog("agents.log", "mail: replied to \(d.mail.address) (\(subject))\(me.isEmpty ? "" : " as \(me)")")
        return "Sent! \(d.mail.name) will have your reply in a moment."
    }

    /// Writes the reply: the fast AI drafts it in the sender's language and a warm, natural tone; offline, Sparrow tidies your words.
    private func compose(for mail: Mail, instruction: String, previous: String?) async -> String {
        let me = AssistantPrefs.displayName
        if SmartPlanner.shared.isAvailable {
            let prompt = """
            Write the body of a short email reply for me. Natural, warm and polite, like a real person; 1–4 sentences.
            Write in the same language as the original email. Start with a greeting using their first name.
            End with a short sign-off\(me.isEmpty ? "" : " and my name, \(me)"). Return ONLY the email body, no subject, no quotes, no notes.
            What I want to say: \(instruction)
            \(previous.map { "Current draft (apply my request to it): \($0)\n" } ?? "")Original email from \(mail.name), subject "\(mail.subject)":
            \(mail.body.prefix(2000))
            """
            if let s = await SmartPlanner.shared.complete(prompt)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return s.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            }
        }
        // Offline: turn "tell him I'll send it tomorrow" into a tidy little email.
        var said = (previous == nil ? instruction : instruction)
            .replacingOccurrences(of: #"^(?:tell|say to|let) (?:him|her|them)(?: know)?(?: that)?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^(?:that|ke|keh do ke)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        said = said.replacingOccurrences(of: #"\b(?:he|she|they) will\b"#, with: "you will", options: [.regularExpression, .caseInsensitive])
        said = said.replacingOccurrences(of: #"\bi\b"#, with: "I", options: .regularExpression)
        if let f = said.first { said = f.uppercased() + said.dropFirst() }
        if !said.hasSuffix(".") && !said.hasSuffix("!") && !said.hasSuffix("?") { said += "." }
        let first = mail.name.split(separator: " ").first.map(String.init) ?? mail.name
        return "Hi \(first),\n\n\(said)\n\nThanks\(me.isEmpty ? "" : ",\n\(me)")"
    }

    /// Finds the newest email from someone (by name or address), first in what was just read out, then in the inbox.
    private func find(_ who: String) async -> Mail? {
        let w = who.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^(?:the |my )?(?:e-?mail|mail|message)\s+(?:from\s+)?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"'s$|’s$"#, with: "", options: .regularExpression)
        guard !w.isEmpty else { return nil }
        if let m = recent.first(where: { $0.sender.lowercased().contains(w) || $0.subject.lowercased().contains(w) }) { return m }
        guard let res = await Self.osa(Self.findScript(w)) else { return nil }
        let (_, mails) = Self.parseList(res)
        return mails.first
    }

    private func notFound(_ who: String) -> String { "I couldn't find a recent email from \(who). Try their first name, or say \"any new emails\"." }
    private static let mailProblem = "I couldn't reach Mail. Add your email in System Settings → Internet Accounts, open Mail once, and allow Sparrow to use Mail when your Mac asks."

    // MARK: Words

    private static func clean(_ raw: String, keepCase: Bool = false) -> String {
        let s = Translit.toCommand(raw)
            .replacingOccurrences(of: #"^(?:can you|could you|please|will you)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        return keepCase ? s : s.lowercased()
    }
    private static func isSend(_ t: String) -> Bool {
        t.range(of: #"^(?:yes|yeah|yep|ok|okay|sure|perfect|great|good)?[, ]*(?:send|send it|send that|send now|send the (?:reply|email)|go ahead|looks good|bhej do|bhejo|bhej de|send kar do|send karo|haan bhej do|haan|ji haan|भेज दो|بھیج دو)$|^(?:yes|yeah|yep|haan)$"#, options: .regularExpression) != nil
    }
    private static func isCancel(_ t: String) -> Bool {
        t.range(of: #"^(?:no|nope|cancel|cancel it|don'?t send(?: it)?|do not send|never ?mind|forget it|discard(?: it)?|rehne do|mat bhejo|nahi|nahin|नहीं|نہیں)$"#, options: .regularExpression) != nil
    }
    private static func isChange(_ t: String) -> String? {
        if let m = match(#"^(?:change it|change that|edit it|rewrite it|redo it)[:, ]*(?:to |so (?:that )?)?(.*)$"#, t) { return m[0].isEmpty ? "make it a bit better" : m[0] }
        if t.range(of: #"^(?:make it|also (?:say|tell|add|mention|ask)|add (?:that|a line|something)|mention|remove the|be more|shorter|longer|more (?:formal|casual|polite|friendly|professional)|less (?:formal|casual)|(?:write it |say it )?in (?:urdu|english|hindi|punjabi|roman urdu)|translate)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { return t }
        return nil
    }
    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return nil }
        return (1..<max(1, m.numberOfRanges)).map { m.range(at: $0).location == NSNotFound ? "" : (s as NSString).substring(with: m.range(at: $0)).trimmingCharacters(in: .whitespaces) }
    }
    nonisolated static func name(of sender: String) -> String {
        var n = sender
        if let lt = sender.firstIndex(of: "<") { n = String(sender[..<lt]) }
        n = n.trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
        if n.isEmpty || n.contains("@") { n = String(address(of: sender).split(separator: "@").first ?? "someone") }
        return n
    }
    nonisolated static func address(of sender: String) -> String {
        if let lt = sender.firstIndex(of: "<"), let gt = sender.lastIndex(of: ">"), lt < gt { return String(sender[sender.index(after: lt)..<gt]) }
        return sender.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Talking to Mail (osascript off the main thread, so the island never freezes)

    private static let FS = "character id 31", RS = "character id 30"

    private static let rowScript = """
          set c to ""
          try
            set c to content of m
          end try
          if (length of c) > 2500 then set c to text 1 thru 2500 of c
          set acc to ""
          try
            set acc to item 1 of (email addresses of (account of (mailbox of m)))
          end try
          set out to out & (id of m) & \(FS) & (sender of m) & \(FS) & (subject of m) & \(FS) & ((date received of m) as string) & \(FS) & c & \(FS) & acc & \(RS)
    """

    private static func listScript(limit: Int) -> String {
        """
        tell application "Mail"
          set total to unread count of inbox
          set msgs to (messages of inbox whose read status is false)
          set n to count of msgs
          if n > \(limit) then set n to \(limit)
          set out to ""
          repeat with i from 1 to n
            set m to item i of msgs
        \(rowScript)
          end repeat
          return (total as string) & (character id 29) & out
        end tell
        """
    }

    private static func findScript(_ who: String) -> String {
        """
        tell application "Mail"
          set msgs to (messages of inbox whose sender contains \(q(who)))
          if (count of msgs) = 0 then set msgs to (messages of inbox whose subject contains \(q(who)))
          set out to ""
          if (count of msgs) > 0 then
            set m to item 1 of msgs
        \(rowScript)
          end if
          return "1" & (character id 29) & out
        end tell
        """
    }

    nonisolated private static func parseList(_ s: String) -> (Int, [Mail]) {
        let parts = s.components(separatedBy: "\u{1D}")
        let total = Int(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        let rows = (parts.count > 1 ? parts[1] : "").components(separatedBy: "\u{1E}").filter { !$0.isEmpty }
        let mails = rows.compactMap { r -> Mail? in
            let f = r.components(separatedBy: "\u{1F}")
            guard f.count >= 5 else { return nil }
            return Mail(id: f[0], sender: f[1], subject: f[2], date: f[3], body: f[4].trimmingCharacters(in: .whitespacesAndNewlines), account: f.count > 5 ? f[5] : "")
        }
        // newest first
        return (total, mails)
    }

    /// An AppleScript string literal (quotes, backslashes and line breaks kept safe).
    nonisolated static func q(_ s: String) -> String {
        let e = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return "\"" + e.replacingOccurrences(of: "\n", with: "\" & linefeed & \"") + "\""
    }

    nonisolated static func osa(_ source: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", source]
                let out = Pipe(), err = Pipe()
                p.standardOutput = out; p.standardError = err
                do { try p.run() } catch { cont.resume(returning: nil); return }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                if p.terminationStatus != 0 {
                    let msg = String(data: errData, encoding: .utf8) ?? ""
                    Task { @MainActor in appendAppLog("agents.log", "mail script failed: \(msg.prefix(300))") }
                    cont.resume(returning: nil); return
                }
                var s = String(data: data, encoding: .utf8) ?? ""
                if s.hasSuffix("\n") { s.removeLast() }
                cont.resume(returning: s)
            }
        }
    }
}
