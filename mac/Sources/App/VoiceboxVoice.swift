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
    static var mode: String { UserDefaults.standard.string(forKey: "offlineVoice") ?? (UserDefaults.standard.bool(forKey: "voiceboxVoice") ? "voicebox" : "builtin") }
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
    private let clips = ClipQueue()
    func say(_ text: String, ended: @escaping () -> Void) async -> Bool {
        stop()
        turn += 1
        let my = turn
        let m = Self.mode
        let pieces = ClipQueue.pieces(text)
        // She starts with the first short phrase while the next ones are made — no waiting for the whole answer.
        if studioUp && (m == "auto" || m == "voicestudio") {
            if await clips.play(pieces, make: { [weak self] t in await self?.studioClip(t) }, ended: ended) { return my == turn }
        }
        guard my == turn, boxUp && (m == "auto" || m == "voicebox") else { return false }
        var pid = UserDefaults.standard.string(forKey: "voiceboxProfile") ?? ""
        if pid.isEmpty { pid = await profiles().first?.id ?? "" }
        guard !pid.isEmpty, my == turn else { return false }
        let profile = pid
        if await clips.play(pieces, make: { [weak self] t in await self?.boxClip(t, profile: profile) }, ended: ended) { return true }
        appendAppLog("voice.log", "Voicebox didn't answer — using Zuffi's own voice")
        return false
    }

    private func boxClip(_ text: String, profile: String) async -> Data? {
        let rec = NLLanguageRecognizer(); rec.processString(text)
        var lang = rec.dominantLanguage?.rawValue.components(separatedBy: "-").first ?? "en"
        if lang == "nb" || lang == "nn" { lang = "no" }
        if !Self.languages.contains(lang) { lang = "en" }
        var body: [String: Any] = ["profile_id": profile, "text": ZuffiExpress.spoken(text), "language": lang, "normalize": true]
        if UserDefaults.standard.object(forKey: "bunnyVoice") as? Bool ?? false {
            body["effects_chain"] = [["type": "pitch_shift", "enabled": true, "params": ["semitones": 4.5]]]
        }
        var r = URLRequest(url: Self.base.appendingPathComponent("generate/stream"), timeoutInterval: 60)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.setValue("zuffi", forHTTPHeaderField: "X-Voicebox-Client-Id")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200, d.count > 100 else { return nil }
        return d
    }

    /// VoiceStudio (OmniVoice): offline, 600+ languages. The bunny voice is designed with its voice tags.
    private func studioClip(_ text: String) async -> Data? {
        let bunny = UserDefaults.standard.object(forKey: "bunnyVoice") as? Bool ?? true
        let picked = UserDefaults.standard.string(forKey: "voicestudioVoice") ?? ""
        var body: [String: Any] = ["model": "tts-1", "input": ZuffiExpress.omni(text), "voice": picked.isEmpty ? "alloy" : picked, "response_format": "wav"]
        if bunny && picked.isEmpty {
            let m = ZuffiExpress.mood(text)
            body["instructions"] = m == .cry || m == .sad ? "female, young adult, low pitch, whisper" : m == .shout || m == .excited ? "female, young adult, high pitch" : "female, young adult, moderate pitch"
        }
        var r = URLRequest(url: Self.studioBase.appendingPathComponent("v1/audio/speech"), timeoutInterval: 45)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200, d.count > 100 else {
            appendAppLog("voice.log", "VoiceStudio didn't answer"); return nil
        }
        return d
    }

    func stop() {
        turn += 1
        clips.stop()
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
    @AppStorage("offlineVoice") private var mode = "builtin"
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
    enum Mood { case neutral, happy, laugh, thinking, surprised, annoyed, sad, agree, angry, cry, shout, excited }

    private static let rules: [(pattern: String, mood: Mood, omni: String, spoken: String)] = [
        (#"\b(?:ha){2,}h?\b|\bhe(?:he)+\b|\blol\b|😂|🤣"#, .laugh, "[laughter]", "ha ha ha!"),
        (#"\b(?:a+ha+n+|uh-?huh|mm-?hm+|haan ji|ji haan)\b"#, .agree, "[confirmation-en]", "a-haan,"),
        (#"\bh+m{2,}\b|\bhmm\b"#, .thinking, "Hmmm…", "Hmmm…"),
        (#"\bo+h+\b(?=[!,.…])"#, .surprised, "[surprise-oh]", "Ohh!"),
        (#"\ba+h+\b(?=[!,.…])"#, .surprised, "[surprise-ah]", "Aah!"),
        (#"\bwo+w+\b"#, .surprised, "[surprise-wa] wow", "Wow!"),
        (#"\b(?:ugh+|hmph|tsk)\b|😠|😤"#, .annoyed, "[dissatisfaction-hnn]", "hmph."),
        (#"\*?\bsighs?\b\*?|😮‍💨"#, .sad, "[sigh]", "haahh…"),
        (#"\b(?:grr+|argh+|how dare( you)?|i'?m (so )?(angry|furious|mad))\b|😡|🤬"#, .angry, "[dissatisfaction-hnn]", "Grrr!"),
        (#"\*\s*(?:sob+s?|sniff+(?:les?)?|cries|crying)\s*\*|\bboo+ ?hoo+\b|\bwa+a+h+\b|😭|😢"#, .cry, "[sigh] sniff…", "sniff… sniff…"),
        (#"\b(?:ya+y+|woo+ ?hoo+|yippee+|omg)\b|🥳"#, .excited, "[surprise-wa]", "Yaaay!"),
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
        if isShout(t) { return .shout }
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
        switch m { case .laugh: return 1.08; case .happy: return 1.05; case .sad: return 0.92; case .thinking: return 0.95; case .annoyed: return 0.97
        case .angry: return 1.06; case .cry: return 0.86; case .shout: return 1.08; case .excited: return 1.08; default: return 1 }
    }
    static func pitch(_ m: Mood) -> Float {
        switch m { case .laugh, .happy: return 1.12; case .surprised: return 1.15; case .sad: return 0.9; case .annoyed: return 0.94
        case .angry: return 0.92; case .cry: return 0.9; case .shout: return 1.14; case .excited: return 1.16; default: return 1 }
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
    /// Shouting: a word in CAPITALS (not a short acronym) or "!!".
    static func isShout(_ t: String) -> Bool {
        if t.contains("!!") { return true }
        let skip: Set<String> = ["HTML", "JSON", "HTTP", "HTTPS", "UTC", "GMT", "NASA", "UK", "USA", "PDF", "API", "CEO", "FAQ", "ASAP", "OK"]
        return t.split(whereSeparator: { !$0.isLetter }).contains { w in w.count >= 4 && w == w.uppercased() && w.contains { $0.isLetter } && !skip.contains(String(w)) }
    }
    /// Pitch change (cents) for the built-in voice in each feeling.
    static func cents(_ m: Mood) -> Double {
        switch m { case .angry: return -80; case .cry, .sad: return -100; case .shout: return 120; case .excited: return 110; case .laugh: return 60; default: return 0 }
    }
    /// Fish Audio voice cues: each sentence gets the feeling it has.
    static func fish(_ t: String) -> String {
        var out: [String] = []
        t.enumerateSubstrings(in: t.startIndex..<t.endIndex, options: .bySentences) { s, _, _, _ in
            guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return }
            let tag: String
            switch mood(s) {
            case .laugh: tag = "[laughing] "
            case .angry: tag = "[angry] "
            case .annoyed: tag = "[annoyed] "
            case .cry: tag = "[sobbing] "
            case .sad: tag = "[sad] "
            case .shout: tag = "[shouting] "
            case .excited: tag = "[excited] "
            case .surprised: tag = "[surprised] "
            case .happy: tag = "[happy] "
            default: tag = ""
            }
            let clean = s.replacingOccurrences(of: #"\*[^*]{1,20}\*"#, with: "", options: .regularExpression)
            out.append(tag + clean)
        }
        return out.isEmpty ? t : out.joined(separator: " ")
    }
    static func bunny(_ m: Mood) -> BunnyMood? {
        switch m {
        case .angry: return .cross
        case .cry: return .sad
        case .shout: return .surprised
        case .excited: return .happy
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

// MARK: - Fish Audio (online, optional): the most natural voice, with real laughing, crying, anger and shouting

/// Uses your own Fish Audio key (Settings → AI models → Her voice). Offline, or without a key, Zuffi's own voice speaks.
@MainActor
final class FishVoice: NSObject, AVAudioPlayerDelegate {
    static let shared = FishVoice()
    static var key: String { KeychainStore.shared.get("fish-api-key") ?? "" }
    /// Switched off: online voices wait for the whole sentence to come back over the internet, which sounded slow and choppy.
    static var usable: Bool { false }
    private var player: AVAudioPlayer?
    private var onEnd: (() -> Void)?
    private var turn = 0

    private let clips = ClipQueue()
    func say(_ text: String, ended: @escaping () -> Void) async -> Bool {
        stop()
        // The first short phrase is made and played at once; the rest is made while she talks.
        return await clips.play(ClipQueue.pieces(text), make: { t in await FishVoice.clip(t) }, ended: ended)
    }
    private static func clip(_ text: String) async -> Data? {
        var body: [String: Any] = ["text": ZuffiExpress.fish(text), "format": "mp3", "mp3_bitrate": 128, "latency": "balanced", "normalize": true]
        let voice = UserDefaults.standard.string(forKey: "fishVoiceId") ?? ""
        if !voice.isEmpty { body["reference_id"] = voice }
        body["prosody"] = ["speed": ZuffiExpress.speed(ZuffiExpress.mood(text))]
        var r = URLRequest(url: URL(string: "https://api.fish.audio/v1/tts")!, timeoutInterval: 20)
        r.httpMethod = "POST"
        r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { appendAppLog("voice.log", "Fish Audio: no answer"); return nil }
        guard (resp as? HTTPURLResponse)?.statusCode == 200, d.count > 200 else {
            appendAppLog("voice.log", "Fish Audio failed (\((resp as? HTTPURLResponse)?.statusCode ?? 0))"); return nil
        }
        return d
    }
    func stop() { turn += 1; clips.stop(); player?.stop(); player = nil; onEnd = nil }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in let f = FishVoice.shared.onEnd; FishVoice.shared.onEnd = nil; f?() }
    }
}


// MARK: - Speaking in pieces: the first short phrase plays at once, the next is made while she talks
@MainActor
final class ClipQueue: NSObject, AVAudioPlayerDelegate {
    private var turn = 0
    private var player: AVAudioPlayer?
    private var finished: CheckedContinuation<Void, Never>?

    /// A short first phrase (so her voice starts right away), then whole sentences of a comfortable length.
    static func pieces(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { s, _, _, _ in
            if let s = s?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { sentences.append(s) }
        }
        if sentences.isEmpty { sentences = [text] }
        var out: [String] = []
        // split a long first sentence at its first pause (or after a few words)
        let first = sentences.removeFirst()
        if first.count > 48 {
            let chars = Array(first)
            var cut: Int? = nil
            for i in 8..<min(chars.count - 6, 60) where ",;:—–".contains(chars[i]) { cut = i + 1; break }
            if cut == nil { for i in stride(from: min(chars.count - 6, 38), to: 12, by: -1) where chars[i] == " " { cut = i; break } }
            if let c = cut {
                out.append(String(chars[..<c]).trimmingCharacters(in: .whitespaces))
                out.append(String(chars[c...]).trimmingCharacters(in: .whitespaces))
            } else { out.append(first) }
        } else { out.append(first) }
        var cur = ""
        for s in sentences {
            if cur.isEmpty { cur = s } else if cur.count + s.count < 170 { cur += " " + s } else { out.append(cur); cur = s }
        }
        if !cur.isEmpty { out.append(cur) }
        // cloud voices take at most ~200 letters at a time: split very long sentences at a comma or space
        var fit: [String] = []
        for var p in out {
            while p.count > 190 {
                let head = String(p.prefix(190))
                let cut = head.lastIndex(where: { ",;:".contains($0) }) ?? head.lastIndex(of: " ") ?? head.endIndex
                let a = String(p[..<cut]).trimmingCharacters(in: .whitespaces)
                fit.append(a.isEmpty ? head : a)
                p = String(p[(a.isEmpty ? head.endIndex : cut)...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
            }
            if !p.isEmpty { fit.append(p) }
        }
        return fit.filter { !$0.isEmpty }
    }

    /// Plays the pieces in order. Returns false only if the very first piece couldn't be made.
    func play(_ pieces: [String], make: @escaping @MainActor (String) async -> Data?, ended: @escaping () -> Void) async -> Bool {
        stop()
        turn += 1
        let my = turn
        guard let firstText = pieces.first else { return false }
        let ahead: Task<Data?, Never>? = pieces.count > 1 ? Task { @MainActor in await make(pieces[1]) } : nil
        guard let d0 = await make(firstText), my == turn, let p0 = try? AVAudioPlayer(data: d0) else { ahead?.cancel(); return false }
        start(p0, firstText)
        Task { @MainActor in
            var next = ahead
            var i = 1
            while i < pieces.count {
                await self.waitForEnd(my)
                guard my == self.turn else { return }
                let d = await next?.value
                guard my == self.turn else { return }
                next = i + 1 < pieces.count ? { let t = pieces[i + 1]; return Task { @MainActor in await make(t) } }() : nil
                if let d, let p = try? AVAudioPlayer(data: d) { self.start(p, pieces[i]) }
                i += 1
            }
            await self.waitForEnd(my)
            guard my == self.turn else { return }
            self.player = nil
            ended()
        }
        return true
    }

    private func start(_ p: AVAudioPlayer, _ text: String) {
        p.delegate = self
        p.volume = ZuffiExpress.mood(text) == .shout ? 1.0 : 0.95
        player = p
        p.play()
        VoiceEngine.shared.audioStartedAt = Date()          // her lips follow this piece's words
        VoiceEngine.shared.lipText = text.replacingOccurrences(of: #"\[[^\]]{1,24}\]"#, with: "", options: .regularExpression)
        ZuffiExpress.face(for: text)
    }

    private func waitForEnd(_ my: Int) async {
        guard my == turn, let p = player, p.isPlaying else { return }
        await withCheckedContinuation { c in finished = c }
    }

    func stop() {
        turn += 1
        player?.stop(); player = nil
        if let c = finished { finished = nil; c.resume() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in if let c = self.finished { self.finished = nil; c.resume() } }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in if let c = self.finished { self.finished = nil; c.resume() } }
    }
}


// MARK: - Her AI voice (Groq · Orpheus): the most human-sounding, fast, uses the Groq key you already have
@MainActor
final class GroqVoice {
    static let shared = GroqVoice()
    static let voices: [(id: String, label: String)] = [
        ("diana", "Diana — warm"), ("hannah", "Hannah — bright"), ("autumn", "Autumn — soft"),
        ("austin", "Austin — friendly (male)"), ("daniel", "Daniel — calm (male)"), ("troy", "Troy — deep (male)"),
    ]
    static var key: String { KeychainStore.shared.get("groq-api-key") ?? "" }
    /// "ai" (default when you have a Groq key) or "builtin" (offline voice only).
    static var wanted: Bool { (UserDefaults.standard.string(forKey: "voiceEngine") ?? "ai") != "builtin" }
    static var usable: Bool { wanted && !key.isEmpty && NetStatus.shared.online && Date() > shared.restUntil }
    var lastError = ""
    private var restUntil = Date.distantPast
    private let clips = ClipQueue()

    func say(_ text: String, ended: @escaping () -> Void) async -> Bool {
        stop()
        return await clips.play(ClipQueue.pieces(text), make: { t in await GroqVoice.shared.clip(t) }, ended: ended)
    }
    func stop() { clips.stop() }

    /// Her feelings as a voice direction for this sentence.
    private static func direction(_ t: String) -> String {
        switch ZuffiExpress.mood(t) {
        case .happy, .laugh, .excited: return "[cheerful] "
        case .sad, .cry: return "[whisper] "
        default: return ""
        }
    }

    func clip(_ text: String) async -> Data? {
        let clean = text.replacingOccurrences(of: #"\[[^\]]{1,24}\]|\*[^*]{1,24}\*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let voice = UserDefaults.standard.string(forKey: "groqVoice") ?? "diana"
        let body: [String: Any] = ["model": "canopylabs/orpheus-v1-english", "voice": voice,
                                   "input": String((Self.direction(clean) + clean).prefix(200)), "response_format": "wav"]
        var r = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/speech")!, timeoutInterval: 12)
        r.httpMethod = "POST"
        r.setValue("Bearer \(Self.key)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { appendAppLog("voice.log", "AI voice: no answer"); return nil }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200, d.count > 400 else {
            let msg = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]).flatMap { ($0["error"] as? [String: Any])?["message"] as? String } ?? ""
            lastError = code == 400 && msg.lowercased().contains("terms") ? "Open console.groq.com → Playground → pick “Orpheus” once and accept its terms, then try again."
                : code == 429 ? "The AI voice has reached its free limit for now — the offline voice speaks meanwhile." : "AI voice error \(code). \(msg.prefix(120))"
            appendAppLog("voice.log", "AI voice failed (\(code)): \(msg.prefix(160))")
            // don't keep trying (and waiting) on every sentence: rest it a while, the offline voice takes over
            restUntil = Date().addingTimeInterval(code == 429 ? 600 : code == 400 || code == 401 || code == 403 ? 3600 : 60)
            return nil
        }
        lastError = ""
        return d
    }
}
