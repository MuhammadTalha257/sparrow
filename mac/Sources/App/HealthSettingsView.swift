import SwiftUI
import AVFoundation
import Speech

// =====================================================================
// MARK: - Settings → Health: water, coffee and medicine reminders
// Each one: on/off, every N minutes or at set times, only between two times.
// When one is due the pink sparrow flies in carrying a water bottle, a coffee
// cup or pills, and says it. (The reminders live in Zuffi's shared app, so
// they work the same on iPhone and Windows.)
// =====================================================================

struct HealthReminder: Equatable {
    var on = false
    var mode = "every"          // "every" | "times"
    var every = 120             // minutes
    var times = ""
    var start = "09:00"
    var end = "22:00"
    var name = "medicine"

    init() {}
    init(_ d: [String: Any]) {
        on = d["on"] as? Bool ?? false
        mode = d["mode"] as? String ?? "every"
        every = (d["every"] as? NSNumber)?.intValue ?? 120
        times = d["times"] as? String ?? ""
        start = d["start"] as? String ?? "09:00"
        end = d["end"] as? String ?? "22:00"
        name = d["name"] as? String ?? "medicine"
    }
    var dict: [String: Any] { ["on": on, "mode": mode, "every": every, "times": times, "start": start, "end": end, "name": name] }
}

struct HealthSettingsView: View {
    @State private var items: [String: HealthReminder] = [:]
    @State private var loaded = false
    @State private var saved = false

    private let kinds: [(id: String, title: String, icon: String, color: String, hint: String)] = [
        ("water", "Water", "waterbottle.fill", "#4FA7FF", "Stay hydrated through the day"),
        ("coffee", "Coffee", "cup.and.saucer.fill", "#9A6A48", "A little break — coffee or tea"),
        ("meds", "Medicine", "pills.fill", "#F06A8A", "Never miss your medicine"),
    ]
    private let intervals = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LittleSparrow(color: nil, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Little reminders").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("When it's time, Zuffi flies in carrying your water, coffee or pills.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            if !loaded {
                ProgressView().controlSize(.small)
            } else {
                ForEach(kinds, id: \.id) { k in card(k) }
                HStack {
                    Button(saved ? "Saved ✓" : "Save") { save() }.buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A"))
                    Text("You can also say “Zuffi, remind me to drink water every 30 minutes”.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func card(_ k: (id: String, title: String, icon: String, color: String, hint: String)) -> some View {
        let binding = Binding<HealthReminder>(get: { items[k.id] ?? HealthReminder() }, set: { items[k.id] = $0; saved = false })
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: k.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: k.color))
                        .frame(width: 30, height: 30).background(Circle().fill(Color(hex: k.color).opacity(0.15)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.title).font(.system(size: 13, weight: .semibold))
                        Text(k.hint).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: binding.on).toggleStyle(.switch).labelsHidden()
                }
                if binding.wrappedValue.on {
                    if k.id == "meds" {
                        TextField("Medicine name", text: binding.name).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    }
                    Picker("", selection: binding.mode) {
                        Text("Every…").tag("every"); Text("At set times").tag("times")
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                    if binding.wrappedValue.mode == "every" {
                        Picker("Remind me every", selection: binding.every) {
                            ForEach(intervals, id: \.self) { m in Text(label(m)).tag(m) }
                        }.frame(maxWidth: 260)
                    } else {
                        HStack {
                            Text("At")
                            TextField("09:00, 13:00, 18:00", text: binding.times).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Only between")
                        TextField("09:00", text: binding.start).textFieldStyle(.roundedBorder).frame(width: 64)
                        Text("and")
                        TextField("22:00", text: binding.end).textFieldStyle(.roundedBorder).frame(width: 64)
                        Spacer()
                        Button("Show me") {
                            Task { _ = await WebHub.shared.callJS("return window.Sparrow.testHealth(k)", ["k": k.id]) }
                        }.controlSize(.small)
                    }.font(.system(size: 12))
                }
            }
            .padding(6)
        }
    }

    private func label(_ m: Int) -> String {
        m < 60 ? "\(m) minutes" : m % 60 == 0 ? "\(m / 60) hour\(m > 60 ? "s" : "")" : "\(m / 60)½ hours"
    }

    private func load() async {
        let r = await WebHub.shared.callJS("return window.Sparrow.getHealth ? window.Sparrow.getHealth() : {}") as? [String: Any] ?? [:]
        var out: [String: HealthReminder] = [:]
        for k in ["water", "coffee", "meds"] { out[k] = HealthReminder(r[k] as? [String: Any] ?? [:]) }
        if r["coffee"] == nil { out["coffee"]?.mode = "times"; out["coffee"]?.times = "10:00, 15:00"; out["coffee"]?.start = "08:00"; out["coffee"]?.end = "18:00" }
        if r["meds"] == nil { out["meds"]?.mode = "times"; out["meds"]?.times = "09:00, 21:00" }
        items = out
        loaded = true
    }

    private func save() {
        var payload: [String: Any] = [:]
        for (k, v) in items { payload[k] = v.dict }
        Task {
            _ = await WebHub.shared.callJS("return window.Sparrow.setHealth(h)", ["h": payload])
            saved = true
        }
    }
}

// =====================================================================
// MARK: - Language tutor: English · Spanish · French · German · Arabic — a senior teacher who speaks with you
// =====================================================================

struct TutorLanguage: Identifiable, Hashable {
    let id: String; let name: String; let flag: String; let locale: String; let rtl: Bool
    static let all: [TutorLanguage] = [
        TutorLanguage(id: "en", name: "English", flag: "🇬🇧", locale: "en-GB", rtl: false),
        TutorLanguage(id: "es", name: "Spanish", flag: "🇪🇸", locale: "es-ES", rtl: false),
        TutorLanguage(id: "fr", name: "French", flag: "🇫🇷", locale: "fr-FR", rtl: false),
        TutorLanguage(id: "de", name: "German", flag: "🇩🇪", locale: "de-DE", rtl: false),
        TutorLanguage(id: "ar", name: "Arabic", flag: "🇸🇦", locale: "ar-SA", rtl: true),
    ]
    static func of(_ id: String) -> TutorLanguage { all.first { $0.id == id } ?? all[0] }
}

struct TutorWord: Codable, Identifiable, Hashable { var id = UUID().uuidString; var lang: String; var word: String; var meaning: String; var example = ""; var box = 0; var due = Date() }
struct TutorExercise: Codable, Hashable { var q: String; var options: [String]; var answer: Int; var why: String }
struct TutorLesson: Codable, Hashable {
    var title = ""
    var words: [[String: String]] = []      // word, meaning, example, exampleMeaning
    var grammar = ""
    var grammarExamples: [String] = []
    var exercises: [TutorExercise] = []
    var phrases: [String] = []
}
struct TutorMsg: Identifiable, Hashable { let id = UUID(); let mine: Bool; let text: String; var note = "" }

/// Speaks the language you're learning with the right accent.
@MainActor
final class TutorVoice {
    static let shared = TutorVoice()
    private let synth = AVSpeechSynthesizer()
    func say(_ text: String, _ lang: TutorLanguage, slow: Bool = false) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang.locale }.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: lang.locale)
        u.rate = slow ? 0.38 : 0.47
        synth.speak(u)
    }
}

/// Listens to you speak the language (on this Mac).
@MainActor
final class TutorEar: ObservableObject {
    static let shared = TutorEar()
    @Published var heard = ""
    @Published var listening = false
    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func start(_ lang: TutorLanguage) {
        stop()
        heard = ""
        Self.askPermission()
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang.locale)), rec.isAvailable else { heard = "(Speech for \(lang.name) isn't available on this Mac — type instead.)"; return }
        let eng = AVAudioEngine(), req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        Self.tap(eng.inputNode, req)
        do { eng.prepare(); try eng.start() } catch { heard = "(Couldn't use the microphone.)"; return }
        engine = eng; request = req; listening = true
        task = Self.recognize(rec, req)
    }
    nonisolated private static func askPermission() { SFSpeechRecognizer.requestAuthorization { _ in } }
    // These run on the audio / speech threads, so they're kept off the main actor.
    nonisolated private static func tap(_ input: AVAudioInputNode, _ req: SFSpeechAudioBufferRecognitionRequest) {
        nonisolated(unsafe) let r = req
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in r.append(buf) }
    }
    nonisolated private static func recognize(_ rec: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest) -> SFSpeechRecognitionTask {
        rec.recognitionTask(with: req) { r, err in
            let text = r?.bestTranscription.formattedString
            let final = (r?.isFinal ?? false) || err != nil
            Task { @MainActor in
                if let text { TutorEar.shared.heard = text }
                if final { TutorEar.shared.stop() }
            }
        }
    }
    func stop() {
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        listening = false
    }
}

@MainActor
final class LanguageTutor: ObservableObject {
    static let shared = LanguageTutor()
    @Published var langID: String = UserDefaults.standard.string(forKey: "tutorLang") ?? "es" { didSet { UserDefaults.standard.set(langID, forKey: "tutorLang"); chat = []; lesson = nil } }
    @Published var explainIn: String = UserDefaults.standard.string(forKey: "tutorExplain") ?? "English" { didSet { UserDefaults.standard.set(explainIn, forKey: "tutorExplain") } }
    @Published var levels: [String: String] = (UserDefaults.standard.dictionary(forKey: "tutorLevels") as? [String: String]) ?? [:] { didSet { UserDefaults.standard.set(levels, forKey: "tutorLevels") } }
    @Published var words: [TutorWord] = TeamStore.load("tutor-words", [TutorWord]()) { didSet { TeamStore.save("tutor-words", words) } }
    @Published var xp: Int = UserDefaults.standard.integer(forKey: "tutorXP") { didSet { UserDefaults.standard.set(xp, forKey: "tutorXP") } }
    @Published var streak: Int = UserDefaults.standard.integer(forKey: "tutorStreak")
    @Published var lesson: TutorLesson?
    @Published var chat: [TutorMsg] = []
    @Published var busy = ""
    @Published var scenario = "Everyday chat"
    @Published var placement: [TutorExercise] = []

    var lang: TutorLanguage { TutorLanguage.of(langID) }
    var level: String { levels[langID] ?? "A1" }
    static let scenarios = ["Everyday chat", "Ordering at a café", "At the airport", "Shopping", "At the doctor", "Job interview", "Meeting new friends", "Asking for directions", "At university", "Phone call"]

    private var teacher: String {
        """
        \(ZuffiVoice.nik)
        Right now you teach \(lang.name) (you speak it like a native and know CEFR levels well). Your student is level \(level) and their own language is \(explainIn); explain rules in \(explainIn).
        Teach warmly and clearly, matched to level \(level): simple words and short sentences for A1–A2, richer for B1+.
        Be accurate: natural, correct, current language a native speaker really uses; never invent words or rules. Praise what's right, fix one thing at a time.
        \(lang.id == "ar" ? "Write Arabic in Arabic script, with the transliteration in brackets for A1–A2." : "")
        """
    }

    func earned(_ n: Int) {
        xp += n
        let today = ZuffiBusiness.iso(Date()), last = UserDefaults.standard.string(forKey: "tutorDay") ?? ""
        if last != today {
            streak = last == ZuffiBusiness.iso(Date().addingTimeInterval(-86400)) ? streak + 1 : 1
            UserDefaults.standard.set(streak, forKey: "tutorStreak"); UserDefaults.standard.set(today, forKey: "tutorDay")
        }
    }

    // MARK: placement test
    func startPlacement() async {
        busy = "Making your level test…"; defer { busy = "" }
        let r = await AIService.shared.oneShot("""
            \(teacher)
            Make a 10-question placement test for \(lang.name), from A1 (first questions) to C1 (last). Questions about meaning, grammar and usage.
            JSON only: [{"q":"…","options":["…","…","…","…"],"answer":0,"why":"one line in \(explainIn)"}]
            """) ?? ""
        placement = ((AIService.jsonIn(r) as? [[String: Any]]) ?? []).compactMap(Self.exercise)
    }
    func finishPlacement(correct: Int) {
        let lv = correct <= 2 ? "A1" : correct <= 4 ? "A2" : correct <= 6 ? "B1" : correct <= 8 ? "B2" : "C1"
        levels[langID] = lv; placement = []; earned(20)
    }
    static func exercise(_ d: [String: Any]) -> TutorExercise? {
        guard let q = d["q"] as? String, let o = d["options"] as? [String], o.count >= 2 else { return nil }
        let a = (d["answer"] as? Int) ?? Int((d["answer"] as? String) ?? "") ?? 0
        return TutorExercise(q: q, options: o, answer: min(max(0, a), o.count - 1), why: (d["why"] as? String) ?? "")
    }

    // MARK: today's lesson
    func newLesson(topic: String = "") async {
        busy = "Your teacher is preparing today's lesson…"; defer { busy = "" }
        let known = words.filter { $0.lang == langID }.suffix(60).map(\.word).joined(separator: ", ")
        let r = await AIService.shared.oneShot("""
            \(teacher)
            Make today's lesson\(topic.isEmpty ? " (pick a useful everyday topic)" : " about: \(topic)"). Don't repeat these known words: \(known.isEmpty ? "none" : known).
            JSON only:
            {"title":"lesson title in \(explainIn)",
             "words":[{"word":"in \(lang.name)","meaning":"in \(explainIn)","example":"short sentence in \(lang.name)","exampleMeaning":"in \(explainIn)"}],
             "grammar":"one grammar point explained simply in \(explainIn)","grammarExamples":["\(lang.name) example — \(explainIn) meaning"],
             "exercises":[{"q":"…","options":["…","…","…","…"],"answer":0,"why":"in \(explainIn)"}],
             "phrases":["3 useful phrases in \(lang.name) to say out loud"]}
            8 words, 6 exercises.
            """) ?? ""
        guard let j = AIService.jsonIn(r) as? [String: Any] else { lesson = nil; busy = ""; return }
        var l = TutorLesson()
        l.title = (j["title"] as? String) ?? "Today's lesson"
        l.words = ((j["words"] as? [[String: Any]]) ?? []).map { d in d.compactMapValues { $0 as? String } }
        l.grammar = (j["grammar"] as? String) ?? ""
        l.grammarExamples = (j["grammarExamples"] as? [String]) ?? []
        l.exercises = ((j["exercises"] as? [[String: Any]]) ?? []).compactMap(Self.exercise)
        l.phrases = (j["phrases"] as? [String]) ?? []
        lesson = l
        for w in l.words { if let word = w["word"], !words.contains(where: { $0.lang == langID && $0.word == word }) { words.append(TutorWord(lang: langID, word: word, meaning: w["meaning"] ?? "", example: w["example"] ?? "")) } }
        earned(10)
    }

    // MARK: speak with your teacher (a role-play, with corrections)
    func say(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
        chat.append(TutorMsg(mine: true, text: t))
        busy = "…"; defer { busy = "" }
        let history = chat.suffix(12).map { ($0.mine ? "Student: " : "Teacher: ") + $0.text }.joined(separator: "\n")
        let r = await AIService.shared.oneShot("""
            \(teacher)
            Role-play: \(scenario). Keep the conversation going in \(lang.name) at level \(level) (1-3 short sentences, end with a question).
            Then check every word of the student's LAST message (it may come from the microphone, so also judge words that sound wrong). JSON only:
            {"reply":"your reply in \(lang.name)","correction":"the student's whole sentence corrected (empty if it was correct)",
             "mistakes":[{"said":"the exact wrong part","correct":"the right form","why":"why, and when we use it, in 1-2 simple sentences in \(explainIn)"}],
             "tip":"a kind one-line note in \(explainIn): praise one thing they did well, or what to practise next","newWord":"one useful \(lang.name) word from your reply","newWordMeaning":"its meaning in \(explainIn)"}
            At most 3 mistakes, most important first; [] if it was correct.
            CONVERSATION:
            \(history)
            """) ?? ""
        guard let j = AIService.jsonIn(r) as? [String: Any], let reply = j["reply"] as? String else { chat.append(TutorMsg(mine: false, text: "(I couldn't answer — check an AI is set up in Settings.)")); return }
        var note = ""
        for m in (j["mistakes"] as? [[String: Any]] ?? []).prefix(3) {
            let said = m["said"] as? String ?? "", fix = m["correct"] as? String ?? "", why = m["why"] as? String ?? ""
            guard !fix.isEmpty else { continue }
            note += "✗ \(said) → ✓ \(fix)" + (why.isEmpty ? "" : "\n   " + why) + "\n"
        }
        if let c = j["correction"] as? String, !c.isEmpty { note += "✏️ " + c + "\n" }
        if let tip = j["tip"] as? String, !tip.isEmpty { note += "💡 " + tip }
        if let i = chat.indices.last { chat[i].note = note }
        chat.append(TutorMsg(mine: false, text: reply))
        TutorVoice.shared.say(reply, lang)
        if let w = j["newWord"] as? String, !w.isEmpty, !words.contains(where: { $0.lang == langID && $0.word == w }) {
            words.append(TutorWord(lang: langID, word: w, meaning: (j["newWordMeaning"] as? String) ?? ""))
        }
        earned((j["correction"] as? String ?? "").isEmpty ? 3 : 2)
    }

    /// How close what you said is to the phrase (word by word).
    static func match(_ said: String, _ target: String) -> Int {
        func words(_ s: String) -> [String] { s.lowercased().folding(options: .diacriticInsensitive, locale: nil).components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty } }
        let a = words(said), b = words(target)
        guard !b.isEmpty else { return 0 }
        return Int(Double(b.filter { a.contains($0) }.count) / Double(b.count) * 100)
    }
}

struct LanguagePage: View {
    var light: Bool
    @ObservedObject private var t = LanguageTutor.shared
    @ObservedObject private var ear = TutorEar.shared
    @State private var tab = "Lesson"
    @State private var typed = ""
    @State private var topic = ""
    @State private var picks: [Int: Int] = [:]
    @State private var pIndex = 0
    @State private var pScore = 0
    @State private var pPick: Int?
    @State private var reviewIndex = 0
    @State private var reveal = false
    @State private var practice = ""
    private var T: HubTheme { HubTheme(light: light) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // language bar
            HStack(spacing: 10) {
                ForEach(TutorLanguage.all) { l in
                    Button { t.langID = l.id } label: {
                        HStack(spacing: 6) { Text(l.flag); Text(l.name).font(HubFont.p(13)) }
                            .foregroundColor(t.langID == l.id ? .white : T.text).padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(t.langID == l.id ? HubTheme.blue : T.content))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Label("\(t.streak)", systemImage: "flame.fill").foregroundColor(Color(hex: "#F5B963")).font(HubFont.p(13))
                Label("\(t.xp) XP", systemImage: "star.fill").foregroundColor(HubTheme.blue).font(HubFont.p(13))
            }
            HStack(spacing: 12) {
                ZSelect(label: "Level", value: Binding(get: { t.level }, set: { t.levels[t.langID] = $0 }), options: ["A1", "A2", "B1", "B2", "C1", "C2"].map { ($0, $0) }, light: light).frame(width: 110)
                Button("Not sure? Take the level test") { tab = "Level test"; Task { pIndex = 0; pScore = 0; await t.startPlacement() } }.buttonStyle(.plain).foregroundColor(HubTheme.blue).font(HubFont.p(12))
                Spacer()
                ZSelect(label: "Explain in", value: $t.explainIn, options: ["English", "Urdu", "Arabic", "Hindi", "Spanish", "French", "German", "Turkish", "Bengali", "Polish"].map { ($0, $0) }, light: light).frame(width: 160)
            }
            HStack(spacing: 8) {
                ForEach(["Lesson", "Speak with your teacher", "Pronunciation", "My words"], id: \.self) { s in
                    Button { tab = s } label: {
                        Text(s).font(HubFont.p(13)).foregroundColor(tab == s ? .white : T.text).padding(.horizontal, 14).frame(height: 30)
                            .background(Capsule().fill(tab == s ? Color(hex: "#7C5CFF") : T.content))
                    }.buttonStyle(.plain)
                }
            }
            if !t.busy.isEmpty && t.busy != "…" { HStack(spacing: 8) { ProgressView().controlSize(.small); Text(t.busy).font(HubFont.p(13, .regular)) } }
            switch tab {
            case "Speak with your teacher": conversation
            case "Pronunciation": pronunciation
            case "My words": review
            case "Level test": placementView
            default: lessonView
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func target(_ s: String, size: CGFloat = 15, weight: Font.Weight = .medium) -> some View {
        Text(s).font(HubFont.p(size, weight)).environment(\.layoutDirection, t.lang.rtl ? .rightToLeft : .leftToRight)
            .multilineTextAlignment(t.lang.rtl ? .trailing : .leading).textSelection(.enabled)
    }
    private func speaker(_ s: String) -> some View {
        Button { TutorVoice.shared.say(s, t.lang) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.plain).foregroundColor(HubTheme.blue).help("Listen")
    }

    private var lessonView: some View {
        VStack(alignment: .leading, spacing: 18) {
            DashCard(light: light) {
                HStack(spacing: 10) {
                    ZField(label: "Topic (optional): food, travel, work, past tense…", text: $topic, light: light)
                    DashButton(title: t.lesson == nil ? "Start today's lesson" : "New lesson", icon: "book.fill", light: light) { picks = [:]; let tp = topic; Task { await t.newLesson(topic: tp) } }
                }
            }
            if let l = t.lesson {
                DashCard(title: l.title, sub: "New words — click 🔊 to hear them", light: light) {
                    ForEach(Array(l.words.enumerated()), id: \.offset) { _, w in
                        HStack(alignment: .top, spacing: 12) {
                            speaker(w["word"] ?? "")
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { target(w["word"] ?? "", size: 16, weight: .semibold); Text("— " + (w["meaning"] ?? "")).font(HubFont.p(13.5, .regular)).foregroundColor(T.inactive) }
                                if let ex = w["example"], !ex.isEmpty { HStack(spacing: 6) { speaker(ex); target(ex, size: 13.5, weight: .regular) } }
                                if let em = w["exampleMeaning"], !em.isEmpty { Text(em).font(HubFont.p(12, .regular)).foregroundColor(T.inactive) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                DashCard(title: "Grammar", light: light) {
                    Text(l.grammar).font(HubFont.p(14, .regular)).textSelection(.enabled)
                    ForEach(l.grammarExamples, id: \.self) { e in HStack { speaker(e.components(separatedBy: " — ").first ?? e); target(e, size: 13.5, weight: .regular) } }
                }
                DashCard(title: "Practice", light: light) {
                    ForEach(Array(l.exercises.enumerated()), id: \.offset) { i, ex in
                        VStack(alignment: .leading, spacing: 6) {
                            target("\(i + 1). " + ex.q, size: 14, weight: .semibold)
                            HStack(spacing: 8) {
                                ForEach(Array(ex.options.enumerated()), id: \.offset) { oi, o in
                                    Button { if picks[i] == nil { picks[i] = oi; if oi == ex.answer { t.earned(2) } } } label: {
                                        target(o, size: 13, weight: .regular).padding(.horizontal, 12).padding(.vertical, 7)
                                            .background(Capsule().fill(picks[i] == nil ? T.content : oi == ex.answer ? Color(hex: "#3DBE7E").opacity(0.25) : picks[i] == oi ? Color(hex: "#EF6B6B").opacity(0.25) : T.content))
                                    }.buttonStyle(.plain)
                                }
                            }
                            if picks[i] != nil { Text(ex.why).font(HubFont.p(12, .regular)).foregroundColor(T.inactive) }
                        }.padding(.vertical, 4)
                    }
                }
                if !l.phrases.isEmpty {
                    DashCard(title: "Say these out loud", light: light) {
                        ForEach(l.phrases, id: \.self) { p in HStack { speaker(p); target(p) ; Spacer(); Button("Practise") { practice = p; tab = "Pronunciation" }.buttonStyle(.plain).foregroundColor(HubTheme.blue).font(HubFont.p(12)) } }
                    }
                }
            }
        }
    }

    private var conversation: some View {
        DashCard(title: "Speak with your teacher", sub: "Talk or type in \(t.lang.name). Your teacher answers, corrects you gently and gives tips.", light: light) {
            ZSelect(label: "Situation", value: $t.scenario, options: LanguageTutor.scenarios.map { ($0, $0) }, light: light).frame(width: 300)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if t.chat.isEmpty { Text("Say hello to start — e.g. “\(["en": "Hi! How are you?", "es": "¡Hola! ¿Qué tal?", "fr": "Bonjour ! Ça va ?", "de": "Hallo! Wie geht's?", "ar": "مرحبا! كيف حالك؟"][t.langID] ?? "Hello!")”").font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
                    ForEach(t.chat) { m in
                        HStack(alignment: .top) {
                            if m.mine { Spacer(minLength: 80) }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) { if !m.mine { speaker(m.text) }; target(m.text, size: 14.5, weight: .regular) }
                                if !m.note.isEmpty { Text(m.note).font(HubFont.p(12, .regular)).foregroundColor(Color(hex: "#F5B963")) }
                            }
                            .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(m.mine ? HubTheme.blue.opacity(0.22) : T.content))
                            if !m.mine { Spacer(minLength: 80) }
                        }
                    }
                    if t.busy == "…" { Text("Your teacher is typing…").font(HubFont.p(12, .regular)).foregroundColor(T.inactive) }
                }
            }.frame(minHeight: 260, maxHeight: 420)
            HStack(spacing: 10) {
                Button { if ear.listening { ear.stop(); typed = ear.heard } else { ear.start(t.lang) } } label: {
                    Image(systemName: ear.listening ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 30)).foregroundColor(ear.listening ? Color(hex: "#E5534B") : HubTheme.blue)
                }.buttonStyle(.plain).help("Speak")
                ZField(label: "Write in \(t.lang.name)…", text: Binding(get: { ear.listening ? ear.heard : typed }, set: { typed = $0 }), light: light, onSubmit: send)
                    .environment(\.layoutDirection, t.lang.rtl ? .rightToLeft : .leftToRight)
                DashButton(title: "Send", icon: "paperplane.fill", light: light, go: send)
            }
        }
    }
    private func send() {
        let s = ear.listening ? ear.heard : typed
        ear.stop(); typed = ""
        Task { await t.say(s) }
    }

    private var pronunciation: some View {
        DashCard(title: "Pronunciation", sub: "Listen, then say it. Zuffi checks how close you were.", light: light) {
            HStack(spacing: 10) {
                ZField(label: "A phrase in \(t.lang.name)", text: $practice, light: light).environment(\.layoutDirection, t.lang.rtl ? .rightToLeft : .leftToRight)
                Button { TutorVoice.shared.say(practice, t.lang, slow: true) } label: { Label("Slow", systemImage: "tortoise.fill") }.buttonStyle(.plain).foregroundColor(HubTheme.blue)
                Button { TutorVoice.shared.say(practice, t.lang) } label: { Label("Normal", systemImage: "speaker.wave.2.fill") }.buttonStyle(.plain).foregroundColor(HubTheme.blue)
            }
            HStack(spacing: 14) {
                DashButton(title: ear.listening ? "Stop" : "Say it", icon: ear.listening ? "stop.fill" : "mic.fill", light: light) { if ear.listening { ear.stop() } else { ear.start(t.lang) } }
                if !ear.heard.isEmpty {
                    let score = LanguageTutor.match(ear.heard, practice)
                    VStack(alignment: .leading, spacing: 2) {
                        target("I heard: " + ear.heard, size: 13.5, weight: .regular)
                        Text(score >= 90 ? "Excellent — \(score)% 🎉" : score >= 60 ? "Good — \(score)%. Listen again and repeat the words you missed." : "\(score)% — listen slowly and try again.")
                            .font(HubFont.p(13)).foregroundColor(score >= 60 ? Color(hex: "#3DBE7E") : Color(hex: "#F5B963"))
                    }
                    .onAppear { if score >= 90 { t.earned(3) } }
                }
            }
            if practice.isEmpty, let p = t.lesson?.phrases.first { Button("Use: \(p)") { practice = p }.buttonStyle(.plain).foregroundColor(HubTheme.blue).font(HubFont.p(12)) }
        }
    }

    private var review: some View {
        let mine = t.words.filter { $0.lang == t.langID }
        let due = mine.filter { $0.due <= Date() }
        return DashCard(title: "My words (\(mine.count))", sub: due.isEmpty ? "Nothing to review right now — great!" : "\(due.count) to review today. Words come back just before you'd forget them.", light: light) {
            if let w = due.isEmpty ? nil : due[min(reviewIndex, due.count - 1)] {
                VStack(spacing: 14) {
                    HStack { speaker(w.word); target(w.word, size: 24, weight: .semibold) }
                    if reveal {
                        Text(w.meaning).font(HubFont.p(16, .regular))
                        if !w.example.isEmpty { target(w.example, size: 13.5, weight: .regular) }
                        HStack(spacing: 12) {
                            DashButton(title: "Again", filled: false, light: light) { grade(w, ok: false) }
                            DashButton(title: "I knew it", icon: "checkmark", light: light) { grade(w, ok: true) }
                        }
                    } else { DashButton(title: "Show meaning", light: light) { reveal = true } }
                }.frame(maxWidth: .infinity).padding(.vertical, 20)
            }
            if !mine.isEmpty {
                Divider()
                ForEach(mine.suffix(30).reversed()) { w in HStack { speaker(w.word); target(w.word, size: 13.5); Text("— " + w.meaning).font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive); Spacer() } }
            }
        }
    }
    private func grade(_ w: TutorWord, ok: Bool) {
        guard let i = t.words.firstIndex(where: { $0.id == w.id }) else { return }
        let box = ok ? min(5, w.box + 1) : 0
        t.words[i].box = box
        t.words[i].due = Date().addingTimeInterval(Double([0, 1, 3, 7, 14, 30][box]) * 86400 + (ok ? 0 : 60))
        reveal = false; reviewIndex += 1
        if ok { t.earned(1) }
    }

    private var placementView: some View {
        DashCard(title: "Level test — \(t.lang.name)", sub: "10 questions, from easy to hard.", light: light) {
            if t.placement.isEmpty { Text(t.busy.isEmpty ? "Couldn't make the test — check an AI is set up in Settings." : "").font(HubFont.p(13, .regular)) }
            else if pIndex < t.placement.count {
                let q = t.placement[pIndex]
                target("\(pIndex + 1). " + q.q, size: 16, weight: .semibold)
                ForEach(Array(q.options.enumerated()), id: \.offset) { i, o in
                    Button { if pPick == nil { pPick = i; if i == q.answer { pScore += 1 } } } label: {
                        target(o, size: 14, weight: .regular).padding(12).frame(maxWidth: .infinity, alignment: t.lang.rtl ? .trailing : .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(pPick == nil ? T.content : i == q.answer ? Color(hex: "#3DBE7E").opacity(0.22) : pPick == i ? Color(hex: "#EF6B6B").opacity(0.22) : T.content))
                    }.buttonStyle(.plain)
                }
                if pPick != nil {
                    DashButton(title: pIndex + 1 == t.placement.count ? "See my level" : "Next", icon: "arrow.right", light: light) {
                        pPick = nil; pIndex += 1
                        if pIndex >= t.placement.count { t.finishPlacement(correct: pScore); tab = "Lesson" }
                    }
                }
            }
        }
    }
}
