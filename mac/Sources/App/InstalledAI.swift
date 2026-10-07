import Foundation
import AppKit
import SwiftUI

// =====================================================================
// MARK: - The AI you already have
//
// Many people already pay for Claude or ChatGPT. If Claude Code (`claude`) or Codex (`codex`)
// is installed, Zuffi can think with *your* subscription — no API key to paste. The Claude,
// ChatGPT, Copilot and Gemini desktop apps can't be driven from outside, so for those Zuffi
// hands your question over: it opens the app, types the question and sends it.
// Ollama / LM Studio (free AI on this Mac) are found too.
// =====================================================================

@MainActor
enum InstalledAI {
    struct Tool: Identifiable, Hashable {
        let id: String          // "claude-code", "codex", "claude-app", …
        let name: String        // what people call it
        let detail: String
        let path: String
        var isCLI: Bool { id == "claude-code" || id == "codex" }
    }

    private static var cache: [Tool]?
    private static let home = FileManager.default.homeDirectoryForCurrentUser.path

    /// Folders command-line tools usually live in (Homebrew, npm, bun, pipx, Claude's own installer…).
    static var searchPath: [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.bun/bin",
         "\(home)/.claude/local", "\(home)/.volta/bin", "\(home)/.nvm/versions/node/current/bin", "/usr/bin", "/bin"]
        + ((try? FileManager.default.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node")) ?? []).map { "\(home)/.nvm/versions/node/\($0)/bin" }
    }

    static func find(_ binary: String) -> String? {
        for dir in searchPath {
            let p = "\(dir)/\(binary)"
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    private static func app(_ names: [String]) -> String? {
        for n in names {
            for base in ["/Applications", "\(home)/Applications"] {
                let p = "\(base)/\(n).app"
                if FileManager.default.fileExists(atPath: p) { return p }
            }
        }
        return nil
    }

    static func detect(refresh: Bool = false) -> [Tool] {
        if let c = cache, !refresh { return c }
        var out: [Tool] = []
        if let p = find("claude") { out.append(Tool(id: "claude-code", name: "Claude (Claude Code)", detail: "Uses your Claude subscription", path: p)) }
        if let p = find("codex") { out.append(Tool(id: "codex", name: "ChatGPT (Codex)", detail: "Uses your ChatGPT subscription", path: p)) }
        if let p = app(["Claude"]) { out.append(Tool(id: "claude-app", name: "Claude app", detail: "Zuffi can send your question to it", path: p)) }
        if let p = app(["ChatGPT"]) { out.append(Tool(id: "chatgpt-app", name: "ChatGPT app", detail: "Zuffi can send your question to it", path: p)) }
        if let p = app(["Microsoft Copilot", "Copilot"]) { out.append(Tool(id: "copilot-app", name: "Copilot app", detail: "Zuffi can send your question to it", path: p)) }
        if let p = app(["Gemini"]) { out.append(Tool(id: "gemini-app", name: "Gemini app", detail: "Zuffi can send your question to it", path: p)) }
        if let p = app(["Ollama"]) ?? find("ollama") { out.append(Tool(id: "ollama", name: "Ollama", detail: "Free AI on this Mac", path: p)) }
        if let p = app(["LM Studio"]) { out.append(Tool(id: "lmstudio", name: "LM Studio", detail: "Free AI on this Mac", path: p)) }
        cache = out
        return out
    }

    static var claudeCode: Tool? { detect().first { $0.id == "claude-code" } }
    static var codex: Tool? { detect().first { $0.id == "codex" } }

    // MARK: Think with Claude Code / Codex

    /// Runs the CLI once with the whole prompt and returns its answer.
    nonisolated static func ask(_ tool: Tool, prompt: String, timeout: TimeInterval = 120) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("zuffi-ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let outFile = tmp.appendingPathComponent("answer-\(UUID().uuidString).txt")
        var args: [String]
        switch tool.id {
        case "claude-code": args = ["-p", prompt, "--output-format", "text"]
        case "codex": args = ["exec", "--skip-git-repo-check", "--output-last-message", outFile.path, prompt]
        default: throw NSError(domain: "Zuffi", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(tool.name) can't be used as a brain."])
        }
        let path = await MainActor.run { searchPath.joined(separator: ":") }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: tool.path)
                p.arguments = args
                p.currentDirectoryURL = tmp
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = path + ":" + (env["PATH"] ?? "")
                env["NO_COLOR"] = "1"
                p.environment = env
                let out = Pipe(), err = Pipe()
                p.standardOutput = out; p.standardError = err
                p.standardInput = FileHandle.nullDevice
                do { try p.run() } catch { cont.resume(throwing: error); return }
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let edata = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                var text = String(data: data, encoding: .utf8) ?? ""
                if tool.id == "codex", let last = try? String(contentsOf: outFile, encoding: .utf8), !last.isEmpty { text = last }
                try? FileManager.default.removeItem(at: outFile)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if p.terminationStatus == 0, !text.isEmpty { cont.resume(returning: text); return }
                let why = (String(data: edata, encoding: .utf8) ?? "").split(separator: "\n").last.map(String.init) ?? "no answer"
                let hint = why.lowercased().contains("login") || why.lowercased().contains("auth")
                    ? "\(tool.name) isn't signed in. Open Terminal, type \(tool.id == "codex" ? "codex" : "claude") and sign in once."
                    : "\(tool.name): \(why)"
                cont.resume(throwing: NSError(domain: "Zuffi", code: Int(p.terminationStatus), userInfo: [NSLocalizedDescriptionKey: hint]))
            }
        }
    }

    // MARK: Hand a question to a desktop chat app

    /// "ask ChatGPT what's the capital of Peru" → opens the app, types the question, sends it.
    static func handOff(appID: String, question: String) async -> String {
        let names = ["claude-app": "Claude", "chatgpt-app": "ChatGPT", "copilot-app": "Copilot", "gemini-app": "Gemini"]
        let web = ["claude-app": "https://claude.ai/new", "chatgpt-app": "https://chatgpt.com", "copilot-app": "https://copilot.microsoft.com", "gemini-app": "https://gemini.google.com/app"]
        let name = names[appID] ?? "the app"
        if let tool = detect().first(where: { $0.id == appID }) {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: tool.path), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !question.isEmpty else { return "Opening \(name)." }
            guard AXIsProcessTrusted() else { return "Opened \(name). Allow Zuffi under Accessibility so I can type your question for you." }
            let pb = NSPasteboard.general, old = pb.string(forType: .string)
            pb.clearContents(); pb.setString(question, forType: .string)
            Hands.keys("cmd+v")
            try? await Task.sleep(nanoseconds: 300_000_000)
            Hands.keys("enter")
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let old { pb.clearContents(); pb.setString(old, forType: .string) }
            return "Asked \(name) for you."
        }
        // Not installed: use the website instead.
        var s = web[appID] ?? "https://chatgpt.com"
        if !question.isEmpty, appID == "chatgpt-app", let q = question.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { s += "/?q=\(q)" }
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        return "\(name) isn't installed, so I opened it in your browser."
    }
}

// MARK: - Settings → AI: "Found on this Mac"

struct InstalledAIView: View {
    @ObservedObject var state: AppState
    @State private var tools = InstalledAI.detect()
    @State private var testing: String?
    @State private var result = ""

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("AI already on this Mac").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Look again") { tools = InstalledAI.detect(refresh: true) }.controlSize(.small)
                }
                if tools.isEmpty {
                    Text("Nothing found yet. Zuffi works with Claude Code, Codex, the Claude / ChatGPT / Copilot / Gemini apps, Ollama and LM Studio.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(tools) { t in
                    HStack(spacing: 8) {
                        Image(systemName: t.isCLI ? "terminal.fill" : t.id == "ollama" || t.id == "lmstudio" ? "desktopcomputer" : "bubble.left.and.bubble.right.fill")
                            .foregroundColor(Color(hex: "#E2648A")).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.name).font(.system(size: 12, weight: .semibold))
                            Text(t.detail).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                        Spacer()
                        if t.isCLI {
                            let pick = t.id == "claude-code" ? AIProvider.claudeCode.rawValue : AIProvider.codex.rawValue
                            if state.aiProvider == pick {
                                Label("Zuffi uses this", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(.green)
                            } else {
                                Button("Use for answers") { state.aiProvider = pick; UserDefaults.standard.set(pick, forKey: "aiProvider") }.controlSize(.small)
                            }
                            Button(testing == t.id ? "…" : "Test") {
                                testing = t.id; result = ""
                                Task {
                                    do { result = try await InstalledAI.ask(t, prompt: "Say hello to the user in one short friendly sentence.") }
                                    catch { result = error.localizedDescription }
                                    testing = nil
                                }
                            }.controlSize(.small).disabled(testing != nil)
                        } else if t.id == "ollama" {
                            Button("Use for answers") { state.aiProvider = AIProvider.ollama.rawValue; UserDefaults.standard.set(AIProvider.ollama.rawValue, forKey: "aiProvider") }.controlSize(.small)
                        } else {
                            Text("Say “ask \(t.name.replacingOccurrences(of: " app", with: "")) …”").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
                if !result.isEmpty { Text(result).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.padding(6)
        }
    }
}
