import Foundation
import AppKit
import SwiftUI
import PDFKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Providers

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case auto, claude, openai, gemini, ollama, apple
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:   return "Auto"
        case .claude: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama (local)"
        case .apple:  return "Apple (on-device)"
        }
    }

    var icon: String {
        switch self {
        case .auto:   return "sparkles"
        case .claude: return "asterisk"
        case .openai: return "circle.hexagongrid"
        case .gemini: return "diamond"
        case .ollama: return "desktopcomputer"
        case .apple:  return "apple.logo"
        }
    }

    /// Whether this provider needs an API key the user pastes in Settings.
    var keychainKey: String? {
        switch self {
        case .claude: return "anthropic-api-key"
        case .openai: return "openai-api-key"
        case .gemini: return "gemini-api-key"
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

    static let systemPrompt = """
    You are Sparrow, a friendly, smart AI assistant that lives at the top of the user's computer screen. \
    Help with anything: questions, writing, summaries, translations, code, ideas and everyday tasks. \
    Reply in the user's language. Be clear and concise unless the user asks for detail. \
    Use plain text with line breaks, no markdown symbols like ** or ##.
    """

    func clearConversation() {
        history = []
        pendingImage = nil
        lastProvider = nil
        ClaudeService.shared.clearConversation()
    }

    // MARK: Entry point

    func chat(query: String, context: PromptContext?, state: AppState) async {
        // 1) Built-in commands run instantly, offline, with no API key.
        if let reply = await CommandEngine.shared.handle(query) {
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
            await ClaudeService.shared.chat(query: query, context: context, state: state)
            return
        }

        // 3) Build the turn (first turn carries the attached file / window).
        var turn = query
        if history.isEmpty, let context {
            let (prefix, image) = Self.describe(context)
            if !prefix.isEmpty { turn = prefix + "\n\n" + query }
            pendingImage = image
        }
        history.append((role: "user", text: turn))

        do {
            let reply: String
            switch provider {
            case .openai: reply = try await callOpenAI(state: state)
            case .gemini: reply = try await callGemini(state: state)
            case .ollama: reply = try await callOllama(state: state)
            case .apple:  reply = try await callApple()
            default:      reply = ""
            }
            pendingImage = nil
            let clean = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            history.append((role: "assistant", text: clean))
            finish(clean.isEmpty ? "(No answer.)" : clean, state: state, emote: .happy)
        } catch {
            history.removeLast()
            finish("⚠︎ \(provider.label): \(error.localizedDescription)", state: state, emote: .annoyed)
        }
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
        for p in [AIProvider.claude, .openai, .gemini] {
            if let k = p.keychainKey, let v = KeychainStore.shared.get(k), !v.isEmpty { return p }
        }
        if Self.appleModelAvailable { return .apple }
        let local = await Self.ollamaModels()
        if !local.isEmpty { return .ollama }
        return nil
    }

    // MARK: Context → text / image

    static func describe(_ context: PromptContext) -> (String, (mime: String, base64: String)?) {
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
            if ext == "pdf", let doc = PDFDocument(url: fileURL), let text = doc.string {
                return ("Attached PDF \"\(name)\":\n" + String(text.prefix(60_000)), nil)
            }
            if let data = try? Data(contentsOf: fileURL), data.count <= 300_000,
               let text = String(data: data, encoding: .utf8) {
                return ("Attached file \"\(name)\":\n" + text, nil)
            }
            return ("Attached file: \(name) (its content can't be read as text)", nil)
        }
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
            throw NSError(domain: "Sparrow", code: code, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        return json
    }

    private func key(_ p: AIProvider) throws -> String {
        guard let k = p.keychainKey, let v = KeychainStore.shared.get(k), !v.isEmpty else {
            throw NSError(domain: "Sparrow", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "No API key yet. Add it in Settings → AI models."])
        }
        return v
    }

    // MARK: OpenAI (ChatGPT)

    private func callOpenAI(state: AppState) async throws -> String {
        let k = try key(.openai)
        var messages: [[String: Any]] = [["role": "system", "content": Self.systemPrompt]]
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
        let model = state.openaiModel.isEmpty ? AppState.defaultOpenAIModel : state.openaiModel
        let json = try await postJSON(URL(string: "https://api.openai.com/v1/chat/completions")!,
                                      body: ["model": model, "messages": messages],
                                      headers: ["Authorization": "Bearer \(k)"])
        guard let choices = json["choices"] as? [[String: Any]],
              let msg = choices.first?["message"] as? [String: Any],
              let text = msg["content"] as? String else { throw Self.badResponse }
        return text
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
        let model = state.geminiModel.isEmpty ? AppState.defaultGeminiModel : state.geminiModel
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        let json = try await postJSON(url, body: [
            "system_instruction": ["parts": [["text": Self.systemPrompt]]],
            "contents": contents,
        ], headers: ["x-goog-api-key": k])
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
                throw NSError(domain: "Sparrow", code: 0, userInfo: [NSLocalizedDescriptionKey:
                    "Ollama isn't running or has no models. Open Ollama, or pick another AI in Settings."])
            }
            model = first
        }
        var messages: [[String: Any]] = [["role": "system", "content": Self.systemPrompt]]
        for (i, m) in history.enumerated() {
            var msg: [String: Any] = ["role": m.role, "content": m.text]
            if i == history.count - 1, m.role == "user", let img = pendingImage { msg["images"] = [img.base64] }
            messages.append(msg)
        }
        let json = try await postJSON(URL(string: "http://127.0.0.1:11434/api/chat")!,
                                      body: ["model": model, "messages": messages, "stream": false],
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
            let session = LanguageModelSession(instructions: Self.systemPrompt)
            let transcript = history.suffix(12).map { ($0.role == "user" ? "User: " : "Sparrow: ") + $0.text }
                .joined(separator: "\n\n")
            let response = try await session.respond(to: transcript + "\n\nSparrow:")
            return response.content
        }
        #endif
        throw NSError(domain: "Sparrow", code: 0, userInfo: [NSLocalizedDescriptionKey:
            "Apple's on-device model needs a Mac with Apple silicon (M1 or newer) and Apple Intelligence turned on."])
    }

    private static let badResponse = NSError(domain: "Sparrow", code: 0,
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
    @State private var ollamaInstalled: [String] = []
    @State private var saved: String = ""

    var body: some View {
        GroupBox("AI models") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Use", selection: $state.aiProvider) {
                    ForEach(AIProvider.allCases) { p in Text(p.label).tag(p.rawValue) }
                }
                Text("Auto picks the first one that's set up: Claude, ChatGPT, Gemini, Apple, then Ollama. Opening apps, music and volume always work, even with nothing set up.")
                    .font(.system(size: 11)).foregroundColor(.secondary)

                Divider()
                Text("ChatGPT (OpenAI)").font(.system(size: 12, weight: .semibold))
                SecureField("API key (sk-…)", text: $openaiKey).textFieldStyle(.roundedBorder)
                TextField("Model (default \(AppState.defaultOpenAIModel))", text: $state.openaiModel).textFieldStyle(.roundedBorder)

                Divider()
                Text("Gemini (Google)").font(.system(size: 12, weight: .semibold))
                SecureField("API key (AIza…)", text: $geminiKey).textFieldStyle(.roundedBorder)
                TextField("Model (default \(AppState.defaultGeminiModel))", text: $state.geminiModel).textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save keys") {
                        save("openai-api-key", openaiKey)
                        save("gemini-api-key", geminiKey)
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
