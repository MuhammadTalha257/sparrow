import AppKit
import Foundation

/// Typed or spoken commands that work on the notch's own pages and your data:
/// "open tasks", "show my reminders", "open the lawyer agent", "delete the task call Ali",
/// "mark buy milk done", "rename note shopping to groceries", "move the dentist reminder to 5pm tomorrow".
@MainActor
enum ZuffiCommand {
    /// Page names people say → the notch page id.
    static let pages: [(String, String)] = [
        ("chat history", "chat"), ("history", "chat"), ("chats?", "chat"),
        ("tasks?|to ?dos?|to-do list", "tasks"), ("notes?", "notes"), ("reminders?", "reminders"), ("habits?", "habits"),
        ("today|my day plan|agenda", "today"), ("(this )?week|weekly plan", "week"), ("focus( timer| mode)?|pomodoro", "focus"),
        ("home", "home"), ("whats ?app( messages)?|messages", "whatsapp"), ("settings|preferences", "settings"),
        ("tools?|converter|file tools", "tools"), ("my screen|screen help", "screen"), ("meeting helper", "meeting"),
        ("your day|my day|day stats|screen time", "day"), ("menu|all options|everything", "grid"),
    ]

    static func handle(_ raw: String) async -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^(hey |ok |okay )?zuffi[,!.]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"[.!?]+$"#, with: "", options: .regularExpression)
        let low = text.lowercased()
        guard !low.isEmpty else { return nil }
        if let r = openPage(low) { return r }
        if let r = openAgent(low, original: text) { return r }
        if let r = focus(low) { return r }
        return await editData(low, original: text)
    }

    // MARK: open a page

    private static func openPage(_ low: String) -> String? {
        let verbs = #"^(please )?(open|show( me)?|go to|take me to|see|view)( my| the)? "#
        guard let v = low.range(of: verbs, options: .regularExpression) else { return nil }
        let rest = String(low[v.upperBound...]).replacingOccurrences(of: #"\s+(page|screen|section|list)$"#, with: "", options: .regularExpression)
        if rest.hasSuffix(" app") { return nil }                          // "open notes app" → the Mac app
        for (pat, id) in pages where rest.range(of: "^(\(pat))$", options: .regularExpression) != nil {
            let chatHistory = rest.contains("history")
            NotchNav.shared.open(id)
            if chatHistory { NotchNav.shared.wantsHistory = true }
            let name = NotchScreen.menu.first { $0.id == id }?.name ?? "the menu"
            return id == "grid" ? "Here's everything I can do." : chatHistory ? "Here are your past chats." : "Opening \(name)."
        }
        return nil
    }

    // MARK: agents

    private static var allAgents: [TeamAgent] { ZuffiTeam.shared.agentGroups.flatMap(\.1) }

    private static func openAgent(_ low: String, original: String) -> String? {
        // "open the lawyer agent", "talk to the accountant", "ask the marketing agent how to …", "switch back to zuffi"
        if low.range(of: #"^(go |switch )?back to zuffi$|^(talk to|open) zuffi$|^close (the )?agent$"#, options: .regularExpression) != nil {
            ZuffiChat.shared.who = .zuffi; NotchNav.shared.open("chat")
            return "Okay, it's just me again!"
        }
        let pat = #"^(please )?(open|talk to|ask|chat with|switch to|use|connect me (to|with))( the| my| an?)? (.+?)( agent| expert| bot)?(( and)? (ask|tell)( (him|her|them|it))?:? (.+)| (about|how|what|why|to|if) (.+))?$"#
        guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]),
              let m = re.firstMatch(in: original.lowercased(), range: NSRange(original.lowercased().startIndex..., in: original.lowercased())),
              let nr = Range(m.range(at: 5), in: original.lowercased()) else { return nil }
        let said = original.lowercased()
        let name = String(said[nr]).trimmingCharacters(in: .whitespaces)
        let saidAgentWord = Range(m.range(at: 6), in: said) != nil
        guard let a = bestAgent(name, strict: !saidAgentWord) else { return nil }
        var question = ""
        if let qr = Range(m.range(at: 12), in: said) { question = String(original[qr]) }
        else if let qr = Range(m.range(at: 14), in: said), let wr = Range(m.range(at: 13), in: said) { question = String(original[wr]) + " " + String(original[qr]) }
        ZuffiChat.shared.who = .agent(a.id)
        NotchNav.shared.open("chat")
        if !question.trimmingCharacters(in: .whitespaces).isEmpty {
            NotchNav.shared.pendingChat = question.trimmingCharacters(in: .whitespaces)
            return "Okay, asking \(a.name) now."
        }
        return "Here's \(a.name). Ask away!"
    }

    /// Finds the agent you meant: by name, role words or division. `strict` = they didn't say "agent", so the match must be clear.
    static func bestAgent(_ q: String, strict: Bool) -> TeamAgent? {
        let q = q.lowercased().replacingOccurrences(of: #"^(a|an|the|my) "#, with: "", options: .regularExpression)
        guard q.count >= 3 else { return nil }
        var best: (TeamAgent, Int)?
        for a in allAgents {
            let n = a.name.lowercased()
            var score = 0
            if n == q { score = 100 }
            else if n.contains(q) { score = 70 }
            else if q.contains(n) { score = 60 }
            else {
                let words = q.split(separator: " ").map(String.init).filter { $0.count > 2 }
                let hay = (n + " " + a.description.lowercased() + " " + a.division.lowercased())
                let hits = words.filter { w in hay.contains(String(w.prefix(max(4, w.count - 2)))) }.count
                if hits > 0 { score = 20 + hits * 12 }
            }
            if score > (best?.1 ?? 0) { best = (a, score) }
        }
        guard let b = best else { return nil }
        return b.1 >= (strict ? 60 : 30) ? b.0 : nil
    }

    // MARK: focus

    private static func focus(_ low: String) -> String? {
        if low.range(of: #"^(stop|end|cancel) (the )?focus"#, options: .regularExpression) != nil {
            FocusTimer.shared.stop(); return "Focus stopped."
        }
        guard low.range(of: #"^(start )?(a )?focus( mode| timer| session)?( for)?( (\d+) ?(min|minutes?))?$|^(let'?s )?focus( for (\d+) ?(min|minutes?))?$"#, options: .regularExpression) != nil else { return nil }
        let n = Int(low.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "") ?? 25
        FocusTimer.shared.start(min(180, max(5, n)))
        NotchNav.shared.open("focus")
        return ""                                     // FocusTimer already said it
    }

    // MARK: change or delete your things

    private static let kinds = #"(task|to ?do|note|reminder|habit|meeting)s?"#

    private static func typeSet(_ word: String?) -> Set<String> {
        switch word?.lowercased().prefix(3) {
        case "tas", "to ", "tod": return ["task"]
        case "not": return ["note"]
        case "rem": return ["reminder", "meeting"]
        case "mee": return ["meeting", "reminder"]
        case "hab": return ["habit"]
        default: return ["task", "note", "reminder", "meeting", "habit"]
        }
    }

    private static func find(_ title: String, in types: Set<String>, strict: Bool = false) async -> ZuffiData.Item? {
        let data = ZuffiData.shared
        await data.refresh()
        let q = title.lowercased().trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #"^(the|my|a) "#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^(called|named|about|to) "#, with: "", options: .regularExpression)
        guard !q.isEmpty else { return nil }
        let pool = data.items.filter { types.contains($0.type) }
        if let exact = pool.first(where: { $0.title.lowercased() == q }) { return exact }
        if let part = pool.first(where: { $0.title.lowercased().contains(q) }) { return part }
        if strict { return nil }
        let words = Set(q.split(separator: " ").map(String.init).filter { $0.count > 2 })
        return pool.max { a, b in
            words.filter { a.title.lowercased().contains($0) }.count < words.filter { b.title.lowercased().contains($0) }.count
        }.flatMap { best in words.contains { best.title.lowercased().contains($0) } ? best : nil }
    }

    private static func groups(_ pattern: String, _ s: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
    }

    private static func editData(_ low: String, original: String) async -> String? {
        let data = ZuffiData.shared
        // delete / remove
        if let g = groups(#"^(please )?(delete|remove|erase|cancel|get rid of)( the| my)? (\#(kinds) )?(.+?)( \#(kinds))?$"#, low), let title = g[6] {
            if title.range(of: #"^(all|every)\b"#, options: .regularExpression) != nil { return "To keep you safe I delete one at a time. Which one?" }
            let types = typeSet(g[5] ?? g[8])
            // "cancel" alone on normal sentences ("cancel that") is for other features
            let named = g[5] != nil || g[8] != nil
            guard named || g[2] != "cancel", let it = await find(title, in: types, strict: !named) else { return named ? "Hmm, I couldn't find that one. Want me to open the list?" : nil }
            await data.remove(it.id)
            NotchNav.shared.openIfShowing(pageFor(it.type))
            return "Done — I deleted “\(it.title)”."
        }
        // done
        if let g = groups(#"^(please )?(mark|tick( off)?|check( off)?|complete|finish(ed)?)( the| my)? (\#(kinds) )?(.+?)( as)?( done| complete(d)?)?$"#, low), let title = g[9],
           g[2] != "complete" || g[8] != nil || g[11] != nil {
            if let it = await find(title, in: typeSet(g[8]).subtracting(["note"])) {
                if it.type == "habit" { await data.bump(it.id); return "Yay! One more for “\(it.title)”." }
                await data.complete(it.id)
                return "Nice, “\(it.title)” is done!"
            }
            return nil
        }
        if let g = groups(#"^i (did|finished|completed|have done) (my |the )?(.+)$"#, low), let title = g[3], let it = await find(title, in: ["task", "habit"]) {
            if it.type == "habit" { await data.bump(it.id); return "Yay! One more for “\(it.title)”. Keep it up!" }
            await data.complete(it.id); return "Nice, “\(it.title)” is done!"
        }
        // rename / change the text
        if let g = groups(#"^(please )?(rename|change|edit|update)( the| my)? (\#(kinds) )?(.+?) (to|into|as) (.+)$"#, low),
           let oldT = g[6], let newRaw = g[8], g[5] != nil || g[2] == "rename" {
            let types = typeSet(g[5])
            guard let it = await find(oldT, in: types) else { return "Hmm, I couldn't find “\(oldT)”." }
            // "change the dentist reminder to 5pm tomorrow" → it's a new time
            if types.contains("reminder") || it.when != nil, let when = date(in: newRaw) {
                await data.update(it.id, when: .some(when))
                return "Okay, “\(it.title)” is now \(nsWhen(when))."
            }
            let start = original.lowercased().range(of: " " + (g[7] ?? "to") + " ", options: .backwards)
            let newT = start.map { String(original[$0.upperBound...]) } ?? newRaw
            if it.type == "note", g[2] != "rename" { await data.update(it.id, text: newT); return "Updated your note “\(it.title)”." }
            await data.update(it.id, title: newT)
            return "Renamed it to “\(newT)”."
        }
        // move a time
        if let g = groups(#"^(please )?(move|push|reschedule|snooze)( the| my)? (\#(kinds) )?(.+?) (to|till|until|for) (.+)$"#, low),
           let title = g[6], let whenRaw = g[8] {
            guard let it = await find(title, in: typeSet(g[5]).subtracting(["note"])) else { return nil }
            var when = date(in: whenRaw)
            if when == nil, let mins = Int(whenRaw.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? ""), whenRaw.contains("min") {
                when = Date().addingTimeInterval(Double(mins) * 60)
            }
            guard let when else { return "What time should I move it to?" }
            await data.update(it.id, when: .some(when))
            return "Moved “\(it.title)” to \(nsWhen(when))."
        }
        // read things out
        if low.range(of: #"^(what are|read|tell me|list)( me)?( all)? my (tasks|to ?dos)$|^what do i (have to|need to) do$"#, options: .regularExpression) != nil {
            await data.refresh()
            let t = data.of(["task"]).prefix(6).map(\.title)
            NotchNav.shared.open("tasks")
            return t.isEmpty ? "Your task list is empty. Lovely!" : "You have \(t.count == 1 ? "one task" : "\(t.count) tasks"): " + t.joined(separator: ", ") + "."
        }
        if low.range(of: #"^(what are|read|tell me|list)( me)?( all)? my (reminders|habits|notes)$"#, options: .regularExpression) != nil {
            await data.refresh()
            let kind = low.contains("habit") ? "habit" : low.contains("note") ? "note" : "reminder"
            let list = data.of(kind == "reminder" ? ["reminder", "meeting"] : [kind]).prefix(6)
            NotchNav.shared.open(kind + "s")
            if list.isEmpty { return "You don't have any \(kind)s yet." }
            if kind == "reminder" { return list.map { "\($0.title), \(nsWhen($0.when))" }.joined(separator: ". ") + "." }
            if kind == "habit" { return list.map { "\($0.title): \($0.count) of \(max(1, $0.target))" }.joined(separator: ". ") + "." }
            return "Your notes: " + list.map(\.title).joined(separator: ", ") + "."
        }
        return nil
    }

    private static func pageFor(_ type: String) -> String {
        switch type { case "task": return "tasks"; case "note": return "notes"; case "habit": return "habits"; default: return "reminders" }
    }

    static func date(in s: String) -> Date? {
        var t = s.replacingOccurrences(of: #"\b(\d{1,2})\s?(am|pm)\b"#, with: "$1 $2", options: [.regularExpression, .caseInsensitive])
        if t.range(of: #"\b(tonight)\b"#, options: .regularExpression) != nil, t.range(of: #"\d"#, options: .regularExpression) == nil { t = "today 8 pm" }
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let m = det.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), var d = m.date else { return nil }
        if d < Date(), !t.lowercased().contains("today") { d = Calendar.current.date(byAdding: .day, value: 1, to: d) ?? d }
        return d
    }
}
