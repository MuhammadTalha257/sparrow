import Foundation
import AppKit
import SwiftUI
import AVFoundation
import Speech
import ApplicationServices

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
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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
        let u = AVSpeechUtterance(string: String(clean.prefix(1200)))
        u.voice = currentVoice()
        let rate = UserDefaults.standard.double(forKey: AssistantPrefs.voiceRate)
        u.rate = Float(rate == 0 ? 0.5 : rate)
        u.pitchMultiplier = 1.0
        u.volume = 0.95
        u.preUtteranceDelay = 0.05
        u.prefersAssistiveTechnologySettings = false
        // Don't listen to ourselves while talking
        if isListening { resumeAfterSpeech = true; pauseRecognition() }
        speaking = true
        synth.speak(u)
    }

    func stopSpeaking() { synth.stopSpeaking(at: .immediate) }

    fileprivate func speechFinished() {
        speaking = false
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

    /// Mic button: listen for one command, no wake word needed.
    func listenOnce() {
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
        node.installTap(onBus: 0, bufferSize: 1024, format: fmt) { buffer, _ in r.append(buffer) }
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
                                 "Safari", "WhatsApp", "Gmail", "YouTube", "Finder", "Visual Studio Code", "volume", "pause", "next song"]
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
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
        var wait = 1.0
        if let cmd = extractCommand(heard), !cmd.isEmpty {
            wait = CommandEngine.shared.looksLikeCommand(cmd) ? 0.4 : 0.9
        } else if oneShot, !heard.isEmpty {
            wait = CommandEngine.shared.looksLikeCommand(heard.lowercased()) ? 0.4 : 0.8
        } else if extractCommand(heard) == "" {
            wait = 0.6   // just "Sparrow"
        }
        silenceTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { _ in
            MainActor.assumeIsolated { VoiceEngine.shared.finishUtterance() }
        }
        if ended { finishUtterance() }
    }

    /// Text after the wake word ("hey sparrow, open chrome" → "open chrome"), "" if only the
    /// wake word was said, nil if the wake word wasn't said at all.
    private func extractCommand(_ said: String) -> String? {
        let lower = said.lowercased()
        for wake in ["sparrow's", "sparrows", "sparrow", "sparro", "sparo", "spero", "spar row", "barrow", "sorrow"] {
            if let r = lower.range(of: wake, options: .backwards) {
                return String(lower[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,.!?"))
            }
        }
        return nil
    }

    private func finishUtterance() {
        silenceTimer?.invalidate()
        let said = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let wasOneShot = oneShot
        if !said.isEmpty { appendAppLog("voice.log", "heard: \(said)") }
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

        guard let command else { return }
        if command.isEmpty {
            // Like Siri: a quick chirp, the sparrow pops out and listens for the command.
            SoundEngine.shared.play("question")
            NotificationCenter.default.post(name: .hookReveal, object: nil)
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
            oneShot = true
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
    static func run(_ text: String, spoken: Bool) async {
        let state = AppState.shared
        // Voice: everyday commands run instantly without opening the chat.
        if spoken, let reply = await CommandEngine.shared.handle(text) {
            let actionWords = ["Opening", "Closing", "Playing", "Paused", "Next", "Previous", "Volume", "Muted",
                               "Sound back", "Searching", "Locking", "Dark mode", "Light mode", "Select an area"]
            if actionWords.contains(where: { reply.hasPrefix($0) }) {
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
        state.chatHistory.append(ChatMessage(role: .user, content: text))
        state.stateOverride = .thinking
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
        let before = state.chatHistory.count
        await AIService.shared.chat(query: text, context: nil, state: state)
        if spoken && UserDefaults.standard.bool(forKey: AssistantPrefs.speakReplies),
           state.chatHistory.count > before, let last = state.chatHistory.last, last.role == .assistant {
            VoiceEngine.shared.speak(last.content)
        }
    }

    static func start() {
        AssistantPrefs.registerDefaults()
        Briefing.shared.start()
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

    func greet() async {
        lastGreet = Date(); lastPeriod = Self.period()
        let text = await composeGreeting()
        let state = AppState.shared
        state.noteMessage = text
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
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
        text += " " + (await Planner.shared.summary())
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
        // Approximate location from the internet connection (no permission prompt).
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
                        Text("Only basic voices are installed, so Sparrow may sound robotic.")
                            .font(.system(size: 11)).foregroundColor(.orange)
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
        SparrowPosition(rawValue: UserDefaults.standard.string(forKey: "islandPosition") ?? "") ?? .notch
    }
}

struct AppearanceSettings: View {
    @ObservedObject var state: AppState
    @AppStorage("islandPosition") private var position = "notch"
    @State private var startPosition = SparrowPosition.current.rawValue

    var body: some View {
        GroupBox("Look & position") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Glass look (see-through background)", isOn: $state.glassStyle)
                Picker("Where Sparrow sits", selection: $position) {
                    ForEach(SparrowPosition.allCases) { Text($0.label).tag($0.rawValue) }
                }
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
