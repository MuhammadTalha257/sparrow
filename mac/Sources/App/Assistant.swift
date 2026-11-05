import Foundation
import AppKit
import SwiftUI
import AVFoundation
import Speech
import NaturalLanguage
import ApplicationServices
import CoreLocation
import CoreAudio
import AudioToolbox

// MARK: - Settings keys (UserDefaults)

enum AssistantPrefs {
    static let voiceGender     = "voiceGender"      // "female" | "male"
    static let voiceId         = "voiceId"          // AVSpeechSynthesisVoice.identifier, "" = best match
    static let voiceRate       = "voiceRate"        // 0.35 … 0.65
    static let speakReplies    = "speakReplies"     // Bool
    static let wakeWord        = "wakeWordEnabled"  // Bool
    static let greetEnabled    = "greetEnabled"     // Bool
    static let greetWeather    = "greetWeather"     // Bool
    static let userName        = "userName"         // String, "" = first name of the Mac account
    static let weatherCity     = "weatherCity"      // String, "" = automatic
    static let readNotes       = "readNotifications"// Bool

    static func registerDefaults() {
        // The mic is never on by itself any more: one time, switch the old always-listening "Zuffi…" off.
        if !UserDefaults.standard.bool(forKey: "aiVoiceV1") {          // her AI voice is the default now
            UserDefaults.standard.set(true, forKey: "aiVoiceV1")
            UserDefaults.standard.set("ai", forKey: "voiceEngine")
        }
        if !UserDefaults.standard.bool(forKey: "micOffByDefaultV1") {
            UserDefaults.standard.set(true, forKey: "micOffByDefaultV1")
            UserDefaults.standard.set(false, forKey: wakeWord)
        }
        UserDefaults.standard.register(defaults: [
            voiceGender: "female", voiceId: "", voiceRate: 0.5, speakReplies: true,
            wakeWord: false, greetEnabled: true, greetWeather: true, userName: "",
            weatherCity: "", readNotes: false,
        ])
    }

    static var displayName: String {
        let custom = (UserDefaults.standard.string(forKey: userName) ?? "").trimmingCharacters(in: .whitespaces)
        return custom          // only the name you gave Zuffi (never borrowed from the Mac's user account)
    }
}

// MARK: - Voice (speaking + listening)

@MainActor
final class VoiceEngine: NSObject, ObservableObject {
    static let shared = VoiceEngine()

    @Published private(set) var isListening = false
    @Published private(set) var heard = ""
    @Published private(set) var status = ""

    private let synth = AVSpeechSynthesizer()
    private var recognizer = SFSpeechRecognizer(locale: Locale(identifier: VoiceEngine.listenLocaleID))
    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var restartTimer: Timer?
    private var oneShot = false          // mic button: no wake word needed
    @Published private(set) var speaking = false { didSet {
        Aurora3DRig.liveSpeaking = speaking
        if speaking != oldValue { speakingSince = speaking ? Date() : .distantFuture }
        // In a conversation she keeps one ear open while she talks, so you can cut in (like ChatGPT voice).
        if speaking, !oldValue, conversation {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { MainActor.assumeIsolated { VoiceEngine.shared.startBargeIn() } }
        }
        if !speaking, oldValue, bargeListening { bargeListening = false; pauseRecognition() }
    } }
    private var speakingSince = Date.distantFuture
    /// When the current recognition session last (re)started — a session that goes quiet for too long is restarted.
    private var listenStartedAt = Date.distantPast
    private var resumeAfterSpeech = false

    private var failures = 0
    /// Each listening session gets a number; callbacks from older (cancelled) sessions are ignored.
    private var generation = 0

    override init() {
        super.init()
        synth.delegate = self
        // Microphone changed (AirPods connected, etc.) → restart listening cleanly.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { VoiceEngine.shared.restartIfWanted(after: 0.8) }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { VoiceEngine.shared.restartIfWanted(after: 2) }
        }
        // Watchdog: if "Zuffi…" listening should be on but isn't (startup race, mic busy,
        // recogniser not ready yet…), start it again. Cheap — runs every 4 seconds.
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated { VoiceEngine.shared.watchdog() }
        }
    }

    private var lastAttempt = Date.distantPast

    fileprivate func watchdog() {
        // Never stay deaf because "speaking" got stuck (a voice that failed or never reported it finished).
        if speaking, Date().timeIntervalSince(speakingSince) > 25, !synth.isSpeaking, !LiveSession.shared.active {
            appendAppLog("voice.log", "watchdog: speaking flag stuck for \(Int(Date().timeIntervalSince(speakingSince)))s — clearing it")
            NativeSpeech.shared.stop()
            neuralTurn += 1
            resumeAfterSpeech = true
            speechFinished()
        }
        // A listening session that silently stalled (no restart for > 75 s): start a fresh one.
        if isListening, !oneShot, !meetingMode, Date().timeIntervalSince(listenStartedAt) > 75, !LiveSession.shared.active {
            appendAppLog("voice.log", "watchdog: listening stalled — restarting")
            startRecognition()
            return
        }
        guard UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord), Self.micOn,
              !isListening, !speaking, !oneShot, !LiveSession.shared.active,
              Date().timeIntervalSince(lastAttempt) > 3.5 else { return }
        let speechOK = SFSpeechRecognizer.authorizationStatus() == .authorized
        let micOK = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        guard speechOK && micOK else {
            // Not allowed yet — ask once (shows the macOS prompts), then wait for the person.
            if SFSpeechRecognizer.authorizationStatus() == .notDetermined
                || AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                lastAttempt = Date().addingTimeInterval(30)
                setWakeWord(true)
            } else {
                status = "Zuffi needs Microphone and Speech Recognition: System Settings → Privacy & Security."
            }
            return
        }
        lastAttempt = Date()
        appendAppLog("voice.log", "watchdog: starting \"Zuffi…\" listening")
        startRecognition()
    }

    /// A live conversation owns the microphone and speaker while it runs.
    func suspendForLive() {
        stopSpeaking(); speaking = false; resumeAfterSpeech = false; listenAfterSpeech = false
        stopRecognition()
        status = "Listening…"
    }
    private var liveEndedAt = Date.distantPast
    func resumeAfterLive() {
        status = ""
        oneShot = false
        listenAfterSpeech = false; resumeAfterSpeech = false
        liveEndedAt = Date()
        if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { VoiceEngine.shared.startRecognition() } }
        }
    }

    func restartIfWanted(after delay: TimeInterval) {
        guard UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord), !speaking, !LiveSession.shared.active else { return }
        pauseRecognition()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord), !LiveSession.shared.active { VoiceEngine.shared.startRecognition() }
        }
    }

    // MARK: Languages

    /// What Zuffi listens for. English (India) understands Roman Urdu / Hindi / Punjabi mixed with English best.
    static var listenLocaleID: String {
        let s = UserDefaults.standard.string(forKey: "listenLocale") ?? ""
        return s.isEmpty ? "en-US" : s
    }

    func setListenLocale(_ id: String) {
        guard id != Self.listenLocaleID || recognizer?.locale.identifier != id else { return }
        let wanted = SFSpeechRecognizer(locale: Locale(identifier: id))
        // Not every language can be recognised on every Mac — fall back sensibly.
        let pick = (wanted?.isAvailable ?? false) ? wanted : (id.hasPrefix("en") ? nil : SFSpeechRecognizer(locale: Locale(identifier: "en-IN")))
        guard let pick else { return }
        UserDefaults.standard.set(pick.locale.identifier, forKey: "listenLocale")
        recognizer = pick
        appendAppLog("voice.log", "listening language: \(pick.locale.identifier) (asked \(id))")
        restartIfWanted(after: 0.3)
    }

    static var supportedListenLocales: [String] {
        SFSpeechRecognizer.supportedLocales().map { $0.identifier }.sorted()
    }

    // MARK: Speaking

    static func availableVoices(gender: String) -> [AVSpeechSynthesisVoice] {
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let wanted: AVSpeechSynthesisVoiceGender = gender == "male" ? .male : .female
        let all = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(lang) || $0.language.hasPrefix("en") }
            .filter { !$0.identifier.contains("eloquence") && !$0.identifier.contains("speech.synthesis.voice") }
        let matching = all.filter { $0.gender == wanted }
        let list = matching.isEmpty ? all : matching
        // Natural-sounding voices first (Premium > Enhanced), then well-known pleasant ones.
        let favourites = ["Zoe", "Ava", "Serena", "Samantha", "Allison", "Susan", "Kate", "Karen", "Moira",
                          "Evan", "Nathan", "Tom", "Daniel", "Oliver", "Alex", "Aaron", "Arthur"]
        func rank(_ v: AVSpeechSynthesisVoice) -> Int {
            let q = v.quality == .premium ? 0 : (v.quality == .enhanced ? 100 : 200)
            let f = favourites.firstIndex(where: { v.name.hasPrefix($0) }) ?? 50
            let local = v.language == Locale.current.identifier.replacingOccurrences(of: "_", with: "-") ? 0 : 1
            return q + f * 2 + local
        }
        return list.sorted { rank($0) < rank($1) }
    }

    /// True when only the robotic "compact" voices are installed.
    static var onlyBasicVoices: Bool {
        !AVSpeechSynthesisVoice.speechVoices().contains { $0.language.hasPrefix("en") && $0.quality != .default }
    }

    private func currentVoice() -> AVSpeechSynthesisVoice? {
        let ud = UserDefaults.standard
        if let id = ud.string(forKey: AssistantPrefs.voiceId), !id.isEmpty,
           let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return Self.availableVoices(gender: ud.string(forKey: AssistantPrefs.voiceGender) ?? "female").first
    }

    func speak(_ text: String) {
        // Don't read emoji names out loud ("alarm clock…")
        let noEmoji = String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x2000)) && $0.value != 0xFE0F
        }))
        var clean = noEmoji.replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: #"(?m)^\s*(?:[-*]|\d+[.)])\s+"#, with: "", options: .regularExpression)     // list marks aren't read out
            .replacingOccurrences(of: #"\s+[-–—]\s+"#, with: ", ", options: .regularExpression)                      // " - " is a pause, not "dash"
            .replacingOccurrences(of: #"[*#_`]+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"https?://\S+"#, with: "the link", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // A long written answer: say the first part, the rest stays in the chat (like a real conversation).
        if clean.count > 360 {
            var head = ""
            clean.enumerateSubstrings(in: clean.startIndex..<clean.endIndex, options: .bySentences) { sub, _, _, stop in
                guard let sub else { return }
                if head.count + sub.count > 300, !head.isEmpty { stop = true; return }
                head += sub
            }
            if !head.isEmpty, head.count < clean.count - 40 { clean = head.trimmingCharacters(in: .whitespacesAndNewlines) + " The rest is in the chat." }
        }
        guard !clean.isEmpty else { return }
        // Only ever one voice: the live conversation is already talking, so don't talk over it.
        if LiveSession.shared.active { appendAppLog("voice.log", "skip speak (live voice is on): \(clean.prefix(40))"); return }
        if TutorVoice.shared.speaking { TutorVoice.shared.stop() }
        lastSpoken = clean; lastSpokenAt = Date()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        // Fish Audio (optional, online, your key): the most natural voice, with real laughs, sobs, anger and shouting.
        if FishVoice.usable {
            if isListening { resumeAfterSpeech = true; pauseRecognition() }
            speaking = true
            neuralTurn += 1
            let turn = neuralTurn
            let text = String(clean.prefix(1500))
            Task { @MainActor in
                let ok = await FishVoice.shared.say(text) {
                    if turn == VoiceEngine.shared.neuralTurn { VoiceEngine.shared.neuralEnded() }
                }
                guard turn == self.neuralTurn else { return }
                if !ok { self.speakBuiltIn(clean) }
            }
            return
        }
        // The voice follows the AI picked in the chat bar (local model → her own offline voice, everywhere)
        let pick = VoicePick.current
        if pick == .local { speakBuiltIn(clean); return }
        // OpenAI / Gemini picked: that company's voice, every language. Urdu, Hindi… with Groq: your OpenAI/Gemini voice if you have one.
        if pick == .openai || pick == .gemini || (!GroqVoice.fits(clean) && WorldVoice.usable) {
            let prefer = pick == .gemini ? "gemini" : pick == .openai ? "openai" : ""
            if isListening { resumeAfterSpeech = true; pauseRecognition() }
            speaking = true
            neuralTurn += 1
            let turn = neuralTurn
            let text = String(clean.prefix(1500))
            Task { @MainActor in
                let ok = await WorldVoice.shared.say(text, prefer: prefer) {
                    if turn == VoiceEngine.shared.neuralTurn { VoiceEngine.shared.neuralEnded() }
                }
                guard turn == self.neuralTurn else { return }
                if !ok { self.speakBuiltIn(clean) }
            }
            return
        }
        // Her AI voice (Groq): the most human, starts in a fraction of a second. No internet / no key → her offline voice.
        if GroqVoice.usable, GroqVoice.fits(clean) {
            if isListening { resumeAfterSpeech = true; pauseRecognition() }
            speaking = true
            neuralTurn += 1
            let turn = neuralTurn
            let text = String(clean.prefix(1500))
            Task { @MainActor in
                let ok = await GroqVoice.shared.say(text) {
                    if turn == VoiceEngine.shared.neuralTurn { VoiceEngine.shared.neuralEnded() }
                }
                guard turn == self.neuralTurn else { return }
                if !ok { self.speakBuiltIn(clean) }
            }
            return
        }
        // Voicebox (if you use it): your own cloned or preset voice, offline, 23 languages.
        if VoiceboxVoice.enabled {
            if isListening { resumeAfterSpeech = true; pauseRecognition() }
            speaking = true
            neuralTurn += 1
            let turn = neuralTurn
            let text = String(clean.prefix(1500))
            Task { @MainActor in
                let ok = await VoiceboxVoice.shared.say(text) {
                    if turn == VoiceEngine.shared.neuralTurn { VoiceEngine.shared.neuralEnded() }
                }
                guard turn == self.neuralTurn else { return }
                if !ok { self.speakBuiltIn(clean) }
            }
            return
        }
        speakBuiltIn(clean)
    }

    /// Try the offline voice (Settings), whatever voice is picked for everyday use.
    func speakOffline(_ text: String) {
        stopSpeaking(); lastSpoken = text; lastSpokenAt = Date(); speakBuiltIn(text)
    }

    /// A language her own voices don't speak (Spanish, French, Arabic, Chinese…): the Mac's voice for that language.
    static func otherLanguage(_ text: String) -> String? {
        let lang = UserDefaults.standard.string(forKey: "sparrowLang") ?? "en"
        let m = NativeSpeech.model(for: text, lang: lang)
        if m.hasPrefix("st-") { return nil }          // her own voice speaks this language
        if m != "kokoro" {                       // Urdu / Hindi / Punjabi / Roman Urdu have their own voices — except Arabic script that isn't Urdu
            if m == "urd" {
                let r = NLLanguageRecognizer(); r.processString(text)
                if let d = r.dominantLanguage, d == .arabic || d == .persian { return d.rawValue }
            }
            return nil
        }
        guard text.count >= 12 else { return nil }
        let r = NLLanguageRecognizer(); r.processString(text)
        guard let d = r.dominantLanguage, d != .english, d != .undetermined,
              (r.languageHypotheses(withMaximum: 1)[d] ?? 0) > 0.6 else { return nil }
        return d.rawValue
    }

    private func speakBuiltIn(_ clean: String) {
        // Another language: the Mac's own voice for it (her English voices would say it with the wrong sounds).
        if Self.otherLanguage(clean) != nil { appleSpeak(clean); return }
        // Zuffi's built-in natural voice (fast, native). Falls back to Apple's voice instantly if it can't.
        if UserDefaults.standard.object(forKey: "neuralVoice") as? Bool ?? true, NativeSpeech.shared.isAvailable {
            if isListening { resumeAfterSpeech = true; pauseRecognition() }
            speaking = true
            neuralTurn += 1
            let turn = neuralTurn
            // The whole answer goes to her voice at once: it speaks the first few words almost immediately and prepares
            // the next sentences WHILE she talks (no waiting between sentences, no gap at the start).
            let piece = String(clean.prefix(1600))
            Task { @MainActor in
                let ok = await NativeSpeech.shared.say(ZuffiExpress.spoken(piece)) {
                    let v = VoiceEngine.shared
                    guard turn == v.neuralTurn else { return }
                    v.neuralEnded()
                }
                guard turn == self.neuralTurn else { return }
                if !ok { self.appleSpeak(piece); return }
                self.lipText = piece
                self.audioStartedAt = Date()          // her lips follow the words from here
                ZuffiExpress.face(for: piece)          // and her face follows the feelings in it
                let secs = 8.0 + Double(piece.count) / 9.0      // safety net: never leave the mic paused
                DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                    MainActor.assumeIsolated { VoiceEngine.shared.neuralTimeout(turn) }
                }
            }
            return
        }
        appleSpeak(clean)
    }

    /// Splits an answer into short spoken pieces (whole sentences, ~180 letters at most).
    static func chunks(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { s, _, _, _ in
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
            if cur.isEmpty { cur = s }
            else if cur.count + s.count < (out.isEmpty ? 90 : 180) { cur += " " + s }
            else { out.append(cur); cur = s }
        }
        if !cur.isEmpty { out.append(cur) }
        return out.isEmpty ? [text] : out
    }
    private var chunkSerial = 0
    private func sayChunk(_ pieces: [String], _ i: Int, turn: Int) {
        guard i < pieces.count, turn == neuralTurn else { return }
        let piece = pieces[i]
        let text = ZuffiExpress.spoken(piece)
        chunkSerial += 1
        let serial = chunkSerial
        Task { @MainActor in
            let ok = await NativeSpeech.shared.say(text) {
                let v = VoiceEngine.shared
                guard turn == v.neuralTurn else { return }
                if i + 1 < pieces.count { v.sayChunk(pieces, i + 1, turn: turn) } else { v.neuralEnded() }
            }
            guard turn == self.neuralTurn else { return }
            if !ok { self.appleSpeak(pieces[i...].joined(separator: " ")); return }
            self.lipText = piece
            self.audioStartedAt = Date()          // Aurora's lips follow the words from here
            ZuffiExpress.face(for: piece)          // and her face follows the feeling
            // Safety net: never leave the microphone paused.
            let secs = 5.0 + Double(text.count) / 9.0
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                MainActor.assumeIsolated { let v = VoiceEngine.shared; if v.chunkSerial == serial { v.neuralTimeout(turn) } }
            }
        }
    }

    private var neuralTurn = 0
    func neuralEnded() { neuralTurn += 1; speechFinished() }
    fileprivate func neuralTimeout(_ turn: Int) { if turn == neuralTurn, speaking { neuralEnded() } }

    private func appleSpeak(_ clean: String) {
        audioStartedAt = Date().addingTimeInterval(0.15)
        lipText = clean
        ZuffiExpress.face(for: clean)
        let feel = ZuffiExpress.mood(clean)
        let u = Self.naturalUtterance(ZuffiExpress.spoken(String(clean.prefix(1200))))
        var voice = currentVoice()
        if let code = Self.otherLanguage(clean) {
            let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(code) }
            let best = all.sorted { ($0.quality.rawValue, $0.gender == .female ? 1 : 0) > ($1.quality.rawValue, $1.gender == .female ? 1 : 0) }.first
            if let best { voice = best } else if let v = AVSpeechSynthesisVoice(language: code) { voice = v }
        }
        u.voice = voice
        let rate = UserDefaults.standard.double(forKey: AssistantPrefs.voiceRate)
        // Basic voices sound less robotic a touch slower; premium ones at a natural pace.
        let base = Float(rate == 0 ? 0.5 : rate)
        u.rate = voice?.quality == .default ? base * 0.94 : base
        // a light lift for her bunny voice — a big one sounds like a cartoon, not a person
        u.pitchMultiplier = (UserDefaults.standard.object(forKey: "bunnyVoice") as? Bool ?? true) ? (voice?.quality == .default ? 1.18 : 1.1) : (voice?.gender == .female ? 1.04 : 0.98)
        u.pitchMultiplier = min(2, u.pitchMultiplier * ZuffiExpress.pitch(feel))
        u.rate = u.rate * Float(ZuffiExpress.speed(feel))
        u.volume = 0.95
        u.preUtteranceDelay = 0.05
        u.prefersAssistiveTechnologySettings = false
        // Don't listen to ourselves while talking
        if isListening { resumeAfterSpeech = true; pauseRecognition() }
        speaking = true
        synth.speak(u)
    }

    func stopSpeaking() {
        synth.stopSpeaking(at: .immediate)
        VoiceboxVoice.shared.stop()
        FishVoice.shared.stop()
        GroqVoice.shared.stop(); WorldVoice.shared.stop()
        if speaking, neuralTurn > 0 { NativeSpeech.shared.stop(); neuralEnded() }
    }

    /// Short natural pauses between sentences and after "Talha," — sounds far less robotic.
    static func naturalUtterance(_ text: String) -> AVSpeechUtterance {
        let esc = text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        var body = esc.replacingOccurrences(of: #"([.!?])\s+"#, with: "$1<break time=\"280ms\"/> ", options: .regularExpression)
        body = body.replacingOccurrences(of: #"\n+"#, with: "<break time=\"320ms\"/> ", options: .regularExpression)
        body = body.replacingOccurrences(of: #":\s+"#, with: ":<break time=\"160ms\"/> ", options: .regularExpression)
        if let u = AVSpeechUtterance(ssmlRepresentation: "<speak>\(body)</speak>") { return u }
        return AVSpeechUtterance(string: text)
    }

    /// Meeting notes: everything heard is written down (only "Zuffi, stop…" is treated as a command).
    var meetingMode = false

    /// Set before speaking a question; Zuffi listens again as soon as it finishes.
    var listenAfterSpeech = false

    fileprivate func speechFinished() {
        speaking = false
        if conversation { listenAfterSpeech = false; resumeAfterSpeech = false; if takeWaitingNote() { return }; conversationNext(); return }
        if !waitingNotes.isEmpty, !listenAfterSpeech { _ = takeWaitingNote() }
        if listenAfterSpeech {
            listenAfterSpeech = false
            resumeAfterSpeech = false
            // (not right after a live conversation ended — then it's back to "Zuffi…" listening)
            if Date().timeIntervalSince(liveEndedAt) > 4, !LiveSession.shared.active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { VoiceEngine.shared.listenOnce(byButton: false) } }
                return
            }
        }
        if resumeAfterSpeech {
            resumeAfterSpeech = false
            if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) { startRecognition() }
        }
    }

    // MARK: Listening

    /// Always-on "Zuffi, …" listening (Settings toggle).
    func setWakeWord(_ on: Bool) {
        if on, ZuffiPlan.shared.isLocked { stopRecognition(); status = ""; return }
        if on { requestPermissions { ok in if ok { self.startRecognition() } } }
        else { stopRecognition(); status = "" }
    }

    // MARK: Voice level (end of speech + orb)
    @Published private(set) var level: Float = 0
    private var noiseFloor: Float = 0.01
    private var lastLoudAt = Date.distantPast
    private var extraWait: TimeInterval = 0

    func noteLevel(_ rms: Float) {
        noiseFloor = rms < noiseFloor ? noiseFloor * 0.9 + rms * 0.1 : noiseFloor * 0.999 + rms * 0.001
        if rms > max(0.012, noiseFloor * 3) { lastLoudAt = Date() }
        let l = min(1, rms * 8)
        if abs(l - level) > 0.04 { level = level * 0.6 + l * 0.4 }
    }

    /// Called when the pause timer fires: if you're still making sound (a long sentence, a breath), wait a little more.
    fileprivate func maybeFinish() {
        if Date().timeIntervalSince(lastLoudAt) < 0.35, extraWait < 6, !heard.isEmpty {
            extraWait += 0.4
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
                MainActor.assumeIsolated { VoiceEngine.shared.maybeFinish() }
            }
            return
        }
        extraWait = 0
        finishUtterance()
    }

    // MARK: Hold-to-talk (right ⌥ Option)
    private(set) var pushToTalk = false

    func pushToTalkDown(forScreen: Bool = false) {
        guard !pushToTalk else { return }
        if ZuffiPlan.shared.blocked(speak: true) { return }
        if LiveSession.shared.active { return }          // already talking: just speak
        if !forScreen, LiveSession.shared.usable, !meetingMode { LiveSession.shared.start(byButton: true); return }
        if speaking { stopSpeaking(); speaking = false; resumeAfterSpeech = false }
        pushToTalk = true
        SoundEngine.shared.play("question")
        NotificationCenter.default.post(name: .hookReveal, object: nil)
        requestPermissions { ok in
            guard ok, self.pushToTalk else { return }
            self.oneShot = true
            self.startRecognition()
            self.status = "Listening… let go of ⌥ when you're done"
        }
    }

    func pushToTalkUp() {
        guard pushToTalk else { return }
        pushToTalk = false
        pttEndedAt = Date()
        // a moment for the last word to arrive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainActor.assumeIsolated { VoiceEngine.shared.finishUtterance() }
        }
    }

    /// Normal (non-live) listening for one command — used when the live voice can't start.
    /// Live talk couldn't start (no internet): say so out loud, then listen for the command offline.
    func offlineHello() {
        liveEndedAt = .distantPast                 // so it really listens after speaking
        listenAfterSpeech = true
        let first = AssistantPrefs.displayName.components(separatedBy: " ").first ?? ""
        speak(first.isEmpty ? "Hey! Yes?" : "Hey \(first)! What's up?")
    }

    func listenOffline() {
        SoundEngine.shared.play("question")
        NotificationCenter.default.post(name: .hookReveal, object: nil)
        requestPermissions { ok in
            guard ok else { return }
            self.oneShot = true
            self.startRecognition()
            self.status = "Listening…"
        }
    }

    /// Mic button: listen for one command, no wake word needed.
    func listenOnce(byButton: Bool = true, forScreen: Bool = false) {
        if ZuffiPlan.shared.blocked(speak: true) { return }
        // The mic button always wins: stop talking and listen right now.
        if speaking { stopSpeaking(); speaking = false; resumeAfterSpeech = false }
        // Pressing a mic / Talk button means "listen" — so switch the mic back on if it was off.
        if !Self.micOn { setMic(true) }
        if !forScreen, LiveSession.shared.usable, !meetingMode { LiveSession.shared.start(byButton: byButton); return }
        requestPermissions { ok in
            guard ok else { return }
            self.oneShot = true
            self.startRecognition()
            self.status = "Listening…"
        }
    }

    private func requestPermissions(_ done: @escaping @MainActor @Sendable (Bool) -> Void) {
        Self.askSpeechAuth { granted in
            Task { @MainActor in
                guard granted else {
                    self.status = "Allow Speech Recognition for Zuffi in System Settings → Privacy & Security."
                    done(false); return
                }
                Self.askMicAuth { mic in
                    Task { @MainActor in
                        if !mic { self.status = "Allow the Microphone for Zuffi in System Settings → Privacy & Security." }
                        done(mic)
                    }
                }
            }
        }
    }

    // Callbacks from these Apple APIs arrive on background threads, so they are
    // created in nonisolated functions and hop back to the main actor themselves.
    nonisolated private static func askSpeechAuth(_ cb: @escaping @Sendable (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { cb($0 == .authorized) }
    }
    nonisolated private static func askMicAuth(_ cb: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { cb($0) }
    }
    nonisolated private static func installTap(_ node: AVAudioInputNode, _ req: SFSpeechAudioBufferRecognitionRequest) {
        MicPick.apply(node)
        let fmt = node.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { return }      // mic busy / not allowed: don't crash
        nonisolated(unsafe) let r = req
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, _ in
            r.append(buffer)
            // How loud it is right now — used to know when you've really stopped talking, and for the orb.
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            var sum: Float = 0
            var i = 0
            while i < n { sum += ch[i] * ch[i]; i += 4 }
            let rms = (sum / Float(max(1, n / 4))).squareRoot()
            Task { @MainActor in VoiceEngine.shared.noteLevel(rms) }
        }
    }
    nonisolated private static func startTask(_ rec: SFSpeechRecognizer, _ req: SFSpeechAudioBufferRecognitionRequest,
                                              _ cb: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        rec.recognitionTask(with: req) { result, error in
            cb(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }

    /// The mic switch (on by default; stays off only when you turn it off).
    static var micOn: Bool { UserDefaults.standard.object(forKey: "micOn") as? Bool ?? true }
    static var cameraOn: Bool { UserDefaults.standard.object(forKey: "cameraOn") as? Bool ?? true }

    /// Mirrors the switch so every mic button redraws the moment it changes.
    @Published var micEnabled: Bool = VoiceEngine.micOn
    /// What was just heard / said / missed — the notch shows it so you always see what happened.
    @Published var lastHeard = "" { didSet { if !lastHeard.isEmpty { conversationHeard() } } }
    var lastHeardAt = Date.distantPast
    @Published var lastSpoken = ""
    var lastSpokenAt = Date.distantPast
    @Published var missedAt = Date.distantPast { didSet { conversationMissed() } }

    // MARK: Reminders while you're talking: never cut you off
    private var waitingNotes: [String] = []
    /// A reminder or alert to say out loud. While you're in a conversation (or she's speaking / listening to you)
    /// it waits for the end of her current sentence instead of cutting in.
    func announce(_ text: String) {
        if conversation || speaking || (isListening && (oneShot || pushToTalk)) {
            if !waitingNotes.contains(text) { waitingNotes.append(text) }
            if !conversation && !speaking { retryNotes(after: 4) }          // only listening for a moment: try again soon
            return
        }
        speak(text)
    }
    private func retryNotes(after d: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + d) {
            MainActor.assumeIsolated {
                let v = VoiceEngine.shared
                guard !v.waitingNotes.isEmpty, !v.conversation, !v.speaking else { return }
                if v.isListening && (v.oneShot || v.pushToTalk) { v.retryNotes(after: 4); return }
                v.speak(v.waitingNotes.removeFirst())
            }
        }
    }
    /// After her turn: a waiting reminder is said first ("By the way — …"), then the conversation carries on.
    private func takeWaitingNote() -> Bool {
        guard !waitingNotes.isEmpty else { return false }
        let t = waitingNotes.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { MainActor.assumeIsolated { VoiceEngine.shared.speak("By the way — " + t) } }
        return true
    }

    // MARK: Cutting in while she talks
    private(set) var bargeListening = false
    private var bargeSkip = 0                 // words at the start of the transcript that were her own voice
    /// What she had said when you cut in — so "carry on" continues from there, and a new question gets a new answer.
    var interruptedNote: String?

    fileprivate func startBargeIn() {
        guard conversation, speaking, !isListening, !bargeListening, Self.micOn, !micLent else { return }
        // AirPods/Bluetooth with no Mac mic to use instead: opening their mic would drop her voice to "phone call" quality.
        guard !MicPick.wouldUseBluetooth else { return }
        // On the Mac's speakers the mic hears her own voice and takes it for yours — so cutting in needs headphones.
        guard MicPick.outputIsHeadphones else { return }
        bargeListening = true
        oneShot = true
        startRecognition()
        if bargeListening { status = "Talking…" }     // she's still talking (the ear is open, but she isn't "listening" yet)
        appendAppLog("voice.log", "listening while talking (you can cut in)")
    }
    private static func words(_ t: String) -> [String] {
        t.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "'" }.map(String.init)
    }
    /// The words in the transcript that are YOU, not her own voice coming back through the mic. nil = only her.
    private func yourWords(_ said: String) -> (skip: Int, words: [String])? {
        let all = Self.words(said)
        guard !all.isEmpty else { return nil }
        // her own words (and anything that sounds like them, or like her name) are never you
        let hersList = Self.words(lastSpoken) + ["zuffi", "zuffy", "zoofy", "sophie", "suffi", "zufi", "talha", "taha"]
        let hers = Set(hersList)
        func isHers(_ w: String) -> Bool {
            if hers.contains(w) { return true }
            let p = String(w.prefix(4))
            return w.count >= 4 && hersList.contains { $0.count >= 4 && $0.hasPrefix(p) }
        }
        let stopWords: Set<String> = ["stop", "wait", "ruko", "suno", "bas"]
        guard let first = all.firstIndex(where: { !isHers($0) }) else { return nil }
        let mine = Array(all[first...])
        let new = mine.filter { !isHers($0) }.count
        if new >= 3 || (stopWords.contains(mine[0]) && mine.count <= 2) { return (first, mine) }
        return nil
    }
    private func cutIn(skip: Int, mine: [String]) {
        bargeListening = false
        bargeSkip = skip
        // what she had already said (her lips follow ~14 letters a second)
        let sec = Date().timeIntervalSince(audioStartedAt)
        let saidSoFar = String(lipText.prefix(max(0, Int(sec * 14.5))))
        if saidSoFar.count > 12 { interruptedNote = String(saidSoFar.suffix(160)) }
        appendAppLog("voice.log", "you cut in: \(mine.joined(separator: " "))")
        neuralTurn += 1                         // her unfinished answer must not "end" and restart listening
        synth.stopSpeaking(at: .immediate)
        VoiceboxVoice.shared.stop(); FishVoice.shared.stop(); GroqVoice.shared.stop(); WorldVoice.shared.stop(); NativeSpeech.shared.stop()
        speaking = false
        resumeAfterSpeech = false; listenAfterSpeech = false
        status = "Listening…"
        BunnyFaceCenter.shared.show(.listening, for: 3)
    }

    // MARK: Conversation (like ChatGPT voice): tap once — talk back and forth; tap again — she stops.
    @Published private(set) var conversation = false
    private var convMisses = 0
    func toggleConversation() {
        if conversation { endConversation(); return }
        if ZuffiPlan.shared.blocked(speak: true) { return }
        conversation = true; convMisses = 0
        appendAppLog("voice.log", "conversation started")
        listenOnce(byButton: true)
    }
    func endConversation() {
        guard conversation else { return }
        conversation = false
        appendAppLog("voice.log", "conversation ended")
        resumeAfterSpeech = false; listenAfterSpeech = false
        if speaking { stopSpeaking(); speaking = false }
        oneShot = false
        stopRecognition()
        status = ""
    }
    /// Her turn is over: listen for yours.
    private func conversationNext(after delay: Double = 0.9) {      // a short beat, so the mic doesn't hear the end of her own voice
        guard conversation else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                let v = VoiceEngine.shared
                guard v.conversation, !v.speaking, !v.isListening else { return }
                v.listenOnce(byButton: false)
            }
        }
    }
    private func conversationMissed() {
        guard conversation else { return }
        convMisses += 1
        if convMisses >= 3 { endConversation() } else { conversationNext(after: 0.2) }
    }
    /// You said something: if nothing is spoken back (a quiet action), keep the conversation going anyway.
    private func conversationHeard() {
        guard conversation else { return }
        convMisses = 0
        let at = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            MainActor.assumeIsolated {
                let v = VoiceEngine.shared
                guard v.conversation, !v.speaking, !v.isListening, v.lastSpokenAt < at else { return }
                v.conversationNext(after: 0)
            }
        }
    }
    var pttEndedAt = Date.distantPast
    /// When the sound of the current sentence actually started (for lip-sync).
    var audioStartedAt = Date.distantPast { didSet { Aurora3DRig.liveStart = audioStartedAt } }
    /// The words being spoken right now (one sentence at a time) — Aurora's lips follow them.
    @Published var lipText = "" { didSet { Aurora3DRig.liveText = lipText } }
    func setMic(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: "micOn")
        micEnabled = on
        if on {
            status = ""
            if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated { VoiceEngine.shared.startRecognition() } } }
        } else {
            if LiveSession.shared.active { LiveSession.shared.stop("mic off") }
            stopRecognition()
            status = "Mic is off"
        }
    }
    func setCamera(_ on: Bool) { UserDefaults.standard.set(on, forKey: "cameraOn"); objectWillChange.send() }

    /// The meeting helper takes the microphone for a while: two listeners on one mic can crash macOS audio.
    private(set) var micLent = false
    func lendMic() { micLent = true; stopRecognition(); status = "Meeting helper is listening" }
    func takeMicBack() {
        micLent = false; status = ""
        if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) && Self.micOn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { VoiceEngine.shared.startRecognition() } }
        }
    }

    fileprivate func startRecognition() {
        guard !micLent else { return }
        guard Self.micOn else { status = "Mic is off — turn it on to talk to Zuffi"; return }
        guard !speaking || bargeListening else { resumeAfterSpeech = true; return }
        bargeSkip = 0
        // Offline: if this language can't be heard on the Mac itself, use a language that can (so voice still works with no internet).
        var hearWith = recognizer
        if !NetStatus.shared.online, !(hearWith?.supportsOnDeviceRecognition ?? false) {
            for id in ["en-IN", "en-US", "en-GB"] {
                if let r = SFSpeechRecognizer(locale: Locale(identifier: id)), r.supportsOnDeviceRecognition { hearWith = r; break }
            }
            appendAppLog("voice.log", "offline: listening on this Mac with \(hearWith?.locale.identifier ?? "none")")
        }
        guard let recognizer = hearWith, recognizer.isAvailable || (!NetStatus.shared.online && recognizer.supportsOnDeviceRecognition) else {
            status = NetStatus.shared.online ? "Speech recognition isn't ready yet — retrying…" : "Offline: turn on Dictation once (System Settings › Keyboard) so your Mac can hear you without internet"
            appendAppLog("voice.log", "recogniser not available")
            return
        }
        pauseRecognition()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.contextualStrings = ["Zuffi", "hey Zuffi", "Zuffy", "hey Zuffy", "Zuffi open", "Zuffi play", "open", "close", "Claude", "Spotify", "Chrome",
                                 "Safari", "WhatsApp", "Gmail", "YouTube", "Finder", "Visual Studio Code", "volume", "pause", "next song",
                                 "remind me", "meeting notes", "Wi-Fi", "Bluetooth", "shut down", "restart", "kholo", "chalao", "band karo",
                                 "yaad dilao", "gaana", "awaaz"]
        // "Zuffi…" is listened for privately on this Mac. Once you're talking to Zuffi (after its name, the mic
        // button or the ⌥ key), Apple's sharper online recognition is used when there's internet.
        let sharp = (oneShot || pushToTalk) && NetStatus.shared.online && UserDefaults.standard.object(forKey: "sharpHearing") as? Bool ?? true
        if recognizer.supportsOnDeviceRecognition && (!sharp || !NetStatus.shared.online) { req.requiresOnDeviceRecognition = true }
        request = req
        let node = audio.inputNode
        Self.installTap(node, req)
        audio.prepare()
        do { try audio.start() } catch {
            appendAppLog("voice.log", "mic start failed: \(error.localizedDescription)")
            status = "Couldn't use the microphone."
            failures += 1
            if failures < 6 { restartIfWanted(after: Double(failures) * 2) }
            return
        }
        isListening = true
        listenStartedAt = Date()
        status = oneShot ? "Listening…" : "Say \"Zuffi…\" anytime"
        failures = 0
        heard = ""
        generation += 1
        let gen = generation
        task = Self.startTask(recognizer, req) { text, ended in
            Task { @MainActor in VoiceEngine.shared.onPartial(text, ended: ended, gen: gen) }
        }
        appendAppLog("voice.log", "listening started (gen \(gen), oneShot \(oneShot), onDevice \(req.requiresOnDeviceRecognition))")
        // Listening for one command but nothing comes (or the recogniser silently stalls)?
        // After 9 s go back to "Zuffi…" listening — never get stuck deaf.
        if oneShot && !pushToTalk {
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                MainActor.assumeIsolated {
                    let me = VoiceEngine.shared
                    guard me.generation == gen, me.oneShot, !me.pushToTalk, me.heard.isEmpty, !me.bargeListening else { return }
                    appendAppLog("voice.log", "one-shot: nothing heard in 9s — back to \"Zuffi…\" listening")
                    me.oneShot = false
                    me.status = ""
                    if me.conversation { me.stopRecognition(); me.conversationMissed(); return }     // quiet turn: listen again (3 → the conversation ends)
                    if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) { me.startRecognition() } else { me.stopRecognition() }
                }
            }
        }
        // Apple limits one recognition task to about a minute — refresh it regularly.
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { _ in
            MainActor.assumeIsolated {
                let me = VoiceEngine.shared
                if me.isListening && !me.oneShot { me.startRecognition() }
            }
        }
    }

    private func pauseRecognition() {
        generation += 1   // anything still arriving from the old session is now ignored
        restartTimer?.invalidate(); silenceTimer?.invalidate()
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
        isListening = false
    }

    private func stopRecognition() {
        oneShot = false
        pauseRecognition()
    }

    private func onPartial(_ text: String?, ended: Bool, gen: Int) {
        guard gen == generation else { return }   // stale session
        if bargeListening {
            // She's talking: only YOUR words (not her own voice in the mic) interrupt her.
            if ended && speaking { pauseRecognition(); bargeListening = false; DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { MainActor.assumeIsolated { VoiceEngine.shared.startBargeIn() } }; return }
            guard let text, speaking, let you = yourWords(text) else { return }
            cutIn(skip: you.skip, mine: you.words)
        }
        if let text { heard = bargeSkip > 0 ? Self.words(text).dropFirst(bargeSkip).joined(separator: " ") : text }
        if ended && text == nil && heard.isEmpty {
            // Session ended on its own (timeout / error) with nothing heard: quietly start a new one.
            appendAppLog("voice.log", "session ended empty (gen \(gen))")
            if oneShot { oneShot = false; missedAt = Date(); status = "Didn't catch that. Tap the mic and try again." }
            restartIfWanted(after: 0.5)
            return
        }
        silenceTimer?.invalidate()
        // When the person stops talking for a moment, act on what they said.
        // Simple commands ("open chrome", "pause") fire almost instantly; questions get a bit longer.
        // Hold-to-talk: wait for the key to be released, never for silence.
        if pushToTalk { return }
        var wait = 1.0
        func complete(_ c: String) -> Bool {
            let l = c.lowercased()
            // Half-said commands ("start…", "start meeting…", "remind me…") wait for the rest instead of firing.
            if l.range(of: #"^(start|begin|take|record|turn on|turn off|open|close|set|remind me|start taking|stop|play|put)( the| my| a)?$|^(start|begin|take|turn on|start taking)( the| my)? (meeting|call|notes?)$"#, options: .regularExpression) != nil { return false }
            return c.split(separator: " ").count <= 7 && (CommandEngine.shared.intent(c) != nil || CommandEngine.shared.looksLikeCommand(l))
        }
        if let cmd = extractCommand(heard), !cmd.isEmpty {
            wait = complete(cmd) ? 0.35 : 0.85       // a clear command runs the moment you stop
        } else if oneShot, !heard.isEmpty {
            wait = conversation ? (complete(heard) ? 0.95 : 1.4) : (complete(heard) ? 0.4 : 0.8)   // in a conversation: let you finish your thought
        } else if extractCommand(heard) == "" {
            wait = 1.3   // just "Zuffi" — give a moment to say the rest in the same breath
        }
        // Sounds unfinished ("open spotify and…", "phir…")? Keep listening a little longer.
        if heard.lowercased().range(of: #"\b(and|then|also|aur|phir|or|to|the|for|with|ke|ki|ka|start|begin|take|meeting|my)\s*$"#, options: .regularExpression) != nil {
            wait = max(wait, 1.4)
        }
        extraWait = 0
        silenceTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { _ in
            MainActor.assumeIsolated { VoiceEngine.shared.maybeFinish() }
        }
        if ended && !oneShot { finishUtterance() }
        else if ended { silenceTimer?.invalidate(); silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
            MainActor.assumeIsolated { VoiceEngine.shared.maybeFinish() } } }
    }

    /// Text after the wake word ("hey sparrow, open chrome" → "open chrome"), "" if only the
    /// wake word was said, nil if the wake word wasn't said at all.
    private func extractCommand(_ said: String) -> String? {
        let lower = said.lowercased()
        for wake in ["zuffi's", "zuffis", "zuffy's", "zuffi", "zuffy", "zuffie", "zufi", "zufy", "zuffee", "zoffy", "zofi", "zophie", "zuphie", "zoo fi", "zu fee", "zoofie", "suffy", "zoofi", "zoofy", "zoofee", "zu fi", "zoo fee", "zaffi", "zuphy", "ज़ुफ़ी", "زوفی",
                     "sparrow's", "sparrows", "sparrow", "sparro", "sparo", "spero", "sperro", "spirrow", "sporrow", "spar row",
                     "spa row", "sparrowe", "hey barrow", "barrow", "sorrow", "سپیرو", "स्पैरो"] {
            if let r = lower.range(of: wake, options: .backwards) {
                return String(lower[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            }
        }
        // Just the name, misheard on-device ("Pero", "Paro", "Porn", "Barrow"…): a single word that sounds like it.
        let words = lower.split(whereSeparator: { " ,.!?".contains($0) })
        if words.count == 1, words[0].range(of: #"^(z|s|j)[uo]+f+(i|y|ie|ee|ey)s?$|^(s|sh|b)?p[aeiou]+r+[aeiou]*(w|ow|n|ne|ns|o)?s?$|^(sp|b)?[aeo]r+o(w|ws)?$|^pharaoh$"#, options: .regularExpression) != nil {
            return ""
        }
        // Close mis-hearings at the very start: "spare open chrome", "sparo, play music"…
        if let r = lower.range(of: #"^(hey |ok |hi )?(sp[aeio]r+[oe]w?s?|z[uo]+f+(i|y|ie|ee))\b[, ]*"#, options: .regularExpression) {
            return String(lower[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        }
        // "Hey Zuffy" is often heard as "hey Sophie" / "hey Sufi" / "hey toffee": accept those after "hey".
        if let r = lower.range(of: #"\b(hey|hi|ok|okay|hay) (sophie|sofie|sophia|soffy|sofi|sufi|soufi|suffy|toffee|zoe fee|zoey|zappy|duffy|fluffy)\b[, ]*"#, options: .regularExpression) {
            return String(lower[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        }
        return nil
    }

    /// Write anywhere (hold ⌃⌥): what you say goes to the typing helper instead of being a command.
    var dictationSink: ((String) -> Void)?

    private func finishUtterance() {
        silenceTimer?.invalidate()
        let said = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        if let sink = dictationSink {
            dictationSink = nil; heard = ""; oneShot = false
            stopRecognition(); status = ""
            sink(said)
            return
        }
        let wasOneShot = oneShot
        if wasOneShot || Date().timeIntervalSince(pttEndedAt) < 3 { if said.isEmpty { missedAt = Date() } else { lastHeard = said; lastHeardAt = Date() } }
        if !said.isEmpty { appendAppLog("voice.log", "heard: \(said)") }
        if meetingMode && !said.isEmpty {
            heard = ""
            if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) || meetingMode { startRecognition() }
            let low = said.lowercased()
            if low.contains("stop meeting") || low.contains("end meeting") || low.contains("meeting khatam") || low.contains("stop the notes") {
                Task {
                    let r = await MeetingNotes.shared.stop()
                    AppState.shared.noteMessage = r
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                    VoiceEngine.shared.speak(r)
                }
            } else {
                MeetingNotes.shared.add(said)
            }
            return
        }
        var command: String?
        if wasOneShot {
            // Already listening for the command: drop a repeated "hey Zuffi" in front of it.
            let stripped = said.replacingOccurrences(of: #"^\s*((hey|hi|ok|okay|hello)\s+)?(zuffi|zuffy|zoofy|sophie|zufi)[\s,.!?]*"#, with: "", options: [.regularExpression, .caseInsensitive])
            if stripped.isEmpty && !said.isEmpty {
                appendAppLog("voice.log", "name again while listening — still listening")
                heard = ""; oneShot = true; startRecognition(); status = "Listening…"
                return
            }
            command = stripped.isEmpty ? nil : stripped
        } else {
            command = extractCommand(said)
        }
        heard = ""
        // Keep listening for "Zuffi…" afterwards if that's switched on; otherwise stop.
        if wasOneShot { oneShot = false }
        if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) { startRecognition() }   // fresh transcript
        else if wasOneShot { stopRecognition(); status = "" }

        // "Hey Nik …" goes to Nik, the teacher (only while the mic is listening, like "Hey Zuffi").
        if !wasOneShot, let nikSaid = NikWake.command(said) {
            appendAppLog("voice.log", "nik: \(nikSaid)")
            NikBrain.shared.heard(nikSaid)
            return
        }
        guard let command else {
            // Hands-free: no need to say "Zuffi" first — act when it's clearly a request.
            let handsFree = UserDefaults.standard.object(forKey: "handsFree") as? Bool ?? false
            if handsFree, !said.isEmpty, AgentRouter.shared.isClearRequest(said) {
                appendAppLog("voice.log", "hands-free command: \(said)")
                Task { await Assistant.run(said, spoken: true) }
            } else if !said.isEmpty {
                appendAppLog("voice.log", "not for me (no \"Zuffi\"): \(said)")
            }
            return
        }
        // Jarvis mode: one continuous conversation (any language, interruptible) until "thanks" / "bye".
        if LiveSession.shared.usable, !meetingMode {
            appendAppLog("voice.log", "live conversation: \(command.isEmpty ? "(name only)" : command)")
            LiveSession.shared.start(text: command.isEmpty ? nil : command, byName: true)
            return
        }
        if command.isEmpty {
            // Just the name: she pops out, answers out loud ("Yes?") and listens for the command — online or offline.
            NotificationCenter.default.post(name: .hookReveal, object: nil)
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
            liveEndedAt = .distantPast
            listenAfterSpeech = true
            let first = AssistantPrefs.displayName.components(separatedBy: " ").first ?? ""
            speak(first.isEmpty ? ["Hey! Yes?", "Hi! I'm here.", "Mm-hm? I'm listening."].randomElement()!
                                : ["Hey \(first)!", "Hey \(first)! What's up?", "Hi \(first)! I'm listening.", "Yes, \(first)?"].randomElement()!)
            status = "Listening…"
            return
        }
        appendAppLog("voice.log", "command: \(command)")
        Task { await Assistant.run(command, spoken: true) }
    }
}

extension VoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in VoiceEngine.shared.speechFinished() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) {
        Task { @MainActor in VoiceEngine.shared.speechFinished() }
    }
}

// MARK: - Assistant: run one command (typed or spoken)

@MainActor
enum Assistant {
    static let notUnderstood = [
        "Sorry, I didn't quite catch that. Could you say it again?",
        "Hmm, I missed that one. Say it once more?",
        "I didn't get that. Try something like \"open Spotify\" or \"play some music\".",
    ]

    /// A warm "say that again" — then Zuffi listens straight away.
    static func askAgain() {
        let line = notUnderstood.randomElement()!
        AppState.shared.noteMessage = "🐰 " + line
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        VoiceEngine.shared.listenAfterSpeech = true
        VoiceEngine.shared.speak(line)
    }

    static func run(_ text: String, spoken: Bool) async {
        let state = AppState.shared
        if ZuffiPlan.shared.blocked(speak: spoken) { return }   // no plan: sign in / choose a plan first
        // Hold Z / double-click Zuffi / "explain this on my screen": answer about what's selected or on screen.
        if spoken, let hit = ZuffiAsk.shared.takeIfAboutScreen(text) {
            await ZuffiAsk.shared.answer(hit.0, about: hit.1)
            return
        }
        AuroraTouch.feel(for: text)          // something funny or sweet: her face answers first
        // Her own pages and your data: "open tasks", "delete the note …", "open the lawyer agent and ask …"
        if let r = await ZuffiCommand.handle(text) {
            if !r.isEmpty {
                if NotchDesign.on { ZuffiAsk.shared.show(r, title: text, speak: spoken) } else if spoken { VoiceEngine.shared.speak(r) }
            }
            return
        }
        // On the notch's Chat page a question goes into that chat (to Zuffi or the agent you picked)
        if spoken, ZuffiAsk.notchOpen, NotchNav.shared.page == "chat", text.split(separator: " ").count > 2, !ZuffiTeam.looksLikeCommand(text) {
            NotchNav.shared.pendingChat = text
            return
        }
        // "Zuffi, help me in this meeting" → the private meeting helper
        if text.lowercased().range(of: #"\b(meeting|call) (helper|help)\b|help me (in|with|during) (this|the) (meeting|call)"#, options: .regularExpression) != nil {
            MeetingHelper.shared.toggle()
            VoiceEngine.shared.speak(MeetingHelper.shared.on ? "I'm listening. Only you can see my notes." : "Meeting helper off.")
            return
        }

        // Voice: everyday commands run instantly without opening the chat.
        if spoken, let reply = await AgentRouter.shared.handle(text) {
            let actionWords = ["Opening", "Closing", "Playing", "Paused", "Next", "Previous", "Volume", "Muted",
                               "Sound back", "Searching", "Locking", "Dark mode", "Light mode", "Select an area"]
            NotificationCenter.default.post(name: .petSay, object: reply)
            if actionWords.contains(where: { reply.hasPrefix($0) }), !reply.contains(". ") {
                SoundEngine.shared.play("approve")          // quick chirp = done…
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                VoiceEngine.shared.speak(reply)              // …and always say it, so you know it heard you
            } else {
                // Information (time, battery, problems…) is spoken and shown.
                if NotchDesign.on { ZuffiAsk.shared.show(reply, title: text) }      // in the notch, not a second window
                else {
                    state.noteMessage = reply
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                    VoiceEngine.shared.speak(reply)
                }
            }
            return
        }
        if spoken {
            func say(_ reply: String) {
                NotificationCenter.default.post(name: .petSay, object: reply)
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                Task { await NotchData.shared.refresh() }
                if NotchDesign.on { ZuffiAsk.shared.show(reply, title: text); return }   // one place: the notch
                state.noteMessage = reply
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                VoiceEngine.shared.speak(reply)
            }
            let short = text.split(separator: " ").count <= 6
            // The notch design: real requests (reminders, habits, notes, prayer times, timers…) are done instantly;
            // everything else is a conversation answered by the SAME model you picked in the chat bar.
            let task = ZuffiTeam.looksLikeCommand(text) || Self.isBrainTask(text)
            if NotchDesign.on, !task {
                NotchNav.shared.open("chat")
                NotchNav.shared.pendingChat = text
                return
            }
            // Habits, prayer times, memory, invoices… (Zuffi's offline brain) — instant for short requests
            if short, let reply = await WebHub.shared.ask(text) { say(reply); return }
            // A real question takes a second to think about: a little "hmm" so it feels like talking to someone
            let low = text.lowercased()
            if !short || text.hasSuffix("?") || low.range(of: #"^(what|why|how|who|when|where|which|can|could|should|is|are|do|does|explain|tell me)\b"#, options: .regularExpression) != nil {
                if !VoiceEngine.shared.conversation { VoiceEngine.shared.speak(["Hmm…", "Hmm, let me think…", "Oh, good question…", "Okay…"].randomElement()!) }
            }
            // Anything else, any language: the smart planner turns it into actions and answers like a person
            if let plan = await SmartPlanner.shared.plan(text) {
                if plan.commands.isEmpty && plan.say.isEmpty { askAgain(); return }
                if plan.commands.isEmpty, NotchDesign.on {           // just talk → the chat model answers, not the planner
                    NotchNav.shared.open("chat"); NotchNav.shared.pendingChat = text; return
                }
                if plan.commands.isEmpty, plan.say.count > 260 {
                    // a long answer belongs in the chat
                    state.chatHistory.append(ChatMessage(role: .user, content: text))
                    state.chatHistory.append(ChatMessage(role: .assistant, content: plan.say))
                    state.view = .prompt
                    NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
                    VoiceEngine.shared.speak(plan.say)
                    return
                }
                say(await SmartPlanner.shared.run(plan)); return
            }
            if !short, let reply = await WebHub.shared.ask(text) { say(reply); return }
            let ollamaHas = !(await AIService.ollamaModels()).isEmpty
            let hasLocalBrain = AIService.appleModelAvailable || ollamaHas
            if !NetStatus.shared.online, !hasLocalBrain, text.split(separator: " ").count > 1 {
                say("I'm offline right now, so I can't look that up. I can still open apps, play music, control your Mac, and set reminders and notes.")
                return
            }
            // Too short or garbled to be a real question, or no AI to ask: a warm "say that again".
            let hasAI = await AIService.shared.resolveProvider(state: state) != nil
            if text.split(separator: " ").count <= 1 || !hasAI {
                askAgain(); return
            }
        }
        if spoken, NotchDesign.on {
            BunnyFaceCenter.shared.show(.thinking, for: 8)
            let r = await AIService.shared.oneShot("The user asks (by voice): \"\(text)\"\nAnswer like a kind, clever friend talking out loud: short and clear (under 90 words), in the language they spoke. Plain text, no symbols.",
                                                   system: ZuffiVoice.persona + "\n" + ZuffiVoice.style) ?? ""
            let out = r.trimmingCharacters(in: .whitespacesAndNewlines)
            ZuffiAsk.shared.show(out.isEmpty ? ZuffiAsk.noBrainLine : out, title: text)
            return
        }
        state.chatHistory.append(ChatMessage(role: .user, content: text))
        state.stateOverride = .thinking
        if NotchDesign.on { NotchNav.shared.open("chat") } else { NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt) }
        let before = state.chatHistory.count
        await AIService.shared.chat(query: text, context: nil, state: state)
        if spoken && (UserDefaults.standard.bool(forKey: AssistantPrefs.speakReplies) || !NetStatus.shared.online),   // offline it talks back like the live voice
           state.chatHistory.count > before, let last = state.chatHistory.last, last.role == .assistant {
            VoiceEngine.shared.speak(last.content)
        }
        if let last = state.chatHistory.last, last.role == .assistant {
            NotificationCenter.default.post(name: .petSay, object: last.content)
        }
    }

    /// Things Zuffi's own brain does (not a chat): reminders, notes, tasks, habits, timers, prayer times, memory, money…
    static func isBrainTask(_ t: String) -> Bool {
        t.lowercased().range(of: #"\b(remind|reminder|alarm|timer|snooze|note|notes|task|tasks|to ?do|habit|habits|prayer|namaz|azan|remember|forget|spent|expense|invoice|quote|meeting|schedule|calendar|what'?s on|my (day|plan|week|tasks|reminders|habits)|what time|date today|weather|battery|focus)\b"#, options: .regularExpression) != nil
    }

    static func start() {
        AssistantPrefs.registerDefaults()
        Briefing.shared.start()
        Routine.shared.start()
        NotificationReader.shared.setEnabled(UserDefaults.standard.bool(forKey: AssistantPrefs.readNotes))
        if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) {
            VoiceEngine.shared.setWakeWord(true)
        }
    }
}

// MARK: - Greeting + weather when you open your Mac

@MainActor
final class Briefing {
    static let shared = Briefing()
    private var lastGreet = Date.distantPast
    private var lastPeriod = ""

    func start() {
        // On launch (after the sparrow's own hello animation)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { Briefing.shared.maybeGreet() }
        // When the Mac wakes or the screen unlocks
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Briefing.shared.scheduleGreet() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Briefing.shared.scheduleGreet() }
        }
    }

    private func scheduleGreet() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { Briefing.shared.maybeGreet() }
    }

    static func period(_ d: Date = Date()) -> String {
        let h = Calendar.current.component(.hour, from: d)
        switch h {
        case 5..<12:  return "morning"
        case 12..<17: return "afternoon"
        case 17..<22: return "evening"
        default:      return "night"
        }
    }

    /// "Tuesday 6 Oct · morning" — Zuffi says hello at most once per part of the day, even after restarts.
    private static func slot(_ d: Date = Date()) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d) + " " + period(d)
    }
    private var greetedThisPart: Bool { UserDefaults.standard.string(forKey: "greetSlot") == Self.slot() }

    private func maybeGreet() {
        guard UserDefaults.standard.bool(forKey: AssistantPrefs.greetEnabled) else { return }
        // Once per morning / afternoon / evening — never again after lunch or a short break, never at night.
        guard !greetedThisPart, Self.period() != "night" else { return }
        appendAppLog("voice.log", "greeting (\(Self.slot()))")
        Task { await greet() }
    }

    /// Called by the morning briefing so the wake greeting doesn't repeat it (and the other way round).
    func markGreeted() { lastGreet = Date(); lastPeriod = Self.period(); UserDefaults.standard.set(Self.slot(), forKey: "greetSlot") }
    /// True if Zuffi already said hello in this part of the day.
    var greetedRecently: Bool { greetedThisPart || Date().timeIntervalSince(lastGreet) < 20 * 60 }

    func greet() async {
        markGreeted()
        let text = await composeGreeting()
        // One-time tip if the Mac only has robotic voices.
        if VoiceEngine.onlyBasicVoices && !UserDefaults.standard.bool(forKey: "voiceTipShown") {
            UserDefaults.standard.set(true, forKey: "voiceTipShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                AppState.shared.noteMessage = "Tip: want me to sound more human? Settings → Voice → “Make Zuffi sound human”. It's free."
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
            }
        }
        // Just spoken — no text on screen.
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        VoiceEngine.shared.speak(text)
    }

    func composeGreeting() async -> String {
        let name = AssistantPrefs.displayName
        let p = Self.period()
        let hello: String
        switch p {
        case "morning":   hello = "Good morning"
        case "afternoon": hello = "Good afternoon"
        case "evening":   hello = "Good evening"
        default:          hello = "Hi, you're up late"
        }
        let tf = DateFormatter(); tf.timeStyle = .short
        var text = "\(hello)\(name.isEmpty ? "" : ", \(name)")! It's \(tf.string(from: Date()))."
        if UserDefaults.standard.bool(forKey: AssistantPrefs.greetWeather), let w = await Weather.now() {
            text += " " + w
        }
        // What's new: unread email (only if Mail is open — never launches it) and what's next today
        if NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == "com.apple.mail" }),
           let n = Int(CommandEngine.shared.runAppleScript("tell application \"Mail\" to get unread count of inbox") ?? ""), n > 0 {
            text += " You have \(n) unread email\(n == 1 ? "" : "s")."
        }
        let mine = await WebHub.shared.zuffiPlan()
        let apple = await Planner.shared.summary(for: Date(), detailed: false)
        text += " " + (mine.isEmpty ? apple : (apple.contains("calendar is clear") ? mine : apple + " " + mine))
        return text
    }
}

// MARK: - Weather (free, no API key: Open-Meteo)

enum Weather {
    static func now() async -> String? {
        guard let loc = await location() else { return nil }
        let useF = Locale.current.measurementSystem == .us
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(loc.lat)), .init(name: "longitude", value: String(loc.lon)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "1"),
            .init(name: "temperature_unit", value: useF ? "fahrenheit" : "celsius"),
        ]
        guard let url = c.url, let json = await getJSON(url),
              let cur = json["current"] as? [String: Any],
              let temp = cur["temperature_2m"] as? Double else { return nil }
        let code = cur["weather_code"] as? Int ?? 0
        var s = "In \(loc.city) it's \(Int(temp.rounded())) degrees and \(describe(code))"
        if let daily = json["daily"] as? [String: Any],
           let hi = (daily["temperature_2m_max"] as? [Double])?.first {
            s += ", with a high of \(Int(hi.rounded()))"
            if let rain = (daily["precipitation_probability_max"] as? [Int])?.first, rain >= 50 {
                s += ". There's a \(rain)% chance of rain, so take an umbrella"
            }
        }
        return s + "."
    }

    static func location() async -> (lat: Double, lon: Double, city: String)? {
        let city = (UserDefaults.standard.string(forKey: AssistantPrefs.weatherCity) ?? "").trimmingCharacters(in: .whitespaces)
        if !city.isEmpty {
            var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
            c.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1")]
            if let url = c.url, let json = await getJSON(url),
               let r = (json["results"] as? [[String: Any]])?.first,
               let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double {
                return (lat, lon, r["name"] as? String ?? city)
            }
        }
        // Real location from the Mac (Wi-Fi based) — correct even when you travel.
        if let here = await LocationProvider.shared.current() { return here }
        // Fallback: approximate location from the internet connection.
        if let url = URL(string: "https://ipapi.co/json/"), let json = await getJSON(url),
           let lat = json["latitude"] as? Double, let lon = json["longitude"] as? Double {
            return (lat, lon, json["city"] as? String ?? "your area")
        }
        return nil
    }

    static func getJSON(_ url: URL) async -> [String: Any]? {
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("Zuffi", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "clear"
        case 1, 2: return "partly cloudy"
        case 3: return "cloudy"
        case 45, 48: return "foggy"
        case 51...57: return "drizzly"
        case 61...67, 80...82: return "rainy"
        case 71...77, 85, 86: return "snowy"
        case 95...99: return "stormy"
        default: return "mild"
        }
    }
}

// MARK: - Current location (Location Services, asked once)

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()
    private let manager = CLLocationManager()
    private var waiting: [CheckedContinuation<CLLocation?, Never>] = []
    private var cached: (lat: Double, lon: Double, city: String, at: Date)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var allowed: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedAlways || s == .authorized
    }

    func current() async -> (lat: Double, lon: Double, city: String)? {
        if let c = cached, Date().timeIntervalSince(c.at) < 20 * 60 { return (c.lat, c.lon, c.city) }
        guard CLLocationManager.locationServicesEnabled() else { return nil }
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted { return nil }
        let loc: CLLocation? = await withCheckedContinuation { cont in
            waiting.append(cont)
            if status == .notDetermined { manager.requestWhenInUseAuthorization() }
            manager.requestLocation()
            // Never wait forever (no Wi-Fi, permission prompt ignored…)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { LocationProvider.shared.resolve(nil) }
        }
        guard let loc else { return nil }
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        let city = await Self.cityName(lat: lat, lon: lon) ?? "your area"
        cached = (lat, lon, city, Date())
        return (lat, lon, city)
    }

    nonisolated static func cityName(lat: Double, lon: Double) async -> String? {
        let l = CLLocation(latitude: lat, longitude: lon)
        guard let pm = try? await CLGeocoder().reverseGeocodeLocation(l).first else { return nil }
        return pm.locality ?? pm.subAdministrativeArea ?? pm.administrativeArea
    }

    fileprivate func resolve(_ loc: CLLocation?) {
        let w = waiting; waiting = []
        w.forEach { $0.resume(returning: loc) }
    }

    nonisolated func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let c = locs.last?.coordinate else { return }
        let lat = c.latitude, lon = c.longitude
        MainActor.assumeIsolated { LocationProvider.shared.resolve(CLLocation(latitude: lat, longitude: lon)) }
    }
    nonisolated func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { LocationProvider.shared.resolve(nil) }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        MainActor.assumeIsolated { LocationProvider.shared.authChanged() }
    }

    fileprivate func authChanged() {
        let s = manager.authorizationStatus
        if s == .denied || s == .restricted { resolve(nil) }
        else if s == .authorizedAlways || s == .authorized { manager.requestLocation() }
    }
}

// MARK: - Read new notifications aloud
// macOS has no public API to read other apps' notifications, so this reads the
// on-screen banners through Accessibility (the person turns it on and grants access).

@MainActor
final class NotificationReader {
    static let shared = NotificationReader()
    private var timer: Timer?
    private var seen: [String] = []
    private var primed = false

    static var hasAccess: Bool { AXIsProcessTrusted() }

    static func askAccess() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Speak new notifications aloud (the user's setting).
    private var speakOn = false

    func setEnabled(_ on: Bool) {
        speakOn = on
        if !on {            // one switch for everything read out: WhatsApp and email too
            WhatsAppLink.shared.readAloud = false
            WebHub.shared.run("try { const s = window.Sparrow && window.Sparrow.store; if (s && s.state) { s.state.waReadAloud = false; s.save && s.save(); } } catch (e) {}")
        }
        if on, !Self.hasAccess { Self.askAccess() }
        refresh()
    }

    /// Runs while notifications are read aloud, or while Zuffi turns WhatsApp messages into leads.
    func refresh() {
        let need = speakOn || (ZuffiCRM.shared.isOn(.watchWhatsApp) && ZuffiBusiness.shared.pack != nil)
        if need, timer == nil {
            primed = false
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                MainActor.assumeIsolated { NotificationReader.shared.poll() }
            }
        } else if !need, let t = timer { t.invalidate(); timer = nil }
    }

    private func poll() {
        guard Self.hasAccess,
              let nc = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" })
        else { return }
        let appEl = AXUIElementCreateApplication(nc.processIdentifier)
        let windows = Self.children(appEl, attr: kAXWindowsAttribute as String)
        var banners: [(joined: String, texts: [String], descs: [String])] = []
        for w in windows {
            var texts: [String] = [], descs: [String] = []
            Self.collectTexts(w, into: &texts, depth: 0, descs: &descs)
            let clean = texts.filter { !$0.isEmpty }
            let joined = clean.joined(separator: ". ")
            if !joined.isEmpty { banners.append((joined, clean, descs)) }
        }
        let new = banners.filter { !seen.contains($0.joined) }
        seen = Array((seen + new.map(\.joined)).suffix(40))
        guard primed else { primed = true; return }
        // If the full Notification Centre is open there are lots of texts — don't read them all.
        guard !new.isEmpty, new.count <= 3 else { return }
        for b in new { ZuffiCRM.shared.fromNotification(b.texts, descriptions: b.descs) }
        if let first = new.first { EdgeGlow.shared.flash(.notify(first.texts.first ?? "Notification"), seconds: 2.6) }   // light round the notch
        if false, speakOn, let first = new.first, new.count <= 2, first.joined.count < 400 {      // notifications are shown, never read out
            VoiceEngine.shared.announce("New notification. " + first.joined)
        }
    }

    private static func children(_ el: AXUIElement, attr: String) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    private static func collectTexts(_ el: AXUIElement, into out: inout [String], depth: Int, descs: inout [String]) {
        guard depth < 12, out.count < 12 else { return }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        var d: CFTypeRef?
        if descs.count < 8, AXUIElementCopyAttributeValue(el, kAXDescriptionAttribute as CFString, &d) == .success, let ds = d as? String, !ds.isEmpty { descs.append(ds) }
        if (role as? String) == (kAXStaticTextRole as String) {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &val) == .success, let s = val as? String {
                out.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        for c in children(el, attr: kAXChildrenAttribute as String) { collectTexts(c, into: &out, depth: depth + 1, descs: &descs) }
    }
}

// MARK: - Settings: voice, greeting, notifications, apps

struct AssistantSettings: View {
    enum Part: CaseIterable { case voice, greeting, notifications, apps }
    var parts: Set<Part> = Set(Part.allCases)

    @AppStorage(AssistantPrefs.voiceGender) private var gender = "female"
    @AppStorage(AssistantPrefs.voiceId) private var voiceId = ""
    @AppStorage(AssistantPrefs.voiceRate) private var rate = 0.5
    @AppStorage(AssistantPrefs.speakReplies) private var speakReplies = true
    @AppStorage(AssistantPrefs.wakeWord) private var wakeWord = false
    @AppStorage("liveMode") private var liveMode = true
    @AppStorage("liveVoice") private var liveVoice = "Kore"
    @AppStorage("liveIdleSeconds") private var liveIdle = 20.0
    @AppStorage(AssistantPrefs.greetEnabled) private var greet = true
    @AppStorage(AssistantPrefs.greetWeather) private var greetWeather = true
    @AppStorage(AssistantPrefs.userName) private var name = ""
    @AppStorage(AssistantPrefs.weatherCity) private var city = ""
    @AppStorage(AssistantPrefs.readNotes) private var readNotes = false
    @ObservedObject private var voice = VoiceEngine.shared
    @State private var appSearch = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if parts.contains(.voice) {
            GroupBox("Voice") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Voice", selection: $gender) {
                        Text("Female").tag("female")
                        Text("Male").tag("male")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: gender) { _, _ in voiceId = "" }

                    Picker("Which voice", selection: $voiceId) {
                        Text("Best available").tag("")
                        ForEach(VoiceEngine.availableVoices(gender: gender), id: \.identifier) { v in
                            Text(voiceLabel(v)).tag(v.identifier)
                        }
                    }
                    HStack {
                        Text("Speed")
                        Slider(value: $rate, in: 0.35...0.62)
                        Button("Test") { VoiceEngine.shared.speak("Hi\(AssistantPrefs.displayName.isEmpty ? "" : " \(AssistantPrefs.displayName)"), I'm Zuffi. How can I help?") }
                    }
                    if VoiceEngine.onlyBasicVoices {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Make Zuffi sound human (free, 2 minutes)", systemImage: "sparkles")
                                .font(.system(size: 12.5, weight: .bold))
                            Text("Your Mac only has the basic robotic voices. Download a natural one once — it then works offline:")
                                .font(.system(size: 11))
                            Text("1. Click “Get more natural voices…” below\n2. Next to System voice, click ⓘ or “Manage Voices…”\n3. English → tick “Zoe (Premium)” or “Ava (Premium)” (female) or “Evan (Enhanced)” (male)\n4. Come back here and pick it in Voice")
                                .font(.system(size: 11)).foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
                    }
                    HStack {
                        Button("Get more natural voices…") {
                            if let u = URL(string: "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent") {
                                NSWorkspace.shared.open(u)
                            }
                        }
                        Text("System voice → Manage Voices → download e.g. \"Zoe (Premium)\" or \"Evan (Enhanced)\".")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }

                    Divider()
                    Toggle("Listen for \"Zuffi…\" (say \"Zuffi, open Chrome\")", isOn: $wakeWord)
                        .onChange(of: wakeWord) { _, on in VoiceEngine.shared.setWakeWord(on) }
                    Toggle("Speak answers out loud when I talk to Zuffi", isOn: $speakReplies)
                    Divider()
                    Toggle("Jarvis conversation — say “Zuffi” once, then just talk until “thanks” or “bye”", isOn: $liveMode)
                    if liveMode {
                        Picker("Conversation voice", selection: $liveVoice) {
                            ForEach(["Kore", "Aoede", "Leda", "Zephyr", "Puck", "Charon", "Orus", "Fenrir"], id: \.self) { Text($0).tag($0) }
                        }.frame(maxWidth: 260)
                        HStack {
                            Text("End when quiet for")
                            Slider(value: $liveIdle, in: 8...60, step: 2).frame(maxWidth: 160)
                            Text("\(Int(liveIdle)) s").monospacedDigit()
                        }.font(.system(size: 11))
                        Text(KeychainStore.shared.get("gemini-api-key")?.isEmpty == false
                             ? "Natural voice in any language (it answers in the language you speak), you can interrupt it, and it does things while you talk. Uses your Gemini key and the internet; offline, Zuffi uses its built-in voice."
                             : "Add a free Gemini key in Settings → AI to turn this on. Until then Zuffi uses its built-in voice.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if !voice.status.isEmpty {
                        HStack(spacing: 6) {
                            Circle().fill(voice.isListening ? Color.green : Color.orange).frame(width: 7, height: 7)
                            Text(voice.status).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                    if !voice.heard.isEmpty {
                        Text("Hearing: \"\(voice.heard)\"").font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2)
                    }
                    Text("Voice commands like opening apps, music and volume work offline with no API key. Speech is recognised on your Mac when it supports it.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(6)
            }
            }

            if parts.contains(.greeting) {
            GroupBox("Greeting") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Say hello when I open my Mac (good morning, time and weather)", isOn: $greet)
                    Toggle("Include the weather", isOn: $greetWeather)
                    TextField("Your name (default: \(NSFullUserName().split(separator: " ").first.map(String.init) ?? ""))", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("City for weather (leave empty for automatic)", text: $city)
                        .textFieldStyle(.roundedBorder)
                    Button("Try the greeting") { Task { await Briefing.shared.greet() } }
                }
                .padding(6)
            }
            }

            if parts.contains(.notifications) {
            GroupBox("Notifications") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("New notifications show at the notch. Zuffi doesn't read them out loud.").font(.system(size: 11.5)).foregroundColor(.secondary)
                    if false && readNotes && !NotificationReader.hasAccess {
                        HStack {
                            Text("Needs Accessibility access.").font(.system(size: 11)).foregroundColor(.orange)
                            Button("Allow…") {
                                NotificationReader.askAccess()
                                if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                    NSWorkspace.shared.open(u)
                                }
                            }
                        }
                    }
                    Text("Zuffi reads the notification banners that pop up on your screen. Nothing is sent anywhere.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(6)
            }
            }

            if parts.contains(.apps) {
            GroupBox("Apps Zuffi can open") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Every app on your Mac works. Type or say \"open\" plus the app name.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    TextField("Search apps", text: $appSearch).textFieldStyle(.roundedBorder)
                    let apps = CommandEngine.shared.allApps().filter {
                        appSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(appSearch)
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(apps, id: \.url) { app in
                                HStack(spacing: 8) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                        .resizable().frame(width: 18, height: 18)
                                    Text(app.name).font(.system(size: 12))
                                    Spacer()
                                    Text("\"open \(app.name.lowercased())\"")
                                        .font(.system(size: 10)).foregroundColor(.secondary)
                                    Button("Open") {
                                        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
                                        NSWorkspace.shared.openApplication(at: app.url, configuration: cfg, completionHandler: nil)
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    .frame(height: 180)
                }
                .padding(6)
            }
            }
        }
    }

    private func voiceLabel(_ v: AVSpeechSynthesisVoice) -> String {
        let q: String
        switch v.quality {
        case .premium:  q = " · Premium"
        case .enhanced: q = " · Enhanced"
        default:        q = ""
        }
        return "\(v.name) (\(v.language))\(q)"
    }
}

// MARK: - Mic button for the chat

struct MicButton: View {
    @ObservedObject private var voice = VoiceEngine.shared
    var body: some View {
        Button { VoiceEngine.shared.listenOnce() } label: {
            Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(voice.isListening ? Color(hex: "#F9A830") : .white.opacity(0.8))
                .frame(width: 22, height: 22)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Talk to Zuffi")
    }
}

// MARK: - Appearance: glass look + where Zuffi sits

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        v.appearance = NSAppearance(named: .darkAqua)
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

enum SparrowPosition: String, CaseIterable, Identifiable {
    case notch, left, right
    var id: String { rawValue }
    var label: String {
        switch self {
        case .notch: return "Top centre (in the notch)"
        case .left:  return "Top left, under the menu bar"
        case .right: return "Top right, under the menu bar"
        }
    }
    static var current: SparrowPosition {
        SparrowPosition(rawValue: UserDefaults.standard.string(forKey: "islandPosition") ?? "") ?? .right
    }
}

struct AppearanceSettings: View {
    @ObservedObject var state: AppState
    @AppStorage("islandPosition") private var position = "right"
    @State private var startPosition = SparrowPosition.current.rawValue

    var body: some View {
        GroupBox("Look & position") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Glass look (see-through background)", isOn: $state.glassStyle)
                HStack {
                    Toggle("Show Zuffi on screen (a little pet you can drag anywhere)", isOn: Binding(
                        get: { PetController.shared.isShown },
                        set: { $0 ? PetController.shared.show() : PetController.shared.hide() }))
                }
                Button("Open Today — meetings & tasks") { TodayWindow.shared.show() }
                Picker("Where Zuffi sits", selection: $position) {
                    ForEach(SparrowPosition.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: position) { _, _ in UserDefaults.standard.removeObject(forKey: "islandOrigin") }
                HStack {
                    Text("Tip: drag Zuffi anywhere — drop it at the left or right edge to park it there.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                    Button("Put Zuffi back at the top") { IslandDrag.resetPosition() }.controlSize(.small)
                }
                if position != startPosition {
                    HStack {
                        Text("Restart Zuffi to move it.").font(.system(size: 11)).foregroundColor(.orange)
                        Button("Restart now") { Self.relaunch() }
                    }
                }
                Text("Shortcut to ask Zuffi anything: \(hotkeyText). Turn it on under Hotkey below.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            .padding(6)
        }
    }

    private var hotkeyText: String {
        let f = NSEvent.ModifierFlags(rawValue: state.hotkeyFlags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        let keys: [UInt16: String] = [45: "N", 49: "Space", 0: "A", 1: "S", 11: "B", 40: "K", 46: "M", 31: "O", 35: "P"]
        return s + (keys[state.hotkeyCode] ?? "key \(state.hotkeyCode)")
    }

    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.8; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }
}


// MARK: - Which microphone to listen with
/// Bluetooth headphones (AirPods…) switch to low "phone call" sound — and pause for a second or two — whenever
/// their microphone is opened. So when the Mac has its own mic, Zuffi listens with that one, and her voice stays
/// clear and instant in your headphones.
enum MicPick {
    nonisolated static func defaultInput() -> AudioDeviceID {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }
    nonisolated static func transport(_ id: AudioDeviceID) -> UInt32 {
        var t = UInt32(0), size = UInt32(MemoryLayout<UInt32>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &t)
        return t
    }
    nonisolated static func isBluetooth(_ id: AudioDeviceID) -> Bool {
        let t = transport(id)
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }
    nonisolated static func builtInInput() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr, size > 0 else { return nil }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return nil }
        for id in ids where transport(id) == kAudioDeviceTransportTypeBuiltIn {
            var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var ss = UInt32(0)
            if AudioObjectGetPropertyDataSize(id, &sa, 0, nil, &ss) == noErr, ss > 0 { return id }
        }
        return nil
    }
    /// Is her voice going into headphones (Bluetooth, wired, or the headphone jack) rather than the Mac's speakers?
    nonisolated static var outputIsHeadphones: Bool {
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return false }
        if isBluetooth(id) || transport(id) == kAudioDeviceTransportTypeUSB { return true }
        var src = UInt32(0), ss = UInt32(MemoryLayout<UInt32>.size)
        var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDataSource, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(id, &sa, 0, nil, &ss, &src) == noErr { return src == 0x6864706E }      // 'hdpn' — wired headphones
        return false
    }
    /// True when listening now would open a Bluetooth headset's mic.
    nonisolated static var wouldUseBluetooth: Bool { isBluetooth(defaultInput()) && builtInInput() == nil }

    /// Point the listening engine at the Mac's own mic when the default one is Bluetooth.
    nonisolated static func apply(_ node: AVAudioInputNode) {
        guard isBluetooth(defaultInput()), var mac = builtInInput(), let au = node.audioUnit else { return }
        let r = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &mac, UInt32(MemoryLayout<AudioDeviceID>.size))
        appendAppLog("voice.log", r == noErr ? "headphones are Bluetooth — listening with the Mac's own mic (keeps her voice clear)" : "couldn't switch to the Mac's mic (\(r))")
    }
}
