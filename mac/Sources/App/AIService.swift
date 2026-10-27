import Foundation
import AppKit
import SwiftUI
import PDFKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Providers

enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case auto, zuffi, claude, openai, gemini, groq, grok, deepseek, mistral, perplexity, openrouter, ollama, apple, claudeCode, codex, geminiCLI
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:   return "Auto"
        case .zuffi:  return "Zuffi AI (included in your plan)"
        case .claude: return "Claude"
        case .openai: return "ChatGPT"
        case .gemini: return "Gemini"
        case .groq:   return "Groq (fast, free)"
        case .grok:   return "Grok (xAI)"
        case .deepseek: return "DeepSeek"
        case .mistral: return "Mistral"
        case .perplexity: return "Perplexity (web answers)"
        case .openrouter: return "OpenRouter (any model)"
        case .geminiCLI: return "My Gemini (Gemini CLI)"
        case .ollama: return "Ollama (local)"
        case .apple:  return "Apple (on-device)"
        case .claudeCode: return "My Claude (Claude Code)"
        case .codex:  return "My ChatGPT (Codex)"
        }
    }

    var icon: String {
        switch self {
        case .auto:   return "sparkles"
        case .zuffi:  return "hare.fill"
        case .claude: return "asterisk"
        case .openai: return "circle.hexagongrid"
        case .gemini: return "diamond"
        case .groq:   return "bolt.fill"
        case .grok:   return "xmark.diamond"
        case .deepseek: return "water.waves"
        case .mistral: return "wind"
        case .perplexity: return "globe"
        case .openrouter: return "arrow.triangle.branch"
        case .geminiCLI: return "terminal"
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
        case .grok:   return "xai-api-key"
        case .deepseek: return "deepseek-api-key"
        case .mistral: return "mistral-api-key"
        case .perplexity: return "perplexity-api-key"
        case .openrouter: return "openrouter-api-key"
        default:      return nil
        }
    }

    /// OpenAI-compatible providers: (chat URL, default model, models URL, preferred model prefixes).
    var openAICompatible: (url: String, model: String, models: String, prefer: [String])? {
        switch self {
        case .grok: return ("https://api.x.ai/v1/chat/completions", "grok-4-fast-non-reasoning", "https://api.x.ai/v1/models", ["grok-4-fast-non-reasoning", "grok-4-fast", "grok-3-mini", "grok-4", "grok"])
        case .deepseek: return ("https://api.deepseek.com/chat/completions", "deepseek-chat", "https://api.deepseek.com/models", ["deepseek-chat", "deepseek"])
        case .mistral: return ("https://api.mistral.ai/v1/chat/completions", "mistral-large-latest", "https://api.mistral.ai/v1/models", ["mistral-large", "mistral-medium", "mistral"])
        case .perplexity: return ("https://api.perplexity.ai/chat/completions", "sonar", "", ["sonar"])
        case .openrouter: return ("https://openrouter.ai/api/v1/chat/completions", "openrouter/auto", "", ["openrouter/auto"])
        default: return nil
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
    IMPORTANT: in this chat you cannot open apps, create files or folders, change settings or send messages yourself — never say you did. \
    If the user asks for one of those, say it didn't work from here and suggest the exact words, e.g. “open business page”, “make a folder called …”, “switch to male voice”. \
    Use plain text with line breaks, no markdown symbols like ** or ##.
    """

    /// System prompt plus the attached document (if any).
    private var oneShotSystem: String?
    /// Does the current question ask about Zuffi herself (features, plans, prices, how to…)?
    private var wantsAbout = true
    /// Who the user is: the welcome form and everything they asked Zuffi to remember (sent by the app's web part), else the Mac's own copy of the form.
    static var userFacts: String {
        let f = UserDefaults.standard.string(forKey: "zuffiFacts") ?? ""
        // The business (services, prices, customers) only joins in when you're talking to Nik — never the everyday chat.
        let biz = ZuffiChat.shared.who == .nik ? ZuffiCRM.shared.memoryContext() : ""
        return (f.isEmpty ? ZuffiPlan.shared.profileLine : f) + ZuffiMemory.shared.itemsLine + biz + RoomListener.shared.contextLine
    }

    /// "which one is cheapest?", "and the route?", "what about tuesday" — a follow-up to the last job, not a new request.
    static func isFollowUp(_ q: String, after a: TeamAgent) -> Bool {
        let t = q.lowercased()
        if let f = ZuffiTeam.intent(t), f != AgentField.of(a) { return false }
        let short = t.split(separator: " ").count <= 16
        let refers = t.range(of: #"\b(which|that|those|these|it|them|cheapest|best|route|via|stop|stops|when|time|times|how long|duration|details?|more|other|compare|first|second|third|last|book|link)\b"#, options: .regularExpression) != nil
        return short && refers
    }
    nonisolated static func asksAboutZuffi(_ q: String) -> Bool {
        q.lowercased().range(of: #"\b(zuffi|sparrow|you|your|yourself|app|plan|plans|pro|business|price|prices|cost|subscription|trial|feature|features|setting|settings|how (do|can|to)|can i|where is|what can|help|lisan)\b"#, options: .regularExpression) != nil
    }

    var fullSystemPrompt: String {
        if let o = oneShotSystem { return o }
        // Zuffi's long self-description only when the question is about Zuffi: a short prompt answers much faster.
        // A team agent is picked: it answers as that person, with the business details — not Zuffi's long self-description.
        let base = ZuffiTeam.shared.active.map { ZuffiTeam.shared.systemPrompt(for: $0) }
            ?? (Self.systemPrompt + Self.userFacts + "\n" + (wantsAbout ? ZuffiAbout.text + "\n" : ""))
        guard let document else { return base }
        return base + """


        The user attached a file. Its content is below, between <file> and </file>. \
        Answer the user's questions using this file. When they say "the file", "the document", "this PDF" \
        or ask about a person, project or detail in it, they mean this file. Quote facts from it; \
        if something isn't in the file, say so.

        <file>
        \(document)
        </file>
        """
    }

    /// Keeps a turn answered outside the AI (team intros, the Team Manager) so follow-up questions have the context.
    func remember(user: String, assistant: String) {
        history.append((role: "user", text: user)); history.append((role: "assistant", text: assistant))
        if history.count > 30 { history.removeFirst(history.count - 30) }
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
        if ZuffiPlan.shared.isLocked { finish(ZuffiPlan.shared.lockedMessage, state: state, emote: .happy); ZuffiPlan.shared.openAccount(); return }
        var context = context
        let who = ZuffiChat.shared.who
        let team = ZuffiTeam.shared
        // An agent asked you something ("which city?"): this message goes back to it, with the original task.
        if context == nil, let w = team.awaiting, Date().timeIntervalSince(w.at) < 20 * 60, !ZuffiTeam.looksLikeCommand(query) {
            team.awaiting = nil
            state.stateOverride = .thinking
            let run = await team.work(w.agent, w.task + "\nMore details from the owner: " + query)
            let r = "\(w.agent.name):\n\(run.result)"
            remember(user: query, assistant: r); finish(r, state: state, emote: .happy); return
        }
        // A follow-up about the last job ("which one is cheapest, and the route?") goes back to the same agent, with the same facts.
        if context == nil, let lw = team.lastWork, Date().timeIntervalSince(lw.at) < 30 * 60, Self.isFollowUp(query, after: lw.agent) {
            state.stateOverride = .thinking
            let r: String
            if AgentField.of(lw.agent) == .travel, let fp = team.flightPage {
                r = "\(lw.agent.name):\n" + (await team.flightAnswer(lw.agent, question: query, trip: fp.trip, page: fp.text, url: fp.url)).0
            } else {
                let run = await team.work(lw.agent, "Earlier task: \(lw.task)\nYour earlier answer:\n\(lw.result.prefix(2500))\n\nFollow-up from the owner: \(query)\nAnswer the follow-up using your earlier answer and its facts.")
                r = "\(lw.agent.name):\n\(run.result)"
            }
            remember(user: query, assistant: r); finish(r, state: state, emote: .happy); return
        }
        // 0) Zuffi's team: "use the finance agent", "who are you?", "who are you guys?", "assign … to research and product manager"
        if let r = await team.handle(query) {
            remember(user: query, assistant: r)
            finish(r, state: state, emote: .happy); return
        }
        // Talking to one agent (picked at the top of the chat).
        if context == nil, case .agent(let id) = who, let a = team.agent(id), !ZuffiTeam.looksLikeCommand(query) {
            state.stateOverride = .thinking
            let r = await team.ask(query, who: [a])
            remember(user: query, assistant: r)
            finish(r, state: state, emote: .happy); return
        }
        // Talking to Nik: business questions — he gives each to the right business agent and sums up.
        if context == nil, who == .nik, !ZuffiTeam.looksLikeCommand(query) {
            state.stateOverride = .thinking
            let r = await team.dispatch(query) ?? (await team.answer(query, people: [ZuffiTeam.manager], routeOnly: false))
            remember(user: query, assistant: r)
            finish(r, state: state, emote: .happy); return
        }
        let business = who == .nik
        // "What's our profit today?" / "how many bookings today?" — straight from the Money page, bookings and the dashboard, never guessed.
        if context == nil, business, ZuffiPlan.shared.isBusiness, ZuffiTeam.isFiguresQuestion(query),
           query.lowercased().range(of: #"\b(our|my|we|us|today|yesterday|this (week|month)|last (week|month))\b"#, options: .regularExpression) != nil,
           let f = ZuffiTeam.intent(query), f == .finance || f == .bookings {
            let r = f == .finance ? TeamData.financeAnswer(query).0 : TeamData.bookingsAnswer(query).0
            remember(user: query, assistant: r)
            finish(r, state: state, emote: .happy); return
        }
        let agentOn = false
        // 0) Questions about the user ("what's my date of birth?") — from the welcome form, no AI, works offline.
        if context == nil, let me = await ZuffiPlan.shared.aboutMe(query) { finish(me, state: state, emote: .happy); return }
        // 0b) Your business data — only with Nik (the everyday chat never mixes in the business).
        if business, let r = ZuffiCRM.shared.handle(query) { finish(r, state: state, emote: .happy); return }
        if business, let r = ZuffiMoney.shared.handle(query) { finish(r, state: state, emote: .happy); return }
        if business, let r = await ZuffiProperties.shared.handle(query) { finish(r, state: state, emote: .happy); return }
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
        if let r = await ZuffiPA.shared.handle(query) { finish(r, state: state, emote: .happy); return }
        // Everyday jobs (flights, research, a website, writing): Zuffi gives them to her own helpers — never the business agents.
        if context == nil, ZuffiPlan.shared.isPaid {
            state.stateOverride = .thinking
            if let r = await team.dispatch(query, personalOnly: true) { remember(user: query, assistant: r); finish(r, state: state, emote: .happy); return }
            state.stateOverride = nil
        }
        // 1) Built-in commands run instantly, offline, with no API key.
        if let reply = await AgentRouter.shared.handle(query) {
            finish(reply, state: state, emote: .happy)
            return
        }
        // 1b) Everything else Zuffi can do offline (habits, prayer times, memory, invoices, time, expenses…).
        if context == nil, !agentOn, let reply = await WebHub.shared.ask(query) {
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
            await ClaudeService.shared.chat(query: agentOn ? query : ZuffiData.shared.augment(query), context: context, state: state)
            return
        }

        // 3) Attachments. A file's text lives in the system prompt for the whole
        //    conversation, so follow-up questions still "see" it. A newly attached
        //    file starts a fresh conversation about that file.
        wantsAbout = Self.asksAboutZuffi(query)
        // Saved spreadsheets only join in for plain Zuffi (an agent answering "who are you" mustn't start reading a sheet).
        var turn = agentOn ? query : ZuffiData.shared.augment(query)
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
                if p == .ollama || p == .apple { AIUsage.shared.current = p == .ollama ? "Ollama (offline)" : "Apple (on-device)" }
                finish(clean, state: state, emote: .happy)
                return
            } catch {
                lastError = error
                appendAppLog("ai.log", "\(p.label) failed: \(error.localizedDescription)")
                // Out of quota / tokens / credit: rest this AI for an hour and quietly use the next one.
                let m = error.localizedDescription.lowercased(), code = (error as NSError).code
                if code == 429 || code == 402 || m.contains("quota") || m.contains("rate limit") || m.contains("insufficient") || m.contains("credit") || m.contains("exceeded") {
                    AIUsage.shared.rest(p.label, minutes: 60)
                    NotificationCenter.default.post(name: .petSay, object: "\(p.label) is out of tokens for now — I’ll use another AI.")
                }
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
        case .zuffi:  return try await callZuffi()
        case .apple:  return try await callApple()
        case .grok, .deepseek, .mistral, .perplexity, .openrouter: return try await callCompatible(p)
        case .claudeCode, .codex, .geminiCLI:
            guard let tool = p == .claudeCode ? InstalledAI.claudeCode : p == .codex ? InstalledAI.codex : InstalledAI.geminiCLI else {
                throw NSError(domain: "Zuffi", code: 0, userInfo: [NSLocalizedDescriptionKey: "\(p.label) isn't installed on this Mac."])
            }
            return try await InstalledAI.ask(tool, prompt: cliPrompt())
        default:      return ""
        }
    }

    /// One prompt for a command-line AI: Zuffi's instructions, any document, and the recent conversation.
    private func cliPrompt() -> String {
        var t = oneShotSystem.map { $0 + " Do not use tools or edit files.\n" }
            ?? ZuffiTeam.shared.active.map { ZuffiTeam.shared.systemPrompt(for: $0) + "\nDo not use tools or edit files.\n" }
            ?? ("You are Zuffi, a friendly personal assistant on the user's Mac. Answer briefly and helpfully, in the user's language. Do not use tools or edit files — just answer.\n" + Self.userFacts + ZuffiAbout.text + "\n")
        if let d = document { t += "\nDocument the user shared:\n\(d.prefix(20_000))\n" }
        for m in history.suffix(12) { t += "\n\(m.role == "assistant" ? "Zuffi" : "User"): \(m.text)" }
        return t + "\nZuffi:"
    }

    /// The chosen provider, then every other one that is ready (keys first, then on-device).
    private func fallbackChain(first: AIProvider) async -> [AIProvider] {
        var out: [AIProvider] = [first]
        if !NetStatus.shared.online {                                   // offline: only the brains on this Mac can answer
            if first != .ollama, !(await Self.ollamaModels()).isEmpty { out.append(.ollama) }
            if first != .apple, Self.appleModelAvailable { out.append(.apple) }
            return out
        }
        for p in [AIProvider.groq, .gemini, .openai, .grok, .deepseek, .mistral, .openrouter] where p != first {
            if let k = p.keychainKey, let v = KeychainStore.shared.get(k), !v.isEmpty { out.append(p) }
        }
        // AIs that just ran out of tokens go to the back of the line.
        if first != .zuffi, Self.builtinAvailable { out.append(.zuffi) }
        out = out.filter { !AIUsage.shared.resting($0.label) } + out.filter { AIUsage.shared.resting($0.label) }
        if first != .apple, Self.appleModelAvailable { out.append(.apple) }
        if first != .ollama, !(await Self.ollamaModels()).isEmpty { out.append(.ollama) }
        return out
    }

    private func finish(_ text: String, state: AppState, emote: BotEmote) {
        state.chatHistory.append(ChatMessage(role: .assistant, content: zClean(text)))
        state.stateOverride = nil
        state.view = .prompt
        NotificationCenter.default.post(name: .triggerEmote, object: emote)
    }

    // MARK: Provider choice

    func resolveProvider(state: AppState) async -> AIProvider? {
        let chosen = AIProvider(rawValue: state.aiProvider) ?? .auto
        // No internet: answer with the brain on this Mac (Ollama, or Apple's model) instead of failing.
        if !NetStatus.shared.online, chosen != .ollama, chosen != .apple {
            if !(await Self.ollamaModels()).isEmpty { return .ollama }
            if Self.appleModelAvailable { return .apple }
        }
        if chosen != .auto { return chosen }
        for p in [AIProvider.claude, .groq, .openai, .gemini, .grok, .deepseek, .mistral, .perplexity, .openrouter] where !AIUsage.shared.resting(p.label) {
            if let k = p.keychainKey, let v = KeychainStore.shared.get(k), !v.isEmpty { return p }
        }
        // The AI that comes with Pro / Business — fast, nothing to set up, the key stays on Zuffi's server.
        if Self.builtinAvailable { return .zuffi }
        // The subscription you already pay for (Claude Code / Codex), if installed.
        if InstalledAI.claudeCode != nil { return .claudeCode }
        if InstalledAI.codex != nil { return .codex }
        if InstalledAI.geminiCLI != nil { return .geminiCLI }
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
        AIUsage.shared.record(url: url.absoluteString, model: body["model"] as? String ?? url.lastPathComponent, json: json)
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
            json = try await postJSON(url, body: ["model": chosen, "messages": messages, "max_tokens": 1200], headers: ["Authorization": "Bearer \(k)"], timeout: 30)
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

    // MARK: One quiet question (used by the PA to turn your words into rows)

    /// Asks whichever AI is set up, without touching the chat. Returns nil when no AI is available.
    private var oneShotBusy = false
    func oneShot(_ prompt: String, system: String = "You turn the user's words into exactly the JSON asked for. Reply with JSON only.") async -> String? {
        // One at a time: it borrows the chat's state, so two at once (team members working together) would mix up their instructions.
        while oneShotBusy { try? await Task.sleep(nanoseconds: 60_000_000) }
        oneShotBusy = true
        defer { oneShotBusy = false }
        let savedHistory = history, savedDoc = document, savedImage = pendingImage
        history = [(role: "user", text: prompt)]; document = nil; pendingImage = nil; oneShotSystem = system
        defer { history = savedHistory; document = savedDoc; pendingImage = savedImage; oneShotSystem = nil }
        if let k = KeychainStore.shared.get("anthropic-api-key"), !k.isEmpty,
           let j = try? await postJSON(URL(string: "https://api.anthropic.com/v1/messages")!,
                                       body: ["model": AppState.shared.claudeModel.isEmpty ? AppState.defaultClaudeModel : AppState.shared.claudeModel,
                                              "max_tokens": 4000, "system": system, "messages": [["role": "user", "content": prompt]]],
                                       headers: ["x-api-key": k, "anthropic-version": "2023-06-01"], timeout: 60),
           let parts = j["content"] as? [[String: Any]] {
            let t = parts.compactMap { $0["text"] as? String }.joined()
            if !t.isEmpty { return t }
        }
        guard let first = await resolveProvider(state: AppState.shared) else { return nil }
        for p in await fallbackChain(first: first) where p != .claude {
            if let r = try? await call(p, state: AppState.shared), !r.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return r }
        }
        return nil
    }

    /// Pulls the first JSON object or array out of an AI reply (which may be wrapped in ``` fences).
    static func jsonIn(_ text: String) -> Any? {
        let t = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let a = t.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        // Walk to the matching bracket (ignoring brackets inside strings), so extra text or a stray "}" after it doesn't break parsing.
        let open = t[a], close: Character = open == "{" ? "}" : "]"
        var depth = 0, inString = false, escaped = false, end: String.Index?
        var i = a
        while i < t.endIndex {
            let c = t[i]
            if inString {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
            } else if c == "\"" { inString = true }
            else if c == open { depth += 1 }
            else if c == close { depth -= 1; if depth == 0 { end = i; break } }
            i = t.index(after: i)
        }
        if let end, let v = try? JSONSerialization.jsonObject(with: Data(t[a...end].utf8)) { return v }
        if let b = t.lastIndex(of: close), a < b { return try? JSONSerialization.jsonObject(with: Data(t[a...b].utf8)) }
        return nil
    }

    /// A quick JSON answer for business chats: Groq (fastest) → Gemini Flash → OpenAI mini → whatever else is set up.
    func fastJSON(_ prompt: String, system: String) async -> [String: Any]? {
        func parse(_ s: String?) -> [String: Any]? { s.flatMap { Self.jsonIn($0) as? [String: Any] } }
        let msgs: [[String: Any]] = [["role": "system", "content": system], ["role": "user", "content": prompt]]
        if let k = KeychainStore.shared.get("groq-api-key"), !k.isEmpty,
           let j = try? await postJSON(URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                                       body: ["model": UserDefaults.standard.string(forKey: "groqResolved") ?? "llama-3.3-70b-versatile", "temperature": 0.3, "max_tokens": 500,
                                              "response_format": ["type": "json_object"], "messages": msgs], headers: ["Authorization": "Bearer \(k)"], timeout: 15),
           let r = parse(((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) { return r }
        if let k = KeychainStore.shared.get("gemini-api-key"), !k.isEmpty {
            let model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
            if let j = try? await postJSON(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                                           body: ["system_instruction": ["parts": [["text": system]]], "contents": [["role": "user", "parts": [["text": prompt]]]],
                                                  "generationConfig": ["temperature": 0.3, "responseMimeType": "application/json"]], headers: ["x-goog-api-key": k], timeout: 15) {
                let parts = (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                if let r = parse(parts.compactMap { $0["text"] as? String }.joined()) { return r }
            }
        }
        if let k = KeychainStore.shared.get("openai-api-key"), !k.isEmpty,
           let j = try? await postJSON(URL(string: "https://api.openai.com/v1/chat/completions")!,
                                       body: ["model": "gpt-4o-mini", "temperature": 0.3, "response_format": ["type": "json_object"], "messages": msgs],
                                       headers: ["Authorization": "Bearer \(k)"], timeout: 15),
           let r = parse(((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) { return r }
        if Self.builtinAvailable, let t = await Self.builtin([["role": "system", "content": system + " Reply with JSON only."], ["role": "user", "content": prompt]], max: 700),
           let r = parse(t) { return r }
        return parse(await oneShot(prompt, system: system))
    }

    // MARK: Zuffi AI — included with Pro and Business (through Zuffi's server, the key never touches this Mac)

    /// On a paid plan (or the trial) and signed in.
    static var builtinAvailable: Bool { ZuffiPlan.shared.isPaid && NetStatus.shared.online && !AIUsage.shared.resting("Zuffi AI") }

    static func builtin(_ messages: [[String: String]], max: Int = 900) async -> String? {
        guard let r = await WebHub.shared.callJS("return await window.Sparrow.builtinAI(m, x)", ["m": messages, "x": max]) as? [String: Any] else { return nil }
        if let t = r["text"] as? String, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        // out of answers this month → rest for an hour; not switched on / signed out → try again in 10 minutes
        if let e = r["error"] as? String { AIUsage.shared.rest("Zuffi AI", minutes: e == "limit" ? 60 : 10) }
        return nil
    }

    /// One answer with its own instructions, without touching the chat (team members, the Team Manager).
    /// Zuffi AI (in the plan) → Groq → Gemini → OpenAI → whatever else is set up. `web`: look things up first (research).
    func textAnswer(system: String, messages: [[String: String]], max: Int = 900, web: Bool = false) async -> String? {
        await textAnswerFull(system: system, messages: messages, max: max, web: web).text
    }

    /// The same, plus the web pages it used (research shows them as links).
    func textAnswerFull(system: String, messages: [[String: String]], max: Int = 900, web: Bool = false, notes known: String? = nil) async -> (text: String?, links: [WebLink]) {
        func clean(_ s: String?) -> String? { let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines); return t.isEmpty ? nil : t }
        let gem = KeychainStore.shared.get("gemini-api-key") ?? ""
        let msgs: [[String: String]] = [["role": "system", "content": system]] + messages
        // Research with Google Search through Gemini when there's a Gemini key.
        if web, !gem.isEmpty, NetStatus.shared.online {
            let model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
            let contents = messages.map { ["role": $0["role"] == "assistant" ? "model" : "user", "parts": [["text": $0["content"] ?? ""]]] as [String: Any] }
            if let j = try? await postJSON(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                                           body: ["system_instruction": ["parts": [["text": system]]], "contents": contents, "tools": [["google_search": [String: Any]()]]],
                                           headers: ["x-goog-api-key": gem], timeout: 40) {
                let cand = (j["candidates"] as? [[String: Any]])?.first
                let parts = ((cand?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                let chunks = ((cand?["groundingMetadata"] as? [String: Any])?["groundingChunks"] as? [[String: Any]]) ?? []
                let links = chunks.compactMap { c -> WebLink? in
                    guard let w = c["web"] as? [String: Any], let u = w["uri"] as? String else { return nil }
                    return WebLink(title: (w["title"] as? String) ?? u, url: u)
                }
                if let t = clean(parts.compactMap { $0["text"] as? String }.joined()) { return (t, links) }
            }
        }
        var system = system, msgs2 = msgs
        var found: [WebLink] = []
        if web, NetStatus.shared.online {
            var notes = known
            if notes == nil { let r = await Self.webSearch(messages.last?["content"] ?? ""); notes = r.notes.isEmpty ? nil : r.notes; found = r.links }
            if let notes {
                system += "\n\nWEB NOTES (looked up just now — use them, name the source of each fact, and say when something isn't covered):\n" + notes
                msgs2[0] = ["role": "system", "content": system]
            }
        }
        if Self.builtinAvailable, let t = clean(await Self.builtin(msgs2, max: max)) { return (t, found) }
        let oa: [[String: Any]] = msgs2.map { $0 as [String: Any] }
        if let k = KeychainStore.shared.get("groq-api-key"), !k.isEmpty,
           let j = try? await postJSON(URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                                       body: ["model": UserDefaults.standard.string(forKey: "groqResolved") ?? "llama-3.3-70b-versatile", "temperature": 0.5, "max_tokens": max, "messages": oa],
                                       headers: ["Authorization": "Bearer \(k)"], timeout: 30),
           let t = clean(((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) { return (t, found) }
        if !gem.isEmpty {
            let model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
            let contents = msgs2.dropFirst().map { ["role": $0["role"] == "assistant" ? "model" : "user", "parts": [["text": $0["content"] ?? ""]]] as [String: Any] }
            if let j = try? await postJSON(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                                           body: ["system_instruction": ["parts": [["text": system]]], "contents": Array(contents)], headers: ["x-goog-api-key": gem], timeout: 30) {
                let parts = (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                if let t = clean(parts.compactMap { $0["text"] as? String }.joined()) { return (t, found) }
            }
        }
        if let k = KeychainStore.shared.get("openai-api-key"), !k.isEmpty,
           let j = try? await postJSON(URL(string: "https://api.openai.com/v1/chat/completions")!,
                                       body: ["model": "gpt-4o-mini", "temperature": 0.5, "max_tokens": max, "messages": oa], headers: ["Authorization": "Bearer \(k)"], timeout: 30),
           let t = clean(((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) { return (t, found) }
        // Last: whatever else is set up (Claude, other keys, Ollama on this Mac…), one at a time.
        let convo = msgs2.dropFirst().map { ($0["role"] == "assistant" ? "Earlier answer: " : "") + ($0["content"] ?? "") }.joined(separator: "\n\n")
        return (clean(await oneShot(convo, system: system)), found)
    }

    /// Free web look-up for research (no key): Google News (latest), DuckDuckGo and Wikipedia — notes for the AI plus the pages, as links.
    static func webSearch(_ q: String) async -> (notes: String, links: [WebLink]) {
        let query = String(q.replacingOccurrences(of: #"(?i)^(please |zuffi,? )?(research|search|look up|find out|find)( for me)?( about| on| the)?( topic( is)?)?[: ]*"#, with: "", options: .regularExpression).prefix(160))
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return ("", []) }
        var out: [String] = [], links: [WebLink] = []
        // Latest news first (free RSS, no key)
        if let u = URL(string: "https://news.google.com/rss/search?q=\(enc)&hl=en-GB&gl=GB&ceid=GB:en"),
           let r = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 7)),
           let xml = String(data: r.0, encoding: .utf8) {
            let items = xml.components(separatedBy: "<item>").dropFirst().prefix(6)
            for it in items {
                func tag(_ n: String) -> String {
                    guard let a = it.range(of: "<\(n)>"), let b = it.range(of: "</\(n)>", range: a.upperBound..<it.endIndex) else { return "" }
                    return String(it[a.upperBound..<b.lowerBound]).replacingOccurrences(of: "<![CDATA[", with: "").replacingOccurrences(of: "]]>", with: "")
                        .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#39;", with: "'").replacingOccurrences(of: "&quot;", with: "\"")
                }
                let title = tag("title"), link = tag("link"), date = tag("pubDate")
                guard !title.isEmpty, !link.isEmpty else { continue }
                out.append("• \(title) — \(date.prefix(16)) (Google News)")
                links.append(WebLink(title: title, url: link))
            }
        }
        if let u = URL(string: "https://api.duckduckgo.com/?q=\(enc)&format=json&no_html=1&skip_disambig=1"),
           let r = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 6)),
           let j = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any] {
            if let a = j["AbstractText"] as? String, !a.isEmpty {
                out.append("• \(a) (\((j["AbstractSource"] as? String) ?? "DuckDuckGo"))")
                if let url = j["AbstractURL"] as? String, !url.isEmpty { links.append(WebLink(title: (j["Heading"] as? String) ?? url, url: url)) }
            }
            for t in ((j["RelatedTopics"] as? [[String: Any]]) ?? []).prefix(3) { if let x = t["Text"] as? String { out.append("• \(x) (DuckDuckGo)") } }
        }
        if let u = URL(string: "https://en.wikipedia.org/w/api.php?action=query&list=search&format=json&srlimit=3&srsearch=\(enc)"),
           let r = try? await URLSession.shared.data(for: URLRequest(url: u, timeoutInterval: 6)),
           let j = try? JSONSerialization.jsonObject(with: r.0) as? [String: Any],
           let hits = (j["query"] as? [String: Any])?["search"] as? [[String: Any]] {
            for h in hits {
                let title = (h["title"] as? String) ?? ""
                let snip = ((h["snippet"] as? String) ?? "").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                out.append("• \(title): \(snip) (Wikipedia)")
                if let t = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) { links.append(WebLink(title: "Wikipedia: \(title)", url: "https://en.wikipedia.org/wiki/\(t)")) }
            }
        }
        return (out.joined(separator: "\n"), links)
    }

    static func webNotes(_ q: String) async -> String? { let r = await webSearch(q); return r.notes.isEmpty ? nil : r.notes }

    private func callZuffi() async throws -> String {
        var msgs: [[String: String]] = [["role": "system", "content": fullSystemPrompt]]
        for m in history.suffix(16) { msgs.append(["role": m.role == "assistant" ? "assistant" : "user", "content": m.text]) }
        guard let t = await Self.builtin(msgs, max: 1200) else {
            throw NSError(domain: "Zuffi", code: 0, userInfo: [NSLocalizedDescriptionKey: "Zuffi AI is busy or not switched on yet."])
        }
        return t
    }

    // MARK: Grok, DeepSeek, Mistral, Perplexity, OpenRouter (all OpenAI-style)

    private func callCompatible(_ p: AIProvider) async throws -> String {
        guard let c = p.openAICompatible else { throw Self.badResponse }
        let k = try key(p)
        var messages: [[String: Any]] = [["role": "system", "content": fullSystemPrompt]]
        for m in history { messages.append(["role": m.role, "content": m.text]) }
        let url = URL(string: c.url)!
        let saved = "\(p.rawValue)Resolved"
        let chosen = UserDefaults.standard.string(forKey: saved) ?? c.model
        var headers = ["Authorization": "Bearer \(k)"]
        if p == .openrouter { headers["HTTP-Referer"] = "https://zuffi.app"; headers["X-Title"] = "Zuffi" }
        var json: [String: Any]
        do {
            json = try await postJSON(url, body: ["model": chosen, "messages": messages, "max_tokens": 1200], headers: headers, timeout: 45)
        } catch let error where Self.isModelProblem(error) && !c.models.isEmpty {
            let list = try await Self.listModels(URL(string: c.models)!, auth: "Bearer \(k)")
            guard let pick = Self.best(list.filter { !$0.contains("image") && !$0.contains("embed") && !$0.contains("vision") }, prefer: c.prefer) else { throw error }
            UserDefaults.standard.set(pick, forKey: saved)
            json = try await postJSON(url, body: ["model": pick, "messages": messages], headers: headers, timeout: 60)
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
        var body: [String: Any] = ["system_instruction": ["parts": [["text": fullSystemPrompt]]], "contents": contents]
        // Flash models "think" before answering by default — off for chat, so replies start in about a second.
        if chosen.contains("2.5-flash") { body["generationConfig"] = ["maxOutputTokens": 1500, "thinkingConfig": ["thinkingBudget": 0] as [String: Any]] as [String: Any] }
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

    /// 16 GB of memory or more: room for a bigger, smarter offline model.
    nonisolated static var bigMac: Bool { ProcessInfo.processInfo.physicalMemory >= 15 * 1_073_741_824 }
    /// The model "Get the offline brain" downloads (Qwen 2.5: strong in English, Urdu, Hindi and Arabic).
    nonisolated static var recommendedOllama: String { bigMac ? "qwen2.5:7b" : "qwen2.5:3b" }

    static func ollamaRunning() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/version") else { return false }
        let req = URLRequest(url: url, timeoutInterval: 1.5)
        return ((try? await URLSession.shared.data(for: req))?.1 as? HTTPURLResponse)?.statusCode == 200
    }

    /// Downloads a model into Ollama, reporting progress 0…1.
    static func pullOllama(_ name: String, progress: @escaping @MainActor (Double, String) -> Void) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:11434/api/pull") else { return false }
        var req = URLRequest(url: url, timeoutInterval: 3600)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["name": name, "stream": true])
        guard let (bytes, resp) = try? await URLSession.shared.bytes(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        do {
            for try await line in bytes.lines {
                guard let d = line.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                if o["error"] != nil { return false }
                let status = o["status"] as? String ?? ""
                let total = (o["total"] as? Double) ?? 0, done = (o["completed"] as? Double) ?? 0
                await progress(total > 0 ? done / total : 0, status)
                if status == "success" { return true }
            }
        } catch { return false }
        return true
    }

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
        // The best model this Mac can run quickly: bigger ones on 16 GB+ Macs, small fast ones otherwise.
        let preferred = Self.bigMac
            ? ["qwen2.5:7b", "llama3.1:8b", "qwen3:8b", "gemma3:12b", "gemma3:4b", "qwen2.5:3b", "llama3.2:3b", "llama3.2:latest", "qwen3:4b", "phi3"]
            : ["qwen2.5:3b", "llama3.2:3b", "llama3.2:latest", "gemma3:4b", "qwen3:4b", "qwen2.5:1.5b", "llama3.2:1b", "phi3"]
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
                                      body: ["model": model, "messages": messages, "stream": false, "keep_alive": "30m",   // stays loaded: fast replies
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
            let response = try await session.respond(to: transcript + "\n\nZuffi:")
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
            ForEach(AIProvider.allCases.filter { $0 != .zuffi || ZuffiPlan.shared.isPaid }) { p in
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
    @State private var xaiKey: String = KeychainStore.shared.get("xai-api-key") ?? ""
    @State private var deepseekKey: String = KeychainStore.shared.get("deepseek-api-key") ?? ""
    @State private var mistralKey: String = KeychainStore.shared.get("mistral-api-key") ?? ""
    @State private var perplexityKey: String = KeychainStore.shared.get("perplexity-api-key") ?? ""
    @State private var openrouterKey: String = KeychainStore.shared.get("openrouter-api-key") ?? ""
    @State private var ollamaInstalled: [String] = []
    @State private var saved: String = ""

    @State private var showMore = false
    @ObservedObject private var plan = ZuffiPlan.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Where answers come from
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZuffiIconBadge(symbol: "sparkles", colors: ["#F27BA1", "#B79CFF"])
                        VStack(alignment: .leading, spacing: 3) {
                            Text(plan.isPaid ? "Zuffi’s built-in AI is included" : "Zuffi’s AI")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(plan.isPaid
                                 ? "You don’t need any key. Zuffi answers with the AI that comes with your plan. Add your own key below only if you want to use your own account."
                                 : "Sign in to get Zuffi’s built-in AI with your trial or plan, or add your own key below.")
                                .font(.system(size: 11.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Picker("Answer with", selection: $state.aiProvider) {
                        ForEach(AIProvider.allCases.filter { $0 != .zuffi || ZuffiPlan.shared.isPaid }) { p in Text(p.label).tag(p.rawValue) }
                    }
                    Text("Auto uses the first one that’s ready and quietly tries the next if one fails. Opening apps, music, reminders and volume always work, even offline.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Image(systemName: AIService.appleModelAvailable ? "checkmark.seal.fill" : "minus.circle")
                            .foregroundColor(AIService.appleModelAvailable ? .green : .secondary)
                        Text(AIService.appleModelAvailable
                             ? "Apple’s on-device model is ready — free and private."
                             : "Apple’s on-device model needs Apple silicon and Apple Intelligence.")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
            } label: { Label("Where answers come from", systemImage: "bolt.horizontal.circle") }

            AIUsageCard()
            InstalledAIView(state: state)
            TeamSettings()

            // 2. Your own keys (optional)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Optional. Keys stay in this Mac’s Keychain and are only sent to that AI company.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                    ZuffiKeyRow(name: "ChatGPT", hint: "OpenAI · platform.openai.com", symbol: "bubble.left.and.text.bubble.right.fill", colors: ["#10A37F", "#3CCB9A"],
                                placeholder: "sk-…", key: $openaiKey, saved: has("openai-api-key")) {
                        TextField("Model (default \(AppState.defaultOpenAIModel))", text: $state.openaiModel).textFieldStyle(.roundedBorder)
                    }
                    ZuffiKeyRow(name: "Groq", hint: "Fastest · free key at console.groq.com", symbol: "hare.fill", colors: ["#F55036", "#FF8A65"],
                                placeholder: "gsk_…", key: $groqKey, saved: has("groq-api-key")) { EmptyView() }
                    ZuffiKeyRow(name: "Gemini", hint: "Google · aistudio.google.com", symbol: "diamond.fill", colors: ["#4285F4", "#9B72CB"],
                                placeholder: "AIza…", key: $geminiKey, saved: has("gemini-api-key")) {
                        TextField("Model (default \(AppState.defaultGeminiModel))", text: $state.geminiModel).textFieldStyle(.roundedBorder)
                    }
                    DisclosureGroup(isExpanded: $showMore) {
                        VStack(alignment: .leading, spacing: 12) {
                            ZuffiKeyRow(name: "Grok", hint: "console.x.ai", symbol: "xmark.circle.fill", colors: ["#333333", "#777777"], placeholder: "xai-…", key: $xaiKey, saved: has("xai-api-key")) { EmptyView() }
                            ZuffiKeyRow(name: "DeepSeek", hint: "platform.deepseek.com", symbol: "water.waves", colors: ["#4D6BFE", "#7F95FF"], placeholder: "sk-…", key: $deepseekKey, saved: has("deepseek-api-key")) { EmptyView() }
                            ZuffiKeyRow(name: "Mistral", hint: "console.mistral.ai", symbol: "wind", colors: ["#FA520F", "#FFAF00"], placeholder: "Key", key: $mistralKey, saved: has("mistral-api-key")) { EmptyView() }
                            ZuffiKeyRow(name: "Perplexity", hint: "Answers with sources", symbol: "magnifyingglass.circle.fill", colors: ["#20808D", "#4FB3BF"], placeholder: "pplx-…", key: $perplexityKey, saved: has("perplexity-api-key")) { EmptyView() }
                            ZuffiKeyRow(name: "OpenRouter", hint: "One key, hundreds of models", symbol: "point.3.connected.trianglepath.dotted", colors: ["#6467F2", "#A78BFA"], placeholder: "sk-or-…", key: $openrouterKey, saved: has("openrouter-api-key")) { EmptyView() }
                        }
                        .padding(.top, 8)
                    } label: {
                        Text("More AI: Grok, DeepSeek, Mistral, Perplexity, OpenRouter").font(.system(size: 12, weight: .semibold))
                    }
                    HStack(spacing: 10) {
                        Button {
                            save("xai-api-key", xaiKey); save("deepseek-api-key", deepseekKey); save("mistral-api-key", mistralKey)
                            save("perplexity-api-key", perplexityKey); save("openrouter-api-key", openrouterKey)
                            save("openai-api-key", openaiKey); save("gemini-api-key", geminiKey); save("groq-api-key", groqKey)
                            UserDefaults.standard.removeObject(forKey: "geminiResolved")
                            AIService.shared.clearConversation()
                            saved = "✓ Saved"; refresh += 1
                        } label: { Label("Save keys", systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A"))
                        Text(saved).font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Button(role: .destructive) {
                            if ZuffiReset.confirmRemoveKeys() {
                                openaiKey = ""; geminiKey = ""; groqKey = ""; xaiKey = ""; deepseekKey = ""; mistralKey = ""; perplexityKey = ""; openrouterKey = ""
                                saved = "All keys removed"; refresh += 1
                            }
                        } label: { Label("Remove all keys", systemImage: "trash") }
                    }
                }
            } label: { Label("Your own AI keys", systemImage: "key.fill") }

            // 3. Free AI on this Mac
            DeviceAdvice()
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Zuffi’s offline brain: answers questions with no internet and nothing leaves this Mac. When the internet drops, Zuffi switches to it by herself.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    OllamaGetButton { ollamaInstalled = await AIService.ollamaModels() }
                    if ollamaInstalled.isEmpty {
                        EmptyView()
                    } else {
                        Picker("Model", selection: $state.ollamaModel) {
                            Text("Automatic (best small model)").tag("")
                            ForEach(ollamaInstalled, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            } label: { Label("Ollama — free, runs on this Mac", systemImage: "desktopcomputer") }
        }
        .id(refresh)
        .task { ollamaInstalled = await AIService.ollamaModels() }
    }

    @State private var refresh = 0
    private func has(_ k: String) -> Bool { !(KeychainStore.shared.get(k) ?? "").isEmpty }

    private func save(_ key: String, _ value: String) {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty { KeychainStore.shared.remove(key) } else { KeychainStore.shared.set(key, value: v) }
    }
}

// MARK: - Pretty pieces for Settings

/// A small rounded square with a gradient and an SF Symbol (like iOS Settings icons).
struct ZuffiIconBadge: View {
    let symbol: String
    let colors: [String]
    var size: CGFloat = 30
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.48, weight: .semibold)).foregroundColor(.white))
            .shadow(color: Color(hex: colors.first ?? "#000000").opacity(0.25), radius: 4, y: 2)
    }
}

/// One AI provider: icon, name, hint, a "Saved" pill, the key field and anything extra (a model field).
struct ZuffiKeyRow<Extra: View>: View {
    let name: String
    let hint: String
    let symbol: String
    let colors: [String]
    let placeholder: String
    @Binding var key: String
    let saved: Bool
    @ViewBuilder var extra: () -> Extra
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZuffiIconBadge(symbol: symbol, colors: colors, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name).font(.system(size: 12.5, weight: .semibold))
                    Text(hint).font(.system(size: 10.5)).foregroundColor(.secondary)
                }
                Spacer()
                Text(saved ? "Saved" : "Not added")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(saved ? Color.green.opacity(0.16) : Color.secondary.opacity(0.12)))
                    .foregroundColor(saved ? .green : .secondary)
            }
            SecureField("API key (\(placeholder))", text: $key).textFieldStyle(.roundedBorder)
            extra()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.035)))
    }
}

/// Settings cards: rounded, soft, with a bold title — used by every GroupBox in Settings.
struct ZuffiCardStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            configuration.content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 4)
    }
}

/// Settings → AI → "This month": built-in AI left, and tokens / rough cost per AI company for your own keys.
struct AIUsageCard: View {
    @ObservedObject private var u = AIUsage.shared
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if u.builtInLimit > 0 {
                    HStack { Text("Zuffi’s built-in AI").font(.system(size: 12.5, weight: .semibold)); Spacer(); Text("\(u.builtInUsed) / \(u.builtInLimit)").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                    ProgressView(value: Double(min(u.builtInUsed, u.builtInLimit)), total: Double(max(u.builtInLimit, 1))).tint(Color(hex: "#E2648A"))
                    Text("\(max(0, u.builtInLimit - u.builtInUsed)) questions left this month (resets on the 1st).").font(.system(size: 11)).foregroundColor(.secondary)
                }
                if u.tokens > 0 {
                    if u.builtInLimit > 0 { Divider() }
                    HStack { Text("Your own keys").font(.system(size: 12.5, weight: .semibold)); Spacer(); Text("\(AIUsage.tok(u.tokens)) tokens · ~\(AIUsage.money(u.cost))").font(.system(size: 12, weight: .semibold, design: .rounded)) }
                    ForEach(u.all.sorted { $0.value.cost > $1.value.cost }, id: \.key) { name, r in
                        HStack { Text(name).font(.system(size: 11.5)); Spacer(); Text("\(r.req) answers · \(AIUsage.tok(r.inT + r.outT)) tokens · ~\(AIUsage.money(r.cost))").font(.system(size: 11)).foregroundColor(.secondary) }
                    }
                    Text("Costs are estimates from list prices — your AI company’s bill is the real number.").font(.system(size: 10.5)).foregroundColor(.secondary)
                }
                if u.builtInLimit == 0 && u.tokens == 0 {
                    Text("Nothing used yet this month.").font(.system(size: 11.5)).foregroundColor(.secondary)
                }
            }
        } label: { Label("This month", systemImage: "chart.bar.fill") }
    }
}

/// Settings → AI → Ollama: one click installs the recommended offline model (or opens ollama.com).
struct OllamaGetButton: View {
    var done: () async -> Void
    @State private var running = false
    @State private var have = false
    @State private var pct: Double = -1
    @State private var status = ""
    var body: some View {
        HStack(spacing: 10) {
            if pct >= 0 && pct < 1 {
                ProgressView(value: pct).frame(width: 160).tint(Color(hex: "#E2648A"))
                Text(status.isEmpty ? "Downloading…" : "\(Int(pct * 100))% · \(status)").font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
            } else if have {
                Label("Offline brain ready (\(AIService.recommendedOllama))", systemImage: "checkmark.seal.fill").font(.system(size: 11.5, weight: .semibold)).foregroundColor(.green)
            } else if running {
                Button {
                    Task {
                        pct = 0
                        let ok = await AIService.pullOllama(AIService.recommendedOllama) { p, s in pct = p; status = s }
                        pct = -1; have = ok; status = ok ? "" : "Download failed — try again"
                        await done()
                    }
                } label: { Label("Get the offline brain (\(AIService.recommendedOllama), \(AIService.bigMac ? "about 4.7 GB" : "about 1.9 GB"))", systemImage: "arrow.down.circle.fill") }
                .buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A"))
            } else {
                Button { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) } label: { Label("Install Ollama (free)", systemImage: "arrow.up.forward.app") }
                Text("Install it, open it once, then come back here.").font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .task {
            running = await AIService.ollamaRunning()
            have = (await AIService.ollamaModels()).contains { $0.hasPrefix(AIService.recommendedOllama) }
        }
    }
}


/// The user's reminders, tasks and meetings (from Zuffi's shared app), kept fresh for every answer — "what do I have tomorrow?".
@MainActor
final class ZuffiMemory {
    static let shared = ZuffiMemory()
    private(set) var itemsLine = ""
    private var timer: Timer?
    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in Task { @MainActor in ZuffiMemory.shared.refresh() } }
    }
    func refresh() {
        Task {
            guard let s = await WebHub.shared.callJS("return window.Sparrow.listItems ? JSON.stringify(window.Sparrow.listItems()) : '[]'") as? String, s.count > 2 else { itemsLine = ""; return }
            itemsLine = "\nTHEIR REMINDERS, TASKS AND MEETINGS (JSON): " + String(s.prefix(3000)) + "\n"
        }
    }
}


// MARK: - Which free AI suits this Mac (chip, memory, disk)

enum DeviceCheck {
    static func sysctl(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "" }
        return String(cString: buf)
    }
    static var chip: String { let c = sysctl("machdep.cpu.brand_string"); return c.isEmpty ? (appleSilicon ? "Apple silicon" : "Intel") : c }
    static var appleSilicon: Bool { var v: Int32 = 0; var s = MemoryLayout<Int32>.size; return sysctlbyname("hw.optional.arm64", &v, &s, nil, 0) == 0 && v == 1 }
    static var ramGB: Int { Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded()) }
    static var freeDiskGB: Int {
        let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int((v?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_000_000_000)
    }
    static var cores: Int { ProcessInfo.processInfo.activeProcessorCount }

    /// (best free choice, why, model to download or nil)
    static var advice: (title: String, why: String, model: String?) {
        let ram = ramGB, disk = freeDiskGB
        if !appleSilicon {
            return ("Groq (free, online)", "This Mac has an Intel chip — AI models run slowly on it. A free Groq key answers in about a second, online. Use “qwen2.5:1.5b” in Ollama only for when there's no internet.", "qwen2.5:1.5b")
        }
        if disk < 6 { return ("Groq (free, online)", "Only \(disk) GB of free space — a local model needs 2–5 GB. Free up space, or use a free Groq key.", nil) }
        if ram >= 32 { return ("Ollama · qwen2.5:14b", "\(ram) GB memory on \(chip): a 14B model runs well and gives the best offline answers (≈9 GB download).", "qwen2.5:14b") }
        if ram >= 16 { return ("Ollama · qwen2.5:7b", "\(ram) GB memory on \(chip): a 7B model is fast and smart (≈4.7 GB download).", "qwen2.5:7b") }
        if ram >= 8 { return ("Ollama · qwen2.5:3b (+ Groq)", "\(ram) GB memory: a 3B model works offline (≈1.9 GB). For long or tricky questions add a free Groq key — it's faster than anything this Mac can run.", "qwen2.5:3b") }
        return ("Groq (free, online)", "\(ram) GB memory is tight for local AI. A free Groq key is the fast choice; “qwen2.5:1.5b” works offline in a pinch.", "qwen2.5:1.5b")
    }

    static var summary: String {
        let a = advice
        return "This Mac: \(chip), \(ramGB) GB memory, \(cores) cores, \(freeDiskGB) GB free. Best free AI: \(a.title). \(a.why)"
    }
}

struct DeviceAdvice: View {
    @State private var pulling = false
    @State private var progress = 0.0
    @State private var status = ""
    var body: some View {
        let a = DeviceCheck.advice
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    spec("cpu", DeviceCheck.chip)
                    spec("memorychip", "\(DeviceCheck.ramGB) GB")
                    spec("internaldrive", "\(DeviceCheck.freeDiskGB) GB free")
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Best for this Mac: \(a.title)").font(.system(size: 12.5, weight: .semibold))
                        Text(a.why).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let m = a.model {
                    HStack {
                        Button(pulling ? "Downloading… \(Int(progress * 100))%" : "Get \(m) in Ollama") {
                            pulling = true
                            Task { @MainActor in
                                _ = await AIService.pullOllama(m) { p, s in progress = p; status = s }
                                pulling = false
                            }
                        }.disabled(pulling)
                        if !status.isEmpty { Text(status).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1) }
                    }.controlSize(.small)
                }
            }.padding(6)
        } label: { Label("Which free AI is best for this Mac?", systemImage: "gauge.with.dots.needle.67percent") }
    }
    private func spec(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).font(.system(size: 11)).lineLimit(1)
    }
}
