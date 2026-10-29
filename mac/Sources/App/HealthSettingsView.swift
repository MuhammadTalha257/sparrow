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
    let id: String; let name: String; var native: String = ""; let flag: String; let locale: String; let rtl: Bool; var hello: String = "Hello!"
    /// 50 world languages Nik teaches (the first ten are the most learned).
    static let all: [TutorLanguage] = [
        TutorLanguage(id: "en", name: "English", native: "English", flag: "🇬🇧", locale: "en-GB", rtl: false, hello: "Hello!"),
        TutorLanguage(id: "es", name: "Spanish", native: "Español", flag: "🇪🇸", locale: "es-ES", rtl: false, hello: "¡Hola!"),
        TutorLanguage(id: "fr", name: "French", native: "Français", flag: "🇫🇷", locale: "fr-FR", rtl: false, hello: "Bonjour !"),
        TutorLanguage(id: "de", name: "German", native: "Deutsch", flag: "🇩🇪", locale: "de-DE", rtl: false, hello: "Hallo!"),
        TutorLanguage(id: "ar", name: "Arabic", native: "العربية", flag: "🇸🇦", locale: "ar-SA", rtl: true, hello: "مرحبا!"),
        TutorLanguage(id: "zh", name: "Chinese", native: "中文", flag: "🇨🇳", locale: "zh-CN", rtl: false, hello: "你好！"),
        TutorLanguage(id: "ja", name: "Japanese", native: "日本語", flag: "🇯🇵", locale: "ja-JP", rtl: false, hello: "こんにちは！"),
        TutorLanguage(id: "ko", name: "Korean", native: "한국어", flag: "🇰🇷", locale: "ko-KR", rtl: false, hello: "안녕하세요!"),
        TutorLanguage(id: "hi", name: "Hindi", native: "हिन्दी", flag: "🇮🇳", locale: "hi-IN", rtl: false, hello: "नमस्ते!"),
        TutorLanguage(id: "it", name: "Italian", native: "Italiano", flag: "🇮🇹", locale: "it-IT", rtl: false, hello: "Ciao!"),
        TutorLanguage(id: "pt", name: "Portuguese", native: "Português", flag: "🇵🇹", locale: "pt-PT", rtl: false, hello: "Olá!"),
        TutorLanguage(id: "ru", name: "Russian", native: "Русский", flag: "🇷🇺", locale: "ru-RU", rtl: false, hello: "Привет!"),
        TutorLanguage(id: "tr", name: "Turkish", native: "Türkçe", flag: "🇹🇷", locale: "tr-TR", rtl: false, hello: "Merhaba!"),
        TutorLanguage(id: "ur", name: "Urdu", native: "اردو", flag: "🇵🇰", locale: "ur-PK", rtl: true, hello: "السلام علیکم!"),
        TutorLanguage(id: "bn", name: "Bengali", native: "বাংলা", flag: "🇧🇩", locale: "bn-IN", rtl: false, hello: "নমস্কার!"),
        TutorLanguage(id: "pa", name: "Punjabi", native: "ਪੰਜਾਬੀ", flag: "🇮🇳", locale: "pa-IN", rtl: false, hello: "ਸਤ ਸ੍ਰੀ ਅਕਾਲ!"),
        TutorLanguage(id: "fa", name: "Persian", native: "فارسی", flag: "🇮🇷", locale: "fa-IR", rtl: true, hello: "سلام!"),
        TutorLanguage(id: "id", name: "Indonesian", native: "Bahasa Indonesia", flag: "🇮🇩", locale: "id-ID", rtl: false, hello: "Halo!"),
        TutorLanguage(id: "ms", name: "Malay", native: "Bahasa Melayu", flag: "🇲🇾", locale: "ms-MY", rtl: false, hello: "Helo!"),
        TutorLanguage(id: "vi", name: "Vietnamese", native: "Tiếng Việt", flag: "🇻🇳", locale: "vi-VN", rtl: false, hello: "Xin chào!"),
        TutorLanguage(id: "th", name: "Thai", native: "ไทย", flag: "🇹🇭", locale: "th-TH", rtl: false, hello: "สวัสดี!"),
        TutorLanguage(id: "fil", name: "Tagalog", native: "Tagalog", flag: "🇵🇭", locale: "fil-PH", rtl: false, hello: "Kumusta!"),
        TutorLanguage(id: "sw", name: "Swahili", native: "Kiswahili", flag: "🇰🇪", locale: "sw-KE", rtl: false, hello: "Habari!"),
        TutorLanguage(id: "nl", name: "Dutch", native: "Nederlands", flag: "🇳🇱", locale: "nl-NL", rtl: false, hello: "Hallo!"),
        TutorLanguage(id: "pl", name: "Polish", native: "Polski", flag: "🇵🇱", locale: "pl-PL", rtl: false, hello: "Cześć!"),
        TutorLanguage(id: "el", name: "Greek", native: "Ελληνικά", flag: "🇬🇷", locale: "el-GR", rtl: false, hello: "Γεια σου!"),
        TutorLanguage(id: "he", name: "Hebrew", native: "עברית", flag: "🇮🇱", locale: "he-IL", rtl: true, hello: "שלום!"),
        TutorLanguage(id: "sv", name: "Swedish", native: "Svenska", flag: "🇸🇪", locale: "sv-SE", rtl: false, hello: "Hej!"),
        TutorLanguage(id: "nb", name: "Norwegian", native: "Norsk", flag: "🇳🇴", locale: "nb-NO", rtl: false, hello: "Hei!"),
        TutorLanguage(id: "da", name: "Danish", native: "Dansk", flag: "🇩🇰", locale: "da-DK", rtl: false, hello: "Hej!"),
        TutorLanguage(id: "fi", name: "Finnish", native: "Suomi", flag: "🇫🇮", locale: "fi-FI", rtl: false, hello: "Hei!"),
        TutorLanguage(id: "cs", name: "Czech", native: "Čeština", flag: "🇨🇿", locale: "cs-CZ", rtl: false, hello: "Ahoj!"),
        TutorLanguage(id: "ro", name: "Romanian", native: "Română", flag: "🇷🇴", locale: "ro-RO", rtl: false, hello: "Salut!"),
        TutorLanguage(id: "hu", name: "Hungarian", native: "Magyar", flag: "🇭🇺", locale: "hu-HU", rtl: false, hello: "Szia!"),
        TutorLanguage(id: "uk", name: "Ukrainian", native: "Українська", flag: "🇺🇦", locale: "uk-UA", rtl: false, hello: "Привіт!"),
        TutorLanguage(id: "ta", name: "Tamil", native: "தமிழ்", flag: "🇮🇳", locale: "ta-IN", rtl: false, hello: "வணக்கம்!"),
        TutorLanguage(id: "te", name: "Telugu", native: "తెలుగు", flag: "🇮🇳", locale: "te-IN", rtl: false, hello: "నమస్కారం!"),
        TutorLanguage(id: "mr", name: "Marathi", native: "मराठी", flag: "🇮🇳", locale: "mr-IN", rtl: false, hello: "नमस्कार!"),
        TutorLanguage(id: "gu", name: "Gujarati", native: "ગુજરાતી", flag: "🇮🇳", locale: "gu-IN", rtl: false, hello: "નમસ્તે!"),
        TutorLanguage(id: "ps", name: "Pashto", native: "پښتو", flag: "🇦🇫", locale: "ps-AF", rtl: true, hello: "سلام!"),
        TutorLanguage(id: "so", name: "Somali", native: "Soomaali", flag: "🇸🇴", locale: "so-SO", rtl: false, hello: "Salaan!"),
        TutorLanguage(id: "am", name: "Amharic", native: "አማርኛ", flag: "🇪🇹", locale: "am-ET", rtl: false, hello: "ሰላም!"),
        TutorLanguage(id: "ha", name: "Hausa", native: "Hausa", flag: "🇳🇬", locale: "ha-NG", rtl: false, hello: "Sannu!"),
        TutorLanguage(id: "yo", name: "Yoruba", native: "Yorùbá", flag: "🇳🇬", locale: "yo-NG", rtl: false, hello: "Báwo!"),
        TutorLanguage(id: "zu", name: "Zulu", native: "isiZulu", flag: "🇿🇦", locale: "zu-ZA", rtl: false, hello: "Sawubona!"),
        TutorLanguage(id: "ga", name: "Irish", native: "Gaeilge", flag: "🇮🇪", locale: "ga-IE", rtl: false, hello: "Dia duit!"),
        TutorLanguage(id: "cy", name: "Welsh", native: "Cymraeg", flag: "🏴", locale: "cy-GB", rtl: false, hello: "Helo!"),
        TutorLanguage(id: "ca", name: "Catalan", native: "Català", flag: "🇪🇸", locale: "ca-ES", rtl: false, hello: "Hola!"),
        TutorLanguage(id: "sr", name: "Serbian", native: "Српски", flag: "🇷🇸", locale: "sr-RS", rtl: false, hello: "Здраво!"),
        TutorLanguage(id: "hr", name: "Croatian", native: "Hrvatski", flag: "🇭🇷", locale: "hr-HR", rtl: false, hello: "Bok!"),
    ]
    static var top: [TutorLanguage] { Array(all.prefix(10)) }
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
    @Published var range = NSRange(location: NSNotFound, length: 0)   // the word being spoken now
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
    func speak(_ text: String, locale: String, slow: Bool = false) { speakSequence([(text, locale)], slow: slow) }

    /// Several parts one after another (e.g. "¡Hola!" in Spanish, then the rest in English), each with its own accent.
    func speakSequence(_ parts: [(String, String)], slow: Bool = false) {
        synth.stopSpeaking(at: .immediate)
        for (text, locale) in parts {
            let clean = Self.plain(text)
            guard !clean.isEmpty else { continue }
            let u = AVSpeechUtterance(string: clean)
            u.voice = Self.voice(for: locale)
            // clear and calm: a little slower than normal speech, short pause between parts
            u.rate = slow ? 0.36 : 0.44
            u.pitchMultiplier = 0.96
            u.volume = 1
            u.postUtteranceDelay = 0.25
            synth.speak(u)
        }
    }

    /// The clearest voice the Mac has for this language: premium / enhanced first, a male voice when there's a choice.
    private static var voiceCache: [String: AVSpeechSynthesisVoice] = [:]
    static func voice(for locale: String) -> AVSpeechSynthesisVoice? {
        if let v = voiceCache[locale] { return v }
        let all = AVSpeechSynthesisVoice.speechVoices().filter { v in
            if v.identifier.contains("eloquence") { return false }          // robotic voices
            if #available(macOS 14.0, *), v.voiceTraits.contains(.isNoveltyVoice) { return false }
            return true
        }
        var pool = all.filter { $0.language == locale }
        if pool.isEmpty { pool = all.filter { $0.language.hasPrefix(String(locale.prefix(2))) } }
        if pool.isEmpty { pool = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(String(locale.prefix(2))) } }
        let v = pool.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: locale)
        if let v { voiceCache[locale] = v }
        return v
    }
    func stop() { synth.stopSpeaking(at: .immediate); speaking = false }
    private static func score(_ v: AVSpeechSynthesisVoice) -> Int { v.quality.rawValue * 20 + (v.gender == .male ? 10 : 0) }
    private static func plain(_ t: String) -> String {
        var s = t
        for c in ["✗", "✓", "✏️", "💡", "→", "*", "#", "•", "`"] { s = s.replacingOccurrences(of: c, with: c == "→" ? ", " : " ") }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in TutorVoice.shared.speaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let more = synthesizer.isSpeaking
        Task { @MainActor in if !more { TutorVoice.shared.speaking = false; TutorVoice.shared.range = NSRange(location: NSNotFound, length: 0) } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in TutorVoice.shared.speaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor in TutorVoice.shared.beat &+= 1; TutorVoice.shared.range = characterRange }
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
        \(NikBrain.shared.memory(for: lang))
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
        busy = "Nik is preparing today's lesson…"; defer { busy = "" }
        NikBrain.shared.started(langID)
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
        NikBrain.shared.started(langID)
        let history = chat.suffix(12).map { ($0.mine ? "Student: " : "Teacher: ") + $0.text }.joined(separator: "\n")
        let r = await AIService.shared.oneShot("""
            \(teacher)
            Role-play: \(scenario). Keep the conversation going in \(lang.name) at level \(level) (1-3 short sentences, end with a question).
            Then check every word of the student's LAST message (it may come from the microphone, so also judge words that sound wrong). JSON only:
            {"reply":"your reply in \(lang.name)","correction":"the student's whole sentence corrected (empty if it was correct)",
             "mistakes":[{"said":"the exact wrong part","correct":"the right form","why":"why, and when we use it, in 1-2 simple sentences in \(explainIn)"}],
             "tip":"a kind one-line note in \(explainIn): praise one thing they did well, or what to practise next","newWord":"one useful \(lang.name) word from your reply","newWordMeaning":"its meaning in \(explainIn)"}
            At most 3 mistakes, most important first, each mistake only ONCE; [] if it was correct. "said" must be words the student really wrote.
            If the student wrote in another language instead of \(lang.name) (e.g. "Hello"), give ONE item showing how to say it in \(lang.name).
            "tip" is advice or praise in \(explainIn), never a question.
            CONVERSATION:
            \(history)
            """) ?? ""
        guard let j = AIService.jsonIn(r) as? [String: Any], let reply = j["reply"] as? String else { chat.append(TutorMsg(mine: false, text: "(I couldn't answer — check an AI is set up in Settings.)")); return }
        var note = ""
        // Each mistake once, only if it is really in what the student wrote, and never "x → x".
        func fold(_ x: String) -> String {
            x.lowercased().folding(options: .diacriticInsensitive, locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        let mine = fold(t)
        var seen = Set<String>(), shown = 0
        for m in (j["mistakes"] as? [[String: Any]] ?? []) {
            let said = (m["said"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let fix = (m["correct"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let why = (m["why"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard shown < 3, !fix.isEmpty, said != fix, !seen.contains(fold(fix)) else { continue }
            if !said.isEmpty, !mine.contains(fold(said)) { continue }
            seen.insert(fold(fix)); shown += 1
            note += (said.isEmpty ? "✓ \(fix)" : "✗ \(said) → ✓ \(fix)") + (why.isEmpty ? "" : "\n   " + why) + "\n"
            NikBrain.shared.trouble(langID, fix)
        }
        if let c = (j["correction"] as? String)?.trimmingCharacters(in: .whitespaces), !c.isEmpty, fold(c) != mine, !seen.contains(fold(c)) {
            note += "✏️ " + c + "\n"
        }
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
    @ObservedObject private var brain = NikBrain.shared
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
                ForEach(barLanguages) { l in
                    Button { if t.langID != l.id { t.langID = l.id; NikBrain.shared.started(l.id); NikSays.hello(l) } } label: {
                        HStack(spacing: 6) { Text(l.flag); Text(l.name).font(HubFont.p(13)) }
                            .foregroundColor(t.langID == l.id ? .white : T.text).padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(t.langID == l.id ? HubTheme.blue : T.content))
                    }.buttonStyle(.plain)
                }
                Button { brain.showLanguages = true } label: {
                    Label("All 50 languages", systemImage: "globe").font(HubFont.p(13)).foregroundColor(T.text)
                        .padding(.horizontal, 14).frame(height: 34).background(Capsule().stroke(T.border))
                }.buttonStyle(.plain)
                Spacer()
                Button { brain.showIntake = true } label: { Label(brain.knowsStudent ? "About me" : "Tell Nik about you", systemImage: "person.crop.circle").font(HubFont.p(12.5)) }
                    .buttonStyle(.plain).foregroundColor(HubTheme.blue)
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
        .sheet(isPresented: $brain.showIntake) { NikIntakeSheet(light: light) { brain.showIntake = false } }
        .sheet(isPresented: $brain.showLanguages) { LanguagePickerSheet(light: light) { brain.showLanguages = false } }
        .onAppear { if !brain.knowsStudent { brain.showIntake = true } }
    }

    /// Your courses first, then the most learned languages — always including the one you're on.
    private var barLanguages: [TutorLanguage] {
        var l = brain.courses.prefix(4).map { TutorLanguage.of($0.id) }
        if !l.contains(t.lang) { l.insert(t.lang, at: 0) }
        for x in TutorLanguage.top where l.count < 5 && !l.contains(x) { l.append(x) }
        return Array(l.prefix(5))
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
                                    Button { if picks[i] == nil { picks[i] = oi; if oi == ex.answer { t.earned(2) }; if picks.count == l.exercises.count { NikBrain.shared.lessonDone(t.langID, title: l.title); TutorVoice.shared.speak("Well done! Lesson finished. I've saved your progress.", locale: TutorVoice.locale(forName: t.explainIn)) } } } label: {
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
        w.evaluateJavaScript("window.nik && window.nik(\(voice.speaking ? "true" : "false"), \(voice.beat), '\(mood)', '\(ZuffiSeasons.activeId())')", completionHandler: nil)
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
.o{display:none}
#chest{transform-box:fill-box;transform-origin:50% 100%;animation:breathe 4.5s ease-in-out infinite}
@keyframes breathe{0%,100%{transform:scale(1)}50%{transform:scale(1.008,1.012)}}
</style></head><body>
<svg viewBox="160 26 280 380" xmlns="http://www.w3.org/2000/svg">
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
<g id="o_winter" class="o"><path d="M256,350 C280,372 320,372 344,350 L352,378 C324,402 276,402 248,378 Z" fill="#4F7FD1"/><path d="M314,384 L334,452 L312,458 L298,390 Z" fill="#3E6BB8"/><path d="M262,362 L338,362 M256,374 L344,374" stroke="#E8F0FF" stroke-width="4" opacity="0.7"/></g>
<g id="o_christmas" class="o"><path d="M256,350 C280,372 320,372 344,350 L352,378 C324,402 276,402 248,378 Z" fill="#D2353F"/><path d="M314,384 L334,452 L312,458 L298,390 Z" fill="#B82A33"/><path d="M262,362 L338,362 M256,374 L344,374" stroke="#FFFFFF" stroke-width="4" opacity="0.85"/></g>
<g id="o_halloween" class="o"><path d="M256,350 C280,372 320,372 344,350 L352,378 C324,402 276,402 248,378 Z" fill="#F28A3C"/><path d="M314,384 L334,452 L312,458 L298,390 Z" fill="#D9742B"/><path d="M262,362 L338,362 M256,374 L344,374" stroke="#3B2A4A" stroke-width="4" opacity="0.8"/><circle cx="222" cy="470" r="13" fill="#F28A3C"/><path d="M222,456 L224,449" stroke="#3E7A3A" stroke-width="3" stroke-linecap="round"/><path d="M216,468 L219,465 L221,468 M224,468 L227,465 L229,468 M215,475 C220,479 225,479 230,475" stroke="#3B2A10" stroke-width="1.6" fill="none"/></g>
<g id="o_independence" class="o"><path d="M256,350 C280,372 320,372 344,350 L352,378 C324,402 276,402 248,378 Z" fill="#1F8A4C"/><path d="M314,384 L334,452 L312,458 L298,390 Z" fill="#F4F7F2"/><path d="M262,362 L338,362" stroke="#FFFFFF" stroke-width="5" opacity="0.8"/></g>
<g id="o_ramadan" class="o" transform="translate(4,-74)"><path d="M232,462 A14,14 0 1,0 244,486 A11,11 0 1,1 232,462 Z" fill="#E9C46A"/></g>
<g id="o_valentine" class="o" transform="translate(6,-74)"><path d="M224,476 C214,468 212,458 220,456 C224,455 226,458 227,460 C228,458 230,455 234,456 C242,458 240,468 230,476 L227,479 Z" fill="#F27BA1"/></g>
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
<g id="h_christmas" class="o"><path d="M236,84 C246,22 326,4 372,34 C384,44 390,58 386,70 L366,84 Z" fill="#D2353F"/><rect x="226" y="72" width="152" height="24" rx="12" fill="#FFFFFF"/><circle cx="388" cy="70" r="14" fill="#FFFFFF"/></g>
<g id="h_birthday" class="o"><path d="M300,-2 L266,78 L334,78 Z" fill="#8B6CF2"/><path d="M283,38 L317,38 M274,60 L326,60" stroke="#FFD27A" stroke-width="6"/><circle cx="300" cy="-4" r="10" fill="#F58FA8"/></g>
<g id="h_eid" class="o"><path d="M232,92 C234,54 366,54 368,92 Z" fill="#FBFBF7"/><path d="M234,84 C270,76 330,76 366,84" stroke="#D4AF37" stroke-width="5" fill="none"/></g>
<g id="h_summer" class="o"><ellipse cx="262" cy="104" rx="30" ry="18" fill="#1D2433"/><ellipse cx="338" cy="104" rx="30" ry="18" fill="#1D2433"/><path d="M292,104 L308,104" stroke="#1D2433" stroke-width="5"/><path d="M248,98 C256,94 266,94 272,98" stroke="#FFFFFF" stroke-width="3" opacity="0.5" fill="none"/></g>
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
var outfit='';
function dress(o){
  if(o===outfit) return; outfit=o;
  var all=document.querySelectorAll('.o'); for(var i=0;i<all.length;i++) all[i].style.display='none';
  ['o_','h_'].forEach(function(p){ var e=document.getElementById(p+o); if(e) e.style.display='inline'; });
}
window.nik=function(sp, beat, md, o){
  mood=md||'smile';
  dress(o||'none');
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

// MARK: - Nik's memory: who the student is, each course, what's covered and what's left

struct NikCourse: Codable, Identifiable, Hashable {
    var id: String                    // language id
    var lessonsDone = 0
    var covered: [String] = []
    var trouble: [String] = []
    var started = Date()
    var last: Date?
    var hours: [Int] = []             // the hours they usually start, to learn their study time
}

@MainActor
final class NikBrain: ObservableObject {
    static let shared = NikBrain()
    /// The speaking course: real situations, in order.
    static let path = ["Say hello and introduce yourself", "Ask and answer simple questions", "Food, shopping and prices", "Directions and travel",
                       "Talk about your day", "Talk about yesterday", "Plans and the future", "Opinions and feelings", "Real conversations and phone calls"]
    static let lessonsPerStep = 2
    static var totalLessons: Int { path.count * lessonsPerStep }

    @Published var profile: [String: String] = (UserDefaults.standard.dictionary(forKey: "nikProfile") as? [String: String]) ?? [:] {
        didSet { UserDefaults.standard.set(profile, forKey: "nikProfile") }
    }
    @Published var courses: [NikCourse] = TeamStore.load("nik-courses", [NikCourse]()) { didSet { TeamStore.save("nik-courses", courses) } }
    @Published var showIntake = false
    @Published var showLanguages = false
    var knowsStudent: Bool { !(profile["name"] ?? "").isEmpty }
    var firstName: String { (profile["name"] ?? ZuffiPlan.shared.profile["name"] ?? "").components(separatedBy: " ").first ?? "" }

    func course(_ id: String) -> NikCourse { courses.first { $0.id == id } ?? NikCourse(id: id) }
    private func update(_ id: String, _ change: (inout NikCourse) -> Void) {
        var c = course(id); change(&c)
        courses.removeAll { $0.id == id }
        courses.insert(c, at: 0)                       // the newest course comes first on the dashboard
    }
    func started(_ id: String) {
        update(id) { c in
            c.last = Date(); c.hours.append(Calendar.current.component(.hour, from: Date()))
            if c.hours.count > 20 { c.hours.removeFirst(c.hours.count - 20) }
        }
    }
    func lessonDone(_ id: String, title: String) {
        update(id) { c in
            c.lessonsDone += 1; c.last = Date()
            if !title.isEmpty, !c.covered.contains(title) { c.covered.append(title) }
            if c.covered.count > 40 { c.covered.removeFirst(c.covered.count - 40) }
        }
    }
    func trouble(_ id: String, _ fix: String) {
        update(id) { c in
            c.trouble.removeAll { $0.lowercased() == fix.lowercased() }
            c.trouble.insert(fix, at: 0)
            if c.trouble.count > 6 { c.trouble.removeLast(c.trouble.count - 6) }
        }
    }
    static func step(_ c: NikCourse) -> Int { min(c.lessonsDone / lessonsPerStep, path.count - 1) }
    static func percent(_ c: NikCourse) -> Int { min(100, c.lessonsDone * 100 / max(1, totalLessons)) }
    static func usualTime(_ c: NikCourse) -> String? {
        guard !c.hours.isEmpty else { return nil }
        var count: [Int: Int] = [:]; c.hours.forEach { count[$0, default: 0] += 1 }
        guard let h = count.max(by: { $0.value < $1.value })?.key else { return nil }
        return h == 0 ? "12 am" : h < 12 ? "\(h) am" : h == 12 ? "12 pm" : "\(h - 12) pm"
    }

    /// What Nik always keeps in mind about this student and this course.
    func memory(for lang: TutorLanguage) -> String {
        let c = course(lang.id), st = Self.step(c)
        var lines = ["WHAT YOU REMEMBER ABOUT YOUR STUDENT (use it naturally, don't list it back)"]
        let p = profile
        if let n = p["name"], !n.isEmpty { lines.append("- Name: \(n)") }
        if let a = p["age"], !a.isEmpty { lines.append("- Age group: \(a)") }
        if let o = p["own"], !o.isEmpty { lines.append("- Their own language: \(o)") }
        if let g = p["goals"], !g.isEmpty { lines.append("- Why they learn: \(g)") }
        if let m = p["minutes"], !m.isEmpty { lines.append("- Time per day: \(m)") }
        if let x = p["notes"], !x.isEmpty { lines.append("- They told you: \(x)") }
        lines.append("COURSE: \(lang.name) speaking course, step \(st + 1) of \(Self.path.count): \(Self.path[st]). Lessons done: \(c.lessonsDone) of \(Self.totalLessons).")
        if !c.covered.isEmpty { lines.append("- Already covered: \(c.covered.suffix(8).joined(separator: "; "))") }
        lines.append("- Still to do: \(Self.path[st...].joined(separator: "; "))")
        if !c.trouble.isEmpty { lines.append("- Keeps tripping on (gently revise these): \(c.trouble.joined(separator: "; "))") }
        return lines.joined(separator: "\n")
    }

    // MARK: what Nik remembers across every subject (not only languages)
    struct Session: Codable, Hashable { var day: String; var summary: String; var plan: [String] }
    @Published var sessions: [Session] = TeamStore.load("nik-sessions", [Session]()) { didSet { TeamStore.save("nik-sessions", sessions) } }
    @Published var explained: [String] = (UserDefaults.standard.stringArray(forKey: "nikExplained")) ?? [] { didSet { UserDefaults.standard.set(explained, forKey: "nikExplained") } }
    static func dayKey(_ d: Date = Date()) -> String { ZuffiBusiness.iso(d) }
    var today: Session? { sessions.first { $0.day == Self.dayKey() } }
    var lastSession: Session? { sessions.first { $0.day != Self.dayKey() } }
    func logExplained(_ t: String) {
        explained.insert(String(t.prefix(80)), at: 0)
        if explained.count > 15 { explained.removeLast(explained.count - 15) }
    }
    func setToday(summaryOfLast: String?, lastDay: String?, plan: [String]) {
        if let d = lastDay, let s = summaryOfLast, !s.isEmpty, let i = sessions.firstIndex(where: { $0.day == d }) { sessions[i].summary = s }
        sessions.removeAll { $0.day == Self.dayKey() }
        sessions.insert(Session(day: Self.dayKey(), summary: "", plan: plan), at: 0)
        if sessions.count > 60 { sessions.removeLast(sessions.count - 60) }
    }

    /// Everything Nik knows about the student: profile, language courses, study sets, deadlines, recent sessions.
    func generalMemory() -> String {
        var l = ["WHAT YOU REMEMBER ABOUT YOUR STUDENT (use it naturally, never list it back)"]
        for (k, v) in [("Name", profile["name"]), ("Age group", profile["age"]), ("Own language", profile["own"]), ("Why they learn", profile["goals"]), ("Time per day", profile["minutes"]), ("They told you", profile["notes"])] {
            if let v, !v.isEmpty { l.append("- \(k): \(v)") }
        }
        for c in courses.prefix(4) {
            let st = Self.step(c)
            l.append("- Course: \(TutorLanguage.of(c.id).name), step \(st + 1)/\(Self.path.count) (\(Self.path[st])), \(c.lessonsDone) lessons done" + (c.trouble.isEmpty ? "" : ", trips on: \(c.trouble.prefix(3).joined(separator: "; "))"))
        }
        let decks = StudyHub.shared.decks.prefix(5).map(\.title)
        if !decks.isEmpty { l.append("- Notes they're studying: \(decks.joined(separator: "; "))") }
        let soon = StudyHub.shared.deadlines.filter { !$0.done && $0.date > Date() }.sorted { $0.date < $1.date }.prefix(4)
        if !soon.isEmpty { l.append("- Coming up: " + soon.map { "\($0.title) (\($0.kind), \($0.date.formatted(date: .abbreviated, time: .omitted)))" }.joined(separator: "; ")) }
        for s in sessions.prefix(4) where !s.summary.isEmpty { l.append("- Session \(s.day): \(s.summary)") }
        if let t = today, !t.plan.isEmpty { l.append("- TODAY'S PLAN: " + t.plan.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: "  ")) }
        if !explained.isEmpty { l.append("- Recently asked you to explain: \(explained.prefix(4).joined(separator: "; "))") }
        return l.joined(separator: "\n")
    }

    /// For Zuffi: what the student is learning, so Zuffi can talk about it and send them to Nik.
    func zuffiContext() -> String {
        """

        THE STUDENT'S LEARNING (from their Zuffi dashboard)
        Nik is the student's teacher inside Zuffi: a senior teacher who teaches any subject and 50 languages, remembers every lesson, and talks out loud. \
        Students reach him in Study › Chat with Nik, in Languages, by saying "Hey Nik", or by selecting text and pressing ⌥⌘N ("Nik, explain this").
        When the student wants a lesson, revision or a language, answer briefly and suggest continuing with Nik.
        \(generalMemory())
        """
    }

    // MARK: "Hey Nik …"
    func heard(_ said: String) {
        let low = said.lowercased()
        if low.range(of: #"\b(explain|meaning|mean|what does|what is this|translate|samjha|samjhao)"#, options: .regularExpression) != nil {
            // "Nik, explain this in Urdu" → that language; otherwise the student's own language
            let lang = TutorLanguage.all.first { low.contains("in " + $0.name.lowercased()) }?.name
            Task { await NikReader.shared.explainMarked(in: lang) }
            return
        }
        if low.range(of: #"\b(read|pronounce|say this|how do i (say|read)|this line|marked|highlight)"#, options: .regularExpression) != nil {
            Task { await NikReader.shared.readMarked() }
            return
        }
        LearnNav.languages()
        if said.trimmingCharacters(in: .whitespaces).isEmpty {
            TutorVoice.shared.speak("Yes\(firstName.isEmpty ? "" : ", \(firstName)")? I'm here. What shall we learn today?", locale: "en-GB")
            return
        }
        Task {
            let lang = LanguageTutor.shared.lang
            let r = await AIService.shared.oneShot("""
                The student just said to you out loud: "\(said)"
                Answer as Nik in 2 to 5 short spoken sentences (it will be read aloud). If they ask to learn or practise, start right away with one useful sentence for them to repeat.
                """, system: ZuffiVoice.nik + "\n" + memory(for: lang)) ?? ""
            let answer = r.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !answer.isEmpty else { return }
            AppState.shared.noteIsAlert = false; AppState.shared.noteAction = nil
            AppState.shared.noteMessage = "Nik · Teacher\n" + answer
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
            TutorVoice.shared.speakAuto(answer)
        }
    }
}

/// "Hey Nik", "Hi Nick", "Nik teacher…" → the words after it ("" = just his name). nil = not for Nik.
enum NikWake {
    static func command(_ said: String) -> String? {
        let low = said.lowercased()
        for p in [#"\b(hey|hi|hello|ok|okay|hay)[ ,]+(nik|nick|nic|neek|nikk|nique)\b[\s,.!?]*"#, #"^\s*(nik|nick)[ ,]+(teacher|sir)\b[\s,.!?]*"#, #"\bteacher (nik|nick)\b[\s,.!?]*"#,
                  #"^\s*(nik|nick)[ ,]+(?=(explain|read|what|how|tell|teach|pronounce|translate|meaning))"#] {
            if let r = low.range(of: p, options: .regularExpression) {
                return String(low[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            }
        }
        return nil
    }
}

// MARK: - Nik's "about you" form

struct NikIntakeSheet: View {
    var light: Bool
    let done: () -> Void
    @ObservedObject private var brain = NikBrain.shared
    @ObservedObject private var t = LanguageTutor.shared
    @State private var name = ""
    @State private var age = "18–24"
    @State private var own = "English"
    @State private var learn = "es"
    @State private var level = "A few words"
    @State private var goals: Set<String> = []
    @State private var minutes = "15 minutes"
    @State private var remind = "Evening · 6 pm"
    @State private var notes = ""
    private var T: HubTheme { HubTheme(light: light) }
    private static let levels = ["Nothing yet": "A1", "A few words": "A1", "I can chat a bit": "A2", "I'm good": "B1"]
    private static let goalList = ["School or exam", "Travel", "Work or study abroad", "Family and friends", "Just for fun"]

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                NikAvatar(mood: "smile").frame(width: 220, height: 290)
                    .background(RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [Color(hex: "#E8EDF4"), Color(hex: "#D9E1EC")], startPoint: .top, endPoint: .bottom)))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                Text("Hi, I'm Nik").font(HubFont.p(20, .semibold))
                Text("Before our first lesson, tell me a little about you. I'll remember it every time we meet, so each lesson fits you.")
                    .font(HubFont.p(14, .regular)).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Text("Saved only on this Mac.").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
            }
            .frame(width: 230)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("About you").font(HubFont.p(22, .semibold))
                    HStack(spacing: 14) {
                        ZField(label: "Your name", text: $name, light: light)
                        ZSelect(label: "Age group", value: $age, options: ["Under 13", "13–17", "18–24", "25+"].map { ($0, $0) }, light: light).frame(width: 150)
                    }
                    HStack(spacing: 14) {
                        ZSelect(label: "Your own language", value: $own, options: ["English", "Urdu", "Arabic", "Hindi", "Spanish", "French", "German", "Turkish", "Bengali", "Polish"].map { ($0, $0) }, light: light)
                        ZSelect(label: "Language to learn", value: $learn, options: TutorLanguage.all.map { ($0.id, $0.name) }, light: light)
                    }
                    Text("How much do you know already?").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                    HStack(spacing: 8) { ForEach(["Nothing yet", "A few words", "I can chat a bit", "I'm good"], id: \.self) { l in pill(l, on: level == l) { level = l } } }
                    Text("Why are you learning? (pick any)").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                    WrapRow(items: Self.goalList) { g in pill(g, on: goals.contains(g)) { if goals.contains(g) { goals.remove(g) } else { goals.insert(g) } } }
                    HStack(spacing: 14) {
                        ZSelect(label: "Time per day", value: $minutes, options: ["10 minutes", "15 minutes", "30 minutes", "1 hour"].map { ($0, $0) }, light: light)
                        ZSelect(label: "Best time to learn", value: $remind, options: ["Morning · 8 am", "Afternoon · 3 pm", "Evening · 6 pm", "Night · 9 pm"].map { ($0, $0) }, light: light)
                    }
                    ZField(label: "Anything I should know? (what's hard, how you like to learn)", text: $notes, light: light)
                    HStack {
                        Spacer()
                        Button("Skip for now") { done() }.buttonStyle(.plain).foregroundColor(T.inactive).padding(.horizontal, 12)
                        DashButton(title: "Start my first lesson", icon: "sparkles", light: light) { save() }
                    }
                }
                .padding(.trailing, 6)
            }
        }
        .padding(28).frame(width: 860, height: 600)
        .onAppear {
            name = brain.profile["name"] ?? (ZuffiPlan.shared.profile["name"] ?? "")
            own = brain.profile["own"] ?? t.explainIn
            learn = brain.profile["learn"] ?? t.langID
            if let g = brain.profile["goals"] { goals = Set(g.components(separatedBy: ", ").filter { !$0.isEmpty }) }
            notes = brain.profile["notes"] ?? ""
        }
    }

    private func pill(_ s: String, on: Bool, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Text(s).font(HubFont.p(13)).foregroundColor(on ? .white : T.text).padding(.horizontal, 14).frame(height: 36)
                .background(Capsule().fill(on ? AnyShapeStyle(ZInk.accentGradient) : AnyShapeStyle(T.content)))
        }.buttonStyle(.plain)
    }

    private func save() {
        brain.profile = ["name": name.trimmingCharacters(in: .whitespaces), "age": age, "own": own, "learn": learn, "level": level,
                         "goals": goals.sorted().joined(separator: ", "), "minutes": minutes, "remind": remind, "notes": notes]
        if ["English", "Urdu", "Arabic", "Hindi", "Spanish", "French", "German", "Turkish", "Bengali", "Polish"].contains(own) { t.explainIn = own }
        t.langID = learn
        if t.levels[learn] == nil { t.levels[learn] = Self.levels[level] ?? "A1" }
        brain.started(learn)
        let first = name.components(separatedBy: " ").first ?? ""
        TutorVoice.shared.speak("Thank you\(first.isEmpty ? "" : ", \(first)"). I'll remember all of this. Let's start speaking \(t.lang.name) together.", locale: "en-GB")
        done()
    }
}

/// A row that wraps onto the next line when it runs out of space.
struct WrapRow<Content: View>: View {
    let items: [String]
    @ViewBuilder let content: (String) -> Content
    var body: some View {
        if #available(macOS 13.0, *) {
            FlowLayout(spacing: 8) { ForEach(items, id: \.self) { content($0) } }
        } else {
            HStack(spacing: 8) { ForEach(items, id: \.self) { content($0) } }
        }
    }
}

@available(macOS 13.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing; row = max(row, s.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; row = max(row, s.height)
        }
    }
}

// MARK: - Pick any of 50 languages; Nik says hello in it

struct LanguagePickerSheet: View {
    var light: Bool
    let done: () -> Void
    @ObservedObject private var t = LanguageTutor.shared
    @State private var search = ""
    private var T: HubTheme { HubTheme(light: light) }
    private var found: [TutorLanguage] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? TutorLanguage.all : TutorLanguage.all.filter { $0.name.lowercased().contains(q) || $0.native.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Which language today?").font(HubFont.p(22, .semibold))
                    Text("50 world languages — Nik teaches them all").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                }
                Spacer()
                ZField(label: "Search languages", text: $search, light: light).frame(width: 260)
                Button("Done", action: done).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(found) { l in
                        Button { pick(l) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(l.flag) \(l.native)").font(HubFont.p(15, .semibold)).lineLimit(1)
                                Text(l.name).font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).frame(height: 64)
                            .background(RoundedRectangle(cornerRadius: 16).fill(t.langID == l.id ? HubTheme.blue.opacity(0.22) : T.content))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.langID == l.id ? HubTheme.blue : .clear, lineWidth: 2))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(26).frame(width: 900, height: 600)
        .foregroundColor(T.text)
    }

    private func pick(_ l: TutorLanguage) {
        t.langID = l.id
        NikBrain.shared.started(l.id)
        NikSays.hello(l)
        done()
    }
}

enum NikSays {
    /// Nik greets in the new language, then says what's next in the student's own language.
    @MainActor static func hello(_ l: TutorLanguage) {
        let name = NikBrain.shared.firstName
        let c = NikBrain.shared.course(l.id), st = NikBrain.step(c)
        TutorVoice.shared.speakSequence([
            (l.hello, l.locale),
            ("\(name.isEmpty ? "" : "\(name), ")let's learn \(l.name) together. \(c.lessonsDone == 0 ? "We'll start by saying hello and introducing yourself." : "Last time we got to: \(NikBrain.path[st]). Let's carry on.")",
             TutorVoice.locale(forName: LanguageTutor.shared.explainIn)),
        ])
    }
}

// MARK: - "Hey Nik, read this line": Nik reads the marked line and shows how to say each word

@MainActor
final class NikReader: ObservableObject {
    static let shared = NikReader()
    struct Word: Hashable { let w: String; let say: String; let meaning: String }
    @Published var line = ""
    @Published var locale = "en-GB"
    @Published var words: [Word] = []
    @Published var tips: [String] = []
    @Published var meaning = ""
    @Published var busy = ""
    @Published var score: Int?
    @Published var mode = "read"            // "read" (how to say it) or "explain" (what it means)
    @Published var explanation = ""
    private var panel: NSPanel?

    /// The words the student marked: the selection in the app in front, or what's highlighted on screen.
    private func grabMarked() async -> String {
        var text = Self.selectedText() ?? ""
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let shot = await ScreenGrab.main() {
            text = await AIService.shared.oneShot("""
                Look at this screen. Return ONLY the text the person has selected, highlighted or marked (a word, a line or a paragraph). If nothing is marked, return the single line nearest the middle of the screen. No quotes, nothing else.
                """, system: "You read text from screenshots exactly.", image: (mime: "image/jpeg", base64: shot.jpeg.base64EncodedString())) ?? ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Nik, explain this (in Urdu)" or the keyboard shortcut: Nik looks at what's marked and explains it simply, out loud.
    func explainMarked(in language: String? = nil) async {
        mode = "explain"; show()
        busy = "Nik is looking at what you marked…"; words = []; tips = []; meaning = ""; explanation = ""; score = nil
        let text = await grabMarked()
        guard !text.isEmpty else {
            busy = ""; line = "Select a word or a line first, then say “Nik, explain this”."
            TutorVoice.shared.speak("Select a word or a line first, then ask me again.", locale: "en-GB")
            return
        }
        line = String(text.prefix(1200))
        let lang = language ?? NikBrain.shared.profile["own"] ?? LanguageTutor.shared.explainIn
        busy = "Nik is explaining…"
        let r = await AIService.shared.oneShot("""
            The student marked this on their screen and wants you to explain it:
            "\(line)"
            Explain it in \(lang), simply, like a kind senior teacher talking to them: what it means, then why / how, with one small real example. \
            If it's a single word, give its meaning, how to say it, and one example sentence. If it's a question or exercise, teach the idea step by step (don't just give the answer). \
            Keep it short enough to be read aloud (under 120 words). Plain text, no symbols.
            """, system: ZuffiVoice.nik + "\n" + NikBrain.shared.generalMemory()) ?? ""
        busy = ""
        explanation = r.trimmingCharacters(in: .whitespacesAndNewlines)
        if explanation.isEmpty { explanation = "I couldn't explain it this time — check an AI model is set up in Settings."; return }
        TutorVoice.shared.speak(explanation, locale: TutorVoice.locale(forName: lang))
        NikBrain.shared.logExplained(line)
    }

    func readMarked() async {
        mode = "read"; show()
        busy = "Looking at the line you marked…"; words = []; tips = []; meaning = ""; explanation = ""; score = nil
        let text = await grabMarked()
        guard !text.isEmpty else {
            busy = ""
            line = "Select a line first, then say “Hey Nik, read this”."
            TutorVoice.shared.speak("Select the line you want, then ask me again.", locale: "en-GB")
            return
        }
        line = String(text.prefix(400))
        let r = NLLanguageRecognizer(); r.processString(line)
        locale = Self.voiceLocale(r.dominantLanguage?.rawValue ?? "en")
        busy = ""
        TutorVoice.shared.speak(line, locale: locale, slow: true)
        let explain = LanguageTutor.shared.explainIn
        let j = await AIService.shared.oneShot("""
            The student marked this line and wants to read it aloud correctly: "\(line)"
            JSON only: {"meaning":"what the line means, in \(explain)","words":[{"w":"each word as written","say":"easy sound-it-out spelling with the STRESSED part in capitals","meaning":"short meaning in \(explain)"}],"tips":["1-3 short pronunciation tips in \(explain): silent letters, sounds that are hard for a \(explain) speaker"]}
            """, system: ZuffiVoice.nik).flatMap { AIService.jsonIn($0) as? [String: Any] }
        meaning = (j?["meaning"] as? String) ?? ""
        words = ((j?["words"] as? [[String: Any]]) ?? []).map { Word(w: $0["w"] as? String ?? "", say: $0["say"] as? String ?? "", meaning: $0["meaning"] as? String ?? "") }.filter { !$0.w.isEmpty }
        tips = (j?["tips"] as? [String]) ?? []
    }

    func myTurn() {
        let ear = TutorEar.shared
        if ear.listening {
            ear.stop()
            score = LanguageTutor.match(ear.heard, line)
            let s = score ?? 0
            TutorVoice.shared.speak(s >= 85 ? "Excellent! That was very clear." : s >= 60 ? "Good try! Listen once more and copy my rhythm." : "Let's do it slowly together. Listen first.", locale: "en-GB")
        } else {
            score = nil
            let l = TutorLanguage.all.first { $0.locale == locale } ?? TutorLanguage(id: "x", name: "this language", flag: "", locale: locale, rtl: false)
            ear.start(l)
        }
    }

    static func voiceLocale(_ code: String) -> String {
        if let l = TutorLanguage.all.first(where: { $0.locale.hasPrefix(code + "-") || $0.id == code }) { return l.locale }
        return code
    }

    /// The text selected in the app in front (needs Accessibility, which Zuffi already asks for).
    static func selectedText() -> String? {
        let sys = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let f = focused else { return nil }
        var sel: CFTypeRef?
        guard AXUIElementCopyAttributeValue(f as! AXUIElement, kAXSelectedTextAttribute as CFString, &sel) == .success else { return nil }
        return sel as? String
    }

    func show() {
        if let p = panel { p.orderFrontRegardless(); return }
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 600), styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        p.title = "Nik"; p.titlebarAppearsTransparent = true; p.isReleasedWhenClosed = false
        p.level = .floating; p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = NSHostingView(rootView: NikReadView())
        if let s = NSScreen.main { p.setFrameOrigin(NSPoint(x: s.visibleFrame.maxX - 500, y: s.visibleFrame.maxY - 640)) }
        p.orderFrontRegardless()
        panel = p
    }
}

struct NikReadView: View {
    @ObservedObject private var r = NikReader.shared
    @ObservedObject private var voice = TutorVoice.shared
    @ObservedObject private var ear = TutorEar.shared
    private var spoken: Int? {
        // which word Nik is saying right now
        guard voice.speaking, voice.range.location != NSNotFound else { return nil }
        let ns = r.line as NSString
        var i = 0, idx: Int?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byWords) { _, range, _, stop in
            if NSLocationInRange(voice.range.location, range) { idx = i; stop.pointee = true }
            i += 1
        }
        return idx
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                NikAvatar(mood: "explain").frame(width: 84, height: 110)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#E3E9F2"))).clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 4) {
                    Text(r.mode == "explain" ? "Nik explains" : "Say it like Nik").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text(r.busy.isEmpty ? (voice.speaking ? "Nik is reading…" : "Listen, then try it yourself") : r.busy).font(.system(size: 12.5)).foregroundColor(.secondary)
                }
            }
            Text(r.line).font(.system(size: 17, weight: .medium, design: .serif)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#FFF2B8").opacity(0.55)))
            if !r.meaning.isEmpty { Text(r.meaning).font(.system(size: 13)).foregroundColor(.secondary) }
            if r.mode == "explain" {
                ScrollView { Text(r.explanation).font(.system(size: 15)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading) }
                HStack(spacing: 10) {
                    Button { TutorVoice.shared.speakAuto(r.explanation) } label: { Label("Say it again", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    Button { Task { await r.readMarked() } } label: { Label("How do I say it?", systemImage: "mouth.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                }.controlSize(.large)
                Text("Select anything and press ⌥⌘N, or say “Nik, explain this in Urdu”.").font(.system(size: 11.5)).foregroundColor(.secondary)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    WrapRow(items: r.words.indices.map { String($0) }) { k in
                        let i = Int(k) ?? 0, w = r.words[i]
                        Button { TutorVoice.shared.speak(w.w, locale: r.locale, slow: true) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(w.w).font(.system(size: 14, weight: .semibold))
                                Text(w.say).font(.system(size: 11.5)).opacity(0.8)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .foregroundColor(spoken == i ? .white : .primary)
                            .background(RoundedRectangle(cornerRadius: 10).fill(spoken == i ? Color(hex: "#5B4BD6") : Color.primary.opacity(0.07)))
                        }.buttonStyle(.plain).help(w.meaning)
                    }
                    ForEach(r.tips, id: \.self) { t in Text("• " + t).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
                }
            }
            if let s = r.score { Text("You matched \(s)% of the words").font(.system(size: 13, weight: .semibold)).foregroundColor(s >= 85 ? .green : .orange) }
            if ear.listening { Text(ear.heard.isEmpty ? "Listening…" : ear.heard).font(.system(size: 13)).foregroundColor(.secondary) }
            HStack(spacing: 10) {
                Button { TutorVoice.shared.speak(r.line, locale: r.locale, slow: true) } label: { Label("Slower", systemImage: "tortoise.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                Button { TutorVoice.shared.speak(r.line, locale: r.locale) } label: { Label("Normal", systemImage: "speaker.wave.2.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button { r.myTurn() } label: { Label(ear.listening ? "Done" : "My turn", systemImage: ear.listening ? "stop.fill" : "mic.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Text("Select any line on screen and say “Hey Nik, read this”.").font(.system(size: 11.5)).foregroundColor(.secondary)
            }
        }
        .padding(20).frame(width: 470, height: 600, alignment: .top)
    }
}

// MARK: - Student dashboard: continue the course, what Nik remembers, today, courses, today's outfits

struct StudentHomeCards: View {
    var light: Bool
    @ObservedObject private var brain = NikBrain.shared
    @ObservedObject private var t = LanguageTutor.shared
    @ObservedObject private var study = StudyHub.shared
    private var T: HubTheme { HubTheme(light: light) }
    private var current: NikCourse? { brain.courses.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            continueCard
            HStack(alignment: .top, spacing: 22) {
                rememberCard
                todayCard
                outfitCard
            }
            if brain.courses.count > 0 { coursesCard }
        }
    }

    private var continueCard: some View {
        DashCard(light: light) {
            HStack(alignment: .center, spacing: 24) {
                NikAvatar(mood: "smile").frame(width: 130, height: 172)
                    .background(RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [Color(hex: "#E8EDF4"), Color(hex: "#D9E1EC")], startPoint: .top, endPoint: .bottom)))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 10) {
                    Text(current == nil ? "START LEARNING WITH NIK" : "CONTINUE YOUR COURSE").font(HubFont.p(12, .semibold)).foregroundColor(HubTheme.blue)
                    if let c = current {
                        let l = TutorLanguage.of(c.id), st = NikBrain.step(c), left = max(0, NikBrain.totalLessons - c.lessonsDone)
                        Text("\(l.name) \(t.levels[c.id] ?? "A1") · Step \(st + 1): \(NikBrain.path[st])").font(HubFont.p(22, .semibold)).lineLimit(2)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(T.content)
                                Capsule().fill(ZInk.accentGradient).frame(width: max(10, g.size.width * CGFloat(NikBrain.percent(c)) / 100))
                            }
                        }.frame(height: 10)
                        Text("\(c.lessonsDone) of \(NikBrain.totalLessons) lessons done · \(left) left · about \(left * 12) min to finish").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                        if let tr = c.trouble.first { Text("“Last time you mixed up \(tr). We'll practise it again today.” — Nik").font(HubFont.p(14, .regular)) }
                        HStack(spacing: 14) {
                            DashButton(title: "Resume lesson", icon: "play.fill", light: light) { t.langID = c.id; LearnNav.languages(); NikSays.hello(l) }
                            Text([NikBrain.usualTime(c).map { "Your usual start: \($0)" }, c.last.map { "last studied \($0.formatted(.relative(presentation: .named)))" }].compactMap { $0 }.joined(separator: " · "))
                                .font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive)
                        }
                    } else {
                        Text("Speak a new language with Nik, your senior teacher").font(HubFont.p(22, .semibold))
                        Text("Pick any of 50 languages. Nik remembers what you covered and what's next.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                        DashButton(title: "Choose a language", icon: "globe", light: light) { LearnNav.languages(); brain.showLanguages = true }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var rememberCard: some View {
        DashCard(title: "Nik remembers", light: light) {
            if let c = current {
                let st = NikBrain.step(c)
                row("Covered", c.covered.isEmpty ? "Nothing yet — your first lesson is next" : c.covered.suffix(4).joined(separator: " · "))
                row("Still to do", NikBrain.path[st...].prefix(4).joined(separator: " · "))
                if !c.trouble.isEmpty { row("Keeps tripping you up", c.trouble.prefix(3).joined(separator: " · ")) }
            } else {
                Text(brain.knowsStudent ? "Start a course and Nik keeps track of everything." : "Tell Nik about you and he'll remember it every lesson.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                if !brain.knowsStudent { DashButton(title: "Tell Nik about you", icon: "person.fill", filled: false, light: light) { LearnNav.languages(); brain.showIntake = true } }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var todayCard: some View {
        DashCard(title: "Today", light: light) {
            if let c = current { item("\(TutorLanguage.of(c.id).name) lesson \(c.lessonsDone + 1)", NikBrain.usualTime(c) ?? "any time") }
            let due = t.words.filter { $0.due <= Date() }.count
            if due > 0 { item("Review words", "\(due) due") }
            ForEach(study.deadlines.filter { !$0.done && $0.date >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.date < $1.date }.prefix(3)) { d in
                item(d.title, d.date.formatted(.dateTime.weekday(.wide)))
            }
            if current == nil && due == 0 && study.deadlines.isEmpty { Text("Nothing planned yet.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
        }
        .frame(maxWidth: .infinity)
    }

    private var outfitCard: some View {
        let s = ZuffiSeasons.find(ZuffiSeasons.activeId())
        return DashCard(title: "Dressed for today", light: light) {
            HStack(spacing: 12) {
                LiveBunnyFace(size: 96).frame(width: 110, height: 120).background(RoundedRectangle(cornerRadius: 16).fill(T.content))
                NikAvatar(mood: "smile").frame(width: 92, height: 120).background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#E3E9F2"))).clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text(s.id == "none" ? "Everyday look. Zuffi and Nik dress up on their own for Eid, Christmas, Halloween, your birthday and the seasons." : "\(s.name) look — picked automatically. \(s.says)")
                .font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var coursesCard: some View {
        DashCard(title: "Your courses", light: light) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(brain.courses) { c in
                    let l = TutorLanguage.of(c.id)
                    Button { t.langID = c.id; LearnNav.languages() } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(l.flag) \(l.name) \(t.levels[c.id] ?? "A1")").font(HubFont.p(15, .semibold))
                            GeometryReader { g in
                                ZStack(alignment: .leading) { Capsule().fill(T.content); Capsule().fill(HubTheme.blue).frame(width: max(8, g.size.width * CGFloat(NikBrain.percent(c)) / 100)) }
                            }.frame(height: 8)
                            Text("\(NikBrain.percent(c))% · next: \(NikBrain.path[NikBrain.step(c)])").font(HubFont.p(12, .regular)).foregroundColor(T.inactive).lineLimit(1)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 16).fill(T.content)).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func row(_ head: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(head).font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
            Text(body).font(HubFont.p(13.5, .regular)).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func item(_ a: String, _ b: String) -> some View {
        HStack { Text(a).font(HubFont.p(13.5, .regular)).lineLimit(1); Spacer(); Text(b).font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive) }
            .padding(.horizontal, 12).frame(height: 40).background(RoundedRectangle(cornerRadius: 12).fill(T.content))
    }
}

// MARK: - Chat with Nik (Study tab): a real class — yesterday's recap, today's plan, one topic at a time

struct NikChatMsg: Codable, Identifiable, Hashable { var id = UUID().uuidString; var mine: Bool; var text: String; var at = Date() }

@MainActor
final class NikTutor: ObservableObject {
    static let shared = NikTutor()
    @Published var messages: [NikChatMsg] = TeamStore.load("nik-chat", [NikChatMsg]()) { didSet { TeamStore.save("nik-chat", Array(messages.suffix(300))) } }
    @Published var thinking = false
    @Published var speakReplies: Bool = UserDefaults.standard.object(forKey: "nikSpeaks") as? Bool ?? true { didSet { UserDefaults.standard.set(speakReplies, forKey: "nikSpeaks") } }
    var explainIn: String { NikBrain.shared.profile["own"] ?? LanguageTutor.shared.explainIn }

    /// First visit of the day: Nik recaps last time and gives today's plan, like a teacher opening the class.
    func openClass() async {
        let brain = NikBrain.shared
        guard brain.today == nil, !thinking else { return }
        thinking = true; defer { thinking = false }
        let todayKey = NikBrain.dayKey()
        let lastDay = messages.last { NikBrain.dayKey($0.at) != todayKey }.map { NikBrain.dayKey($0.at) }
        let lastTalk = messages.filter { lastDay != nil && NikBrain.dayKey($0.at) == lastDay! }.suffix(30)
            .map { ($0.mine ? "Student: " : "Nik: ") + $0.text.prefix(400) }.joined(separator: "\n")
        let r = await AIService.shared.oneShot("""
            A new day's class is starting. \(lastTalk.isEmpty ? "This is your first class together." : "Here is what you talked about last time (\(lastDay ?? "")):\n\(lastTalk)")
            Plan today's class for this student from what you remember (their courses, notes, deadlines, what they found hard).
            JSON only: {"lastSummary":"one line: what you covered last time (empty if first class)","plan":["2 to 4 short topic names for today"],
             "say":"what you say now, in \(explainIn): greet them by name, recap last time in 1-2 lines, give today's plan as a numbered list, then start topic 1 with a short explanation and ONE question"}
            """, system: ZuffiVoice.nik + "\n" + brain.generalMemory())
        guard let r, let j = AIService.jsonIn(r) as? [String: Any], let say = j["say"] as? String, !say.isEmpty else { return }
        brain.setToday(summaryOfLast: j["lastSummary"] as? String, lastDay: lastDay, plan: (j["plan"] as? [String]) ?? [])
        messages.append(NikChatMsg(mine: false, text: say))
        if speakReplies { TutorVoice.shared.speak(say, locale: TutorVoice.locale(forName: explainIn)) }
    }

    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        messages.append(NikChatMsg(mine: true, text: t))
        thinking = true; defer { thinking = false }
        let history = messages.suffix(16).dropLast().map { ($0.mine ? "Student: " : "Nik: ") + $0.text.prefix(600) }.joined(separator: "\n")
        let r = await AIService.shared.oneShot("""
            CLASS SO FAR TODAY:
            \(history.isEmpty ? "(just started)" : history)

            The student says: "\(t)"
            Reply as Nik, in the student's language (\(explainIn)) unless they write in another language or you're teaching a language. Follow today's plan. Short turns: explain, example, one question.
            """, system: ZuffiVoice.nik + "\n" + NikBrain.shared.generalMemory()) ?? ""
        let reply = r.trimmingCharacters(in: .whitespacesAndNewlines)
        messages.append(NikChatMsg(mine: false, text: reply.isEmpty ? "I couldn't answer just now — check an AI model is set up (the model button above)." : reply))
        if speakReplies, !reply.isEmpty { TutorVoice.shared.speakAuto(reply, fallback: TutorVoice.locale(forName: explainIn)) }
        if let i = NikBrain.shared.sessions.firstIndex(where: { $0.day == NikBrain.dayKey() }) {
            // keep a running one-line note of today's class for tomorrow's recap
            NikBrain.shared.sessions[i].summary = "Talked about: " + messages.filter { $0.mine && NikBrain.dayKey($0.at) == NikBrain.dayKey() }.suffix(6).map { String($0.text.prefix(40)) }.joined(separator: "; ")
        }
    }

    func newDay() { NikBrain.shared.sessions.removeAll { $0.day == NikBrain.dayKey() }; Task { await openClass() } }
}

struct NikChatView: View {
    var light: Bool
    @ObservedObject private var tutor = NikTutor.shared
    @ObservedObject private var brain = NikBrain.shared
    @ObservedObject private var voice = TutorVoice.shared
    @ObservedObject private var ear = TutorEar.shared
    @ObservedObject private var state = AppState.shared
    @State private var text = ""
    private var T: HubTheme { HubTheme(light: light) }
    private var explainLang: TutorLanguage { TutorLanguage.all.first { $0.name == tutor.explainIn } ?? TutorLanguage.of("en") }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            // Nik
            VStack(alignment: .leading, spacing: 12) {
                NikAvatar(mood: tutor.thinking ? "explain" : "smile").frame(width: 230, height: 300)
                    .background(RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [Color(hex: "#E8EDF4"), Color(hex: "#D3DCEA")], startPoint: .top, endPoint: .bottom)))
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .overlay(alignment: .bottom) {
                        if voice.speaking || tutor.thinking {
                            Text(voice.speaking ? "speaking…" : "thinking…").font(HubFont.p(12)).foregroundColor(.white)
                                .padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(Color.black.opacity(0.45))).padding(.bottom, 10)
                        }
                    }
                Text("Nik").font(HubFont.p(20, .semibold))
                Text("Your teacher · 20 years · every subject and 50 languages").font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive)
                if let plan = brain.today?.plan, !plan.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TODAY'S PLAN").font(HubFont.p(11, .semibold)).foregroundColor(HubTheme.blue)
                        ForEach(Array(plan.enumerated()), id: \.offset) { i, p in Text("\(i + 1). \(p)").font(HubFont.p(13, .regular)).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 16).fill(T.content))
                }
                if let last = brain.lastSession, !last.summary.isEmpty {
                    Text("Last time: \(last.summary)").font(HubFont.p(12, .regular)).foregroundColor(T.inactive).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Nik speaks his answers", isOn: $tutor.speakReplies).toggleStyle(.switch).font(HubFont.p(12.5))
                ProviderMenu(state: state, tint: T.text, big: true)
            }
            .frame(width: 230)

            // the class
            VStack(spacing: 12) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if tutor.messages.isEmpty && !tutor.thinking {
                                Text("Say hi to Nik, or ask anything you're studying.").font(HubFont.p(14, .regular)).foregroundColor(T.inactive).padding(.top, 30)
                            }
                            ForEach(tutor.messages.suffix(80)) { m in bubble(m).id(m.id) }
                            if tutor.thinking { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Nik is thinking…").font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive) }.id("thinking") }
                        }
                        .padding(18)
                    }
                    .onChange(of: tutor.messages.count) { _ in withAnimation { proxy.scrollTo(tutor.messages.last?.id, anchor: .bottom) } }
                    .onAppear { proxy.scrollTo(tutor.messages.last?.id, anchor: .bottom) }
                }
                .frame(minHeight: 460)
                .background(RoundedRectangle(cornerRadius: 22).fill(T.content.opacity(0.6)))
                HStack(spacing: 10) {
                    Button { if ear.listening { ear.stop(); text = ear.heard } else { ear.start(explainLang) } } label: {
                        Image(systemName: ear.listening ? "stop.circle.fill" : "mic.circle.fill").font(.system(size: 34))
                            .foregroundColor(ear.listening ? Color(hex: "#E5534B") : HubTheme.blue)
                    }.buttonStyle(.plain).help("Talk to Nik")
                    ZField(label: "Ask Nik or answer his question…", text: Binding(get: { ear.listening ? ear.heard : text }, set: { text = $0 }), light: light, onSubmit: send)
                    DashButton(title: "Send", icon: "paperplane.fill", light: light, go: send)
                }
                HStack(spacing: 16) {
                    Button { tutor.newDay() } label: { Label("Start today's class again", systemImage: "arrow.clockwise") }.buttonStyle(.plain)
                    Button { brain.showIntake = true } label: { Label("About me", systemImage: "person.crop.circle") }.buttonStyle(.plain)
                    Spacer()
                    if voice.speaking { Button { voice.stop() } label: { Label("Stop talking", systemImage: "stop.fill") }.buttonStyle(.plain) }
                }
                .font(HubFont.p(12.5)).foregroundColor(HubTheme.blue)
            }
        }
        .sheet(isPresented: $brain.showIntake) { NikIntakeSheet(light: light) { brain.showIntake = false; Task { await tutor.openClass() } } }
        .task {
            if !brain.knowsStudent { brain.showIntake = true } else { await tutor.openClass() }
        }
    }

    private func bubble(_ m: NikChatMsg) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if m.mine { Spacer(minLength: 90) }
            VStack(alignment: .leading, spacing: 6) {
                if m.mine { Text(m.text).font(HubFont.p(14.5, .regular)).textSelection(.enabled) }
                else { ChatRichText(text: m.text) }
                if !m.mine {
                    HStack(spacing: 12) {
                        Button { TutorVoice.shared.speakAuto(m.text, fallback: TutorVoice.locale(forName: tutor.explainIn)) } label: { Image(systemName: "speaker.wave.2.fill") }.buttonStyle(.plain).help("Hear Nik say it")
                        Button { ResultExport.copy(m.text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain).help("Copy")
                        Text(m.at.formatted(date: .omitted, time: .shortened)).font(HubFont.p(10.5, .regular))
                    }.font(.system(size: 11)).foregroundColor(T.inactive)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(m.mine ? AnyShapeStyle(HubTheme.blue.opacity(0.22)) : AnyShapeStyle(T.content)))
            if !m.mine { Spacer(minLength: 60) }
        }
    }

    private func send() {
        let s = ear.listening ? ear.heard : text
        ear.stop(); text = ""
        Task { await tutor.send(s) }
    }
}

/// Learn is one page now (Chat with Nik · Study a file · Languages · My progress).
@MainActor
enum LearnNav {
    static func languages() { UserDefaults.standard.set("Languages", forKey: "studyTab"); ZuffiHub.shared.show(.study) }
    static func nik() { UserDefaults.standard.set("Chat with Nik", forKey: "studyTab"); ZuffiHub.shared.show(.study) }
}

/// The front dashboard: your day — how to call Zuffi, messages waiting, what's coming up.
struct YourDayCards: View {
    var light: Bool
    @ObservedObject private var inbox = NotchInbox.shared
    @ObservedObject private var study = StudyHub.shared
    @ObservedObject private var meeting = MeetingHelper.shared
    @ObservedObject private var log = ZuffiHelpLog.shared
    @ObservedObject private var day = DashToday.shared
    @ObservedObject private var archive = ChatArchive.shared
    private var T: HubTheme { HubTheme(light: light) }

    private var soon: [Deadline] {
        Array(study.deadlines.filter { !$0.done && $0.date >= Calendar.current.startOfDay(for: Date()) }.sorted { $0.date < $1.date }.prefix(3))
    }
    private var hello: String {
        let h = Calendar.current.component(.hour, from: Date())
        let first = (ZuffiPlan.shared.profile["name"] ?? "").components(separatedBy: " ").first ?? ""
        return (h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening") + (first.isEmpty ? "" : ", \(first)")
    }
    private var needsLine: String {
        let m = inbox.notes.count, t = day.events.count + day.tasks.count + soon.count
        if m + t == 0 { return "Nothing needs you right now. Select text and hold Z whenever you want help." }
        var parts: [String] = []
        if m > 0 { parts.append("\(m) message\(m == 1 ? "" : "s") to answer") }
        if t > 0 { parts.append("\(t) thing\(t == 1 ? "" : "s") today") }
        return "\(m + t) thing\(m + t == 1 ? " needs" : "s need") you: " + parts.joined(separator: " and ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashCard(light: light) {
                HStack(spacing: 20) {
                    RealAuroraHead(width: 80, mood: "idle")
                    VStack(alignment: .leading, spacing: 5) {
                        Text(hello).font(HubFont.p(22, .semibold))
                        Text(needsLine).font(HubFont.p(14, .regular)).foregroundColor(T.inactive)
                    }
                    Spacer(minLength: 10)
                    stat(log.today.count, "helps today")
                    stat(log.today.filter { $0.kind == "Reply written" }.count, "replies written")
                }
            }
            HStack(alignment: .top, spacing: 22) {
                DashCard(title: "Waiting for you", light: light) {
                    if inbox.notes.isEmpty { Text("No new messages. WhatsApp and email land here and in the notch.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
                    ForEach(inbox.notes.prefix(4)) { n in
                        HStack(spacing: 12) {
                            Image(systemName: n.icon).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(RoundedRectangle(cornerRadius: 10).fill(n.action == "whatsapp" ? Color(hex: "#25D366") : Color(hex: "#5B8CFF")))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(n.head).font(HubFont.p(13.5, .semibold)).lineLimit(1)
                                Text(n.body).font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            small("Explain") { Task { await ZuffiAsk.shared.act("explain", n.body) } }
                            small("Reply", filled: true) { Task { await ZuffiAsk.shared.act("reply", n.body) } }
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(light ? 0.05 : 0.25)))
                    }
                }
                .frame(maxWidth: .infinity)
                DashCard(title: "Today", light: light) {
                    if day.events.isEmpty && day.tasks.isEmpty && soon.isEmpty {
                        Text("Nothing planned. Say “Hey Zuffi, remind me…” to add something.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                    }
                    ForEach(day.events.prefix(4)) { e in row(e.title, e.allDay ? "all day" : e.start.formatted(date: .omitted, time: .shortened)) }
                    ForEach(day.tasks.prefix(4)) { r in row(r.title, r.due.map { $0.formatted(date: .omitted, time: .shortened) } ?? "to do") }
                    ForEach(soon) { d in row(d.title, d.date.formatted(.dateTime.weekday(.wide)), warn: true) }
                }
                .frame(maxWidth: .infinity)
            }
            DashCard(title: "Recent help", light: light) {
                if log.items.isEmpty {
                    Text("What Zuffi explains, translates or writes for you shows up here. Only on this Mac.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(log.items.prefix(6)) { i in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(i.kind) · \(i.at.formatted(date: .omitted, time: .shortened))").font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
                                Text(i.text).font(HubFont.p(13, .regular)).lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
                            .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(light ? 0.05 : 0.25)))
                            .contextMenu { Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(i.text, forType: .string) } }
                        }
                    }
                }
            }
            DashCard(title: "Recent chats", light: light) {
                let past = Array(archive.chats.prefix(6))
                if past.isEmpty && AppState.shared.chatHistory.isEmpty {
                    Text("Your chats with Zuffi are kept here. Click one to open it in the chat.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 12) {
                    if let now = AppState.shared.chatHistory.first(where: { $0.role == .user }) {
                        chatTile("Open now", now.content) { ZuffiChat.shared.open() }
                    }
                    ForEach(past) { c in
                        chatTile(c.date.formatted(date: .abbreviated, time: .shortened), c.title) { ZuffiChat.shared.openPast(c) }
                    }
                }
                HStack {
                    Spacer()
                    small("All chats") { ZuffiChat.shared.showHistory = true; ZuffiChat.shared.open() }
                    small("New chat", filled: true) { AppState.shared.newChat(); ZuffiChat.shared.open() }
                }
            }
            DashCard(title: "How to ask", light: light) {
                HStack(spacing: 22) {
                    tip("Hold Z", "talk, let go")
                    tip("Select text", "Explain · Translate · Reply")
                    tip("“Hey Zuffi”", "when the mic is on")
                    Spacer()
                    DashButton(title: meeting.on ? "Meeting helper is on" : "Meeting helper", icon: "person.2.wave.2.fill", filled: false, light: light) { meeting.toggle() }
                }
            }
        }
        .task { await day.refresh() }
    }
    private func chatTile(_ top: String, _ title: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 10)).foregroundColor(Color(hex: "#B79CFF"))
                    Text(top).font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
                }
                Text(title).font(HubFont.p(13, .regular)).foregroundColor(T.text).lineLimit(2).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(light ? 0.05 : 0.25)))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help("Open this chat")
    }
    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(n)").font(HubFont.p(26, .semibold))
            Text(label).font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
        }.frame(minWidth: 70)
    }
    private func row(_ a: String, _ b: String, warn: Bool = false) -> some View {
        HStack {
            Text(a).font(HubFont.p(13.5, .regular)).lineLimit(1)
            Spacer()
            Text(b).font(HubFont.p(12.5, .regular)).foregroundColor(warn ? Color(hex: "#F5B963") : T.inactive)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(light ? 0.05 : 0.25)))
    }
    private func small(_ t: String, filled: Bool = false, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Text(t).font(HubFont.p(12, .semibold)).foregroundColor(filled ? Color(hex: "#141218") : T.text)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(filled ? Color(hex: "#F9FAFB") : Color.white.opacity(0.08)))
        }.buttonStyle(.plain)
    }
    private func tip(_ a: String, _ b: String) -> some View {
        HStack(spacing: 8) { Text(a).font(HubFont.p(13.5, .semibold)); Text(b).font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
    }
}
