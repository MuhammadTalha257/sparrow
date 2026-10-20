import Foundation
import AppKit
import AVFoundation
import Speech
import ScreenCaptureKit
import CoreMedia

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


// =====================================================================
// MARK: - Screen recording ("Zuffi, record my screen" / "stop recording")
// Records the whole screen (with the Mac's sound) to Movies → Zuffi recordings. Zuffi hides itself from the video.
// =====================================================================
/// Not tied to the main thread: ScreenCaptureKit hands back its objects off the main actor.
final class ScreenRecorder: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    static let shared = ScreenRecorder()
    private let lock = NSLock()
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var fileURL: URL?
    private var startedAt: Date?
    var isRecording: Bool { lock.withLock { stream != nil } }

    func start() async -> String {
        if isRecording { return "I’m already recording your screen. Say “stop recording” when you’re done." }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let mainID = CGMainDisplayID()
            guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else { return "I couldn’t find a screen to record." }
            let me = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
            let cfg = SCStreamConfiguration()
            if let mode = CGDisplayCopyDisplayMode(display.displayID) { cfg.width = mode.pixelWidth; cfg.height = mode.pixelHeight }
            else { cfg.width = display.width * 2; cfg.height = display.height * 2 }
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            cfg.showsCursor = true
            cfg.capturesAudio = true
            let dir = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Zuffi recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
            let file = dir.appendingPathComponent("Screen recording \(f.string(from: Date())).mov")
            let rc = SCRecordingOutputConfiguration()
            rc.outputURL = file
            rc.outputFileType = .mov
            rc.videoCodecType = .hevc
            let out = SCRecordingOutput(configuration: rc, delegate: self)
            let s = SCStream(filter: filter, configuration: cfg, delegate: nil)
            try s.addRecordingOutput(out)
            try await s.startCapture()
            lock.withLock { stream = s; output = out; fileURL = file; startedAt = Date() }
            let name = file.lastPathComponent
            Task { @MainActor in appendAppLog("screen.log", "recording to \(name)") }
            return "Recording your screen. Say “Zuffi, stop recording” or press Stop when you’re done."
        } catch {
            let msg = error.localizedDescription
            Task { @MainActor in appendAppLog("screen.log", "start failed: \(msg)") }
            return "I couldn’t record the screen yet. Allow Zuffi in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
        }
    }

    func stop() async -> String {
        let (s, o, u, t): (SCStream?, SCRecordingOutput?, URL?, Date?) = lock.withLock {
            let r = (stream, output, fileURL, startedAt); stream = nil; output = nil; return r
        }
        guard let s else { return "I’m not recording the screen right now." }
        try? await s.stopCapture()
        if let o { try? s.removeRecordingOutput(o) }
        let mins = Int(Date().timeIntervalSince(t ?? Date()) / 60)
        guard let u else { return "Stopped." }
        try? await Task.sleep(nanoseconds: 600_000_000)   // let the file finish writing
        await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        return "Saved your screen recording\(mins > 0 ? " (\(mins) min)" : "") in Movies → Zuffi recordings."
    }

    func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {}
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        let msg = error.localizedDescription
        Task { @MainActor in appendAppLog("screen.log", "failed: \(msg)") }
    }
}

// =====================================================================
// MARK: - Meeting & call detection
// Every few seconds Zuffi looks at the meeting apps that are open (Zoom, Teams, Google Meet in a browser, FaceTime,
// WhatsApp, Slack huddles, Webex). When a call starts she asks once: “Take notes?” — and when the call ends she
// stops the notes by herself and shows the summary. Nothing is recorded without your yes.
// =====================================================================
@MainActor
final class MeetingWatcher {
    static let shared = MeetingWatcher()
    private var timer: Timer?
    private(set) var current: String?          // the meeting we saw ("Zoom", "Google Meet"…)
    private var askedFor: [String: Date] = [:]
    private var goneSince: Date?
    private var startedByUs = false
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "meetingDetect") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "meetingDetect"); newValue ? start() : stop() }
    }

    func start() {
        guard enabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in MainActor.assumeIsolated { MeetingWatcher.shared.tick() } }
    }
    func stop() { timer?.invalidate(); timer = nil }

    /// The meeting on screen right now, if any.
    static func detect() -> String? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in info {
            let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
            let name = (w[kCGWindowName as String] as? String ?? "").lowercased()
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 || owner.contains("zoom") else { continue }
            if owner.contains("zoom") && (name.contains("zoom meeting") || name.contains("zoom webinar") || name == "meeting") { return "Zoom" }
            if owner.contains("teams") && (name.contains("meeting") || name.contains("call") || name.contains("| compact")) { return "Teams" }
            if name.hasPrefix("meet - ") || name.contains("google meet") && !name.contains("start") { return "Google Meet" }
            if owner == "facetime" && !name.isEmpty && name != "facetime" { return "FaceTime" }
            if owner.contains("whatsapp") && (name.contains("voice call") || name.contains("video call") || name.contains("call with")) { return "WhatsApp call" }
            if owner.contains("slack") && name.contains("huddle") { return "Slack huddle" }
            if owner.contains("webex") && name.contains("meeting") { return "Webex" }
            if owner.contains("discord") && name.contains("voice connected") { return "Discord call" }
        }
        _ = running
        return nil
    }

    private func tick() {
        guard enabled else { return }
        let now = Self.detect()
        if let m = now {
            goneSince = nil
            if current != m {
                current = m
                guard !MeetingNotes.shared.active else { return }
                if let last = askedFor[m], Date().timeIntervalSince(last) < 45 * 60 { return }   // asked recently: don't nag
                askedFor[m] = Date()
                ask(m)
            }
        } else if current != nil {
            if goneSince == nil { goneSince = Date() }
            if let g = goneSince, Date().timeIntervalSince(g) > 20 {      // the call has ended
                current = nil; goneSince = nil
                if MeetingNotes.shared.active && startedByUs {
                    startedByUs = false
                    Task { @MainActor in
                        let r = await MeetingNotes.shared.stop()
                        AppState.shared.noteAction = nil
                        AppState.shared.noteMessage = r
                        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
                    }
                }
            }
        }
    }

    private func ask(_ m: String) {
        let st = AppState.shared
        st.noteIsAlert = false
        st.noteAction = "meeting"
        st.noteMessage = "Looks like you’re in a \(m) call.\nShall I take notes? You get a summary and to-dos when it ends."
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
    }

    /// "Take notes" from the notch.
    func acceptNotes() -> String {
        startedByUs = true
        return MeetingNotes.shared.start()
    }
}
