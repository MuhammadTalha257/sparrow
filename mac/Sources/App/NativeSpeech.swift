import Foundation
import AppKit

/// Zuffi's built-in natural voice: the SparrowSpeech helper (sherpa-onnx engine) bundled in the app.
/// English → Kokoro · Urdu / Roman Urdu / Hindi / Punjabi → MMS. Falls back to Apple's voice if anything goes wrong.
@MainActor
final class NativeSpeech {
    static let shared = NativeSpeech()

    private var proc: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var nextId = 0
    private var currentId = 0
    private var startWaiter: CheckedContinuation<Bool, Never>?
    private var onEnd: (() -> Void)?
    private(set) var failures = 0
    private var slowStreak = 0
    private var restarting = false
    private var startedAt = Date.distantPast

    static let voices: [String: (sid: Int, label: String)] = [
        "af_heart": (3, "Heart (warm, American)"), "af_bella": (2, "Bella (bright, American)"), "af_nicole": (6, "Nicole (soft, American)"),
        "bf_emma": (21, "Emma (British)"), "bf_isabella": (22, "Isabella (British)"),
        "am_michael": (16, "Michael (calm, American)"), "bm_george": (26, "George (British)"), "bm_lewis": (27, "Lewis (British)"),
    ]

    /// Things Zuffi says often — prepared in the background so they play instantly.
    static let common = ["Playing.", "Paused.", "Next song.", "Previous song.", "Muted.", "Sound back on.", "Done.",
                         "Opening Spotify.", "Opening Google Chrome.", "Opening Safari.", "Opening WhatsApp.", "Opening Notes.",
                         "Opening Finder.", "Opening Gmail in your browser.", "Opening YouTube in your browser.",
                         "Playing music on Spotify.", "Sorry, I didn't quite catch that. Could you say it again?",
                         "Hmm, I missed that one. Say it once more?", "Saved in your Notes."]

    private var dir: URL? { Bundle.main.resourceURL?.appendingPathComponent("speech") }
    var isAvailable: Bool {
        guard let d = dir else { return false }
        return failures < 3 && FileManager.default.isExecutableFile(atPath: d.appendingPathComponent("SparrowSpeech").path)
            && FileManager.default.fileExists(atPath: d.appendingPathComponent("kokoro").path)
    }

    func start() {
        guard proc?.isRunning != true, isAvailable, let d = dir else { return }
        let p = Process()
        p.executableURL = d.appendingPathComponent("SparrowSpeech")
        p.arguments = [d.path]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice
        outPipe.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in NativeSpeech.shared.received(data) }
        }
        p.terminationHandler = { _ in
            Task { @MainActor in NativeSpeech.shared.died() }
        }
        do {
            try p.run()
            proc = p
            startedAt = Date()
            input = inPipe.fileHandleForWriting
            send(["cmd": "warm", "model": "kokoro", "sid": sid(), "phrases": Self.common])
            appendAppLog("voice.log", "natural voice engine started")
        } catch {
            failures += 1
            appendAppLog("voice.log", "natural voice engine failed to start: \(error.localizedDescription)")
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NativeSpeech.shared.proc?.terminate() }
        }
    }

    private func died() {
        proc = nil; input = nil
        if restarting {
            restarting = false
            // start again right away in the background, so the next sentence is in HER voice (not the Mac's)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated { NativeSpeech.shared.start() } }
        } else { failures += 1 }
        appendAppLog("voice.log", "natural voice engine stopped (\(failures))")
        startWaiter?.resume(returning: false); startWaiter = nil
        let end = onEnd; onEnd = nil; end?()
    }

    private func send(_ o: [String: Any]) {
        guard let input, proc?.isRunning == true, let d = try? JSONSerialization.data(withJSONObject: o) else { return }
        // write(contentsOf:) throws a Swift error if the helper has gone away; the old write(_:) crashed Zuffi instead.
        do { try input.write(contentsOf: d + Data([0x0A])) }
        catch { appendAppLog("voice.log", "natural voice helper gone: \(error.localizedDescription)"); proc = nil; self.input = nil }
    }

    private func received(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let ev = o["ev"] as? String else { continue }
            let id = o["id"] as? Int ?? -1
            switch ev {
            case "start" where id == currentId:
                slowStreak = 0
                startWaiter?.resume(returning: true); startWaiter = nil
            case "end" where id == currentId:
                let end = onEnd; onEnd = nil; end?()
            case "error" where id == currentId:
                appendAppLog("voice.log", "natural voice error: \(o["msg"] ?? "")")
                startWaiter?.resume(returning: false); startWaiter = nil
                onEnd = nil
            case "speed":
                let a = o["audio"] as? Double ?? 0, t = o["took"] as? Double ?? 0
                appendAppLog("voice.log", String(format: "voice speed %@: %.1fs audio in %.2fs", o["model"] as? String ?? "", a, t))
            case "loaded":
                appendAppLog("voice.log", "voice \(o["model"] ?? "") loaded in \(o["ms"] ?? 0) ms")
            default: break
            }
        }
    }

    /// Which voice fits this text: Urdu script, Devanagari, Gurmukhi, Roman Urdu or English.
    static func model(for text: String, lang: String) -> String {
        for u in text.unicodeScalars {
            switch u.value {
            case 0x0A00...0x0A7F: return "pan"
            case 0x0900...0x097F: return "hin"
            case 0x0600...0x06FF: return "urd"
            default: continue
            }
        }
        if ["ur", "hi", "pa"].contains(lang) {
            let roman: Set<String> = ["hai", "hain", "kya", "kia", "aap", "ap", "mein", "main", "nahi", "nahin", "karo", "kar", "ka", "ki", "ke", "ko", "se",
                                      "tha", "thi", "ho", "hum", "tum", "yeh", "ye", "woh", "wo", "acha", "theek", "ji", "shukriya", "kal", "aaj", "baje",
                                      "abhi", "bhi", "lekin", "aur", "sab", "kuch", "bohat", "bahut", "mujhe", "mera", "meri", "tusi", "assi", "haan", "rahi", "raha"]
            let words = text.lowercased().split { !$0.isLetter }.map(String.init)
            if !words.isEmpty, Double(words.filter { roman.contains($0) }.count) / Double(words.count) > 0.18 { return "urd-latn" }
        }
        return "kokoro"
    }

    /// Her voices: each is a natural voice + its own pitch and pace. Her feelings (happy, angry, sad, excited…)
    /// then colour whichever one you pick.
    struct Preset { let id: String; let name: String; let sid: Int; let pitch: Double; let speed: Double }
    static let presets: [Preset] = [
        Preset(id: "sweet", name: "Sweet (Zuffi)", sid: 3, pitch: 200, speed: 1.06),
        Preset(id: "light", name: "Light & airy", sid: 10, pitch: 220, speed: 1.05),
        Preset(id: "bright", name: "Bright & happy", sid: 7, pitch: 120, speed: 1.1),
        Preset(id: "soft", name: "Soft & calm", sid: 6, pitch: 40, speed: 0.96),
        Preset(id: "bold", name: "Bold & strong", sid: 5, pitch: -60, speed: 1.0),
        Preset(id: "warm", name: "Warm & natural", sid: 3, pitch: 0, speed: 1.05),
        Preset(id: "story", name: "Storyteller", sid: 9, pitch: 0, speed: 0.98),
        Preset(id: "british", name: "British", sid: 21, pitch: 60, speed: 1.04),
        Preset(id: "britsoft", name: "British, gentle", sid: 23, pitch: 80, speed: 1.0),
        Preset(id: "deep", name: "Deep & heavy (male)", sid: 17, pitch: -120, speed: 0.97),
        Preset(id: "calm-m", name: "Calm (male)", sid: 16, pitch: 0, speed: 1.02),
        Preset(id: "fun-m", name: "Playful (male)", sid: 18, pitch: 40, speed: 1.08),
        Preset(id: "brit-m", name: "British (male)", sid: 26, pitch: 0, speed: 1.02),
    ]
    static var preset: Preset {
        let id = UserDefaults.standard.string(forKey: "voicePreset") ?? "sweet"
        return presets.first { $0.id == id } ?? presets[0]
    }

    /// A new voice picked: prepare her everyday phrases in it, so they stay instant.
    func rewarm() {
        guard proc?.isRunning == true else { return }
        send(["cmd": "warm", "model": "kokoro", "sid": sid(), "phrases": Self.common])
    }

    private func sid() -> Int {
        let ud = UserDefaults.standard
        if ud.string(forKey: "voicePreset") != nil { return Self.preset.sid }
        if let v = ud.string(forKey: "voiceName"), let s = Self.voices[v] { return s.sid }
        return (ud.string(forKey: AssistantPrefs.voiceGender) ?? "female") == "male" ? 26 : 3
    }

    /// Speaks; returns true once audio has started (false → caller uses Apple's voice). `ended` fires when it's done.
    func say(_ text: String, ended: @escaping () -> Void) async -> Bool {
        start()
        guard proc?.isRunning == true else { return false }
        stop()
        nextId += 1
        currentId = nextId
        let lang = UserDefaults.standard.string(forKey: "sparrowLang") ?? "en"
        let model = Self.model(for: text, lang: lang)
        let rate = UserDefaults.standard.double(forKey: AssistantPrefs.voiceRate)
        let preset = Self.preset
        let speed = (rate == 0 ? 1.0 : max(0.8, min(1.4, rate / 0.5))) * ZuffiExpress.speed(ZuffiExpress.mood(text)) * preset.speed
        onEnd = ended
        let bunny = UserDefaults.standard.object(forKey: "bunnyVoice") as? Bool ?? true
        send(["cmd": "say", "id": currentId, "text": text, "model": model, "sid": sid(), "speed": speed,
                   "pitch": (bunny && preset.id == "sweet" ? 200.0 : preset.pitch) + ZuffiExpress.cents(ZuffiExpress.mood(text))])   // a lighter lift sounds natural, not robotic
        let id = currentId
        // Never wait long: if the first words aren't ready, use the instant voice instead. Just after it starts it is still
        // loading her voice, so it gets longer then — otherwise the first reminder would come out in the Mac's voice.
        let patience: Double = Date().timeIntervalSince(startedAt) < 25 ? 14 : 6
        DispatchQueue.main.asyncAfter(deadline: .now() + patience) {
            MainActor.assumeIsolated {
                if id == NativeSpeech.shared.currentId, let w = NativeSpeech.shared.startWaiter {
                    NativeSpeech.shared.startWaiter = nil
                    NativeSpeech.shared.onEnd = nil
                    NativeSpeech.shared.send(["cmd": "stop"])
                    appendAppLog("voice.log", "natural voice too slow — using the instant voice")
                    // Stop the helper outright, so its late audio can never play on top of the instant voice (two voices at once).
                    NativeSpeech.shared.slowStreak = 0
                    NativeSpeech.shared.restarting = true
                    appendAppLog("voice.log", "natural voice: stopping the helper (it starts again next time)")
                    NativeSpeech.shared.proc?.terminate()
                    w.resume(returning: false)
                }
            }
        }
        return await withCheckedContinuation { c in startWaiter = c }
    }

    func stop() {
        if let w = startWaiter { startWaiter = nil; w.resume(returning: false) }
        onEnd = nil
        send(["cmd": "stop"])
    }
}
