import SwiftUI
import AVFoundation
import Speech
import WebKit
import NaturalLanguage

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

/// Nik's voice: speaks the language you're learning with the right accent (a male voice when the Mac has one),
/// and tells Nik's face when he is talking and on every word, so his lips move with the voice.
@MainActor
final class TutorVoice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = TutorVoice()
    private let synth = AVSpeechSynthesizer()
    @Published var speaking = false
    @Published var beat = 0          // goes up on every spoken word
    override init() { super.init(); synth.delegate = self }

    func say(_ text: String, _ lang: TutorLanguage, slow: Bool = false) { speak(text, locale: lang.locale, slow: slow) }
    /// Speak in the language the text is written in (notes, explanations).
    func speakAuto(_ text: String, fallback: String = "en-GB") {
        let r = NLLanguageRecognizer(); r.processString(String(text.prefix(2000)))
        speak(text, locale: r.dominantLanguage?.rawValue ?? fallback)
    }
    static func locale(forName name: String) -> String {
        ["English": "en-GB", "Urdu": "ur-PK", "Arabic": "ar-SA", "Hindi": "hi-IN", "Spanish": "es-ES", "French": "fr-FR",
         "German": "de-DE", "Turkish": "tr-TR", "Bengali": "bn-IN", "Polish": "pl-PL"][name] ?? "en-GB"
    }
    func speak(_ text: String, locale: String, slow: Bool = false) {
        synth.stopSpeaking(at: .immediate)
        let clean = Self.plain(text)
        guard !clean.isEmpty else { return }
        let u = AVSpeechUtterance(string: clean)
        let all = AVSpeechSynthesisVoice.speechVoices()
        var pool = all.filter { $0.language == locale }
        if pool.isEmpty { pool = all.filter { $0.language.hasPrefix(String(locale.prefix(2))) } }
        u.voice = pool.max { Self.score($0) < Self.score($1) } ?? AVSpeechSynthesisVoice(language: locale)
        u.rate = slow ? 0.38 : 0.47
        u.pitchMultiplier = 0.95
        synth.speak(u)
    }
    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }
    private static func score(_ v: AVSpeechSynthesisVoice) -> Int { v.quality.rawValue * 10 + (v.gender == .male ? 20 : 0) }
    private static func plain(_ t: String) -> String {
        var s = t
        for c in ["✗", "✓", "✏️", "💡", "→", "*", "#", "•", "`"] { s = s.replacingOccurrences(of: c, with: c == "→" ? ", " : " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in TutorVoice.shared.speaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in TutorVoice.shared.speaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in TutorVoice.shared.speaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in TutorVoice.shared.beat &+= 1 }
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
            Make today's speaking lesson\(topic.isEmpty ? " (the next useful real-life situation on the speaking course path for level \(level))" : " about: \(topic)"). Build it around phrases and short sentences the student will actually say, not a list of single words. Don't repeat these known words: \(known.isEmpty ? "none" : known).
            JSON only:
            {"title":"lesson title in \(explainIn)",
             "words":[{"word":"in \(lang.name)","meaning":"in \(explainIn)","example":"short sentence in \(lang.name)","exampleMeaning":"in \(explainIn)"}],
             "grammar":"one grammar point explained simply in \(explainIn)","grammarExamples":["\(lang.name) example — \(explainIn) meaning"],
             "exercises":[{"q":"…","options":["…","…","…","…"],"answer":0,"why":"in \(explainIn)"}],
             "phrases":["5 whole sentences in \(lang.name) to say out loud in this situation"]}
            8 useful words or short chunks (each with an example sentence), 6 exercises that practise using the phrases in conversation.
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
            NikCard(light: light,
                    line: tab == "Speak with your teacher" ? "Talk or write to me in \(t.lang.name). I'll check every word, show you what to fix and explain why we say it that way."
                        : "Hello! I'm Nik. We'll learn \(t.lang.name) step by step, at your level (\(t.level)). Ask me anything, any time.",
                    hello: "Hello! I'm Nik, your teacher. Let's learn \(t.lang.name) together. Speak or write to me, and I'll gently fix your mistakes and explain why.",
                    listen: { TutorVoice.shared.speak("Hello! I'm Nik, your teacher. Let's learn \(t.lang.name) together. Speak or write to me, and I'll gently fix your mistakes and explain why.", locale: TutorVoice.locale(forName: t.explainIn)) })
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
                                if !m.note.isEmpty {
                                    HStack(alignment: .top, spacing: 6) {
                                        Button { TutorVoice.shared.speak(m.note, locale: TutorVoice.locale(forName: t.explainIn)) } label: { Image(systemName: "speaker.wave.2.fill") }
                                            .buttonStyle(.plain).foregroundColor(Color(hex: "#F5B963")).help("Nik explains this")
                                        Text(m.note).font(HubFont.p(12, .regular)).foregroundColor(Color(hex: "#F5B963")).textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(m.mine ? HubTheme.blue.opacity(0.22) : T.content))
                            if !m.mine { Spacer(minLength: 80) }
                        }
                    }
                    if t.busy == "…" { Text("Nik is thinking…").font(HubFont.p(12, .regular)).foregroundColor(T.inactive) }
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

// MARK: - Nik, the student's teacher (face with lip movement)

/// Nik's face. His mouth moves while he speaks (on every word), his brows lift, he blinks and breathes.
struct NikAvatar: NSViewRepresentable {
    @ObservedObject var voice = TutorVoice.shared
    var mood = "smile"            // "smile" or "explain" (calm look when quiet)

    final class Web: WKWebView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never steals clicks or scrolling
    }
    func makeNSView(context: Context) -> WKWebView {
        let w = Web(frame: .zero)
        w.setValue(false, forKey: "drawsBackground")
        w.loadHTMLString(NikArt.html, baseURL: nil)
        return w
    }
    func updateNSView(_ w: WKWebView, context: Context) {
        w.evaluateJavaScript("window.nik && window.nik(\(voice.speaking ? "true" : "false"), \(voice.beat), '\(mood)')", completionHandler: nil)
    }
}

/// Nik's card: face, name and what he's doing. Says hello the first time the student opens a lesson.
struct NikCard: View {
    var light: Bool
    var line: String
    var hello: String = ""
    var mood = "smile"
    var listen: (() -> Void)?
    @ObservedObject private var voice = TutorVoice.shared
    @MainActor static var greeted = false
    private var T: HubTheme { HubTheme(light: light) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            NikAvatar(mood: mood).frame(width: 118, height: 156)
                .background(RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [Color(hex: "#E8EDF4"), Color(hex: "#D9E1EC")], startPoint: .top, endPoint: .bottom)))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Nik").font(HubFont.p(18, .semibold)).foregroundColor(T.text)
                    Text(voice.speaking ? "speaking…" : "your teacher · 20 years").font(HubFont.p(12, .regular)).foregroundColor(voice.speaking ? HubTheme.blue : T.inactive)
                }
                Text(line).font(HubFont.p(13.5, .regular)).foregroundColor(T.text).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    if let listen {
                        Button { voice.speaking ? voice.stop() : listen() } label: {
                            Label(voice.speaking ? "Stop" : "Listen to Nik", systemImage: voice.speaking ? "stop.fill" : "speaker.wave.2.fill")
                        }.buttonStyle(.plain).foregroundColor(HubTheme.blue).font(HubFont.p(12.5))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 24).fill(T.content))
        .onAppear {
            guard !hello.isEmpty, !Self.greeted else { return }
            Self.greeted = true
            voice.speak(hello, locale: "en-GB")
        }
    }
}

enum NikArt {
    static let html = #"""
<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;background:transparent;overflow:hidden}
svg{width:100%;height:100%;display:block}
#bob{transform-box:fill-box;transform-origin:50% 100%;animation:idle 4.5s ease-in-out infinite}
body.talk #bob{animation:nod 1.1s ease-in-out infinite}
@keyframes idle{0%,100%{transform:translateY(0) rotate(0deg)}50%{transform:translateY(-1.5px) rotate(.7deg)}}
@keyframes nod{0%,100%{transform:translateY(0) rotate(-.6deg)}50%{transform:translateY(1.2px) rotate(.8deg)}}
#brows{transition:transform .18s ease}
body.talk #brows{transform:translateY(-3px)}
#eyeL,#eyeR{transform-box:fill-box;transform-origin:center;transition:transform .07s}
body.blink #eyeL,body.blink #eyeR{transform:scaleY(.08)}
#chest{transform-box:fill-box;transform-origin:50% 100%;animation:breathe 4.5s ease-in-out infinite}
@keyframes breathe{0%,100%{transform:scale(1)}50%{transform:scale(1.008,1.012)}}
</style></head><body>
<svg viewBox="165 48 270 357" xmlns="http://www.w3.org/2000/svg">
<defs>
<radialGradient id="sk" cx="0.42" cy="0.38" r="0.7"><stop offset="0" stop-color="#F7D3BC"/><stop offset="0.55" stop-color="#EBB596"/><stop offset="1" stop-color="#C98868"/></radialGradient>
<linearGradient id="nk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#B9785A"/><stop offset="0.45" stop-color="#D99C7C"/><stop offset="1" stop-color="#E4AC8C"/></linearGradient>
<linearGradient id="hr" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5A3C2A"/><stop offset="0.5" stop-color="#3B271B"/><stop offset="1" stop-color="#24170F"/></linearGradient>
<linearGradient id="gy" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4A3426"/><stop offset="1" stop-color="#A39C95"/></linearGradient>
<linearGradient id="sh" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#F7FAFD"/><stop offset="0.55" stop-color="#E6EDF4"/><stop offset="1" stop-color="#C3CFDC"/></linearGradient>
<linearGradient id="sl" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#D3DCE6"/><stop offset="0.5" stop-color="#F6F9FC"/><stop offset="1" stop-color="#DCE4ED"/></linearGradient>
<linearGradient id="sr" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#DCE4ED"/><stop offset="0.45" stop-color="#E9EFF5"/><stop offset="1" stop-color="#B8C5D3"/></linearGradient>
<linearGradient id="ti" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#3D5F93"/><stop offset="0.5" stop-color="#2D4A78"/><stop offset="1" stop-color="#1D3156"/></linearGradient>
<radialGradient id="ir" cx="0.4" cy="0.35" r="0.7"><stop offset="0" stop-color="#9A6A3E"/><stop offset="0.7" stop-color="#5E3A1E"/><stop offset="1" stop-color="#2E1B0E"/></radialGradient>
<radialGradient id="bl" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#E88C7A" stop-opacity="0.42"/><stop offset="1" stop-color="#E88C7A" stop-opacity="0"/></radialGradient>
<linearGradient id="jw" x1="0" y1="0" x2="1" y2="0"><stop offset="0.55" stop-color="#B8714F" stop-opacity="0"/><stop offset="1" stop-color="#B8714F" stop-opacity="0.45"/></linearGradient>
<linearGradient id="ln" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF" stop-opacity="0.38"/><stop offset="0.35" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>
<clipPath id="cL"><path d="M231,207 C239,193 270,192 279,206 C270,216 241,217 231,207 Z"/></clipPath>
<clipPath id="cR"><path d="M321,206 C330,192 361,193 369,207 C359,217 330,216 321,206 Z"/></clipPath>
</defs>
<g id="chest">
<path d="M274,292 L272,380 C284,394 316,394 328,380 L326,292 Z" fill="url(#nk)"/>
<path d="M150,430 C152,400 198,382 252,372 L348,372 C402,382 448,400 450,430 L452,560 L148,560 Z" fill="url(#sh)"/>
<path d="M300,412 L300,560" stroke="#C3CEDA" stroke-width="2"/>
<path d="M206,452 L252,452 L250,494 C238,500 218,500 208,494 Z" fill="none" stroke="#C7D1DC" stroke-width="2"/>
<path d="M262,352 C280,364 320,364 338,352 L342,372 C320,384 280,384 258,372 Z" fill="#E2E9F1"/>
<path d="M292,398 L308,398 L322,548 L300,574 L278,548 Z" fill="url(#ti)"/>
<path d="M286,378 L314,378 L310,404 L290,404 Z" fill="#2A4470"/>
<path d="M300,394 L262,356 L240,380 L266,418 Z" fill="#F4F8FB" stroke="#CBD5E0" stroke-width="1.5" stroke-linejoin="round"/>
<path d="M300,394 L338,356 L360,380 L334,418 Z" fill="#E7EDF3" stroke="#C3CEDA" stroke-width="1.5" stroke-linejoin="round"/>
<path d="M150,420 C126,440 118,500 122,566 L204,566 L202,474 C200,440 182,418 150,420 Z" fill="url(#sl)"/>
<path d="M450,420 C474,440 482,500 478,566 L396,566 L398,474 C400,440 418,418 450,420 Z" fill="url(#sr)"/>
</g>
<g id="bob"><g transform="translate(300,342) scale(0.86) translate(-300,-342)">
<ellipse cx="203" cy="226" rx="17" ry="27" fill="#E2A483"/>
<path d="M200,212 C192,218 192,236 200,242" stroke="#B9775A" stroke-width="2.5" fill="none" stroke-linecap="round"/>
<ellipse cx="397" cy="226" rx="17" ry="27" fill="#D99A79"/>
<path d="M400,212 C408,218 408,236 400,242" stroke="#A9694C" stroke-width="2.5" fill="none" stroke-linecap="round"/>
<path d="M300,102 C366,102 400,148 402,210 C404,262 386,296 356,320 C336,336 318,342 300,342 C282,342 264,336 244,320 C214,296 196,262 198,210 C200,148 234,102 300,102 Z" fill="url(#sk)"/>
<path d="M300,102 C366,102 400,148 402,210 C404,262 386,296 356,320 C336,336 318,342 300,342 C282,342 264,336 244,320 C214,296 196,262 198,210 C200,148 234,102 300,102 Z" fill="url(#jw)"/>
<ellipse cx="236" cy="262" rx="30" ry="18" fill="url(#bl)"/>
<ellipse cx="364" cy="262" rx="30" ry="18" fill="url(#bl)"/>
<ellipse cx="290" cy="152" rx="44" ry="13" fill="#FBE0CF" opacity="0.4"/>
<path d="M200,204 C188,160 196,104 236,78 C270,56 334,50 372,68 C410,86 416,140 402,204 C400,212 398,218 397,222 L393,222 C393,194 391,170 384,154 C360,130 304,118 254,126 C232,132 218,146 212,164 C208,182 207,200 207,222 L203,222 C202,216 201,210 200,204 Z" fill="url(#hr)"/>
<path d="M250,128 C244,100 266,72 314,64 C360,58 396,80 402,118 C394,124 386,134 384,146 C374,124 350,110 318,110 C292,110 268,118 250,128 Z" fill="#432C1E"/>
<path d="M254,124 C262,98 290,80 328,76 C356,74 380,84 392,102" stroke="#7E5A41" stroke-width="4" fill="none" stroke-linecap="round" opacity="0.85"/>
<path d="M262,116 C276,98 302,88 334,88 C358,88 378,98 390,114" stroke="#664532" stroke-width="3" fill="none" stroke-linecap="round" opacity="0.8"/>
<path d="M300,70 C330,64 360,70 382,86" stroke="#9A7860" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.55"/>
<path d="M251,127 C245,108 246,90 256,74" stroke="#20140C" stroke-width="2.2" fill="none" stroke-linecap="round" opacity="0.7"/>
<path d="M248,90 C236,100 226,118 222,140" stroke="#6B4A35" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.6"/>
<path d="M203,222 C202,200 204,184 209,172 C211,192 211,208 208,222 Z" fill="url(#gy)" opacity="0.85"/>
<path d="M397,222 C398,200 396,184 391,172 C389,192 389,208 392,222 Z" fill="url(#gy)" opacity="0.85"/>
<g id="eyeL">
<path d="M231,207 C239,193 270,192 279,206 C270,216 241,217 231,207 Z" fill="#FBF8F5"/>
<g clip-path="url(#cL)"><circle cx="256" cy="205" r="10.5" fill="url(#ir)"/><circle cx="256" cy="205" r="4.6" fill="#140C07"/><circle cx="259.5" cy="201.5" r="2.4" fill="#FFFFFF"/></g>
<path d="M229,207 C238,192 270,190 281,205" stroke="#2A1A10" stroke-width="3" fill="none" stroke-linecap="round"/>
</g>
<g id="eyeR">
<path d="M321,206 C330,192 361,193 369,207 C359,217 330,216 321,206 Z" fill="#FBF8F5"/>
<g clip-path="url(#cR)"><circle cx="344" cy="205" r="10.5" fill="url(#ir)"/><circle cx="344" cy="205" r="4.6" fill="#140C07"/><circle cx="347.5" cy="201.5" r="2.4" fill="#FFFFFF"/></g>
<path d="M319,205 C330,190 362,192 371,207" stroke="#2A1A10" stroke-width="3" fill="none" stroke-linecap="round"/>
</g>
<path d="M236,212 C246,218 264,218 276,211" stroke="#C48263" stroke-width="1.5" fill="none" opacity="0.7"/>
<path d="M324,211 C336,218 354,218 364,212" stroke="#C48263" stroke-width="1.5" fill="none" opacity="0.7"/>
<path d="M224,206 L217,203 M225,212 L218,213" stroke="#C48263" stroke-width="1.4" stroke-linecap="round" opacity="0.7"/>
<path d="M376,206 L383,203 M375,212 L382,213" stroke="#B9775A" stroke-width="1.4" stroke-linecap="round" opacity="0.7"/>
<g id="brows">
<path d="M226,176 C238,164 262,162 284,168 C285,172 284,175 282,176 C262,172 242,174 230,184 C226,183 225,179 226,176 Z" fill="#3B271B"/>
<path d="M374,176 C362,164 338,162 316,168 C315,172 316,175 318,176 C338,172 358,174 370,184 C374,183 375,179 374,176 Z" fill="#3B271B"/>
</g>
<path d="M308,210 C310,228 316,242 320,254" stroke="#C98868" stroke-width="5" fill="none" stroke-linecap="round" opacity="0.28"/>
<path d="M282,258 C276,248 284,240 293,244 C295,234 305,234 307,244 C316,240 324,248 318,258 C310,266 290,266 282,258 Z" fill="#E7AC8C"/>
<ellipse cx="299" cy="247" rx="8" ry="5" fill="#FBE0CF" opacity="0.8"/>
<path d="M287,260 C291,264 295,264 296,261" stroke="#8E4F36" stroke-width="2.2" fill="none" stroke-linecap="round"/>
<path d="M304,261 C305,264 309,264 313,260" stroke="#8E4F36" stroke-width="2.2" fill="none" stroke-linecap="round"/>
<path d="M278,264 C268,270 264,278 265,286" stroke="#C07D5D" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.3"/>
<path d="M322,264 C332,270 336,278 335,286" stroke="#B9775A" stroke-width="2" fill="none" stroke-linecap="round" opacity="0.35"/>
<g id="m_smile">
<path d="M272,284 C287,292 313,292 328,284 C324,297 312,304 300,304 C288,304 276,297 272,284 Z" fill="#6A2626"/>
<path d="M275,285 C288,292 312,292 325,285 L323,291 C311,295 289,295 277,291 Z" fill="#FFFDFB"/>
<path d="M287,308 C294,311 306,311 313,308" stroke="#C9776A" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.6"/>
</g>
<g id="m_rest" style="display:none">
<path d="M276,287 C288,295 310,295 326,283" stroke="#8E3F36" stroke-width="3.5" fill="none" stroke-linecap="round"/>
<path d="M288,303 C295,306 305,306 312,303" stroke="#C9776A" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.6"/>
</g>
<g id="m_a" style="display:none">
<path d="M282,286 C291,283 309,283 318,286 C318,295 310,300 300,300 C290,300 282,295 282,286 Z" fill="#5E1F20"/>
<path d="M285,287 C293,285 307,285 315,287 L314,290 C306,291 294,291 286,290 Z" fill="#FFFDFB"/>
<path d="M289,306 C295,308 305,308 311,306" stroke="#C9776A" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.6"/>
</g>
<g id="m_b" style="display:none">
<path d="M281,284 C290,279 310,279 319,284 C322,301 312,314 300,314 C288,314 278,301 281,284 Z" fill="#5E1F20"/>
<path d="M284,285 C292,281 308,281 316,285 L315,291 C306,293 294,293 285,291 Z" fill="#FFFDFB"/>
<ellipse cx="300" cy="306" rx="11" ry="5" fill="#C8615E"/>
<path d="M289,318 C295,320 305,320 311,318" stroke="#C9776A" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.6"/>
</g>
<g id="m_o" style="display:none">
<ellipse cx="300" cy="294" rx="9" ry="11" fill="#5E1F20"/>
<path d="M292,289 C296,286 304,286 308,289" stroke="#FFFDFB" stroke-width="2.5" fill="none" stroke-linecap="round"/>
<path d="M291,309 C296,311 304,311 309,309" stroke="#C9776A" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.6"/>
</g>
<ellipse cx="255" cy="207" rx="35" ry="29" fill="url(#ln)" stroke="#1E2A44" stroke-width="5"/>
<ellipse cx="345" cy="207" rx="35" ry="29" fill="url(#ln)" stroke="#1E2A44" stroke-width="5"/>
<path d="M289,203 C294,196 306,196 311,203" stroke="#1E2A44" stroke-width="4.5" fill="none" stroke-linecap="round"/>
<path d="M221,200 L204,206" stroke="#1E2A44" stroke-width="4.5" stroke-linecap="round"/>
<path d="M379,200 L396,206" stroke="#1E2A44" stroke-width="4.5" stroke-linecap="round"/>
<path d="M232,190 C238,184 246,181 254,180" stroke="#FFFFFF" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.7"/>
<path d="M322,190 C328,184 336,181 344,180" stroke="#FFFFFF" stroke-width="2.5" fill="none" stroke-linecap="round" opacity="0.7"/>
</g></g>
</svg>
<script>
var speaking=false, lastBeat=-1, mood='smile', timer=null;
function show(k){['smile','rest','a','b','o'].forEach(function(id){document.getElementById('m_'+id).style.display=(id===k)?'inline':'none';});}
function idle(){show(mood==='explain'?'rest':'smile');}
function flap(){
  if(!speaking) return;
  var r=Math.random();
  show(r<0.34?'b':r<0.62?'a':r<0.8?'o':'rest');
  timer=setTimeout(flap, 85+Math.random()*95);
}
window.nik=function(sp, beat, md){
  mood=md||'smile';
  if(sp && !speaking){ speaking=true; flap(); }
  else if(!sp && speaking){ speaking=false; clearTimeout(timer); }
  if(sp && beat!==lastBeat){ show(Math.random()<0.5?'b':'a'); }
  lastBeat=beat;
  document.body.classList.toggle('talk', sp);
  if(!sp) idle();
};
function blink(){ document.body.classList.add('blink'); setTimeout(function(){document.body.classList.remove('blink');},130); setTimeout(blink, 2600+Math.random()*3000); }
setTimeout(blink, 1500);
</script></body></html>
"""#
}
