import Foundation
import AppKit
import ApplicationServices
import SwiftUI
@preconcurrency import Network

// =====================================================================
// MARK: - Agents: Claude Code, Codex and GitHub in Zuffi
//
// Claude Code: a tiny hook script (installed only when you press "Connect") tells Zuffi
// what each session is doing. When Claude asks for permission, Zuffi shows it with
// Deny / Approve / All. If Zuffi isn't running the script does nothing and Claude
// asks in the terminal as usual. A status-line helper passes on how much of your
// 5-hour and weekly limits are used.
// Codex: read from its own session logs (~/.codex/sessions) — replies and limits.
// GitHub: unread notifications through the GitHub CLI (`gh`), if it's installed.
// =====================================================================

// MARK: Local server the hook script talks to (127.0.0.1 only, secret token)

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()
    private var listener: NWListener?
    private let q = DispatchQueue(label: "zuffi.hooks")
    let token: String
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".zuffi", isDirectory: true)

    private init() {
        let f = Self.dir.appendingPathComponent("token")
        if let t = try? String(contentsOf: f, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), t.count >= 32 {
            token = t
        } else {
            token = (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        }
    }

    func start() {
        guard listener == nil else { return }
        try? FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let tf = Self.dir.appendingPathComponent("token")
        try? token.write(to: tf, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tf.path)
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        guard let l = try? NWListener(using: params) else { appendAppLog("agents.log", "could not start the hook listener"); return }
        l.stateUpdateHandler = { st in
            if case .ready = st, let p = l.port?.rawValue {
                try? "\(p)".write(to: HookServer.dir.appendingPathComponent("port"), atomically: true, encoding: .utf8)
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.start(queue: q)
        listener = l
    }

    private struct Conn: @unchecked Sendable { let c: NWConnection }

    private func accept(_ c: NWConnection) {
        c.start(queue: q)
        read(Conn(c: c), Data())
    }

    private func read(_ conn: Conn, _ buf: Data) {
        conn.c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var b = buf
            if let data { b.append(data) }
            if b.count > 4_000_000 || err != nil { conn.c.cancel(); return }
            guard let hdrEnd = b.range(of: Data("\r\n\r\n".utf8)) else {
                if done { conn.c.cancel() } else { self.read(conn, b) }
                return
            }
            let head = String(decoding: b[..<hdrEnd.lowerBound], as: UTF8.self)
            let lines = head.components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for l in lines.dropFirst() {
                if let i = l.firstIndex(of: ":") { headers[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) }
            }
            let need = Int(headers["content-length"] ?? "0") ?? 0
            let body = b[hdrEnd.upperBound...]
            if body.count < need && !done { self.read(conn, b); return }
            let parts = (lines.first ?? "").split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            guard headers["x-zuffi"] == self.token else { self.respond(conn, 403, Data()); return }
            let payload = Data(body.prefix(need))
            let event = path.split(separator: "/").last.map(String.init) ?? ""
            Task { @MainActor in
                let reply = await AgentHub.shared.handle(event: event, body: payload)
                self.respond(conn, 200, reply)
            }
        }
    }

    private func respond(_ conn: Conn, _ code: Int, _ body: Data) {
        var head = "HTTP/1.1 \(code) \(code == 200 ? "OK" : "Forbidden")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        if code != 200 { head = head.replacingOccurrences(of: "application/json", with: "text/plain") }
        var out = Data(head.utf8); out.append(body)
        conn.c.send(content: out, completion: .contentProcessed { _ in conn.c.cancel() })
    }
}

// MARK: Model

struct AgentLimit: Equatable, Sendable {
    var label: String          // "5-hour", "Weekly"
    var usedPercent: Double
    var resetsAt: Date?
}

struct AgentSession: Identifiable, Equatable, Sendable {
    let id: String
    var tool: String           // "Claude Code", "Codex"
    var project: String
    var cwd: String
    var state: State
    var startedAt: Date?
    var lastPrompt = ""
    var lastStep = ""          // "Bash · npm test"
    var lastReply = ""
    var contextLeft: Double?   // 0…100
    var tokens: Int?
    var updated = Date()
    enum State: String, Sendable { case idle, working, needsYou, finished }
}

struct AgentApproval: Identifiable, Equatable {
    let id: String
    let sessionId: String
    let tool: String
    let detail: String
    let project: String
    let at = Date()
}

struct GitHubItem: Identifiable, Equatable { let id: String; let kind: String; let title: String; let repo: String }

@MainActor
final class AgentHub: ObservableObject {
    static let shared = AgentHub()

    @Published var sessions: [AgentSession] = []
    @Published var approvals: [AgentApproval] = []
    @Published var claudeLimits: [AgentLimit] = []
    @Published var codexLimits: [AgentLimit] = []
    @Published var github: [GitHubItem] = []
    @Published var githubNote = ""
    @Published var autoApprove: Set<String> = []
    @Published private(set) var claudeConnected = false

    private var waiting: [String: CheckedContinuation<Data, Never>] = [:]
    private var timer: Timer?
    private var codexStamp: Date?
    private var lastGitHub = Date.distantPast

    var needsYou: Bool { !approvals.isEmpty || sessions.contains { $0.state == .needsYou } }
    var working: AgentSession? { sessions.first { $0.state == .working } }

    func start() {
        claudeConnected = ClaudeHooks.isInstalled
        HookServer.shared.start()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated { AgentHub.shared.poll() }
        }
        poll()
    }

    private func poll() {
        readCodex()
        if Date().timeIntervalSince(lastGitHub) > 300 { lastGitHub = Date(); Task { await refreshGitHub() } }
        // forget sessions quiet for 6 hours
        sessions.removeAll { Date().timeIntervalSince($0.updated) > 6 * 3600 }
    }

    // MARK: Claude Code events

    func handle(event: String, body: Data) async -> Data {
        guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return Data() }
        if event == "statusline" { takeStatus(j); return Data() }
        let sid = j["session_id"] as? String ?? "claude"
        let cwd = j["cwd"] as? String ?? ""
        var s = sessions.first { $0.id == sid } ?? AgentSession(id: sid, tool: "Claude Code", project: Self.project(cwd), cwd: cwd, state: .idle)
        if !cwd.isEmpty { s.cwd = cwd; s.project = Self.project(cwd) }
        s.updated = Date()
        switch event {
        case "SessionStart":
            s.state = .idle
        case "UserPromptSubmit":
            s.state = .working; s.startedAt = Date(); s.lastPrompt = (j["prompt"] as? String) ?? ""; s.lastStep = "Thinking…"; s.lastReply = ""
        case "PreToolUse":
            if s.state != .working { s.state = .working; s.startedAt = s.startedAt ?? Date() }
            s.lastStep = Self.describe(tool: j["tool_name"] as? String ?? "Tool", input: j["tool_input"] as? [String: Any])
        case "Notification":
            let m = (j["message"] as? String) ?? ""
            if m.lowercased().contains("waiting") || m.lowercased().contains("input") { s.state = .needsYou; s.lastStep = m }
        case "Stop":
            s.state = .finished
            s.lastReply = (j["last_assistant_message"] as? String) ?? Self.lastReply(transcript: j["transcript_path"] as? String) ?? s.lastReply
            if let u = Self.usage(transcript: j["transcript_path"] as? String) { s.tokens = u.tokens; if s.contextLeft == nil { s.contextLeft = u.left } }
            SoundEngine.shared.play("finish")
            EdgeGlow.shared.flash(.done)
        case "SessionEnd":
            sessions.removeAll { $0.id == sid }; autoApprove.remove(sid)
            return Data()
        case "PermissionRequest":
            let tool = j["tool_name"] as? String ?? "Tool"
            let detail = Self.describe(tool: tool, input: j["tool_input"] as? [String: Any])
            if autoApprove.contains(sid) {
                s.lastStep = "✓ " + detail
                upsert(s)
                EdgeGlow.shared.flash(.autoApprove)
                return Self.decision(allow: true)
            }
            s.state = .needsYou; s.lastStep = detail
            upsert(s)
            return await ask(AgentApproval(id: UUID().uuidString, sessionId: sid, tool: tool, detail: detail, project: s.project))
        default: break
        }
        upsert(s)
        return Data()
    }

    private func upsert(_ s: AgentSession) {
        if let i = sessions.firstIndex(where: { $0.id == s.id }) { sessions[i] = s } else { sessions.insert(s, at: 0) }
    }

    private func ask(_ a: AgentApproval) async -> Data {
        approvals.append(a)
        SoundEngine.shared.play("approval")
        EdgeGlow.shared.set(.needsYou)
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.agents)
        let id = a.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280 * 1_000_000_000)
            AgentHub.shared.finish(id, Data())        // no answer → Claude asks in the terminal
        }
        return await withCheckedContinuation { cont in waiting[id] = cont }
    }

    private func finish(_ id: String, _ reply: Data) {
        guard let c = waiting.removeValue(forKey: id) else { return }
        if let a = approvals.first(where: { $0.id == id }), var s = sessions.first(where: { $0.id == a.sessionId }) {
            s.state = .working; upsert(s)
        }
        approvals.removeAll { $0.id == id }
        if approvals.isEmpty { EdgeGlow.shared.set(nil) }
        c.resume(returning: reply)
    }

    /// Deny / Approve / All (approve everything else this session asks).
    func decide(_ a: AgentApproval, allow: Bool, all: Bool = false) {
        if all { autoApprove.insert(a.sessionId) }
        SoundEngine.shared.play(allow ? "approve" : "error")
        if allow { EdgeGlow.shared.flash(all ? .autoApprove : .done) }
        finish(a.id, Self.decision(allow: allow))
        // anything else waiting from the same session is approved too when "All"
        if all { for other in approvals where other.sessionId == a.sessionId { finish(other.id, Self.decision(allow: true)) } }
    }

    static func decision(allow: Bool) -> Data {
        var d: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { d["message"] = "Denied from Zuffi" }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": d]]
        return (try? JSONSerialization.data(withJSONObject: out)) ?? Data()
    }

    private func takeStatus(_ j: [String: Any]) {
        if let rl = j["rate_limits"] as? [String: Any] {
            var out: [AgentLimit] = []
            for (key, label) in [("five_hour", "5-hour"), ("seven_day", "Weekly")] {
                if let w = rl[key] as? [String: Any], let p = (w["used_percentage"] as? NSNumber)?.doubleValue {
                    out.append(AgentLimit(label: label, usedPercent: p, resetsAt: (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }))
                }
            }
            if !out.isEmpty { claudeLimits = out }
        }
        if let sid = j["session_id"] as? String, let cw = j["context_window"] as? [String: Any],
           let left = (cw["remaining_percentage"] as? NSNumber)?.doubleValue,
           let i = sessions.firstIndex(where: { $0.id == sid }) {
            sessions[i].contextLeft = left
            if let t = (cw["total_input_tokens"] as? NSNumber)?.intValue { sessions[i].tokens = t + ((cw["total_output_tokens"] as? NSNumber)?.intValue ?? 0) }
        }
    }

    // MARK: Codex (reads its session logs)

    private var codexBusy = false

    /// Reads Codex's newest session log in the background (never on the main thread, so Zuffi never stutters).
    private func readCodex() {
        guard !codexBusy else { return }
        codexBusy = true
        let stamp = codexStamp
        let base = sessions.first { $0.id == "codex" } ?? AgentSession(id: "codex", tool: "Codex", project: "Codex", cwd: "", state: .idle)
        Task.detached(priority: .utility) {
            let r = AgentHub.scanCodex(since: stamp, base: base)
            await MainActor.run { AgentHub.shared.applyCodex(r) }
        }
    }

    struct CodexScan: Sendable { let mtime: Date; let session: AgentSession; let limits: [AgentLimit] }

    private func applyCodex(_ r: CodexScan?) {
        codexBusy = false
        guard let r else { return }
        codexStamp = r.mtime
        if !r.limits.isEmpty { codexLimits = r.limits }
        if Date().timeIntervalSince(r.mtime) < 6 * 3600 {
            let was = sessions.first { $0.id == "codex" }?.state
            upsert(r.session)
            if was == .working && r.session.state == .finished { SoundEngine.shared.play("finish"); EdgeGlow.shared.flash(.done) }
        }
    }

    nonisolated static func scanCodex(since stamp: Date?, base: AgentSession) -> CodexScan? {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/sessions")
        guard let file = newest(in: root, depth: 3),
              let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let mtime = attrs[.modificationDate] as? Date, mtime != stamp,
              let text = tail(file, bytes: 300_000) else { return nil }
        var s = base
        var limits: [AgentLimit] = []
        for line in text.split(separator: "\n") {
            guard line.contains("\"payload\""), let d = line.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            let p = j["payload"] as? [String: Any] ?? [:]
            let type = p["type"] as? String ?? ""
            if let cwd = p["cwd"] as? String, !cwd.isEmpty { s.cwd = cwd; s.project = project(cwd) }
            switch type {
            case "user_message": s.state = .working; s.startedAt = date(j["timestamp"]) ?? Date(); s.lastPrompt = p["message"] as? String ?? ""; s.lastStep = "Thinking…"
            case "task_started": s.state = .working; s.startedAt = date(j["timestamp"]) ?? s.startedAt
            case "agent_message": s.lastReply = p["message"] as? String ?? s.lastReply
            case "exec_command_begin":
                if let cmd = p["command"] as? [String] { s.lastStep = "Shell · " + cmd.joined(separator: " ").prefix(80) }
            case "task_complete":
                s.state = .finished
                if let m = p["last_agent_message"] as? String, !m.isEmpty { s.lastReply = m }
            case "token_count":
                if let info = p["info"] as? [String: Any] {
                    if let tot = (info["total_token_usage"] as? [String: Any])?["total_tokens"] as? NSNumber { s.tokens = tot.intValue }
                    if let last = (info["last_token_usage"] as? [String: Any])?["input_tokens"] as? NSNumber,
                       let win = info["model_context_window"] as? NSNumber, win.doubleValue > 0 {
                        s.contextLeft = max(0, 100 - last.doubleValue / win.doubleValue * 100)
                    }
                }
                if let rl = p["rate_limits"] as? [String: Any] {
                    limits = []
                    for key in ["primary", "secondary"] {
                        guard let w = rl[key] as? [String: Any], let used = (w["used_percent"] as? NSNumber)?.doubleValue else { continue }
                        let mins = (w["window_minutes"] as? NSNumber)?.intValue ?? 0
                        let label = mins >= 10_000 ? "Weekly" : mins > 0 ? "\(mins / 60)-hour" : key.capitalized
                        var reset: Date?
                        if let r = (w["resets_at"] as? NSNumber)?.doubleValue { reset = Date(timeIntervalSince1970: r) }
                        else if let r = (w["resets_in_seconds"] as? NSNumber)?.doubleValue { reset = (date(j["timestamp"]) ?? Date()).addingTimeInterval(r) }
                        limits.append(AgentLimit(label: label, usedPercent: used, resetsAt: reset))
                    }
                }
            default: break
            }
        }
        if s.state == .working, Date().timeIntervalSince(mtime) > 600 { s.state = .finished }
        s.updated = mtime
        return CodexScan(mtime: mtime, session: s, limits: limits)
    }

    /// Bring the terminal (or editor) running that session to the front — the window whose title mentions the project if we can see titles.
    static func jumpToTerminal(project: String) {
        let ids = ["com.mitchellh.ghostty", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "com.apple.Terminal",
                   "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed"]
        let running = ids.compactMap { id in NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id } }
        let pick = running.first { app in
            guard AXIsProcessTrusted() else { return false }
            let ax = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(ax, 0.3)
            var wins: CFTypeRef?
            guard AXUIElementCopyAttributeValue(ax, kAXWindowsAttribute as CFString, &wins) == .success, let list = wins as? [AXUIElement] else { return false }
            for w in list {
                var t: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t) == .success, let title = t as? String,
                   title.localizedCaseInsensitiveContains(project) {
                    AXUIElementPerformAction(w, kAXRaiseAction as CFString)
                    return true
                }
            }
            return false
        } ?? running.first
        pick?.bringForward()
    }

    // MARK: GitHub

    func refreshGitHub() async {
        guard let gh = InstalledAI.find("gh") else {
            githubNote = "Install the GitHub CLI (brew install gh) and run “gh auth login” to see your GitHub here."
            return
        }
        let (code, out) = await Self.run(gh, ["api", "notifications", "--jq", ".[] | [.id, .subject.type, .subject.title, .repository.full_name] | @tsv"])
        if code != 0 { githubNote = "Run “gh auth login” in Terminal once to see your GitHub here."; github = []; return }
        githubNote = ""
        github = out.split(separator: "\n").prefix(20).compactMap { l in
            let f = l.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            return f.count >= 4 ? GitHubItem(id: f[0], kind: f[1], title: f[2], repo: f[3]) : nil
        }
    }

    // MARK: Helpers

    nonisolated static func project(_ cwd: String) -> String {
        let n = (cwd as NSString).lastPathComponent
        return n.isEmpty ? "Claude Code" : n
    }

    static func describe(tool: String, input: [String: Any]?) -> String {
        let i = input ?? [:]
        let s = (i["command"] as? String) ?? (i["file_path"] as? String).map { ($0 as NSString).lastPathComponent }
            ?? (i["url"] as? String) ?? (i["pattern"] as? String) ?? (i["description"] as? String) ?? ""
        let one = s.replacingOccurrences(of: "\n", with: " ")
        return one.isEmpty ? tool : "\(tool) · \(one.prefix(140))"
    }

    nonisolated static func tail(_ url: URL, bytes: Int) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        guard let d = try? h.readToEnd() else { return nil }
        var s = String(decoding: d, as: UTF8.self)
        if size > UInt64(bytes), let nl = s.firstIndex(of: "\n") { s = String(s[s.index(after: nl)...]) }
        return s
    }

    static func lastReply(transcript: String?) -> String? {
        guard let p = transcript, let text = tail(URL(fileURLWithPath: p), bytes: 300_000) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard let d = line.data(using: .utf8), let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  j["type"] as? String == "assistant", let m = j["message"] as? [String: Any],
                  let content = m["content"] as? [[String: Any]] else { continue }
            let t = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
            if !t.isEmpty { return t }
        }
        return nil
    }

    static func usage(transcript: String?) -> (tokens: Int, left: Double)? {
        guard let p = transcript, let text = tail(URL(fileURLWithPath: p), bytes: 300_000) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"usage\""), let d = line.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
                  let m = j["message"] as? [String: Any], let u = m["usage"] as? [String: Any] else { continue }
            let n = { (k: String) in (u[k] as? NSNumber)?.intValue ?? 0 }
            let ctx = n("input_tokens") + n("cache_read_input_tokens") + n("cache_creation_input_tokens")
            let window = ((m["model"] as? String) ?? "").contains("1m") ? 1_000_000.0 : 200_000.0
            return (ctx + n("output_tokens"), max(0, 100 - Double(ctx) / window * 100))
        }
        return nil
    }

    /// Newest .jsonl under year/month/day folders — looks only at the latest folders.
    nonisolated static func newest(in dir: URL, depth: Int) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        if depth == 0 {
            var best: (URL, Date)?
            for f in items where f.pathExtension == "jsonl" {
                let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if best == nil || d > best!.1 { best = (f, d) }
            }
            return best?.0
        }
        for sub in items.filter({ $0.hasDirectoryPath }).sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).prefix(2) {
            if let f = newest(in: sub, depth: depth - 1) { return f }
        }
        return nil
    }

    nonisolated static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    nonisolated static func run(_ exe: String, _ args: [String]) async -> (Int32, String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
                p.environment = env
                let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
                do { try p.run() } catch { cont.resume(returning: (-1, "")); return }
                let d = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(decoding: d, as: UTF8.self)))
            }
        }
    }
}

// MARK: - Installing the Claude Code hooks (only when you press "Connect")

@MainActor
enum ClaudeHooks {
    static var settingsURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json") }
    static var hookScript: URL { HookServer.dir.appendingPathComponent("zuffi-claude-hook.sh") }
    static var statusScript: URL { HookServer.dir.appendingPathComponent("zuffi-statusline.sh") }
    static var originalStatus: URL { HookServer.dir.appendingPathComponent("statusline-original") }
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd"]

    static var claudeFound: Bool {
        InstalledAI.claudeCode != nil || FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude").path)
    }

    static var isInstalled: Bool {
        guard let d = try? Data(contentsOf: settingsURL), let s = String(data: d, encoding: .utf8) else { return false }
        return s.contains("zuffi-claude-hook.sh")
    }

    private static let hookBody = """
    #!/bin/bash
    # Zuffi ↔ Claude Code. Tells Zuffi what Claude is doing and lets you approve from Zuffi.
    # If Zuffi isn't running this does nothing and Claude Code works exactly as normal.
    EV="$1"; D="$HOME/.zuffi"
    PORT=$(cat "$D/port" 2>/dev/null) || exit 0
    TOKEN=$(cat "$D/token" 2>/dev/null) || exit 0
    if [ "$EV" = "PermissionRequest" ]; then
      curl -s -m 290 -X POST -H "X-Zuffi: $TOKEN" --data-binary @- "http://127.0.0.1:$PORT/claude/$EV" 2>/dev/null
    else
      curl -s -m 2 -X POST -H "X-Zuffi: $TOKEN" --data-binary @- "http://127.0.0.1:$PORT/claude/$EV" >/dev/null 2>&1
    fi
    exit 0
    """

    private static let statusBody = """
    #!/bin/bash
    # Passes Claude Code's status (limits used, context left) to Zuffi, then shows your own status line.
    IN=$(cat); D="$HOME/.zuffi"
    PORT=$(cat "$D/port" 2>/dev/null); TOKEN=$(cat "$D/token" 2>/dev/null)
    if [ -n "$PORT" ]; then printf '%s' "$IN" | curl -s -m 1 -X POST -H "X-Zuffi: $TOKEN" --data-binary @- "http://127.0.0.1:$PORT/claude/statusline" >/dev/null 2>&1; fi
    if [ -s "$D/statusline-original" ]; then printf '%s' "$IN" | bash -c "$(cat "$D/statusline-original")"; exit 0; fi
    M=$(printf '%s' "$IN" | sed -n 's/.*"display_name":"\\([^"]*\\)".*/\\1/p')
    echo "🐰 ${M:-Claude}"
    """

    static func install() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: HookServer.dir, withIntermediateDirectories: true)
        try hookBody.write(to: hookScript, atomically: true, encoding: .utf8)
        try statusBody.write(to: statusScript, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScript.path)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: statusScript.path)

        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root: [String: Any] = [:]
        if let d = try? Data(contentsOf: settingsURL) {
            guard let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
                throw NSError(domain: "Zuffi", code: 2, userInfo: [NSLocalizedDescriptionKey: "Your ~/.claude/settings.json isn't valid JSON, so Zuffi left it alone."])
            }
            root = j
            try? d.write(to: settingsURL.appendingPathExtension("zuffi-backup"))
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for ev in events {
            var list = (hooks[ev] as? [[String: Any]] ?? []).filter { !(String(describing: $0).contains("zuffi-claude-hook.sh")) }
            var entry: [String: Any] = ["hooks": [["type": "command", "command": "\"\(hookScript.path)\" \(ev)", "timeout": ev == "PermissionRequest" ? 300 : 5]]]
            if ev == "PreToolUse" || ev == "PermissionRequest" { entry["matcher"] = "*" }
            list.append(entry)
            hooks[ev] = list
        }
        root["hooks"] = hooks
        // status line: keep the person's own one running after ours
        let current = (root["statusLine"] as? [String: Any])?["command"] as? String
        if let current, !current.contains("zuffi-statusline.sh") { try current.write(to: originalStatus, atomically: true, encoding: .utf8) }
        root["statusLine"] = ["type": "command", "command": "\"\(statusScript.path)\""]
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settingsURL, options: .atomic)
    }

    static func uninstall() throws {
        guard let d = try? Data(contentsOf: settingsURL), var root = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        if var hooks = root["hooks"] as? [String: Any] {
            for (k, v) in hooks {
                let kept = (v as? [[String: Any]] ?? []).filter { !(String(describing: $0).contains("zuffi-claude-hook.sh")) }
                if kept.isEmpty { hooks.removeValue(forKey: k) } else { hooks[k] = kept }
            }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        }
        if let cmd = (root["statusLine"] as? [String: Any])?["command"] as? String, cmd.contains("zuffi-statusline.sh") {
            if let orig = try? String(contentsOf: originalStatus, encoding: .utf8), !orig.isEmpty {
                root["statusLine"] = ["type": "command", "command": orig]
            } else { root.removeValue(forKey: "statusLine") }
        }
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settingsURL, options: .atomic)
    }

    static func toggle() -> String {
        do {
            if isInstalled { try uninstall(); return "Disconnected. Claude Code asks in the terminal again." }
            try install()
            return "Connected! New Claude Code sessions show up in Zuffi, and you can approve from here."
        } catch { return error.localizedDescription }
    }
}

// MARK: - Island: Agents tab

struct AgentsIslandView: View {
    @ObservedObject var hub = AgentHub.shared
    @State private var note = ""

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(hub.approvals) { a in approvalCard(a) }
                if hub.sessions.isEmpty && hub.approvals.isEmpty { emptyCard }
                ForEach(hub.sessions) { s in sessionCard(s) }
                limitsRow
                if !hub.github.isEmpty || !hub.githubNote.isEmpty { githubCard }
                DeveloperCard()
            }
            .padding(.vertical, 4)
        }
    }

    private func approvalCard(_ a: AgentApproval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").foregroundColor(Color(hex: "#F7C948"))
                Text("\(a.project) needs you").font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Text("Claude Code").font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            }
            Text(a.detail).font(.system(size: 11, design: .monospaced)).foregroundColor(.white.opacity(0.9))
                .lineLimit(3).padding(7).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            HStack(spacing: 6) {
                pill("Deny", bg: Color.white.opacity(0.1), fg: .white) { hub.decide(a, allow: false) }
                pill("Approve", bg: Color(hex: "#34D399"), fg: Color(hex: "#062A1B")) { hub.decide(a, allow: true) }
                pill("All", bg: Color(hex: "#F7C948"), fg: Color(hex: "#2A1E00")) { hub.decide(a, allow: true, all: true) }
                    .help("Approve this and everything else this session asks")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#F5A524").opacity(0.16)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: "#F7C948").opacity(0.5), lineWidth: 1))
    }

    private func sessionCard(_ s: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color(s.state)).frame(width: 7, height: 7).shadow(color: color(s.state), radius: 3)
                Text(s.tool).font(.system(size: 12, weight: .bold, design: .rounded))
                Text(s.project).font(.system(size: 11)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                Spacer()
                if s.state == .working, let st = s.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        Text("Working… \(Int(tl.date.timeIntervalSince(st)))s").font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundColor(Color(hex: "#7CC4FF"))
                    }
                } else {
                    Text(label(s.state)).font(.system(size: 10.5, weight: .semibold, design: .rounded)).foregroundColor(color(s.state))
                }
                Button { AgentHub.jumpToTerminal(project: s.project) } label: {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 10, weight: .bold))
                }.buttonStyle(.plain).foregroundColor(.white.opacity(0.6)).help("Open its terminal")
                if hub.autoApprove.contains(s.id) {
                    Text("Auto-approve").font(.system(size: 9.5, weight: .bold)).padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "#34D399").opacity(0.25))).foregroundColor(Color(hex: "#34D399"))
                        .onTapGesture { hub.autoApprove.remove(s.id) }.help("Tap to stop auto-approving")
                }
            }
            if !s.lastStep.isEmpty && s.state != .finished {
                Text(s.lastStep).font(.system(size: 10.5, design: .monospaced)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
            }
            if !s.lastReply.isEmpty {
                Text(s.lastReply).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.88)).lineLimit(4)
                    .textSelection(.enabled)
            }
            HStack(spacing: 10) {
                if let c = s.contextLeft { meter("Context left", 100 - c, inverted: true) }
                if let t = s.tokens { Text("\(Self.short(t)) tokens").font(.system(size: 10)).foregroundColor(.white.opacity(0.45)) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 0.7))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hub.claudeConnected ? "No agents working right now" : "See Claude Code and Codex here")
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
            Text(hub.claudeConnected
                 ? "Start Claude Code or Codex in Terminal — their replies, steps and permission requests appear here."
                 : "Connect Claude Code to watch its sessions, approve its requests from Zuffi, and see how much of your limits you've used. Codex shows up on its own.")
                .font(.system(size: 11)).foregroundColor(.white.opacity(0.65)).fixedSize(horizontal: false, vertical: true)
            if !hub.claudeConnected && ClaudeHooks.claudeFound {
                pill("Connect Claude Code", bg: Color(hex: "#F28A3C"), fg: Color(hex: "#1A1008")) {
                    note = ClaudeHooks.toggle(); AgentHub.shared.start()
                }
            }
            if !note.isEmpty { Text(note).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder private var limitsRow: some View {
        if !hub.claudeLimits.isEmpty || !hub.codexLimits.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("LIMITS USED").font(.system(size: 8.5, weight: .heavy, design: .rounded)).kerning(1).foregroundColor(.white.opacity(0.45))
                if !hub.claudeLimits.isEmpty { limitLine("Claude", hub.claudeLimits) }
                if !hub.codexLimits.isEmpty { limitLine("Codex", hub.codexLimits) }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
        }
    }

    private func limitLine(_ name: String, _ l: [AgentLimit]) -> some View {
        HStack(spacing: 12) {
            Text(name).font(.system(size: 11, weight: .bold, design: .rounded)).frame(width: 46, alignment: .leading)
            ForEach(l, id: \.label) { x in
                VStack(alignment: .leading, spacing: 2) {
                    meter(x.label, x.usedPercent)
                    if let r = x.resetsAt {
                        Text("\(Int(100 - x.usedPercent))% left · resets \(r.formatted(r.timeIntervalSinceNow > 86400 ? .dateTime.weekday().hour() : .dateTime.hour().minute()))")
                            .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45))
                    }
                }
            }
        }
    }

    private var githubCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text("GitHub").font(.system(size: 12, weight: .bold, design: .rounded))
                if !hub.github.isEmpty { Text("\(hub.github.count) unread").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.55)) }
                Spacer()
                Button("Open") { NSWorkspace.shared.open(URL(string: "https://github.com/notifications")!) }.buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#F9A830"))
            }
            if !hub.githubNote.isEmpty { Text(hub.githubNote).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)) }
            ForEach(hub.github.prefix(4)) { g in
                HStack(spacing: 6) {
                    Text(g.kind == "PullRequest" ? "PR" : g.kind == "Issue" ? "Issue" : g.kind).font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5).padding(.vertical, 1).background(Capsule().fill(Color.white.opacity(0.1)))
                    Text(g.title).font(.system(size: 11)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(g.repo.components(separatedBy: "/").last ?? g.repo).font(.system(size: 10)).foregroundColor(.white.opacity(0.45))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }

    private func meter(_ label: String, _ used: Double, inverted: Bool = false) -> some View {
        let left = 100 - used
        let tint = left < 15 ? Color(hex: "#F4505E") : left < 40 ? Color(hex: "#F5A524") : Color(hex: "#34D399")
        return HStack(spacing: 5) {
            Text(label).font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule().fill(tint).frame(width: 60 * CGFloat(max(0.03, min(1, (inverted ? left : used) / 100))))
            }
            .frame(width: 60, height: 5)
            Text(inverted ? "\(Int(left))%" : "\(Int(used))%").font(.system(size: 10, weight: .semibold)).foregroundColor(tint)
        }
    }

    private func pill(_ t: String, bg: Color, fg: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(.system(size: 11.5, weight: .bold, design: .rounded)).foregroundColor(fg)
                .padding(.horizontal, 14).frame(height: 26).background(Capsule().fill(bg))
        }.buttonStyle(.plain)
    }

    private func color(_ s: AgentSession.State) -> Color {
        switch s { case .working: return Color(hex: "#3B9EFF"); case .needsYou: return Color(hex: "#F7C948"); case .finished: return Color(hex: "#34D399"); case .idle: return Color.white.opacity(0.4) }
    }
    private func label(_ s: AgentSession.State) -> String {
        switch s { case .working: return "Working"; case .needsYou: return "Needs you"; case .finished: return "Done"; case .idle: return "Ready" }
    }
    static func short(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)" }
}

// MARK: - Settings → Agents

struct AgentsSettingsView: View {
    @ObservedObject var hub = AgentHub.shared
    @State private var note = ""
    @State private var connected = ClaudeHooks.isInstalled

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text("Coding agents").font(.system(size: 13, weight: .semibold))
                HStack {
                    Image(systemName: "terminal.fill").foregroundColor(Color(hex: "#E2648A"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Claude Code").font(.system(size: 12, weight: .semibold))
                        Text(connected ? "Connected — sessions, replies, approvals and limits show in Zuffi" : "Approve Claude's requests from Zuffi and see your limits")
                            .font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(connected ? "Disconnect" : "Connect") {
                        note = ClaudeHooks.toggle(); connected = ClaudeHooks.isInstalled; hub.start()
                    }.controlSize(.small)
                }
                HStack {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundColor(Color(hex: "#E2648A"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Codex").font(.system(size: 12, weight: .semibold))
                        Text("Shows up on its own — replies and limits come from Codex's logs. Approve Codex's requests in its terminal.")
                            .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack {
                    Image(systemName: "bell.badge.fill").foregroundColor(Color(hex: "#E2648A"))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("GitHub").font(.system(size: 12, weight: .semibold))
                        Text(hub.githubNote.isEmpty ? "Unread notifications through the GitHub CLI" : hub.githubNote)
                            .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Check now") { Task { await hub.refreshGitHub() } }.controlSize(.small)
                }
                if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundColor(.secondary) }
            }
            .padding(6)
        }
    }
}


// MARK: - Developer tools (like Coucou): your services at a glance

struct DeveloperCard: View {
    @ObservedObject private var state = AppState.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "hammer.fill").foregroundColor(Color(hex: "#F7C948"))
                Text("Developer tools").font(.system(size: 12, weight: .bold, design: .rounded))
                Spacer()
                Button("Keys…") { NotificationCenter.default.post(name: .openFullSettings, object: nil) }
                    .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#F9A830"))
            }
            Text("Stripe payments, Vercel deploys, n8n workflows, Resend emails, Notion, Cal.com and GitHub — switch on the ones you use.")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.55)).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(IslandConst.allIntegrations, id: \.id) { m in
                    let on = state.activeIntegrations.contains(m.id)
                    let task = state.tasks.first { $0.id == m.id }
                    Button { state.toggleIntegration(m.id) } label: {
                        HStack(spacing: 6) {
                            LittleSparrow(color: m.color, size: 16)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(m.name).font(.system(size: 11, weight: .semibold))
                                Text(on ? (task?.steps.last ?? "Watching") : "Off").font(.system(size: 9)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Circle().fill(on ? Color(hex: "#34D399") : Color.white.opacity(0.2)).frame(width: 7, height: 7)
                        }
                        .padding(6).background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(on ? 0.1 : 0.04)))
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.05)))
    }
}
