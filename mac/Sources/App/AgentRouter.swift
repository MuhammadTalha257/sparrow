import Foundation
import AppKit
import Contacts

// =====================================================================
// MARK: - Zuffi's agent team
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

    /// Which inbox Zuffi last talked about, so "reply to Ahmed…" goes to the right app.
    enum Channel { case none, mail, whatsapp }
    static var lastChannel: Channel = .none

    /// Handles a request if any agent can. nil = nobody could (the caller asks the AI instead).
    func handle(_ raw: String) async -> String? {
        if let r = await screen(raw) { return r }
        if let r = await ZuffiTeam.shared.handle(raw) { return r }     // "switch to the finance agent and tell me…", "who are you guys?"
        if let r = await ZuffiSelf.handle(raw) { return r }          // Zuffi's own controls, instantly
        if let r = await askChatApp(raw) { return r }
        // Email first: a reply like "tell him yes and thanks" must not be split into steps.
        // Business jobs said in one breath ("make a post and share it with all clients", "we have 20% off today") stay whole.
        if ZuffiPlan.shared.isBusiness, let r = ZuffiCRM.shared.handle(raw) { return r }
        if WhatsAppAgent.shared.claims(raw), let r = await WhatsAppAgent.shared.handle(raw) { return r }
        if MailAgent.shared.claims(raw), let r = await MailAgent.shared.handle(raw) { return r }
        let steps = split(raw)
        if steps.count <= 1 {
            if let r = await single(raw) { return r }
            return await ZuffiSelf.aiRoute(raw)                      // a command the rules didn't know → one quick AI pick
        }
        var replies: [String] = []
        var anyDone = false
        for (i, step) in steps.enumerated() {
            var r = await ZuffiSelf.handle(step)
            if r == nil { r = await single(step) }
            if r == nil { r = await WebHub.shared.ask(step) }
            if let r { replies.append(r); anyDone = true } else { replies.append("I couldn't do \"\(step)\".") }
            // Give an app a moment to open before the next step talks to it.
            if i < steps.count - 1, step.lowercased().hasPrefix("open") || (r ?? "").hasPrefix("Opening") {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
            }
        }
        return anyDone ? replies.joined(separator: " ") : nil
    }

    /// "ask ChatGPT …", "ask Claude …", "Copilot se poocho …" → the user's own chat app gets the question.
    private func askChatApp(_ raw: String) async -> String? {
        let pattern = #"^(?:ask|open|use)\s+(chat ?gpt|claude|copilot|gemini|grok|perplexity)(?:\s+(?:app))?(?:\s*[,:]?\s*(?:and\s+)?(?:ask\s+)?(?:it\s+|him\s+)?(?:about\s+)?)?(.*)$"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              let a = Range(m.range(at: 1), in: raw) else { return nil }
        let which = raw[a].lowercased().replacingOccurrences(of: " ", with: "")
        let q = Range(m.range(at: 2), in: raw).map { String(raw[$0]).trimmingCharacters(in: .whitespaces) } ?? ""
        // "open Claude" with nothing to ask is just opening an app — leave it to the normal opener.
        if q.isEmpty, raw.lowercased().hasPrefix("open") { return nil }
        let id = ["chatgpt": "chatgpt-app", "claude": "claude-app", "copilot": "copilot-app", "gemini": "gemini-app", "grok": "grok-app", "perplexity": "perplexity-app"][which] ?? "chatgpt-app"
        return await InstalledAI.handOff(appID: id, question: q)
    }

    /// The screen agent: answers to its questions, "stop", "what's on my screen?", "on screen, …".
    private func screen(_ raw: String) async -> String? {
        let t = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))
        let agent = ScreenAgent.shared
        if agent.awaitingConfirmation {
            if t.range(of: #"^(yes|yeah|yep|yup|ok|okay|sure|go ahead|do it|haan|han|ji|jee|theek hai|kar do|yes do it|confirm)\b"#, options: .regularExpression) != nil {
                agent.confirm(true); return "Okay, doing it."
            }
            if t.range(of: #"^(no|nope|don'?t|do not|cancel|stop|nahi|nahin|mat karo|ruko)\b"#, options: .regularExpression) != nil {
                agent.confirm(false); return "Okay, I won't."
            }
        }
        if agent.running, t.range(of: #"^(stop|stop it|cancel|that'?s enough|enough|ruk jao|ruko|bas|band karo)$"#, options: .regularExpression) != nil {
            agent.stop(); return "Stopping."
        }
        guard t.contains("screen") || t.hasPrefix("click ") || t.hasPrefix("scroll ") else { return nil }
        // Do something: "on screen, …", "use my screen to …", "click the Sign in button", "scroll down"
        let doPrefix = #"^(?:on (?:my |the )?(?:mac )?screen[,:]?\s+|use (?:my |the )?screen (?:to|and)\s+|(?:control|use) (?:my |the )?(?:mac|computer|screen) (?:to|and)\s+|screen (?:pe|par)\s+)"#
        if let r = t.range(of: doPrefix, options: .regularExpression) {
            let task = String(raw.dropFirst(t.distance(from: t.startIndex, to: r.upperBound))).trimmingCharacters(in: .whitespaces)
            if !task.isEmpty { return await agent.run(task) }
        }
        if t.range(of: #"^(click|double click|right click|scroll)\b"#, options: .regularExpression) != nil { return await agent.run(raw) }
        // Look: "what's on my screen", "read my screen", "check what you see on my screen", "screen pe kya hai"
        if t.range(of: #"\b(what|see|check|read|look|describe|tell me|explain|kya|dekho|batao|summari[sz]e|translate)\b"#, options: .regularExpression) != nil {
            return await agent.describe(raw)
        }
        return nil
    }

    private func single(_ raw: String) async -> String? {
        let base = Translit.toCommand(raw)
        let lowered = base.lowercased()
        if lowered.range(of: #"^(reset|fix) (zuffi'?s? )?(position|place)$|^(bring|put) zuffi back( to the top)?$|^where (are you|is zuffi)\??$"#, options: .regularExpression) != nil {
            IslandDrag.resetPosition(); return "I'm back at the top of your screen 🐰"
        }
        if SparrowBubble.shared.isHidden,
           lowered.range(of: #"^(come back|show (yourself|sparrow|up)|bring (sparrow|yourself) back|wapas aao|where are you|sparrow)$"#, options: .regularExpression) != nil {
            SparrowBubble.shared.restore(); return "I'm back! 🐰"
        }
        if lowered.range(of: #"^(hide|minimi[sz]e) (yourself|sparrow|the island)$|^go hide$"#, options: .regularExpression) != nil {
            SparrowBubble.shared.hideIsland(); return "I'll wait in my little bubble. Click it when you need me."
        }
        // Linked WhatsApp: "link whatsapp", "unlink whatsapp", "read my whatsapp messages out loud"
        if lowered.range(of: #"^(link|connect|set up|setup) (my )?whats ?app( to zuffi)?$"#, options: .regularExpression) != nil {
            guard ZuffiFocus.whatsapp else { return "WhatsApp linking is switched off in this version of Zuffi." }
            guard ZuffiPlan.shared.isBusiness else { WhatsAppLink.shared.showWindow(); return "Linking WhatsApp is part of Zuffi Business — on Pro, WhatsApp stays closed." }
            WhatsAppLink.shared.showWindow()
            return "Opening WhatsApp. On your phone: WhatsApp → Settings → Linked devices → Link a device, then scan the code."
        }
        if lowered.range(of: #"^(unlink|disconnect) (my )?whats ?app$"#, options: .regularExpression) != nil {
            await WhatsAppLink.shared.unlink(); return "WhatsApp is unlinked from Zuffi."
        }
        if lowered.range(of: #"^(read|say) (my )?(new )?whats ?app (messages )?(out loud|aloud)( from now on)?$"#, options: .regularExpression) != nil {
            WhatsAppLink.shared.readAloud = true; return "Okay — I’ll read new WhatsApp messages out loud. Say “stop reading WhatsApp” to turn it off."
        }
        if lowered.range(of: #"^stop reading (my )?whats ?app( messages)?$"#, options: .regularExpression) != nil {
            WhatsAppLink.shared.readAloud = false; return "Okay, I’ll stop reading them out."
        }
        // Room mode: "listen to the room", "room mode on/off", "stop listening to the room"
        if lowered.range(of: #"^(start |turn on |switch on )?(room mode|listen(ing)? to (the |this )?(room|conversation|everyone))( on)?$"#, options: .regularExpression) != nil {
            RoomListener.shared.start()
            return "Room mode is on. I’ll follow the conversation and show the topics in the notch — nothing is saved. Say “stop room mode” to end it."
        }
        if lowered.range(of: #"^(stop|end|turn off|switch off) (room mode|listening to (the )?(room|conversation))$|^room mode off$"#, options: .regularExpression) != nil {
            RoomListener.shared.stop()
            return "Room mode is off. I’ve forgotten what I heard."
        }
        // Screen recording: "record my screen", "start screen recording", "stop recording"
        if lowered.range(of: #"^(start |begin )?(record|recording|capture)( my| the)? (screen|display)( recording)?$|^(start|begin|make) (a )?screen ?(recording|record|video)$|^screen ?record(ing)?$"#, options: .regularExpression) != nil {
            let r = await ScreenRecorder.shared.start()
            if ScreenRecorder.shared.isRecording {
                // a small "recording" card with a Stop button, after the reply
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { MainActor.assumeIsolated {
                    let st = AppState.shared
                    st.noteIsAlert = false; st.noteAction = "screen"
                    st.noteMessage = "● Recording your screen\nSay “Zuffi, stop recording” or press Stop."
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                } }
            }
            return r
        }
        if ScreenRecorder.shared.isRecording, lowered.range(of: #"^(stop|end|finish|save)( the| my)?( screen)? (recording|record|video|capture)$|^stop$"#, options: .regularExpression) != nil {
            AppState.shared.noteAction = nil
            return await ScreenRecorder.shared.stop()
        }
        if lowered.range(of: #"^(start|begin|take|record)( the| my)? (meeting )?(notes|minutes)|^(start|begin) (recording|transcribing) (the )?meeting|^meeting notes( start)?$|^take notes$"#, options: .regularExpression) != nil
            || (lowered.range(of: #"^(?:start|begin|take|turn on|record|start taking|switch on)(?:\s+(?:the|my|this|meeting|call|video|zoom|teams|whatsapp|notes|minutes|recording|transcript|taking|of|on))+$"#, options: .regularExpression) != nil
                && lowered.range(of: #"\b(meeting|notes|minutes|recording|transcript)\b"#, options: .regularExpression) != nil) {
            return MeetingNotes.shared.start()
        }
        if lowered.range(of: #"^(stop|end|finish|save)( the| my)? (meeting )?(notes|minutes|recording)|^meeting (khatam|over|done)"#, options: .regularExpression) != nil {
            return await MeetingNotes.shared.stop()
        }
        // Job agent: "type my email" fills the box you clicked in an application form with your CV details.
        if let m = lowered.range(of: #"^(?:type|fill|paste|enter|likho) (?:in )?(?:my |the )?(email|e-mail|phone(?: number)?|mobile(?: number)?|number|full name|first name|last name|surname|name|linkedin(?: url| profile)?|website|portfolio|github|city|location|address|headline|cover letter|pitch|summary)$"#, options: .regularExpression) {
            let field = String(lowered[m]).replacingOccurrences(of: #"^(?:type|fill|paste|enter|likho) (?:in )?(?:my |the )?"#, with: "", options: .regularExpression)
            guard let value = await WebHub.shared.jobField(field) else {
                return "I don't have your \(field) yet. Add your CV in the job agent and I'll remember it."
            }
            if let front = AppState.shared.lastExternalApp { front.activate(options: []) }
            try? await Task.sleep(nanoseconds: 450_000_000)
            // Paste (fast, keeps line breaks, never presses Enter by accident), then put your clipboard back.
            let pb = NSPasteboard.general, old = pb.string(forType: .string)
            pb.clearContents(); pb.setString(value, forType: .string)
            _ = CommandEngine.shared.runAppleScript("tell application \"System Events\" to keystroke \"v\" using command down")
            try? await Task.sleep(nanoseconds: 600_000_000)
            if let old { pb.clearContents(); pb.setString(old, forType: .string) }
            return field.contains("cover") ? "Pasted your cover letter." : "Typed your \(field)."
        }
        // Job agent: CV, job search, cover letters, applications → the shared app's job agent.
        if lowered.range(of: #"\b(cv|resume|résumé)\b|\b(jobs?|vacanc(y|ies)|naukri|cover letter|job applications?|job tracker)\b"#, options: .regularExpression) != nil,
           lowered.range(of: #"^(find|search|look for|show|get|analy[sz]e|review|check|score|rate|improve|tailor|customi[sz]e|write|make|apply|my|which|what|open|job|jobs|meri|mera|mere)\b|(dhoondo|dhundo|talash karo|dikhao|check karo)$"#, options: .regularExpression) != nil,
           let r = await WebHub.shared.ask(raw) {
            return r
        }
        // Mac control first (shut down, Wi-Fi, Bluetooth, windows…), on the words as said and as understood.
        if let r = MacControl.shared.handle(raw) ?? MacControl.shared.handle(base) { return r }
        let t = CommandEngine.shared.intent(base) ?? base
        if t != base { appendAppLog("agents.log", "understood \"\(raw)\" as \"\(t)\"") }
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

    /// Hands-free: is this clearly something to do (so Zuffi acts without hearing its name first)?
    func isClearRequest(_ s: String) -> Bool {
        let base = Translit.toCommand(s)
        if MacControl.shared.matches(s) || MacControl.shared.matches(base) { return true }
        if CommandEngine.shared.intent(base) != nil { return true }
        if split(s).count > 1 { return true }
        let t = base.lowercased()
        let starts = ["find jobs", "analyse my cv", "analyze my cv", "remind me", "add task", "take a note", "note ", "save this", "save that", "message ", "text ", "whatsapp ",
                      "what time", "what's the time", "what's the weather", "weather", "prayer times", "battery", "lock screen", "dark mode",
                      "light mode", "screenshot", "new chat", "naya chat", "what's on", "what do i have", "my tasks", "brief me", "snooze"]
        return starts.contains { t.hasPrefix($0) } || (t.contains("number") && (t.contains("save") || t.contains("what")))
    }

    func isAction(_ s: String) -> Bool {
        let base = Translit.toCommand(s)
        if MacControl.shared.matches(s) { return true }
        if CommandEngine.shared.intent(base) != nil { return true }
        let t = base.lowercased()
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
        // WhatsApp  ("Ahmed ko whatsapp karo ke main aa raha hoon", "whatsapp check karo")
        (#"^(.+?)\s+(?:ko|nu)\s+(?:whats ?app|whatsapp)\s+(?:pe\s+|par\s+|pr\s+|te\s+)?(?:karo|kar do|kardo|bhejo|bhej do|message karo|msg karo|reply karo|likho)\s*(?:ke|keh|ki|:)?\s+(.+)$"#, "whatsapp $1 saying $2"),
        (#"^(?:whats ?app|whatsapp)\s+(?:check karo|check kar do|dekho|dikhao|parho|batao|sunao|check kro)$|^(?:whats ?app|whatsapp)\s+(?:pe|par|pr|te)\s+(?:koi\s+)?(?:naya|new)\s+(?:message|msg)\s+(?:aaya|aya|hai)\s*(?:hai)?\??$"#, "check whatsapp"),
        // email  ("email check karo", "naye email", "Ahmed ko reply karo ke main kal bhej dunga")
        (#"^(?:mere\s+)?(?:naye|nai|new)?\s*(?:e-?mails?|mails?|inbox)\s+(?:check karo|check kar do|dekho|dikhao|parho|parh do|batao|sunao|check kro)$|^(?:koi\s+)?(?:naya|nayi|new)\s+(?:e-?mail|mail)\s+(?:aayi|aaya|hai|ayi|aya)\s*(?:hai)?\??$"#, "check my emails"),
        (#"^(.+?)\s+(?:ko|nu)\s+(?:reply|jawab)\s+(?:karo|kar do|kardo|do|de do|likho|bhejo)\s*(?:ke|keh|ki|that|:)?\s+(.+)$"#, "reply to $1 saying $2"),
        (#"^(.+?)\s+(?:ki|ka|di|da)\s+(?:e-?mail|mail)\s+(?:parho|parh do|sunao|dikhao|kholo)$"#, "read the email from $1"),
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
        // Mac control
        (#"^(?:mac|computer|laptop|system)\s+(?:ko\s+)?(?:band karo|band kar do|band kardo|off karo|shut down karo|bnd karo)$"#, "shut down mac"),
        (#"^(?:mac|computer|laptop|system)\s+(?:ko\s+)?(?:restart karo|restart kar do|dobara chalao)$"#, "restart mac"),
        (#"^(?:mac|computer|laptop)\s+(?:ko\s+)?(?:sula do|sleep karo|sleep kar do)$"#, "sleep mac"),
        (#"^(?:wifi|wi-fi|net)\s+(?:band karo|band kar do|off karo|off kar do|band)$"#, "turn off wifi"),
        (#"^(?:wifi|wi-fi|net)\s+(?:on karo|on kar do|chalu karo|chalao|on)$"#, "turn on wifi"),
        (#"^bluetooth\s+(?:band karo|band kar do|off karo)$"#, "turn off bluetooth"),
        (#"^bluetooth\s+(?:on karo|on kar do|chalu karo|chalao)$"#, "turn on bluetooth"),
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
    private let noAccess = "I need access to Contacts: System Settings → Privacy & Security → Contacts → Zuffi."

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
        // "this" = the text you copied, or else Zuffi's last answer.
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
        return "I couldn't reach Notes. Allow Zuffi under System Settings → Privacy & Security → Automation."
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

// =====================================================================
// MARK: - Zuffi's own controls by voice ("change your colour", "male voice", "turn on water reminders",
//   "make a folder called Invoices", "open WhatsApp", "open the business page"…)
//   Fast rules first (instant); anything else that sounds like a command goes to a quick AI that picks one action.
//   Zuffi only says she did something when she actually did it.
// =====================================================================
@MainActor
enum ZuffiSelf {
    static let colours: [String: String] = [
        "blue": "#4F6BFF", "indigo": "#6366F1", "purple": "#8B5CF6", "violet": "#8B5CF6", "teal": "#0E9F9A", "green": "#16A34A",
        "orange": "#EA7A2A", "rose": "#E5487A", "pink": "#E5487A", "red": "#E5484D", "slate": "#475569", "grey": "#475569", "gray": "#475569",
        "yellow": "#E0A126", "gold": "#D4AF37", "mint": "#0F9F76", "black": "#3D4555",
    ]
    static let furWords: [String: String] = ["white": "snow", "snow": "snow", "pink": "blush", "blush": "blush", "peach": "peach", "orange": "peach",
        "honey": "honey", "yellow": "honey", "gold": "honey", "mint": "mint", "green": "mint", "sky": "sky", "blue": "sky", "lilac": "lilac",
        "purple": "lilac", "brown": "cocoa", "cocoa": "cocoa", "grey": "storm", "gray": "storm", "storm": "storm"]

    private static func clean(_ raw: String) -> String {
        raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!?,"))
            .replacingOccurrences(of: #"^(ok(ay)? )?(hey )?zuffi[, ]+|^(please |can you |could you )+|( please)$"#, with: "", options: .regularExpression)
    }
    private static func m(_ t: String, _ p: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
              let r = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        return (0..<r.numberOfRanges).map { i in Range(r.range(at: i), in: t).map { String(t[$0]) } ?? "" }
    }

    /// The instant rules. nil = not one of Zuffi's own controls.
    static func handle(_ raw: String) async -> String? {
        let t = clean(raw)
        if m(t, #"^(open|show|go to)( up)? (your |the |my |zuffi'?s? )?(business|business page|business dashboard|dashboard)( page)?$"#) != nil {
            return perform("open_business", [:])
        }
        if m(t, #"^(open|show)( up)? (your |my |the )?whats ?app$"#) != nil { return perform("open_whatsapp", [:]) }
        if m(t, #"(which|what|best) (free )?(ai|model|ai model|llm)s?\b.*\b(best|for|on|suits?|run)\b.*\b(my |this )?(mac|computer|laptop|device|pc)|^(check|analy[sz]e) (my |this )?(mac|device|computer)( for ai)?$"#) != nil {
            return DeviceCheck.summary
        }
        // The pet: "stop the pet bringing reminders", "never show the pet", "show the pet again"
        if m(t, #"^(stop|don'?t let|no more)( the)? (pet|bunny)( bringing| bring)?( my)? reminders$|^(turn off|disable) pet reminders$"#) != nil {
            UserDefaults.standard.set(false, forKey: "petReminders"); return "Okay — reminders will show at the notch instead of the pet walking in."
        }
        if m(t, #"^(let )?(the )?(pet|bunny) (bring|brings) (my )?reminders$|^(turn on|enable) pet reminders$"#) != nil {
            UserDefaults.standard.set(true, forKey: "petReminders"); UserDefaults.standard.set(false, forKey: "petNever"); return "Okay — I'll walk in with your reminders."
        }
        if m(t, #"^(never|don'?t|do not) (show|bring)( the| your)? (pet|bunny)( on (the )?screen)?( again)?$|^no pet$"#) != nil {
            UserDefaults.standard.set(true, forKey: "petNever"); PetController.shared.hide(); return "Okay — the pet won't come on screen. Reminders show at the notch."
        }
        if m(t, #"^(open|show)( up)? (your |the )?(features|all features)$"#) != nil { return perform("open", ["what": "features"]) }
        if m(t, #"^(open|show)( up)? (your |the |my )?(settings)$"#) != nil { return perform("open", ["what": "settings"]) }
        if m(t, #"^(open|show)( up)? (the )?chat$"#) != nil { return perform("open", ["what": "chat"]) }
        if m(t, #"^(open|show)( up)? (my )?(profile|details)$"#) != nil { return perform("open", ["what": "profile"]) }
        if let c = m(t, #"^(change|set|make|turn)( your| the| zuffi'?s?| my)? (colou?r|theme|accent)( colou?r)?( to| into)? ([a-z]+)$"#) { return perform("set_colour", ["colour": c[6]]) }
        if let c = m(t, #"^(change|set|make|turn)( your| the)? (fur|bunny|bunny colou?r|fur colou?r)( to| into)? ([a-z]+)$"#) { return perform("set_fur", ["colour": c[5]]) }
        if let c = m(t, #"^(switch|change|use|set|give me)( to| me)?( a| the)? (male|man|boy|men'?s|female|woman|girl|lady|bunny|cute|normal)( voice| version)+$"#)
            ?? m(t, #"^(talk|speak) (in|with) (a )?(male|man|boy|female|woman|girl|bunny|cute|normal) voice$"#) {
            return perform("voice", ["kind": c[4]])
        }
        if let c = m(t, #"^(turn on|start|enable|switch on|on|set up|remind me to drink|turn off|stop|disable|switch off|off)( the| my)? (water|coffee|tea|medicine|meds|pill)( reminders?)?( every (\d+) ?(min|minutes|hours?))?$"#) {
            let on = !["turn off", "stop", "disable", "switch off", "off"].contains(c[1])
            var mins = Int(c[6]) ?? 0
            if c[7].hasPrefix("hour") { mins *= 60 }
            return await health(kind: c[3], on: on, every: mins)
        }
        if let c = m(t, #"^(make|create|add|new)( me)?( a)?( new)? folder( called| named| name)?( "?([^"]+?)"?)?( on (the |my )?(desktop|documents|downloads))?$"#)
            ?? m(t, #"^(desktop|documents|downloads) (pe|par|mein|me) (ek )?(naya )?folder (bana|banao|create kar|create karna)( (.+))?$"#) {
            let place = c.count > 10 ? c[10] : (c.count > 1 ? c[1] : "desktop")
            let name = c.count > 7 ? c[7] : (c.count > 6 ? c[6] : "")
            return makeFolder(name.trimmingCharacters(in: .whitespaces), place: ["desktop", "documents", "downloads"].contains(place) ? place : "desktop")
        }
        if let c = m(t, #"^(search|look up|find)( the)? (meaning|definition) of (.+)$|^(what does|what's the meaning of|meaning of|define) (.+?)( mean)?$"#) {
            let w = (c[4].isEmpty ? c[6] : c[4]).trimmingCharacters(in: .whitespaces)
            if !w.isEmpty, w.split(separator: " ").count <= 3, let r = await WebHub.shared.ask("define \(w)") { return r }
        }
        if let c = m(t, #"^(search|google)( for| on google for| google for)? (.+?)( on google| online)?$"#), !c[3].contains("meaning") {
            let q = c[3].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? c[3]
            if let u = URL(string: "https://www.google.com/search?q=\(q)") { NSWorkspace.shared.open(u); return "Searching Google for “\(c[3])”." }
        }
        if m(t, #"^(turn on|start|switch on) room mode$|^room mode on$"#) != nil { RoomListener.shared.start(); return "Room mode is on — nothing is saved." }
        if let c = m(t, #"^(turn|switch|make)( the)? (business|business page|business window)( to)? (dark|light)( mode)?$|^(dark|light) mode( for)?( the)? business$"#) {
            let dark = (c[5] + c[7]) == "dark"; BizLook.shared.set(dark: dark); return "Business is now \(dark ? "dark" : "light")."
        }
        // "what's Begum's number?", "Begum number" → from Zuffi's own records, on this Mac (numbers never go to the AI)
        if let c = m(t, #"^(what'?s|what is|give me|send me|tell me)? ?([a-z][a-z .'-]{1,30}?)('s|s)? (phone |whatsapp |mobile )?(number|no\.?)$"#), !["my", "your", "the", "a"].contains(c[2].trimmingCharacters(in: .whitespaces)),
           // a person's name — not "gave me old messages", "inbox", "leads"…
           c[2].range(of: #"\b(me|my|old|new|messages?|inbox|leads?|records?|clients?|customers?|contacts?|total|all|of|how|many|gave|give|show)\b"#, options: .regularExpression) == nil {
            let who = c[2].trimmingCharacters(in: .whitespaces)
            if let l = ZuffiCRM.shared.leads.first(where: { $0.name.lowercased() == who || $0.name.lowercased().hasPrefix(who) }), !l.phone.isEmpty { return "\(l.display): +\(l.phone.filter(\.isNumber))" }
            if let c = await WhatsAppLink.shared.lookup(who), !c.phone.isEmpty { return "\(c.name): +\(c.phone)" }
            if let n = await ContactsAgent.shared.number(for: who) { return "\(who.capitalized): \(n)" }
            return "I don't have a number for \(who.capitalized) yet. Say “save \(who) number 0300…” and I'll remember it."
        }
        if m(t, #"^(turn|switch) (the )?(mic|microphone) on$|^(mic|microphone) on$"#) != nil { VoiceEngine.shared.setMic(true); return "Mic is on." }
        if m(t, #"^(turn|switch) (the )?(mic|microphone) off$|^(mic|microphone) off$|^mute( yourself)?$"#) != nil { VoiceEngine.shared.setMic(false); return "Mic is off." }
        return nil
    }

    /// Anything else that sounds like an instruction to Zuffi → one quick AI call that picks an action (or none).
    static func aiRoute(_ raw: String) async -> String? {
        let t = clean(raw)
        // only for things about Zuffi herself — ordinary questions go straight to the answer (no extra wait)
        guard t.range(of: #"\b(colou?r|theme|accent|voice|reminders?|water|coffee|medicine|folder|business|whats ?app|mic|microphone|pet|sound|record|recording|music|song|dark|light|fur|room mode|settings|features|profile|chat|zuffi)\b"#, options: .regularExpression) != nil else { return nil }
        guard t.count < 160, t.range(of: #"^(open|show|change|set|make|create|turn|switch|start|stop|enable|disable|use|put|add|remove|hide|close|go|take|play|pause|mute|unmute|link|connect|remind|karo|kar do|bana|kholo|chalao|band)\b|\b(karo|kar do|banao|kholo|band karo)$"#, options: .regularExpression) != nil else { return nil }
        let prompt = """
        The user said to their Mac assistant Zuffi: "\(raw)"
        Pick ONE action Zuffi can do itself, or "none" if it's not one of these:
        open {what: business|whatsapp|features|settings|chat|profile|history|today|data|agents|room}, set_colour {colour}, set_fur {colour},
        voice {kind: male|female|bunny}, health {kind: water|coffee|medicine, on: true|false, every_minutes}, make_folder {name, place: desktop|documents|downloads},
        mic {on}, pet {on}, sound {on}, record_screen {on}, music {cmd: playpause|next track|previous track}, business_look {dark: true|false},
        search_web {query}, define {word}.
        JSON only: {"action":"","args":{}}
        """
        guard let j = await AIService.shared.fastJSON(prompt, system: "You map a spoken command to one app action. Reply with JSON only."),
              let a = j["action"] as? String, a != "none", !a.isEmpty else { return nil }
        let args = (j["args"] as? [String: Any]) ?? [:]
        switch a {
        case "health":
            return await health(kind: args["kind"] as? String ?? "water", on: (args["on"] as? Bool) ?? true, every: (args["every_minutes"] as? Int) ?? 0)
        case "make_folder": return makeFolder(args["name"] as? String ?? "", place: args["place"] as? String ?? "desktop")
        case "define": if let w = args["word"] as? String { return await WebHub.shared.ask("define \(w)") }; return nil
        default: return perform(a, args)
        }
    }

    static func perform(_ action: String, _ args: [String: Any]) -> String? {
        func bool(_ k: String) -> Bool { (args[k] as? Bool) ?? ((args[k] as? String).map { ["true", "on", "yes"].contains($0.lowercased()) } ?? true) }
        switch action {
        case "open_business": BusinessDashboard.shared.show(); return "Opening your business page."
        case "open_whatsapp":
            if ZuffiPlan.shared.isBusiness, WhatsAppLink.shared.enabled { WhatsAppLink.shared.showWindow(); return "Here's WhatsApp." }
            if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "desktop.WhatsApp") {
                NSWorkspace.shared.openApplication(at: u, configuration: .init()); return "Opening WhatsApp."
            }
            NSWorkspace.shared.open(URL(string: "https://web.whatsapp.com")!); return "Opening WhatsApp Web."
        case "open":
            let what = (args["what"] as? String ?? "").lowercased()
            switch what {
            case "business": return perform("open_business", [:])
            case "whatsapp": return perform("open_whatsapp", [:])
            case "features": ZuffiNav.go(.features)
            case "settings": ZuffiNav.go(.settings)
            case "chat": ZuffiChat.shared.open()
            case "profile": ZuffiNav.go(.profile)
            case "history": ZuffiNav.go(.history)
            case "data": ZuffiNav.go(.data)
            case "agents": ZuffiNav.go(.agents)
            case "today": TodayWindow.shared.show()
            case "room": RoomListener.shared.start()
            default: return nil
            }
            return "Opened \(what)."
        case "set_colour":
            let name = (args["colour"] as? String ?? "").lowercased()
            guard let hex = colours[name] else { return "I have blue, indigo, purple, teal, green, orange, rose, red, yellow, gold, mint and slate — which one?" }
            UserDefaults.standard.set(hex, forKey: "zuffiAccentHex")
            BizLook.shared.set(accent: hex)
            WebHub.shared.run("window.Sparrow && window.Sparrow.setAccent && window.Sparrow.setAccent('\(name)')")
            if let fur = furWords[name] { ZuffiLook.shared.kind = .bunny; ZuffiLook.shared.fur = fur }
            NotificationCenter.default.post(name: .zuffiSwitch, object: IslandView.overview)
            return "Done — I'm \(name) now 🎨"
        case "set_fur":
            let name = (args["colour"] as? String ?? "").lowercased()
            guard let fur = furWords[name] else { return "My fur comes in white, pink, peach, honey, mint, sky, lilac, cocoa and grey." }
            ZuffiLook.shared.kind = .bunny; ZuffiLook.shared.fur = fur
            return "New fur! 🐰"
        case "voice":
            let k = (args["kind"] as? String ?? "").lowercased()
            let d = UserDefaults.standard
            d.removeObject(forKey: "voiceName")
            if ["male", "man", "boy", "men's", "mens"].contains(k) {
                d.set("male", forKey: AssistantPrefs.voiceGender); d.set(false, forKey: "bunnyVoice"); d.set("Charon", forKey: "liveVoice")
                WebHub.shared.run("window.Sparrow && window.Sparrow.setVoice && window.Sparrow.setVoice('male')")
                VoiceEngine.shared.speak("Okay, this is my male voice.")
                return "Switched to a male voice."
            }
            if ["bunny", "cute"].contains(k) {
                d.set("female", forKey: AssistantPrefs.voiceGender); d.set(true, forKey: "bunnyVoice"); d.removeObject(forKey: "liveVoice")
                WebHub.shared.run("window.Sparrow && window.Sparrow.setVoice && window.Sparrow.setVoice('female')")
                VoiceEngine.shared.speak("Yay, my bunny voice is back!")
                return "Bunny voice is back."
            }
            d.set("female", forKey: AssistantPrefs.voiceGender); d.set(false, forKey: "bunnyVoice"); d.set("Kore", forKey: "liveVoice")
            WebHub.shared.run("window.Sparrow && window.Sparrow.setVoice && window.Sparrow.setVoice('female')")
            VoiceEngine.shared.speak("Okay, this is my normal voice.")
            return "Switched to a female voice."
        case "mic": VoiceEngine.shared.setMic(bool("on")); return bool("on") ? "Mic is on." : "Mic is off."
        case "pet": if bool("on") { UserDefaults.standard.set(false, forKey: "petNever"); PetController.shared.show() } else { PetController.shared.hide() }; return bool("on") ? "Here I am on your screen!" : "Okay, I'm hiding."
        case "sound": AppState.shared.soundEnabled = bool("on"); return bool("on") ? "Sounds on." : "Sounds off."
        case "record_screen":
            Task { await Assistant.run(bool("on") ? "record my screen" : "stop recording", spoken: false) }
            return bool("on") ? "Starting the screen recording." : "Stopping the recording."
        case "music":
            let c = args["cmd"] as? String ?? "playpause"
            NowPlaying.shared.send(["playpause", "next track", "previous track"].contains(c) ? c : "playpause"); return "Done."
        case "business_look": BizLook.shared.set(dark: bool("dark")); return "Done."
        case "search_web":
            let q = (args["query"] as? String ?? "")
            guard !q.isEmpty, let u = URL(string: "https://www.google.com/search?q=\(q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q)") else { return nil }
            NSWorkspace.shared.open(u); return "Searching for “\(q)”."
        case "open_whatsapp_link": WhatsAppLink.shared.showWindow(); return "Opening WhatsApp."
        default: return nil
        }
    }

    static func health(kind raw: String, on: Bool, every: Int) async -> String {
        let kind = raw.hasPrefix("med") || raw.hasPrefix("pill") ? "meds" : (raw == "tea" ? "coffee" : raw)
        var h: [String: Any] = ["on": on]
        if every > 0 { h["mode"] = "every"; h["every"] = every }
        _ = await WebHub.shared.callJS("return window.Sparrow.setHealth(h)", ["h": [kind: h]])
        let label = kind == "meds" ? "medicine" : kind
        return on ? "\(label.capitalized) reminders are on\(every > 0 ? " — every \(every >= 60 && every % 60 == 0 ? "\(every / 60) hour\(every == 60 ? "" : "s")" : "\(every) minutes")" : "")." : "\(label.capitalized) reminders are off."
    }

    static func makeFolder(_ rawName: String, place: String) -> String {
        let fm = FileManager.default
        let dirKind: FileManager.SearchPathDirectory = place == "documents" ? .documentDirectory : place == "downloads" ? .downloadsDirectory : .desktopDirectory
        guard let base = fm.urls(for: dirKind, in: .userDomainMask).first else { return "I couldn't find your \(place) folder." }
        var name = rawName.replacingOccurrences(of: #"[/:]"#, with: "-", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { name = "New Folder" }
        name = name.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        var url = base.appendingPathComponent(name), n = 2
        while fm.fileExists(atPath: url.path) { url = base.appendingPathComponent("\(name) \(n)"); n += 1 }
        do {
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return "Made the folder “\(url.lastPathComponent)” on your \(place.capitalized) 📁"
        } catch {
            return "I couldn't make the folder: \(error.localizedDescription). If macOS asks, allow Zuffi to use your \(place.capitalized) folder."
        }
    }
}
