import Foundation
import AppKit

// =====================================================================
// MARK: - Smart planner: talk to Sparrow like a person
// When the instant built-in rules don't recognise a request, a fast AI (Groq — free, ~0.3 s;
// or Gemini / ChatGPT) turns whatever you said — any wording, English, Urdu, Hindi, Roman Urdu,
// several things at once — into Sparrow's own commands. Sparrow runs them and answers naturally.
// =====================================================================

@MainActor
final class SmartPlanner {
    static let shared = SmartPlanner()

    struct Plan { let commands: [String]; let say: String }

    private func key(_ k: String) -> String? {
        guard let v = KeychainStore.shared.get(k), !v.isEmpty else { return nil }
        return v
    }
    var isAvailable: Bool { NetStatus.shared.online && (key("groq-api-key") ?? key("gemini-api-key") ?? key("openai-api-key")) != nil }

    private static let commands = """
    open <app or website> · quit <app> · play music · play music on spotify · play <song or artist> · play <song> on spotify · play <query> on youtube
    pause · next song · previous song · volume <0-100> · volume up · volume down · mute
    remind me to <task> at <time> <day> · meeting with <who> <day> at <time> · add task <task> · note <text> · what's on today · my tasks
    save <phone number> as <name> · what's <name>'s number
    search <query> · youtube <query> · weather · prayer times · battery · what time is it · new chat
    remind me to drink water every <n> hours · medicine reminders at <times>
    shut down mac · restart mac · sleep mac · lock screen · turn on wifi · turn off wifi · turn on bluetooth · turn off bluetooth
    brightness up · brightness down · dark mode · light mode · hide everything · screenshot · full screen · close this window · new tab
    put <app> on the left and <app> on the right · run shortcut <name> · type <text>
    start meeting notes · stop meeting notes
    check my emails · read the email from <name> · reply to <name> saying <what to tell them> · send · cancel
    analyse my cv · find <role> jobs in <place> · find jobs for me · tailor my cv for job <n> · apply to job <n> · my job applications · type my email|phone|name|linkedin|cover letter
    check whatsapp · whatsapp <name> saying <text> · reply to <name> on whatsapp saying <text>
    """

    private func systemPrompt() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM yyyy, h:mm a"
        let name = AssistantPrefs.displayName
        let app = AppState.shared.lastExternalApp?.localizedName ?? "unknown"
        return """
        You are Sparrow, a warm, quick assistant living on the user's Mac. Now: \(f.string(from: Date())). User: \(name.isEmpty ? "unknown" : name). Front app: \(app).
        Turn what the user said (any language: English, Urdu, Hindi, Punjabi, Roman Urdu, mixed) into Sparrow commands, in order.
        Write every command in ENGLISH using exactly these forms:
        \(Self.commands)
        Rules:
        - Use as few commands as needed. Times like "kal 10 baje" become "at 10am tomorrow".
        - If it's a question or chat (not an action), return no commands and answer in "say" (max 2 short sentences).
        - If you're not sure what they want, return no commands and ask a short question in "say".
        - Never invent actions they didn't ask for. Risky actions (shut down, restart) only if clearly asked.
        - "say": one short, friendly, human sentence confirming what you're doing, in the SAME language and script the user used.
        Reply ONLY with JSON: {"commands": ["..."], "say": "..."}
        """
    }

    func plan(_ text: String) async -> Plan? {
        guard isAvailable else { return nil }
        let t0 = Date()
        var raw: String?
        if let k = key("groq-api-key") { raw = try? await openAIStyle(url: "https://api.groq.com/openai/v1/chat/completions",
                                                                       model: UserDefaults.standard.string(forKey: "groqResolved") ?? "llama-3.3-70b-versatile", key: k, text: text) }
        if raw == nil, let k = key("gemini-api-key") { raw = try? await gemini(key: k, text: text) }
        if raw == nil, let k = key("openai-api-key") { raw = try? await openAIStyle(url: "https://api.openai.com/v1/chat/completions",
                                                                                    model: UserDefaults.standard.string(forKey: "openaiResolved") ?? "gpt-4o-mini", key: k, text: text) }
        guard let raw, let plan = Self.parse(raw) else { return nil }
        appendAppLog("agents.log", String(format: "planner %.2fs: \"%@\" → %@ | %@", Date().timeIntervalSince(t0), text, plan.commands.joined(separator: " ; "), plan.say))
        return plan
    }

    static func parse(_ raw: String) -> Plan? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}") { s = String(s[a...b]) }
        guard let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let cmds = (o["commands"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return Plan(commands: Array(cmds.prefix(6)), say: (o["say"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func post(_ url: URL, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        var req = URLRequest(url: url, timeoutInterval: body["contents"] != nil && (body["generationConfig"] == nil) ? 30 : 8)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func openAIStyle(url: String, model: String, key: String, text: String) async throws -> String? {
        let j = try await post(URL(string: url)!, body: [
            "model": model, "temperature": 0, "max_tokens": 300,
            "response_format": ["type": "json_object"],
            "messages": [["role": "system", "content": systemPrompt()], ["role": "user", "content": text]],
        ], headers: ["Authorization": "Bearer \(key)"])
        return ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
    }

    private func gemini(key: String, text: String) async throws -> String? {
        let model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
        let j = try await post(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!, body: [
            "system_instruction": ["parts": [["text": systemPrompt()]]],
            "contents": [["role": "user", "parts": [["text": text]]]],
            "generationConfig": ["temperature": 0, "responseMimeType": "application/json"],
        ], headers: ["x-goog-api-key": key])
        let parts = (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
        return parts.compactMap { $0["text"] as? String }.joined()
    }

    /// A plain text answer from the fast AI (used for meeting summaries).
    func complete(_ prompt: String) async -> String? {
        let msgs: [[String: Any]] = [["role": "user", "content": prompt]]
        if let k = key("groq-api-key"), let j = try? await post(URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            body: ["model": UserDefaults.standard.string(forKey: "groqResolved") ?? "llama-3.3-70b-versatile", "temperature": 0.2, "messages": msgs],
            headers: ["Authorization": "Bearer \(k)"]),
           let c = ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String { return c }
        if let k = key("gemini-api-key") {
            let model = UserDefaults.standard.string(forKey: "geminiResolved") ?? AppState.defaultGeminiModel
            if let j = try? await post(URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
                                       body: ["contents": [["role": "user", "parts": [["text": prompt]]]]], headers: ["x-goog-api-key": k]) {
                let parts = (((j["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                let t = parts.compactMap { $0["text"] as? String }.joined()
                if !t.isEmpty { return t }
            }
        }
        if let k = key("openai-api-key"), let j = try? await post(URL(string: "https://api.openai.com/v1/chat/completions")!,
            body: ["model": UserDefaults.standard.string(forKey: "openaiResolved") ?? "gpt-4o-mini", "messages": msgs],
            headers: ["Authorization": "Bearer \(k)"]),
           let c = ((j["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String { return c }
        return nil
    }

    /// Runs a plan: every command through Sparrow's own agents, then one natural answer.
    func run(_ plan: Plan) async -> String {
        var results: [String] = []
        for (i, c) in plan.commands.enumerated() {
            var r = await AgentRouter.shared.handle(c)
            if r == nil { r = await WebHub.shared.ask(c) }
            if let r { results.append(r) }
            if i < plan.commands.count - 1, c.lowercased().hasPrefix("open") { try? await Task.sleep(nanoseconds: 900_000_000) }
        }
        // Information answers (time, weather, numbers…) are worth saying; plain confirmations are covered by "say".
        let info = results.filter { r in
            !["Opening", "Closing", "Playing", "Paused", "Next", "Previous", "Volume", "Muted", "Searching", "Done"].contains { r.hasPrefix($0) }
        }
        if plan.commands.isEmpty { return plan.say }
        if !info.isEmpty && info.joined().count < 260 { return ([plan.say] + info).filter { !$0.isEmpty }.joined(separator: " ") }
        return plan.say.isEmpty ? (results.joined(separator: " ")) : plan.say
    }
}
