import Foundation
import AppKit
import SwiftUI
import AVFoundation
import Speech
import ApplicationServices
import CoreLocation

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
        UserDefaults.standard.register(defaults: [
            voiceGender: "female", voiceId: "", voiceRate: 0.5, speakReplies: true,
            wakeWord: true, greetEnabled: true, greetWeather: true, userName: "",
            weatherCity: "", readNotes: false,
        ])
    }

    static var displayName: String {
        let custom = (UserDefaults.standard.string(forKey: userName) ?? "").trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty { return custom }
        return NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
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
    private var speaking = false
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
        // Watchdog: if "Sparrow…" listening should be on but isn't (startup race, mic busy,
        // recogniser not ready yet…), start it again. Cheap — runs every 4 seconds.
        Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated { VoiceEngine.shared.watchdog() }
        }
    }

    private var lastAttempt = Date.distantPast

    fileprivate func watchdog() {
        guard UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord),
              !isListening, !speaking, !oneShot,
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
                status = "Sparrow needs Microphone and Speech Recognition: System Settings → Privacy & Security."
            }
            return
        }
        lastAttempt = Date()
        appendAppLog("voice.log", "watchdog: starting \"Sparrow…\" listening")
        startRecognition()
    }

    func restartIfWanted(after delay: TimeInterval) {
        guard UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord), !speaking else { return }
        pauseRecognition()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) { VoiceEngine.shared.startRecognition() }
        }
    }

    // MARK: Languages

    /// What Sparrow listens for. English (India) understands Roman Urdu / Hindi / Punjabi mixed with English best.
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
        let clean = noEmoji.replacingOccurrences(of: "•", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        // Sparrow's built-in natural voice (fast, native). Falls back to Apple's voice instantly if it can't.
        if UserDefaults.standard.object(forKey: "neuralVoice") as? Bool ?? true, NativeSpeech.shared.isAvailable {
            if isListening { resumeAfterSpeech = true; pauseRecognition() }
            speaking = true
            neuralTurn += 1
            let turn = neuralTurn
            let text = String(clean.prefix(1200))
            Task { @MainActor in
                let ok = await NativeSpeech.shared.say(text) {
                    if turn == VoiceEngine.shared.neuralTurn { VoiceEngine.shared.neuralEnded() }
                }
                guard turn == self.neuralTurn else { return }
                if !ok { self.appleSpeak(clean) }
                else {
                    // Safety net: never leave the microphone paused.
                    let secs = 6.0 + Double(text.count) / 9.0
                    DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                        MainActor.assumeIsolated { VoiceEngine.shared.neuralTimeout(turn) }
                    }
                }
            }
            return
        }
        appleSpeak(clean)
    }

    private var neuralTurn = 0
    func neuralEnded() { neuralTurn += 1; speechFinished() }
    fileprivate func neuralTimeout(_ turn: Int) { if turn == neuralTurn, speaking { neuralEnded() } }

    private func appleSpeak(_ clean: String) {
        let u = Self.naturalUtterance(String(clean.prefix(1200)))
        let voice = currentVoice()
        u.voice = voice
        let rate = UserDefaults.standard.double(forKey: AssistantPrefs.voiceRate)
        // Basic voices sound less robotic a touch slower; premium ones at a natural pace.
        let base = Float(rate == 0 ? 0.5 : rate)
        u.rate = voice?.quality == .default ? base * 0.94 : base
        u.pitchMultiplier = voice?.gender == .female ? 1.04 : 0.98
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

    /// Meeting notes: everything heard is written down (only "Sparrow, stop…" is treated as a command).
    var meetingMode = false

    /// Set before speaking a question; Sparrow listens again as soon as it finishes.
    var listenAfterSpeech = false

    fileprivate func speechFinished() {
        speaking = false
        if listenAfterSpeech {
            listenAfterSpeech = false
            resumeAfterSpeech = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { MainActor.assumeIsolated { VoiceEngine.shared.listenOnce() } }
            return
        }
        if resumeAfterSpeech {
            resumeAfterSpeech = false
            if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) { startRecognition() }
        }
    }

    // MARK: Listening

    /// Always-on "Sparrow, …" listening (Settings toggle).
    func setWakeWord(_ on: Bool) {
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

    func pushToTalkDown() {
        guard !pushToTalk else { return }
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
        // a moment for the last word to arrive
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainActor.assumeIsolated { VoiceEngine.shared.finishUtterance() }
        }
    }

    /// Mic button: listen for one command, no wake word needed.
    func listenOnce() {
        // The mic button always wins: stop talking and listen right now.
        if speaking { stopSpeaking(); speaking = false; resumeAfterSpeech = false }
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
                    self.status = "Allow Speech Recognition for Sparrow in System Settings → Privacy & Security."
                    done(false); return
                }
                Self.askMicAuth { mic in
                    Task { @MainActor in
                        if !mic { self.status = "Allow the Microphone for Sparrow in System Settings → Privacy & Security." }
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
        let fmt = node.outputFormat(forBus: 0)
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

    fileprivate func startRecognition() {
        guard !speaking else { resumeAfterSpeech = true; return }
        guard let recognizer, recognizer.isAvailable else {
            status = "Speech recognition isn't ready yet — retrying…"
            appendAppLog("voice.log", "recogniser not available")
            return
        }
        pauseRecognition()
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.contextualStrings = ["Sparrow", "hey Sparrow", "Sparrow open", "open", "close", "Claude", "Spotify", "Chrome",
                                 "Safari", "WhatsApp", "Gmail", "YouTube", "Finder", "Visual Studio Code", "volume", "pause", "next song",
                                 "remind me", "meeting notes", "Wi-Fi", "Bluetooth", "shut down", "restart", "kholo", "chalao", "band karo",
                                 "yaad dilao", "gaana", "awaaz"]
        // "Sparrow…" is listened for privately on this Mac. Once you're talking to Sparrow (after its name, the mic
        // button or the ⌥ key), Apple's sharper online recognition is used when there's internet.
        let sharp = (oneShot || pushToTalk) && NetStatus.shared.online && UserDefaults.standard.object(forKey: "sharpHearing") as? Bool ?? true
        if recognizer.supportsOnDeviceRecognition && !sharp { req.requiresOnDeviceRecognition = true }
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
        status = oneShot ? "Listening…" : "Say \"Sparrow…\" anytime"
        failures = 0
        heard = ""
        generation += 1
        let gen = generation
        task = Self.startTask(recognizer, req) { text, ended in
            Task { @MainActor in VoiceEngine.shared.onPartial(text, ended: ended, gen: gen) }
        }
        appendAppLog("voice.log", "listening started (gen \(gen), oneShot \(oneShot), onDevice \(req.requiresOnDeviceRecognition))")
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
        if let text { heard = text }
        if ended && text == nil && heard.isEmpty {
            // Session ended on its own (timeout / error) with nothing heard: quietly start a new one.
            appendAppLog("voice.log", "session ended empty (gen \(gen))")
            if oneShot { oneShot = false; status = "Didn't catch that. Tap the mic and try again." }
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
            wait = complete(cmd) ? 0.5 : 1.1        // a clear command runs the moment you stop
        } else if oneShot, !heard.isEmpty {
            wait = complete(heard) ? 0.5 : 1.0
        } else if extractCommand(heard) == "" {
            wait = 1.7   // just "Sparrow" — give a moment to say the rest in the same breath
        }
        // Sounds unfinished ("open spotify and…", "phir…")? Keep listening a little longer.
        if heard.lowercased().range(of: #"\b(and|then|also|aur|phir|or|to|the|for|with|ke|ki|ka|start|begin|take|meeting|my)\s*$"#, options: .regularExpression) != nil {
            wait = max(wait, 1.8)
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
        for wake in ["sparrow's", "sparrows", "sparrow", "sparro", "sparo", "spero", "sperro", "spirrow", "sporrow", "spar row",
                     "spa row", "sparrowe", "hey barrow", "barrow", "sorrow", "سپیرو", "स्पैरो"] {
            if let r = lower.range(of: wake, options: .backwards) {
                return String(lower[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            }
        }
        // Close mis-hearings at the very start: "spare open chrome", "sparo, play music"…
        if let r = lower.range(of: #"^(hey |ok |hi )?sp[aeio]r+[oe]w?s?\b[, ]*"#, options: .regularExpression) {
            return String(lower[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
        }
        return nil
    }

    private func finishUtterance() {
        silenceTimer?.invalidate()
        let said = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasOneShot = oneShot
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
            command = said.isEmpty ? nil : said
        } else {
            command = extractCommand(said)
        }
        heard = ""
        // Keep listening for "Sparrow…" afterwards if that's switched on; otherwise stop.
        if wasOneShot { oneShot = false }
        if UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord) { startRecognition() }   // fresh transcript
        else if wasOneShot { stopRecognition(); status = "" }

        guard let command else {
            // Hands-free: no need to say "Sparrow" first — act when it's clearly a request.
            let handsFree = UserDefaults.standard.object(forKey: "handsFree") as? Bool ?? false
            if handsFree, !said.isEmpty, AgentRouter.shared.isClearRequest(said) {
                appendAppLog("voice.log", "hands-free command: \(said)")
                Task { await Assistant.run(said, spoken: true) }
            } else if !said.isEmpty {
                appendAppLog("voice.log", "not for me (no \"Sparrow\"): \(said)")
            }
            return
        }
        if command.isEmpty {
            // Like Siri: a quick chirp, the sparrow pops out and listens for the command.
            SoundEngine.shared.play("question")
            NotificationCenter.default.post(name: .hookReveal, object: nil)
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
            oneShot = true
            startRecognition()          // fresh session with sharper recognition for what comes next
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

    /// A warm "say that again" — then Sparrow listens straight away.
    static func askAgain() {
        let line = notUnderstood.randomElement()!
        AppState.shared.noteMessage = "🐦 " + line
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        VoiceEngine.shared.listenAfterSpeech = true
        VoiceEngine.shared.speak(line)
    }

    static func run(_ text: String, spoken: Bool) async {
        let state = AppState.shared

        // Voice: everyday commands run instantly without opening the chat.
        if spoken, let reply = await AgentRouter.shared.handle(text) {
            let actionWords = ["Opening", "Closing", "Playing", "Paused", "Next", "Previous", "Volume", "Muted",
                               "Sound back", "Searching", "Locking", "Dark mode", "Light mode", "Select an area"]
            NotificationCenter.default.post(name: .petSay, object: reply)
            if actionWords.contains(where: { reply.hasPrefix($0) }), !reply.contains(". ") {
                SoundEngine.shared.play("approve")          // quick chirp = done
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
            } else {
                // Information (time, battery, problems…) is spoken and shown.
                state.noteMessage = reply
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                VoiceEngine.shared.speak(reply)
            }
            return
        }
        if spoken {
            func say(_ reply: String) {
                state.noteMessage = reply
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                NotificationCenter.default.post(name: .petSay, object: reply)
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                VoiceEngine.shared.speak(reply)
            }
            let short = text.split(separator: " ").count <= 6
            // Habits, prayer times, memory, invoices… (Sparrow's offline brain) — instant for short requests
            if short, let reply = await WebHub.shared.ask(text) { say(reply); return }
            // Anything else, any language: the smart planner turns it into actions and answers like a person
            if let plan = await SmartPlanner.shared.plan(text) {
                if plan.commands.isEmpty && plan.say.isEmpty { askAgain(); return }
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
            // Too short or garbled to be a real question, or no AI to ask: a warm "say that again".
            let hasAI = await AIService.shared.resolveProvider(state: state) != nil
            if text.split(separator: " ").count <= 1 || !hasAI {
                askAgain(); return
            }
        }
        state.chatHistory.append(ChatMessage(role: .user, content: text))
        state.stateOverride = .thinking
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
        let before = state.chatHistory.count
        await AIService.shared.chat(query: text, context: nil, state: state)
        if spoken && UserDefaults.standard.bool(forKey: AssistantPrefs.speakReplies),
           state.chatHistory.count > before, let last = state.chatHistory.last, last.role == .assistant {
            VoiceEngine.shared.speak(last.content)
        }
        if let last = state.chatHistory.last, last.role == .assistant {
            NotificationCenter.default.post(name: .petSay, object: last.content)
        }
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

    private func maybeGreet() {
        guard UserDefaults.standard.bool(forKey: AssistantPrefs.greetEnabled) else { return }
        let p = Self.period()
        // Greet once per part of the day, or after 3 hours away.
        guard p != lastPeriod || Date().timeIntervalSince(lastGreet) > 3 * 3600 else { return }
        Task { await greet() }
    }

    /// Called by the morning briefing so the wake greeting doesn't repeat it.
    func markGreeted() { lastGreet = Date(); lastPeriod = Self.period() }
    /// True if Sparrow already said hello (with the day's plan) in the last 20 minutes.
    var greetedRecently: Bool { Date().timeIntervalSince(lastGreet) < 20 * 60 }

    func greet() async {
        lastGreet = Date(); lastPeriod = Self.period()
        let text = await composeGreeting()
        // One-time tip if the Mac only has robotic voices.
        if VoiceEngine.onlyBasicVoices && !UserDefaults.standard.bool(forKey: "voiceTipShown") {
            UserDefaults.standard.set(true, forKey: "voiceTipShown")
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                AppState.shared.noteMessage = "Tip: want me to sound more human? Settings → Voice → “Make Sparrow sound human”. It's free."
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
        text += " " + (await Planner.shared.summary(for: Date(), detailed: false))
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

    private static func location() async -> (lat: Double, lon: Double, city: String)? {
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

    private static func getJSON(_ url: URL) async -> [String: Any]? {
        var req = URLRequest(url: url, timeoutInterval: 6)
        req.setValue("Sparrow", forHTTPHeaderField: "User-Agent")
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

    func setEnabled(_ on: Bool) {
        timer?.invalidate(); timer = nil
        guard on else { return }
        if !Self.hasAccess { Self.askAccess() }
        primed = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { NotificationReader.shared.poll() }
        }
    }

    private func poll() {
        guard Self.hasAccess,
              let nc = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" })
        else { return }
        let appEl = AXUIElementCreateApplication(nc.processIdentifier)
        let windows = Self.children(appEl, attr: kAXWindowsAttribute as String)
        var banners: [String] = []
        for w in windows {
            var texts: [String] = []
            Self.collectTexts(w, into: &texts, depth: 0)
            let joined = texts.filter { !$0.isEmpty }.joined(separator: ". ")
            if !joined.isEmpty { banners.append(joined) }
        }
        // If the full Notification Centre is open there are lots of texts — don't read them all.
        let new = banners.filter { !seen.contains($0) }
        seen = Array((seen + new).suffix(40))
        guard primed else { primed = true; return }
        guard let first = new.first, new.count <= 2, first.count < 400 else { return }
        VoiceEngine.shared.speak("New notification. " + first)
    }

    private static func children(_ el: AXUIElement, attr: String) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success, let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    private static func collectTexts(_ el: AXUIElement, into out: inout [String], depth: Int) {
        guard depth < 12, out.count < 12 else { return }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        if (role as? String) == (kAXStaticTextRole as String) {
            var val: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &val) == .success, let s = val as? String {
                out.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        for c in children(el, attr: kAXChildrenAttribute as String) { collectTexts(c, into: &out, depth: depth + 1) }
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
                        Button("Test") { VoiceEngine.shared.speak("Hi\(AssistantPrefs.displayName.isEmpty ? "" : " \(AssistantPrefs.displayName)"), I'm Sparrow. How can I help?") }
                    }
                    if VoiceEngine.onlyBasicVoices {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Make Sparrow sound human (free, 2 minutes)", systemImage: "sparkles")
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
                    Toggle("Listen for \"Sparrow…\" (say \"Sparrow, open Chrome\")", isOn: $wakeWord)
                        .onChange(of: wakeWord) { _, on in VoiceEngine.shared.setWakeWord(on) }
                    Toggle("Speak answers out loud when I talk to Sparrow", isOn: $speakReplies)
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
                    Toggle("Read new notifications out loud", isOn: $readNotes)
                        .onChange(of: readNotes) { _, on in NotificationReader.shared.setEnabled(on) }
                    if readNotes && !NotificationReader.hasAccess {
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
                    Text("Sparrow reads the notification banners that pop up on your screen. Nothing is sent anywhere.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                .padding(6)
            }
            }

            if parts.contains(.apps) {
            GroupBox("Apps Sparrow can open") {
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
        .help("Talk to Sparrow")
    }
}

// MARK: - Appearance: glass look + where Sparrow sits

struct VisualEffectBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
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
                    Toggle("Show Sparrow on screen (a little pet you can drag anywhere)", isOn: Binding(
                        get: { PetController.shared.isShown },
                        set: { $0 ? PetController.shared.show() : PetController.shared.hide() }))
                }
                Button("Open Today — meetings & tasks") { TodayWindow.shared.show() }
                Picker("Where Sparrow sits", selection: $position) {
                    ForEach(SparrowPosition.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .onChange(of: position) { _, _ in UserDefaults.standard.removeObject(forKey: "islandOrigin") }
                Text("Tip: drag the top bar of the island to put Sparrow anywhere you like.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                if position != startPosition {
                    HStack {
                        Text("Restart Sparrow to move it.").font(.system(size: 11)).foregroundColor(.orange)
                        Button("Restart now") { Self.relaunch() }
                    }
                }
                Text("Shortcut to ask Sparrow anything: \(hotkeyText). Turn it on under Hotkey below.")
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
