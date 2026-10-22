import Foundation
import SwiftUI

// =====================================================================
// MARK: - Zuffi's team (agency-agents, MIT licence — see THIRD_PARTY_NOTICES.md)
//
// 289 specialists (sales, marketing, finance, product, support, research…).
// • Chat: pick one in the chat line or say "switch to the finance agent" — Zuffi then answers AS that person
//   ("Who are you?" → "I'm your Product Manager…") until you say "back to normal".
// • Business plan: hire your own AI team, pick several at once, and give them jobs. The Team Manager splits
//   each job between the right people and brings back one clear answer ("who are you guys?" → each one says hello).
// Agents think and write. They never send, post, pay or change anything by themselves — they ask you first.
// =====================================================================

struct TeamAgent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let division: String
    let name: String
    let description: String
    let emoji: String
    let prompt: String
}

/// A job given to the AI team (Business → AI Team, or "assign … to research and product manager").
struct TeamTask: Codable, Identifiable, Hashable {
    struct Part: Codable, Hashable { var agent: String; var task: String; var text: String }
    var id = UUID().uuidString
    var title: String
    var agents: [String]
    var status = "Waiting"          // Waiting · Working · Done · Needs you
    var summary = ""
    var parts: [Part] = []
    var created = Date()
}

@MainActor
final class ZuffiTeam: ObservableObject {
    static let shared = ZuffiTeam()

    /// Leads the team: plans the job, hands out the parts, sums up. Always there on the Business plan.
    static let manager = TeamAgent(id: "zuffi-team-manager", division: "management", name: "Team Manager",
                                   description: "Leads your AI team: splits each job, gives every part to the right person and brings back one clear answer with next steps.",
                                   emoji: "🧭", prompt: "")

    @Published private(set) var agents: [TeamAgent] = []
    /// The people talking in the chat right now (one = that agent answers; several = the team with its manager).
    @Published var activeIDs: [String] = {
        let d = UserDefaults.standard
        if let a = d.stringArray(forKey: "teamActive") { return a }
        if let one = d.string(forKey: "teamAgent"), !one.isEmpty { return [one] }
        return []
    }() { didSet { UserDefaults.standard.set(activeIDs, forKey: "teamActive") } }
    /// The business's own team (Business → AI Team → Hire).
    @Published var hired: [String] = UserDefaults.standard.stringArray(forKey: "teamHired") ?? [] {
        didSet { UserDefaults.standard.set(hired, forKey: "teamHired") }
    }
    @Published var tasks: [TeamTask] = {
        guard let d = UserDefaults.standard.data(forKey: "teamTasks"), let t = try? JSONDecoder().decode([TeamTask].self, from: d) else { return [] }
        return t
    }() { didSet { if let d = try? JSONEncoder().encode(Array(tasks.prefix(60))) { UserDefaults.standard.set(d, forKey: "teamTasks") } } }
    @Published var working = ""          // "Research Synthesist is looking things up…"

    /// Kept for older callers: the one agent in use, or "" (none, or a whole team).
    var activeID: String {
        get { activeIDs.count == 1 ? activeIDs[0] : "" }
        set { activeIDs = newValue.isEmpty ? [] : [newValue] }
    }
    var active: TeamAgent? { activeIDs.count == 1 ? agent(activeIDs[0]) : nil }
    var activeAgents: [TeamAgent] { activeIDs.compactMap(agent) }
    var isTeam: Bool { activeAgents.count > 1 }
    var hiredAgents: [TeamAgent] { hired.compactMap(agent) }
    /// Teams (several at once, hiring, jobs) come with the Business plan.
    var teamsAllowed: Bool { ZuffiPlan.shared.isBusiness }

    func agent(_ id: String) -> TeamAgent? { id == Self.manager.id ? Self.manager : agents.first { $0.id == id } }

    /// Divisions in a friendly order: business ones first.
    var divisions: [String] {
        let order = ["sales", "marketing", "paid-media", "support", "finance", "product", "project-management", "research",
                     "specialized", "design", "engineering", "testing", "security", "healthcare", "academic", "strategy"]
        let all = Set(agents.map(\.division))
        return order.filter(all.contains) + all.subtracting(order).sorted()
    }

    func members(of division: String) -> [TeamAgent] { agents.filter { $0.division == division }.sorted { $0.name < $1.name } }

    static func divisionLabel(_ d: String) -> String {
        d.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// A good first team for each kind of business (ids from the agents file).
    var starterTeam: [String] {
        var ids = ["product-manager", "research-synthesist", "finance-financial-analyst", "sales-coach", "marketing-social-media-strategist", "support-support-responder"]
        if ZuffiCRM.shared.isEstate { ids += ["sales-deal-strategist"] }
        return ids.filter { id in agents.contains { $0.id == id } }
    }

    private init() {
        Task { @MainActor in
            let list = await Task.detached(priority: .utility) { () -> [TeamAgent] in
                guard let url = Bundle.main.url(forResource: "agency-agents", withExtension: "json", subdirectory: "agents")
                        ?? Bundle.main.url(forResource: "agency-agents", withExtension: "json"),
                      let data = try? Data(contentsOf: url) else { return [] }
                return (try? JSONDecoder().decode([TeamAgent].self, from: data)) ?? []
            }.value
            self.agents = list
            self.activeIDs = self.activeIDs.filter { self.agent($0) != nil }
        }
    }

    // MARK: Who they are

    /// Research people may look things up on the web.
    static func isResearcher(_ a: TeamAgent) -> Bool {
        let n = (a.name + " " + a.division).lowercased()
        return n.contains("research") || n.contains("analyst") || n.contains("intelligence") || n.contains("trend")
    }

    /// The role guide without code samples, tables and decoration — the parts that say how this person thinks.
    private static func guide(_ a: TeamAgent, limit: Int = 2600) -> String {
        var t = a.prompt.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^\\|.*\\|\\s*$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*", with: "").replacingOccurrences(of: "(?m)^#+\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return String(t.prefix(limit))
    }

    /// Everything a team member must know about the business and the owner (short, so answers come fast).
    static var businessContext: String {
        let crm = ZuffiCRM.shared, biz = ZuffiBusiness.shared
        let country = ["PK": "Pakistan", "GB": "the UK"][crm.country] ?? ""
        var lines: [String] = []
        let name = biz.businessName.isEmpty ? "" : "“\(biz.businessName)”"
        if ZuffiPlan.shared.isBusiness {
            lines.append("Business: \(name.isEmpty ? "(name not given yet)" : name) — \(crm.businessWord)\(country.isEmpty ? "" : " in \(country)"). Money is in \(crm.currency).")
            let info = crm.businessInfo.trimmingCharacters(in: .whitespacesAndNewlines)
            lines.append(info.isEmpty ? "Business details: NOT FILLED IN YET — ask the owner for anything you need about the business."
                                      : "Business details from the owner (the truth — use these exact facts):\n" + String(info.prefix(3500)))
            if !crm.todaysUpdate.isEmpty { lines.append("Today's offer / news: \(crm.todaysUpdate)") }
            let leads = crm.leads
            if !leads.isEmpty {
                let won = leads.filter { $0.stage == "Won" }.count, due = leads.filter(\.dueToday).count
                lines.append("Right now: \(leads.count) clients/leads in Zuffi (\(won) won, \(due) to follow up today).")
            }
        }
        let who = UserDefaults.standard.string(forKey: "zuffiFacts") ?? ""
        lines.append((who.isEmpty ? ZuffiPlan.shared.profileLine : who).trimmingCharacters(in: .whitespacesAndNewlines))
        let mem = ZuffiMemory.shared.itemsLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mem.isEmpty { lines.append(String(mem.prefix(1200))) }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Identity first: this person, the rules, the business. (A long Zuffi prompt with the persona at the end made agents forget who they were.)
    func systemPrompt(for a: TeamAgent, part: String = "", others: [TeamAgent] = []) -> String {
        let owner = AssistantPrefs.displayName.isEmpty ? "the owner" : AssistantPrefs.displayName
        let team = others.isEmpty ? "" : "\nYou're working together with: " + others.map { "\($0.name)" }.joined(separator: ", ") + ". Do only your own part; don't repeat theirs."
        return """
        You are \(a.name) \(a.emoji), a senior \(a.name) with 15+ years of experience, working on \(owner)'s team inside Zuffi.\(team)
        WHO YOU ARE
        - Speak as yourself, in the first person. If asked who you are, say “I'm your \(a.name)” and, in one line, how you help this business. Never call yourself Zuffi or “an AI model”. If asked directly whether you're an AI, say you're \(a.name) from Zuffi's AI team.
        - Your expertise: \(a.description)
        HOW YOU WORK
        - Think like the best \(a.name) in the field, for THIS business: practical steps, real numbers (in their currency), examples, what to do first.
        - Use the business details below. Never invent facts about the business (prices, staff, sales, clients). If you need a fact that isn't here, ask the owner one or two short questions FIRST, then answer.
        - You think, plan and write. You can't send messages, post, pay, book or change anything yourself — suggest the action and ask the owner to OK it.
        - Reply in the owner's language (English, Urdu, Roman Urdu…). Plain text with line breaks — no markdown like ** or ##. Short paragraphs or numbered steps; no filler.
        \(part.isEmpty ? "" : "\nYOUR PART OF THIS JOB: \(part)\nKeep it under 180 words.\n")
        ABOUT THE BUSINESS AND THE OWNER
        \(Self.businessContext)

        YOUR ROLE GUIDE (how a top \(a.name) works — follow its thinking, ignore anything about tools or code you don't have):
        \(Self.guide(a, limit: part.isEmpty ? 2600 : 1400))
        """
    }

    /// "Hi, I'm your …" — instant, no AI.
    func intro(_ a: TeamAgent) -> String {
        let first = a.description.split(whereSeparator: { ".!".contains($0) }).first.map(String.init) ?? a.description
        return "\(a.emoji) \(a.name): Hi, I'm your \(a.name). \(first.trimmingCharacters(in: .whitespaces))."
    }

    // MARK: Picking people

    func use(_ a: TeamAgent?) {
        activeIDs = a.map { [$0.id] } ?? []
        AIService.shared.clearConversation()
    }

    /// Adds or removes someone from the chat (several at once = Business plan).
    func toggle(_ a: TeamAgent) {
        if activeIDs.contains(a.id) { activeIDs.removeAll { $0 == a.id } }
        else if teamsAllowed { activeIDs.append(a.id) } else { activeIDs = [a.id] }
        AIService.shared.clearConversation()
    }

    func hire(_ a: TeamAgent) { if !hired.contains(a.id) { hired.append(a.id) } }
    func fire(_ a: TeamAgent) { hired.removeAll { $0 == a.id }; activeIDs.removeAll { $0 == a.id } }

    /// Common words → the person most people mean.
    private static let aliases: [(String, String)] = [
        ("team manager", "zuffi-team-manager"), ("manager", "zuffi-team-manager"),
        ("finance", "finance-financial-analyst"), ("financial", "finance-financial-analyst"), ("accountant", "finance-bookkeeper-controller"),
        ("accounts", "finance-bookkeeper-controller"), ("bookkeeper", "finance-bookkeeper-controller"), ("cfo", "finance-financial-analyst"),
        ("money", "finance-financial-analyst"), ("tax", "finance-tax-strategist"),
        ("research", "research-synthesist"), ("researcher", "research-synthesist"),
        ("product manager", "product-manager"), ("product", "product-manager"), ("pm", "product-manager"),
        ("project manager", "project-manager-senior"), ("project", "project-manager-senior"),
        ("sales", "sales-coach"), ("seller", "sales-coach"), ("marketing", "marketing-social-media-strategist"),
        ("social media", "marketing-social-media-strategist"), ("seo", "marketing-seo-specialist"), ("content", "marketing-content-creator"),
        ("support", "support-support-responder"), ("customer service", "support-support-responder"), ("legal", "support-legal-compliance-checker"),
        ("lawyer", "support-legal-compliance-checker"), ("growth", "marketing-growth-hacker"), ("ads", "paid-media-paid-social-strategist"),
    ]

    /// Finds an agent by words the user said ("sales coach", "seo", "finance").
    func find(_ words: String) -> TeamAgent? {
        let w = words.lowercased().replacingOccurrences(of: #"\b(the|a|an|my|our|agent|agents|specialist|expert|team|member|person|guy)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return nil }
        if let exact = agents.first(where: { $0.name.lowercased() == w }) { return exact }
        if let hit = Self.aliases.first(where: { $0.0 == w }), let a = agent(hit.1) ?? agents.first(where: { $0.id.hasSuffix(hit.1) }) { return a }
        // The business's own team first ("finance" → the finance person you hired).
        let tokens = w.split(separator: " ").map(String.init).filter { $0.count > 1 }
        let pool = hiredAgents.isEmpty ? agents : hiredAgents + agents
        let scored = pool.enumerated().map { (i, a) -> (TeamAgent, Int) in
            let n = a.name.lowercased(), d = a.description.lowercased(), div = a.division.lowercased()
            let s = tokens.reduce(0) { $0 + (n.contains($1) ? 4 : 0) + (div.contains($1) ? 2 : 0) + (d.contains($1) ? 1 : 0) }
            return (a, s * 10 + (i < hiredAgents.count && s > 0 ? 5 : 0))
        }.filter { $0.1 > 0 }
        if let best = scored.max(by: { $0.1 < $1.1 }) { return best.0 }
        if let hit = Self.aliases.first(where: { w.contains($0.0) }) { return agent(hit.1) }
        return nil
    }

    /// "research and product manager" → both.
    func findMany(_ words: String) -> [TeamAgent] {
        let parts = words.lowercased().components(separatedBy: CharacterSet(charactersIn: ",&+")).flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var out: [TeamAgent] = []
        for p in parts { if let a = find(p), !out.contains(a) { out.append(a) } }
        return out
    }

    nonisolated static func looksLikeCommand(_ q: String) -> Bool {
        q.lowercased().range(of: #"^(open|close|quit|play|pause|stop|next|previous|skip|volume|mute|remind|set (a )?(timer|reminder|alarm)|turn (on|off)|lock|sleep|shut ?down|restart|launch|search (google|youtube)|call|text|send|switch to (male|female|bunny)|change your|make a (folder|note))\b"#, options: .regularExpression) != nil
    }

    // MARK: What people say

    /// Team words in the chat or by voice. nil = not about the team.
    func handle(_ raw: String) async -> String? {
        let t = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        if t.range(of: #"^(stop|leave|exit|end|close|drop) (the |this |my )?(agents?|specialists?|team( members?)?)$|^back to (normal|zuffi)$|^be (normal|zuffi) again$|^(just )?zuffi please$"#, options: .regularExpression) != nil {
            guard !activeIDs.isEmpty else { return "You're already talking to plain Zuffi." }
            use(nil); return "Okay, I'm just Zuffi again."
        }
        // "who are you?" / "who are you guys?" while agents are picked → they introduce themselves.
        if !activeIDs.isEmpty, t.range(of: #"^(who|what) (are|r) (you|u)( guys| all| people| two| both| everyone)?( and what (do )?(you|u) do( for me)?)?$|^introduce (yourself|yourselves|the team)$|^who('s| is) (here|there|this)$|^(tell me )?about (yourself|yourselves)$|^aap kaun (ho|hain)$"#, options: .regularExpression) != nil {
            let people = activeAgents
            if people.count == 1 { return intro(people[0]) + " What can I do for you?" }
            return ([intro(Self.manager) + " I lead this team — give us a job and I'll split it up."] + people.map(intro)).joined(separator: "\n\n")
        }
        if t.range(of: #"^(who('s| is) (on )?(my|your) team|list (the |my |your )?(team|agents)|show (me )?(the |my |your )?(team|agents))$"#, options: .regularExpression) != nil {
            if !hiredAgents.isEmpty {
                return "Your AI team (\(hiredAgents.count + 1)):\n" + ([Self.manager] + hiredAgents).map { "\($0.emoji) \($0.name)" }.joined(separator: "\n")
                    + "\n\nSay “use research and product manager agents”, or open Business → AI Team."
            }
            let lines = divisions.prefix(10).map { "\(Self.divisionLabel($0)): \(members(of: $0).count)" }
            return "I have \(agents.count) specialists:\n" + lines.joined(separator: "\n") + "\n\nSay “switch to the finance agent”, or pick one with the people button in the chat line."
        }
        if t.range(of: #"^(which|what) agents?( is| are)?( on| active| working)?$"#, options: .regularExpression) != nil {
            let p = activeAgents
            return p.isEmpty ? "No agent — I'm plain Zuffi." : "Right now: " + p.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ") + "."
        }
        // "hire the SEO specialist" / "add tax strategist to my team"
        if let m = Self.match(t, #"^(?:hire|add) (?:the |a |an )?(.+?)(?: agents?| specialists?)?(?: to (?:my |the )?team)?$"#), t.hasPrefix("hire") || t.contains("to my team") || t.contains("to the team") {
            guard teamsAllowed else { return "Hiring your own AI team is part of Zuffi Business." }
            let found = findMany(m[0]); guard !found.isEmpty else { return "I couldn't find that person. Open Business → AI Team to browse everyone." }
            found.forEach(hire)
            return found.map(intro).joined(separator: "\n\n") + "\n\nWelcome to the team. You have \(hired.count) people now."
        }
        // "assign <job> to research and product manager"
        if let m = Self.match(t, #"^(?:assign|give) (.+?) to (?:the |my )?(.+?)(?: agents?| team)?$"#), teamsAllowed {
            let who = findMany(m[1])
            if !who.isEmpty {
                let task = await assign(m[0], to: who)
                return render(task)
            }
        }
        // "switch to the finance agent", "use research and product manager agents", "…agent and tell me how to …"
        let pattern = #"^(?:use|switch to|talk to|call|bring in|act as|select|pick|ask) (?:the |my |a |an |our )?(.+?) (?:agents?|specialists?|experts?|team members?)(?:\s*(?:,|and then|and|then|to)\s+(.+))?$|^(?:use|switch to|act as) agents? (.+)$"#
        guard let m = Self.match(t, pattern) else { return nil }
        let names = m[0].isEmpty ? m[2] : m[0], rest = m[1]
        var who = findMany(names)
        guard !who.isEmpty else { return "I couldn't find that agent. Say “show my team” to see who's here." }
        if who.count > 1, !teamsAllowed { who = [who[0]] }
        activeIDs = who.map(\.id).filter { $0 != Self.manager.id }
        if activeIDs.isEmpty, who.first?.id == Self.manager.id { activeIDs = hired.isEmpty ? starterTeam : hired }
        AIService.shared.clearConversation()
        let hello = activeAgents.count == 1 ? intro(activeAgents[0]) : "🧭 Team Manager here with " + activeAgents.map(\.name).joined(separator: ", ") + "."
        guard !rest.trimmingCharacters(in: .whitespaces).isEmpty else { return hello + " What do you need?" }
        // "…and tell me how to manage my business finances" → answer straight away, as that person.
        let answer = await ask(rest)
        return hello + "\n\n" + answer
    }

    /// For the voice brain: an answer from whoever is picked (or the named person).
    func ask(_ question: String, who: [TeamAgent]? = nil) async -> String {
        let people = who ?? activeAgents
        if people.count > 1 { return await runTeam(question, people: people) }
        guard let a = people.first else { return "Pick someone from the team first — say “switch to the finance agent”." }
        working = "\(a.name) is thinking…"; defer { working = "" }
        let r = await AIService.shared.textAnswer(system: systemPrompt(for: a), messages: recent + [["role": "user", "content": question]], max: 1000, web: Self.isResearcher(a))
        guard let r else { return "\(a.emoji) \(a.name): I can't reach an AI right now. Check the internet, or connect one in Settings → AI." }
        note(question, r)
        return r
    }

    // MARK: The Team Manager

    private var recent: [[String: String]] = []
    private func note(_ q: String, _ a: String) {
        recent += [["role": "user", "content": q], ["role": "assistant", "content": String(a.prefix(1500))]]
        if recent.count > 8 { recent.removeFirst(recent.count - 8) }
    }

    /// Several people on one question: plan → each does their part → one summary.
    func runTeam(_ question: String, people: [TeamAgent]? = nil) async -> String {
        let task = await assign(question, to: people ?? activeAgents, save: false)
        let text = render(task)
        note(question, text)
        return text
    }

    /// Gives a job to the team and keeps it on the board.
    @discardableResult
    func assign(_ job: String, to people: [TeamAgent], save: Bool = true) async -> TeamTask {
        let team = people.filter { $0.id != Self.manager.id }
        var task = TeamTask(title: job, agents: team.map(\.id), status: "Working")
        if save { tasks.insert(task, at: 0) }
        func update() { if save, let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = task } }
        guard !team.isEmpty else { task.status = "Needs you"; task.summary = "Pick at least one team member for this job."; update(); return task }

        // 1) The manager splits the job (fast JSON model).
        working = "🧭 Team Manager is planning…"
        let roster = team.map { "\($0.id) — \($0.name): \($0.description.prefix(140))" }.joined(separator: "\n")
        let plan = await AIService.shared.fastJSON("""
        The owner's request: \(job)

        Team members:
        \(roster)

        About the business:
        \(Self.businessContext.prefix(1800))
        """, system: """
        You are the Team Manager of an AI team for a small business. Split the owner's request into one clear task per team member who can really help \
        (skip members who aren't needed). If a key fact about the business is missing and nobody can do good work without it, \
        put ONE short question for the owner in "ask" and leave tasks empty. \
        JSON: {"tasks":[{"id":"member id","task":"what this member should do, 1-2 sentences"}],"ask":""}
        """)
        if let ask = (plan?["ask"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !ask.isEmpty,
           ((plan?["tasks"] as? [Any]) ?? []).isEmpty {
            task.status = "Needs you"; task.summary = ask; working = ""; update(); return task
        }
        var jobs: [(TeamAgent, String)] = ((plan?["tasks"] as? [[String: Any]]) ?? []).compactMap { d in
            guard let id = d["id"] as? String, let a = team.first(where: { $0.id == id || $0.name.lowercased() == id.lowercased() }) else { return nil }
            return (a, (d["task"] as? String) ?? job)
        }
        if jobs.isEmpty { jobs = team.prefix(5).map { ($0, job) } }

        // 2) Each one does their part (at the same time when a cloud AI is there).
        let parallel = AIService.builtinAvailable || ["groq-api-key", "gemini-api-key", "openai-api-key"].contains { !(KeychainStore.shared.get($0) ?? "").isEmpty }
        let others = jobs.map { $0.0 }
        let history = recent
        var results: [String: String] = [:]
        working = "👥 " + jobs.map { $0.0.name }.joined(separator: ", ") + " working…"
        if parallel {
            // Start everyone at once (each a main-actor task), then collect the answers.
            var running: [(String, Task<String?, Never>)] = []
            for (a, part) in jobs {
                let sys = systemPrompt(for: a, part: part, others: others.filter { $0 != a })
                let web = Self.isResearcher(a), msgs = history + [["role": "user", "content": job + "\n\nYour part: " + part]]
                running.append((a.id, Task { @MainActor in await AIService.shared.textAnswer(system: sys, messages: msgs, max: 700, web: web) }))
            }
            for (id, t) in running { results[id] = await t.value }
        } else {
            for (a, part) in jobs {
                working = "\(a.emoji) \(a.name) is working…"
                results[a.id] = await AIService.shared.textAnswer(system: systemPrompt(for: a, part: part, others: others.filter { $0 != a }),
                                                                  messages: history + [["role": "user", "content": job + "\n\nYour part: " + part]], max: 700, web: Self.isResearcher(a))
            }
        }
        task.parts = jobs.map { TeamTask.Part(agent: $0.0.id, task: $0.1, text: results[$0.0.id] ?? "I couldn't reach an AI for this part.") }

        // 3) The manager sums up (skipped for one person — their answer is the answer).
        if jobs.count > 1 {
            working = "🧭 Team Manager is summing up…"
            let all = task.parts.map { p in "\(agent(p.agent)?.name ?? p.agent): \(p.text.prefix(1200))" }.joined(separator: "\n\n")
            task.summary = await AIService.shared.textAnswer(system: """
            You are the Team Manager. In the owner's language, plain text, no markdown: one or two sentences with the answer, \
            then "Next steps:" with up to 5 numbered actions (say who does each). Mention anything that needs the owner's OK. Under 120 words.
            """, messages: [["role": "user", "content": "Request: \(job)\n\nWhat the team said:\n\(all)"]], max: 350) ?? ""
        }
        task.status = task.parts.contains { $0.text.hasPrefix("I couldn't reach") } ? "Needs you" : "Done"
        working = ""
        update()
        return task
    }

    func render(_ t: TeamTask) -> String {
        var out: [String] = []
        if !t.summary.isEmpty { out.append("🧭 Team Manager: " + t.summary) }
        for p in t.parts { let a = agent(p.agent); out.append("\(a?.emoji ?? "👤") \(a?.name ?? p.agent):\n\(p.text)") }
        return out.joined(separator: "\n\n")
    }

    func rerun(_ t: TeamTask) async {
        tasks.removeAll { $0.id == t.id }
        await assign(t.title, to: t.agents.compactMap(agent))
    }

    private static func match(_ t: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: t).map { String(t[$0]) } ?? "" }
    }
}

// MARK: - Team picker (chat line)

struct TeamMenu: View {
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var plan = ZuffiPlan.shared
    var compact = true

    var body: some View {
        Menu {
            if !team.activeIDs.isEmpty {
                Button { team.use(nil) } label: { Label("Plain Zuffi (no agent)", systemImage: "xmark.circle") }
                Divider()
            }
            if plan.isBusiness {
                if !team.hiredAgents.isEmpty {
                    Button { team.activeIDs = team.hired; AIService.shared.clearConversation() } label: {
                        Label("🧭 Whole team with Team Manager", systemImage: "person.3.sequence.fill")
                    }
                    Section("Your AI team — pick several") {
                        ForEach(team.hiredAgents) { a in
                            Button { team.toggle(a) } label: { Text("\(a.emoji) \(a.name)\(team.activeIDs.contains(a.id) ? "  ✓" : "")") }
                        }
                    }
                }
                Button { BusinessDashboard.shared.show(.aiTeam) } label: { Label("Hire & manage your team…", systemImage: "person.badge.plus") }
                Divider()
            }
            ForEach(team.divisions, id: \.self) { d in
                Menu(ZuffiTeam.divisionLabel(d)) {
                    ForEach(team.members(of: d)) { a in
                        Button { plan.isBusiness ? team.toggle(a) : team.use(a) } label: {
                            Text("\(a.emoji) \(a.name)\(team.activeIDs.contains(a.id) ? "  ✓" : "")")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                let people = team.activeAgents
                if people.count == 1, let a = people.first {
                    Text(a.emoji).font(.system(size: 11))
                    if !compact { Text(a.name).font(.system(size: 10, weight: .medium)).lineLimit(1) }
                } else if people.count > 1 {
                    Text("🧭").font(.system(size: 11))
                    Text("\(people.count)").font(.system(size: 10, weight: .bold))
                } else {
                    Image(systemName: "person.3.fill").font(.system(size: 10, weight: .semibold))
                    if !compact { Text("Team").font(.system(size: 10, weight: .medium)) }
                }
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 7).frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(team.activeIDs.isEmpty ? 0.08 : 0.2)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(team.activeAgents.isEmpty ? "Pick a specialist from Zuffi's team" : "Talking to " + team.activeAgents.map(\.name).joined(separator: ", "))
    }
}

/// Compact model chip for the chat line (icon only).
struct ModelChip: View {
    @ObservedObject var state: AppState
    var body: some View {
        let current = AIProvider(rawValue: state.aiProvider) ?? .auto
        Menu {
            ForEach(AIProvider.allCases.filter { $0 != .zuffi || ZuffiPlan.shared.isPaid }) { p in
                Button {
                    state.aiProvider = p.rawValue
                    UserDefaults.standard.set(p.rawValue, forKey: "aiProvider")
                    AIService.shared.clearConversation()
                } label: { Label(p.label + (p == current ? "  ✓" : ""), systemImage: p.icon) }
            }
        } label: {
            Image(systemName: current.icon).font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .frame(width: 24, height: 22)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("AI model: \(current.label)")
    }
}

struct TeamSettings: View {
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var search = ""
    var body: some View {
        GroupBox("Zuffi's team") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(team.agents.count) specialists — sales, marketing, finance, support, product and more. Pick one and it answers as that person. Say “back to normal” to stop. With Business you can hire your own team and give it jobs.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Text("Talking to:"); Text(team.activeAgents.isEmpty ? "Plain Zuffi" : team.activeAgents.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ")).bold().lineLimit(2); Spacer()
                    if !team.activeIDs.isEmpty { Button("Stop") { team.use(nil) }.controlSize(.small) } }
                TextField("Search the team…", text: $search).textFieldStyle(.roundedBorder)
                if !search.isEmpty {
                    let hits = team.agents.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }.prefix(12)
                    ForEach(Array(hits)) { a in
                        HStack {
                            Text(a.emoji)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(.system(size: 12, weight: .semibold))
                                Text(a.description).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button(team.activeIDs.contains(a.id) ? "In use" : "Use") { team.use(a) }.controlSize(.small).disabled(team.activeIDs.contains(a.id))
                        }
                    }
                }
                Text("Team from “agency-agents” (MIT licence).").font(.system(size: 9.5)).foregroundColor(.secondary)
            }.padding(6)
        }
    }
}

// MARK: - Business → AI Team

struct BizAITeamView: View {
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var job = ""
    @State private var picked: Set<String> = []
    @State private var browsing = false
    @State private var search = ""
    @State private var division = "sales"
    @State private var open: String?
    @State private var running = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stats
                if team.hiredAgents.isEmpty { emptyTeam } else { members; jobBox }
                if !team.tasks.isEmpty { board }
                if browsing || team.hiredAgents.isEmpty { browser }
            }
            .padding(22)
        }
        .onAppear { if picked.isEmpty { picked = Set(team.hired) } }
    }

    private var stats: some View {
        HStack(spacing: 12) {
            stat("Team members", "\(team.hiredAgents.count + (team.hiredAgents.isEmpty ? 0 : 1))", "person.3.fill", "#0EA5C6")
            stat("Jobs done", "\(team.tasks.filter { $0.status == "Done" }.count)", "checkmark.seal.fill", "#0F9F76")
            stat("Need you", "\(team.tasks.filter { $0.status == "Needs you" }.count)", "exclamationmark.bubble.fill", "#E0527E")
            stat("Working", team.working.isEmpty ? "0" : "1", "bolt.fill", "#F2A516")
        }
    }

    private func stat(_ label: String, _ value: String, _ icon: String, _ tint: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundColor(Ink.faint).lineLimit(1)
                Text(value).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundColor(Ink.text)
            }
            Spacer(minLength: 4)
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                .frame(width: 38, height: 38).background(Circle().fill(Color(hex: tint).gradient))
        }
        .padding(14).frame(maxWidth: .infinity).zGlass(16)
    }

    private var emptyTeam: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Build your AI team").font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Hire specialists — a product manager, a researcher, a finance analyst, a sales coach… Give them a job and the Team Manager splits it between them and brings back one clear answer. They use your business details, ask you when something is missing, and never send or change anything without your OK.")
                .font(.system(size: 12)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button { team.starterTeam.compactMap(team.agent).forEach(team.hire); picked = Set(team.hired) } label: {
                    Label("Hire a starter team", systemImage: "sparkles").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(Ink.accent))
                }.buttonStyle(.plain)
                Text("or pick people below").font(.system(size: 11)).foregroundColor(Ink.faint)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading).zGlass(18)
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your team").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button { browsing.toggle() } label: { Label(browsing ? "Done" : "Hire more", systemImage: browsing ? "checkmark" : "person.badge.plus").font(.system(size: 11.5, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundColor(Ink.accent)
                Button {
                    team.activeIDs = team.hired; AIService.shared.clearConversation(); ZuffiChat.shared.open()
                } label: { Label("Talk to the team", systemImage: "bubble.left.and.bubble.right.fill").font(.system(size: 11.5, weight: .semibold)) }
                    .buttonStyle(.plain).foregroundColor(Ink.accent).padding(.leading, 10)
            }
            row(ZuffiTeam.manager, lead: true)
            ForEach(team.hiredAgents) { a in row(a) }
        }
        .padding(16).zGlass(18)
    }

    private func row(_ a: TeamAgent, lead: Bool = false) -> some View {
        HStack(spacing: 12) {
            Text(a.emoji).font(.system(size: 18)).frame(width: 38, height: 38).background(Circle().fill(Ink.accent.opacity(0.14)))
                .overlay(alignment: .bottomTrailing) { Circle().fill(Color(hex: "#3FC48C")).frame(width: 9, height: 9).overlay(Circle().stroke(Ink.panel, lineWidth: 2)) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Ink.text)
                    if lead { Text("LEADS").font(.system(size: 8.5, weight: .heavy)).foregroundColor(Ink.accent).padding(.horizontal, 5).frame(height: 15).background(Capsule().fill(Ink.accent.opacity(0.15))) }
                    if ZuffiTeam.isResearcher(a) { Image(systemName: "globe").font(.system(size: 9)).foregroundColor(Ink.faint).help("Can look things up on the web") }
                }
                Text(a.description).font(.system(size: 11)).foregroundColor(Ink.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !lead {
                Toggle("", isOn: Binding(get: { picked.contains(a.id) }, set: { if $0 { picked.insert(a.id) } else { picked.remove(a.id) } }))
                    .toggleStyle(.checkbox).labelsHidden().help("On this job")
                Button { team.use(a); ZuffiChat.shared.open() } label: { Image(systemName: "bubble.left.fill").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundColor(Ink.muted).help("Talk to \(a.name)")
                Button { team.fire(a); picked.remove(a.id) } label: { Image(systemName: "person.fill.xmark").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundColor(Ink.faint).help("Remove from the team")
            }
        }
        .padding(.vertical, 4)
    }

    private var jobBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Give the team a job").font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Tick who works on it above. Example: “Research what customers in my area pay and suggest new prices”.")
                .font(.system(size: 11)).foregroundColor(Ink.faint)
            HStack(spacing: 8) {
                TextField("What should the team do?", text: $job, axis: .vertical).textFieldStyle(.plain).lineLimit(1...4)
                    .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Ink.panelHi)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.line))
                Button {
                    let t = job.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
                    let who = team.hired.filter(picked.contains).compactMap(team.agent)
                    job = ""; running = true
                    Task { @MainActor in let done = await team.assign(t, to: who.isEmpty ? team.hiredAgents : who); open = done.id; running = false }
                } label: {
                    Label("Assign", systemImage: "paperplane.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 14).frame(height: 34).background(Capsule().fill(Ink.accent))
                }.buttonStyle(.plain).disabled(running || job.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if !team.working.isEmpty {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(team.working).font(.system(size: 11.5)).foregroundColor(Ink.muted).lineLimit(1) }
            }
        }
        .padding(16).zGlass(18)
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Jobs").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button("Clear done") { team.tasks.removeAll { $0.status == "Done" } }.buttonStyle(.plain).font(.system(size: 11)).foregroundColor(Ink.faint)
            }
            ForEach(team.tasks) { t in taskRow(t) }
        }
        .padding(16).zGlass(18)
    }

    private func taskRow(_ t: TeamTask) -> some View {
        let color: String = ["Done": "#3FC48C", "Working": "#F2A516", "Needs you": "#E0527E"][t.status] ?? "#8A92A4"
        return VStack(alignment: .leading, spacing: 8) {
            Button { open = open == t.id ? nil : t.id } label: {
                HStack(spacing: 10) {
                    Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
                    Text(t.title).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Ink.text).lineLimit(open == t.id ? nil : 1)
                    Spacer(minLength: 8)
                    HStack(spacing: -6) { ForEach(t.agents.prefix(5), id: \.self) { id in Text(team.agent(id)?.emoji ?? "👤").font(.system(size: 11)).frame(width: 22, height: 22).background(Circle().fill(Ink.panelHi)).overlay(Circle().stroke(Ink.panel, lineWidth: 1.5)) } }
                    Text(t.status).font(.system(size: 10, weight: .bold)).foregroundColor(Color(hex: color)).padding(.horizontal, 7).frame(height: 18).background(Capsule().fill(Color(hex: color).opacity(0.15)))
                    Text(t.created, style: .relative).font(.system(size: 10)).foregroundColor(Ink.faint).frame(width: 70, alignment: .trailing)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open == t.id {
                VStack(alignment: .leading, spacing: 10) {
                    if !t.summary.isEmpty { Text("🧭 " + t.summary).font(.system(size: 12)).foregroundColor(Ink.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    ForEach(t.parts, id: \.self) { p in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(team.agent(p.agent)?.emoji ?? "👤") \(team.agent(p.agent)?.name ?? p.agent)").font(.system(size: 11.5, weight: .bold))
                            Text(p.text).font(.system(size: 11.5)).foregroundColor(Ink.muted).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 10).fill(Ink.panelHi))
                    }
                    HStack {
                        Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(team.render(t), forType: .string) }
                        Button("Run again") { Task { @MainActor in await team.rerun(t) } }
                        Button("Ask a follow-up in chat") { team.activeIDs = t.agents; AIService.shared.clearConversation(); AIService.shared.remember(user: t.title, assistant: team.render(t)); ZuffiChat.shared.open() }
                        Spacer()
                        Button("Delete") { team.tasks.removeAll { $0.id == t.id } }.foregroundColor(Color(hex: "#E0527E"))
                    }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundColor(Ink.accent)
                }.padding(.leading, 18)
            }
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) }
    }

    private var browser: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hire specialists").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(Ink.faint)
                    TextField("Search 289 specialists…", text: $search).textFieldStyle(.plain).frame(width: 200)
                }.padding(.horizontal, 10).frame(height: 30).inkPanel(Capsule())
            }
            if search.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(team.divisions, id: \.self) { d in
                            Button { division = d } label: {
                                Text(ZuffiTeam.divisionLabel(d)).font(.system(size: 11, weight: .semibold)).foregroundColor(division == d ? .white : Ink.text)
                                    .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(division == d ? Ink.accent : Ink.panelHi))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            let list = search.isEmpty ? team.members(of: division)
                : team.agents.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], spacing: 10) {
                ForEach(list.prefix(60)) { a in
                    HStack(alignment: .top, spacing: 10) {
                        Text(a.emoji).font(.system(size: 16)).frame(width: 32, height: 32).background(Circle().fill(Ink.accent.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Ink.text)
                            Text(a.description).font(.system(size: 10.5)).foregroundColor(Ink.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        let have = team.hired.contains(a.id)
                        Button { if have { team.fire(a) } else { team.hire(a); picked.insert(a.id) } } label: {
                            Text(have ? "Hired" : "Hire").font(.system(size: 10.5, weight: .bold)).foregroundColor(have ? Ink.muted : .white)
                                .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(have ? Ink.panelHi : Ink.accent))
                        }.buttonStyle(.plain)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi.opacity(0.6)))
                }
            }
        }
        .padding(16).zGlass(18)
    }
}
