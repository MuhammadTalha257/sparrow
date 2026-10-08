import Foundation
import AppKit
import SwiftUI
import PDFKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Providers

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case auto, claude, openai, gemini, groq, ollama, apple, claudeCode, codex
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:   return "Auto"
        case .claude: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        case .groq:   return "Groq (fast, free)"
        case .ollama: return "Ollama (local)"
        case .apple:  return "Apple (on-device)"
        case .claudeCode: return "My Claude (Claude Code)"
        case .codex:  return "My ChatGPT (Codex)"
        }
    }

    var icon: String {
        switch self {
        case .auto:   return "sparkles"
        case .claude: return "asterisk"
        case .openai: return "circle.hexagongrid"
        case .gemini: return "diamond"
        case .groq:   return "bolt.fill"
        case .ollama: return "desktopcomputer"
        case .apple:  return "apple.logo"
        case .claudeCode: return "terminal.fill"
        case .codex:  return "terminal"
        }
    }

    /// Whether this provider needs an API key the user pastes in Settings.
    var keychainKey: String? {
        switch self {
        case .claude: return "anthropic-api-key"
        case .openai: return "openai-api-key"
        case .gemini: return "gemini-api-key"
        case .groq:   return "groq-api-key"
        default:      return nil
        }
    }
}

// MARK: - AI service (routes every chat message)

@MainActor
final class AIService {
    static let shared = AIService()

    /// Provider-neutral conversation (used by every provider except Claude, which keeps its own).
    private var history: [(role: String, text: String)] = []
    private var pendingImage: (mime: String, base64: String)?
    /// The provider that answered the last message in this conversation.
    private(set) var lastProvider: AIProvider?
    /// Text of the attached file, if any. Sent with every message of this conversation.
    private var document: String?
    private var lastContextKey: String?

    static let systemPrompt = """
    You are Zuffi, a friendly, smart AI assistant that lives at the top of the user's computer screen. \
    Help with anything: questions, writing, summaries, translations, code, ideas and everyday tasks. \
    Reply in the user's language. Be clear and concise unless the user asks for detail. \
    Use plain text with line breaks, no markdown symbols like ** or ##.
    """

    /// System prompt plus the attached document (if any).
    var fullSystemPrompt: String {
        guard let document else { return Self.systemPrompt }
        return Self.systemPrompt + """


        The user attached a file. Its content is below, between <file> and </file>. \
        Answer the user's questions using this file. When they say "the file", "the document", "this PDF" \
        or ask about a person, project or detail in it, they mean this file. Quote facts from it; \
        if something isn't in the file, say so.

        <file>
        \(document)
        </file>
        """
    }

    func clearConversation() {
        history = []
        pendingImage = nil
        lastProvider = nil
        document = nil
        lastContextKey = nil
        ClaudeService.shared.clearConversation()
    }

    // MARK: Entry point

    func chat(query: String, context: PromptContext?, state: AppState) async {
        var context = context
        // 0) Your data: daily messages, and spreadsheets you hand over.
        if let r = ZuffiData.shared.handleCommand(query) { finish(r, state: state, emote: .happy); return }
        if case .file(_, let fileURL)? = context, let fileURL, ZuffiData.isSheet(fileURL) {
            let saved = await ZuffiData.shared.importSheet(fileURL)
            state.promptContext = nil
            context = nil
            let q = query.lowercased()
            if q.isEmpty || q.range(of: #"^(store|save|keep|remember|add)\b|this data|these data|is data"#, options: .regularExpression) != nil {
                finish(saved, state: state, emote: .happy); return
            }
        }
        // 1) Built-in commands run instantly, offline, with no API key.
        if let reply = await AgentRouter.shared.handle(query) {
            finish(reply, state: state, emote: .happy)
            return
        }
        // 1b) Everything else Zuffi can do offline (habits, prayer times, memory, invoices, time, expenses…).
        if context == nil, let reply = await WebHub.shared.ask(query) {
            finish(reply, state: state, emote: .happy)
            return
        }

        // 2) Pick an AI model.
        guard let provider = await resolveProvider(state: state) else {
            finish("""
            I can open apps, websites and folders, control music and volume, and more without any setup. Try "open Spotify" or "volume 40".

            To chat about anything else, connect an AI in Settings: paste a Claude, ChatGPT or Gemini key, or install Ollama (free, runs on your computer).
            """, state: state, emote: .surprised)
            return
        }
        lastProvider = provider

        // Claude keeps its own richer pipeline (web search, PDFs, images).
        if provider == .claude {
            await ClaudeService.shared.chat(query: ZuffiData.shared.augment(query), context: context, state: state)
            return
        }

        // 3) Attachments. A file's text lives in the system prompt for the whole
        //    conversation, so follow-up questions still "see" it. A newly attached
        //    file starts a fresh conversation about that file.
        var turn = ZuffiData.shared.augment(query)
        if let context, context.key != lastContextKey {
            lastContextKey = context.key
            let limit = provider == .ollama || provider == .apple ? 12_000 : 80_000
            let (text, image) = Self.describe(context, limit: limit)
            if context.isFile {
                history = []
                document = image == nil ? text : nil
                if let image { pendingImage = image; turn = text + "\n\n" + query }
            } else if history.isEmpty, document == nil, !text.isEmpty {
                turn = text + "\n\n" + query
            }
        }
        history.append((role: "user", text: turn))

        // Try the chosen AI first; if it fails (old model, no internet, bad key…), quietly try the others that are set up.
        var lastError: Error?
        for p in await fallbackChain(first: provider) {
            do {
                let reply = try await call(p, state: state)
                pendingImage = nil
                let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { continue }
                history.append((role: "assistant", text: clean))
                lastProvider = p
                finish(clean, state: state, emote: .happy)
                return
            } catch {
                lastError = error
                appendAppLog("ai.log", "\(p.label) failed: \(error.localizedDescription)")
            }
        }
        history.removeLast()
        finish("⚠︎ \(provider.label): \(lastError?.localizedDescription ?? "no answer")", state: state, emote: .annoyed)
    }

    private func call(_ p: AIProvider, state: AppState) async throws -> String {
        switch p {
        case .openai: return try await callOpenAI(state: state)
        case .gemini: return try await callGemini(state: state)
        case .groq:   return try await callGroq(state: state)
        case .ollama: return try await callOllama(state: state)
        case .apple:  return try await callApple()
        case .claudeCode, .codex:
            guard let tool = p == .claudeCode ? InstalledAI.claudeCode : InstalledAI.codex else {
                throw NSError(domain: "Zuffi", code: 0, userInfo: [NSLocalizedDescriptionKey: "\(p.label) isn't installed on this Mac."])
            }
            return try await InstalledAI.ask(tool, prompt: cliPrompt())
        default:      return ""
        }
    }

    /// One prompt for a command-line AI: Zuffi's instructions, any document, and the recent conversation.
    private func cliPrompt() -> String {
        var t = "You are Zuffi, a friendly personal assistant on the user's Mac. Answer briefly and helpfully, in the user's language. Do not use tools or edit files — just answer.\n"
        if let d = document { t += "\nDocument the user shared:\n\(d.prefix(20_000))\n" }
        for m in history.suffix(12) { t += "\n\(m.role == "assistant" ? "Zuffi" : "User"): \(m.text)" }
        return t + "\nZuffi:"
    }

    /// The chosen provider, then every other one that is ready (keys first, then on-device).
    private func fallbackChain(first: AIProvider) async -> [AIProvider] {
        var out: [AIProvider] = [first]
        for p in [AIProvider.groq, .gemini, .openai] where p != first {
            if let k = p.keychainKey, let v = KeychainStore.shared.get(k), !v.isEmpty { out.append(p) }
        }
        if first != .apple, Self.appleModelAvailable { out.append(.apple) }
        if first != .ollama, !(await Self.ollamaModels()).isEmpty { out.append(.ollama) }
        return out
    }

    private func finish(_ text: String, state: AppState, emote: BotEmote) {
        state.chatHistory.append(ChatMessage(role: .assistant, content: text))
        state.stateOverride = nil
        state.view = .prompt
        NotificationCenter.default.post(name: .triggerEmote, object: emote)
    }

    // MARK: Provider choice

    func resolveProvider(state: AppState) async -> AIProvider? {
        let chosen = AIProvider(rawValue: state.aiProvider) ?? .auto
        if chosen != .auto { return chosen }
        for p in [AIProvider.claude, .groq, .openai, .gemini] {
            if let k = p.keychainKey, let v = KeychainStore.shared.get(k), !v.isEmpty { return p }
        }
        // The subscription you already pay for (Claude Code / Codex), if installed.
        if InstalledAI.claudeCode != nil { return .claudeCode }
        if InstalledAI.codex != nil { return .codex }
        if Self.appleModelAvailable { return .apple }
        let local = await Self.ollamaModels()
        if !local.isEmpty { return .ollama }
        return nil
    }

    // MARK: Context → text / image

    static func describe(_ context: PromptContext, limit: Int = 80_000) -> (String, (mime: String, base64: String)?) {
        switch context {
        case .window(let app, let title, let url):
            var t = "Context: the user is looking at \(app), window \"\(title)\""
            if let url { t += ", URL \(url)" }
            return (t + ".", nil)
        case .file(let name, let fileURL):
            guard let fileURL else { return ("Attached file: \(name)", nil) }
            let ext = fileURL.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "gif", "webp", "heic"].contains(ext),
               let data = imageAsJPEG(fileURL) {
                return ("Attached image: \(name)", ("image/jpeg", data.base64EncodedString()))
            }
            if ext == "pdf", let doc = PDFDocument(url: fileURL) {
                let text = doc.string ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return ("File name: \(name) (PDF). It has no selectable text (it looks like a scanned image), so its words can't be read. Tell the user this.", nil)
                }
                return ("File name: \(name) (PDF)\n\n" + Self.tidy(text, limit: limit), nil)
            }
            if let data = try? Data(contentsOf: fileURL), data.count <= 300_000,
               let text = String(data: data, encoding: .utf8) {
                return ("File name: \(name)\n\n" + Self.tidy(text, limit: limit), nil)
            }
            return ("Attached file: \(name) (its content can't be read as text)", nil)
        }
    }

    /// Collapses runs of blank space (PDF text is full of it) and trims to `limit` characters.
    static func tidy(_ text: String, limit: Int) -> String {
        var t = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n\\s*\\n+", with: "\n", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > limit { t = String(t.prefix(limit)) + "\n[…the rest of the file was cut to fit]" }
        return t
    }

    /// Re-encodes any image as a JPEG no wider than 1600 px (keeps uploads small).
    static func imageAsJPEG(_ url: URL) -> Data? {
        guard let img = NSImage(contentsOf: url),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        let maxW: CGFloat = 1600
        let w = CGFloat(rep.pixelsWide), h = CGFloat(rep.pixelsHigh)
        if w > maxW {
            let scale = maxW / w
            let size = NSSize(width: w * scale, height: h * scale)
            let resized = NSImage(size: size)
            resized.lockFocus()
            img.draw(in: NSRect(origin: .zero, size: size))
            resized.unlockFocus()
            if let t = resized.tiffRepresentation, let r = NSBitmapImageRep(data: t) {
                return r.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
            }
        }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    // MARK: HTTP helper

    private func postJSON(_ url: URL, body: [String: Any], headers: [String: String], timeout: TimeInterval = 60) async throws -> [String: Any] {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            var msg = "HTTP \(code)"
            if let e = json["error"] as? [String: Any], let m = e["message"] as? String { msg = m }
            else if let m = json["error"] as? String { msg = m }
            if code == 401 || code == 403 { msg += " — check the API key in Settings." }
            throw NSError(domain: "Zuffi", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return json
    }

    private func key(_ p: AIProvider) throws -> String {
        guard let k = p.keychainKey, let v = KeychainStore.shared.get(k), !v.isEmpty else {
            throw NSError(domain: "Zuffi", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No API key yet. Add it in Settings → AI models."])
        }
        return v
    }

    // MARK: OpenAI (ChatGPT)

    private func callOpenAI(state: AppState) async throws -> String {
        let k = try key(.openai)
        var messages: [[String: Any]] = [["role": "system", "content": fullSystemPrompt]]
        for (i, m) in history.enumerated() {
            if i == history.count - 1, m.role == "user", let img = pendingImage {
                let parts: [[String: Any]] = [
                    ["type": "text", "text": m.text] as [String: Any],
                    ["type": "image_url", "image_url": ["url": "data:\(img.mime);base64,\(img.base64)"]] as [String: Any],
                ]
                messages.append(["role": "user", "content": parts])
            } else {
                messages.append(["role": m.role, "content": m.text])
            }
        }
        let chosen = state.openaiModel.isEmpty ? (UserDefaults.standard.string(forKey: "openaiResolved") ?? AppState.defaultOpenAIModel) : state.openaiModel
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var json: [String: Any]
        do {
            json = try await postJSON(url, body: ["model": chosen, "messages": messages], headers: ["Authorization": "Bearer \(k)"])
        } catch let error where Self.isModelProblem(error) {
            // That model was retired or isn't on this account — ask OpenAI which ones are, and use the best small one.
            let list = try await Self.listModels(URL(string: "https://api.openai.com/v1/models")!, auth: "Bearer \(k)")
            guard let pick = Self.best(list, prefer: ["gpt-5-mini", "gpt-5", "gpt-4.1-mini", "gpt-4o-mini", "gpt-4o", "gpt-"]) else { throw error }
            UserDefaults.standard.set(pick, forKey: "openaiResolved")
            json = try await postJSON(url, body: ["model": pick, "messages": messages], headers: ["Authorization": "Bearer \(k)"])
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else { throw Self.badResponse }
        return text
    }

    // MARK: Groq (very fast, free tier)

    private func callGroq(state: AppState) async throws -> String {
        let k = try key(.groq)
        var messages: [[String: Any]] = [["role": "system", "content": fullSystemPrompt]]
        for m in history { messages.append(["role": m.role, "content": m.text]) }
        let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        let chosen = UserDefaults.standard.string(forKey: "groqResolved") ?? "llama-3.3-70b-versatile"
        var json: [String: Any]
        do {
            json = try await postJSON(url, body: ["model": chosen, "messages": messages], headers: ["Authorization": "Bearer \(k)"], timeout: 30)
        } catch let error where Self.isModelProblem(error) {
            let list = try await Self.listModels(URL(string: "https://api.groq.com/openai/v1/models")!, auth: "Bearer \(k)")
            guard let pick = Self.best(list.filter { !$0.contains("whisper") && !$0.contains("guard") && !$0.contains("tts") },
                                       prefer: ["llama-3.3-70b", "llama-4", "gpt-oss-120b", "qwen", "llama-3.1-8b", "llama"]) else { throw error }
            UserDefaults.standard.set(pick, forKey: "groqResolved")
            json = try await postJSON(url, body: ["model": pick, "messages": messages], headers: ["Authorization": "Bearer \(k)"], timeout: 30)
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else { throw Self.badResponse }
        return text
    }

    // MARK: Model discovery (so Zuffi keeps working when providers retire models)

    static func isModelProblem(_ error: Error) -> Bool {
        let m = error.localizedDescription.lowercased()
        let code = (error as NSError).code
        return code == 404 || m.contains("model") && (m.contains("not found") || m.contains("no longer") || m.contains("deprecated")
            || m.contains("does not exist") || m.contains("not supported") || m.contains("decommissioned") || m.contains("unavailable"))
    }

    static func listModels(_ url: URL, auth: String) async throws -> [String] {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }

    /// First model matching the preference list (newest version wins within a match).
    static func best(_ ids: [String], prefer: [String]) -> String? {
        for p in prefer {
            let hits = ids.filter { $0.hasPrefix(p) || $0.contains(p) }
            if let h = hits.sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending }).first { return h }
        }
        return nil
    }

    static func newestGemini(key: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200")!, timeoutInterval: 15)
        req.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let (data, _) = try await URLSession.shared.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let models = (json["models"] as? [[String: Any]] ?? []).filter {
            ($0["supportedGenerationMethods"] as? [String] ?? []).contains("generateContent")
        }.compactMap { $0["name"] as? String }.map { $0.replacingOccurrences(of: "models/", with: "") }
        let usable = models.filter { !$0.contains("image") && !$0.contains("tts") && !$0.contains("embedding") && !$0.contains("live") && !$0.contains("audio") }
        func version(_ m: String) -> Double { Double(m.split(separator: "-").dropFirst().first ?? "0") ?? 0 }
        let stable = usable.filter { !$0.contains("preview") && !$0.contains("exp") }
        for pool in [stable, usable] {
            if let m = pool.filter({ $0.contains("flash") && !$0.contains("lite") }).max(by: { version($0) < version($1) }) { return m }
            if let m = pool.filter({ $0.contains("flash") }).max(by: { version($0) < version($1) }) { return m }
            if let m = pool.max(by: { version($0) < version($1) }) { return m }
        }
        throw NSError(domain: "Zuffi", code: 404, userInfo: [NSLocalizedDescriptionKey: "No Gemini model is available for this key."])
    }

    // MARK: Google Gemini

    private func callGemini(state: AppState) async throws -> String {
        let k = try key(.gemini)
        var contents: [[String: Any]] = []
        for (i, m) in history.enumerated() {
            var parts: [[String: Any]] = [["text": m.text]]
            if i == history.count - 1, m.role == "user", let img = pendingImage {
                parts.append(["inline_data": ["mime_type": img.mime, "data": img.base64]])
            }
            contents.append(["role": m.role == "assistant" ? "model" : "user", "parts": parts])
        }
        let chosen = state.geminiModel.isEmpty ? (UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel) : state.geminiModel
        let body: [String: Any] = ["system_instruction": ["parts": [["text": fullSystemPrompt]]], "contents": contents]
        func url(_ m: String) -> URL {
            let id = m.hasPrefix("models/") ? String(m.dropFirst(7)) : m
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(id):generateContent")!
        }
        var json: [String: Any]
        do {
            json = try await postJSON(url(chosen), body: body, headers: ["x-goog-api-key": k])
        } catch let error where Self.isModelProblem(error) {
            // Google retires models often — ask which ones this key can use and pick the newest Flash.
            let pick = try await Self.newestGemini(key: k)
            UserDefaults.standard.set(pick, forKey: "geminiResolved")
            appendAppLog("ai.log", "Gemini: switched to \(pick)")
            json = try await postJSON(url(pick), body: body, headers: ["x-goog-api-key": k])
        }
        guard let cands = json["candidates"] as? [[String: Any]],
              let content = cands.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else { throw Self.badResponse }
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    // MARK: Ollama (local, free)

    static func ollamaModels() async -> [String] {
        guard let url = URL(string: "http://127.0.0.1:11434/api/tags") else { return [] }
        let req = URLRequest(url: url, timeoutInterval: 1.5)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        // Only local chat models: skip embedding models and ":cloud" ones (they need an account + internet).
        let names = models.compactMap { $0["name"] as? String }.filter { n in
            let l = n.lowercased()
            return !l.contains("embed") && !l.contains("cloud") && !l.contains("nomic") && !l.contains("bge")
        }
        // Prefer small, fast models first (good on any Mac), then the rest.
        let preferred = ["llama3.2:latest", "llama3.2:3b", "qwen2.5:3b", "gemma3:4b", "qwen2.5:1.5b", "llama3.2:1b", "qwen3:4b", "phi3"]
        return names.sorted { a, b in
            let ia = preferred.firstIndex(where: { a.hasPrefix($0) }) ?? 99
            let ib = preferred.firstIndex(where: { b.hasPrefix($0) }) ?? 99
            return ia == ib ? a < b : ia < ib
        }
    }

    private func callOllama(state: AppState) async throws -> String {
        var model = state.ollamaModel
        if model.isEmpty {
            let installed = await Self.ollamaModels()
            guard let first = installed.first else {
                throw NSError(domain: "Zuffi", code: 0, userInfo: [NSLocalizedDescriptionKey:
                    "Ollama isn't running or has no models. Open Ollama, or pick another AI in Settings."])
            }
            model = first
        }
        var messages: [[String: Any]] = [["role": "system", "content": fullSystemPrompt]]
        for (i, m) in history.enumerated() {
            var msg: [String: Any] = ["role": m.role, "content": m.text]
            if i == history.count - 1, m.role == "user", let img = pendingImage { msg["images"] = [img.base64] }
            messages.append(msg)
        }
        let json = try await postJSON(URL(string: "http://127.0.0.1:11434/api/chat")!,
                                      body: ["model": model, "messages": messages, "stream": false,
                                             // Default window (2k tokens) is too small for a document.
                                             "options": ["num_ctx": document == nil ? 4096 : 8192]],
                                      headers: [:], timeout: 180)
        guard let msg = json["message"] as? [String: Any], let text = msg["content"] as? String else { throw Self.badResponse }
        return text
    }

    // MARK: Apple on-device model (Apple silicon, macOS 26+)

    static var appleModelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    private func callApple() async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), Self.appleModelAvailable {
            let session = LanguageModelSession(instructions: fullSystemPrompt)
            let transcript = history.suffix(12).map { ($0.role == "user" ? "User: " : "Zuffi: ") + $0.text }
                .joined(separator: "\n\n")
            let response = try await session.respond(to: transcript + "\n\nSparrow:")
            return response.content
        }
        #endif
        throw NSError(domain: "Zuffi", code: 0, userInfo: [NSLocalizedDescriptionKey:
            "Apple's on-device model needs a Mac with Apple silicon (M1 or newer) and Apple Intelligence turned on."])
    }

    private static let badResponse = NSError(domain: "Zuffi", code: 0,
                                             userInfo: [NSLocalizedDescriptionKey: "Unexpected answer from the AI."])
}

// MARK: - Provider picker shown in the chat

struct ProviderMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        let current = AIProvider(rawValue: state.aiProvider) ?? .auto
        Menu {
            ForEach(AIProvider.allCases) { p in
                Button {
                    state.aiProvider = p.rawValue
                    AIService.shared.clearConversation()
                } label: {
                    Label(p.label, systemImage: p.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: current.icon).font(.system(size: 9, weight: .semibold))
                Text(current.label).font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundColor(.white.opacity(0.75))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Settings section for every AI model

struct AIModelsSettings: View {
    @ObservedObject var state: AppState
    @State private var openaiKey: String = KeychainStore.shared.get("openai-api-key") ?? ""
    @State private var geminiKey: String = KeychainStore.shared.get("gemini-api-key") ?? ""
    @State private var groqKey: String = KeychainStore.shared.get("groq-api-key") ?? ""
    @State private var ollamaInstalled: [String] = []
    @State private var saved: String = ""

    var body: some View {
        GroupBox("AI models") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Use", selection: $state.aiProvider) {
                    ForEach(AIProvider.allCases) { p in Text(p.label).tag(p.rawValue) }
                }
                Text("Auto picks the first one that's set up: Claude, Groq, ChatGPT, Gemini, Apple, then Ollama — and if one fails, Zuffi quietly tries the next. Models are picked automatically. Opening apps, music and volume always work, even with nothing set up.")
                    .font(.system(size: 11)).foregroundColor(.secondary)

                InstalledAIView(state: state)

                Divider()
                Text("ChatGPT (OpenAI)").font(.system(size: 12, weight: .semibold))
                SecureField("API key (sk-…)", text: $openaiKey).textFieldStyle(.roundedBorder)
                TextField("Model (default \(AppState.defaultOpenAIModel))", text: $state.openaiModel).textFieldStyle(.roundedBorder)

                Divider()
                Text("Groq — the fastest, free key at console.groq.com").font(.system(size: 12, weight: .semibold))
                SecureField("API key (gsk_…)", text: $groqKey).textFieldStyle(.roundedBorder)

                Divider()
                Text("Gemini (Google)").font(.system(size: 12, weight: .semibold))
                SecureField("API key (AIza…)", text: $geminiKey).textFieldStyle(.roundedBorder)
                TextField("Model (default \(AppState.defaultGeminiModel))", text: $state.geminiModel).textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save keys") {
                        save("openai-api-key", openaiKey)
                        save("gemini-api-key", geminiKey)
                        save("groq-api-key", groqKey)
                        UserDefaults.standard.removeObject(forKey: "geminiResolved")
                        AIService.shared.clearConversation()
                        saved = "✓ Saved"
                    }
                    .buttonStyle(.borderedProminent)
                    Text(saved).font(.system(size: 11)).foregroundColor(.secondary)
                }

                Divider()
                Text("Ollama — free, runs on your computer").font(.system(size: 12, weight: .semibold))
                if ollamaInstalled.isEmpty {
                    Text("Not running. Install it from ollama.com, open it once, then come back.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                } else {
                    Picker("Model", selection: $state.ollamaModel) {
                        Text("Automatic (best small model)").tag("")
                        ForEach(ollamaInstalled, id: \.self) { Text($0).tag($0) }
                    }
                }

                Divider()
                HStack(spacing: 6) {
                    Image(systemName: AIService.appleModelAvailable ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(AIService.appleModelAvailable ? .green : .secondary)
                    Text(AIService.appleModelAvailable
                         ? "Apple's on-device model is available — free and private."
                         : "Apple's on-device model needs Apple silicon and Apple Intelligence.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(6)
        }
        .task { ollamaInstalled = await AIService.ollamaModels() }
    }

    private func save(_ key: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { KeychainStore.shared.remove(key) } else { KeychainStore.shared.set(key, value: v) }
    }
}
