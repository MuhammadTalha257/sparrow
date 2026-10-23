import Foundation
import SwiftUI
import AppKit
import Combine

// =====================================================================
// MARK: - Zuffi's team (agency-agents, MIT licence — see THIRD_PARTY_NOTICES.md)
//
// 289 specialists + Zuffi's own business agents (Bookings, Customers, Competitor research).
// • Every agent has a field (finance, bookings, marketing…) that sets its look, its tools (which real data it may read)
//   and its default daily job.
// • Answers are grounded: money and booking figures come only from the Money page, the Appointments sheet,
//   the leads, or a business dashboard Zuffi read from the screen — never invented. If the data isn't there,
//   the agent says so and asks.
// • The Team Manager routes a question only to the agents it needs ("profit today?" → Financial Analyst alone).
// • Every piece of work is a visible run (steps, sources, result) on Business → My Team, with an audit log.
// • Agents think, read and write. Sending, posting, paying or deleting always waits for the owner.
// =====================================================================

struct TeamAgent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let division: String
    let name: String
    let description: String
    let emoji: String
    let prompt: String
}

/// What real data an agent may read.
enum AgentTool: String, Codable, CaseIterable {
    case money, bookings, customers, dashboard, web, contacts
    var label: String {
        switch self {
        case .money: return "Money page"
        case .bookings: return "Bookings"
        case .customers: return "Customers & leads"
        case .dashboard: return "Business dashboard"
        case .web: return "Web search"
        case .contacts: return "WhatsApp contacts"
        }
    }
    var symbol: String {
        switch self {
        case .money: return "sterlingsign.circle.fill"
        case .bookings: return "calendar"
        case .customers: return "person.2.fill"
        case .dashboard: return "rectangle.on.rectangle.angled"
        case .web: return "globe"
        case .contacts: return "message.fill"
        }
    }
}

/// An agent's field: its colours, symbol and tools — so every kind of agent looks and works differently.
enum AgentField: String, CaseIterable {
    case manager, finance, bookings, customers, sales, marketing, research, travel, product, project, support, design, engineering, security, legal, health, data, strategy, education, games, other

    var label: String {
        switch self {
        case .manager: return "Management"
        case .finance: return "Finance"
        case .bookings: return "Bookings"
        case .customers: return "Customers"
        case .sales: return "Sales"
        case .marketing: return "Marketing"
        case .research: return "Research"
        case .travel: return "Travel"
        case .product: return "Product"
        case .project: return "Projects"
        case .support: return "Support"
        case .design: return "Design"
        case .engineering: return "Engineering"
        case .security: return "Security"
        case .legal: return "Legal"
        case .health: return "Health"
        case .data: return "Data & reports"
        case .strategy: return "Strategy"
        case .education: return "Education"
        case .games: return "Games"
        case .other: return "Specialist"
        }
    }
    var symbol: String {
        switch self {
        case .manager: return "point.3.connected.trianglepath.dotted"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .bookings: return "calendar.badge.clock"
        case .customers: return "heart.text.square.fill"
        case .sales: return "handshake.fill"
        case .marketing: return "megaphone.fill"
        case .research: return "magnifyingglass"
        case .travel: return "airplane"
        case .product: return "shippingbox.fill"
        case .project: return "checklist"
        case .support: return "bubble.left.and.text.bubble.right.fill"
        case .design: return "paintbrush.pointed.fill"
        case .engineering: return "chevron.left.forwardslash.chevron.right"
        case .security: return "lock.shield.fill"
        case .legal: return "building.columns.fill"
        case .health: return "cross.case.fill"
        case .data: return "chart.bar.doc.horizontal.fill"
        case .strategy: return "map.fill"
        case .education: return "graduationcap.fill"
        case .games: return "gamecontroller.fill"
        case .other: return "sparkles"
        }
    }
    /// Two colours for the card gradient.
    var colors: [String] {
        switch self {
        case .manager: return ["#F59E3B", "#E8572A"]
        case .finance: return ["#16C47F", "#0B8A5A"]
        case .bookings: return ["#3B82F6", "#1D4ED8"]
        case .customers: return ["#F472B6", "#DB2777"]
        case .sales: return ["#F97316", "#C2410C"]
        case .marketing: return ["#A855F7", "#7E22CE"]
        case .research: return ["#06B6D4", "#0E7490"]
        case .travel: return ["#38BDF8", "#1E40AF"]
        case .product: return ["#6366F1", "#4338CA"]
        case .project: return ["#14B8A6", "#0F766E"]
        case .support: return ["#38BDF8", "#0284C7"]
        case .design: return ["#EC4899", "#9D174D"]
        case .engineering: return ["#64748B", "#334155"]
        case .security: return ["#EF4444", "#991B1B"]
        case .legal: return ["#A3A3A3", "#525252"]
        case .health: return ["#22C55E", "#15803D"]
        case .data: return ["#EAB308", "#A16207"]
        case .strategy: return ["#8B5CF6", "#5B21B6"]
        case .education: return ["#0EA5E9", "#075985"]
        case .games: return ["#84CC16", "#4D7C0F"]
        case .other: return ["#94A3B8", "#475569"]
        }
    }
    var color: Color { Color(hex: colors[0]) }
    var gradient: LinearGradient { LinearGradient(colors: colors.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing) }
    var tools: [AgentTool] {
        switch self {
        case .manager: return [.money, .bookings, .customers, .dashboard]
        case .finance: return [.money, .dashboard]
        case .bookings: return [.bookings, .dashboard, .customers]
        case .customers: return [.customers, .contacts, .bookings]
        case .sales: return [.customers, .contacts]
        case .marketing: return [.customers, .web]
        case .research, .strategy, .travel: return [.web]
        case .product: return [.customers, .web]
        case .data: return [.money, .bookings, .customers, .dashboard]
        case .support: return [.customers, .contacts]
        default: return []
        }
    }

    static func of(_ a: TeamAgent) -> AgentField {
        if a.id == "zuffi-team-manager" { return .manager }
        let n = a.name.lowercased(), d = a.division.lowercased()
        func has(_ w: String...) -> Bool { w.contains { n.contains($0) } }
        if has("travel", "flight") { return .travel }
        if has("booking") { return .bookings }
        if has("customer relationship", "feedback") { return .customers }
        if d == "finance" || has("finance", "financial", "tax", "bookkeep", "accountant", "fp&a") { return .finance }
        if has("legal", "compliance") { return .legal }
        if has("analytics", "executive summary", "report") { return .data }
        if has("research", "trend", "intelligence", "competitor") { return .research }
        switch d {
        case "sales": return .sales
        case "marketing", "paid-media": return .marketing
        case "product": return .product
        case "project-management": return .project
        case "support": return .support
        case "design": return .design
        case "engineering", "testing", "spatial-computing", "gis": return .engineering
        case "security": return .security
        case "healthcare": return .health
        case "academic": return .education
        case "game-development": return .games
        case "strategy": return .strategy
        case "research": return .research
        case "business": return .other
        default: break
        }
        if has("seo", "social", "content", "brand", "growth", "ads") { return .marketing }
        if has("sales", "deal") { return .sales }
        return .other
    }
}

// MARK: - Work records (what the owner sees on My Team)

struct AgentStep: Codable, Hashable { var at = Date(); var text: String }
struct WebLink: Codable, Hashable { var title: String; var url: String }

struct AgentRun: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var agent: String
    var task: String
    var steps: [AgentStep] = []
    var sources: [String] = []
    var result = ""
    var status = "Working"            // Working · Done · Needs input · Failed
    var started = Date()
    var finished: Date?
    var job: String?                  // the daily job it ran for
    var links: [WebLink]?             // pages it read (research)
}

struct JobRun: Codable, Hashable { var at = Date(); var status: String; var summary: String }

/// A daily job for one agent (e.g. Financial Analyst: today's money at 18:00).
struct TeamJob: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var agent: String
    var title: String
    var task: String
    var hour: Int
    var minute: Int
    var enabled = true
    var readsDashboard = false
    var lastRun: Date?
    var lastStatus = ""
    var history: [JobRun] = []
}

struct AuditEntry: Codable, Hashable, Identifiable {
    var id = UUID().uuidString
    var at = Date()
    var who: String
    var action: String
    var detail: String
}

/// A business dashboard the owner pointed Zuffi at (Fresha, Square, a bank…).
struct DataSource: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name: String
    var page: String
    var tabs: [String]
    var added = Date()
    var lastRead: Date?
}

struct DataFigure: Codable, Hashable { var label: String; var value: String; var kind: String; var sure: Bool }

/// What Zuffi read from the dashboard on screen, exactly as shown, with the time it was read.
struct DataReading: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var source: String
    var page: String
    var at = Date()
    var figures: [DataFigure]
    var note = ""
}

/// Agents Zuffi suggests hiring, with the reason.
struct AgentSuggestion: Identifiable, Hashable { var id: String { agent }; let agent: String; let reason: String }

/// Small JSON files in Application Support (team state stays on this Mac).
enum TeamStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Zuffi/Team", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func load<T: Decodable>(_ name: String, _ fallback: T) -> T {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent(name + ".json")) else { return fallback }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode(T.self, from: d)) ?? fallback
    }
    static func save<T: Encodable>(_ name: String, _ value: T) {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970
        if let d = try? enc.encode(value) { try? d.write(to: dir.appendingPathComponent(name + ".json"), options: .atomic) }
    }
}

@MainActor
final class ZuffiTeam: ObservableObject {
    static let shared = ZuffiTeam()

    /// Leads the team: routes each question to the right people, sums up. Always there on the Business plan.
    static let manager = TeamAgent(id: "zuffi-team-manager", division: "management", name: "Team Manager",
                                   description: "Leads your AI team: sends each question only to the people who should answer it and brings back one clear answer with next steps.",
                                   emoji: "🧭", prompt: "")

    /// Zuffi's own business agents (the 289 are general specialists; these know Zuffi's own business data).
    static let builtins: [TeamAgent] = [
        TeamAgent(id: "zuffi-bookings", division: "business", name: "Bookings Agent",
                  description: "Watches your bookings: today's and upcoming appointments or site visits, cancellations and no-shows, from your Appointments sheet and your booking dashboard.",
                  emoji: "📅", prompt: """
                  You count and watch the business's bookings. Report exact counts from the data you're given: today, tomorrow, this week, cancellations, no-shows, free gaps. \
                  Point out busy and quiet times and who hasn't rebooked. Never estimate a count you weren't given.
                  """),
        TeamAgent(id: "zuffi-crm", division: "business", name: "Customer Relationship Agent",
                  description: "Looks after your customers: who's new or returning, who hasn't come back, who needs a follow-up, and what people asked on WhatsApp.",
                  emoji: "🤝", prompt: """
                  You look after customer relationships for a small business. From the customer and contact data you're given, say who is new, returning, \
                  overdue for a visit or follow-up, and suggest short, friendly messages the owner can approve. Never send anything yourself.
                  """),
        TeamAgent(id: "zuffi-travel", division: "business", name: "Travel Agent",
                  description: "Finds flights, hotels and trains: compares prices and times, gives you the links, and can open them in your browser. Never books or pays without your yes.",
                  emoji: "✈️", prompt: """
                  You find travel options for the owner: flights, hotels, trains, car hire. Use the web notes you're given and name each source. \
                  Ask for what's missing (from, to, dates, how many people, one-way or return) — briefly — but still give useful links straight away. \
                  Give options with times and prices only when the notes show them; otherwise say prices must be checked on the link. \
                  You can't book or pay; say “I can open the cheapest option in your browser” and wait for a yes.
                  """),
        TeamAgent(id: "zuffi-competitors", division: "business", name: "Competitor Research Agent",
                  description: "Researches competitors near you — prices, offers, reviews, what they do better — and suggests what to change.",
                  emoji: "🔎", prompt: """
                  You research the owner's local competitors. Use the web notes you're given; name each competitor and source. Compare prices, offers, reviews, \
                  opening hours and online presence with this business, then give 3-5 concrete actions. Say clearly when you couldn't find something.
                  """),
    ]

    @Published private(set) var agents: [TeamAgent] = []
    /// The people talking in the chat right now (one = that agent answers; several = the team with its manager).
    @Published var activeIDs: [String] = {
        let d = UserDefaults.standard
        if let a = d.stringArray(forKey: "teamActive") { return a }
        if let one = d.string(forKey: "teamAgent"), !one.isEmpty { return [one] }
        return []
    }() { didSet { UserDefaults.standard.set(activeIDs, forKey: "teamActive") } }
    /// The business's own team (Business → My Team → Hire).
    @Published var hired: [String] = UserDefaults.standard.stringArray(forKey: "teamHired") ?? [] {
        didSet { UserDefaults.standard.set(hired, forKey: "teamHired") }
    }
    @Published var paused: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "teamPaused") ?? []) {
        didSet { UserDefaults.standard.set(Array(paused), forKey: "teamPaused") }
    }
    @Published var runs: [AgentRun] = TeamStore.load("runs", [AgentRun]()) { didSet { saveSoon("runs") } }
    @Published var jobs: [TeamJob] = TeamStore.load("jobs", [TeamJob]()) { didSet { TeamStore.save("jobs", jobs) } }
    @Published var audit: [AuditEntry] = TeamStore.load("audit", [AuditEntry]()) { didSet { saveSoon("audit") } }
    @Published var sources: [DataSource] = TeamStore.load("sources", [DataSource]()) { didSet { TeamStore.save("sources", sources) } }
    @Published var readings: [DataReading] = TeamStore.load("readings", [DataReading]()) { didSet { TeamStore.save("readings", Array(readings.prefix(200))) } }
    @Published var suggestions: [AgentSuggestion] = []
    @Published var autoHire: Bool = UserDefaults.standard.bool(forKey: "teamAutoHire") { didSet { UserDefaults.standard.set(autoHire, forKey: "teamAutoHire") } }
    /// Let agents click between the dashboard's tabs (navigation only — never changes anything).
    @Published var clickTabs: Bool = UserDefaults.standard.object(forKey: "teamClickTabs") as? Bool ?? true { didSet { UserDefaults.standard.set(clickTabs, forKey: "teamClickTabs") } }
    @Published var working = ""          // shown while something runs
    /// "Hire Bookings Agent?" waiting for a yes.
    var pendingHire: [TeamAgent] = []

    /// A new chat: plain Zuffi again, and the team forgets the old topic.
    func newConversation() { activeIDs = []; recent = []; pendingHire = [] }

    private var saveTasks: [String: Task<Void, Never>] = [:]
    private func saveSoon(_ name: String) {
        saveTasks[name]?.cancel()
        saveTasks[name] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            if name == "runs" { TeamStore.save("runs", Array(self.runs.prefix(300))) } else { TeamStore.save("audit", Array(self.audit.prefix(500))) }
        }
    }

    /// Kept for older callers: the one agent in use, or "" (none, or a whole team).
    var activeID: String {
        get { activeIDs.count == 1 ? activeIDs[0] : "" }
        set { activeIDs = newValue.isEmpty ? [] : [newValue] }
    }
    var active: TeamAgent? { activeIDs.count == 1 ? agent(activeIDs[0]) : nil }
    var activeAgents: [TeamAgent] { activeIDs.compactMap(agent) }
    var isTeam: Bool { activeAgents.count > 1 }
    var hiredAgents: [TeamAgent] { hired.compactMap(agent) }
    /// Teams (several at once, hiring, jobs, dashboard reading) come with the Business plan.
    var teamsAllowed: Bool { ZuffiPlan.shared.isBusiness }
    var everyone: [TeamAgent] { Self.builtins + agents }

    func agent(_ id: String) -> TeamAgent? {
        if id == Self.manager.id { return Self.manager }
        return Self.builtins.first { $0.id == id } ?? agents.first { $0.id == id }
    }

    /// Divisions in a friendly order: business ones first.
    var divisions: [String] {
        let order = ["business", "sales", "marketing", "paid-media", "support", "finance", "product", "project-management", "research",
                     "specialized", "design", "engineering", "testing", "security", "healthcare", "academic", "strategy"]
        let all = Set(everyone.map(\.division))
        return order.filter(all.contains) + all.subtracting(order).sorted()
    }

    func members(of division: String) -> [TeamAgent] { everyone.filter { $0.division == division }.sorted { $0.name < $1.name } }

    static func divisionLabel(_ d: String) -> String {
        if d == "business" { return "Zuffi Business" }
        return d.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    /// A good first team for each kind of business.
    var starterTeam: [String] {
        var ids = ["finance-financial-analyst", "zuffi-bookings", "zuffi-crm", "marketing-social-media-strategist", "zuffi-competitors", "product-manager"]
        if ZuffiCRM.shared.isEstate { ids = ["finance-financial-analyst", "zuffi-bookings", "zuffi-crm", "sales-deal-strategist", "marketing-social-media-strategist", "zuffi-competitors"] }
        return ids.filter { agent($0) != nil }
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
            self.activeIDs = self.activeIDs.filter { self.agent($0) != nil && $0 != Self.manager.id }
            // Work that was running when Zuffi quit didn't finish — say so honestly.
            for i in self.runs.indices where self.runs[i].status == "Working" {
                self.runs[i].status = "Failed"; self.runs[i].result = "Stopped — Zuffi was closed before this finished."; self.runs[i].finished = Date()
            }
        }
    }

    // MARK: Status

    enum Status: String { case active = "Active", working = "Working", waiting = "Waiting for input", attention = "Needs attention", offline = "Paused" }

    func status(_ a: TeamAgent) -> Status {
        if paused.contains(a.id) { return .offline }
        if runs.contains(where: { $0.agent == a.id && $0.status == "Working" }) { return .working }
        guard let last = runs.first(where: { $0.agent == a.id }) else { return .active }
        switch last.status {
        case "Needs input": return .waiting
        case "Failed": return .attention
        default: return .active
        }
    }
    static func color(_ s: Status) -> Color {
        switch s {
        case .active: return Color(hex: "#3FC48C")
        case .working: return Color(hex: "#F2A516")
        case .waiting: return Color(hex: "#6EA8F7")
        case .attention: return Color(hex: "#EF6B6B")
        case .offline: return Color(hex: "#8A92A4")
        }
    }
    func lastRun(_ a: TeamAgent) -> AgentRun? { runs.first { $0.agent == a.id } }
    func lastSuccess(_ a: TeamAgent) -> AgentRun? { runs.first { $0.agent == a.id && $0.status == "Done" } }
    func current(_ a: TeamAgent) -> AgentRun? { runs.first { $0.agent == a.id && $0.status == "Working" } }

    // MARK: Runs & audit

    @discardableResult
    func begin(_ a: TeamAgent, _ task: String, job: String? = nil) -> String {
        let r = AgentRun(agent: a.id, task: String(task.prefix(400)), job: job)
        runs.insert(r, at: 0)
        if runs.count > 300 { runs.removeLast(runs.count - 300) }
        return r.id
    }
    func step(_ id: String, _ text: String, source: String? = nil) {
        guard let i = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[i].steps.append(AgentStep(text: text))
        if let source, !runs[i].sources.contains(source) { runs[i].sources.append(source) }
    }
    func finish(_ id: String, _ result: String, _ status: String) {
        guard let i = runs.firstIndex(where: { $0.id == id }) else { return }
        runs[i].result = result; runs[i].status = status; runs[i].finished = Date()
    }
    func log(_ who: String, _ action: String, _ detail: String = "") {
        audit.insert(AuditEntry(who: who, action: action, detail: String(detail.prefix(300))), at: 0)
        if audit.count > 500 { audit.removeLast(audit.count - 500) }
    }

    // MARK: Who they are

    static func isResearcher(_ a: TeamAgent) -> Bool { AgentField.of(a).tools.contains(.web) }

    /// The role guide without code samples, tables and decoration — the parts that say how this person thinks.
    private static func guide(_ a: TeamAgent, limit: Int = 2600) -> String {
        var t = a.prompt.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^\\|.*\\|\\s*$", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\*\\*", with: "").replacingOccurrences(of: "(?m)^#+\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return String(t.prefix(limit))
    }

    /// The business and the owner, short (no reminders, no personal memory — agents work on the business).
    static var businessContext: String {
        let crm = ZuffiCRM.shared, biz = ZuffiBusiness.shared
        let country = ["PK": "Pakistan", "GB": "the UK"][crm.country] ?? ""
        var lines: [String] = []
        let name = biz.businessName.isEmpty ? "(name not given yet)" : "“\(biz.businessName)”"
        lines.append("Business: \(name) — \(crm.businessWord)\(country.isEmpty ? "" : " in \(country)"). Money is in \(crm.currency). Today is \(ZuffiBusiness.iso(Date())).")
        let owner = AssistantPrefs.displayName
        if !owner.isEmpty { lines.append("Owner: \(owner).") }
        let info = crm.businessInfo.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append(info.isEmpty ? "Business details: NOT FILLED IN YET — ask the owner for anything you need about the business."
                                  : "Business details from the owner (use these exact facts):\n" + String(info.prefix(3000)))
        if !crm.todaysUpdate.isEmpty { lines.append("Today's offer / news: \(crm.todaysUpdate)") }
        return lines.joined(separator: "\n")
    }

    /// Identity first, then the rules, the business, and only the real data this agent's tools allow.
    func systemPrompt(for a: TeamAgent, part: String = "", others: [TeamAgent] = [], data: String = "") -> String {
        let field = AgentField.of(a)
        let owner = AssistantPrefs.displayName.isEmpty ? "the owner" : AssistantPrefs.displayName
        let team = others.isEmpty ? "" : "\nYou're working together with: " + others.map(\.name).joined(separator: ", ") + ". Do only your own part; don't repeat theirs."
        return """
        You are \(a.name) \(a.emoji), a senior \(a.name) (\(field.label)) with 15+ years of experience, working on \(owner)'s team inside Zuffi. Zuffi is the owner's AI assistant and business manager; you are one of the team members, led by the Team Manager.\(team)
        WHO YOU ARE
        - Speak as yourself, in the first person. If asked who you are, say “I'm your \(a.name)” and in one line how you help this business. Never call yourself Zuffi or “an AI model”.
        - Your expertise: \(a.description)
        - Stay on the owner's question and on your own field. Never talk about reminders, the owner's personal life or Zuffi's features unless asked.
        HOW YOU WORK
        - Think like the best \(a.name) in the field, for THIS business: practical steps, examples, what to do first.
        - NUMBERS: use only numbers that appear in VERIFIED DATA below. Never invent, estimate or "assume" revenue, costs, tax, profit, bookings, customers or prices. If a number you need isn't there, say it can't be verified yet and ask the owner for it (or to open the page). Label figures as actual (from data), calculated (show the sum) or missing.
        - If you need a fact about the business that isn't here, ask one or two short questions first.
        - If the question belongs to another field, say who on the team should take it.
        - You think, read and write. You can't send messages, post, pay, book or delete — suggest it and ask the owner to OK it.
        - Reply in the owner's language. Plain text with line breaks: no markdown, no ** or ##, no tables. Short paragraphs or numbered steps.
        \(part.isEmpty ? "" : "\nYOUR PART OF THIS JOB: \(part)\nKeep it under 180 words.\n")
        ABOUT THE BUSINESS
        \(Self.businessContext)

        VERIFIED DATA (the only figures you may use)
        \(data.isEmpty ? "(none for this question)" : data)

        YOUR ROLE GUIDE (follow its thinking; ignore anything about tools or code you don't have):
        \(Self.guide(a, limit: part.isEmpty ? 2200 : 1200))
        """
    }

    /// "Hi, I'm your …" — instant, no AI.
    func intro(_ a: TeamAgent) -> String {
        let first = a.description.split(whereSeparator: { ".!".contains($0) }).first.map(String.init) ?? a.description
        return "\(a.emoji) \(a.name): Hi, I'm your \(a.name). \(first.trimmingCharacters(in: .whitespaces))."
    }

    // MARK: Picking and hiring

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

    /// Hiring is real: the agent joins My Team, gets its daily job, and it's in the audit log.
    func hire(_ a: TeamAgent, why: String = "") {
        guard a.id != Self.manager.id, !hired.contains(a.id) else { return }
        hired.append(a.id)
        paused.remove(a.id)
        suggestions.removeAll { $0.agent == a.id }
        log("You", "Hired \(a.name)", why)
        if let j = defaultJob(for: a), !jobs.contains(where: { $0.agent == a.id }) { jobs.append(j); log(a.name, "Daily job added", "\(j.title) at \(String(format: "%02d:%02d", j.hour, j.minute))") }
        BizNav.shared.say("\(a.emoji) \(a.name) joined your team")
    }
    func fire(_ a: TeamAgent) {
        hired.removeAll { $0 == a.id }; activeIDs.removeAll { $0 == a.id }
        jobs.removeAll { $0.agent == a.id }
        log("You", "Removed \(a.name) from the team")
    }
    /// Everyone off the team (their work history stays).
    func startFresh() {
        let n = hired.count
        hired = []; activeIDs = []; jobs = []; suggestions = []; pendingHire = []
        log("You", "Started a fresh team", "Removed \(n) agents")
    }
    func setPaused(_ a: TeamAgent, _ on: Bool) {
        if on { paused.insert(a.id) } else { paused.remove(a.id) }
        log("You", on ? "Paused \(a.name)" : "Resumed \(a.name)")
    }

    /// The everyday job each field does.
    func defaultJob(for a: TeamAgent) -> TeamJob? {
        let dash = !sources.isEmpty
        switch AgentField.of(a) {
        case .finance: return TeamJob(agent: a.id, title: "Today's money", task: "What are today's revenue, costs, tax and profit?", hour: 18, minute: 0, readsDashboard: dash)
        case .bookings: return TeamJob(agent: a.id, title: "Bookings check", task: "How many bookings do we have today and tomorrow, and any cancellations or no-shows?", hour: 8, minute: 30, readsDashboard: dash)
        case .customers: return TeamJob(agent: a.id, title: "Customers to look after", task: "Which customers are new, which haven't come back, and who needs a follow-up today? Suggest messages for me to approve.", hour: 9, minute: 15)
        case .research where a.id == "zuffi-competitors":
            return TeamJob(agent: a.id, title: "Competitor check", task: "Research my local competitors today: prices, offers, reviews — why might customers choose them over us, and what should we change?", hour: 10, minute: 0)
        case .marketing: return TeamJob(agent: a.id, title: "Today's post idea", task: "Suggest one social media post for today (caption and picture idea) for my business.", hour: 9, minute: 45)
        default: return nil
        }
    }

    /// Common words → the person most people mean.
    private static let aliases: [(String, String)] = [
        ("team manager", "zuffi-team-manager"), ("manager", "zuffi-team-manager"),
        ("finance", "finance-financial-analyst"), ("financial", "finance-financial-analyst"), ("accountant", "finance-bookkeeper-controller"),
        ("accounts", "finance-bookkeeper-controller"), ("bookkeeper", "finance-bookkeeper-controller"), ("cfo", "finance-financial-analyst"),
        ("money", "finance-financial-analyst"), ("tax", "finance-tax-strategist"),
        ("travel", "zuffi-travel"), ("flight", "zuffi-travel"), ("flights", "zuffi-travel"), ("travel agent", "zuffi-travel"),
        ("booking agent", "zuffi-bookings"), ("booking", "zuffi-bookings"), ("bookings", "zuffi-bookings"), ("appointments", "zuffi-bookings"),
        ("customer", "zuffi-crm"), ("customers", "zuffi-crm"), ("crm", "zuffi-crm"), ("customer relationship", "zuffi-crm"),
        ("competitor", "zuffi-competitors"), ("competitors", "zuffi-competitors"), ("competitor research", "zuffi-competitors"),
        ("research", "research-synthesist"), ("researcher", "research-synthesist"),
        ("product manager", "product-manager"), ("product", "product-manager"), ("pm", "product-manager"),
        ("project manager", "project-manager-senior"), ("project", "project-manager-senior"),
        ("sales", "sales-coach"), ("seller", "sales-coach"), ("marketing", "marketing-social-media-strategist"),
        ("social media", "marketing-social-media-strategist"), ("seo", "marketing-seo-specialist"), ("content", "marketing-content-creator"),
        ("support", "support-support-responder"), ("customer service", "support-support-responder"), ("legal", "support-legal-compliance-checker"),
        ("lawyer", "support-legal-compliance-checker"), ("growth", "marketing-growth-hacker"), ("ads", "paid-media-paid-social-strategist"),
    ]

    /// Little words that never identify an agent ("for me", "please"…).
    static let filler: Set<String> = ["the", "a", "an", "my", "our", "me", "us", "for", "to", "please", "now", "agent", "agents", "specialist", "expert",
                                      "team", "member", "person", "guy", "one", "new", "some", "someone", "and", "of", "in", "on", "with", "can", "you", "hire", "add"]

    /// Finds an agent by words the user said ("sales coach", "seo", "finance"). nil when unsure — never a random match.
    func find(_ words: String) -> TeamAgent? {
        let tokens = words.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "&" }).map(String.init).filter { $0.count >= 2 && !Self.filler.contains($0) }
        guard !tokens.isEmpty else { return nil }
        let w = tokens.joined(separator: " ")
        if let exact = everyone.first(where: { $0.name.lowercased() == w }) { return exact }
        if let hit = Self.aliases.first(where: { $0.0 == w }), let a = agent(hit.1) { return a }
        // The business's own team first ("finance" → the finance person you hired).
        if let mine = hiredAgents.first(where: { AgentField.of($0).label.lowercased() == w }) { return mine }
        func wordSet(_ s: String) -> Set<String> { Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)) }
        let scored = (hiredAgents + everyone).enumerated().map { (i, a) -> (TeamAgent, Int) in
            let n = wordSet(a.name), f = AgentField.of(a).label.lowercased()
            var score = 0
            for t in tokens {
                if n.contains(t) { score += 10 }                                              // a whole word of its name
                else if t.count >= 4, n.contains(where: { $0.hasPrefix(t) || t.hasPrefix($0) && $0.count >= 4 }) { score += 6 }
                if f == t || f.hasPrefix(t) && t.count >= 4 { score += 4 }
            }
            return (a, score > 0 && i < hiredAgents.count ? score + 1 : score)
        }.filter { $0.1 >= 6 }
        if let best = scored.max(by: { $0.1 < $1.1 }) { return best.0 }
        if let hit = Self.aliases.first(where: { a in tokens.contains(a.0) || w.contains(a.0) && a.0.contains(" ") }) { return agent(hit.1) }
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
        // "this is my business dashboard" — Zuffi reads it from the screen and suggests the right team.
        if t.range(of: #"^(this is|here'?s|that'?s|this is our|it'?s) (my|our)? ?(business |salon |shop |booking |sales )?(dashboard|fresha|square|booksy|treatwell|admin( page)?|booking system|back ?office)\b|^(read|connect|learn|watch) (my|our|the) (business )?dashboard$"#, options: .regularExpression) != nil {
            return await connectDashboard()
        }
        if t.range(of: #"^(read|check|look at) (my|our|the) (dashboard|screen|fresha) (again|now)$|^(refresh|update) (the )?dashboard( numbers)?$"#, options: .regularExpression) != nil {
            let (r, err) = await readDashboard(for: nil, tab: nil)
            guard let r else { return err }
            return "Read \(r.source) (\(r.page)) at \(Self.time(r.at)):\n" + Self.figuresText(r)
        }
        if t.range(of: #"^(hire|ok hire|yes hire) (them|all|everyone|the team|those)( all)?$"#, options: .regularExpression) != nil, !suggestions.isEmpty {
            guard teamsAllowed else { return "Hiring your own AI team is part of Zuffi Business." }
            let list = suggestions
            for s in list { if let a = agent(s.agent) { hire(a, why: s.reason) } }
            return "Hired: " + list.compactMap { agent($0.agent)?.name }.joined(separator: ", ") + ". They're on Business → My Team with their daily jobs."
        }
        // "who are you?" / "who are you guys?" while agents are picked → they introduce themselves.
        if !activeIDs.isEmpty, t.range(of: #"^(who|what) (are|r) (you|u)( guys| all| people| two| both| everyone)?( and what (do )?(you|u) do( for me)?)?$|^introduce (yourself|yourselves|the team)$|^who('s| is) (here|there|this)$|^(tell me )?about (yourself|yourselves)$|^aap kaun (ho|hain)$"#, options: .regularExpression) != nil {
            let people = activeAgents
            if people.count == 1 { return intro(people[0]) + " What can I do for you?" }
            return ([intro(Self.manager) + " I lead this team — ask anything and I'll send it to the right person."] + people.map(intro)).joined(separator: "\n\n")
        }
        if t.range(of: #"^(who('s| is) (on )?(my|your) team|list (the |my |your )?(team|agents)|show (me )?(the |my |your )?(team|agents))$"#, options: .regularExpression) != nil {
            if !hiredAgents.isEmpty {
                return "Your AI team (\(hiredAgents.count + 1)):\n" + ([Self.manager] + hiredAgents).map { "\($0.emoji) \($0.name) — \(status($0).rawValue)" }.joined(separator: "\n")
                    + "\n\nOpen Business → My Team to see what each one is doing."
            }
            return "I have \(everyone.count) specialists in \(divisions.count) fields. Say “switch to the finance agent”, or open Business → My Team to hire your own team."
        }
        if t.range(of: #"^(which|what) agents?( is| are)?( on| active| working)?$"#, options: .regularExpression) != nil {
            let p = activeAgents
            return p.isEmpty ? "No agent — I'm plain Zuffi." : "Right now: " + p.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ") + "."
        }
        // "yes" after "Hire Bookings Agent?"
        if !pendingHire.isEmpty, t.range(of: #"^(yes|yeah|yep|ok|okay|sure|haan|han|ji|do it|hire (him|her|them|it))( please)?$"#, options: .regularExpression) != nil {
            let list = pendingHire; pendingHire = []
            list.forEach { hire($0, why: "You asked") }
            return list.map(intro).joined(separator: "\n\n") + "\n\nThey're on Business → My Team now (\(hired.count) on your team)."
        }
        if !pendingHire.isEmpty, t.range(of: #"^(no|nope|cancel|not now|nahi)"#, options: .regularExpression) != nil { pendingHire = []; return "Okay, nobody hired." }
        // "hire the SEO specialist" / "hire booking agent for me" / "add tax strategist to my team" → asks first
        if let m = Self.match(t, #"^(?:please )?(?:hire|add) (.+?)(?: to (?:my |the |our )?team)?$"#),
           t.hasPrefix("hire") || t.hasPrefix("please hire") || (t.contains("team") && t.range(of: #"\b(agent|specialist|expert|analyst|strategist|manager)\b"#, options: .regularExpression) != nil) {
            guard teamsAllowed else { return "Hiring your own AI team is part of Zuffi Business." }
            let found = findMany(m[0]).filter { $0.id != Self.manager.id }
            guard !found.isEmpty else { return "I'm not sure who you mean. Try a field like “hire a bookings agent”, “hire a travel agent”, or open Business → My Team to browse everyone." }
            let new = found.filter { !hired.contains($0.id) }
            guard !new.isEmpty else { return found.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ") + " is already on your team." }
            pendingHire = new
            return "Hire " + new.map { "\($0.emoji) \($0.name) (\(AgentField.of($0).label))" }.joined(separator: " and ") + "?\n" + new.map { "• \($0.description.prefix(120))" }.joined(separator: "\n") + "\n\nSay “yes” to hire."
        }
        // "check my business inbox", "how many messages", "old messages", "who messaged" → from the real inbox and contacts
        if teamsAllowed, t.range(of: #"\b(inbox|unread|messages?|who (messaged|wrote|texted)|leads? (today|waiting)|need(s)? (a )?reply)\b"#, options: .regularExpression) != nil,
           t.range(of: #"^(send|reply|write|draft|message|tell|text|read|open|delete|remind) "#, options: .regularExpression) == nil,
           t.range(of: #"\b(email|mail|gmail|outlook)\b"#, options: .regularExpression) == nil {
            return TeamData.inboxAnswer(t)
        }
        // "assign <job> to research and product manager"
        if let m = Self.match(t, #"^(?:assign|give) (.+?) to (?:the |my )?(.+?)(?: agents?| team)?$"#), teamsAllowed {
            let who = findMany(m[1]).filter { $0.id != Self.manager.id }
            if !who.isEmpty { return await answer(m[0], people: who, routeOnly: false) }
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
        return hello + "\n\n" + (await ask(rest))
    }

    /// An answer from whoever is picked (or the named people) — routed, grounded and logged.
    func ask(_ question: String, who: [TeamAgent]? = nil) async -> String {
        let people = who ?? activeAgents
        guard !people.isEmpty else { return await dispatch(question) ?? "Tell me what you need and I'll give it to the right person on the team." }
        return await answer(question, people: people, routeOnly: true)
    }

    // MARK: The Team Manager: route → work → sum up

    /// Which field a question belongs to (by its words).
    static func intent(_ q: String) -> AgentField? {
        let t = q.lowercased()
        func m(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        if m(#"\b(flights?|fly|airline|airport|hotels?|train tickets?|holiday|trip to|travel(ling)? to)\b"#) { return .travel }
        if m(#"\b(profit|revenue|income|turnover|takings|expenses?|costs?|spent|spend|tax|vat|cash ?flow|margin|earn(ed|ings)?|kamai|munafa|kharcha|money (in|out|made)|how much (did|have) we (make|made|sell|sold|earn))\b"#) { return .finance }
        if m(#"\b(bookings?|appointments?|booked|no.?shows?|cancell?ations?|slots?|site visits?|visits (today|tomorrow))\b"#) { return .bookings }
        if m(#"\b(competitors?|competition|rivals?|other salons|other shops|other agencies)\b"#) { return .research }
        if m(#"\b(instagram|facebook|tiktok|post|reel|caption|social media|marketing|ads?|campaign|seo|reviews? on google)\b"#) { return .marketing }
        if m(#"\b(customers?|clients?|returning|regulars?|loyal|follow.?ups?|complain(t|ts)?|win back|lapsed)\b|\b(come|came) back\b|haven'?t (been|visited|booked)"#) { return .customers }
        if m(#"\b(sell more|sales pitch|close (the )?deal|leads?|negotiat)\b"#) { return .sales }
        if m(#"^(please )?(research|look up|find out|search( the web)? for|what'?s new in|latest news)\b|\b(research|trends?|market size|find out|latest (news|updates?) (on|about|in))\b"#) { return .research }
        if m(#"\b(product|service menu|price list|pricing|new service|package|launch|roadmap|feature)\b"#) { return .product }
        return nil
    }
    /// A figures question (answer from data) rather than advice ("how can I increase profit?").
    static func isFiguresQuestion(_ q: String) -> Bool {
        let t = q.lowercased()
        if t.range(of: #"\b(how (can|do|should|to)|why|improve|increase|reduce|grow|advice|plan|strategy|ideas?|tips?)\b"#, options: .regularExpression) != nil { return false }
        return t.range(of: #"\b(what('s| is| are| were)|how (much|many)|show|tell me|total|today|yesterday|this (week|month)|last (week|month)|kitna|kitne|report)\b"#, options: .regularExpression) != nil
    }

    private static let defaultFor: [AgentField: String] = [
        .finance: "finance-financial-analyst", .bookings: "zuffi-bookings", .customers: "zuffi-crm", .marketing: "marketing-social-media-strategist",
        .sales: "sales-coach", .product: "product-manager", .research: "research-synthesist", .travel: "zuffi-travel",
    ]

    /// The people who should answer: the field's person from the picked team, else from the hired team, else Zuffi's default.
    func route(_ question: String, among people: [TeamAgent]) async -> [TeamAgent] {
        let team = people.filter { $0.id != Self.manager.id }
        // "Today's business report" → money and bookings (and customers if they're on the team) — nobody else.
        if question.lowercased().range(of: #"\b(business|daily|today'?s|weekly|monthly) (report|summary|update)\b|\breport (for|on) (today|this week|this month)\b"#, options: .regularExpression) != nil {
            let pool = team + hiredAgents
            var out: [TeamAgent] = []
            for f in [AgentField.finance, .bookings, .customers] {
                if let a = pool.first(where: { AgentField.of($0) == f }) ?? (f == .customers ? nil : Self.defaultFor[f].flatMap(agent)), !out.contains(a) { out.append(a) }
            }
            if !out.isEmpty { return out }
        }
        if let f = Self.intent(question) {
            let pickFrom = team + hiredAgents
            if f == .research, question.lowercased().range(of: #"competitor|competition|rival"#, options: .regularExpression) != nil,
               let c = pickFrom.first(where: { $0.id == "zuffi-competitors" }) ?? agent("zuffi-competitors") { return [c] }
            if let a = pickFrom.first(where: { AgentField.of($0) == f }) { return [a] }
            if f == .research, let a = pickFrom.first(where: { [.research, .strategy].contains(AgentField.of($0)) }) { return [a] }
            if let id = Self.defaultFor[f], let a = agent(id) { return [a] }
        }
        if team.count <= 1 { return team }
        // No clear field: one quick pick by the manager (1-3 people, usually 1).
        let roster = team.map { "\($0.id) — \($0.name) (\(AgentField.of($0).label))" }.joined(separator: "\n")
        if let j = await AIService.shared.fastJSON("Question: \(question)\n\nTeam:\n\(roster)",
                                                    system: "You are a Team Manager. Pick ONLY the team members needed to answer — usually one, never more than three. JSON: {\"ids\":[\"member id\"]}"),
           let ids = j["ids"] as? [String] {
            let picked = ids.compactMap { id in team.first { $0.id == id } }
            if !picked.isEmpty { return Array(picked.prefix(3)) }
        }
        return [team[0]]
    }

    /// Answers a question with the right people. `routeOnly`: route within `people`; false = everyone given works on it.
    func answer(_ question: String, people: [TeamAgent], routeOnly: Bool) async -> String {
        let chosen = routeOnly ? await route(question, among: people) : people.filter { $0.id != Self.manager.id }
        guard !chosen.isEmpty else { return "Pick someone from the team first." }
        let mgrRun = chosen.count > 1 || people.count > 1 ? begin(Self.manager, question) : nil
        if let mgrRun { step(mgrRun, "Sent to " + chosen.map(\.name).joined(separator: ", ")) }
        var parts: [(TeamAgent, AgentRun)] = []
        for a in chosen {
            if paused.contains(a.id) { continue }
            parts.append((a, await work(a, question)))
        }
        if parts.isEmpty { if let mgrRun { finish(mgrRun, "Everyone needed is paused.", "Needs input") }; return "The people for this are paused. Resume them on Business → My Team." }
        var out = parts.map { "\($0.0.emoji) \($0.0.name):\n\($0.1.result)" }
        if parts.count > 1 {
            let ok = parts.filter { $0.1.status == "Done" }
            let summary = ok.count == parts.count ? await managerSummary(question, ok.map { ($0.0, $0.1.result) }) : nil
            if let summary { out.insert("🧭 Team Manager: " + summary, at: 0) }
            if let mgrRun { finish(mgrRun, summary ?? "Collected \(parts.count) answers.", ok.count == parts.count ? "Done" : "Needs input") }
        } else if let mgrRun { finish(mgrRun, "Answered by \(parts[0].0.name).", parts[0].1.status) }
        let text = out.joined(separator: "\n\n")
        note(question, text)
        return text
    }

    /// One agent does one task: real data first, then (if needed) the AI with that data, checked before it's shown.
    @discardableResult
    func work(_ a: TeamAgent, _ task: String, job: String? = nil, readDashboard: Bool = false) async -> AgentRun {
        let id = begin(a, task, job: job)
        let field = AgentField.of(a)
        working = "\(a.emoji) \(a.name) is working…"
        defer { working = "" }
        step(id, "Got the task")

        // Read the business dashboard on screen first, when the job asks for it.
        if readDashboard, field.tools.contains(.dashboard) {
            let tab = field == .finance ? "Sales / Finance / Reports" : field == .bookings ? "Calendar / Bookings" : nil
            step(id, "Reading your business dashboard on screen\(tab.map { " (\($0))" } ?? "")…", source: sources.first?.name ?? "Business dashboard")
            let (r, err) = await self.readDashboard(for: a, tab: tab)
            if let r { step(id, "Read \(r.figures.count) figure\(r.figures.count == 1 ? "" : "s") from \(r.source) · \(r.page)") }
            else { step(id, "Couldn't read the dashboard: \(err)") }
        }

        // Figures questions: answered straight from the data — no AI, nothing invented.
        if Self.isFiguresQuestion(task) || job != nil {
            if field == .finance || (field == .manager && Self.intent(task) == .finance) {
                let (text, verified, used) = TeamData.financeAnswer(task)
                for u in used { step(id, "Checked \(u)", source: u) }
                finish(id, text, verified ? "Done" : "Needs input")
                return runs.first { $0.id == id }!
            }
            if field == .bookings {
                let (text, verified, used) = TeamData.bookingsAnswer(task)
                for u in used { step(id, "Checked \(u)", source: u) }
                finish(id, text, verified ? "Done" : "Needs input")
                return runs.first { $0.id == id }!
            }
        }

        // Everything else: the AI, with only the real data this agent's tools allow.
        let data = TeamData.block(for: field.tools, question: task)
        for s in data.sources { step(id, "Looked at \(s)", source: s) }
        // Research like a person: search, open the pages, read them — each step shows on the agent's card.
        var webNotes = "", links: [WebLink] = []
        if field.tools.contains(.web), NetStatus.shared.online {
            step(id, "Searching the web for “\(task.prefix(80))”…", source: "Web search")
            let r = await AIService.webSearch(task)
            webNotes = r.notes; links = r.links
            for l in links.prefix(5) { step(id, "Reading: \(l.title.prefix(90))") }
            if links.isEmpty { step(id, "The free search found nothing — asking the AI with Google Search if it's available") }
        }
        if field == .travel { links = Self.travelLinks(task) + links }
        if !links.isEmpty, let i = runs.firstIndex(where: { $0.id == id }) { runs[i].links = Array(links.prefix(10)) }
        var system = systemPrompt(for: a, data: data.text)
        if field == .travel { system += "\n\nLINKS ZUFFI WILL SHOW UNDER YOUR ANSWER (you can refer to them):\n" + Self.travelLinks(task).map { "\($0.title): \($0.url)" }.joined(separator: "\n") }
        step(id, "Writing the answer")
        var reply: String? = nil
        var problem = ""
        for attempt in 0..<2 {
            let extra = attempt == 0 ? "" : "\n\nIMPORTANT: your last answer broke the rules (\(problem)). Answer again as \(a.name), only about this question, using only verified numbers, and don't claim you can book, buy, send or access anything."
            let r = await AIService.shared.textAnswerFull(system: system + extra, messages: recent + [["role": "user", "content": task]], max: 900,
                                                          web: field.tools.contains(.web), notes: webNotes.isEmpty ? nil : webNotes)
            guard let text = r.text else { problem = "no AI answered"; break }
            if !r.links.isEmpty, let i = runs.firstIndex(where: { $0.id == id }) {
                var all = runs[i].links ?? []
                for l in r.links where !all.contains(where: { $0.url == l.url }) { all.append(l) }
                runs[i].links = Array(all.prefix(12))
                for l in r.links.prefix(3) { step(id, "Checked: \(l.title.prefix(90))", source: "Google Search") }
            }
            let clean = Self.plain(text)
            if let bad = Self.badAnswer(clean, agent: a, data: data.text + webNotes, question: task) { problem = bad; step(id, "Answer rejected (\(bad)) — trying again"); continue }
            reply = clean; break
        }
        guard let reply else {
            let why = problem == "no AI answered"
                ? "I couldn't reach an AI just now, so I haven't answered — nothing was made up. \(AIService.builtinAvailable ? "Try again in a minute." : "Zuffi AI isn't available on this Mac yet; add a key in Settings → AI, or try again later.")"
                : "I couldn't produce a reliable answer (\(problem)), so I'm not giving one. Try asking again."
            finish(id, why + ((runs.first { $0.id == id }?.links ?? []).isEmpty ? "" : "\nThe pages I found are linked below."), "Failed")
            return runs.first { $0.id == id }!
        }
        let shownLinks = runs.first { $0.id == id }?.links ?? []
        let withLinks = shownLinks.isEmpty ? reply : reply + "\n\nLinks:\n" + shownLinks.prefix(6).map { "• \($0.title.prefix(70)) — \($0.url)" }.joined(separator: "\n")
        finish(id, withLinks, reply.contains("?") && reply.count < 400 && reply.lowercased().range(of: #"could you|can you (tell|share|give)|please (tell|share|send)|what (is|are) your"#, options: .regularExpression) != nil ? "Needs input" : "Done")
        return runs.first { $0.id == id }!
    }

    /// Flight / hotel searches as links (Google Flights, Skyscanner, Booking.com) from "london to lahore".
    static func travelLinks(_ q: String) -> [WebLink] {
        let t = q.lowercased()
        var from = "", to = ""
        if let re = try? NSRegularExpression(pattern: #"from ([a-z ]+?) to ([a-z ]+?)(?: on| for| in| next| this| tomorrow| and|,|\.|$)"#),
           let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)), let a = Range(m.range(at: 1), in: t), let b = Range(m.range(at: 2), in: t) {
            from = String(t[a]).trimmingCharacters(in: .whitespaces); to = String(t[b]).trimmingCharacters(in: .whitespaces)
        } else if let re = try? NSRegularExpression(pattern: #"([a-z]+) to ([a-z]+)"#), let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
                  let a = Range(m.range(at: 1), in: t), let b = Range(m.range(at: 2), in: t) {
            from = String(t[a]); to = String(t[b])
        }
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        var out: [WebLink] = []
        if t.range(of: #"hotel|stay|room"#, options: .regularExpression) != nil {
            let place = to.isEmpty ? from : to
            if !place.isEmpty { out.append(WebLink(title: "Booking.com — hotels in \(place.capitalized)", url: "https://www.booking.com/searchresults.html?ss=\(enc(place))")) }
        }
        if !from.isEmpty, !to.isEmpty, from != "how", from != "go" {
            let q = "Flights from \(from) to \(to)" + (t.contains("cheap") ? " cheapest" : "")
            out.append(WebLink(title: "Google Flights — \(from.capitalized) to \(to.capitalized)", url: "https://www.google.com/travel/flights?q=\(enc(q))"))
            out.append(WebLink(title: "Compare prices (Skyscanner, Kayak…) — \(from.capitalized) to \(to.capitalized)", url: "https://www.google.com/search?q=\(enc("cheap flights " + from + " to " + to))"))
        }
        return out
    }

    // MARK: Zuffi gives the work out (nobody has to pick an agent)

    /// Splits "research AI news, check today's bookings and write an Instagram post" into separate jobs.
    static func splitTasks(_ q: String) -> [String] {
        let lines = q.components(separatedBy: CharacterSet.newlines).map { $0.replacingOccurrences(of: #"^\s*(\d+[.)]|[-•*])\s*"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.count > 1 { return lines }
        // "…, and also …", "…; …", ", then …", " and " — only where both halves are real jobs.
        let parts = q.components(separatedBy: CharacterSet(charactersIn: ";")).flatMap { $0.components(separatedBy: ", then ") }
            .flatMap { $0.components(separatedBy: " and also ") }.flatMap { p -> [String] in
                let bits = p.components(separatedBy: ", ")
                return bits.allSatisfy({ intent($0) != nil }) ? bits : [p]
            }.flatMap { p -> [String] in
                let bits = p.components(separatedBy: " and ")
                return bits.count > 1 && bits.allSatisfy({ intent($0) != nil && $0.split(separator: " ").count >= 3 }) ? bits : [p]
            }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Zuffi as the manager: each job goes to the right field's agent (on the team, or Zuffi's own if nobody is hired for it),
    /// they work at the same time and show on screen. nil = not team work (Zuffi answers herself).
    func dispatch(_ query: String) async -> String? {
        guard teamsAllowed, !Self.looksLikeCommand(query) else { return nil }
        if query.lowercased().range(of: #"^(remind|set|add|save|delete|remove|open|play|call|note)\b"#, options: .regularExpression) != nil { return nil }
        let jobs = Self.splitTasks(query).compactMap { t -> (String, AgentField)? in Self.intent(t).map { (t, $0) } }
        guard !jobs.isEmpty else { return nil }
        var plan: [(TeamAgent, String)] = []
        for (task, _) in jobs {
            if let a = await route(task, among: hiredAgents).first, !plan.contains(where: { $0.0 == a && $0.1 == task }) { plan.append((a, task)) }
        }
        guard !plan.isEmpty else { return nil }
        if plan.count > 1 { log("Zuffi", "Gave out \(plan.count) jobs", plan.map { "\($0.0.name): \($0.1.prefix(40))" }.joined(separator: " · ")) }
        // All at the same time (each is a main-actor task; their characters pop up on screen).
        var running: [(TeamAgent, Task<AgentRun, Never>)] = []
        for (a, task) in plan where !paused.contains(a.id) {
            running.append((a, Task { @MainActor in await self.work(a, task) }))
        }
        var out: [String] = []
        for (a, t) in running { let r = await t.value; out.append("\(a.emoji) \(a.name):\n\(r.result)") }
        // Not on the team yet? Offer to hire (never hires by itself from a chat question).
        let guests = plan.map { $0.0 }.filter { !hired.contains($0.id) }
        var unique: [TeamAgent] = []
        for g in guests where !unique.contains(g) { unique.append(g) }
        if !unique.isEmpty {
            pendingHire = unique
            out.append("Want " + unique.map(\.name).joined(separator: " and ") + " on your team for next time? Say “yes”.")
        }
        let text = out.joined(separator: "\n\n")
        note(query, text)
        return text
    }

    /// The manager's summary: only what the team said, no new numbers.
    private func managerSummary(_ q: String, _ parts: [(TeamAgent, String)]) async -> String? {
        let all = parts.map { "\($0.0.name): \($0.1.prefix(1200))" }.joined(separator: "\n\n")
        guard let s = await AIService.shared.textAnswer(system: """
        You are the Team Manager. Sum up what the team said in the owner's language: one or two sentences, then "Next steps:" with up to 4 numbered actions (say who does each). \
        Plain text, no markdown. Add NO new facts or numbers — only restate the team's. Under 110 words.
        """, messages: [["role": "user", "content": "Question: \(q)\n\nTeam answers:\n\(all)"]], max: 300) else { return nil }
        let clean = Self.plain(s)
        return Self.badAnswer(clean, agent: Self.manager, data: all) == nil ? clean : nil
    }

    /// Why an answer can't be shown (nil = fine): wrong identity, junk, or money figures that aren't in the data.
    static func badAnswer(_ t: String, agent a: TeamAgent, data: String, question: String = "") -> String? {
        let l = t.lowercased()
        if l.hasPrefix("assistant") || l.hasPrefix("user:") || l.contains("<|") { return "garbled reply" }
        if a.id != manager.id, l.range(of: #"\b(i'?m|i am) zuffi\b|bunny ai|as an ai (language )?model"#, options: .regularExpression) != nil { return "answered as someone else" }
        // Claims an agent can't make: it can't book, buy, send or access systems by itself.
        if l.range(of: #"\bi('ll| will| can|'ve| have)( now)? (book|booked|purchase|buy|pay|paid|send|sent|access|log ?in)\b|\bi have access to\b|\baccess the booking system\b|\bi('ve| have) (booked|sent|paid)\b"#, options: .regularExpression) != nil,
           l.range(of: #"(can'?t|cannot|won'?t|not able to|without your (ok|yes))"#, options: .regularExpression) == nil { return "claimed it can do something it can't" }
        // Drifting back to an old topic (e.g. profit) when the question is about something else.
        if !question.isEmpty, intent(question) != .finance, AgentField.of(a) != .finance,
           l.range(of: #"\b(profit|financial statement|income or expenses)\b"#, options: .regularExpression) != nil,
           question.lowercased().range(of: #"profit|money|income|expense"#, options: .regularExpression) == nil { return "talked about an earlier topic" }
        // Money figures are checked for agents that work with money (and the manager's summary): every amount must be in the data.
        let f = AgentField.of(a)
        guard f.tools.contains(.money) || f.tools.contains(.dashboard) || a.id == manager.id else { return nil }
        let unknown = amounts(in: t).subtracting(amounts(in: data))
        if !unknown.isEmpty { return "used figures that aren't in your data (\(unknown.prefix(3).joined(separator: ", ")))" }
        return nil
    }

    /// Money amounts in a text, normalised ("£1,200.50" → "1200.5").
    static func amounts(in t: String) -> Set<String> {
        let re = try? NSRegularExpression(pattern: #"(£|\$|€|rs\.?\s?|pkr\s?|aed\s?)\s?(\d[\d,]*(\.\d+)?)|(\d[\d,]*(\.\d+)?)\s?(lakh|lac|crore|k\b|pounds|rupees)"#, options: .caseInsensitive)
        var out = Set<String>()
        let ns = t as NSString
        re?.enumerateMatches(in: t, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let whole = ns.substring(with: m.range).lowercased()
            var v = ZuffiMoney.number(whole)
            if whole.contains("k"), !whole.contains("lakh") { v = ZuffiMoney.number(whole) }
            if v > 0 { out.insert(ZuffiMoney.plain(v)) }
        }
        return out
    }

    /// No markdown in the app's text.
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        t = t.replacingOccurrences(of: "(?m)^#{1,6}\\s*", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?m)^\\s*[\\*\\-]\\s+", with: "• ", options: .regularExpression)
        t = t.replacingOccurrences(of: "`", with: "")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recent: [[String: String]] = []
    private func note(_ q: String, _ a: String) {
        recent += [["role": "user", "content": q], ["role": "assistant", "content": String(a.prefix(1500))]]
        if recent.count > 8 { recent.removeFirst(recent.count - 8) }
    }

    /// Kept for older callers (chat with several people).
    func runTeam(_ question: String, people: [TeamAgent]? = nil) async -> String {
        await answer(question, people: people ?? activeAgents, routeOnly: true)
    }

    // MARK: Business dashboard on screen

    static let readPrompt = """
    This is a screenshot of a small-business owner's computer. Return JSON only:
    {"is_dashboard": true or false (is a business dashboard / admin / booking / payments / sales system visible?),
     "platform": "the product's name if visible (Fresha, Square, Booksy, Treatwell, Timely, Shopify, Zameen, a bank…) or \\"unknown\\"",
     "page": "which page or tab is open",
     "tabs": ["names of the navigation sections / tabs you can see"],
     "figures": [{"label": "the label exactly as on screen", "value": "the value exactly as shown, with currency", "kind": "revenue|sales|cost|expenses|tax|profit|bookings|cancellations|no_shows|clients|other", "sure": true}]}
    Copy numbers exactly as shown. If a number is blurry, cut off or you're not sure, set "sure": false. Never add numbers that are not visible. \
    Include the date range shown for the figures in the label (e.g. "Total sales (today)").
    """

    /// The picture → the model (Gemini / Claude key, else Zuffi AI if it can see pictures).
    static func vision(_ prompt: String, _ jpeg: Data) async -> String? {
        if ScreenBrain.ready, let r = await ScreenBrain.ask(prompt: prompt, jpeg: jpeg, json: true) { return r }
        guard AIService.builtinAvailable,
              let r = await WebHub.shared.callJS("return await window.Sparrow.builtinVision(p, i)", ["p": prompt, "i": jpeg.base64EncodedString()]) as? [String: Any],
              let t = r["text"] as? String, !t.isEmpty else { return nil }
        return t
    }

    func parseReading(_ raw: String) -> (isDash: Bool, platform: String, page: String, tabs: [String], figures: [DataFigure])? {
        guard let j = AIService.jsonIn(raw) as? [String: Any] else { return nil }
        let figs = ((j["figures"] as? [[String: Any]]) ?? []).compactMap { f -> DataFigure? in
            guard let l = f["label"] as? String, let v = f["value"] as? String, !v.isEmpty else { return nil }
            return DataFigure(label: l, value: v, kind: (f["kind"] as? String) ?? "other", sure: (f["sure"] as? Bool) ?? false)
        }
        let isDash = (j["is_dashboard"] as? Bool) ?? false
        return (isDash, (j["platform"] as? String) ?? "unknown", (j["page"] as? String) ?? "", (j["tabs"] as? [String]) ?? [], figs)
    }

    /// "This is my business dashboard": read it, remember it, suggest (or hire) the right agents.
    func connectDashboard() async -> String {
        guard teamsAllowed else { return "Reading your business dashboard is part of Zuffi Business." }
        working = "Reading your dashboard…"; defer { working = "" }
        guard let shot = await ScreenGrab.main() else {
            return "I can't see the screen yet. Allow Screen Recording: Zuffi Settings → Screen → Fix permissions, then say it again."
        }
        guard let raw = await Self.vision(Self.readPrompt, shot.jpeg), let r = parseReading(raw) else {
            return "I couldn't read the screen: reading pictures needs a Gemini or Claude key (Settings → AI), or Zuffi AI with pictures switched on. Nothing was saved."
        }
        guard r.isDash else { return "I don't see a business dashboard on the screen. Open it (logged in), make it the front window, and say “this is my business dashboard” again." }
        let name = r.platform.lowercased() == "unknown" || r.platform.isEmpty ? "Business dashboard" : r.platform
        if let i = sources.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            sources[i].tabs = Array(Set(sources[i].tabs + r.tabs)).sorted(); sources[i].page = r.page; sources[i].lastRead = Date()
        } else { sources.insert(DataSource(name: name, page: r.page, tabs: r.tabs, lastRead: Date()), at: 0) }
        let reading = DataReading(source: name, page: r.page, figures: r.figures)
        readings.insert(reading, at: 0)
        log("Zuffi", "Connected \(name)", "Page: \(r.page). Tabs: \(r.tabs.joined(separator: ", "))")
        suggestions = suggest(tabs: r.tabs + [r.page])
        var out = "I can see your \(name) dashboard (\(r.page.isEmpty ? "home" : r.page)).\n"
        if !r.tabs.isEmpty { out += "Sections: " + r.tabs.prefix(10).joined(separator: ", ") + ".\n" }
        out += r.figures.isEmpty ? "No figures are visible on this page.\n" : "Read just now:\n" + Self.figuresText(reading) + "\n"
        if suggestions.isEmpty { return out + "\nYour team already covers this dashboard." }
        if autoHire {
            let list = suggestions
            for s in list { if let a = agent(s.agent) { hire(a, why: s.reason) } }
            for i in jobs.indices where [.finance, .bookings].contains(agent(jobs[i].agent).map(AgentField.of) ?? .other) { jobs[i].readsDashboard = true }
            return out + "\nAuto-hire is on, so I hired: " + list.compactMap { agent($0.agent)?.name }.joined(separator: ", ") + ". Their daily jobs are on Business → My Team."
        }
        return out + "\nI suggest hiring:\n" + suggestions.map { s in "• \(agent(s.agent)?.name ?? s.agent) — \(s.reason)" }.joined(separator: "\n")
            + "\n\nSay “hire them”, or review them on Business → My Team."
    }

    /// Reads the dashboard on screen now (clicking to a tab first if allowed). Never treats an unreadable picture as data.
    func readDashboard(for a: TeamAgent?, tab: String?) async -> (DataReading?, String) {
        guard let src = sources.first else { return (nil, "No dashboard connected yet — open it and say “this is my business dashboard”.") }
        guard var shot = await ScreenGrab.main() else { return (nil, "Zuffi can't see the screen (Screen Recording permission is off).") }
        guard let raw = await Self.vision(Self.readPrompt, shot.jpeg), var r = parseReading(raw) else {
            return (nil, "Reading pictures needs a Gemini or Claude key, or Zuffi AI with pictures.")
        }
        guard r.isDash else { return (nil, "\(src.name) isn't on the screen. Open it (logged in) and keep it in front when the job runs.") }
        // Go to the right tab (navigation only) when the needed one isn't open.
        if let tab, clickTabs, !tab.lowercased().split(separator: "/").contains(where: { r.page.lowercased().contains($0.trimmingCharacters(in: .whitespaces)) }),
           let target = r.tabs.first(where: { t in tab.lowercased().split(separator: "/").contains { t.lowercased().contains($0.trimmingCharacters(in: .whitespaces)) } }) {
            _ = await ScreenAgent.shared.run("In the \(src.name) page that is open, click the “\(target)” tab or menu item only, then answer done. Do not type, change, send or delete anything.")
            if let s2 = await ScreenGrab.main(), let raw2 = await Self.vision(Self.readPrompt, s2.jpeg), let r2 = parseReading(raw2), r2.isDash { shot = s2; r = r2 }
            log(a?.name ?? "Zuffi", "Opened the \(target) tab in \(src.name)")
        }
        let reading = DataReading(source: src.name, page: r.page, figures: r.figures)
        readings.insert(reading, at: 0)
        if let i = sources.firstIndex(where: { $0.id == src.id }) { sources[i].lastRead = Date(); sources[i].tabs = Array(Set(sources[i].tabs + r.tabs)).sorted() }
        log(a?.name ?? "Zuffi", "Read \(src.name)", "\(r.page): \(r.figures.count) figures")
        _ = shot
        return (reading, "")
    }

    static func figuresText(_ r: DataReading) -> String {
        r.figures.prefix(14).map { "• \($0.label): \($0.value)\($0.sure ? "" : " (couldn't read clearly — check)")" }.joined(separator: "\n")
    }
    static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    /// Agents that fit the dashboard's sections and the business type, with the reason.
    func suggest(tabs: [String]) -> [AgentSuggestion] {
        let t = tabs.joined(separator: " ").lowercased()
        var out: [AgentSuggestion] = []
        func add(_ id: String, _ why: String) { if !hired.contains(id), agent(id) != nil, !out.contains(where: { $0.agent == id }) { out.append(AgentSuggestion(agent: id, reason: why)) } }
        if t.range(of: #"sales|revenue|payment|finance|report|invoice|payout|money|transactions|tax"#, options: .regularExpression) != nil { add("finance-financial-analyst", "your dashboard has sales and payments — it reports revenue, costs, tax and profit from them") }
        if t.range(of: #"calendar|booking|appointment|schedule|diary|visits?"#, options: .regularExpression) != nil { add("zuffi-bookings", "your dashboard has a calendar — it counts bookings, cancellations and no-shows") }
        if t.range(of: #"client|customer|contacts|members"#, options: .regularExpression) != nil { add("zuffi-crm", "your dashboard has a client list — it finds who to win back and who needs a follow-up") }
        if t.range(of: #"marketing|promotion|campaign|review|deals|offers"#, options: .regularExpression) != nil { add("marketing-social-media-strategist", "your dashboard has marketing and reviews — it plans posts and offers") }
        if t.range(of: #"products?|services?|menu|catalog|inventory|stock"#, options: .regularExpression) != nil { add("product-manager", "your dashboard lists services or products — it reviews your menu and prices") }
        add("zuffi-competitors", "every business benefits from a daily look at nearby competitors")
        return out
    }

    private static func match(_ t: String, _ pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        return (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: t).map { String(t[$0]) } ?? "" }
    }

    // MARK: Daily jobs

    private var jobRunning = Set<String>()

    /// Every half minute (from the business tick): run jobs that are due; mark missed ones honestly.
    func tickJobs() {
        guard teamsAllowed else { return }
        let now = Date(), cal = Calendar.current
        for job in jobs where job.enabled && !jobRunning.contains(job.id) {
            guard let due = cal.date(bySettingHour: job.hour, minute: job.minute, second: 0, of: now), now >= due else { continue }
            if let last = job.lastRun, last >= due { continue }
            if now.timeIntervalSince(due) > 3 * 3600 {
                // The Mac was off or asleep at that time.
                mark(job.id, JobRun(at: now, status: "Missed", summary: "Didn't run at \(String(format: "%02d:%02d", job.hour, job.minute)) — the Mac was off or asleep."))
                continue
            }
            Task { @MainActor in await self.runJob(job.id) }
        }
    }

    private func mark(_ id: String, _ run: JobRun) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].lastRun = run.at; jobs[i].lastStatus = run.status
        jobs[i].history.insert(run, at: 0)
        if jobs[i].history.count > 30 { jobs[i].history.removeLast(jobs[i].history.count - 30) }
    }

    func runJob(_ id: String) async {
        guard let job = jobs.first(where: { $0.id == id }), let a = agent(job.agent), !jobRunning.contains(id) else { return }
        if paused.contains(a.id) { mark(id, JobRun(status: "Skipped", summary: "\(a.name) is paused.")); return }
        jobRunning.insert(id); defer { jobRunning.remove(id) }
        let run = await work(a, job.task, job: job.title, readDashboard: job.readsDashboard)
        let status = run.status == "Done" ? "Done" : run.status == "Needs input" ? "Needs input" : "Failed"
        mark(id, JobRun(status: status, summary: String(run.result.prefix(300))))
        log(a.name, "Ran “\(job.title)”", status)
        let head = "\(a.emoji) \(job.title)" + (status == "Done" ? "" : status == "Needs input" ? " — needs you" : " — didn't work")
        MacStatus.shared.toast(head, String(run.result.prefix(160)), icon: AgentField.of(a).symbol)
        BizSync.shared.notify(title: head, body: String(run.result.prefix(300)))
    }
}

// MARK: - Real business data for agents (nothing here is ever guessed)

@MainActor
enum TeamData {
    /// The dates a question is about.
    static func period(_ q: String) -> (label: String, from: String, to: String) {
        let t = q.lowercased(), cal = Calendar.current, now = Date()
        func iso(_ d: Date) -> String { ZuffiBusiness.iso(d) }
        if t.contains("yesterday") { let y = now.addingTimeInterval(-86400); return ("yesterday", iso(y), iso(y)) }
        if t.contains("this week") || t.contains("week") {
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return ("this week", iso(start), iso(now))
        }
        if t.contains("last month") {
            let m = cal.date(byAdding: .month, value: -1, to: now) ?? now
            let i = cal.dateInterval(of: .month, for: m)
            return ("last month", iso(i?.start ?? m), iso((i?.end ?? m).addingTimeInterval(-1)))
        }
        if t.contains("month") { let start = cal.dateInterval(of: .month, for: now)?.start ?? now; return ("this month", iso(start), iso(now)) }
        return ("today", iso(now), iso(now))
    }

    static func money(_ v: Double) -> String { "\(ZuffiCRM.shared.currency)\(ZuffiCRM.shared.currency.count > 1 ? " " : "")\(ZuffiMoney.pretty(v))" }

    /// Today's (or the asked period's) dashboard figures of some kinds.
    static func dashboardFigures(_ kinds: Set<String>, since: Date) -> [(DataReading, DataFigure)] {
        var out: [(DataReading, DataFigure)] = []
        var seen = Set<String>()
        for r in ZuffiTeam.shared.readings where r.at >= since {
            for f in r.figures where kinds.contains(f.kind) && !seen.contains(f.label.lowercased()) {
                seen.insert(f.label.lowercased()); out.append((r, f))
            }
        }
        return out
    }

    /// "What's our profit today?" → from the Money page and the dashboard read today. (text, verified, sources used)
    static func financeAnswer(_ q: String) -> (String, Bool, [String]) {
        let p = period(q), m = ZuffiMoney.shared
        let es = m.entries.filter { $0.date >= p.from && $0.date <= p.to }
        let inc = es.filter { $0.type == "Income" }.reduce(0) { $0 + $1.amount }
        let exp = es.filter { $0.type != "Income" }.reduce(0) { $0 + $1.amount }
        let tax = es.filter { $0.category.lowercased().range(of: #"tax|vat"#, options: .regularExpression) != nil }.reduce(0) { $0 + $1.amount }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let dash = dashboardFigures(["revenue", "sales", "cost", "expenses", "tax", "profit"], since: p.label == "today" ? startOfDay : Date().addingTimeInterval(-31 * 86400))
        var lines: [String] = [], used: [String] = ["Money page (\(es.count) entr\(es.count == 1 ? "y" : "ies") \(p.label))"]
        if !es.isEmpty {
            lines.append("From your Money page, \(p.label):")
            lines.append("• Income: \(money(inc)) (actual, \(es.filter { $0.type == "Income" }.count) entries)")
            lines.append("• Expenses: \(money(exp)) (actual, \(es.filter { $0.type != "Income" }.count) entries)")
            if tax > 0 { lines.append("• Tax / VAT paid: \(money(tax)) (actual)") }
            lines.append("• Profit: \(money(inc - exp)) (calculated: income − expenses)")
        }
        if !dash.isEmpty {
            let src = dash[0].0
            used.append("\(src.source) dashboard (read \(ZuffiTeam.time(src.at)))")
            lines.append("From \(src.source), read from the screen at \(ZuffiTeam.time(src.at)):")
            for (_, f) in dash.prefix(8) { lines.append("• \(f.label): \(f.value)\(f.sure ? " (as shown)" : " (couldn't read clearly — please check)")") }
        }
        if es.isEmpty && dash.isEmpty {
            let has = !ZuffiTeam.shared.sources.isEmpty
            return ("I can't verify the profit for \(p.label) yet — there's no income or expenses recorded in Money for \(p.label)\(has ? ", and I haven't read your dashboard \(p.label)" : ""). I won't guess.\n\n"
                    + (has ? "Open your \(ZuffiTeam.shared.sources[0].name) sales or finance page and say “read my dashboard again”, " : "Open your booking or payments dashboard (e.g. Fresha) and say “this is my business dashboard”, ")
                    + "or tell me today's takings and costs (e.g. “income 450 haircuts”, “expense 60 supplies”).", false, used)
        }
        if es.isEmpty { lines.append("Nothing is recorded in Money for \(p.label), so costs from Money are missing — profit can't be fully verified from Money.") }
        return (lines.joined(separator: "\n"), true, used)
    }

    /// Bookings from the Appointments sheet, site visits, leads marked Booked, and the dashboard.
    static func bookingsAnswer(_ q: String) -> (String, Bool, [String]) {
        let p = period(q)
        let book = ZuffiPA.load("Appointments", header: ZuffiPA.apptHeader)
        let inRange = book.rows.filter { let d = book.get($0, ["date"]); return d >= p.from && d <= p.to }
        let cancelled = inRange.filter { book.get($0, ["status"]).lowercased().contains("cancel") }
        let noShow = inRange.filter { book.get($0, ["status"]).lowercased().replacingOccurrences(of: "-", with: " ").contains("no show") }
        let tomorrow = ZuffiBusiness.iso(Date().addingTimeInterval(86400))
        let tmr = book.rows.filter { book.get($0, ["date"]) == tomorrow }
        let visits = ZuffiCRM.shared.isEstate ? ZuffiProperties.shared.visits.filter { $0.date >= p.from && $0.date <= p.to } : []
        let dash = dashboardFigures(["bookings", "cancellations", "no_shows"], since: Calendar.current.startOfDay(for: Date()))
        var lines: [String] = [], used: [String] = ["Appointments sheet"]
        let hasSheet = !book.rows.isEmpty
        if hasSheet {
            lines.append("From your Appointments, \(p.label): \(inRange.count) booking\(inRange.count == 1 ? "" : "s")\(cancelled.isEmpty ? "" : ", \(cancelled.count) cancelled")\(noShow.isEmpty ? "" : ", \(noShow.count) no-show").")
            if p.label == "today" { lines.append("Tomorrow: \(tmr.count).") }
            for r in inRange.prefix(8) { lines.append("• \(book.get(r, ["time"])) \(book.get(r, ["client"])) — \(book.get(r, ["service"]))") }
        }
        if !visits.isEmpty { used.append("Site visits"); lines.append("Site visits \(p.label): \(visits.count).") }
        if !dash.isEmpty {
            let src = dash[0].0
            used.append("\(src.source) dashboard (read \(ZuffiTeam.time(src.at)))")
            lines.append("From \(src.source), read at \(ZuffiTeam.time(src.at)):")
            for (_, f) in dash.prefix(6) { lines.append("• \(f.label): \(f.value)\(f.sure ? "" : " (check)")") }
        }
        if lines.isEmpty {
            return ("I can't count the bookings for \(p.label) yet — there are no appointments in Zuffi and I haven't read your booking dashboard \(p.label). Open your calendar (e.g. Fresha) and say “this is my business dashboard”, or add bookings in Zuffi. I won't guess.", false, used)
        }
        return (lines.joined(separator: "\n"), true, used)
    }

    /// "Check my business inbox" / "how many messages" / "old messages" — straight from the inbox and WhatsApp contacts.
    static func inboxAnswer(_ q: String) -> String {
        let crm = ZuffiCRM.shared, book = WAContactBook.shared.list
        let today = ZuffiBusiness.iso(Date())
        let withMsg = crm.leads.filter { !$0.lastMessage.isEmpty }.sorted { $0.lastMessageAt > $1.lastMessageAt }
        let waiting = withMsg.filter { !$0.lastMessage.hasPrefix("You:") && $0.isOpen }
        let newToday = crm.leads.filter { $0.added == today }
        let old = q.contains("old") || q.contains("earlier") || q.contains("previous")
        let shown = old ? withMsg.filter { !$0.lastMessageAt.hasPrefix(today) } : withMsg
        var lines: [String] = []
        lines.append("Business inbox: \(withMsg.count) conversation\(withMsg.count == 1 ? "" : "s"), \(waiting.count) waiting for your reply, \(newToday.count) new today\(crm.drafts.isEmpty ? "" : ", \(crm.drafts.count) suggested repl\(crm.drafts.count == 1 ? "y" : "ies") ready to send").")
        if !book.isEmpty { lines.append("WhatsApp contacts saved: \(book.count) (\(book.filter { Calendar.current.isDateInToday($0.first) }.count) new today).") }
        if shown.isEmpty { lines.append(old ? "No older messages." : "No messages yet.") }
        for l in shown.prefix(6) {
            let when = l.lastMessageAt.count >= 16 ? String(l.lastMessageAt.prefix(16)).replacingOccurrences(of: "T", with: " ") : l.lastMessageAt
            lines.append("• \(l.display) — “\(l.lastMessage.prefix(70))” (\(when))\(waiting.contains(l) ? " · needs a reply" : "")")
        }
        if !waiting.isEmpty { lines.append("Open Business → Inbox to answer, or say “reply to \(waiting[0].display.split(separator: " ").first ?? "") …”.") }
        return lines.joined(separator: "\n")
    }

    /// The real data an agent's tools allow, as text for the AI, with the sources used.
    static func block(for tools: [AgentTool], question: String) -> (text: String, sources: [String]) {
        var parts: [String] = [], used: [String] = []
        if tools.contains(.money) {
            let (t, ok, _) = financeAnswer(question.isEmpty ? "this month" : question)
            let month = financeAnswer("this month")
            parts.append("MONEY:\n" + (ok ? t : "No money data for this question.") + (month.1 ? "\nThis month so far:\n" + month.0 : ""))
            used.append("Money page")
        }
        if tools.contains(.bookings) {
            let (t, ok, _) = bookingsAnswer(question)
            parts.append("BOOKINGS:\n" + (ok ? t : "No bookings data.")); used.append("Bookings")
        }
        if tools.contains(.customers) {
            let crm = ZuffiCRM.shared
            let leads = crm.leads
            if !leads.isEmpty {
                let byStage = Dictionary(grouping: leads, by: \.stage).map { "\($0.key): \($0.value.count)" }.sorted().joined(separator: ", ")
                let due = leads.filter(\.dueToday).prefix(10).map(\.display).joined(separator: ", ")
                let recent = leads.sorted { $0.added > $1.added }.prefix(10).map { "\($0.display) (\($0.stage), added \($0.added))" }.joined(separator: "; ")
                parts.append("CUSTOMERS / LEADS: \(leads.count) total. By stage: \(byStage).\(due.isEmpty ? "" : " Follow up today: \(due).") Newest: \(recent).")
            } else { parts.append("CUSTOMERS / LEADS: none recorded yet.") }
            used.append("Customers & leads")
        }
        if tools.contains(.contacts) {
            let c = WAContactBook.shared.list
            if !c.isEmpty {
                let new = c.filter { $0.count == 1 }.count
                parts.append("WHATSAPP CONTACTS: \(c.count) saved (\(new) new, \(c.count - new) returning). Latest: " + c.prefix(10).map { "\($0.displayName) — last \($0.last.formatted(date: .abbreviated, time: .shortened)): \($0.history.last?.text.prefix(60) ?? "")" }.joined(separator: "; "))
                used.append("WhatsApp contacts")
            }
        }
        if tools.contains(.dashboard), let r = ZuffiTeam.shared.readings.first {
            parts.append("BUSINESS DASHBOARD (\(r.source) · \(r.page), read \(r.at.formatted(date: .abbreviated, time: .shortened))):\n" + ZuffiTeam.figuresText(r))
            used.append("\(r.source) dashboard")
        }
        return (parts.joined(separator: "\n\n"), used)
    }
}

// MARK: - Agent looks (each field its own colour and symbol)

struct AgentAvatar: View {
    let agent: TeamAgent
    var size: CGFloat = 40
    var status: ZuffiTeam.Status? = nil
    var body: some View {
        let f = AgentField.of(agent)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(f.gradient)
            Image(systemName: f.symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundColor(.white.opacity(0.95))
            Text(agent.emoji).font(.system(size: size * 0.34))
                .frame(width: size * 0.5, height: size * 0.5)
                .background(Circle().fill(Color.black.opacity(0.35)))
                .offset(x: size * 0.34, y: size * 0.34)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if let status { Circle().fill(ZuffiTeam.color(status)).frame(width: size * 0.24, height: size * 0.24).overlay(Circle().stroke(Ink.panel, lineWidth: 2)).offset(x: 3, y: -3) }
        }
        .shadow(color: f.color.opacity(0.35), radius: 6, y: 3)
    }
}

struct FieldChip: View {
    let field: AgentField
    var body: some View {
        Label(field.label, systemImage: field.symbol).font(.system(size: 10, weight: .bold)).foregroundColor(field.color)
            .padding(.horizontal, 7).frame(height: 20).background(Capsule().fill(field.color.opacity(0.14))).lineLimit(1).fixedSize()
    }
}

struct AgentStatusPill: View {
    let status: ZuffiTeam.Status
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(ZuffiTeam.color(status)).frame(width: 7, height: 7)
            Text(status.rawValue).font(.system(size: 10.5, weight: .semibold)).foregroundColor(ZuffiTeam.color(status)).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8).frame(height: 21).background(Capsule().fill(ZuffiTeam.color(status).opacity(0.13)))
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
                    Section("Your team — pick several") {
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
                Text("\(team.everyone.count) specialists — finance, bookings, customers, sales, marketing, research and more. Pick one and it answers as that person, from your real business data. Say “back to normal” to stop. With Business you hire your own team on Business → My Team.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Text("Talking to:"); Text(team.activeAgents.isEmpty ? "Plain Zuffi" : team.activeAgents.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ")).bold().lineLimit(2); Spacer()
                    if !team.activeIDs.isEmpty { Button("Stop") { team.use(nil) }.controlSize(.small) } }
                TextField("Search the team…", text: $search).textFieldStyle(.roundedBorder)
                if !search.isEmpty {
                    let hits = team.everyone.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }.prefix(12)
                    ForEach(Array(hits)) { a in
                        HStack {
                            AgentAvatar(agent: a, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(.system(size: 12, weight: .semibold))
                                Text(a.description).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Button(team.activeIDs.contains(a.id) ? "In use" : "Use") { team.use(a) }.controlSize(.small).disabled(team.activeIDs.contains(a.id))
                        }
                    }
                }
                Text("Specialists from “agency-agents” (MIT licence).").font(.system(size: 9.5)).foregroundColor(.secondary)
            }.padding(6)
        }
    }
}

// MARK: - Business → My Team

struct BizAITeamView: View {
    enum TeamTab: String, CaseIterable { case team = "Team", jobs = "Daily jobs", activity = "Activity", hire = "Hire" }
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var stage = AgentStage.shared
    @State private var section: TeamTab = .team
    @State private var openAgent: TeamAgent?
    @State private var assignTo: TeamAgent?
    @State private var ask = ""
    @State private var busy = false
    @State private var lastAnswer = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stats
                HStack(spacing: 6) {
                    ForEach(TeamTab.allCases, id: \.self) { s in
                        Button { section = s } label: {
                            Text(s.rawValue + (s == .team ? " (\(team.hiredAgents.count))" : s == .jobs ? " (\(team.jobs.count))" : ""))
                                .font(.system(size: 12, weight: section == s ? .semibold : .regular)).foregroundColor(section == s ? .white : Ink.text)
                                .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(section == s ? Ink.accent : Ink.panelHi))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    if !team.working.isEmpty { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(team.working).font(.system(size: 11)).foregroundColor(Ink.muted).lineLimit(1) } }
                    Toggle("Show agents on screen", isOn: $stage.enabled).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
                }
                if !team.suggestions.isEmpty { suggestionsBox }
                switch section {
                case .team: teamSection
                case .jobs: TeamJobsView()
                case .activity: TeamActivityView()
                case .hire: TeamHireView()
                }
            }
            .padding(22)
        }
        .sheet(item: $openAgent) { a in AgentDetailView(agent: a).frame(minWidth: 640, minHeight: 560) }
        .sheet(item: $assignTo) { a in AssignSheet(agent: a) }
    }

    private var stats: some View {
        let working = team.hiredAgents.filter { team.status($0) == .working }.count
        let need = team.hiredAgents.filter { [.waiting, .attention].contains(team.status($0)) }.count
        let today = Calendar.current.startOfDay(for: Date())
        return HStack(spacing: 12) {
            stat("Team", "\(team.hiredAgents.count)", "person.3.fill", "#5B6CFF")
            stat("Working now", "\(working)", "bolt.fill", "#F2A516")
            stat("Done today", "\(team.runs.filter { $0.status == "Done" && $0.started >= today }.count)", "checkmark.seal.fill", "#16C47F")
            stat("Need you", "\(need)", "exclamationmark.bubble.fill", "#EF6B6B")
        }
    }

    private func stat(_ label: String, _ value: String, _ icon: String, _ tint: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.4).foregroundColor(Ink.faint).lineLimit(1)
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundColor(Ink.text)
            }
            Spacer(minLength: 4)
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
                .frame(width: 40, height: 40).background(Circle().fill(Color(hex: tint).gradient))
        }
        .padding(14).frame(maxWidth: .infinity).zGlass(14)
    }

    private var suggestionsBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Suggested for your business", systemImage: "sparkles").font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                Button("Hire all") { for s in team.suggestions { if let a = team.agent(s.agent) { team.hire(a, why: s.reason) } } }
                    .buttonStyle(.borderedProminent).tint(Ink.accent).controlSize(.small)
                Button("Not now") { team.suggestions = [] }.controlSize(.small)
            }
            ForEach(team.suggestions) { s in
                if let a = team.agent(s.agent) {
                    HStack(alignment: .top, spacing: 10) {
                        AgentAvatar(agent: a, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.name).font(.system(size: 12.5, weight: .semibold))
                            Text("Why: \(s.reason)").font(.system(size: 11)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                            if let j = team.defaultJob(for: a) { Text("Will do: \(j.title) every day at \(String(format: "%02d:%02d", j.hour, j.minute))").font(.system(size: 10.5)).foregroundColor(Ink.faint) }
                        }
                        Spacer()
                        Button("Hire") { team.hire(a, why: s.reason) }.controlSize(.small)
                    }
                }
            }
        }
        .padding(16).zGlass(16)
    }

    @AppStorage("teamReviewed") private var reviewed = false
    @State private var confirmClear = false

    @ViewBuilder private var teamSection: some View {
        if !team.hiredAgents.isEmpty && !reviewed {
            HStack(spacing: 12) {
                Image(systemName: "person.3.sequence.fill").font(.system(size: 18)).foregroundColor(Ink.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You have \(team.hiredAgents.count) agents from before").font(.system(size: 13, weight: .bold))
                    Text(team.hiredAgents.map(\.name).joined(separator: ", ")).font(.system(size: 11)).foregroundColor(Ink.muted).lineLimit(2)
                }
                Spacer()
                Button("Keep them") { reviewed = true }.controlSize(.small)
                Button("Start fresh") { team.startFresh(); reviewed = true }.buttonStyle(.borderedProminent).tint(Ink.accent).controlSize(.small)
            }
            .padding(14).zGlass(14)
        }
        // Ask the team
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentAvatar(agent: ZuffiTeam.manager, size: 34)
                TextField("Ask your team — e.g. “What's our profit today?” · “Why are competitors busier?”", text: $ask)
                    .textFieldStyle(.plain).font(.system(size: 13))
                    .padding(.horizontal, 12).frame(height: 36).background(RoundedRectangle(cornerRadius: 10).fill(Ink.panelHi)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Ink.line))
                    .onSubmit(send)
                Button(action: send) {
                    Label("Ask", systemImage: "paperplane.fill").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                        .padding(.horizontal, 14).frame(height: 36).background(RoundedRectangle(cornerRadius: 10).fill(Ink.accent))
                }.buttonStyle(.plain).disabled(busy || ask.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("The Team Manager sends it only to the people who should answer. Money and booking figures come from your Money page, bookings and your dashboard — never guessed.")
                .font(.system(size: 10.5)).foregroundColor(Ink.faint)
            if !lastAnswer.isEmpty {
                Text(lastAnswer).font(.system(size: 12)).foregroundColor(Ink.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi))
            }
        }
        .padding(16).zGlass(16)

        if team.hiredAgents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Build your AI team").font(.system(size: 17, weight: .bold, design: .rounded))
                Text("Hire specialists who work on your business every day. Open your booking or payments dashboard and say “this is my business dashboard” — Zuffi reads it and suggests the right people. Or start with a ready team.")
                    .font(.system(size: 12)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button { team.starterTeam.compactMap(team.agent).forEach { team.hire($0, why: "Starter team") } } label: {
                        Label("Hire a starter team", systemImage: "sparkles").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                            .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(Ink.accent))
                    }.buttonStyle(.plain)
                    Button { Task { @MainActor in lastAnswer = await team.connectDashboard() } } label: {
                        Label("Read my dashboard on screen", systemImage: "rectangle.on.rectangle.angled").font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 32).inkPanel(Capsule(), interactive: true)
                    }.buttonStyle(.plain)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).zGlass(18)
        } else {
            HStack {
                Text("Your team (\(team.hiredAgents.count))").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Button("Remove all") { confirmClear = true }.buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#EF6B6B"))
            }
            .confirmationDialog("Remove all \(team.hiredAgents.count) agents and their daily jobs?", isPresented: $confirmClear) {
                Button("Remove all", role: .destructive) { team.startFresh() }
            } message: { Text("Their past work stays in Activity. You can hire again any time.") }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 14)], spacing: 14) {
                AgentCard(agent: ZuffiTeam.manager, lead: true, open: { openAgent = ZuffiTeam.manager }, assign: { section = .team })
                ForEach(team.hiredAgents) { a in AgentCard(agent: a, open: { openAgent = a }, assign: { assignTo = a }) }
            }
        }
    }

    private func send() {
        let q = ask.trimmingCharacters(in: .whitespacesAndNewlines); guard !q.isEmpty else { return }
        busy = true; lastAnswer = ""
        Task { @MainActor in
            let people = team.hiredAgents.isEmpty ? team.starterTeam.compactMap(team.agent) : team.hiredAgents
            lastAnswer = await team.answer(q, people: people, routeOnly: true)
            busy = false; ask = ""
        }
    }
}

/// One hired agent: who, status, what it's doing, data it uses, last results, controls.
struct AgentCard: View {
    let agent: TeamAgent
    var lead = false
    let open: () -> Void
    let assign: () -> Void
    @ObservedObject private var team = ZuffiTeam.shared

    var body: some View {
        let f = AgentField.of(agent), st = team.status(agent)
        let cur = team.current(agent), last = team.lastRun(agent), ok = team.lastSuccess(agent)
        VStack(alignment: .leading, spacing: 0) {
            // header in the field's colours
            HStack(spacing: 12) {
                AgentAvatar(agent: agent, size: 46, status: st)
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name).font(.system(size: 14, weight: .bold)).foregroundColor(Ink.text).lineLimit(1)
                    HStack(spacing: 6) { FieldChip(field: f); if lead { Text("LEADS").font(.system(size: 8.5, weight: .heavy)).foregroundColor(Ink.accent) } }
                }
                Spacer(minLength: 4)
                AgentStatusPill(status: st)
            }
            .padding(14)
            .background(LinearGradient(colors: [f.color.opacity(Ink.dark ? 0.22 : 0.14), .clear], startPoint: .top, endPoint: .bottom))
            VStack(alignment: .leading, spacing: 8) {
                Text(agent.description).font(.system(size: 11.5)).foregroundColor(Ink.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                row("bolt.fill", cur.map { "Now: \($0.task)" } ?? (st == .offline ? "Paused" : "Not working on anything right now"))
                if !f.tools.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(f.tools, id: \.self) { t in
                            Label(t.label, systemImage: t.symbol).font(.system(size: 9.5, weight: .medium)).foregroundColor(Ink.muted)
                                .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(Ink.panelHi)).lineLimit(1).fixedSize()
                        }
                    }
                }
                if let last { row("clock", "Last activity \(last.started.formatted(.relative(presentation: .named)))" + (ok.map { " · last success \($0.started.formatted(.relative(presentation: .named)))" } ?? "")) }
                if let last, last.status != "Working" {
                    Text(last.result).font(.system(size: 11)).foregroundColor(last.status == "Done" ? Ink.text : ZuffiTeam.color(st)).lineLimit(3)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Ink.panelHi))
                }
                if let j = team.jobs.first(where: { $0.agent == agent.id }) {
                    row("calendar.badge.clock", "\(j.title) · daily \(String(format: "%02d:%02d", j.hour, j.minute))\(j.enabled ? "" : " (off)")\(j.lastStatus.isEmpty ? "" : " · last: \(j.lastStatus)")")
                }
                HStack(spacing: 8) {
                    Button("Open", action: open)
                    if !lead {
                        Button("Assign task", action: assign)
                        Button(st == .offline ? "Resume" : "Pause") { team.setPaused(agent, st != .offline) }
                        Spacer()
                        Menu { Button("Remove from team", role: .destructive) { team.fire(agent) } } label: { Image(systemName: "ellipsis") }
                            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    } else { Spacer() }
                }
                .buttonStyle(.plain).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Ink.accent).padding(.top, 2)
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Ink.panel))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(f.color.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Ink.shadow, radius: 8, y: 3)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(Ink.faint).frame(width: 14)
            Text(text).font(.system(size: 11)).foregroundColor(Ink.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Give one agent a task now.
struct AssignSheet: View {
    let agent: TeamAgent
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var task = ""
    @State private var readDash = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) { AgentAvatar(agent: agent, size: 36); Text("Assign a task to \(agent.name)").font(.system(size: 15, weight: .bold)) }
            TextField("What should \(agent.name) do?", text: $task, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(2...5)
            if AgentField.of(agent).tools.contains(.dashboard), !team.sources.isEmpty {
                Toggle("Read \(team.sources[0].name) on screen first", isOn: $readDash).toggleStyle(.checkbox)
            }
            Text("You'll see each step on the agent's page. It reads and writes only — anything that sends, posts or pays waits for you.").font(.system(size: 11)).foregroundColor(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Assign") {
                    let t = task.trimmingCharacters(in: .whitespacesAndNewlines); guard !t.isEmpty else { return }
                    team.log("You", "Assigned a task to \(agent.name)", t)
                    let a = agent, rd = readDash
                    Task { @MainActor in await team.work(a, t, readDashboard: rd) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Ink.accent)
            }
        }
        .padding(20).frame(width: 460)
    }
}

/// How an agent works: its runs with steps, sources and results; its job; settings.
struct AgentDetailView: View {
    let agent: TeamAgent
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var open: String?

    var body: some View {
        let f = AgentField.of(agent)
        let mine = team.runs.filter { $0.agent == agent.id }
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                AgentAvatar(agent: agent, size: 56, status: team.status(agent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(agent.name).font(.system(size: 20, weight: .bold, design: .rounded))
                    HStack(spacing: 6) { FieldChip(field: f); AgentStatusPill(status: team.status(agent)) }
                    Text(agent.description).font(.system(size: 11.5)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(20).background(f.gradient.opacity(0.18))
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !f.tools.isEmpty {
                        Text("Data it can use: " + f.tools.map(\.label).joined(separator: " · ")).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    if let j = team.jobs.first(where: { $0.agent == agent.id }) { JobRow(job: j) }
                    else if let j = team.defaultJob(for: agent), team.hired.contains(agent.id) {
                        Button("Add daily job: \(j.title)") { team.jobs.append(j) }.controlSize(.small)
                    }
                    Text("Work").font(.system(size: 14, weight: .bold))
                    if mine.isEmpty { Text("No work yet. Assign a task or ask the team a question.").font(.system(size: 12)).foregroundColor(.secondary) }
                    ForEach(mine.prefix(40)) { r in runRow(r) }
                }
                .padding(20)
            }
        }
    }

    private func runRow(_ r: AgentRun) -> some View {
        let color: Color = r.status == "Done" ? Color(hex: "#3FC48C") : r.status == "Working" ? Color(hex: "#F2A516") : r.status == "Needs input" ? Color(hex: "#6EA8F7") : Color(hex: "#EF6B6B")
        return VStack(alignment: .leading, spacing: 8) {
            Button { open = open == r.id ? nil : r.id } label: {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(r.job.map { "Daily job · \($0)" } ?? r.task).font(.system(size: 12.5, weight: .semibold)).lineLimit(open == r.id ? nil : 1)
                    Spacer()
                    Text(r.status).font(.system(size: 10.5, weight: .bold)).foregroundColor(color)
                    Text(r.started.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10.5)).foregroundColor(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open == r.id {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(r.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .top, spacing: 6) {
                            Text("\(i + 1).").font(.system(size: 10.5, weight: .bold)).foregroundColor(.secondary).frame(width: 18, alignment: .trailing)
                            Text(s.text).font(.system(size: 11))
                            Spacer()
                            Text(s.at.formatted(date: .omitted, time: .standard)).font(.system(size: 9.5)).foregroundColor(.secondary)
                        }
                    }
                    if !r.sources.isEmpty { Text("Sources: " + r.sources.joined(separator: " · ")).font(.system(size: 10.5)).foregroundColor(.secondary).padding(.top, 2) }
                    if !r.result.isEmpty {
                        Text(r.result).font(.system(size: 11.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                    }
                }.padding(.leading, 16)
            }
        }
        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
    }
}

struct JobRow: View {
    let job: TeamJob
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var showHistory = false
    var body: some View {
        let a = team.agent(job.agent)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let a { AgentAvatar(agent: a, size: 30) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.title).font(.system(size: 12.5, weight: .semibold))
                    Text("\(a?.name ?? job.agent) · every day\(job.readsDashboard ? " · reads \(team.sources.first?.name ?? "your dashboard")" : "")").font(.system(size: 10.5)).foregroundColor(Ink.faint)
                }
                Spacer()
                DatePicker("", selection: Binding(get: {
                    Calendar.current.date(bySettingHour: job.hour, minute: job.minute, second: 0, of: Date()) ?? Date()
                }, set: { d in
                    if let i = team.jobs.firstIndex(where: { $0.id == job.id }) {
                        team.jobs[i].hour = Calendar.current.component(.hour, from: d); team.jobs[i].minute = Calendar.current.component(.minute, from: d)
                    }
                }), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 90)
                Toggle("", isOn: Binding(get: { job.enabled }, set: { v in if let i = team.jobs.firstIndex(where: { $0.id == job.id }) { team.jobs[i].enabled = v } }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
                Button("Run now") { Task { @MainActor in await team.runJob(job.id) } }.controlSize(.small)
            }
            HStack(spacing: 8) {
                if job.lastStatus.isEmpty { Text("Hasn't run yet").font(.system(size: 10.5)).foregroundColor(Ink.faint) }
                else { StatusDot(text: "Last run: \(job.lastStatus)\(job.lastRun.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "")",
                                 color: job.lastStatus == "Done" ? Color(hex: "#3FC48C") : job.lastStatus == "Missed" || job.lastStatus == "Skipped" ? Color(hex: "#8A92A4") : Color(hex: "#EF6B6B")) }
                if job.readsDashboard { Text("Keep \(team.sources.first?.name ?? "the dashboard") open and the Mac awake at this time.").font(.system(size: 10)).foregroundColor(Ink.faint) }
                Spacer()
                if !job.history.isEmpty { Button(showHistory ? "Hide history" : "History (\(job.history.count))") { showHistory.toggle() }.buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Ink.accent) }
            }
            if showHistory {
                ForEach(Array(job.history.prefix(10).enumerated()), id: \.offset) { _, h in
                    HStack(alignment: .top) {
                        Text(h.at.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundColor(Ink.faint).frame(width: 120, alignment: .leading)
                        Text(h.status).font(.system(size: 10, weight: .bold)).frame(width: 80, alignment: .leading)
                        Text(h.summary).font(.system(size: 10.5)).foregroundColor(Ink.muted).lineLimit(2)
                    }
                }
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi.opacity(0.7)))
    }
}

struct TeamJobsView: View {
    @ObservedObject private var team = ZuffiTeam.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily jobs").font(.system(size: 15, weight: .bold, design: .rounded))
            Text("Each job runs on this Mac at its time and sends the result to your phone (Business → Connect & devices). If the Mac is off or the dashboard isn't open, the job shows as missed — it never pretends it ran.")
                .font(.system(size: 11)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
            if team.jobs.isEmpty { Text("No jobs yet — hiring an agent adds its everyday job.").font(.system(size: 12)).foregroundColor(Ink.faint) }
            ForEach(team.jobs) { j in JobRow(job: j) }
        }
        .padding(16).zGlass(16)
    }
}

struct TeamActivityView: View {
    @ObservedObject private var team = ZuffiTeam.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent work").font(.system(size: 15, weight: .bold, design: .rounded))
                if team.runs.isEmpty { Text("Nothing yet.").font(.system(size: 12)).foregroundColor(Ink.faint) }
                ForEach(team.runs.prefix(30)) { r in
                    HStack(spacing: 8) {
                        if let a = team.agent(r.agent) { AgentAvatar(agent: a, size: 24) }
                        Text(team.agent(r.agent)?.name ?? r.agent).font(.system(size: 11.5, weight: .semibold)).frame(width: 170, alignment: .leading).lineLimit(1)
                        Text(r.job ?? r.task).font(.system(size: 11.5)).foregroundColor(Ink.muted).lineLimit(1)
                        Spacer()
                        StatusDot(text: r.status, color: r.status == "Done" ? Color(hex: "#3FC48C") : r.status == "Working" ? Color(hex: "#F2A516") : r.status == "Needs input" ? Color(hex: "#6EA8F7") : Color(hex: "#EF6B6B"))
                        Text(r.started.formatted(.relative(presentation: .named))).font(.system(size: 10.5)).foregroundColor(Ink.faint).frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 3)
                }
            }
            .padding(16).zGlass(16)
            VStack(alignment: .leading, spacing: 6) {
                Text("Audit log").font(.system(size: 15, weight: .bold, design: .rounded))
                Text("Hiring, jobs, dashboard reads and anything sent — who did what, and when.").font(.system(size: 11)).foregroundColor(Ink.muted)
                if team.audit.isEmpty { Text("Nothing yet.").font(.system(size: 12)).foregroundColor(Ink.faint) }
                ForEach(team.audit.prefix(60)) { e in
                    HStack(alignment: .top, spacing: 8) {
                        Text(e.at.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10.5)).foregroundColor(Ink.faint).frame(width: 130, alignment: .leading)
                        Text(e.who).font(.system(size: 11, weight: .semibold)).frame(width: 150, alignment: .leading).lineLimit(1)
                        Text(e.action + (e.detail.isEmpty ? "" : " — \(e.detail)")).font(.system(size: 11)).foregroundColor(Ink.muted).lineLimit(2)
                        Spacer()
                    }
                }
            }
            .padding(16).zGlass(16)
        }
    }
}

struct TeamHireView: View {
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var search = ""
    @State private var division = "business"
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Hire specialists").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Toggle("Auto-hire from my dashboard", isOn: $team.autoHire).toggleStyle(.switch).controlSize(.small)
                    .help("When you show Zuffi your business dashboard, it hires the suggested agents by itself.")
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(Ink.faint)
                    TextField("Search \(team.everyone.count) specialists…", text: $search).textFieldStyle(.plain).frame(width: 200)
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
                : team.everyone.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)], spacing: 10) {
                ForEach(list.prefix(80)) { a in
                    let have = team.hired.contains(a.id)
                    HStack(alignment: .top, spacing: 10) {
                        AgentAvatar(agent: a, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.name).font(.system(size: 12.5, weight: .semibold)).foregroundColor(Ink.text)
                            FieldChip(field: AgentField.of(a))
                            Text(a.description).font(.system(size: 10.5)).foregroundColor(Ink.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Button { if have { team.fire(a) } else { team.hire(a) } } label: {
                            Text(have ? "Hired ✓" : "Hire").font(.system(size: 10.5, weight: .bold)).foregroundColor(have ? Ink.muted : .white)
                                .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(have ? Ink.panelHi : AgentField.of(a).color))
                        }.buttonStyle(.plain)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi.opacity(0.6)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(AgentField.of(a).color.opacity(have ? 0.6 : 0.15)))
                }
            }
        }
        .padding(16).zGlass(16)
    }
}

// MARK: - Business → Data sources (dashboards Zuffi reads from the screen)

struct BizDataSourcesView: View {
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your business dashboards").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Open your booking, payments or sales dashboard (Fresha, Square, your bank…), logged in, and keep it in front. Zuffi reads it from the screen — no API or password needed. Screenshots are sent to the AI to read the numbers; your passwords are never seen or stored.")
                        .font(.system(size: 12)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button {
                            busy = true
                            Task { @MainActor in message = await team.connectDashboard(); busy = false }
                        } label: {
                            Label(busy ? "Reading…" : "This is my business dashboard", systemImage: "rectangle.on.rectangle.angled").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                                .padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(Ink.accent))
                        }.buttonStyle(.plain).disabled(busy)
                        Toggle("Agents may click between its tabs (never change anything)", isOn: $team.clickTabs).toggleStyle(.checkbox).font(.system(size: 11.5))
                    }
                    if !message.isEmpty {
                        Text(message).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi))
                    }
                }
                .padding(18).zGlass(18)
                ForEach(team.sources) { s in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "rectangle.on.rectangle.angled").foregroundColor(.white).frame(width: 34, height: 34).background(Circle().fill(Color(hex: "#4C5BD4").gradient))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.system(size: 14, weight: .bold))
                                Text("Connected \(s.added.formatted(date: .abbreviated, time: .omitted))\(s.lastRead.map { " · last read " + $0.formatted(.relative(presentation: .named)) } ?? "")").font(.system(size: 10.5)).foregroundColor(Ink.faint)
                            }
                            Spacer()
                            Button("Read now") { Task { @MainActor in let (r, e) = await team.readDashboard(for: nil, tab: nil); message = r.map { "Read \($0.source) (\($0.page)):\n" + ZuffiTeam.figuresText($0) } ?? e } }.controlSize(.small)
                            Button("Remove") { team.sources.removeAll { $0.id == s.id }; team.log("You", "Removed \(s.name)") }.controlSize(.small)
                        }
                        if !s.tabs.isEmpty { Text("Sections seen: " + s.tabs.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(Ink.muted) }
                    }
                    .padding(16).zGlass(16)
                }
                if !team.readings.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Latest readings").font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("Exactly as read from the screen. Figures marked “check” weren't clear and are never used as verified numbers.").font(.system(size: 11)).foregroundColor(Ink.muted)
                        ForEach(team.readings.prefix(8)) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(r.source) · \(r.page) · \(r.at.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11.5, weight: .semibold))
                                if r.figures.isEmpty { Text("No figures on that page.").font(.system(size: 11)).foregroundColor(Ink.faint) }
                                ForEach(Array(r.figures.prefix(12).enumerated()), id: \.offset) { _, f in
                                    HStack {
                                        Text(f.label).font(.system(size: 11)).foregroundColor(Ink.muted)
                                        Spacer()
                                        Text(f.value).font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                                        if !f.sure { Text("check").font(.system(size: 9.5, weight: .bold)).foregroundColor(Color(hex: "#EF6B6B")) }
                                    }
                                }
                            }
                            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Ink.panelHi.opacity(0.7)))
                        }
                    }
                    .padding(16).zGlass(16)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - Business → Reports (daily job results)

struct BizReportsView: View {
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var crm = ZuffiCRM.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Today's summary").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(crm.summary()).font(.system(size: 12)).foregroundColor(Ink.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading).zGlass(16)
                let reports = team.runs.filter { $0.job != nil }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reports from your team").font(.system(size: 15, weight: .bold, design: .rounded))
                    if reports.isEmpty { Text("Daily jobs put their results here. Hire agents on My Team — each one gets an everyday job.").font(.system(size: 12)).foregroundColor(Ink.faint) }
                    ForEach(reports.prefix(40)) { r in
                        HStack(alignment: .top, spacing: 10) {
                            if let a = team.agent(r.agent) { AgentAvatar(agent: a, size: 30) }
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(r.job ?? "").font(.system(size: 12.5, weight: .semibold))
                                    Text(team.agent(r.agent)?.name ?? "").font(.system(size: 11)).foregroundColor(Ink.faint)
                                    Spacer()
                                    Text(r.started.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10.5)).foregroundColor(Ink.faint)
                                }
                                Text(r.result).font(.system(size: 11.5)).foregroundColor(r.status == "Done" ? Ink.text : Color(hex: "#EF6B6B")).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Ink.panelHi.opacity(0.7)))
                    }
                }
                .padding(16).zGlass(16)
            }
            .padding(22)
        }
    }
}

// MARK: - Agents on screen: small robots at the bottom of the screen while they work
//
// Each field has its own look (colour, hat, what it holds). They pop up when a job starts, show what they're doing
// step by step, then show the result with its links. Original drawings — no outside characters.

@MainActor
final class AgentStage: ObservableObject {
    static let shared = AgentStage()
    @Published var showing: [String] = []          // run ids on screen
    @Published var enabled: Bool = UserDefaults.standard.object(forKey: "agentsOnScreen") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "agentsOnScreen"); if !enabled { showing = []; layout() } }
    }
    private var panel: NSPanel?
    private var watch: AnyCancellable?
    private var hideAt: [String: Date] = [:]
    private var timer: Timer?

    private init() {
        watch = ZuffiTeam.shared.$runs.receive(on: RunLoop.main).sink { runs in
            MainActor.assumeIsolated { AgentStage.shared.update(runs) }
        }
    }
    /// Call once at start-up.
    func start() { _ = watch }

    private func update(_ runs: [AgentRun]) {
        guard enabled else { return }
        let now = Date()
        for r in runs.prefix(40) where r.agent != ZuffiTeam.manager.id {
            if r.status == "Working", !showing.contains(r.id), now.timeIntervalSince(r.started) < 600 { showing.append(r.id) }
            if r.status != "Working", showing.contains(r.id), hideAt[r.id] == nil { hideAt[r.id] = now.addingTimeInterval(40) }   // result stays 40 s
        }
        showing = Array(showing.suffix(5))
        layout()
        if timer == nil, !showing.isEmpty {
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in MainActor.assumeIsolated { AgentStage.shared.sweep() } }
        }
    }
    private func sweep() {
        let now = Date()
        let gone = hideAt.filter { $0.value < now }.map(\.key)
        if !gone.isEmpty { showing.removeAll { gone.contains($0) }; gone.forEach { hideAt[$0] = nil }; layout() }
        if showing.isEmpty { timer?.invalidate(); timer = nil }
    }
    func dismiss(_ id: String) { showing.removeAll { $0 == id }; hideAt[id] = nil; layout() }
    func keep(_ id: String) { hideAt[id] = Date().addingTimeInterval(600) }

    private func layout() {
        guard !showing.isEmpty else { panel?.orderOut(nil); return }
        let size = NSSize(width: CGFloat(showing.count) * 196 + 24, height: 300)
        let p = panel ?? make()
        panel = p
        let vf = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        // bottom of the screen, left of where the pet sits
        p.setFrame(NSRect(x: vf.minX + 24, y: vf.minY + 6, width: size.width, height: size.height), display: true)
        if !p.isVisible { p.alphaValue = 0; p.orderFrontRegardless(); NSAnimationContext.runAnimationGroup { $0.duration = 0.25; p.animator().alphaValue = 1 } }
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.contentView = FirstMouseHostingView(rootView: AgentStageView())
        return p
    }

    /// Opens one agent's page (steps, sources, results) in a small window.
    private var detail: NSWindow?
    func open(_ agent: TeamAgent) {
        let w = detail ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 600), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = agent.name; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: AgentDetailView(agent: agent))
        if detail == nil { w.center() }
        detail = w
        w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct AgentStageView: View {
    @ObservedObject private var stage = AgentStage.shared
    @ObservedObject private var team = ZuffiTeam.shared
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(stage.showing, id: \.self) { id in
                if let r = team.runs.first(where: { $0.id == id }), let a = team.agent(r.agent) {
                    AgentBuddyCard(run: r, agent: a).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: stage.showing)
    }
}

/// One agent at work: speech bubble with what it's doing, the robot, its name.
struct AgentBuddyCard: View {
    let run: AgentRun
    let agent: TeamAgent
    @State private var hover = false
    var body: some View {
        let f = AgentField.of(agent), working = run.status == "Working"
        let color: Color = run.status == "Done" ? Color(hex: "#3FC48C") : working ? f.color : run.status == "Needs input" ? Color(hex: "#6EA8F7") : Color(hex: "#EF6B6B")
        VStack(spacing: 4) {
            // bubble
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    if working { ProgressView().controlSize(.mini).tint(.white) } else { Image(systemName: run.status == "Done" ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundColor(color) }
                    Text(working ? "Working…" : run.status == "Done" ? "Done" : run.status).font(.system(size: 10, weight: .bold)).foregroundColor(color)
                    Spacer(minLength: 0)
                    Button { AgentStage.shared.dismiss(run.id) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white.opacity(0.6)) }.buttonStyle(.plain)
                }
                Text(working ? (run.steps.last?.text ?? "Starting…") : run.result)
                    .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.92)).lineLimit(working ? 3 : 4).fixedSize(horizontal: false, vertical: true)
                if working { Text("Step \(run.steps.count) · \(run.task.prefix(40))").font(.system(size: 9)).foregroundColor(.white.opacity(0.5)).lineLimit(1) }
                HStack(spacing: 8) {
                    Button("See steps") { AgentStage.shared.keep(run.id); AgentStage.shared.open(agent) }
                    if let links = run.links, !links.isEmpty {
                        Menu("Links (\(links.count))") {
                            ForEach(links.prefix(10), id: \.url) { l in Button(String(l.title.prefix(60))) { if let u = URL(string: l.url) { NSWorkspace.shared.open(u) } } }
                        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    }
                    if f.tools.contains(.web), let q = run.task.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                        Button("Open in browser") {
                            let url = f == .travel ? (ZuffiTeam.travelLinks(run.task).first?.url ?? "https://www.google.com/search?q=\(q)") : "https://www.google.com/search?q=\(q)"
                            if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                        }
                    }
                }
                .buttonStyle(.plain).font(.system(size: 9.5, weight: .semibold)).foregroundColor(f.color)
            }
            .padding(9)
            .frame(width: 184, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#12141B").opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(f.color.opacity(0.55), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            AgentRobot(field: f, working: working, done: run.status == "Done").frame(width: 92, height: 104)
                .onTapGesture { AgentStage.shared.keep(run.id); AgentStage.shared.open(agent) }
                .scaleEffect(hover ? 1.06 : 1).onHover { hover = $0 }.animation(.spring(), value: hover)
            Text(agent.name).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(f.gradient)).lineLimit(1)
        }
        .frame(width: 184)
        .help("\(agent.name): \(run.task)")
    }
}

/// A small, cute robot drawn in code. Colour, hat and what it holds come from its field.
struct AgentRobot: View {
    let field: AgentField
    var working = false
    var done = false

    private var hand: String {
        switch field {
        case .research: return "magnifyingglass"
        case .finance: return "chart.line.uptrend.xyaxis"
        case .bookings: return "calendar"
        case .customers: return "heart.fill"
        case .sales: return "briefcase.fill"
        case .marketing: return "megaphone.fill"
        case .travel: return "airplane"
        case .product: return "shippingbox.fill"
        case .project: return "checklist"
        case .support: return "bubble.left.fill"
        case .design: return "paintbrush.pointed.fill"
        case .engineering: return "wrench.and.screwdriver.fill"
        case .security: return "lock.shield.fill"
        case .legal: return "building.columns.fill"
        case .health: return "cross.fill"
        case .data: return "chart.bar.fill"
        case .strategy: return "map.fill"
        case .education: return "book.fill"
        case .games: return "gamecontroller.fill"
        case .manager: return "point.3.connected.trianglepath.dotted"
        case .other: return "sparkles"
        }
    }
    private enum Hat { case none, cap, beret, headset, pilot, grad, hardhat, crown }
    private var hat: Hat {
        switch field {
        case .marketing, .sales: return .cap
        case .design: return .beret
        case .support, .bookings, .customers: return .headset
        case .travel: return .pilot
        case .research, .education, .data: return .grad
        case .engineering, .project: return .hardhat
        case .manager: return .crown
        default: return .none
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let bob = working ? sin(t * 6) * 3 : done ? abs(sin(t * 3)) * -6 : sin(t * 1.6) * 1.5
            let arm = working ? sin(t * 8) * 22 : done ? -40 : sin(t * 1.6) * 6
            let blink = (t.truncatingRemainder(dividingBy: 3.4)) < 0.12
            let c = field.color, c2 = Color(hex: field.colors[1])
            ZStack {
                // shadow
                Ellipse().fill(Color.black.opacity(0.25)).frame(width: 52, height: 8).offset(y: 50)
                Group {
                    // legs
                    HStack(spacing: 12) {
                        Capsule().fill(Color(hex: "#DDE3EC")).frame(width: 11, height: 16)
                        Capsule().fill(Color(hex: "#DDE3EC")).frame(width: 11, height: 16)
                    }.offset(y: 40)
                    // arms
                    Capsule().fill(Color(hex: "#E8EDF4")).frame(width: 10, height: 26)
                        .rotationEffect(.degrees(20 - arm * 0.3), anchor: .top).offset(x: -26, y: 14)
                    ZStack {
                        Capsule().fill(Color(hex: "#E8EDF4")).frame(width: 10, height: 26)
                        Image(systemName: hand).font(.system(size: 13, weight: .bold)).foregroundColor(c)
                            .padding(3).background(Circle().fill(.white)).offset(y: 16)
                    }
                    .rotationEffect(.degrees(-20 + arm), anchor: .top).offset(x: 26, y: 14)
                    // body with the field's outfit
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LinearGradient(colors: [.white, Color(hex: "#DCE3EE")], startPoint: .top, endPoint: .bottom))
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LinearGradient(colors: [c, c2], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 30, height: 22).offset(y: 3)
                        Image(systemName: field.symbol).font(.system(size: 10, weight: .bold)).foregroundColor(.white).offset(y: 3)
                        if field == .finance || field == .sales || field == .legal {         // a little tie
                            Path { p in p.move(to: CGPoint(x: 21, y: 0)); p.addLine(to: CGPoint(x: 27, y: 0)); p.addLine(to: CGPoint(x: 24, y: 9)); p.closeSubpath() }
                                .fill(c2).frame(width: 48, height: 10).offset(y: -15)
                        }
                    }
                    .frame(width: 48, height: 42).offset(y: 16)
                    // head
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(LinearGradient(colors: [.white, Color(hex: "#E4E9F1")], startPoint: .top, endPoint: .bottom))
                            .frame(width: 60, height: 46)
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: "#151A26")).frame(width: 46, height: 26).offset(y: 2)
                        // eyes
                        HStack(spacing: 10) {
                            Capsule().fill(c).frame(width: 9, height: blink ? 2 : (done ? 5 : 10)).shadow(color: c, radius: 4)
                            Capsule().fill(c).frame(width: 9, height: blink ? 2 : (done ? 5 : 10)).shadow(color: c, radius: 4)
                        }.offset(y: 2)
                        if done { Path { p in p.addArc(center: CGPoint(x: 12, y: 0), radius: 6, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false) }
                            .stroke(c, lineWidth: 2).frame(width: 24, height: 8).offset(y: 11) }
                        // cheeks
                        HStack(spacing: 40) { Circle().fill(c.opacity(0.35)).frame(width: 6); Circle().fill(c.opacity(0.35)).frame(width: 6) }.offset(y: 12)
                        // antenna (under a hat it hides)
                        if hat == .none || hat == .headset {
                            VStack(spacing: 0) {
                                Circle().fill(c).frame(width: 8, height: 8).shadow(color: c, radius: working ? 6 : 2)
                                Rectangle().fill(Color(hex: "#C9D1DC")).frame(width: 2, height: 7)
                            }.offset(y: -28)
                        }
                        hatView(c: c, c2: c2)
                    }
                    .offset(y: -18)
                }
                .offset(y: bob)
            }
            .frame(width: 92, height: 104)
        }
    }

    @ViewBuilder private func hatView(c: Color, c2: Color) -> some View {
        switch hat {
        case .none: EmptyView()
        case .cap:
            ZStack {
                Capsule().fill(c).frame(width: 46, height: 14).offset(y: -22)
                Capsule().fill(c2).frame(width: 26, height: 5).offset(x: 20, y: -16)
            }
        case .beret: Ellipse().fill(c).frame(width: 50, height: 14).rotationEffect(.degrees(-10)).offset(x: -4, y: -24)
        case .headset:
            ZStack {
                Circle().trim(from: 0.55, to: 0.95).stroke(c2, lineWidth: 3).frame(width: 64, height: 56).offset(y: -2)
                Circle().fill(c).frame(width: 12, height: 12).offset(x: -31, y: 2)
                Circle().fill(c).frame(width: 12, height: 12).offset(x: 31, y: 2)
                Capsule().fill(c2).frame(width: 14, height: 3).rotationEffect(.degrees(25)).offset(x: 24, y: 14)
            }
        case .pilot:
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(c2).frame(width: 50, height: 14).offset(y: -22)
                Capsule().fill(Color(hex: "#1B2236")).frame(width: 56, height: 5).offset(y: -15)
                Image(systemName: "airplane").font(.system(size: 7, weight: .bold)).foregroundColor(.yellow).offset(y: -22)
            }
        case .grad:
            ZStack {
                Rectangle().fill(Color(hex: "#1B2236")).frame(width: 46, height: 6).rotation3DEffect(.degrees(55), axis: (x: 1, y: 0, z: 0)).offset(y: -27)
                RoundedRectangle(cornerRadius: 3).fill(Color(hex: "#1B2236")).frame(width: 30, height: 8).offset(y: -22)
                Capsule().fill(c).frame(width: 2, height: 10).offset(x: 18, y: -22)
            }
        case .hardhat:
            ZStack {
                Ellipse().fill(Color(hex: "#F5B833")).frame(width: 52, height: 22).offset(y: -20)
                Capsule().fill(Color(hex: "#E09E12")).frame(width: 60, height: 5).offset(y: -12)
            }
        case .crown:
            Image(systemName: "crown.fill").font(.system(size: 18)).foregroundStyle(LinearGradient(colors: [Color(hex: "#FFD66B"), Color(hex: "#F59E3B")], startPoint: .top, endPoint: .bottom)).offset(y: -30)
        }
    }
}
