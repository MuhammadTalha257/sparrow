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

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "voiceboxVoice") }

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
        var pid = UserDefaults.standard.string(forKey: "voiceboxProfile") ?? ""
        if pid.isEmpty { pid = await profiles().first?.id ?? "" }
        guard !pid.isEmpty else { return false }
        let rec = NLLanguageRecognizer(); rec.processString(text)
        var lang = rec.dominantLanguage?.rawValue.components(separatedBy: "-").first ?? "en"
        if lang == "nb" || lang == "nn" { lang = "no" }
        if !Self.languages.contains(lang) { lang = "en" }
        var body: [String: Any] = ["profile_id": pid, "text": text, "language": lang, "normalize": true]
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
    @AppStorage("voiceboxVoice") private var on = false
    @AppStorage("voiceboxProfile") private var profile = ""
    @AppStorage("bunnyVoice") private var bunny = false
    @State private var running = false
    @State private var list: [VoiceboxVoice.Profile] = []
    @State private var testing = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Cute bunny voice (higher, a little quicker)", isOn: $bunny)
                Divider()
                HStack {
                    Text("Voicebox voices").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Circle().fill(running ? Color.green : Color.gray).frame(width: 7, height: 7)
                    Text(running ? "Voicebox is running" : "Voicebox isn't running").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Text("Offline voices in 23 languages — or your own cloned voice. Free and open source; runs on this Mac, no API key.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Speak with Voicebox when it's running", isOn: $on)
                if !list.isEmpty {
                    Picker("Voice", selection: $profile) {
                        Text("First voice").tag("")
                        ForEach(list) { p in Text("\(p.name) · \(p.language)").tag(p.id) }
                    }
                }
                HStack {
                    if !running { Button("Get Voicebox") { NSWorkspace.shared.open(URL(string: "https://voicebox.sh")!) } }
                    Button("Check again") { Task { await refresh() } }
                    Button(testing ? "…" : "Test") {
                        testing = true
                        Task {
                            let ok = await VoiceboxVoice.shared.say("Hi! I'm Zuffi. This is my Voicebox voice.") {}
                            if !ok { VoiceEngine.shared.speak("Voicebox didn't answer, so this is my own voice.") }
                            testing = false
                        }
                    }.disabled(testing)
                }.controlSize(.small)
            }
            .padding(6)
        }
        .task { await refresh() }
    }

    private func refresh() async {
        running = await VoiceboxVoice.shared.running()
        list = running ? await VoiceboxVoice.shared.profiles() : []
    }
}
