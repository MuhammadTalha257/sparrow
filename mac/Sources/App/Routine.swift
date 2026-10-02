import Foundation
import AppKit
import SwiftUI
import EventKit

// =====================================================================
// MARK: - Daily routine: spoken alerts, morning briefing, night check-in
// Everything here runs on the Mac itself: no internet, no AI, no API key.
// =====================================================================

enum RoutinePrefs {
    static let alertsOn    = "routine.alertsOn"      // speak reminders & meetings
    static let alertLead   = "routine.alertLead"     // minutes before (0 = only on time)
    static let morningOn   = "routine.morningOn"
    static let morningTime = "routine.morningTime"   // minutes after midnight
    static let nightOn     = "routine.nightOn"
    static let nightTime   = "routine.nightTime"
    static let lastMorning = "routine.lastMorning"   // "yyyy-MM-dd"
    static let lastNight   = "routine.lastNight"
    static let fired       = "routine.fired"         // [key: timestamp]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            alertsOn: true, alertLead: 5,
            morningOn: true, morningTime: 8 * 60 + 30,
            nightOn: true, nightTime: 21 * 60 + 30,
        ])
    }

    static func dayKey(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }

    /// Minutes after midnight ⇄ Date (today) for the time pickers.
    static func date(fromMinutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    static func minutes(from d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

// MARK: - Task model used by the routine

extension Planner {
    struct TaskItem: Identifiable, Sendable {
        let id: String
        let title: String
        let due: Date?
        let hasTime: Bool
        let created: Date?
    }

    nonisolated static func openTasks() async -> [TaskItem] {
        await withCheckedContinuation { cont in
            let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            store.fetchReminders(matching: pred) { list in
                let items = (list ?? []).map { r -> TaskItem in
                    let comps = r.dueDateComponents
                    return TaskItem(id: r.calendarItemIdentifier, title: r.title ?? "Task",
                                    due: comps.flatMap { Calendar.current.date(from: $0) },
                                    hasTime: comps?.hour != nil, created: r.creationDate)
                }
                cont.resume(returning: items.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) })
            }
        }
    }

    nonisolated static func completedToday() async -> Int {
        await withCheckedContinuation { cont in
            let start = Calendar.current.startOfDay(for: Date())
            let pred = store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: Date(), calendars: nil)
            store.fetchReminders(matching: pred) { list in cont.resume(returning: list?.count ?? 0) }
        }
    }

    /// Today's list: due today, overdue, or added today without a date.
    static func todaysTasks(_ all: [TaskItem]) -> [TaskItem] {
        let cal = Calendar.current
        let endOfToday = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        return all.filter { t in
            if let d = t.due { return d < endOfToday }
            return t.created.map { cal.isDateInToday($0) } ?? false
        }
    }

    /// Moves a task to tomorrow (same time if it had one).
    func moveToTomorrow(_ id: String) -> Bool {
        guard let r = Planner.store.calendarItem(withIdentifier: id) as? EKReminder else { return false }
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        if let old = r.dueDateComponents, let h = old.hour {
            comps.hour = h; comps.minute = old.minute ?? 0
        }
        r.dueDateComponents = comps
        r.alarms?.forEach { r.removeAlarm($0) }
        if comps.hour != nil, let d = cal.date(from: comps) { r.addAlarm(EKAlarm(absoluteDate: d)) }
        do { try Planner.store.save(r, commit: true); return true } catch { return false }
    }

    func moveAllToTomorrow() async -> Int {
        let list = Self.todaysTasks(await Self.openTasks())
        return list.filter { moveToTomorrow($0.id) }.count
    }

    /// Spoken list: "Buy milk, Call mum and Send invoice"
    static func spokenList(_ titles: [String], max: Int = 5) -> String {
        var t = Array(titles.prefix(max))
        if titles.count > max { t.append("\(titles.count - max) more") }
        if t.count <= 1 { return t.first ?? "" }
        return t.dropLast().joined(separator: ", ") + " and " + t.last!
    }

    /// The day's plan, written for speaking.
    func spokenPlan() async -> String {
        let access = await ensureAccess()
        let tf = DateFormatter(); tf.timeStyle = .short
        var parts: [String] = []
        if access.calendar {
            let evs = eventItems(from: Date(), days: 1).filter { !$0.allDay && $0.end > Date() }
            if !evs.isEmpty {
                let list = evs.prefix(4).map { "\($0.title) at \(tf.string(from: $0.start))" }
                parts.append("You have \(evs.count) meeting\(evs.count == 1 ? "" : "s"): " + Self.spokenList(Array(list), max: 4) + ".")
            }
        }
        if access.reminders {
            let today = Self.todaysTasks(await Self.openTasks())
            let cal = Calendar.current
            let overdue = today.filter { ($0.due ?? .distantFuture) < cal.startOfDay(for: Date()) }
            let now = today.filter { t in !overdue.contains { $0.id == t.id } }
            if !now.isEmpty {
                parts.append("Your task\(now.count == 1 ? " for today is" : "s for today are"): " + Self.spokenList(now.map(\.title)) + ".")
            }
            if !overdue.isEmpty {
                parts.append("And \(overdue.count == 1 ? "one task" : "\(overdue.count) tasks") from before: " + Self.spokenList(overdue.map(\.title), max: 3) + ".")
            }
        }
        if parts.isEmpty { return "Your day is clear. No meetings or tasks yet." }
        return parts.joined(separator: " ")
    }
}

// MARK: - The routine engine

@MainActor
final class Routine {
    static let shared = Routine()

    private var timer: Timer?
    private var events: [Planner.EItem] = []
    private var tasks: [Planner.TaskItem] = []
    private var lastRefresh = Date.distantPast
    private let ud = UserDefaults.standard

    func start() {
        RoutinePrefs.registerDefaults()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { _ in
            MainActor.assumeIsolated { Task { await Routine.shared.tick() } }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Routine.shared.lastRefresh = .distantPast }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                Routine.shared.lastRefresh = .distantPast
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { Task { await Routine.shared.tick() } }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { Task { await Routine.shared.tick() } }
    }

    private func tick() async {
        if Date().timeIntervalSince(lastRefresh) > 60 { await refresh() }
        if ud.bool(forKey: RoutinePrefs.alertsOn) { checkAlerts() }
        await checkDaily()
    }

    private func refresh() async {
        lastRefresh = Date()
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            events = Planner.shared.eventItems(from: Date(), days: 2).filter { !$0.allDay }
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            tasks = await Planner.openTasks().filter { $0.hasTime && $0.due != nil }
        }
    }

    // MARK: Spoken alerts

    private var firedMap: [String: Double] {
        get { ud.dictionary(forKey: RoutinePrefs.fired) as? [String: Double] ?? [:] }
        set { ud.set(newValue, forKey: RoutinePrefs.fired) }
    }

    private func checkAlerts() {
        let now = Date()
        let lead = TimeInterval(ud.integer(forKey: RoutinePrefs.alertLead) * 60)
        var fired = firedMap
        // forget alerts older than 2 days
        fired = fired.filter { now.timeIntervalSince1970 - $0.value < 2 * 86400 }
        var toSay: [(String, String)] = []   // (spoken, short)

        func consider(id: String, title: String, at: Date, meeting: Bool) {
            let stamp = Int(at.timeIntervalSince1970)
            let keyNow = "now|\(id)|\(stamp)", keySoon = "soon|\(id)|\(stamp)"
            let name = AssistantPrefs.displayName
            let who = name.isEmpty ? "" : "\(name), "
            if now >= at && now.timeIntervalSince(at) < 10 * 60 {
                if fired[keyNow] == nil {
                    fired[keyNow] = now.timeIntervalSince1970
                    fired[keySoon] = fired[keySoon] ?? now.timeIntervalSince1970
                    let late = now.timeIntervalSince(at) > 120
                    let tf = DateFormatter(); tf.timeStyle = .short
                    if meeting {
                        toSay.append((late ? "\(who)your meeting \(title) started at \(tf.string(from: at))."
                                           : "\(who)you have a meeting now: \(title).", "🗓️ Now: \(title)"))
                    } else {
                        toSay.append((late ? "\(who)you had a reminder at \(tf.string(from: at)): \(title)."
                                           : "\(who)it's time: \(title).", "⏰ \(title)"))
                    }
                }
            } else if lead > 0, now < at, at.timeIntervalSince(now) <= lead, fired[keySoon] == nil {
                fired[keySoon] = now.timeIntervalSince1970
                let mins = max(1, Int((at.timeIntervalSince(now) / 60).rounded()))
                let inMins = "in \(mins) minute\(mins == 1 ? "" : "s")"
                toSay.append((meeting ? "\(who)you have a meeting \(inMins): \(title)."
                                      : "\(who)reminder \(inMins): \(title).", "⏳ \(inMins.capitalized): \(title)"))
            }
        }

        let meetingWords = #"\b(meeting|meet|call|interview|appointment|zoom|teams|standup|stand-up|lunch with|dinner with)\b"#
        for e in events { consider(id: e.id, title: e.title, at: e.start, meeting: true) }
        for t in tasks {
            guard let due = t.due else { continue }
            let isMeeting = t.title.lowercased().range(of: meetingWords, options: .regularExpression) != nil
            consider(id: t.id, title: t.title, at: due, meeting: isMeeting)
        }
        firedMap = fired
        guard !toSay.isEmpty else { return }
        alert(spoken: toSay.map(\.0).joined(separator: " "), shown: toSay.map(\.1).joined(separator: "\n"))
    }

    func alert(spoken: String, shown: String) {
        SoundEngine.shared.play("chime")
        let state = AppState.shared
        state.noteMessage = shown
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        NotificationCenter.default.post(name: .petSay, object: shown)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { VoiceEngine.shared.speak(spoken) }
    }

    // MARK: Morning briefing + night check-in

    private func checkDaily() async {
        let now = Date()
        let mins = RoutinePrefs.minutes(from: now)
        let today = RoutinePrefs.dayKey(now)

        if ud.bool(forKey: RoutinePrefs.morningOn), ud.string(forKey: RoutinePrefs.lastMorning) != today {
            let m = ud.integer(forKey: RoutinePrefs.morningTime)
            // At the chosen time — or later in the morning if the Mac was asleep then.
            if mins >= m && mins < max(m + 4 * 60, 12 * 60) {
                ud.set(today, forKey: RoutinePrefs.lastMorning)
                // Just said hello with the plan (Mac opened)? Don't repeat it.
                if Briefing.shared.greetedRecently { return }
                await morningBriefing()
                return
            }
        }
        if ud.bool(forKey: RoutinePrefs.nightOn), ud.string(forKey: RoutinePrefs.lastNight) != today {
            let n = ud.integer(forKey: RoutinePrefs.nightTime)
            if mins >= n && mins < n + 3 * 60 {
                ud.set(today, forKey: RoutinePrefs.lastNight)
                await nightCheckIn()
            }
        }
    }

    func morningBriefing() async {
        ud.set(RoutinePrefs.dayKey(), forKey: RoutinePrefs.lastMorning)
        let name = AssistantPrefs.displayName
        let tf = DateFormatter(); tf.timeStyle = .short
        var text = "Good \(Briefing.period() == "night" ? "morning" : Briefing.period())\(name.isEmpty ? "" : ", \(name)")! It's \(tf.string(from: Date()))."
        if UserDefaults.standard.bool(forKey: AssistantPrefs.greetWeather), let w = await Weather.now() { text += " " + w }
        text += " " + (await Planner.shared.spokenPlan())
        text += " Have a lovely day!"
        Briefing.shared.markGreeted()
        let state = AppState.shared
        state.noteMessage = text
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        SoundEngine.shared.play("greet")
        VoiceEngine.shared.speak(text)
    }

    func nightCheckIn() async {
        ud.set(RoutinePrefs.dayKey(), forKey: RoutinePrefs.lastNight)
        let access = await Planner.shared.ensureAccess()
        guard access.reminders else { return }
        let open = Planner.todaysTasks(await Planner.openTasks())
        let done = await Planner.completedToday()
        let name = AssistantPrefs.displayName
        let who = name.isEmpty ? "" : ", \(name)"
        var text = "Hi\(who), it's check-in time."
        if done > 0 { text += " You finished \(done) task\(done == 1 ? "" : "s") today. Nice work!" }
        if open.isEmpty {
            text += done > 0 ? " Everything for today is done. Well done!" : " You have no tasks left for today."
            text += " Want to add anything for tomorrow? Just tell me."
        } else {
            text += " \(open.count == 1 ? "One task is" : "\(open.count) tasks are") still open: "
                + Planner.spokenList(open.map(\.title)) + "."
            text += " Tick the ones you finished, and I'll move the rest to tomorrow."
        }
        SoundEngine.shared.play("chime")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        if open.isEmpty {
            AppState.shared.noteMessage = text
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        } else {
            CheckInWindow.shared.show()
        }
        VoiceEngine.shared.speak(text)
    }
}

// MARK: - Night check-in window

@MainActor
final class CheckInModel: ObservableObject {
    @Published var tasks: [Planner.TaskItem] = []
    @Published var done: Set<String> = []
    @Published var moved: Set<String> = []
    @Published var finishedCount = 0
    @Published var loaded = false

    func load() async {
        tasks = Planner.todaysTasks(await Planner.openTasks())
        finishedCount = await Planner.completedToday()
        loaded = true
    }
}

@MainActor
final class CheckInWindow {
    static let shared = CheckInWindow()
    private var window: NSWindow?

    func show() {
        window?.close()
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                        styleMask: [.titled, .closable, .fullSizeContentView],
                        backing: .buffered, defer: false)
        w.title = "Evening check-in"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.level = .floating
        w.contentView = NSHostingView(rootView: CheckInView(close: { CheckInWindow.shared.close() }))
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close(); window = nil }
}

struct CheckInView: View {
    let close: () -> Void
    @StateObject private var model = CheckInModel()
    private let amber = Color(hex: "#F9A830")
    private let sunset = Color(hex: "#F28A3C")

    var body: some View {
        ZStack {
            VisualEffectBlur()
            LinearGradient(colors: [sunset.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("🌙").font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Evening check-in").font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(subtitle).font(.system(size: 12.5)).foregroundColor(.secondary)
                    }
                }
                .padding(.top, 18)

                Text("Tick what you finished. The rest moves to tomorrow.")
                    .font(.system(size: 12.5)).foregroundColor(.secondary)

                ScrollView {
                    VStack(spacing: 8) {
                        if model.loaded && model.tasks.isEmpty {
                            Text("Nothing left for today 🎉").font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(model.tasks) { t in row(t) }
                    }
                }

                HStack {
                    Button("Later") { close() }
                        .buttonStyle(.plain).foregroundColor(.secondary)
                    Spacer()
                    Button { finish() } label: {
                        Text(leftCount == 0 ? "All done" : "Move \(leftCount) to tomorrow")
                            .font(.system(size: 13.5, weight: .bold))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), sunset],
                                                                      startPoint: .top, endPoint: .bottom)))
                            .foregroundColor(Color(hex: "#1A1008"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 22)
        }
        .frame(width: 420, height: 520)
        .task { await model.load() }
    }

    private var leftCount: Int { model.tasks.filter { !model.done.contains($0.id) && !model.moved.contains($0.id) }.count }

    private var subtitle: String {
        let n = model.finishedCount + model.done.count
        return n == 0 ? "How did today go?" : "You finished \(n) task\(n == 1 ? "" : "s") today ✨"
    }

    private func row(_ t: Planner.TaskItem) -> some View {
        let isDone = model.done.contains(t.id)
        let isMoved = model.moved.contains(t.id)
        return HStack(spacing: 12) {
            Button {
                if isDone { if Planner.shared.setDone(t.id, false) { model.done.remove(t.id) } }
                else if Planner.shared.setDone(t.id, true) { model.done.insert(t.id); SoundEngine.shared.play("finish") }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundColor(isDone ? .green : sunset)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).font(.system(size: 13.5, weight: .medium)).strikethrough(isDone)
                    .foregroundColor(isDone ? .secondary : .primary)
                Text(isMoved ? "Moved to tomorrow" : dueText(t)).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            if !isDone && !isMoved {
                Button { if Planner.shared.moveToTomorrow(t.id) { model.moved.insert(t.id) } } label: {
                    Label("Tomorrow", systemImage: "arrow.turn.down.right").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Capsule().fill(amber.opacity(0.16)))
                }
                .buttonStyle(.plain).foregroundColor(.primary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(isDone ? 0.03 : 0.06)))
        .animation(.easeOut(duration: 0.2), value: isDone)
    }

    private func dueText(_ t: Planner.TaskItem) -> String {
        guard let d = t.due else { return "Added today" }
        if d < Calendar.current.startOfDay(for: Date()) { return "Overdue" }
        return t.hasTime ? "Today, " + d.formatted(date: .omitted, time: .shortened) : "Today"
    }

    private func finish() {
        var moved = 0
        for t in model.tasks where !model.done.contains(t.id) && !model.moved.contains(t.id) {
            if Planner.shared.moveToTomorrow(t.id) { moved += 1 }
        }
        let total = model.moved.count + moved
        let name = AssistantPrefs.displayName
        let msg = total == 0
            ? "Great job today\(name.isEmpty ? "" : ", \(name)")! Sleep well."
            : "Done. I moved \(total) task\(total == 1 ? "" : "s") to tomorrow. Sleep well\(name.isEmpty ? "" : ", \(name)")!"
        VoiceEngine.shared.speak(msg)
        NotificationCenter.default.post(name: .todayRefresh, object: nil)
        close()
    }
}

// MARK: - Settings: Daily routine

struct RoutineSettings: View {
    @AppStorage(RoutinePrefs.alertsOn) private var alertsOn = true
    @AppStorage(RoutinePrefs.alertLead) private var lead = 5
    @AppStorage(RoutinePrefs.morningOn) private var morningOn = true
    @AppStorage(RoutinePrefs.morningTime) private var morningTime = 8 * 60 + 30
    @AppStorage(RoutinePrefs.nightOn) private var nightOn = true
    @AppStorage(RoutinePrefs.nightTime) private var nightTime = 21 * 60 + 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("Reminders & meetings", "bell.badge.fill") {
                Toggle("Say my reminders and meetings out loud", isOn: $alertsOn)
                if alertsOn {
                    Picker("Also warn me", selection: $lead) {
                        Text("Only on time").tag(0)
                        Text("1 minute before").tag(1)
                        Text("5 minutes before").tag(5)
                        Text("10 minutes before").tag(10)
                        Text("15 minutes before").tag(15)
                    }
                    Text("e.g. “Talha, you have a meeting in 5 minutes: Standup.”")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            group("Morning briefing", "sun.max.fill") {
                Toggle("Tell me my day every morning", isOn: $morningOn)
                if morningOn {
                    DatePicker("At", selection: binding($morningTime), displayedComponents: .hourAndMinute)
                    Text("Time, weather, meetings and today's tasks. If your Mac is asleep, Sparrow tells you when you open it.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Button("Play it now") { Task { await Routine.shared.morningBriefing() } }
            }
            group("Evening check-in", "moon.stars.fill") {
                Toggle("Ask me what I finished every evening", isOn: $nightOn)
                if nightOn {
                    DatePicker("At", selection: binding($nightTime), displayedComponents: .hourAndMinute)
                    Text("Tick what's done; the rest moves to tomorrow.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Button("Open it now") { Task { await Routine.shared.nightCheckIn() } }
            }
            Text("All of this works offline — no internet, AI or key needed. Reminders and meetings come from your Mac's Reminders and Calendar apps.")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func binding(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(get: { RoutinePrefs.date(fromMinutes: minutes.wrappedValue) },
                set: { minutes.wrappedValue = RoutinePrefs.minutes(from: $0) })
    }

    private func group<C: View>(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(hex: "#F28A3C"))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.primary.opacity(0.04)))
    }
}
