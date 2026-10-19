import Foundation
import AppKit
import AVFoundation
import Speech

/// "Zuffi, start meeting notes" … "Zuffi, stop meeting notes":
/// Zuffi records the whole meeting (so no words are lost between listening sessions), then writes an accurate
/// transcript — Groq Whisper / Gemini / OpenAI when online, the Mac's own recogniser offline — and tidy notes
/// (summary, decisions, action items) into Apple Notes and her memory. The live words are kept as a backup.
@MainActor
final class MeetingNotes {
    static let shared = MeetingNotes()
    private(set) var active = false
    private var started = Date()
    private var lines: [String] = []
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    func start() -> String {
        guard !active else { return "I'm already taking notes. Say “Zuffi, stop meeting notes” when you're done." }
        active = true; started = Date(); lines = []
        VoiceEngine.shared.meetingMode = true
        startRecording()
        appendAppLog("voice.log", "meeting notes started (recording: \(recorder != nil))")
        return "Taking meeting notes now. Say “Zuffi, stop meeting notes” when you're done."
    }

    func add(_ text: String) {
        guard active else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { lines.append(t) }
    }

    private func startRecording() {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zuffi/Meetings", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = dir.appendingPathComponent("meeting-\(f.string(from: Date())).m4a")
        // 16 kHz mono AAC: clear for speech and small (~15 MB an hour), well under the transcription limits.
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
                                       AVEncoderBitRateKey: 32000, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        do {
            let r = try AVAudioRecorder(url: url, settings: settings)
            if r.record() { recorder = r; fileURL = url }
        } catch {
            appendAppLog("voice.log", "meeting recording failed: \(error.localizedDescription)")
        }
    }

    func stop() async -> String {
        guard active else { return "I wasn't taking notes. Say “Zuffi, start meeting notes” to begin." }
        active = false
        VoiceEngine.shared.meetingMode = false
        recorder?.stop(); recorder = nil
        let url = fileURL; fileURL = nil
        let live = lines.joined(separator: "\n")
        let mins = max(1, Int(Date().timeIntervalSince(started) / 60))
        // Let the person know it's working (a long meeting takes a few seconds to write up).
        AppState.shared.noteMessage = "Writing up your \(mins) minute meeting…"
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)

        var transcript = live
        if let url {
            let t0 = Date()
            if let t = await transcribe(url), t.count >= min(40, max(1, live.count / 3)) { transcript = t }
            appendAppLog("voice.log", String(format: "meeting transcript: %d chars from the recording in %.1fs (live had %d)", transcript.count, Date().timeIntervalSince(t0), live.count))
            try? FileManager.default.removeItem(at: url)   // the audio isn't kept once it's written down
        }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "I didn't hear anything to write down." }
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy, h:mm a"
        let title = "Meeting notes — \(f.string(from: started))"
        let summary = await summarize(transcript) ?? "Transcript (\(mins) min):"
        let body = "\(summary)\n\n— Full transcript —\n\(transcript)"
        // Apple Notes
        let html = "<h2>\(esc(title))</h2>" + body.split(separator: "\n", omittingEmptySubsequences: false).map { "<div>\(esc(String($0)))</div>" }.joined()
        let script = "tell application \"Notes\" to make new note with properties {name:\"\(asq(title))\", body:\"\(asq(html))\"}"
        let saved = CommandEngine.shared.runAppleScript(script) != nil
        // Zuffi's memory (searchable later: "what did we decide in the meeting on Monday?")
        WebHub.shared.run("window.Sparrow && window.Sparrow.rememberNote && window.Sparrow.rememberNote(\(json(title)), \(json(body)))")
        let points = summary.split(separator: "\n").filter { $0.hasPrefix("•") || $0.hasPrefix("-") }.count
        return saved ? "Done — \(mins) minute meeting saved to Notes\(points > 0 ? " with \(points) key points" : "")."
                     : "I saved the notes in my memory. Allow Zuffi to use Notes (System Settings → Privacy & Security → Automation) to save them there too."
    }

    // MARK: transcription (best available first)

    private func transcribe(_ url: URL) async -> String? {
        guard let data = try? Data(contentsOf: url), data.count > 4000 else { return nil }
        let mb = Double(data.count) / 1_048_576
        if NetStatus.shared.online {
            if mb < 24, let k = KeychainStore.shared.get("groq-api-key"), !k.isEmpty,
               let t = await VoiceNotes.whisper("https://api.groq.com/openai/v1/audio/transcriptions", key: k, model: "whisper-large-v3", file: data, name: "meeting.m4a") { return t }
            if mb < 18, let k = KeychainStore.shared.get("gemini-api-key"), !k.isEmpty, let t = await Self.gemini(data, key: k) { return t }
            if mb < 24, let k = KeychainStore.shared.get("openai-api-key"), !k.isEmpty,
               let t = await VoiceNotes.whisper("https://api.openai.com/v1/audio/transcriptions", key: k, model: "whisper-1", file: data, name: "meeting.m4a") { return t }
        }
        return await Self.onDevice(url)
    }

    /// Gemini listens to the whole recording: verbatim, with "Speaker 1 / Speaker 2" when voices change.
    private static func gemini(_ audio: Data, key: String) async -> String? {
        let prompt = "Transcribe this meeting recording word for word in the language spoken. Start a new line each time the speaker changes and label them Speaker 1, Speaker 2… (use a name if someone is clearly addressed by name). No summary, no commentary — only the transcript."
        let body: [String: Any] = [
            "contents": [["role": "user", "parts": [["text": prompt], ["inline_data": ["mime_type": "audio/mp4", "data": audio.base64EncodedString()]]]]],
            "generationConfig": ["temperature": 0.0],
        ]
        var model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
        for attempt in 0..<3 {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else { return nil }
            var req = URLRequest(url: url, timeoutInterval: 180)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            guard let (data, resp) = try? await URLSession.shared.data(for: req) else { continue }
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            if code == 200, let parts = ((o["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            }
            if code == 404 || code == 400, attempt == 0, let pick = try? await AIService.newestGemini(key: key) {
                model = pick; UserDefaults.standard.set(pick, forKey: "geminiResolved"); continue
            }
            if code == 429 || code == 503 || code == 500 { try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 2_000_000_000); continue }
            return nil
        }
        return nil
    }

    /// Offline: the Mac's own recogniser over the whole file (in the language Zuffi listens in).
    private static func onDevice(_ url: URL) async -> String? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              let rec = SFSpeechRecognizer(locale: Locale(identifier: VoiceEngine.listenLocaleID)) ?? SFSpeechRecognizer(),
              rec.isAvailable else { return nil }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        if rec.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        req.addsPunctuation = true
        return await withCheckedContinuation { (c: CheckedContinuation<String?, Never>) in
            final class Once: @unchecked Sendable { var done = false }
            let once = Once()
            _ = rec.recognitionTask(with: req) { @Sendable result, error in
                if once.done { return }
                if let result, result.isFinal { once.done = true; c.resume(returning: result.bestTranscription.formattedString) }
                else if error != nil { once.done = true; c.resume(returning: nil) }
            }
        }
    }

    private func summarize(_ transcript: String) async -> String? {
        guard SmartPlanner.shared.isAvailable else { return nil }
        let prompt = """
        Summarise these meeting notes for the user. Use plain text with short bullet points starting with "• ":
        Summary (2-3 bullets), Decisions, Action items (who → what → when). Skip empty sections. Same language as the notes.
        Only use what is actually in the transcript — never invent names, dates or numbers.

        \(transcript.prefix(30000))
        """
        return await SmartPlanner.shared.complete(prompt)
    }

    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    private func asq(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    private func json(_ s: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [s]), encoding: .utf8)).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
}
