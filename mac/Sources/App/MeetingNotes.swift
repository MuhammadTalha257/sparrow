import Foundation
import AppKit

/// "Sparrow, start meeting notes" … "Sparrow, stop meeting notes":
/// Sparrow writes down everything said, then saves tidy notes (summary, decisions, action items)
/// to Apple Notes and to its memory.
@MainActor
final class MeetingNotes {
    static let shared = MeetingNotes()
    private(set) var active = false
    private var started = Date()
    private var lines: [String] = []

    func start() -> String {
        guard !active else { return "I'm already taking notes. Say “Sparrow, stop meeting notes” when you're done." }
        active = true; started = Date(); lines = []
        VoiceEngine.shared.meetingMode = true
        appendAppLog("voice.log", "meeting notes started")
        return "Taking meeting notes now. Say “Sparrow, stop meeting notes” when you're done."
    }

    func add(_ text: String) {
        guard active else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { lines.append(t) }
    }

    func stop() async -> String {
        guard active else { return "I wasn't taking notes. Say “Sparrow, start meeting notes” to begin." }
        active = false
        VoiceEngine.shared.meetingMode = false
        let transcript = lines.joined(separator: "\n")
        guard !transcript.isEmpty else { return "I didn't hear anything to write down." }
        let mins = max(1, Int(Date().timeIntervalSince(started) / 60))
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy, h:mm a"
        let title = "Meeting notes — \(f.string(from: started))"
        let summary = await summarize(transcript) ?? "Transcript (\(mins) min):"
        let body = "\(summary)\n\n— Full transcript —\n\(transcript)"
        // Apple Notes
        let html = "<h2>\(esc(title))</h2>" + body.split(separator: "\n", omittingEmptySubsequences: false).map { "<div>\(esc(String($0)))</div>" }.joined()
        let script = "tell application \"Notes\" to make new note with properties {name:\"\(as(title))\", body:\"\(as(html))\"}"
        let saved = CommandEngine.shared.runAppleScript(script) != nil
        // Sparrow's memory (searchable later: "what did we decide in the meeting on Monday?")
        WebHub.shared.run("window.Sparrow && window.Sparrow.rememberNote && window.Sparrow.rememberNote(\(json(title)), \(json(body)))")
        let points = summary.split(separator: "\n").filter { $0.hasPrefix("•") || $0.hasPrefix("-") }.count
        return saved ? "Done — \(mins) minute meeting saved to Notes\(points > 0 ? " with \(points) key points" : "")."
                     : "I saved the notes in my memory. Allow Sparrow to use Notes (System Settings → Privacy & Security → Automation) to save them there too."
    }

    private func summarize(_ transcript: String) async -> String? {
        guard SmartPlanner.shared.isAvailable else { return nil }
        let prompt = """
        Summarise these meeting notes for the user. Use plain text with short bullet points starting with "• ":
        Summary (2-3 bullets), Decisions, Action items (who → what → when). Skip empty sections. Same language as the notes.

        \(transcript.prefix(24000))
        """
        return await SmartPlanner.shared.complete(prompt)
    }

    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
    private func `as`(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") }
    private func json(_ s: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [s]), encoding: .utf8)).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }
}
