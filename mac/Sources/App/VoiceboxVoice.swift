import Foundation
import AVFoundation
import NaturalLanguage
import SwiftUI

// =====================================================================
// MARK: - Voicebox voices (offline, 23 languages, your own cloned voice)
//
// Voicebox (free, open source, voicebox.sh) runs its voice models on this Mac
// and listens on 127.0.0.1:17493. When it's running and switched on here, Zuffi
// speaks with the Voicebox voice you pick — no internet, no API key. If Voicebox
// isn't running, Zuffi quietly uses its own built-in voice.
// =====================================================================

@MainActor
final class VoiceboxVoice: NSObject, AVAudioPlayerDelegate {
    static let shared = VoiceboxVoice()
    static let base = URL(string: "http://127.0.0.1:17493")!
    static let languages: Set<String> = ["zh", "en", "ja", "ko", "de", "fr", "ru", "pt", "es", "it", "he", "ar", "da", "el", "fi", "hi", "ms", "nl", "no", "pl", "sv", "sw", "tr"]

    struct Profile: Identifiable, Hashable { let id: String; let name: String; let language: String; let kind: String }

    /// "auto" (VoiceStudio, else Voicebox, if one is running), "voicestudio", "voicebox" or "builtin".
    static var mode: String { UserDefaults.standard.string(forKey: "offlineVoice") ?? (UserDefaults.standard.bool(forKey: "voiceboxVoice") ? "voicebox" : "auto") }
    /// True when an offline voice studio is running and allowed — checked every 30 s, so speaking never waits for it.
    static var enabled: Bool { mode != "builtin" && (shared.studioUp && mode != "voicebox" || shared.boxUp && mode != "voicestudio") }
    static let studioBase = URL(string: "http://127.0.0.1:3900")!

    private(set) var studioUp = false
    private(set) var boxUp = false
    private var watch: Timer?

    func startWatching() {
        guard watch == nil else { return }
        Task { await refreshStatus() }
        watch = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in await VoiceboxVoice.shared.refreshStatus() }
        }
    }

    func refreshStatus() async {
        studioUp = await Self.ping(Self.studioBase.appendingPathComponent(".well-known/voicestudio-speech"))
        boxUp = await Self.ping(Self.base.appendingPathComponent("health"))
    }

    nonisolated static func ping(_ u: URL) async -> Bool {
        let r = URLRequest(url: u, timeoutInterval: 1.2)
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// VoiceStudio voices (your clones and presets).
    func studioVoices() async -> [Profile] {
        let r = URLRequest(url: Self.studioBase.appendingPathComponent("v1/audio/voices"), timeoutInterval: 3)
        guard let (d, _) = try? await URLSession.shared.data(for: r), let j = try? JSONSerialization.jsonObject(with: d) else { return [] }
        let list = (j as? [[String: Any]]) ?? ((j as? [String: Any])?["voices"] as? [[String: Any]]) ?? ((j as? [String: Any])?["data"] as? [[String: Any]]) ?? []
        return list.compactMap { v in
            guard let id = (v["voice_id"] as? String) ?? (v["id"] as? String) else { return nil }
            return Profile(id: id, name: v["name"] as? String ?? id, language: v["language"] as? String ?? "", kind: "voicestudio")
        }
    }

    private var player: AVAudioPlayer?
    private var onEnd: (() -> Void)?
    private var turn = 0

    func running() async -> Bool {
        var r = URLRequest(url: Self.base.appendingPathComponent("health"), timeoutInterval: 1.5)
        r.httpMethod = "GET"
        guard let (_, resp) = try? await URLSession.shared.data(for: r) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    func profiles() async -> [Profile] {
        let r = URLRequest(url: Self.base.appendingPathComponent("profiles"), timeoutInterval: 3)
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let list = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] else { return [] }
        return list.compactMap { p in
            guard let id = p["id"] as? String else { return nil }
            return Profile(id: id, name: p["name"] as? String ?? "Voice", language: p["language"] as? String ?? "en", kind: p["voice_type"] as? String ?? "")
        }
    }

    /// Speaks `text`; returns false (so Zuffi uses its own voice) if Voicebox isn't there.
    func say(_ text: String, ended: @escaping () -> Void) async -> Bool {
        stop()
        turn += 1
        let my = turn
        let m = Self.mode
        if studioUp && (m == "auto" || m == "voicestudio") {
            if await studioSay(text, my: my, ended: ended) { return true }
        }
        guard boxUp && (m == "auto" || m == "voicebox") else { return false }
        var pid = UserDefaults.standard.string(forKey: "voiceboxProfile") ?? ""
        if pid.isEmpty { pid = await profiles().first?.id ?? "" }
        guard !pid.isEmpty else { return false }
        let rec = NLLanguageRecognizer(); rec.processString(text)
        var lang = rec.dominantLanguage?.rawValue.components(separatedBy: "-").first ?? "en"
        if lang == "nb" || lang == "nn" { lang = "no" }
        if !Self.languages.contains(lang) { lang = "en" }
        var body: [String: Any] = ["profile_id": pid, "text": ZuffiExpress.spoken(text), "language": lang, "normalize": true]
        if UserDefaults.standard.object(forKey: "bunnyVoice") as? Bool ?? false {
            body["effects_chain"] = [["type": "pitch_shift", "enabled": true, "params": ["semitones": 4.5]]]
        }
        var r = URLRequest(url: Self.base.appendingPathComponent("generate/stream"), timeoutInterval: 90)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("zuffi", forHTTPHeaderField: "X-Voicebox-Client-Id")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200, d.count > 100, my == turn,
              let p = try? AVAudioPlayer(data: d) else {
            appendAppLog("voice.log", "Voicebox didn't answer — using Zuffi's own voice")
            return false
        }
        p.delegate = self
        p.volume = 0.95
        player = p
        onEnd = ended
        p.play()
        VoiceEngine.shared.audioStartedAt = Date(); VoiceEngine.shared.lipText = text
        ZuffiExpress.face(for: text)
        return true
    }

    /// VoiceStudio (OmniVoice): offline, 600+ languages. The bunny voice is designed with its voice tags.
    private func studioSay(_ text: String, my: Int, ended: @escaping () -> Void) async -> Bool {
        let bunny = UserDefaults.standard.object(forKey: "bunnyVoice") as? Bool ?? true
        let picked = UserDefaults.standard.string(forKey: "voicestudioVoice") ?? ""
        var body: [String: Any] = ["model": "tts-1", "input": ZuffiExpress.omni(text), "voice": picked.isEmpty ? "alloy" : picked, "response_format": "wav"]
        if bunny && picked.isEmpty { body["instructions"] = "female, child, very high pitch" }
        var r = URLRequest(url: Self.studioBase.appendingPathComponent("v1/audio/speech"), timeoutInterval: 60)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200, d.count > 100, my == turn,
              let p = try? AVAudioPlayer(data: d) else {
            appendAppLog("voice.log", "VoiceStudio didn't answer")
            return false
        }
        p.delegate = self
        p.volume = 0.95
        player = p
        onEnd = ended
        p.play()
        VoiceEngine.shared.audioStartedAt = Date(); VoiceEngine.shared.lipText = text
        ZuffiExpress.face(for: text)
        return true
    }

    func stop() {
        turn += 1
        player?.stop()
        player = nil
        onEnd = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            let f = VoiceboxVoice.shared.onEnd
            VoiceboxVoice.shared.onEnd = nil
            f?()
        }
    }
}

// MARK: - Settings → Voice

struct VoiceboxSettings: View {
    @AppStorage("offlineVoice") private var mode = "auto"
    @AppStorage("voiceboxProfile") private var profile = ""
    @AppStorage("voicestudioVoice") private var studioVoice = ""
    @AppStorage("bunnyVoice") private var bunny = true
    @State private var studioUp = false
    @State private var boxUp = false
    @State private var list: [VoiceboxVoice.Profile] = []
    @State private var studioList: [VoiceboxVoice.Profile] = []
    @State private var testing = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Cute bunny voice (higher, a little quicker)", isOn: $bunny)
                Divider()
                Text("Offline voice studios").font(.system(size: 13, weight: .semibold))
                Text("Zuffi can speak through a free voice studio running on this Mac — no internet, no API key, many languages, even your own cloned voice. If none is running, Zuffi uses its own voice.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Picker("Speak with", selection: $mode) {
                    Text("Automatic").tag("auto")
                    Text("VoiceStudio").tag("voicestudio")
                    Text("Voicebox").tag("voicebox")
                    Text("Zuffi's own voice").tag("builtin")
                }
                status("VoiceStudio", up: studioUp, note: "600+ languages · voice cloning · voicestudio.sh")
                if !studioList.isEmpty {
                    Picker("VoiceStudio voice", selection: $studioVoice) {
                        Text(bunny ? "Bunny (designed)" : "Default").tag("")
                        ForEach(studioList) { p in Text(p.name).tag(p.id) }
                    }
                }
                status("Voicebox", up: boxUp, note: "23 languages · voice cloning · voicebox.sh")
                if !list.isEmpty {
                    Picker("Voicebox voice", selection: $profile) {
                        Text("First voice").tag("")
                        ForEach(list) { p in Text("\(p.name) · \(p.language)").tag(p.id) }
                    }
                }
                HStack {
                    if !studioUp {
                        Button("Install VoiceStudio") { installStudio() }
                            .help("Opens Terminal with VoiceStudio's official installer so you can see what it does")
                    }
                    if !boxUp { Button("Get Voicebox") { NSWorkspace.shared.open(URL(string: "https://voicebox.sh")!) } }
                    Button("Check again") { Task { await refresh() } }
                    Button(testing ? "…" : "Test") {
                        testing = true
                        Task {
                            await VoiceboxVoice.shared.refreshStatus()
                            if VoiceboxVoice.enabled { VoiceEngine.shared.speak("Hi! I'm Zuffi. This is my offline studio voice.") }
                            else { VoiceEngine.shared.speak("Hi! I'm Zuffi. No voice studio is running, so this is my own voice.") }
                            testing = false
                        }
                    }.disabled(testing)
                }.controlSize(.small)
            }
            .padding(6)
        }
        .task { await refresh() }
    }

    private func status(_ name: String, up: Bool, note: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(up ? Color.green : Color.gray).frame(width: 7, height: 7)
            Text(name).font(.system(size: 12, weight: .semibold))
            Text(up ? "running" : "not running").font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text(note).font(.system(size: 10)).foregroundColor(.secondary)
        }
    }

    private func installStudio() {
        let cmd = "curl -fsSL https://voicestudio.sh/install | sh"
        let script = "tell application \"Terminal\"\n activate\n do script \"\(cmd)\"\nend tell"
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err != nil { NSWorkspace.shared.open(URL(string: "https://github.com/debpalash/VoiceStudio/releases/latest")!) }
    }

    private func refresh() async {
        await VoiceboxVoice.shared.refreshStatus()
        studioUp = VoiceboxVoice.shared.studioUp
        boxUp = VoiceboxVoice.shared.boxUp
        studioList = studioUp ? await VoiceboxVoice.shared.studioVoices() : []
        list = boxUp ? await VoiceboxVoice.shared.profiles() : []
    }
}


// MARK: - Zuffi's feelings in her voice: "hmm", "ahan", "haha", "oh!", a sigh, a little "hmph" — online and offline

@MainActor
enum ZuffiExpress {
    enum Mood { case neutral, happy, laugh, thinking, surprised, annoyed, sad, agree }

    private static let rules: [(pattern: String, mood: Mood, omni: String, spoken: String)] = [
        (#"\b(?:ha){2,}h?\b|\bhe(?:he)+\b|\blol\b|😂|🤣"#, .laugh, "[laughter]", "ha ha ha!"),
        (#"\b(?:a+ha+n+|uh-?huh|mm-?hm+|haan ji|ji haan)\b"#, .agree, "[confirmation-en]", "a-haan,"),
        (#"\bh+m{2,}\b|\bhmm\b"#, .thinking, "Hmmm…", "Hmmm…"),
        (#"\bo+h+\b(?=[!,.…])"#, .surprised, "[surprise-oh]", "Ohh!"),
        (#"\ba+h+\b(?=[!,.…])"#, .surprised, "[surprise-ah]", "Aah!"),
        (#"\bwo+w+\b"#, .surprised, "[surprise-wa] wow", "Wow!"),
        (#"\b(?:ugh+|hmph|tsk)\b|😠|😤"#, .annoyed, "[dissatisfaction-hnn]", "hmph."),
        (#"\*?\bsighs?\b\*?|😮‍💨"#, .sad, "[sigh]", "haahh…"),
    ]

    /// Where each reaction happens in the sentence (letter position) and how she feels there.
    static func cues(_ t: String) -> [(at: Int, mood: Mood)] {
        var out: [(Int, Mood)] = []
        let ns = t as NSString
        for r in rules {
            guard let re = try? NSRegularExpression(pattern: r.pattern, options: [.caseInsensitive]) else { continue }
            for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) { out.append((m.range.location, r.mood)) }
        }
        return out.sorted { $0.0 < $1.0 }
    }

    /// The overall feeling of what she's about to say.
    static func mood(_ t: String) -> Mood {
        if let first = cues(t).first, first.at < 40 { return first.mood }
        let l = t.lowercased()
        if l.range(of: #"\b(sorry|sad|unfortunately|afsos|maaf)\b"#, options: .regularExpression) != nil { return .sad }
        if l.range(of: #"\b(great|yay|awesome|congrat|well done|amazing|shabash|mubarak)\b|🎉|😊|!$"#, options: .regularExpression) != nil { return .happy }
        return .neutral
    }

    private static func apply(_ t: String, _ pick: (Int) -> String) -> String {
        var s = t
        for (i, r) in rules.enumerated() {
            s = s.replacingOccurrences(of: r.pattern, with: pick(i), options: [.regularExpression, .caseInsensitive])
        }
        return s
    }
    /// For OmniVoice (offline studio): written reactions become real sounds (laugh, "mm-hm", sigh, surprise…).
    static func omni(_ t: String) -> String { apply(t) { rules[$0].omni } }
    /// For the built-in voices: spell reactions so they come out as sounds, not as words.
    static func spoken(_ t: String) -> String { apply(t) { rules[$0].spoken } }

    /// Talking speed and pitch for the feeling.
    static func speed(_ m: Mood) -> Double {
        switch m { case .laugh: return 1.08; case .happy: return 1.05; case .sad: return 0.92; case .thinking: return 0.95; case .annoyed: return 0.97; default: return 1 }
    }
    static func pitch(_ m: Mood) -> Float {
        switch m { case .laugh, .happy: return 1.12; case .surprised: return 1.15; case .sad: return 0.9; case .annoyed: return 0.94; default: return 1 }
    }

    /// Aurora's face follows the voice: she laughs on "haha", thinks on "hmm", looks surprised on "oh!", gets cross on "hmph".
    static func face(for text: String, startingNow: Bool = true) {
        let total = Double(text.count) / 14.5
        let m = mood(text)
        if let f = Self.bunny(m), m != .neutral { BunnyFaceCenter.shared.show(f, for: min(6, max(1.6, total * 0.6))) }
        for c in cues(text) {
            guard let f = Self.bunny(c.mood) else { continue }
            let at = Double(c.at) / 14.5
            DispatchQueue.main.asyncAfter(deadline: .now() + at) {
                MainActor.assumeIsolated { if VoiceEngine.shared.speaking { BunnyFaceCenter.shared.show(f, for: 1.8) } }
            }
        }
    }
    static func bunny(_ m: Mood) -> BunnyMood? {
        switch m {
        case .laugh: return .laugh
        case .happy, .agree: return .happy
        case .thinking: return .thinking
        case .surprised: return .surprised
        case .annoyed: return .cross
        case .sad: return .sad
        case .neutral: return nil
        }
    }
}
