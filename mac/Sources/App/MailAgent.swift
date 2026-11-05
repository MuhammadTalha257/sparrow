import Foundation
import AppKit
import Network

// =====================================================================
// MARK: - Mail agent: Zuffi reads and answers your email
// Works with every account added to the Mac's Mail app (Gmail, Outlook,
// iCloud, Yahoo…) — System Settings → Internet Accounts. Zuffi never sees
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

    struct Mail { let id: String; let sender: String; let subject: String; let date: String; let body: String; let account: String; var age: Int = 0
        var name: String { MailAgent.name(of: sender) }
        var address: String { MailAgent.address(of: sender) }
    }
    struct Draft { let mail: Mail; var body: String; let made: Date }

    private var recent: [Mail] = []          // last list we read out, newest first
    private var lastMail: Mail?              // "reply to it", "read it"
    private(set) var draft: Draft?

    // MARK: Understanding

    private static let checkRE = #"^(?:check|read|show|any|do i have|have i got|got any|what are|what's in)?\s*(?:my |any |the |new |unread |latest |recent )*(?:e-?mails?|mails?|inbox)(?:\s+(?:today|now|please))?\??$|^(?:check|open) (?:my )?inbox$|^(?:any(?:thing)?|something) new in (?:my )?(?:e-?mail|mail|inbox)\??$|^(?:who|has anyone) (?:e-?mailed|wrote to) me\??$|^what'?s new (?:in|on) (?:my )?(?:e-?mails?|mails?|inbox)\??$|^(?:any|new) (?:e-?mails?|mails?)\??$"#
    private static let latestRE = #"^(?:read|open|show|check|tell me|give me|what'?s|what is|what was)(?: me)?(?: my| the)? (?:latest|last|newest|most recent|recent|new|top|first|current)(?: new| unread| received)? (?:e-?mail|mail|message|inbox message)(?: i got| i received| in (?:my )?inbox)?\??$|^who (?:e-?mailed|wrote to|mailed) me (?:last|most recently)\??$|^(?:read|open) (?:my |the )?(?:e-?mail|mail)(?: for me)?$|^(?:my |the )?(?:latest|last|newest|new|most recent) (?:e-?mail|mail)\??$|^(?:open|read|show)(?: me)? (?:the )?(?:lates|latests|latest|last|new) (?:e-?mail|mail|message)$"#
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
            || t.range(of: Self.latestRE, options: .regularExpression) != nil
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
        if t.range(of: Self.latestRE, options: .regularExpression) != nil { return await readLatest(show: t.hasPrefix("open") || t.hasPrefix("show")) }
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
        let got = await Self.osa(Self.listScript(limit: 6))
        guard let res = got, !Self.failed(res) else { return Self.problem(got) }
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

    /// Unread email for the dashboard's Inbox: [total, mails: [{id, from, subject, age}]] or [error].
    func inbox(limit: Int) async -> [String: Any] {
        let got = await Self.osa(Self.listScript(limit: max(1, min(limit, 15))))
        guard let res = got, !Self.failed(res) else { return ["error": "mail"] }
        let (total, mails) = Self.parseList(res)
        let rows: [[String: Any]] = mails.map { m -> [String: Any] in ["id": m.id, "from": m.name, "subject": m.subject, "age": m.age] }
        return ["total": total, "mails": rows]
    }
    /// Opens one message in Mail.
    func open(id: String) async {
        guard Int(id) != nil else { return }
        _ = await Self.osa("""
        tell application "Mail"
          activate
          try
            open (first message of inbox whose id is \(id))
          end try
        end tell
        """)
    }

    /// The newest email in the inbox (read or not), read out.
    func readLatest(show: Bool = false) async -> String {
        AgentRouter.lastChannel = .mail
        var res = await Self.osa(Self.latestScript(days: 3))
        if let r = res, Self.failed(r) { return Self.problem(r) }
        if res.map({ Self.parseList($0).1.isEmpty }) ?? true { res = await Self.osa(Self.latestScript(days: 60)) }
        guard let r = res, !Self.failed(r) else { return Self.problem(res) }
        guard let mail = Self.parseList(r).1.first else { return "Your inbox looks empty. Is your account switched on in Mail?" }
        if show {
            // "open latest mail": it appears on screen in Mail, and Zuffi tells you what it's about.
            _ = await Self.osa("""
            tell application "Mail"
              activate
              try
                open (first message of inbox whose id is \(mail.id))
              end try
            end tell
            """)
        }
        return await read(mail)
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
        // The draft is shown on the island and read out; Zuffi then listens for "send", "change…" or "cancel".
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

    /// Writes the reply: the fast AI drafts it in the sender's language and a warm, natural tone; offline, Zuffi tidies your words.
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
        if let res = await Self.osa(Self.findScript(w)), let m = Self.parseList(res).1.first { return m }
        if let res = await Self.osa(Self.findSubjectScript(w)), let m = Self.parseList(res).1.first { return m }
        return nil
    }

    private func notFound(_ who: String) -> String { "I couldn't find a recent email from \(who). Try their first name, or say \"any new emails\"." }
    nonisolated static func failed(_ s: String) -> Bool { s.hasPrefix("\u{15}") }
    private static func problem(_ s: String?) -> String {
        let e = s.map { failed($0) ? String($0.dropFirst()) : "" } ?? ""
        if e.contains("-1743") || e.lowercased().contains("not authori") || e.lowercased().contains("not allowed") {
            return "Zuffi isn't allowed to use Mail yet. Open System Settings → Privacy & Security → Automation → Zuffi and switch on Mail."
        }
        return mailProblem
    }
    private static let mailProblem = "I couldn't reach Mail. Add your email in System Settings → Internet Accounts, open Mail once, and allow Zuffi to use Mail when your Mac asks."

    // MARK: Words

    private static func clean(_ raw: String, keepCase: Bool = false) -> String {
        let s = Translit.toCommand(raw.replacingOccurrences(of: "’", with: "'"))
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
          set age to 0
          try
            set age to ((current date) - (date received of m)) as integer
          end try
          set out to out & (id of m) & \(FS) & (sender of m) & \(FS) & (subject of m) & \(FS) & ((date received of m) as string) & \(FS) & c & \(FS) & acc & \(FS) & age & \(RS)
    """

    /// The newest `limit` inbox messages matching `filter` (Mail doesn't promise any order, so Zuffi sorts by date itself).
    private static func newestScript(_ filter: String, limit: Int, total: String = "0") -> String {
        """
        tell application "Mail"
          set total to \(total)
          set msgs to (messages of inbox whose \(filter))
          set n to count of msgs
          set out to ""
          if n > 0 then
            set ds to date received of (messages of inbox whose \(filter))
            set picked to {}
            set want to \(limit)
            if want > n then set want to n
            repeat want times
              set best to 0
              repeat with i from 1 to n
                if picked does not contain i then
                  if best = 0 then
                    set best to i
                  else if item i of ds > item best of ds then
                    set best to i
                  end if
                end if
              end repeat
              set end of picked to best
            end repeat
            repeat with i in picked
              set m to item i of msgs
        \(rowScript)
            end repeat
          end if
          return (total as string) & (character id 29) & out
        end tell
        """
    }
    private static func listScript(limit: Int) -> String { newestScript("read status is false", limit: limit, total: "unread count of inbox") }
    private static func latestScript(days: Int) -> String { newestScript("date received > ((current date) - \(days) * days)", limit: 1, total: "1") }
    private static func findScript(_ who: String) -> String {
        // by sender first; the subject is tried by find() if nobody matches
        newestScript("sender contains \(q(who))", limit: 1, total: "1")
    }
    private static func findSubjectScript(_ what: String) -> String { newestScript("subject contains \(q(what))", limit: 1, total: "1") }

    nonisolated private static func parseList(_ s: String) -> (Int, [Mail]) {
        let parts = s.components(separatedBy: "\u{1D}")
        let total = Int(parts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
        let rows = (parts.count > 1 ? parts[1] : "").components(separatedBy: "\u{1E}").filter { !$0.isEmpty }
        let mails = rows.compactMap { r -> Mail? in
            let f = r.components(separatedBy: "\u{1F}")
            guard f.count >= 5 else { return nil }
            return Mail(id: f[0], sender: f[1], subject: f[2], date: f[3], body: f[4].trimmingCharacters(in: .whitespacesAndNewlines),
                        account: f.count > 5 ? f[5] : "", age: f.count > 6 ? Int(f[6].trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0 : 0)
        }
        return (total, mails.sorted { $0.age < $1.age })      // newest first
    }

    /// An AppleScript string literal (quotes, backslashes and line breaks kept safe).
    nonisolated static func q(_ s: String) -> String {
        let e = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return "\"" + e.replacingOccurrences(of: "\n", with: "\" & linefeed & \"") + "\""
    }

    /// Mail.app not answering (AppleEvent timed out): leave it alone for a few minutes instead of piling up scripts
    /// that slow the whole Mac (and her voice) down.
    nonisolated(unsafe) static var mailRestUntil = Date.distantPast
    nonisolated static func osa(_ source: String) async -> String? {
        if source.contains("application \"Mail\""), Date() < mailRestUntil { return "\u{15}Mail isn't answering right now." }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
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
                    if msg.contains("-1712") || msg.contains("-609") { MailAgent.mailRestUntil = Date().addingTimeInterval(300) }
                    Task { @MainActor in appendAppLog("agents.log", "mail script failed: \(msg.prefix(300))") }
                    cont.resume(returning: "\u{15}" + msg); return
                }
                var s = String(data: data, encoding: .utf8) ?? ""
                if s.hasSuffix("\n") { s.removeLast() }
                cont.resume(returning: s)
            }
        }
    }
}

// =====================================================================
// MARK: - Gmail, linked directly (IMAP + SMTP with a Google "app password")
// The address is kept in Settings, the app password only in the Keychain on this Mac.
// Zuffi reads your newest emails and sends a reply only when you press Send.
// =====================================================================

enum MailLinkError: LocalizedError {
    case closed, timeout, login(String), server(String)
    var errorDescription: String? {
        switch self {
        case .closed: return "The connection to Gmail closed."
        case .timeout: return "Gmail took too long to answer."
        case .login(let s): return "Gmail didn't accept the sign-in. Check the address and the app password. (\(s))"
        case .server(let s): return "Gmail said: \(s)"
        }
    }
}

/// A tiny TLS text connection (IMAP / SMTP speak in lines).
final class MailWire: @unchecked Sendable {
    private let conn: NWConnection
    private let q = DispatchQueue(label: "zuffi.mail.wire")
    private let lock = NSLock()
    private var buffer = Data()
    init(host: String, port: UInt16) {
        conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tls)
    }
    func open(timeout: Double = 15) async throws {
        final class Once: @unchecked Sendable { var done = false; let l = NSLock()
            func fire() -> Bool { l.lock(); defer { l.unlock() }; if done { return false }; done = true; return true } }
        let once = Once()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready: if once.fire() { c.resume() }
                case .failed(let e): if once.fire() { c.resume(throwing: e) }
                case .cancelled: if once.fire() { c.resume(throwing: MailLinkError.closed) }
                default: break
                }
            }
            conn.start(queue: q)
            q.asyncAfter(deadline: .now() + timeout) { if once.fire() { c.resume(throwing: MailLinkError.timeout) } }
        }
    }
    func close() { conn.cancel() }
    func send(_ s: String) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            conn.send(content: Data(s.utf8), completion: .contentProcessed { e in if let e { c.resume(throwing: e) } else { c.resume() } })
        }
    }
    private func receiveOnce() async throws -> Data {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { data, _, complete, e in
                if let e { c.resume(throwing: e) } else if let data, !data.isEmpty { c.resume(returning: data) }
                else if complete { c.resume(throwing: MailLinkError.closed) } else { c.resume(returning: Data()) }
            }
        }
    }
    /// Reads until `done(text so far)` says the answer is complete; returns that text and keeps anything after it.
    func read(until done: @Sendable (String) -> Range<String.Index>?, timeout: Double = 25) async throws -> String {
        let start = Date()
        while true {
            let text = String(decoding: buffer, as: UTF8.self)
            if let r = done(text) {
                let out = String(text[..<r.upperBound])
                buffer = Data(text[r.upperBound...].utf8)
                return out
            }
            if Date().timeIntervalSince(start) > timeout { throw MailLinkError.timeout }
            buffer.append(try await receiveOnce())
        }
    }
}

@MainActor
final class GmailLink: ObservableObject {
    static let shared = GmailLink()
    struct Mail: Identifiable, Hashable { let id: String; let uid: String; let from: String; let fromAddress: String; let subject: String; let date: Date?; let unread: Bool; let messageId: String; let gmailId: String }
    @Published private(set) var address = UserDefaults.standard.string(forKey: "gmailAddress") ?? ""
    @Published private(set) var mails: [Mail] = []
    @Published private(set) var status = ""
    @Published private(set) var loading = false
    var linked: Bool { !address.isEmpty && !(KeychainStore.shared.get("gmail-app-password") ?? "").isEmpty }

    /// Saves the address and app password after checking they work.
    func link(address a: String, appPassword p: String) async -> Bool {
        let addr = a.trimmingCharacters(in: .whitespaces), pass = p.replacingOccurrences(of: " ", with: "")
        guard addr.contains("@"), pass.count >= 12 else { status = "Enter your Gmail address and the 16-letter app password."; return false }
        status = "Checking with Gmail…"
        do {
            let w = try await imapLogin(addr, pass); w.close()
            UserDefaults.standard.set(addr, forKey: "gmailAddress"); address = addr
            KeychainStore.shared.set("gmail-app-password", value: pass)
            status = "Gmail linked ✓"
            await refresh()
            return true
        } catch { status = error.localizedDescription; return false }
    }
    func unlink() {
        KeychainStore.shared.set("gmail-app-password", value: "")
        UserDefaults.standard.removeObject(forKey: "gmailAddress"); address = ""; mails = []; status = "Gmail unlinked."
    }

    private var tagN = 0
    private func tag() -> String { tagN += 1; return "z\(tagN)" }
    private func imapLogin(_ addr: String, _ pass: String) async throws -> MailWire {
        let w = MailWire(host: "imap.gmail.com", port: 993)
        try await w.open()
        _ = try await w.read(until: { $0.range(of: "\r\n") })
        let t = tag()
        try await w.send("\(t) LOGIN \(Self.quote(addr)) \(Self.quote(pass))\r\n")
        let r = try await w.read(until: { Self.tagged($0, t) })
        guard Self.ok(r, t) else { w.close(); throw MailLinkError.login(Self.lastLine(r)) }
        return w
    }
    private func command(_ w: MailWire, _ cmd: String) async throws -> String {
        let t = tag()
        try await w.send("\(t) \(cmd)\r\n")
        let r = try await w.read(until: { Self.tagged($0, t) })
        guard Self.ok(r, t) else { throw MailLinkError.server(Self.lastLine(r)) }
        return r
    }

    /// The newest 15 emails in the inbox.
    func refresh() async {
        guard linked, !loading else { return }
        loading = true; defer { loading = false }
        do {
            let w = try await imapLogin(address, KeychainStore.shared.get("gmail-app-password") ?? "")
            defer { w.close() }
            let sel = try await command(w, "SELECT INBOX")
            let total = Int(sel.range(of: #"\* (\d+) EXISTS"#, options: .regularExpression).map { sel[$0].filter(\.isNumber) } ?? "0") ?? 0
            guard total > 0 else { mails = []; status = "Your inbox is empty."; return }
            let from = max(1, total - 14)
            let r = try await command(w, "FETCH \(from):\(total) (UID FLAGS X-GM-MSGID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE MESSAGE-ID)])")
            mails = Self.parse(r).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            status = ""
        } catch { status = error.localizedDescription }
    }

    /// The text of one email (for "Explain" and "Write a reply").
    func body(_ m: Mail) async -> String {
        guard linked else { return "" }
        do {
            let w = try await imapLogin(address, KeychainStore.shared.get("gmail-app-password") ?? "")
            defer { w.close() }
            _ = try await command(w, "SELECT INBOX")
            let r = try await command(w, "UID FETCH \(m.uid) (BODY.PEEK[TEXT]<0.20000>)")
            return Self.readable(r)
        } catch { return "" }
    }

    /// Sends a reply (only when you press Send).
    func reply(to m: Mail, text: String) async -> Bool {
        guard linked else { return false }
        let pass = KeychainStore.shared.get("gmail-app-password") ?? ""
        do {
            let w = MailWire(host: "smtp.gmail.com", port: 465)
            try await w.open(); defer { w.close() }
            func code(_ expect: String) async throws {
                let r = try await w.read(until: { $0.range(of: #"(^|\r\n)\d{3} [^\r\n]*\r\n"#, options: .regularExpression) })
                guard r.range(of: #"(^|\r\n)\#(expect)\d\d "#, options: .regularExpression) != nil else { throw MailLinkError.server(Self.lastLine(r)) }
            }
            try await code("2")
            try await w.send("EHLO zuffi.local\r\n"); try await code("2")
            let auth = Data("\u{0}\(address)\u{0}\(pass)".utf8).base64EncodedString()
            try await w.send("AUTH PLAIN \(auth)\r\n"); try await code("2")
            try await w.send("MAIL FROM:<\(address)>\r\n"); try await code("2")
            try await w.send("RCPT TO:<\(m.fromAddress)>\r\n"); try await code("2")
            try await w.send("DATA\r\n"); try await code("3")
            let subj = m.subject.lowercased().hasPrefix("re:") ? m.subject : "Re: " + m.subject
            var msg = "From: <\(address)>\r\nTo: <\(m.fromAddress)>\r\nSubject: =?UTF-8?B?\(Data(subj.utf8).base64EncodedString())?=\r\n"
            if !m.messageId.isEmpty { msg += "In-Reply-To: \(m.messageId)\r\nReferences: \(m.messageId)\r\n" }
            msg += "MIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            msg += Data(text.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]) + "\r\n.\r\n"
            try await w.send(msg); try await code("2")
            try? await w.send("QUIT\r\n")
            return true
        } catch { status = error.localizedDescription; return false }
    }

    func openInGmail(_ m: Mail) {
        let hex = UInt64(m.gmailId).map { String($0, radix: 16) } ?? ""
        let url = hex.isEmpty ? "https://mail.google.com/mail/u/0/#inbox" : "https://mail.google.com/mail/u/0/#inbox/\(hex)"
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }

    // MARK: parsing
    nonisolated static func quote(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    nonisolated static func tagged(_ t: String, _ tag: String) -> Range<String.Index>? {
        t.range(of: "(^|\r\n)\(tag) (OK|NO|BAD)[^\r\n]*\r\n", options: .regularExpression)
    }
    nonisolated static func ok(_ t: String, _ tag: String) -> Bool { t.range(of: "(^|\r\n)\(tag) OK", options: .regularExpression) != nil }
    nonisolated static func lastLine(_ t: String) -> String { t.split(separator: "\r\n").last.map(String.init) ?? t }

    /// "=?UTF-8?B?…?=" and "=?UTF-8?Q?…?=" → readable text.
    nonisolated static func decodeWords(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#) else { return s }
        var out = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let r = Range(m.range, in: s), let er = Range(m.range(at: 2), in: s), let tr = Range(m.range(at: 3), in: s) else { continue }
            let enc = s[er].uppercased(), txt = String(s[tr])
            var decoded: String?
            if enc == "B" { decoded = Data(base64Encoded: txt + String(repeating: "=", count: (4 - txt.count % 4) % 4)).map { String(decoding: $0, as: UTF8.self) } }
            else { decoded = quotedPrintable(txt.replacingOccurrences(of: "_", with: " ")) }
            if let decoded { out.replaceSubrange(Range(m.range, in: out) ?? r, with: decoded) }
        }
        return out.replacingOccurrences(of: #"\?=\s+=\?"#, with: "", options: .regularExpression)
    }
    nonisolated static func quotedPrintable(_ s: String) -> String {
        let u = Array(s.utf8); var out: [UInt8] = []; var i = 0
        func hex(_ c: UInt8) -> UInt8? {
            switch c { case 48...57: return c - 48; case 65...70: return c - 55; case 97...102: return c - 87; default: return nil }
        }
        while i < u.count {
            if u[i] == 61 {                                   // "="
                if i + 2 < u.count, let a = hex(u[i + 1]), let b = hex(u[i + 2]) { out.append(a << 4 | b); i += 3; continue }
                if i + 1 < u.count, u[i + 1] == 13 || u[i + 1] == 10 {      // soft line break
                    i += (i + 2 < u.count && u[i + 1] == 13 && u[i + 2] == 10) ? 3 : 2; continue
                }
            }
            out.append(u[i]); i += 1
        }
        return String(decoding: out, as: UTF8.self)
    }
    nonisolated static func parse(_ r: String) -> [Mail] {
        var out: [Mail] = []
        let parts = r.components(separatedBy: "\r\n* ").map { $0.hasPrefix("* ") ? String($0.dropFirst(2)) : $0 }
        for p in parts where p.contains("FETCH") {
            func grab(_ pat: String) -> String { p.range(of: pat, options: .regularExpression).map { String(p[$0]) } ?? "" }
            let uid = grab(#"UID \d+"#).filter(\.isNumber)
            let gm = grab(#"X-GM-MSGID \d+"#).filter(\.isNumber)
            let unread = !grab(#"FLAGS \([^)]*\)"#).contains("\\Seen")
            // header lines (folded lines joined)
            let unfolded = p.replacingOccurrences(of: #"\r\n[ \t]+"#, with: " ", options: .regularExpression)
            func header(_ name: String) -> String {
                guard let r = unfolded.range(of: "(?im)^\(name):[^\r\n]*", options: .regularExpression) else { return "" }
                return decodeWords(String(unfolded[r].dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces))
            }
            let fromRaw = header("From")
            let addr = fromRaw.range(of: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+"#, options: .regularExpression).map { String(fromRaw[$0]) } ?? fromRaw
            var name = fromRaw.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " \""))
            if name.isEmpty { name = addr }
            let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "EEE, d MMM yyyy HH:mm:ss Z"
            let ds = header("Date").replacingOccurrences(of: #"\s*\([^)]*\)$"#, with: "", options: .regularExpression)
            let date = df.date(from: ds) ?? { df.dateFormat = "d MMM yyyy HH:mm:ss Z"; return df.date(from: ds) }()
            guard !uid.isEmpty else { continue }
            out.append(Mail(id: uid, uid: uid, from: name, fromAddress: addr, subject: header("Subject").isEmpty ? "(no subject)" : header("Subject"),
                            date: date, unread: unread, messageId: header("Message-ID"), gmailId: gm))
        }
        return out
    }
    /// The readable part of a raw email body (plain text preferred; HTML tags stripped; base64 / quoted-printable decoded).
    nonisolated static func readable(_ raw: String) -> String {
        var t = raw
        if let r = t.range(of: "}\r\n") { t = String(t[r.upperBound...]) }
        // multipart: prefer the text/plain part
        if let plain = t.range(of: #"(?is)Content-Type:\s*text/plain.*?\r\n\r\n(.*?)(\r\n--|$)"#, options: .regularExpression) {
            var part = String(t[plain])
            let b64 = part.range(of: #"(?i)Content-Transfer-Encoding:\s*base64"#, options: .regularExpression) != nil
            let qp = part.range(of: #"(?i)Content-Transfer-Encoding:\s*quoted-printable"#, options: .regularExpression) != nil
            if let h = part.range(of: "\r\n\r\n") { part = String(part[h.upperBound...]) }
            if let e = part.range(of: "\r\n--") { part = String(part[..<e.lowerBound]) }
            if b64, let d = Data(base64Encoded: part.replacingOccurrences(of: "\r\n", with: "")) { part = String(decoding: d, as: UTF8.self) }
            else if qp { part = quotedPrintable(part) }
            t = part
        } else if t.range(of: "=\r\n") != nil || t.range(of: #"=[0-9A-F]{2}"#, options: .regularExpression) != nil { t = quotedPrintable(t) }
        t = t.replacingOccurrences(of: #"(?is)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<br\s*/?>|</p>|</div>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"\r\n\)\r\n.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return String(t.trimmingCharacters(in: .whitespacesAndNewlines).prefix(6000))
    }
}


// MARK: - Gmail by voice (when Gmail is linked): "what needs me in my email?", "read the email from Sam",
// "reply to Sam saying I'll be there at 6" → she writes it, reads it back, and sends only after you say "send".
@MainActor
final class GmailVoice {
    static let shared = GmailVoice()
    private struct Draft { let mail: GmailLink.Mail; var text: String; let made: Date }
    private var draft: Draft?
    private var last: GmailLink.Mail?

    private static let checkRE = #"\b(check|read|any|new|unread|what'?s|what is|whats|what needs|anything)\b.*\b(e-?mails?|mails?|inbox|gmail)\b|\b(e-?mails?|inbox|gmail)\b.*\b(need|important|new|today)\b"#
    private static let readRE = #"^(?:read|open|show|what does|what did)\s+(?:me\s+)?(?:the\s+)?(?:latest\s+|last\s+|new\s+)?(?:e-?mail|mail|message)\s+from\s+(.+?)(?:\s+say)?\??$"#
    private static let replyRE = #"^(?:reply|respond|answer|write back|email|mail)\s+(?:to\s+)?(.+?)\s*(?:saying|that|and say|to say|:|,)\s+(.+)$"#

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"^(?:can you|could you|please|zuffi,?)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
    }
    private static func isSend(_ t: String) -> Bool { t.range(of: #"^(yes,? )?(send|send it|send now|go ahead|ok send|yes)$"#, options: .regularExpression) != nil }
    private static func isCancel(_ t: String) -> Bool { t.range(of: #"^(cancel|don'?t send|no|stop|forget it)$"#, options: .regularExpression) != nil }

    func claims(_ raw: String) -> Bool {
        guard GmailLink.shared.linked else { return false }
        let t = Self.clean(raw).lowercased()
        if t.contains("whatsapp") { return false }
        if draft != nil, Self.isSend(t) || Self.isCancel(t) || t.hasPrefix("change") || t.hasPrefix("make it") { return true }
        if t.range(of: Self.checkRE, options: .regularExpression) != nil { return true }
        if t.range(of: Self.readRE, options: .regularExpression) != nil { return true }
        if let m = t.range(of: Self.replyRE, options: .regularExpression).map({ String(t[$0]) }), !m.isEmpty {
            return t.contains("email") || t.contains("mail") || sender(Self.match(Self.replyRE, t)?.first ?? "") != nil
        }
        return false
    }

    func handle(_ raw: String) async -> String? {
        let o = Self.clean(raw), t = o.lowercased()
        if let d = draft, Date().timeIntervalSince(d.made) > 600 { draft = nil }
        if let d = draft {
            if Self.isSend(t) {
                draft = nil
                return await GmailLink.shared.reply(to: d.mail, text: d.text) ? "Sent to \(d.mail.from)! ✅" : "I couldn't send it: \(GmailLink.shared.status)"
            }
            if Self.isCancel(t) { draft = nil; return "Okay, I won't send it." }
            if t.hasPrefix("change") || t.hasPrefix("make it") {
                let new = await AIService.shared.oneShot("Rewrite this email reply as asked: \"\(o)\". Return ONLY the reply.\n\n\(d.text)", system: "You write the user's emails: friendly, clear, short.") ?? ""
                if !new.isEmpty { draft?.text = new }
                VoiceEngine.shared.listenAfterSpeech = true
                return "Here it is now: \"\(draft?.text ?? d.text)\". Say send, change something, or cancel."
            }
        }
        if let m = Self.match(Self.replyRE, o), m.count == 2 {
            if GmailLink.shared.mails.isEmpty { await GmailLink.shared.refresh() }
            guard let mail = sender(m[0]) else { return "I couldn't find an email from \(m[0]) in your latest mail." }
            let body = await GmailLink.shared.body(mail)
            let text = await AIService.shared.oneShot("""
                Write the user's reply to this email. What they want to say: "\(m[1])".
                Keep it short, warm and natural, in the language of the email, signed with their first name (\(AssistantPrefs.displayName.components(separatedBy: " ").first ?? "")) if known.
                Return ONLY the reply text.
                EMAIL from \(mail.from) — "\(mail.subject)":
                \(body.prefix(3000))
                """, system: "You write the user's emails: friendly, clear, short.") ?? m[1]
            draft = Draft(mail: mail, text: text.trimmingCharacters(in: .whitespacesAndNewlines), made: Date())
            last = mail
            VoiceEngine.shared.listenAfterSpeech = true
            return "Reply to \(mail.from): \"\(draft!.text)\". Say send, tell me what to change, or cancel."
        }
        if let m = Self.match(Self.readRE, t) {
            if GmailLink.shared.mails.isEmpty { await GmailLink.shared.refresh() }
            guard let mail = sender(m.first ?? "") else { return "I couldn't find an email from \(m.first ?? "them")." }
            last = mail
            let body = await GmailLink.shared.body(mail)
            let sum = await AIService.shared.oneShot("In 2 short spoken sentences: what does this email say and what (if anything) must the user do, by when?\nFrom \(mail.from) — \(mail.subject)\n\(body.prefix(4000))",
                                                     system: "You read emails to the user like a helpful friend. Plain sentences, no lists.") ?? ""
            return "\(mail.from) — \(mail.subject). " + (sum.isEmpty ? String(body.prefix(300)) : sum)
        }
        if t.range(of: Self.checkRE, options: .regularExpression) != nil { return await whatNeedsYou() }
        return nil
    }

    /// Like Taby: "what needs you" — bills, invitations, deadlines and people waiting for an answer; newsletters skipped.
    func whatNeedsYou() async -> String {
        await GmailLink.shared.refresh()
        let list = GmailLink.shared.mails.prefix(15)
        guard !list.isEmpty else { return GmailLink.shared.status.isEmpty ? "Your inbox is empty." : GmailLink.shared.status }
        let lines = list.map { "\($0.unread ? "[new] " : "")\($0.from) — \($0.subject)" }.joined(separator: "\n")
        let r = await AIService.shared.oneShot("""
            These are the user's latest emails. Tell them, in 2–3 short spoken sentences, only what needs them: bills, payments, invitations, \
            deadlines, check-ins, and people waiting for a reply. Skip newsletters, promotions and notifications. If nothing needs them, say so warmly.
            \(lines)
            """, system: "You are Zuffi, sorting the user's email like a helpful friend. Plain sentences, no lists, no markdown.") ?? ""
        if !r.isEmpty { return r.trimmingCharacters(in: .whitespacesAndNewlines) }
        let unread = list.filter(\.unread)
        return unread.isEmpty ? "No new emails." : "You have \(unread.count) new: " + unread.prefix(3).map { "\($0.from) about \($0.subject)" }.joined(separator: "; ") + "."
    }

    private func sender(_ who: String) -> GmailLink.Mail? {
        let w = who.lowercased().replacingOccurrences(of: #"^(the |my )?(e-?mail|mail|message)\s*(from\s+)?"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if ["him", "her", "them", "it", "that", "this"].contains(w) { return last }
        guard w.count >= 2 else { return nil }
        return GmailLink.shared.mails.first { $0.from.lowercased().contains(w) || $0.fromAddress.lowercased().contains(w) }
    }
    private static func match(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1..<m.numberOfRanges).compactMap { Range(m.range(at: $0), in: s).map { String(s[$0]) } }
    }
}
