import Foundation
import AppKit
import EventKit

/// Meetings, tasks, reminders and notes — saved straight into the Mac's own
/// Calendar, Reminders and Notes apps (so they sync to iPhone via iCloud too).
@MainActor
final class Planner {
    static let shared = Planner()

    // EventKit's store isn't Sendable; it's only touched from the main actor or inside
    // the small nonisolated helpers below, so it is shared deliberately.
    nonisolated(unsafe) static let store = EKEventStore()

    // MARK: Permissions

    nonisolated private static func askEvents() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestFullAccessToEvents { ok, _ in cont.resume(returning: ok) }
        }
    }
    nonisolated private static func askReminders() async -> Bool {
        await withCheckedContinuation { cont in
            store.requestFullAccessToReminders { ok, _ in cont.resume(returning: ok) }
        }
    }

    private func calendarAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return await Self.askEvents()
    }
    private func remindersAccess() async -> Bool {
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess { return true }
        return await Self.askReminders()
    }

    private let noCalendar = "I need access to Calendar: System Settings → Privacy & Security → Calendars → Sparrow."
    private let noReminders = "I need access to Reminders: System Settings → Privacy & Security → Reminders → Sparrow."

    // MARK: Date understanding (Apple's built-in detector — offline)

    private struct When { let date: Date; let rest: String }

    private func parseWhen(_ text: String) -> When? {
        guard let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let ns = text as NSString
        guard let m = det.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)), var d = m.date else { return nil }
        let phrase = ns.substring(with: m.range).lowercased()
        // A day without a time ("tomorrow", "Friday") → 9 am
        let hasTime = phrase.range(of: #"\d|noon|midnight|morning|afternoon|evening|tonight"#, options: .regularExpression) != nil
        if !hasTime, let nine = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: d) { d = nine }
        if d < Date(), !hasTime, let next = Calendar.current.date(byAdding: .day, value: 7, to: d) { d = next }
        let rest = ns.replacingCharacters(in: m.range, with: " ")
        return When(date: d, rest: rest)
    }

    private func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?:-"))
        for p in ["to ", "that ", "about ", "for ", "me ", "a ", "an "] where t.lowercased().hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        for s in [" at", " on", " by", " for", " in", " this", " next"] where t.lowercased().hasSuffix(s) { t = String(t.dropLast(s.count)) }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    private func whenText(_ d: Date) -> String {
        let cal = Calendar.current
        let tf = DateFormatter(); tf.timeStyle = .short
        let day: String
        if cal.isDateInToday(d) { day = "today" }
        else if cal.isDateInTomorrow(d) { day = "tomorrow" }
        else { let f = DateFormatter(); f.dateFormat = "EEEE d MMM"; day = f.string(from: d) }
        return "\(day) at \(tf.string(from: d))"
    }

    // MARK: Handle a request (returns nil if it isn't a planner request)

    func handle(_ raw: String) async -> String? {
        let o = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^((hey|hi|ok)\s+)?sparrow[,!\s]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^(please|can you|could you)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        let t = o.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "?!."))

        // What's on…
        if t.range(of: #"what('?s| is) (on|up|planned)|my (day|agenda|schedule|plan)\b|what do i have|anything (on|planned)|^agenda"#,
                   options: .regularExpression) != nil {
            let day = t.contains("tomorrow") ? Calendar.current.date(byAdding: .day, value: 1, to: Date())! : Date()
            return await summary(for: day, detailed: true)
        }
        if t.range(of: #"^(show |list |what are )?(my )?(tasks|to-?dos|todo list|reminders)$"#, options: .regularExpression) != nil {
            guard await remindersAccess() else { return noReminders }
            let items = await Self.openReminders()
            if items.isEmpty { return "No open tasks. 🎉" }
            return "Your tasks:\n" + items.prefix(12).map { "• " + $0.title + ($0.due.map { " (\(whenText($0)))" } ?? "") }.joined(separator: "\n")
        }

        // Reminders
        if let r = o.range(of: #"^(?:remind me|set (?:a )?reminder|reminder|don'?t let me forget)\b[\s,:]*"#,
                           options: [.regularExpression, .caseInsensitive]) {
            let body = String(o[r.upperBound...])
            var date = Date().addingTimeInterval(3600)
            var title = body
            var note = ""
            if let w = parseWhen(body) { date = w.date; title = w.rest } else { note = " (in 1 hour — say a time to change it)" }
            title = tidy(title); if title.isEmpty { title = "Reminder" }
            guard await remindersAccess() else { return noReminders }
            return saveReminder(title: title, due: date)
                ? "⏰ I'll remind you: \(title) — \(whenText(date))\(note). It's in your Reminders app."
                : "Sorry, I couldn't save that reminder."
        }

        // Meetings
        let meetingWords = #"\b(meeting|meet|call with|appointment|interview|lunch with|dinner with|catch ?up|zoom|teams call|doctor|dentist)\b"#
        if t.range(of: meetingWords, options: .regularExpression) != nil || t.range(of: #"^(schedule|book|set up|arrange)\b"#, options: .regularExpression) != nil,
           let w = parseWhen(o) {
            var title = w.rest.replacingOccurrences(of: #"^(add|schedule|book|set up|arrange|create|i have|put)\s+(a |an )?"#,
                                                     with: "", options: [.regularExpression, .caseInsensitive])
            title = tidy(title.replacingOccurrences(of: #"\s+(to|in|on) (my )?(calendar|agenda|schedule)$"#, with: "", options: [.regularExpression, .caseInsensitive]))
            if title.isEmpty { title = "Meeting" }
            guard await calendarAccess() else { return noCalendar }
            return saveEvent(title: title, start: w.date)
                ? "🗓️ Added to your Calendar: \(title) — \(whenText(w.date)). I'll alert you 10 minutes before."
                : "Sorry, I couldn't add that to your Calendar."
        }

        // Notes → Apple Notes
        if let r = o.range(of: #"^(?:take a note|note(?: down)?|write down|remember that|save (?:a )?note|jot down)\b[\s,:]*"#,
                           options: [.regularExpression, .caseInsensitive]) {
            let body = String(o[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { return "What should the note say?" }
            let esc = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            if CommandEngine.shared.runAppleScript("tell application \"Notes\" to make new note with properties {body:\"\(esc)\"}") != nil {
                return "📝 Saved in your Notes app."
            }
            return "I couldn't reach Notes. Allow Sparrow under System Settings → Privacy & Security → Automation."
        }

        // Tasks → Reminders without a time
        var taskBody: String?
        for pattern in [#"^(?:add|new|create)?\s*(?:a\s+)?(?:task|todo|to-do|to do)\b[\s,:]*(.+)$"#,
                        #"^(?:add|put)\s+(.+?)\s+(?:to|on)\s+(?:my\s+)?(?:list|tasks|to-?do(?: list)?|shopping list)$"#,
                        #"^i (?:need|have|must|should) to\s+(.+)$"#] {
            if let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let m = re.firstMatch(in: o, range: NSRange(location: 0, length: (o as NSString).length)), m.numberOfRanges > 1 {
                taskBody = (o as NSString).substring(with: m.range(at: 1)); break
            }
        }
        if let body = taskBody {
            let w = parseWhen(body)
            let title = tidy(w?.rest ?? body)
            guard await remindersAccess() else { return noReminders }
            return saveReminder(title: title, due: w?.date)
                ? "✅ Added to your tasks: \(title)\(w.map { " — " + whenText($0.date) } ?? "")."
                : "Sorry, I couldn't add that task."
        }

        // Done
        if let re = try? NSRegularExpression(pattern: #"^(?:done|completed?|finish(?:ed)?|mark|tick(?: off)?|i (?:did|finished))\s+(.+?)(?:\s+(?:as\s+)?(?:done|complete))?$"#),
           let m = re.firstMatch(in: t, range: NSRange(location: 0, length: (t as NSString).length)) {
            let what = (t as NSString).substring(with: m.range(at: 1))
            guard await remindersAccess() else { return noReminders }
            if let title = await Self.complete(matching: what) { return "Nice! ✔️ \"\(title)\" done." }
            return "I couldn't find \"\(what)\" in your Reminders."
        }
        return nil
    }

    // MARK: Saving

    private func saveReminder(title: String, due: Date?) -> Bool {
        let s = Self.store
        let r = EKReminder(eventStore: s)
        r.title = title
        r.calendar = s.defaultCalendarForNewReminders()
        if let due {
            r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
            r.addAlarm(EKAlarm(absoluteDate: due))
        }
        do { try s.save(r, commit: true); return true } catch { return false }
    }

    private func saveEvent(title: String, start: Date) -> Bool {
        let s = Self.store
        let e = EKEvent(eventStore: s)
        e.title = title
        e.startDate = start
        e.endDate = start.addingTimeInterval(3600)
        e.calendar = s.defaultCalendarForNewEvents
        e.addAlarm(EKAlarm(relativeOffset: -600))
        e.notes = "Added by Sparrow 🐦"
        do { try s.save(e, span: .thisEvent, commit: true); return true } catch { return false }
    }

    // MARK: Reading

    struct Item: Sendable { let title: String; let due: Date? }

    nonisolated static func openReminders() async -> [Item] {
        await withCheckedContinuation { cont in
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: pred) { list in
                let items = (list ?? []).map { r in Item(title: r.title ?? "", due: r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }) }
                cont.resume(returning: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }

    nonisolated static func complete(matching q: String) async -> String? {
        await withCheckedContinuation { cont in
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: pred) { list in
                let s = q.lowercased()
                let hit = (list ?? []).first { ($0.title ?? "").lowercased() == s }
                    ?? (list ?? []).first { ($0.title ?? "").lowercased().contains(s) }
                guard let r = hit else { cont.resume(returning: nil); return }
                r.isCompleted = true
                let title = r.title ?? q
                do { try store.save(r, commit: true); cont.resume(returning: title) } catch { cont.resume(returning: nil) }
            }
        }
    }

    private func events(on day: Date) -> [(title: String, start: Date)] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let pred = Self.store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return Self.store.events(matching: pred).filter { !$0.isAllDay }
            .map { (title: $0.title ?? "Event", start: $0.startDate) }
            .sorted { $0.start < $1.start }
    }

    /// "Today you have 2 meetings and 3 reminders. Next: Standup at 10:00."
    func summary(for day: Date = Date(), detailed: Bool = false) async -> String {
        let cal = Calendar.current
        _ = await calendarAccess()
        let evs = events(on: day)
        var dueToday: [Item] = []
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            dueToday = await Self.openReminders().filter { $0.due.map { cal.isDate($0, inSameDayAs: day) } ?? false }
        }
        let label = cal.isDateInToday(day) ? "Today" : (cal.isDateInTomorrow(day) ? "Tomorrow" : "That day")
        if evs.isEmpty && dueToday.isEmpty { return "\(label) your calendar is clear. 🌤️" }
        var parts: [String] = []
        if !evs.isEmpty { parts.append("\(evs.count) meeting\(evs.count == 1 ? "" : "s")") }
        if !dueToday.isEmpty { parts.append("\(dueToday.count) reminder\(dueToday.count == 1 ? "" : "s")") }
        var s = "\(label) you have \(parts.joined(separator: " and "))."
        let tf = DateFormatter(); tf.timeStyle = .short
        if let next = evs.first(where: { $0.start > Date() }) ?? evs.first { s += " Next: \(next.title) at \(tf.string(from: next.start))." }
        if detailed {
            let lines = evs.map { "• \(tf.string(from: $0.start)) — \($0.title)" } + dueToday.map { "• ⏰ " + $0.title }
            if !lines.isEmpty { s += "\n" + lines.joined(separator: "\n") }
        }
        return s
    }
}
