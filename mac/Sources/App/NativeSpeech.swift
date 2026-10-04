import Foundation
import AppKit

/// Sparrow's built-in natural voice: the SparrowSpeech helper (sherpa-onnx engine) bundled in the app.
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

    static let voices: [String: (sid: Int, label: String)] = [
        "af_heart": (3, "Heart (warm, American)"), "af_bella": (2, "Bella (bright, American)"), "af_nicole": (6, "Nicole (soft, American)"),
        "bf_emma": (21, "Emma (British)"), "bf_isabella": (22, "Isabella (British)"),
        "am_michael": (16, "Michael (calm, American)"), "bm_george": (26, "George (British)"), "bm_lewis": (27, "Lewis (British)"),
    ]

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
            input = inPipe.fileHandleForWriting
            send(["cmd": "warm", "model": "kokoro", "sid": sid()])
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
        failures += 1
        appendAppLog("voice.log", "natural voice engine stopped (\(failures))")
        startWaiter?.resume(returning: false); startWaiter = nil
        let end = onEnd; onEnd = nil; end?()
    }

    private func send(_ o: [String: Any]) {
        guard let input, let d = try? JSONSerialization.data(withJSONObject: o) else { return }
        input.write(d + Data([0x0A]))
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

    private func sid() -> Int {
        let ud = UserDefaults.standard
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
        let speed = rate == 0 ? 1.0 : max(0.8, min(1.3, rate / 0.5))
        onEnd = ended
        send(["cmd": "say", "id": currentId, "text": text, "model": model, "sid": sid(), "speed": speed])
        let id = currentId
        // Never wait long: if the first words aren't ready in 4 s, use the instant voice instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            MainActor.assumeIsolated {
                if id == NativeSpeech.shared.currentId, let w = NativeSpeech.shared.startWaiter {
                    NativeSpeech.shared.startWaiter = nil
                    NativeSpeech.shared.onEnd = nil
                    NativeSpeech.shared.send(["cmd": "stop"])
                    appendAppLog("voice.log", "natural voice too slow — using the instant voice")
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
