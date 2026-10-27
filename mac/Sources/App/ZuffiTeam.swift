import Foundation
import SwiftUI
import AppKit
import Combine
import WebKit
import CoreAudio
import SceneKit

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
    case manager, finance, bookings, customers, sales, marketing, research, travel, web, product, project, support, design, engineering, security, legal, health, data, strategy, education, games, other

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
        case .web: return "Web tasks"
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
        case .web: return "safari.fill"
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
        case .web: return ["#60A5FA", "#7C3AED"]
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
        case .research, .strategy, .travel, .web: return [.web]
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
        if a.id == "zuffi-web" { return .web }
        if a.id == "zuffi-reviews" { return .customers }
        if a.id == "zuffi-reports" { return .data }
        if a.id == "zuffi-docs" { return .data }
        if a.id == "zuffi-social" || a.id == "zuffi-writer" || a.id == "zuffi-instagram" || a.id == "zuffi-facebook" { return .marketing }
        if a.id == "zuffi-whatsapp" { return .customers }
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
    var weekday: Int?                 // 1 = Sunday … 7 = Saturday; nil = every day
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
    static let manager = TeamAgent(id: "zuffi-team-manager", division: "management", name: "Nik",
                                   description: "Nik, your manager, leads your AI team: sends each question only to the people who should answer it and brings back one clear answer with next steps.",
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
        TeamAgent(id: "zuffi-social", division: "business", name: "Social Media Agent",
                  description: "Plans your week of posts, makes the pictures and captions in your brand, and gets them ready for you to approve and post.",
                  emoji: "📣", prompt: """
                  You run a small business's social media. Plan posts from its offers, services, UK dates and what worked before. \
                  For each post give: the day, a picture idea, the caption (short, warm, in the brand's tone) and 5-8 hashtags. Never invent prices or offers — use the business details. \
                  Posting waits for the owner's approval.
                  """),
        TeamAgent(id: "zuffi-instagram", division: "business", name: "Instagram Agent",
                  description: "Checks your Instagram and your competitors', plans posts and reels with captions and hashtags, and drafts replies to comments and DMs for you to approve.",
                  emoji: "📸", prompt: """
                  You grow a small business on Instagram. Look at what the business and its competitors post (from the pages you read),                   then plan posts and reels: the idea, the first 3 seconds hook, the caption, 8-12 hashtags and the best time to post.                   Draft replies to comments or DMs when asked. Never invent prices or offers. You never post, follow, like or send — the owner approves and posts.
                  """),
        TeamAgent(id: "zuffi-facebook", division: "business", name: "Facebook Agent",
                  description: "Looks after your Facebook page: post ideas and captions, local groups worth joining, ad ideas with a budget, and replies to comments for you to approve.",
                  emoji: "👍", prompt: """
                  You run a small business's Facebook page. From what you read (the page, competitors, local groups) suggest posts,                   events and simple ad ideas with audience, budget and the message. Draft replies to comments and reviews.                   Never invent prices or offers. You never post, join, like or send — the owner approves first.
                  """),
        TeamAgent(id: "zuffi-whatsapp", division: "business", name: "WhatsApp Agent",
                  description: "Writes WhatsApp replies, follow-ups and offers for your customers in your tone, and spots who needs a message today — you approve before anything is sent.",
                  emoji: "💬", prompt: """
                  You look after the business's WhatsApp customers. Using the customer and lead data, say who needs a message today                   (new enquiries, no reply yet, follow-ups, past customers to win back) and write each message: short, friendly, in the owner's language and tone.                   Never promise prices or availability that aren't in the data. Nothing is sent until the owner approves.
                  """),
        TeamAgent(id: "zuffi-reviews", division: "business", name: "Reviews Agent",
                  description: "Watches your Google and Facebook reviews, drafts warm replies for you to approve, and finds happy customers to ask for a review.",
                  emoji: "⭐", prompt: """
                  You look after the business's online reviews. Draft short, personal, polite replies (thank by name, mention what they liked, \
                  for complaints apologise, offer to fix it privately). Never argue. Replies are sent only after the owner approves.
                  """),
        TeamAgent(id: "zuffi-reports", division: "business", name: "Reports Agent",
                  description: "Writes your weekly report in plain words: what the team did, what worked, and what to do next week.",
                  emoji: "📊", prompt: """
                  You write a short weekly report for a small business owner from the team's real work and data you're given. \
                  Plain words, numbers only from the data, three sections: done this week, what worked, next week's plan.
                  """),
        TeamAgent(id: "zuffi-web", division: "business", name: "Web Helper",
                  description: "Does jobs on websites for you in its own browser tab — looks things up, fills forms, compares prices — while your mouse stays free. Asks before anything risky.",
                  emoji: "🧭", prompt: """
                  You do tasks on websites in your own browser tab. Explain each step briefly. Never type passwords or card numbers, never buy, send, \
                  post or delete without the user's yes. If a site needs a login or a CAPTCHA, ask the user to do that part.
                  """),
        TeamAgent(id: "zuffi-writer", division: "business", name: "Writer",
                  description: "Writes emails, proposals, posts, letters and summaries in your voice, ready for you to check.",
                  emoji: "✍️", prompt: """
                  You write clear, warm, well-structured text in the user's voice and language: emails, proposals, posts, letters, summaries. \
                  Ask one question if something essential is missing; otherwise write it straight away.
                  """),
        TeamAgent(id: "zuffi-travel", division: "business", name: "Travel Agent",
                  description: "Finds flights, hotels and trains: compares prices and times, gives you the links, and can open them in your browser. Never books or pays without your yes.",
                  emoji: "✈️", prompt: """
                  You find travel options for the owner: flights, hotels, trains, car hire. Use the web notes you're given and name each source. \
                  If anything is missing (which city or airport, dates, how many people, one-way or return) ask for it first and stop. \
                  Give times and prices only when you read them on a real page; otherwise say they must be checked on the link. Never estimate a price. \
                  You can't book or pay; say “I can open the cheapest option in your browser” and wait for a yes.
                  """),
        TeamAgent(id: "zuffi-docs", division: "business", name: "Documents & Data",
                  description: "Turns data you give it into neat spreadsheets, fixes and tidies messy data (duplicates, formats, gaps), and reads PDFs and documents to pull out what you need.",
                  emoji: "📄", prompt: """
                  You handle the owner's documents and data. From the file or text you're given: tidy it (remove duplicates, fix dates, names and number formats, \
                  flag missing values), lay it out as a clear table (columns first, then rows), and pull out exactly what was asked. \
                  Use only what is in the file or text — never invent rows, totals or values. Say which rows you changed and why. \
                  If the file or a needed column is missing, ask for it.
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
    /// An agent asked you something ("which city?") — your next message goes back to it with the original task.
    var awaiting: (agent: TeamAgent, task: String, at: Date)?
    /// The last job done in the chat, so "which one is cheapest?" goes back to the same agent with the same facts.
    var lastWork: (agent: TeamAgent, task: String, result: String, facts: String, at: Date)?
    /// Personal helpers (everyday): the chat with Zuffi only uses these. Business agents work only in the business tabs or with Nik.
    static func isPersonal(_ a: TeamAgent) -> Bool { personalTeam.contains(a.id) }
    /// Who you can talk to in the chat.
    var chatAgents: [TeamAgent] {
        let personal = (Self.personalTeam.compactMap { agent($0) })
        let biz = ZuffiPlan.shared.isPersonal ? [] : hiredAgents.filter { !Self.isPersonal($0) }
        var out: [TeamAgent] = []
        for a in personal + biz where !out.contains(a) { out.append(a) }
        return out
    }

    /// A new chat: plain Zuffi again, and the team forgets the old topic.
    func newConversation() { activeIDs = []; recent = []; pendingHire = []; awaiting = nil; lastWork = nil; flightPage = nil }

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

    /// The focused team shown for now (the full list of specialists is hidden, not removed).
    var focusAgents: [TeamAgent] {
        // business agents only once the business form is filled in
        let ids = ZuffiPlan.shared.isPersonal || !BizNav.shared.formDone ? Self.personalTeam : Self.personalTeam + Self.businessTeam + ["finance-financial-analyst", "zuffi-bookings", "zuffi-crm"]
        var out: [TeamAgent] = []
        for id in ids { if let a = agent(id), !out.contains(a) { out.append(a) } }
        return out
    }
    static let personalTeam = ["zuffi-travel", "research-synthesist", "zuffi-writer", "zuffi-web", "zuffi-docs"]
    static let businessTeam = ["zuffi-social", "zuffi-instagram", "zuffi-facebook", "zuffi-whatsapp", "zuffi-reviews", "zuffi-competitors", "zuffi-reports"]

    /// A good first team for each kind of business.
    var starterTeam: [String] {
        if ZuffiPlan.shared.isPersonal { return Self.personalTeam }
        if ZuffiPlan.shared.mode != nil { return Self.businessTeam }
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
    func systemPrompt(for a: TeamAgent, part: String = "", others: [TeamAgent] = [], data: String = "", business: Bool? = nil) -> String {
        let useBusiness = business ?? !Self.isPersonal(a)
        let field = AgentField.of(a)
        let owner = AssistantPrefs.displayName.isEmpty ? "the owner" : AssistantPrefs.displayName
        let team = others.isEmpty ? "" : "\nYou're working together with: " + others.map(\.name).joined(separator: ", ") + ". Do only your own part; don't repeat theirs."
        return """
        You are \(AgentEdits.name(a)) \(a.emoji), a senior \(a.name) (\(field.label)) with 15+ years of experience, working for \(owner) inside Zuffi. You are one of the team members, led by Nik, the manager.\(team)
        WHO YOU ARE
        - Speak as yourself, in the first person. If asked who you are, say “I'm your \(a.name)” and in one line how you help this business. Never call yourself Zuffi or “an AI model”.
        - Your expertise: \(a.description)
        - Stay on the owner's question and on your own field. Never talk about reminders, the owner's personal life or Zuffi's features unless asked.
        HOW YOU WORK
        - Think like the best \(a.name) in the field, for THIS business: practical steps, examples, what to do first.
        - NUMBERS: use only numbers that appear in VERIFIED DATA below. Never invent, estimate or "assume" revenue, costs, tax, profit, bookings, customers or prices. If a number you need isn't there, say it can't be verified yet and ask the owner for it (or to open the page). Label figures as actual (from data), calculated (show the sum) or missing.
        - If the request is unclear or a detail you need is missing (which city or airport, dates, budget, who it's for…), DON'T guess: ask one to three short questions and stop.
        - Ask ONCE only. If the task says "already answered", never ask again: use their details, and if something is still missing, say your assumption in one line and carry on.
        - If you need a fact about the business that isn't here, ask one or two short questions first.
        WORK LIKE A SENIOR EXPERT (this is why people use Zuffi instead of a chatbot)
        - First work out what the owner really needs (goal, budget, timing, limits) — answer that, not just the words.
        - Don't paste search results. Compare at least three real options from the sources you read, then pick the best one FOR THIS PERSON and say why in one line.
        - Point out what they didn't think of: hidden costs, a better time or place, a cheaper or safer alternative, risks.
        - End with the clear next step (and the link to act on). Every option and price must come from a source you read, with its link.
        - If the question belongs to another field, say who on the team should take it.
        - You think, read and write. You can't send messages, post, pay, book or delete — suggest it and ask the owner to OK it.
        - Reply in the owner's language. Plain text with line breaks: no ** bold and no tables. Use short paragraphs, numbered steps or lines starting with \"- \".
        \(part.isEmpty ? "" : "\nYOUR PART OF THIS JOB: \(part)\nKeep it under 180 words.\n")
        \(useBusiness ? "ABOUT THE BUSINESS\n" + Self.businessContext : "This is the owner's own everyday request — it is NOT about their business. Don't mention their business.")

        VERIFIED DATA (the only figures you may use)
        \(data.isEmpty ? "(none for this question)" : data)

        \(AgentEdits.get(a.id).notes.isEmpty ? "" : "THE OWNER'S OWN INSTRUCTIONS FOR YOU (follow them):\n" + AgentEdits.get(a.id).notes + "\n")
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
        switch a.id {
        case "zuffi-instagram": return TeamJob(agent: a.id, title: "Today's Instagram", task: "Check my Instagram and two competitors, then give me today's post or reel: idea, hook, caption, hashtags and the best time to post.", hour: 10, minute: 0)
        case "zuffi-facebook": return TeamJob(agent: a.id, title: "Facebook page check", task: "Check my Facebook page and local competitors, then suggest today's post and one local group or ad idea worth trying.", hour: 10, minute: 30)
        case "zuffi-whatsapp": return TeamJob(agent: a.id, title: "WhatsApp follow-ups", task: "Who should get a WhatsApp message today (new enquiries, no reply yet, follow-ups, customers to win back)? Write each message for me to approve.", hour: 9, minute: 30)
        case "zuffi-reviews": return TeamJob(agent: a.id, title: "Reviews check", task: "Check my business's newest reviews. Summarise what people liked and didn't, and draft polite replies for me to approve.", hour: 11, minute: 0)
        case "zuffi-reports": return TeamJob(agent: a.id, title: "End-of-day report", task: "Write today's short business report: what happened, numbers you can see, and 3 things to do tomorrow.", hour: 17, minute: 30, readsDashboard: dash)
        case "research-synthesist": return TeamJob(agent: a.id, title: "Morning brief", task: "Give me a short morning brief: the most important news today in my area of work, with links.", hour: 8, minute: 0)
        default: break
        }
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
        if t.range(of: #"^(show|open)( me)?( the| my)? (agent browser|agents at work|agents'? tabs?|what (my|the) agents are doing)$"#, options: .regularExpression) != nil {
            AgentBrowser.shared.show(); return "Here's the agent browser — every agent's tab, live."
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
        if m(#"^(please )?(go to|open) [a-z0-9.-]+\.(com|co\.uk|org|net|io)\b.*\b(and|then)\b|\b(fill (in|out)?( the| this| a)? form|compare prices|on (amazon|ebay|argos|currys|john lewis|gumtree|etsy)|sign me up|check (the )?website)\b"#) { return .web }
        if m(#"\b(write|draft|rewrite|proofread)( me)? (an? )?(email|proposal|letter|cover letter|summary|bio|description|reply)\b"#) { return .marketing }
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
        .sales: "sales-coach", .product: "product-manager", .research: "research-synthesist", .travel: "zuffi-travel", .web: "zuffi-web",
    ]

    /// The people who should answer: the field's person from the picked team, else from the hired team, else Zuffi's default.
    func route(_ question: String, among people: [TeamAgent]) async -> [TeamAgent] {
        let team = people.filter { $0.id != Self.manager.id }
        // "Today's business report" → money and bookings (and customers if they're on the team) — nobody else.
        let ql = question.lowercased()
        if ql.range(of: #"\b(weekly|week'?s) (report|summary)\b|\bwhat did (my|the) team do\b"#, options: .regularExpression) != nil, let r = agent("zuffi-reports") { return [r] }
        if ql.range(of: #"\b(write|draft|rewrite|proofread)\b.*\b(email|proposal|letter|summary|bio|reply)\b"#, options: .regularExpression) != nil, let w = agent("zuffi-writer") { return [w] }
        if ql.range(of: #"\breviews?\b"#, options: .regularExpression) != nil, ql.range(of: #"\b(google|facebook|reply|replies|customer)\b"#, options: .regularExpression) != nil, let r = agent("zuffi-reviews") { return [r] }
        if ql.range(of: #"\b(business|daily|today'?s|monthly) (report|summary|update)\b|\breport (for|on) (today|this week|this month)\b"#, options: .regularExpression) != nil {
            let pool = team + hiredAgents
            var out: [TeamAgent] = []
            for f in [AgentField.finance, .bookings, .customers] {
                if let a = pool.first(where: { AgentField.of($0) == f }) ?? (f == .customers ? nil : Self.defaultFor[f].flatMap(agent)), !out.contains(a) { out.append(a) }
            }
            if !out.isEmpty { return out }
        }
        if let f = Self.intent(question) {
            let pickFrom = team + hiredAgents + focusAgents
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
        if let r = await continueAwaiting(question) { return r }
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

        // Flights: ask first if the trip isn't clear; then really open Google Flights and read the results — never guess prices.
        if field == .travel, Self.isFlightQuestion(task) {
            if let q = Self.flightQuestions(task) {
                awaiting = (a, task, Date())
                step(id, "Asked you for the missing details")
                finish(id, q, "Needs input")
                return runs.first { $0.id == id }!
            }
            let trip = Self.flightTrip(task)
            step(id, "Opening Google Flights — \(trip.label)", source: "Google Flights")
            let page = await AgentBrowser.shared.readPage(trip.url, agent: a, runID: id)
            step(id, page.text.count > 600 ? "Read the flight results" : "Google Flights didn't show results", source: "Google Flights")
            flightPage = (trip.label, page.text, trip.url.absoluteString)
            if let i = runs.firstIndex(where: { $0.id == id }) { runs[i].links = [WebLink(title: "Google Flights — \(trip.label)", url: trip.url.absoluteString)] }
            step(id, "Writing the answer")
            let (text, ok) = await flightAnswer(a, question: task, trip: trip.label, page: page.text, url: trip.url.absoluteString)
            finish(id, text, ok ? "Done" : "Failed")
            if ok { lastWork = (a, task, text, page.text, Date()) }
            return runs.first { $0.id == id }!
        }

        // Web jobs: the agent works in its own tab in the agent browser (watch it, pause it, take over).
        if field == .web {
            step(id, "Opening its own browser tab")
            let ans = await AgentBrowser.shared.run(task, agent: a, runID: id)
            let failed = ans.hasPrefix("I couldn't") || ans.hasPrefix("I stopped") || ans == "Stopped."
            finish(id, Self.plain(ans), failed ? "Failed" : "Done")
            return runs.first { $0.id == id }!
        }

        // Documents & Data: makes a real spreadsheet file (CSV, opens in Excel or Numbers) or a new PDF from the owner's data.
        if a.id == "zuffi-docs" {
            let (text, ok) = await DocsAgent.run(task, step: { self.step(id, $0) })
            finish(id, text, ok ? "Done" : "Needs input")
            if !ok { awaiting = (a, task, Date()) } else { lastWork = (a, task, text, "", Date()) }
            return runs.first { $0.id == id }!
        }

        // Everything else: the AI, with only the real data this agent's tools allow.
        var data = TeamData.block(for: field.tools, question: task)
        if a.id == "zuffi-reports" {
            let week = runs.filter { $0.started > Date().addingTimeInterval(-7 * 86400) && $0.agent != a.id && $0.status != "Working" }
            let lines = week.prefix(40).map { r in "\(agent(r.agent)?.name ?? r.agent) · \(r.started.formatted(date: .abbreviated, time: .omitted)) · \(r.status): \(r.task.prefix(80)) → \(r.result.prefix(140))" }
            data.text += "\n\nTEAM WORK THIS WEEK (\(week.count) jobs):\n" + (lines.isEmpty ? "No jobs yet." : lines.joined(separator: "\n"))
            data.sources.append("Team activity")
        }
        for s in data.sources { step(id, "Looked at \(s)", source: s) }
        // Research like a person: search, open the pages, read them — each step shows on the agent's card.
        var webNotes = "", links: [WebLink] = []
        if field.tools.contains(.web), NetStatus.shared.online {
            let r = await ZuffiReach.research(task, agent: a, runID: id, step: { self.step(id, $0, source: "Web") })
            webNotes = r.notes; links = r.links
            if links.isEmpty { step(id, "The searches found nothing — asking the AI with Google Search if it's available") }
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
            let r = await AIService.shared.textAnswerFull(system: system + extra, messages: recent + [["role": "user", "content": task]], max: 1500,
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
        let asks = reply.contains("?") && reply.count < 500 && reply.lowercased().range(of: #"could you|can you (tell|share|give|confirm)|please (tell|share|send|confirm)|what (is|are) your|which (city|one|date|airport|day)|when (do|would) you|do you (want|prefer)"#, options: .regularExpression) != nil
        finish(id, withLinks, asks ? "Needs input" : "Done")
        if asks { awaiting = (a, task, Date()) } else { lastWork = (a, task, reply, data.text + "\n" + webNotes, Date()) }
        return runs.first { $0.id == id }!
    }

    // MARK: Flights — real results only

    /// What the Travel agent read on Google Flights last (so "which one is cheapest?" is answered from the same page).
    var flightPage: (trip: String, text: String, url: String)?

    static func isFlightQuestion(_ q: String) -> Bool {
        q.lowercased().range(of: #"\b(flights?|fly|flying|airline|air ?fare|plane tickets?|tickets? to)\b"#, options: .regularExpression) != nil
    }

    private static let countryCities: [String: [String]] = [
        "pakistan": ["Lahore", "Islamabad", "Karachi", "Peshawar", "Multan", "Sialkot", "Faisalabad"], "pak": ["Lahore", "Islamabad", "Karachi", "Peshawar", "Multan", "Sialkot", "Faisalabad"],
        "uk": ["London", "Manchester", "Birmingham", "Glasgow", "Edinburgh"], "england": ["London", "Manchester", "Birmingham"], "united kingdom": ["London", "Manchester", "Birmingham"],
        "india": ["Delhi", "Mumbai", "Bangalore"], "uae": ["Dubai", "Abu Dhabi", "Sharjah"], "usa": ["New York", "Los Angeles", "Chicago"], "america": ["New York", "Los Angeles", "Chicago"],
        "us": ["New York", "Los Angeles", "Chicago"], "turkey": ["Istanbul", "Antalya", "Izmir"], "spain": ["Barcelona", "Madrid", "Malaga"], "saudi": ["Jeddah", "Riyadh", "Madinah"],
        "saudi arabia": ["Jeddah", "Riyadh", "Madinah"], "italy": ["Rome", "Milan", "Venice"], "france": ["Paris", "Nice", "Lyon"], "canada": ["Toronto", "Vancouver", "Montreal"],
        "bangladesh": ["Dhaka", "Sylhet", "Chittagong"], "egypt": ["Cairo", "Sharm el-Sheikh", "Hurghada"], "greece": ["Athens", "Crete", "Rhodes"], "portugal": ["Lisbon", "Porto", "Faro"],
    ]

    /// "from london to lahore" → ("london", "lahore").
    static func fromTo(_ q: String) -> (String, String) {
        let t = q.lowercased().replacingOccurrences(of: "\n", with: " ")
        let stop = #"(?: on| for| in| next| this| tomorrow| and| one| return| around| between| from the|,|\.|\?|$)"#
        for p in [#"from ([a-z][a-z ]*?) to ([a-z][a-z ]*?)"# + stop, #"([a-z]+(?: [a-z]+)?) to ([a-z][a-z ]*?)"# + stop] {
            if let re = try? NSRegularExpression(pattern: p), let m = re.matches(in: t, range: NSRange(t.startIndex..., in: t)).last,
               let a = Range(m.range(at: 1), in: t), let b = Range(m.range(at: 2), in: t) {
                var from = String(t[a]).trimmingCharacters(in: .whitespaces), to = String(t[b]).trimmingCharacters(in: .whitespaces)
                for w in ["cheap flight", "cheapest flight", "flights", "flight", "cheap", "cheapest", "a ", "fly", "i want", "want", "go", "find me", "find"] { from = from.replacingOccurrences(of: w, with: "").trimmingCharacters(in: .whitespaces) }
                to = to.replacingOccurrences(of: "flights", with: "").trimmingCharacters(in: .whitespaces)
                if !from.isEmpty || !to.isEmpty { return (from, to) }
            }
        }
        return ("", "")
    }

    static func hasDate(_ q: String) -> Bool {
        let t = q.lowercased()
        if t.range(of: #"\b(today|tomorrow|tonight|next (week|month|weekend)|this (week|month|weekend)|any ?time|anytime|flexible|whenever|any date|cheapest (day|date|month)|january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec|monday|tuesday|wednesday|thursday|friday|saturday|sunday|eid|christmas|summer|winter)\b"#, options: .regularExpression) != nil { return true }
        if let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue), d.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) != nil { return true }
        return false
    }

    /// The questions to ask before searching (nil = enough to search).
    /// A city of that country you mentioned anywhere (e.g. you answered "Lahore" to "which city in Pakistan?").
    static func cityIn(_ q: String, _ country: String) -> String? {
        guard let cities = countryCities[country] else { return nil }
        let l = q.lowercased()
        return cities.first { l.contains($0.lowercased()) }
    }
    static func flightQuestions(_ q: String) -> String? {
        // Asked once already: never ask again — go with what you said.
        if q.contains("already answered") { return nil }
        var (from, to) = fromTo(q)
        if let c = cityIn(q, from) { from = c }
        if let c = cityIn(q, to) { to = c }
        var ask: [String] = []
        if from.isEmpty { ask.append("Where are you flying from? (city or airport, e.g. London Heathrow)") }
        else if let cities = countryCities[from] { ask.append("Which city in \(from.capitalized) are you flying from? (\(cities.joined(separator: ", ")))") }
        if to.isEmpty { ask.append("Where do you want to fly to?") }
        else if let cities = countryCities[to] { ask.append("Which city in \(to == "pak" ? "Pakistan" : to.capitalized)? (\(cities.joined(separator: ", ")))") }
        if !hasDate(q) { ask.append("When do you want to fly? (a date, a month, or “any time” for the cheapest day)") }
        if q.lowercased().range(of: #"\b(one.?way|single|return|round.?trip|coming back|back on)\b"#, options: .regularExpression) == nil, !ask.isEmpty { ask.append("One way or return?") }
        guard !ask.isEmpty else { return nil }
        return "I'll find real prices on Google Flights. First I need to know:\n" + ask.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    static func flightTrip(_ q: String) -> (label: String, url: URL) {
        var (from, to) = fromTo(q)
        if let c = cityIn(q, from) { from = c }
        if let c = cityIn(q, to) { to = c }
        let t = q.lowercased()
        let ret = t.range(of: #"\b(return|round.?trip|coming back|back on)\b"#, options: .regularExpression) != nil
        // the date words exactly as you said them
        var when = ""
        if let r = t.range(of: #"\b(on|in|for|around|next|this|tomorrow|today)\b[^.?\n]{0,40}"#, options: .regularExpression) { when = String(t[r]) }
        if t.range(of: #"any ?time|anytime|flexible|whenever|any date"#, options: .regularExpression) != nil { when = "" }
        var phrase = "Flights from \(from) to \(to)"
        if !when.isEmpty { phrase += " " + when }
        phrase += ret ? " return" : " one way"
        let enc = phrase.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? phrase
        let url = URL(string: "https://www.google.com/travel/flights?q=\(enc)&hl=en-GB&curr=GBP") ?? URL(string: "https://www.google.com/travel/flights")!
        let label = "\(from.capitalized) → \(to.capitalized)" + (when.isEmpty ? ", cheapest dates" : ", \(when)") + (ret ? ", return" : ", one way")
        return (label, url)
    }

    /// The answer from the page Google Flights showed. Every price must be on that page.
    func flightAnswer(_ a: TeamAgent, question: String, trip: String, page: String, url: String) async -> (String, Bool) {
        guard page.count > 600, page.range(of: #"[£$€]\s?\d|Rs\.?\s?\d|PKR"#, options: .regularExpression) != nil else {
            return ("I opened Google Flights for \(trip) but it didn't show any prices I could read, so I won't guess.\nOpen the results yourself:\n• Google Flights — \(url)", false)
        }
        let system = """
        You are the Travel Agent. The text below is the Google Flights results page you just opened for: \(trip).
        Answer the owner's question using ONLY this page. Copy prices, times, airlines and airports exactly as written. Never add a price that isn't on the page.
        Layout (plain text, no markdown symbols):
        Cheapest: <airline> — <price>
        Route: <departure airport> → <stop city/airport if any> → <arrival airport>
        Times: <depart> → <arrive> (<duration>, <stops>)
        Then a heading "Other options:" with up to 4 lines "• <airline> — <price> · <depart>–<arrive> · <duration> · <stops>".
        End with one line about the date/trip type shown. If the page doesn't show something, say it isn't shown.
        PAGE TEXT:
        \(page.prefix(12000))
        """
        for attempt in 0..<2 {
            let extra = attempt == 0 ? "" : "\nIMPORTANT: your last answer used a price that isn't on the page. Use only prices from the page."
            guard let r = await AIService.shared.textAnswer(system: system + extra, messages: [["role": "user", "content": question]], max: 700) else {
                return ("I read the Google Flights page but couldn't reach an AI to sum it up. Nothing was made up — open the results:\n• Google Flights — \(url)", false)
            }
            let clean = Self.plain(r)
            if Self.badAnswer(clean, agent: a, data: page) == nil {
                return (clean + "\n\nSources:\n• Google Flights — \(trip) — \(url)", true)
            }
        }
        return ("I couldn't get reliable prices from the page, so I won't guess. Open the results:\n• Google Flights — \(url)", false)
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
    /// Zuffi's own everyday helpers (always available — no hiring needed): who should take this?
    func personalRoute(_ q: String) -> TeamAgent? {
        let t = q.lowercased()
        func m(_ p: String) -> Bool { t.range(of: p, options: .regularExpression) != nil }
        if m(#"\b(spreadsheet|excel|csv|pdf|sheet|clean (this|the|my) data|fix (this|the|my) data|make a table)\b"#) { return agent("zuffi-docs") }
        if m(#"\b(write|draft|rewrite|proofread|reply to)\b.*\b(email|letter|message|post|caption|bio|cv|resume|cover letter|essay|speech|toast|story|poem)\b"#) { return agent("zuffi-writer") }
        if m(#"\b(flights?|fly to|airline|hotels?|holiday|vacation|trip|travel|travell?ing|itinerary|visit (germany|france|spain|italy|turkey|dubai|japan|[a-z]+)|places to (go|visit|see)|where (should|can) i go|tour|backpack)\b"#) { return agent("zuffi-travel") }
        if m(#"^(please )?(go to|open) [a-z0-9.-]+\.(com|co\.uk|org|net|io)\b.*\b(and|then)\b|\b(fill (in|out)?( the| this| a)? form|sign me up|add to (my )?basket)\b"#) { return agent("zuffi-web") }
        if m(#"\b(search|find|look(ing)? for|looking|research|compare|recommend|best|cheapest|cheap|price of|prices|cost of|rent|room|flat|house to|jobs?|course|school|restaurant|near me|in [a-z]+ area|where (can|do) i (buy|get|find)|which (is|one)|news|latest|review of|vs\.?|versus|how (do|can|to) i (find|get|choose))\b"#) { return agent("research-synthesist") }
        return nil
    }

    /// You answered an agent's question (in the chat, the task bar or the Office): it carries on with the first task — no asking again.
    func continueAwaiting(_ reply: String) async -> String? {
        guard let w = awaiting, Date().timeIntervalSince(w.at) < 30 * 60, !Self.looksLikeCommand(reply) else { return nil }
        // A clearly different, long new task is a new job, not an answer.
        let words = reply.split(separator: " ").count
        if words > 14, let f = Self.intent(reply), f != AgentField.of(w.agent) { return nil }
        awaiting = nil
        MissionControl.shared.begin(w.task, agents: [w.agent.id])
        let run = await work(w.agent, w.task + "\nMore details from the owner (already answered — don't ask these again): " + reply)
        return "\(w.agent.emoji) \(w.agent.name):\n\(run.result)"
    }

    func dispatch(_ query: String, personalOnly: Bool = false) async -> String? {
        guard ZuffiPlan.shared.isPaid, !Self.looksLikeCommand(query) else { return nil }
        if query.lowercased().range(of: #"^(remind|set|add|save|delete|remove|open|play|call|note)\b"#, options: .regularExpression) != nil { return nil }
        if let r = await continueAwaiting(query) { return r }
        // Everyday jobs go to Zuffi's own helpers (travel, research, writing, documents, websites).
        if personalOnly {
            guard let a = personalRoute(query) else { return nil }
            MissionControl.shared.begin(query, agents: [a.id])
            let run = await work(a, query)
            note(query, run.result)
            return "\(a.emoji) \(a.name):\n\(run.result)"
        }
        let jobs = Self.splitTasks(query).compactMap { t -> (String, AgentField)? in Self.intent(t).map { (t, $0) } }
        guard !jobs.isEmpty else { return nil }
        var plan: [(TeamAgent, String)] = []
        for (task, _) in jobs {
            if let a = await route(task, among: personalOnly ? hiredAgents.filter(Self.isPersonal) : hiredAgents).first,
               !personalOnly || Self.isPersonal(a),
               !plan.contains(where: { $0.0 == a && $0.1 == task }) { plan.append((a, task)) }
        }
        guard !plan.isEmpty else { return nil }
        if plan.count > 1 { log("Zuffi", "Gave out \(plan.count) jobs", plan.map { "\($0.0.name): \($0.1.prefix(40))" }.joined(separator: " · ")) }
        MissionControl.shared.begin(query, agents: plan.map { $0.0.id })
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

    /// "Give a task" (notch / dashboard): always team work, never the chat. Nik hands it to the right agent(s).
    func assignTask(_ q: String) async -> String {
        if let r = await continueAwaiting(q) { return r }
        if let r = await dispatch(q) { return r }
        if let a = personalRoute(q), ZuffiPlan.shared.isPaid {
            MissionControl.shared.begin(q, agents: [a.id])
            let run = await work(a, q); note(q, run.result); return run.result
        }
        guard ZuffiPlan.shared.isPaid else { return "Your team is part of Zuffi Pro and Business." }
        let a = (await route(q, among: hiredAgents).first) ?? agent("zuffi-web") ?? Self.manager
        MissionControl.shared.begin(q, agents: [a.id])
        let run = await work(a, q)
        note(q, run.result)
        return run.result
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
        guard f.tools.contains(.money) || f.tools.contains(.dashboard) || a.id == manager.id || [.travel, .research, .web].contains(f) else { return nil }
        let unknown = amounts(in: t).subtracting(amounts(in: data))
        if !unknown.isEmpty { return "used prices or figures it didn't actually read anywhere (\(unknown.prefix(3).joined(separator: ", ")))" }
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
            // a business agent's daily job waits until the business form is done
            if let a = agent(job.agent), !Self.isPersonal(a), !BizNav.shared.formDone { continue }
            if let wd = job.weekday, cal.component(.weekday, from: now) != wd { continue }
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
        let run: AgentRun
        if job.task == "plan posts" || job.task == "check reviews" {
            // the workspace jobs: posts go to Approvals; review replies are drafted for approval
            let id = begin(a, job.title, job: job.title)
            let text = job.task == "plan posts" ? await ZuffiWorkspace.shared.planPosts(runID: id) : await ZuffiWorkspace.shared.checkReviews(runID: id)
            finish(id, text, text.hasPrefix("I couldn't") ? "Needs input" : "Done")
            run = runs.first { $0.id == id }!
        } else {
            run = await work(a, job.task, job: job.title, readDashboard: job.readsDashboard)
        }
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
            if !ZuffiFocus.allAgents {
                Section("Zuffi's helpers") {
                    ForEach(team.focusAgents) { a in
                        Button { plan.isBusiness ? team.toggle(a) : team.use(a) } label: { Text("\(a.emoji) \(a.name)\(team.activeIDs.contains(a.id) ? "  ✓" : "")") }
                    }
                }
            }
            ForEach(ZuffiFocus.allAgents ? team.divisions : [], id: \.self) { d in
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
                    let hits = (ZuffiFocus.allAgents ? team.everyone : team.focusAgents).filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }.prefix(12)
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
    enum TeamTab: String, CaseIterable { case team = "Team", approvals = "Approvals", jobs = "Routines", activity = "Activity", hire = "Hire" }
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
                            Text(s.rawValue + (s == .team ? " (\(team.hiredAgents.count))" : s == .jobs ? " (\(team.jobs.count))" : s == .approvals ? " (\(ZuffiWorkspace.shared.waiting.count))" : ""))
                                .font(.system(size: 12, weight: section == s ? .semibold : .regular)).foregroundColor(section == s ? .white : Ink.text)
                                .padding(.horizontal, 12).frame(height: 28).background(Capsule().fill(section == s ? Ink.accent : Ink.panelHi))
                        }.buttonStyle(.plain)
                    }
                    Spacer()
                    if !team.working.isEmpty { HStack(spacing: 6) { ProgressView().controlSize(.small); Text(team.working).font(.system(size: 11)).foregroundColor(Ink.muted).lineLimit(1) } }
                    Button { AgentBrowser.shared.show() } label: { Label("Agent browser", systemImage: "safari") }.controlSize(.small)
                    Toggle("Show agents on screen", isOn: $stage.enabled).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
                }
                if !team.suggestions.isEmpty { suggestionsBox }
                switch section {
                case .team: teamSection
                case .approvals: TeamApprovalsView()
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

    @ObservedObject private var ws = ZuffiWorkspace.shared

    @ViewBuilder private var teamSection: some View {
        if ws.brief.isEmpty && !ZuffiPlan.shared.isPersonal { OnboardingChat() }
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
                    Text("\(a?.name ?? job.agent) · \(job.weekday.map { "every " + Calendar.current.weekdaySymbols[($0 - 1) % 7] } ?? "every day")\(job.readsDashboard ? " · reads \(team.sources.first?.name ?? "your dashboard")" : "")").font(.system(size: 10.5)).foregroundColor(Ink.faint)
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
                    TextField(ZuffiFocus.allAgents ? "Search \(team.everyone.count) specialists…" : "Search your helpers…", text: $search).textFieldStyle(.plain).frame(width: 200)
                }.padding(.horizontal, 10).frame(height: 30).inkPanel(Capsule())
            }
            if search.isEmpty && ZuffiFocus.allAgents {
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
            let pool = ZuffiFocus.allAgents ? team.everyone : team.focusAgents
            let list = !ZuffiFocus.allAgents && search.isEmpty ? team.focusAgents : search.isEmpty ? team.members(of: division)
                : pool.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.description.localizedCaseInsensitiveContains(search) }
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
    @Published var enabled: Bool = false {      // agents work in their tabs (Agent Office), never over your desktop
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
        let size = NSSize(width: CGFloat(showing.count) * 160 + 24, height: 230)
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
            .padding(8)
            .frame(width: 150, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "#12141B").opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(f.color.opacity(0.55), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            Buddy3DView(kind: .robot(f), mood: working ? .working : run.status == "Done" ? .happy : .idle, lookAtMouse: true)
                .frame(width: 64, height: 72)
                .overlay(Color.white.opacity(0.001))
                .onTapGesture { AgentStage.shared.keep(run.id); AgentStage.shared.open(agent) }
                .scaleEffect(hover ? 1.06 : 1).onHover { hover = $0 }.animation(.spring(), value: hover)
            Text(agent.name).font(.system(size: 10, weight: .bold)).foregroundColor(.white)
                .padding(.horizontal, 8).frame(height: 18).background(Capsule().fill(f.gradient)).lineLimit(1)
        }
        .frame(width: 150)
        .opacity(hover ? 1 : 0.92)
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
        case .web: return "safari.fill"
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

// MARK: - Agent browser: each agent works in its own tab inside Zuffi (your mouse stays free)
//
// Watch every agent live, pause it, or take over its tab. Agents read the page, click, type and scroll through the page itself
// (not your mouse), so several work at the same time. Anything that buys, pays, sends, posts, deletes or submits waits for your yes.
// Passwords and card numbers are never typed by an agent — it hands that part to you. Sign-ins stay in Zuffi's own browser.

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate {
    let id = UUID().uuidString
    let agent: TeamAgent
    let task: String
    let web: WKWebView
    @Published var title = "New tab"
    @Published var url = ""
    @Published var status = "Starting"           // Working · Paused · You're in control · Needs you · Done · Stopped
    @Published var steps: [String] = []
    @Published var paused = false
    @Published var takeover = false
    @Published var asking: String?                // "Click “Place order”?" waiting for a yes
    var answer: CheckedContinuation<Bool, Never>?
    var stopped = false
    var runID: String?

    init(agent: TeamAgent, task: String, store: WKWebsiteDataStore) {
        self.agent = agent; self.task = task
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = store
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760), configuration: cfg)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        super.init()
        web.navigationDelegate = self
    }

    func say(_ s: String) {
        steps.append(s)
        if let r = runID { ZuffiTeam.shared.step(r, s) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        title = webView.title ?? title; url = webView.url?.absoluteString ?? url
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // web pages only (no file://, no app links)
        guard let s = navigationAction.request.url?.scheme?.lowercased() else { return .cancel }
        return ["http", "https", "about", "data", "blob"].contains(s) ? .allow : .cancel
    }
}

@MainActor
final class AgentBrowser: ObservableObject {
    static let shared = AgentBrowser()
    @Published var tabs: [BrowserTab] = []
    @Published var selected: String?
    private var window: NSWindow?

    /// One sign-in store for all agent tabs (separate from Safari and WhatsApp).
    private lazy var store: WKWebsiteDataStore = {
        let key = "agentBrowserStore"
        let id = UUID(uuidString: UserDefaults.standard.string(forKey: key) ?? "") ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return WKWebsiteDataStore(forIdentifier: id)
    }()

    func show(_ tabID: String? = nil) {
        if let tabID { selected = tabID }
        if selected == nil { selected = tabs.last?.id }
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Zuffi — agents at work"; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentMinSize = NSSize(width: 900, height: 600)
        w.contentView = NSHostingView(rootView: AgentBrowserView())
        w.center(); w.setFrameAutosaveName("ZuffiAgentBrowser")
        window = w
        w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }

    func close(_ t: BrowserTab) {
        t.stopped = true; t.answer?.resume(returning: false); t.answer = nil
        tabs.removeAll { $0.id == t.id }
        if selected == t.id { selected = tabs.last?.id }
    }

    // MARK: the agent's hands

    /// Reads the page: what you can click or type into (numbered), plus the visible text.
    private static let readJS = """
    (() => {
      const vis = el => { const r = el.getBoundingClientRect(); const s = getComputedStyle(el);
        return r.width > 2 && r.height > 2 && s.visibility !== 'hidden' && s.display !== 'none' && r.bottom > -200 && r.top < innerHeight + 1400; };
      const items = []; let n = 0;
      document.querySelectorAll('a[href],button,input,textarea,select,[role=button],[role=link],[role=tab],[role=menuitem],[contenteditable=true],summary').forEach(el => {
        if (!vis(el) || n >= 120) return;
        const id = ++n; el.setAttribute('data-zid', id);
        const t = (el.getAttribute('aria-label') || el.innerText || el.value || el.placeholder || el.title || el.name || '').replace(/\\s+/g, ' ').trim().slice(0, 80);
        items.push({ id, tag: el.tagName.toLowerCase(), type: (el.type || '').toLowerCase(), text: t, href: (el.href || '').slice(0, 90),
          ac: (el.autocomplete || '').toLowerCase() });
      });
      const text = (document.body ? document.body.innerText : '').replace(/\\n{2,}/g, '\\n').slice(0, 3500);
      return JSON.stringify({ title: document.title, url: location.href, items, text });
    })()
    """

    private func read(_ t: BrowserTab) async -> [String: Any]? {
        guard let raw = try? await t.web.evaluateJavaScript(Self.readJS) as? String, let d = raw.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    private func waitLoaded(_ t: BrowserTab) async {
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if !t.web.isLoading, ((try? await t.web.evaluateJavaScript("document.readyState")) as? String) == "complete" { break }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
        t.title = t.web.title ?? t.title; t.url = t.web.url?.absoluteString ?? t.url
    }

    /// A Google search in an agent tab (you can watch it). Returns the result links; empty if Google asks for a check (we never get around those).
    func googleResults(_ query: String, agent: TeamAgent, runID: String?) async -> [(title: String, url: String, snippet: String)] {
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let url = URL(string: "https://www.google.com/search?q=\(enc)&hl=en-GB&num=10") else { return [] }
        let t = BrowserTab(agent: agent, task: "Google: \(query.prefix(60))", store: store)
        t.runID = runID; tabs.append(t)
        if selected == nil || tabs.count == 1 { selected = t.id }
        t.status = "Working"; t.say("Searching Google for “\(query.prefix(70))”")
        t.web.load(URLRequest(url: url)); await waitLoaded(t)
        if (t.web.url?.host ?? "").contains("consent.") {
            let r = await js(t, "(() => { const b = [...document.querySelectorAll('button,input[type=submit]')].find(x => /reject all|decline all|reject/i.test(x.innerText || x.value || '')); if (b) { b.click(); return 'ok'; } return 'none'; })()")
            if r == "ok" { t.say("Said no to extra cookies"); await waitLoaded(t) }
        }
        try? await Task.sleep(nanoseconds: 900_000_000)
        if (t.web.url?.path ?? "").hasPrefix("/sorry") {
            t.say("Google asked for a check — using another search instead"); t.status = "Done"; return []
        }
        let raw = await js(t, """
        JSON.stringify([...document.querySelectorAll('a h3')].slice(0, 10).map(h => { const a = h.closest('a'); const box = h.closest('div.g, div[data-hveid], div.MjjYud') || a.parentElement;
          const sn = box ? (box.querySelector('div.VwiC3b, span.aCOpRe, div[data-sncf]') || {}).innerText || '' : '';
          return { t: h.innerText, u: a ? a.href : '', s: sn }; }).filter(x => x.u.startsWith('http') && !x.u.includes('google.com/')))
        """)
        t.status = "Done"
        guard let d = raw.data(using: .utf8), let arr = try? JSONSerialization.jsonObject(with: d) as? [[String: String]] else { return [] }
        t.say("Found \(arr.count) results")
        return arr.map { (title: $0["t"] ?? "", url: $0["u"] ?? "", snippet: $0["s"] ?? "") }
    }

    /// Opens a site's sign-in page in Zuffi's own agent browser — you sign in yourself (Zuffi never sees or types your password).
    func signIn(_ site: String, url: URL) {
        let t = BrowserTab(agent: ZuffiTeam.manager, task: "Sign in to \(site)", store: store)
        tabs.append(t); selected = t.id
        t.status = "You're in control"; t.takeover = true
        t.say("Sign in to \(site) yourself — agents will then read it with your sign-in (read only).")
        t.web.load(URLRequest(url: url))
        show(t.id)
    }

    /// Is this site already signed in, in the agent browser? (checks for its usual session cookie)
    func isSignedIn(_ domain: String, cookie: String) async -> Bool {
        let all = await store.httpCookieStore.allCookies()
        return all.contains { $0.domain.contains(domain) && $0.name == cookie }
    }

    private func js(_ t: BrowserTab, _ code: String) async -> String {
        ((try? await t.web.evaluateJavaScript(code)) as? String) ?? ""
    }
    private static func q(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(data: d, encoding: .utf8)?.dropFirst().dropLast() ?? "\"\"")
    }

    /// Waits while paused / taken over; false when the tab was closed.
    private func holdIfPaused(_ t: BrowserTab) async -> Bool {
        while (t.paused || t.takeover) && !t.stopped { try? await Task.sleep(nanoseconds: 300_000_000) }
        return !t.stopped
    }

    private func approve(_ t: BrowserTab, _ question: String) async -> Bool {
        t.asking = question; t.status = "Needs you"
        MacStatus.shared.toast("\(t.agent.emoji) \(t.agent.name) needs your OK", question, icon: "hand.raised.fill")
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in MainActor.assumeIsolated { t.answer = c } }
        t.asking = nil; t.status = t.stopped ? "Stopped" : "Working"
        ZuffiTeam.shared.log(t.agent.name, ok ? "You approved" : "You said no", question)
        return ok
    }
    func reply(_ t: BrowserTab, _ yes: Bool) { t.answer?.resume(returning: yes); t.answer = nil }

    static let rules = """
    You are an agent doing a task in a web browser for the user. Each turn you get the page: title, url, the elements you can use (with numbers) and the visible text.
    Reply with ONE next action as JSON only:
    {"say": "very short step, e.g. 'Searching for flights'", "action": "click"|"type"|"select"|"scroll"|"go"|"back"|"wait"|"done"|"ask",
     "id": element number (click/type/select), "text": text to type, "enter": true to press Enter after typing, "value": option for select,
     "url": address for go, "dir": "down"|"up" for scroll, "answer": the result for done (what you found, with key facts and links), "question": what you need for ask,
     "risky": true if this action buys, pays, sends, posts, publishes, submits a form, books, subscribes, deletes or changes an account}
    Rules: use the fastest reliable way (search boxes, direct URLs). Never type passwords, card numbers, security codes or one-time codes — use "ask" so the user does it.
    If there's a login wall or a CAPTCHA, use "ask". Decline non-essential cookies. Don't repeat the same action again and again. Use "done" as soon as you have the answer.
    """

    /// Runs one agent's task in a new tab. Returns its answer (or why it stopped).
    func run(_ task: String, agent: TeamAgent, runID: String?) async -> String {
        let t = BrowserTab(agent: agent, task: task, store: store)
        t.runID = runID
        tabs.append(t)
        if selected == nil || tabs.count == 1 { selected = t.id }
        t.status = "Working"
        let start = Self.startURL(task)
        t.say("Opening \(start.host ?? start.absoluteString)")
        t.web.load(URLRequest(url: start))
        await waitLoaded(t)
        var history: [String] = []
        for stepNo in 1...25 {
            guard await holdIfPaused(t) else { return "Stopped." }
            guard let page = await read(t) else { t.say("Couldn't read the page"); continue }
            let items = (page["items"] as? [[String: Any]]) ?? []
            let list = items.map { i -> String in
                let id = i["id"] as? Int ?? 0, tag = i["tag"] as? String ?? "", type = i["type"] as? String ?? "", text = i["text"] as? String ?? ""
                return "[\(id)] \(tag)\(type.isEmpty ? "" : "(\(type))") \(text)"
            }.joined(separator: "\n")
            let prompt = """
            TASK: \(task)
            STEPS SO FAR:
            \(history.isEmpty ? "none" : history.suffix(10).joined(separator: "\n"))
            PAGE: \(page["title"] as? String ?? "") — \(page["url"] as? String ?? "")
            ELEMENTS:
            \(list.prefix(9000))
            VISIBLE TEXT:
            \((page["text"] as? String ?? "").prefix(3000))
            """
            guard let raw = await AIService.shared.textAnswer(system: Self.rules, messages: [["role": "user", "content": prompt]], max: 400),
                  let a = AIService.jsonIn(raw) as? [String: Any], let action = a["action"] as? String else {
                t.say("The AI didn't answer — stopping"); t.status = "Stopped"
                return "I couldn't reach an AI to work the page. Nothing was done after step \(stepNo - 1)."
            }
            let say = (a["say"] as? String) ?? action
            let id = (a["id"] as? Int) ?? Int((a["id"] as? String) ?? "") ?? 0
            let item = items.first { ($0["id"] as? Int) == id }
            let itemText = (item?["text"] as? String ?? "").lowercased()
            // risky? (the AI says so, or the button says buy / pay / send / post / delete…)
            let riskyWords = itemText.range(of: #"\b(buy|pay|place order|checkout|purchase|send|post|publish|share|submit|delete|remove|confirm|book now|reserve|subscribe|sign up|transfer)\b"#, options: .regularExpression) != nil
            let secret = ["password"].contains(item?["type"] as? String ?? "") || (item?["ac"] as? String ?? "").hasPrefix("cc-") || itemText.range(of: #"card number|cvv|cvc|security code|one.time"#, options: .regularExpression) != nil
            if action == "type", secret {
                t.say("This needs your password or card details — please type it yourself")
                t.takeover = true; t.status = "You're in control"
                MacStatus.shared.toast("\(agent.emoji) \(agent.name): your turn", "Please type your details in its tab, then press “Give back”.", icon: "lock.fill")
                show(t.id)
                history.append("Asked the user to type private details")
                continue
            }
            if ((a["risky"] as? Bool) == true || ((action == "click" || action == "type") && riskyWords)) {
                let ok = await approve(t, "\(say) — on \(t.web.url?.host ?? "this site")")
                if !ok { history.append("User said NO to: \(say)"); t.say("You said no — skipping that"); continue }
            }
            t.say(say)
            history.append("\(stepNo). \(action) \(id > 0 ? "[\(id)] \(itemText.prefix(40))" : "") \(a["text"] as? String ?? a["url"] as? String ?? "")")
            switch action {
            case "click":
                let r = await js(t, "(() => { const el = document.querySelector('[data-zid=\"\(id)\"]'); if (!el) return 'missing'; el.scrollIntoView({block:'center'}); el.focus(); el.click(); return 'ok'; })()")
                if r != "ok" { history.append("(that element wasn't there)") }
                await waitLoaded(t)
            case "type":
                let text = Self.q((a["text"] as? String) ?? "")
                let enter = (a["enter"] as? Bool) == true
                _ = await js(t, """
                (() => { const el = document.querySelector('[data-zid="\(id)"]'); if (!el) return 'missing'; el.scrollIntoView({block:'center'}); el.focus();
                  if (el.isContentEditable) { document.execCommand('selectAll', false); document.execCommand('insertText', false, \(text)); }
                  else { const p = Object.getPrototypeOf(el); const d = Object.getOwnPropertyDescriptor(p, 'value'); d && d.set ? d.set.call(el, \(text)) : (el.value = \(text));
                    el.dispatchEvent(new Event('input', {bubbles:true})); el.dispatchEvent(new Event('change', {bubbles:true})); }
                  \(enter ? "const k = {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true}; el.dispatchEvent(new KeyboardEvent('keydown', k)); el.dispatchEvent(new KeyboardEvent('keyup', k)); if (el.form) { el.form.requestSubmit ? el.form.requestSubmit() : el.form.submit(); }" : "")
                  return 'ok'; })()
                """)
                if enter { await waitLoaded(t) } else { try? await Task.sleep(nanoseconds: 300_000_000) }
            case "select":
                _ = await js(t, "(() => { const el = document.querySelector('[data-zid=\"\(id)\"]'); if (!el) return 'missing'; el.value = \(Self.q((a["value"] as? String) ?? "")); el.dispatchEvent(new Event('change', {bubbles:true})); return 'ok'; })()")
            case "scroll":
                _ = await js(t, "window.scrollBy(0, \((a["dir"] as? String) == "up" ? -700 : 700)); 'ok'")
                try? await Task.sleep(nanoseconds: 500_000_000)
            case "go":
                if let s = a["url"] as? String, let u = URL(string: s.hasPrefix("http") ? s : "https://" + s) { t.web.load(URLRequest(url: u)); await waitLoaded(t) }
            case "back":
                t.web.goBack(); await waitLoaded(t)
            case "wait":
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            case "ask":
                let qn = (a["question"] as? String) ?? "I need your help on this page."
                t.say("Asks you: \(qn)")
                t.takeover = true; t.status = "You're in control"
                MacStatus.shared.toast("\(agent.emoji) \(agent.name) needs you", qn, icon: "questionmark.circle.fill")
                show(t.id)
                history.append("Asked the user: \(qn) (they handled it in the tab)")
            case "done":
                let ans = (a["answer"] as? String) ?? "Done."
                t.status = "Done"
                return ans + "\n\n(Page: \(t.web.url?.absoluteString ?? ""))"
            default:
                history.append("(unknown action \(action))")
            }
        }
        t.status = "Stopped"
        return "I stopped after 25 steps without finishing. The tab is still open in the agent browser so you can carry on."
    }

    /// Opens a page in the agent's own tab and reads what's on it (results that load after the page do too).
    /// Google's cookie screen is answered with "Reject all".
    func readPage(_ url: URL, agent: TeamAgent, runID: String?) async -> (text: String, url: String) {
        let t = BrowserTab(agent: agent, task: "Reading \(url.host ?? "a page")", store: store)
        t.runID = runID
        tabs.append(t)
        if selected == nil || tabs.count == 1 { selected = t.id }
        t.status = "Working"
        t.say("Opening \(url.host ?? url.absoluteString)")
        t.web.load(URLRequest(url: url))
        await waitLoaded(t)
        if (t.web.url?.host ?? "").contains("consent.") {
            let r = await js(t, "(() => { const b = [...document.querySelectorAll('button,input[type=submit]')].find(x => /reject all|decline all|reject/i.test(x.innerText || x.value || '')); if (b) { b.click(); return 'ok'; } return 'none'; })()")
            if r == "ok" { t.say("Said no to extra cookies"); await waitLoaded(t) }
        }
        var text = ""
        for i in 0..<10 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            text = await js(t, "document.body ? document.body.innerText : ''")
            if text.count > 3000 || (i > 4 && text.range(of: #"[£$€]\s?\d|Rs\.?\s?\d|PKR"#, options: .regularExpression) != nil) { break }
        }
        _ = await js(t, "window.scrollBy(0, 1400); 'ok'")
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        let more = await js(t, "document.body ? document.body.innerText : ''")
        if more.count > text.count { text = more }
        t.say(text.count > 400 ? "Read the page" : "The page showed almost nothing")
        t.status = "Done"
        return (String(text.prefix(16000)), t.web.url?.absoluteString ?? url.absoluteString)
    }

    /// Where to start: a site named in the task, else a web search.
    static func startURL(_ task: String) -> URL {
        let l = task.lowercased()
        if let r = l.range(of: #"(https?://\S+|\b[a-z0-9-]+\.(com|co\.uk|org|net|io|ai|uk)\S*)"#, options: .regularExpression) {
            let s = String(l[r]); if let u = URL(string: s.hasPrefix("http") ? s : "https://" + s) { return u }
        }
        let q = task.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? task
        return URL(string: "https://www.google.com/search?q=\(q)") ?? URL(string: "https://www.google.com")!
    }
}

/// Shows one tab's live page.
struct BrowserTabWeb: NSViewRepresentable {
    let web: WKWebView
    func makeNSView(context: Context) -> NSView { let v = NSView(); host(v); return v }
    func updateNSView(_ v: NSView, context: Context) { host(v) }
    private func host(_ v: NSView) {
        guard web.superview !== v else { return }
        web.removeFromSuperview()
        web.translatesAutoresizingMaskIntoConstraints = true
        web.frame = v.bounds; web.autoresizingMask = [.width, .height]
        v.addSubview(web)
    }
}

struct AgentBrowserView: View {
    @ObservedObject private var browser = AgentBrowser.shared
    var body: some View {
        HStack(spacing: 0) {
            // agents (tabs)
            VStack(alignment: .leading, spacing: 6) {
                Text("Agents at work").font(.system(size: 13, weight: .bold)).padding(.top, 34).padding(.horizontal, 12)
                if browser.tabs.isEmpty {
                    Text("When an agent works on a website, its tab appears here. Try: “Web Helper, find the cheapest train from London to Manchester tomorrow”.")
                        .font(.system(size: 11)).foregroundColor(.secondary).padding(12)
                }
                ScrollView {
                    VStack(spacing: 4) { ForEach(browser.tabs) { t in TabRow(tab: t, on: browser.selected == t.id) { browser.selected = t.id } } }.padding(.horizontal, 8)
                }
                Spacer()
            }
            .frame(width: 250).background(Color.black.opacity(0.25))
            Divider()
            if let t = browser.tabs.first(where: { $0.id == browser.selected }) { TabDetail(tab: t) }
            else { Spacer(); Text("No agent selected").foregroundColor(.secondary); Spacer() }
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    struct TabRow: View {
        @ObservedObject var tab: BrowserTab
        let on: Bool
        let pick: () -> Void
        var body: some View {
            Button(action: pick) {
                HStack(spacing: 8) {
                    AgentAvatar(agent: tab.agent, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.agent.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(tab.status + " · " + (tab.steps.last ?? tab.task)).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Circle().fill(tab.status == "Done" ? Color.green : tab.status == "Needs you" || tab.status == "You're in control" ? Color.orange : tab.status == "Stopped" ? Color.gray : AgentField.of(tab.agent).color).frame(width: 8, height: 8)
                }
                .padding(8).background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.white.opacity(0.1) : .clear))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    struct TabDetail: View {
        @ObservedObject var tab: BrowserTab
        @ObservedObject private var browser = AgentBrowser.shared
        var body: some View {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button { tab.web.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!tab.web.canGoBack)
                        Button { tab.web.reload() } label: { Image(systemName: "arrow.clockwise") }
                        Text(tab.url.isEmpty ? tab.task : tab.url).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                            .padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).frame(height: 26).background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                        if tab.takeover {
                            Button("Give back to \(tab.agent.name)") { tab.takeover = false; tab.status = "Working"; tab.say("You gave control back") }.buttonStyle(.borderedProminent)
                        } else {
                            Button("Take over") { tab.takeover = true; tab.status = "You're in control"; tab.say("You took over") }
                        }
                        Button(tab.paused ? "Resume" : "Pause") { tab.paused.toggle(); tab.status = tab.paused ? "Paused" : "Working" }
                        Button { browser.close(tab) } label: { Image(systemName: "xmark") }.help("Stop and close this tab")
                    }
                    .controlSize(.small).padding(.horizontal, 10).padding(.top, 30).padding(.bottom, 8)
                    if let q = tab.asking {
                        HStack(spacing: 10) {
                            Image(systemName: "hand.raised.fill").foregroundColor(.orange)
                            Text("\(tab.agent.name) wants to: \(q)").font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button("No") { browser.reply(tab, false) }
                            Button("Yes, go ahead") { browser.reply(tab, true) }.buttonStyle(.borderedProminent).tint(.orange)
                        }
                        .padding(10).background(Color.orange.opacity(0.15))
                    }
                    BrowserTabWeb(web: tab.web)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) { AgentAvatar(agent: tab.agent, size: 30); VStack(alignment: .leading, spacing: 1) { Text(tab.agent.name).font(.system(size: 12.5, weight: .bold)); Text(tab.status).font(.system(size: 10.5)).foregroundColor(.secondary) } }
                    Text(tab.task).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(tab.steps.enumerated()), id: \.offset) { i, s in
                                HStack(alignment: .top, spacing: 6) { Text("\(i + 1).").font(.system(size: 10, weight: .bold)).foregroundColor(.secondary).frame(width: 20, alignment: .trailing); Text(s).font(.system(size: 11)) }
                            }
                        }
                    }
                }
                .padding(12).padding(.top, 22).frame(width: 260)
            }
        }
    }
}

// MARK: - Workspace: brand brief from a chat, the Manager's plan, approvals, the first jobs and routines

struct BrandBrief: Codable, Equatable {
    var business = "", kind = "", town = "", audience = "", tone = "", colours = "", offers = "", goals = "", accounts = "", postsPerWeek = 4, extra = ""
    var isEmpty: Bool { business.isEmpty && offers.isEmpty }
    var text: String {
        [("Business", business), ("Type", kind), ("Town / area", town), ("Customers", audience), ("Tone", tone), ("Brand colours", colours),
         ("Services, prices & offers", offers), ("Goals", goals), ("Accounts", accounts), ("Posts per week", "\(postsPerWeek)"), ("Notes", extra)]
            .filter { !$0.1.isEmpty }.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
    }
}

/// Something an agent wants to do that waits for the owner: a post, a review reply, a message.
struct ApprovalItem: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var agent: String
    var kind: String                 // post · review reply · message
    var title: String
    var body: String                 // caption / reply text
    var extra = ""                   // hashtags, who it's for, the review being answered…
    var when = ""                    // planned day
    var image: String?               // file path of the picture
    var status = "Waiting"           // Waiting · Approved · Done · Skipped
    var created = Date()
}

@MainActor
final class ZuffiWorkspace: ObservableObject {
    static let shared = ZuffiWorkspace()
    @Published var brief: BrandBrief = TeamStore.load("brand", BrandBrief()) { didSet { TeamStore.save("brand", brief); syncInfo() } }
    @Published var approvals: [ApprovalItem] = TeamStore.load("approvals", [ApprovalItem]()) { didSet { TeamStore.save("approvals", Array(approvals.prefix(200))) } }
    @Published var busy = ""
    var waiting: [ApprovalItem] { approvals.filter { $0.status == "Waiting" } }

    /// The brief also goes into the business details every agent and reply uses.
    private func syncInfo() {
        guard !brief.isEmpty else { return }
        if brief.business.count > 1, ZuffiBusiness.shared.businessName.isEmpty {
            ZuffiBusiness.shared.businessName = brief.business; UserDefaults.standard.set(brief.business, forKey: "zuffiBusinessName")
        }
        let marker = "\n— Brand brief —\n"
        let base = ZuffiCRM.shared.businessInfo.components(separatedBy: marker).first ?? ""
        ZuffiCRM.shared.businessInfo = base.trimmingCharacters(in: .whitespacesAndNewlines) + marker + brief.text
    }

    // MARK: the chat that sets everything up

    static let questions: [(key: String, ask: String, hint: String)] = [
        ("business", "Hi! I'm your Team Manager. What's your business called, and what do you do?", "e.g. Glow Studio — a nail and beauty salon"),
        ("town", "Where are you based, and who are your customers?", "e.g. Woking — mostly women 25–45, office workers, mums"),
        ("offers", "What do you sell or offer, with prices and any current offers?", "e.g. Gel nails £30, BIAB £38, 10% off Tuesdays"),
        ("tone", "How should your posts sound, and what are your brand colours?", "e.g. friendly and fun, pink and gold"),
        ("goals", "What do you want more of in the next 3 months?", "e.g. 10 more bookings a week, more Google reviews"),
        ("accounts", "Which accounts do you use? (Instagram, Facebook, Google Business Profile, TikTok, LinkedIn, Fresha…)", "e.g. Instagram @glowstudio, Facebook page, Google Business"),
        ("postsPerWeek", "How many posts a week should we make? (3, 5 or 7)", "e.g. 5"),
    ]

    func apply(_ key: String, _ v: String) {
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        switch key {
        case "business":
            brief.business = t.components(separatedBy: CharacterSet(charactersIn: "—-,")).first?.trimmingCharacters(in: .whitespaces) ?? t
            brief.kind = t
        case "town": brief.town = t; brief.audience = t
        case "offers": brief.offers = t
        case "tone": brief.tone = t; brief.colours = t
        case "goals": brief.goals = t
        case "accounts": brief.accounts = t
        case "postsPerWeek": brief.postsPerWeek = max(2, min(7, Int(t.filter(\.isNumber)) ?? 4))
        default: brief.extra = t
        }
    }

    /// After the chat: the AI tidies the answers, then the Manager proposes the team and sets the routines.
    func finishSetup() async -> String {
        busy = "Setting up your workspace…"; defer { busy = "" }
        if let j = await AIService.shared.fastJSON("Answers:\n\(brief.text)", system: """
        Tidy a small business's setup answers into JSON: {"business":"just the name","kind":"what it is, short","town":"","audience":"","tone":"","colours":"","offers":"","goals":""}. \
        Keep the owner's facts and prices exactly; "" when not given.
        """) {
            func s(_ k: String) -> String { (j[k] as? String ?? "").trimmingCharacters(in: .whitespaces) }
            var b = brief
            if !s("business").isEmpty { b.business = s("business") }
            for (k, path) in [("kind", \BrandBrief.kind), ("town", \BrandBrief.town), ("audience", \BrandBrief.audience), ("tone", \BrandBrief.tone),
                              ("colours", \BrandBrief.colours), ("offers", \BrandBrief.offers), ("goals", \BrandBrief.goals)] where !s(k).isEmpty { b[keyPath: path] = s(k) }
            brief = b
        }
        let team = ZuffiTeam.shared
        let ids: [String] = {
            switch ZuffiPlan.shared.mode {
            case .freelancer?: return ["zuffi-social", "zuffi-writer", "zuffi-competitors", "zuffi-reports"]
            case .creator?: return ["zuffi-social", "research-synthesist", "zuffi-writer", "zuffi-reports"]
            case .personal?: return ZuffiTeam.personalTeam
            default: return ZuffiTeam.businessTeam
            }
        }()
        for id in ids { if let a = team.agent(id) { team.hire(a, why: "Team Manager's plan") } }
        setRoutines()
        team.log("Team Manager", "Set up the workspace", brief.business)
        let names = ids.compactMap { team.agent($0) }.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ")
        return "Your workspace for \(brief.business.isEmpty ? "your business" : brief.business) is ready.\nTeam: \(names).\nEvery Monday the Social Media Agent plans \(brief.postsPerWeek) posts for you to approve; reviews are checked every morning; competitors on Wednesday; your report on Friday. Want this week's posts now? Press “Plan this week's posts”."
    }

    /// The routines every business gets (changeable on My Team → Daily jobs).
    func setRoutines() {
        let team = ZuffiTeam.shared
        func job(_ agent: String, _ title: String, _ task: String, _ h: Int, _ m: Int, _ weekday: Int?) {
            guard team.agent(agent) != nil, !team.jobs.contains(where: { $0.agent == agent && $0.title == title }) else { return }
            var j = TeamJob(agent: agent, title: title, task: task, hour: h, minute: m)
            j.weekday = weekday
            team.jobs.removeAll { $0.agent == agent && $0.weekday == nil && agent != "zuffi-reviews" }
            team.jobs.append(j)
        }
        job("zuffi-social", "Plan this week's posts", "plan posts", 9, 0, 2)          // Monday
        job("zuffi-reviews", "Check new reviews", "check reviews", 10, 0, nil)         // every day
        job("zuffi-competitors", "Competitor check", "Research my local competitors this week: prices, offers, reviews — what do they do better, and what should we change?", 11, 0, 4)   // Wednesday
        job("zuffi-reports", "Weekly report", "Write this week's report: what the team did, what worked, and next week's plan.", 16, 0, 6)   // Friday
    }

    // MARK: job 1 — posts

    func planPosts(count: Int? = nil, runID: String? = nil) async -> String {
        let n = count ?? brief.postsPerWeek
        let team = ZuffiTeam.shared
        busy = "📣 Planning \(n) posts…"; defer { busy = "" }
        let cal = Calendar.current
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: Date()) }.map { $0.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) }
        let prompt = """
        BRAND BRIEF:
        \(brief.isEmpty ? ZuffiCRM.shared.businessInfo.prefix(2000) : Substring(brief.text))
        Today's offer/news: \(ZuffiCRM.shared.todaysUpdate.isEmpty ? "none" : ZuffiCRM.shared.todaysUpdate)
        The next 7 days: \(days.joined(separator: ", ")). Country: \(ZuffiCRM.shared.country == "PK" ? "Pakistan" : "UK").
        Plan \(n) social media posts for these days. Use UK dates and seasons that fall in this week where relevant. Never invent prices or offers that aren't in the brief.
        JSON: {"posts":[{"day":"one of the days above","idea":"short title","caption":"the full caption, warm, in the brand's tone, with a call to action","hashtags":"#… #…","picture":"what the picture should show, no text in it"}]}
        """
        if let r = runID { team.step(r, "Planning \(n) posts from your brand brief", source: "Brand brief") }
        guard let j = await AIService.shared.fastJSON(prompt, system: "You are a social media manager for a small business. Reply with JSON only."),
              let posts = j["posts"] as? [[String: Any]], !posts.isEmpty else {
            return "I couldn't plan the posts — no AI answered. Nothing was made up; try again in a minute."
        }
        var made = 0
        for p in posts.prefix(n) {
            func s(_ k: String) -> String { (p[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
            var item = ApprovalItem(agent: "zuffi-social", kind: "post", title: s("idea"), body: s("caption"), extra: s("hashtags"), when: s("day"))
            if let r = runID { team.step(r, "Making the picture for “\(s("idea").prefix(50))”") }
            if let img = await WebHub.shared.callJS("return await window.Sparrow.makeBizPost(a, 'post', c)", ["a": s("idea") + ". " + s("picture"), "c": "Book now — link in bio"]) as? [String: Any],
               let b64 = img["b64"] as? String, let data = Data(base64Encoded: b64) {
                let dir = ZuffiBusiness.docs.appendingPathComponent("Posts", isDirectory: true)
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let url = dir.appendingPathComponent((img["name"] as? String) ?? "post-\(UUID().uuidString.prefix(6)).png")
                if (try? data.write(to: url)) != nil { item.image = url.path }
            }
            approvals.insert(item, at: 0); made += 1
        }
        team.log("Social Media Agent", "Planned \(made) posts", "Waiting for your approval")
        MacStatus.shared.toast("📣 \(made) posts ready", "Open My Team → Approvals to approve them.", icon: "megaphone.fill")
        return "I've planned \(made) posts for this week, each with a picture and caption. They're waiting in My Team → Approvals."
    }

    /// Approving a post: save it, copy the caption, and the Social Media Agent opens Meta Business Suite in its tab to fill it in.
    /// (Direct posting through Meta's official connection comes once Zuffi's Meta approval is done.)
    func publish(_ item: ApprovalItem) async {
        guard let i = approvals.firstIndex(where: { $0.id == item.id }) else { return }
        approvals[i].status = "Approved"
        let caption = item.body + (item.extra.isEmpty ? "" : "\n\n" + item.extra)
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(caption, forType: .string)
        ZuffiTeam.shared.log("You", "Approved a post", item.title)
        guard let agent = ZuffiTeam.shared.agent("zuffi-social") else { return }
        let task = """
        Go to https://business.facebook.com/latest/composer and create a new post for the user's Facebook page and Instagram. Type this caption into the post text box: \(caption.prefix(1500))
        Then use "ask" so the user adds the photo (it's saved at \(item.image ?? "Documents/Zuffi/Posts")) and checks it. Do NOT press Publish or Schedule yourself — ask first.
        """
        let id = ZuffiTeam.shared.begin(agent, "Post: \(item.title)")
        ZuffiTeam.shared.step(id, "Caption copied; opening Meta Business Suite in its tab")
        let ans = await AgentBrowser.shared.run(task, agent: agent, runID: id)
        ZuffiTeam.shared.finish(id, ans, "Done")
        if let k = approvals.firstIndex(where: { $0.id == item.id }) { approvals[k].status = "Done" }
        AgentBrowser.shared.show()
    }

    // MARK: job 2 — reviews

    func checkReviews(runID: String? = nil) async -> String {
        guard let agent = ZuffiTeam.shared.agent("zuffi-reviews") else { return "No Reviews Agent." }
        let task = """
        Open https://business.google.com/reviews (if a sign-in is needed, use "ask"). Read the newest reviews.
        Finish with "done" and in "answer" give ONLY JSON: {"reviews":[{"name":"","stars":5,"text":"","replied":false}]} (up to 10, newest first).
        """
        if let r = runID { ZuffiTeam.shared.step(r, "Opening Google reviews in its own tab", source: "Google Business Profile") }
        let ans = await AgentBrowser.shared.run(task, agent: agent, runID: runID)
        guard let j = AIService.jsonIn(ans) as? [String: Any], let reviews = j["reviews"] as? [[String: Any]] else {
            return "I couldn't read your reviews yet: \(ans.prefix(200))\nOpen the agent browser and sign in to Google once — next time it works by itself."
        }
        let fresh = reviews.filter { !(($0["replied"] as? Bool) ?? false) }
        var drafted = 0
        for r in fresh.prefix(6) {
            let name = r["name"] as? String ?? "a customer", text = r["text"] as? String ?? "", stars = r["stars"] as? Int ?? 0
            if approvals.contains(where: { $0.kind == "review reply" && $0.extra.contains(text.prefix(60)) }) { continue }
            let reply = await AIService.shared.textAnswer(system: ZuffiTeam.shared.systemPrompt(for: agent), messages: [["role": "user", "content": "Draft a reply to this \(stars)-star review from \(name): “\(text)”. Reply text only, 1-3 sentences."]], max: 200) ?? ""
            guard !reply.isEmpty else { continue }
            approvals.insert(ApprovalItem(agent: agent.id, kind: "review reply", title: "Reply to \(name) (\(stars)★)", body: ZuffiTeam.plain(reply), extra: "“\(text.prefix(300))”"), at: 0)
            drafted += 1
        }
        ZuffiTeam.shared.log(agent.name, "Checked reviews", "\(reviews.count) read, \(drafted) replies drafted")
        return "Read \(reviews.count) review\(reviews.count == 1 ? "" : "s"); \(fresh.count) without a reply. I drafted \(drafted) repl\(drafted == 1 ? "y" : "ies") — they're in Approvals."
    }

    func sendReviewReply(_ item: ApprovalItem) async {
        guard let i = approvals.firstIndex(where: { $0.id == item.id }), let agent = ZuffiTeam.shared.agent("zuffi-reviews") else { return }
        approvals[i].status = "Approved"
        ZuffiTeam.shared.log("You", "Approved a review reply", item.title)
        let task = "Open https://business.google.com/reviews, find the review \(item.extra.prefix(120)) and type this reply: \(item.body). Use \"ask\" before pressing the final Reply / Post button."
        let id = ZuffiTeam.shared.begin(agent, item.title)
        let ans = await AgentBrowser.shared.run(task, agent: agent, runID: id)
        ZuffiTeam.shared.finish(id, ans, "Done")
        if let k = approvals.firstIndex(where: { $0.id == item.id }) { approvals[k].status = "Done" }
    }
}

/// My Team → Approvals: everything waiting for your yes.
struct TeamApprovalsView: View {
    @ObservedObject private var ws = ZuffiWorkspace.shared
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var editing: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Approvals").font(.system(size: 15, weight: .bold, design: .rounded))
                Text("\(ws.waiting.count) waiting").font(.system(size: 11, weight: .semibold)).foregroundColor(Ink.muted)
                Spacer()
                if !ws.busy.isEmpty { ProgressView().controlSize(.small); Text(ws.busy).font(.system(size: 11)).foregroundColor(Ink.muted) }
                Button("Plan this week's posts") { Task { @MainActor in _ = await ws.planPosts() } }.disabled(!ws.busy.isEmpty)
                Button("Check reviews") { Task { @MainActor in _ = await ws.checkReviews() } }.disabled(!ws.busy.isEmpty)
            }
            .controlSize(.small)
            Text("Posts and replies your agents made. Nothing goes out until you approve. Approving a post copies the caption and the Social Media Agent fills it in on Meta Business Suite in its own tab — you add the photo and press Publish. (Posting straight from Zuffi comes after Meta's approval.)")
                .font(.system(size: 11)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
            if ws.approvals.isEmpty { Text("Nothing yet. Press “Plan this week's posts”.").font(.system(size: 12)).foregroundColor(Ink.faint) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach($ws.approvals) { $it in card($it) }
            }
        }
        .padding(16).zGlass(16)
    }

    @ViewBuilder private func card(_ it: Binding<ApprovalItem>) -> some View {
        let item = it.wrappedValue
        let a = team.agent(item.agent)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let a { AgentAvatar(agent: a, size: 26) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
                    Text([item.kind.capitalized, item.when].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10.5)).foregroundColor(Ink.faint)
                }
                Spacer()
                StatusDot(text: item.status, color: item.status == "Waiting" ? Color(hex: "#F2A516") : item.status == "Skipped" ? Color(hex: "#8A92A4") : Color(hex: "#3FC48C"))
            }
            if let p = item.image, let img = NSImage(contentsOfFile: p) {
                Image(nsImage: img).resizable().scaledToFill().frame(height: 170).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
            }
            if editing == item.id {
                TextField("Text", text: it.body, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(3...10)
                if item.kind == "post" { TextField("Hashtags", text: it.extra).textFieldStyle(.roundedBorder) }
            } else {
                Text(item.body).font(.system(size: 11.5)).foregroundColor(Ink.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).lineLimit(8)
                if !item.extra.isEmpty { Text(item.extra).font(.system(size: 10.5)).foregroundColor(Ink.muted).lineLimit(3) }
            }
            if item.status == "Waiting" {
                HStack {
                    Button(item.kind == "post" ? "Approve & post" : "Approve & send") {
                        Task { @MainActor in if item.kind == "post" { await ws.publish(item) } else { await ws.sendReviewReply(item) } }
                    }.buttonStyle(.borderedProminent).tint(Ink.accent)
                    Button(editing == item.id ? "Done" : "Edit") { editing = editing == item.id ? nil : item.id }
                    Spacer()
                    Button("Skip") { it.wrappedValue.status = "Skipped"; team.log("You", "Skipped", item.title) }
                }
                .controlSize(.small)
            }
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi.opacity(0.7)))
    }
}

/// The Team Manager's setup chat (first time on My Team).
struct OnboardingChat: View {
    @ObservedObject private var ws = ZuffiWorkspace.shared
    @State private var step = 0
    @State private var answer = ""
    @State private var log: [(Bool, String)] = []       // (from Zuffi, text)
    @State private var finished = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Buddy3DView(kind: .robot(.manager), mood: ws.busy.isEmpty ? .speaking : .working).frame(width: 80, height: 90)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let's set up your workspace").font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Seven quick questions. Your team uses the answers in every post, reply and report.").font(.system(size: 11.5)).foregroundColor(Ink.muted)
                }
            }
            ForEach(Array(log.enumerated()), id: \.offset) { _, m in
                HStack { if !m.0 { Spacer(minLength: 60) }
                    Text(m.1).font(.system(size: 12)).padding(10).background(RoundedRectangle(cornerRadius: 12).fill(m.0 ? Ink.panelHi : Ink.accent.opacity(0.22))).textSelection(.enabled)
                    if m.0 { Spacer(minLength: 60) } }
            }
            if step < ZuffiWorkspace.questions.count {
                let q = ZuffiWorkspace.questions[step]
                HStack { Text(q.ask).font(.system(size: 12.5, weight: .semibold)).padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi)); Spacer(minLength: 60) }
                HStack {
                    TextField(q.hint, text: $answer).textFieldStyle(.roundedBorder).onSubmit(send)
                    Button("Send", action: send).buttonStyle(.borderedProminent).tint(Ink.accent).disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if finished.isEmpty {
                HStack { ProgressView().controlSize(.small); Text(ws.busy.isEmpty ? "Finishing…" : ws.busy).font(.system(size: 12)).foregroundColor(Ink.muted) }
            } else {
                Text(finished).font(.system(size: 12.5)).padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi))
                Button("Plan this week's posts") { Task { @MainActor in _ = await ws.planPosts() } }.buttonStyle(.borderedProminent).tint(Ink.accent)
            }
        }
        .padding(18).zGlass(18)
    }
    private func send() {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines); guard !a.isEmpty, step < ZuffiWorkspace.questions.count else { return }
        let q = ZuffiWorkspace.questions[step]
        log.append((true, q.ask)); log.append((false, a))
        ws.apply(q.key, a); answer = ""; step += 1
        if step == ZuffiWorkspace.questions.count { Task { @MainActor in finished = await ws.finishSetup() } }
    }
}

// MARK: - Under the notch: music bars and your working agents (never in the way)
//
// A thin strip that hangs just under the notch. When any app plays sound (music, YouTube, a call…) small bars dance;
// when agents are working, their little faces show next to it. It lets clicks pass through unless you click a face.

@MainActor
final class NotchHang: ObservableObject {
    static let shared = NotchHang()
    @Published var audio = false
    @Published var working: [AgentRun] = []
    private var panel: NSPanel?
    private var timer: Timer?
    private var watch: AnyCancellable?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in MainActor.assumeIsolated { NotchHang.shared.tick() } }
        watch = ZuffiTeam.shared.$runs.receive(on: RunLoop.main).sink { runs in
            MainActor.assumeIsolated { NotchHang.shared.working = runs.filter { $0.status == "Working" && $0.agent != ZuffiTeam.manager.id && Date().timeIntervalSince($0.started) < 900 } }
        }
    }

    /// Is any app playing sound right now? (the default output device is running)
    nonisolated static func soundPlaying() -> Bool {
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private func tick() {
        let on = UserDefaults.standard.object(forKey: "notchHang") as? Bool ?? true
        audio = false                    // no sound bars on the notch (kept for later)
        _ = on
        // with the glass wings the closed notch shows this itself; the strip is only for when Zuffi is fully hidden
        layout(show: on && (audio || !working.isEmpty) && (NotchDesign.on ? AppState.shared.mode == .hidden : AppState.shared.mode != .expanded))
    }

    private func layout(show: Bool) {
        guard show, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { panel?.orderOut(nil); return }
        let top = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : (screen.frame.maxY - screen.visibleFrame.maxY)
        var notchW: CGFloat = 200
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea { notchW = max(120, screen.frame.width - l.width - r.width) }
        let w = max(notchW, CGFloat(working.count) * 26 + (audio ? 70 : 0) + 24), h: CGFloat = 26
        let p = panel ?? make()
        panel = p
        p.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - top - h, width: w, height: h), display: true)
        p.ignoresMouseEvents = working.isEmpty            // click-through unless there are faces to click
        if !p.isVisible { p.orderFrontRegardless() }
    }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 26), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.contentView = NSHostingView(rootView: NotchHangView())
        return p
    }
}

/// Dancing bars shown beside the notch while sound plays.
struct NotchBars: View {
    var count = 14
    var width: CGFloat = 2.5
    var height: CGFloat = 18
    private static let ink = LinearGradient(colors: [Color(hex: "#F58FA8"), Color(hex: "#B98CFF")], startPoint: .top, endPoint: .bottom)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24)) { tl in
            let t: Double = tl.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule().fill(Self.ink).frame(width: width, height: barHeight(i, t))
                }
            }
        }
        .frame(height: height)
    }
    private func barHeight(_ i: Int, _ t: Double) -> CGFloat {
        let speed: Double = 3.1 + Double(i % 5) * 0.9
        let v: Double = 0.35 + 0.65 * abs(sin(t * speed + Double(i) * 1.3))
        return CGFloat(4.0 + (Double(height) - 4.0) * v)
    }
}

struct NotchHangView: View {
    @ObservedObject private var hang = NotchHang.shared
    @ObservedObject private var team = ZuffiTeam.shared
    var body: some View {
        HStack(spacing: 8) {
            if hang.audio { NotchBars() }
            ForEach(hang.working.prefix(6)) { r in face(r) }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 1)
    }
    @ViewBuilder private func face(_ r: AgentRun) -> some View {
        if let a = team.agent(r.agent) {
            let c: Color = AgentField.of(a).color
            let tip: String = a.name + ": " + (r.steps.last?.text ?? r.task)
            AgentAvatar(agent: a, size: 20)
                .overlay(Circle().stroke(c, lineWidth: 1.5).scaleEffect(1.25).opacity(0.7))
                .onTapGesture { MissionControl.shared.show() }
                .help(tip)
        }
    }
}

// MARK: - Mission window: watch the Manager give out the work and each agent do it

@MainActor
final class MissionControl: ObservableObject {
    static let shared = MissionControl()
    @Published var question = ""
    @Published var agents: [String] = []
    @Published var started = Date.distantPast
    @Published var result: String?

    /// Give Nik a task: the window opens and the team gets to work (the answer shows here, not in the chat).
    func assign(_ q: String) {
        question = q; agents = []; result = nil; started = Date().addingTimeInterval(-1)
        ZuffiHub.shared.show(.office)
        Task { @MainActor in
            let r = await ZuffiTeam.shared.assignTask(q)
            // an agent that asked a question shows it in the office; otherwise the answer
            if ZuffiTeam.shared.awaiting == nil { MissionControl.shared.result = zClean(r) }
        }
    }
    private var window: NSWindow?
    var enabled: Bool { UserDefaults.standard.object(forKey: "missionWindow") as? Bool ?? true }

    func begin(_ q: String, agents ids: [String]) {
        if Date().timeIntervalSince(started) > 5 || question != q { started = Date().addingTimeInterval(-1); result = nil }
        question = q; agents = ids
        BunnyFaceCenter.shared.show(.thinking, for: 3)
        OfficeModel.shared.sync()
    }

    /// You answered an agent's question in the office: it carries on with the original task.
    func reply(_ text: String) {
        let team = ZuffiTeam.shared
        guard let w = team.awaiting else { return }
        team.awaiting = nil
        result = nil
        Task { @MainActor in
            let run = await team.work(w.agent, w.task + "\nMore details from the owner (already answered — don't ask these again): " + text)
            MissionControl.shared.result = zClean(run.status == "Needs input" ? "" : run.result).isEmpty ? nil : zClean(run.result)
        }
    }

    func show() {
        if ZuffiHub.oneWindow { ZuffiHub.shared.show(.office); return }
        if let w = window { w.orderFrontRegardless(); return }
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 430), styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        w.title = "Nik — your manager"; w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isReleasedWhenClosed = false
        w.isMovableByWindowBackground = true; w.level = .floating; w.hidesOnDeactivate = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.isOpaque = false; w.backgroundColor = .clear
        w.contentView = NSHostingView(rootView: MissionView())
        if let s = NSScreen.main?.visibleFrame { w.setFrameOrigin(NSPoint(x: s.midX - 380, y: s.maxY - 470)) }
        window = w
        w.orderFrontRegardless()
    }
}

struct MissionView: View {
    @ObservedObject private var mc = MissionControl.shared
    @ObservedObject private var team = ZuffiTeam.shared
    private var runs: [AgentRun] { team.runs.filter { $0.started >= mc.started && mc.agents.contains($0.agent) } }
    var body: some View {
        let rs = runs
        let done = mc.result != nil || (!rs.isEmpty && rs.allSatisfy { $0.status != "Working" })
        ZStack {
            VisualEffectBlur().overlay(LinearGradient(colors: [Color(hex: "#0B1020").opacity(0.75), Color(hex: "#151A2E").opacity(0.6)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 10) {
                // the manager
                HStack(spacing: 12) {
                    Buddy3DView(kind: .robot(.manager), mood: done ? .happy : .speaking).frame(width: 74, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nik · your manager").font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("“\(mc.question.prefix(140))”").font(.system(size: 12)).foregroundColor(.white.opacity(0.8)).lineLimit(2)
                        Text(done ? "All done — here's what the team found." : mc.agents.isEmpty ? "Choosing who should do this…" : "I gave this to " + mc.agents.compactMap { team.agent($0)?.name }.joined(separator: ", ") + ".")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundColor(done ? Color(hex: "#3FC48C") : Color(hex: "#F5B963"))
                    }
                    Spacer()
                }
                // beams from the manager to each agent
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    Canvas { ctx, size in
                        let n = max(1, mc.agents.count)
                        let from = CGPoint(x: size.width / 2, y: 0)
                        for i in 0..<n {
                            let to = CGPoint(x: size.width * (CGFloat(i) + 0.5) / CGFloat(n), y: size.height)
                            var p = Path(); p.move(to: from); p.addCurve(to: to, control1: CGPoint(x: from.x, y: size.height * 0.6), control2: CGPoint(x: to.x, y: size.height * 0.4))
                            let c = team.agent(mc.agents[min(i, mc.agents.count - 1)]).map { AgentField.of($0).color } ?? .white
                            ctx.stroke(p, with: .color(c.opacity(0.25)), lineWidth: 2)
                            ctx.stroke(p, with: .color(c.opacity(done ? 0.5 : 0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 10], dashPhase: done ? 0 : -tl.date.timeIntervalSinceReferenceDate * 40))
                        }
                    }
                }
                .frame(height: 36)
                // the agents
                HStack(alignment: .top, spacing: 12) {
                    ForEach(mc.agents, id: \.self) { id in
                        if let a = team.agent(id) {
                            let r = rs.first { $0.agent == id }
                            VStack(spacing: 6) {
                                Buddy3DView(kind: .robot(AgentField.of(a)), mood: r?.status == "Working" || r == nil ? .working : r?.status == "Done" ? .happy : .idle)
                                    .frame(width: 70, height: 80)
                                Text(a.name).font(.system(size: 11.5, weight: .bold)).lineLimit(1)
                                FieldChip(field: AgentField.of(a))
                                Text(r == nil ? "Starting…" : r!.status == "Working" ? (r!.steps.last?.text ?? "Working…") : r!.status)
                                    .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.75)).lineLimit(3).multilineTextAlignment(.center).frame(height: 40, alignment: .top)
                                if let r, !(r.links ?? []).isEmpty {
                                    Button("Links (\(r.links!.count))") { if let u = URL(string: r.links![0].url) { NSWorkspace.shared.open(u) } }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundColor(AgentField.of(a).color)
                                }
                                if AgentField.of(a) == .web { Button("Watch") { AgentBrowser.shared.show() }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundColor(AgentField.of(a).color) }
                            }
                            .padding(10).frame(width: 150)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AgentField.of(a).color.opacity(0.45)))
                        }
                    }
                }
                if mc.agents.isEmpty && mc.result == nil {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Nik is reading your task…").font(.system(size: 12.5)).foregroundColor(.white.opacity(0.8)) }
                        .padding(.top, 10)
                }
                if let r = mc.result {
                    ScrollView {
                        Text(r).font(.system(size: 12.5)).foregroundColor(.white.opacity(0.92)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12).frame(maxHeight: 150)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.top, 26).padding(.bottom, 14)
        }
        .foregroundColor(.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .frame(minWidth: 520, minHeight: 380)
    }
}

/// Zuffi's helpers on the notch: who's on your team and who's working.
struct NotchAgentsRow: View {
    @ObservedObject private var team = ZuffiTeam.shared
    var body: some View {
        let people = Array((team.hiredAgents.isEmpty ? team.focusAgents : team.hiredAgents).prefix(5))
        VStack(spacing: 4) {
            ForEach(people) { a in
                let st = team.status(a)
                AgentAvatar(agent: a, size: 18, status: st == .active ? nil : st)
                    .opacity(st == .working ? 1 : 0.75)
                    .help("\(a.name) — \(st.rawValue)")
                    .onTapGesture { if st == .working { MissionControl.shared.show() } else { team.use(a); ZuffiChat.shared.open() } }
            }
        }
    }
}

// =====================================================================
// MARK: - The Agent Office: watch Nik hand out the work and each agent do it
//
// A small, real-looking office in 3D (wood floor, desks, windows, plants, soft shadows). Each agent is a cute glossy robot
// in its field's colour with its own item (pilot cap, glasses, beret…). When you give a task, the office opens: Nik walks
// to the right desk, hands over the task card, the agent works (its screen shows what it's doing), asks you if something's
// missing, and the result appears with Copy and Save.
// =====================================================================

@MainActor
enum RobotLook {
    static func item(for a: TeamAgent) -> String {
        switch a.id {
        case ZuffiTeam.manager.id: return "tie"
        case "zuffi-travel": return "cap"
        case "zuffi-writer": return "beret"
        case "zuffi-web": return "globe"
        case "zuffi-docs": return "sheet"
        case "zuffi-social", "zuffi-instagram", "zuffi-facebook": return "megaphone"
        case "zuffi-whatsapp": return "heart"
        case "zuffi-reviews": return "star"
        case "zuffi-reports": return "chart"
        case "zuffi-bookings": return "calendar"
        case "zuffi-crm": return "heart"
        case "zuffi-competitors": return "glasses"
        default: return AgentField.of(a) == .research ? "glasses" : ""
        }
    }
    static func color(for a: TeamAgent) -> NSColor {
        if let c = AgentEdits.get(a.id).color, !c.isEmpty { return NSColor(Color(hex: c)).usingColorSpace(.deviceRGB) ?? .systemBlue }
        let hex: String
        switch a.id {
        case ZuffiTeam.manager.id: hex = "#F5B963"
        case "zuffi-travel": hex = "#33C3A4"
        case "zuffi-writer": hex = "#F07FAA"
        case "zuffi-web": hex = "#4C9BF5"
        case "zuffi-docs": hex = "#F2A23A"
        case "zuffi-social": hex = "#FF7A59"
        case "zuffi-instagram": hex = "#E1306C"
        case "zuffi-facebook": hex = "#1877F2"
        case "zuffi-whatsapp": hex = "#25D366"
        case "zuffi-reviews": hex = "#E8C24A"
        case "zuffi-reports": hex = "#3DBE7E"
        default: hex = AgentField.of(a) == .research ? "#9B7BFF" : AgentField.of(a).colors[0]
        }
        return NSColor(Color(hex: hex)).usingColorSpace(.deviceRGB) ?? .systemBlue
    }
}

/// Builds the robots and the room. Everything here runs on the main actor; the per-frame movement runs on SceneKit's thread.
struct OfficeRobot { let root: SCNNode; let body: SCNNode; let head: SCNNode; let hands: [SCNNode]; let eyes: [SCNNode]; let bubble: SCNNode }

@MainActor
enum OfficeBuilder {
    static func gloss(_ c: NSColor, rough: CGFloat = 0.18) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = c; m.roughness.contents = rough; m.metalness.contents = 0.0
        m.clearCoat.contents = 1.0; m.clearCoatRoughness.contents = 0.08
        return m
    }
    static func matte(_ c: NSColor, rough: CGFloat = 0.8) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased; m.diffuse.contents = c; m.roughness.contents = rough; m.metalness.contents = 0.0; return m
    }
    static func node(_ g: SCNGeometry, _ m: SCNMaterial, _ p: SCNVector3 = SCNVector3Zero, scale: SCNVector3 = SCNVector3(1, 1, 1)) -> SCNNode {
        g.materials = [m]; let n = SCNNode(geometry: g); n.position = p; n.scale = scale; n.castsShadow = true; return n
    }
    static func hex(_ h: String) -> NSColor { NSColor(Color(hex: h)).usingColorSpace(.deviceRGB) ?? .gray }


    /// One cute glossy robot: onion-round head with a white face, shiny eyes, a smile, an antenna, a little floating body and hands.
    static func robot(_ a: TeamAgent) -> OfficeRobot {
        let col = RobotLook.color(for: a)
        let root = SCNNode(), body = SCNNode(); root.addChildNode(body)
        let head = node(SCNSphere(radius: 0.6), gloss(col), SCNVector3(0, 1.15, 0), scale: SCNVector3(1.0, 0.9, 0.95))
        (head.geometry as? SCNSphere)?.segmentCount = 48
        body.addChildNode(head)
        let tip = node(SCNCone(topRadius: 0.0, bottomRadius: 0.26, height: 0.22), gloss(col), SCNVector3(0, 0.6, 0)); head.addChildNode(tip)
        head.addChildNode(node(SCNSphere(radius: 1), gloss(.white), SCNVector3(0, -0.05, 0.45), scale: SCNVector3(0.46, 0.36, 0.27)))
        let eyeM = gloss(hex("#111216"), rough: 0.05)
        var eyes: [SCNNode] = []
        for s in [-1.0, 1.0] as [CGFloat] {
            let e = node(SCNSphere(radius: 0.075), eyeM, SCNVector3(0.16 * s, -0.01, 0.7), scale: SCNVector3(1, 1.15, 0.6))
            let hl = SCNMaterial(); hl.lightingModel = .constant; hl.diffuse.contents = NSColor.white
            e.addChildNode(node(SCNSphere(radius: 0.022), hl, SCNVector3(0.025, 0.03, 0.05)))
            head.addChildNode(e); eyes.append(e)
        }
        let sp = NSBezierPath()
        sp.appendArc(withCenter: .zero, radius: 0.075, startAngle: 200, endAngle: 340, clockwise: false)
        sp.appendArc(withCenter: .zero, radius: 0.055, startAngle: 340, endAngle: 200, clockwise: true); sp.close()
        let smile = node(SCNShape(path: sp, extrusionDepth: 0.01), gloss(hex("#111216")), SCNVector3(0, -0.06, 0.71)); head.addChildNode(smile)
        let ant = SCNNode(); ant.position = SCNVector3(0, 0.68, 0); head.addChildNode(ant)
        ant.addChildNode(node(SCNCylinder(radius: 0.02, height: 0.18), gloss(.white), SCNVector3(0, 0.09, 0)))
        let ring = node(SCNTorus(ringRadius: 0.07, pipeRadius: 0.018), gloss(.white), SCNVector3(0, 0.08, 0)); ant.addChildNode(ring)
        ant.addChildNode(node(SCNSphere(radius: 0.075), gloss(col), SCNVector3(0, 0.22, 0)))
        body.addChildNode(node(SCNSphere(radius: 1), gloss(col), SCNVector3(0, 0.45, 0), scale: SCNVector3(0.3, 0.26, 0.26)))
        body.addChildNode(node(SCNSphere(radius: 0.06), gloss(.white), SCNVector3(0, 0.47, 0.25)))
        var hands: [SCNNode] = []
        for s in [-1.0, 1.0] as [CGFloat] {
            let h = node(SCNSphere(radius: 1), gloss(col), SCNVector3(0.42 * s, 0.5, 0.05), scale: SCNVector3(0.1, 0.16, 0.08))
            h.eulerAngles.z = 0.5 * s; body.addChildNode(h); hands.append(h)
        }
        let dark = gloss(hex("#22232B")), white = gloss(.white)
        switch RobotLook.item(for: a) {
        case "tie":
            let t = node(SCNCone(topRadius: 0.0, bottomRadius: 0.07, height: 0.22), gloss(hex("#2F3A67")), SCNVector3(0, 0.5, 0.27)); t.eulerAngles.x = .pi; body.addChildNode(t)
            for s in [-1.0, 1.0] as [CGFloat] { head.addChildNode(node(SCNSphere(radius: 0.1), dark, SCNVector3(0.6 * s, 0.0, 0))) }
            let band = node(SCNTorus(ringRadius: 0.6, pipeRadius: 0.03), dark, SCNVector3(0, 0, 0)); band.eulerAngles.z = .pi / 2; band.scale = SCNVector3(1, 1, 0.12); head.addChildNode(band)
        case "cap":
            head.addChildNode(node(SCNCylinder(radius: 0.44, height: 0.18), gloss(hex("#1F3B57")), SCNVector3(0, 0.52, 0)))
            head.addChildNode(node(SCNBox(width: 0.5, height: 0.03, length: 0.3, chamferRadius: 0.05), dark, SCNVector3(0, 0.44, 0.38)))
            head.addChildNode(node(SCNSphere(radius: 0.05), gloss(hex("#FFD34D")), SCNVector3(0, 0.55, 0.45)))
        case "glasses":
            for s in [-1.0, 1.0] as [CGFloat] { let r = node(SCNTorus(ringRadius: 0.1, pipeRadius: 0.014), dark, SCNVector3(0.16 * s, -0.01, 0.73)); r.eulerAngles.x = .pi / 2; head.addChildNode(r) }
        case "beret":
            head.addChildNode(node(SCNSphere(radius: 0.46), gloss(hex("#3A2A4A")), SCNVector3(-0.08, 0.52, 0), scale: SCNVector3(1, 0.3, 1)))
        case "globe":
            ant.addChildNode(node(SCNSphere(radius: 0.11), gloss(hex("#9CD3FF")), SCNVector3(0, 0.25, 0)))
        case "sheet":
            let sh = node(SCNBox(width: 0.34, height: 0.42, length: 0.03, chamferRadius: 0.02), white, SCNVector3(0.5, 0.42, 0.18)); sh.eulerAngles.z = -0.2
            for i in 0..<4 { sh.addChildNode(node(SCNBox(width: 0.22, height: 0.025, length: 0.01, chamferRadius: 0), gloss(col), SCNVector3(0, 0.12 - CGFloat(i) * 0.08, 0.02))) }
            body.addChildNode(sh)
        case "megaphone":
            let m = node(SCNCone(topRadius: 0.04, bottomRadius: 0.14, height: 0.3), white, SCNVector3(0.62, 0.55, 0.1)); m.eulerAngles.z = -.pi / 2; body.addChildNode(m)
        case "star":
            let st = NSBezierPath()
            for i in 0..<10 { let r: CGFloat = i % 2 == 1 ? 0.07 : 0.16, an = CGFloat(i) / 10 * .pi * 2 + .pi / 2; let p = NSPoint(x: cos(an) * r, y: sin(an) * r); i == 0 ? st.move(to: p) : st.line(to: p) }
            st.close(); body.addChildNode(node(SCNShape(path: st, extrusionDepth: 0.05), gloss(hex("#FFD34D")), SCNVector3(0.55, 0.6, 0.1)))
        case "chart":
            for i in 0..<3 { let h = 0.12 + CGFloat(i) * 0.1; body.addChildNode(node(SCNBox(width: 0.08, height: h, length: 0.08, chamferRadius: 0.02), white, SCNVector3(0.45 + CGFloat(i) * 0.1, 0.42 + h / 2, 0.15))) }
        case "calendar":
            let c = node(SCNBox(width: 0.32, height: 0.3, length: 0.04, chamferRadius: 0.03), white, SCNVector3(0.5, 0.45, 0.15)); c.addChildNode(node(SCNBox(width: 0.32, height: 0.08, length: 0.045, chamferRadius: 0.02), gloss(hex("#E5534B")), SCNVector3(0, 0.11, 0))); body.addChildNode(c)
        case "heart":
            let hp = NSBezierPath(); hp.move(to: NSPoint(x: 0, y: -0.12)); hp.curve(to: NSPoint(x: 0, y: 0.06), controlPoint1: NSPoint(x: -0.2, y: 0.0), controlPoint2: NSPoint(x: -0.08, y: 0.16))
            hp.curve(to: NSPoint(x: 0, y: -0.12), controlPoint1: NSPoint(x: 0.08, y: 0.16), controlPoint2: NSPoint(x: 0.2, y: 0.0)); hp.close()
            body.addChildNode(node(SCNShape(path: hp, extrusionDepth: 0.05), gloss(hex("#F0607A")), SCNVector3(0.52, 0.55, 0.12)))
        default: break
        }
        // name tag + speech bubble (always face the camera)
        let tag = billboard(Self.labelImage(AgentEdits.name(a), col), width: 2.1, height: 0.46); tag.position = SCNVector3(0, 2.25, 0); root.addChildNode(tag)
        let bubble = billboard(NSImage(size: NSSize(width: 4, height: 4)), width: 2.9, height: 0.9); bubble.position = SCNVector3(0, 2.95, 0); bubble.isHidden = true; root.addChildNode(bubble)
        let shadow = SCNPlane(width: 0.9, height: 0.9)
        let sm = SCNMaterial(); sm.lightingModel = .constant; sm.diffuse.contents = blob(); sm.writesToDepthBuffer = false; shadow.materials = [sm]
        let sn = SCNNode(geometry: shadow); sn.eulerAngles.x = -.pi / 2; sn.position = SCNVector3(0, 0.012, 0); root.addChildNode(sn)
        return OfficeRobot(root: root, body: body, head: head, hands: hands, eyes: eyes, bubble: bubble)
    }

    static func billboard(_ img: NSImage, width: CGFloat, height: CGFloat) -> SCNNode {
        let p = SCNPlane(width: width, height: height)
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = img; m.isDoubleSided = true; m.readsFromDepthBuffer = false; m.writesToDepthBuffer = false
        p.materials = [m]
        let n = SCNNode(geometry: p); n.renderingOrder = 50; n.constraints = [SCNBillboardConstraint()]
        return n
    }
    static func blob() -> NSImage {
        let img = NSImage(size: NSSize(width: 64, height: 64)); img.lockFocus()
        NSGradient(colors: [NSColor(calibratedWhite: 0, alpha: 0.32), NSColor(calibratedWhite: 0, alpha: 0)])?.draw(fromCenter: NSPoint(x: 32, y: 32), radius: 0, toCenter: NSPoint(x: 32, y: 32), radius: 31, options: [])
        img.unlockFocus(); return img
    }
    static func labelImage(_ text: String, _ dot: NSColor) -> NSImage {
        let size = NSSize(width: 512, height: 112)
        let img = NSImage(size: size); img.lockFocus()
        let font = NSFont.systemFont(ofSize: 40, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let w = min(500, (text as NSString).size(withAttributes: attrs).width + 70)
        NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: (512 - w) / 2, y: 18, width: w, height: 76), xRadius: 38, yRadius: 38).fill()
        dot.setFill(); NSBezierPath(ovalIn: NSRect(x: (512 - w) / 2 + 22, y: 47, width: 18, height: 18)).fill()
        (text as NSString).draw(at: NSPoint(x: (512 - w) / 2 + 52, y: 31), withAttributes: attrs)
        img.unlockFocus(); return img
    }
    static func bubbleImage(_ text: String, _ accent: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 640, height: 200)); img.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 10, y: 40, width: 620, height: 150), xRadius: 40, yRadius: 40).fill()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 300, y: 42)); tail.line(to: NSPoint(x: 320, y: 8)); tail.line(to: NSPoint(x: 340, y: 42)); tail.close(); tail.fill()
        accent.setFill(); NSRect(x: 40, y: 78, width: 8, height: 74).fill()
        let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 36, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.1, alpha: 1), .paragraphStyle: para]
        (String(text.prefix(90)) as NSString).draw(in: NSRect(x: 66, y: 58, width: 540, height: 110), withAttributes: attrs)
        img.unlockFocus(); return img
    }
    /// What an agent's screen shows.
    static func screenImage(_ title: String, _ line: String, _ color: NSColor, busy: Bool) -> NSImage {
        let img = NSImage(size: NSSize(width: 512, height: 320)); img.lockFocus()
        NSColor(calibratedRed: 0.055, green: 0.07, blue: 0.125, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 512, height: 320).fill()
        if busy {
            NSColor.white.setFill(); NSRect(x: 0, y: 274, width: 512, height: 46).fill()
            NSColor(calibratedWhite: 0.88, alpha: 1).setFill(); NSBezierPath(roundedRect: NSRect(x: 60, y: 284, width: 380, height: 26), xRadius: 13, yRadius: 13).fill()
            (title as NSString).draw(at: NSPoint(x: 78, y: 288), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.darkGray])
            NSColor(calibratedWhite: 0.96, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 512, height: 274).fill()
            let para = NSMutableParagraphStyle(); para.lineBreakMode = .byWordWrapping
            (String(line.prefix(140)) as NSString).draw(in: NSRect(x: 22, y: 40, width: 468, height: 210), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1), .paragraphStyle: para])
            color.setFill(); NSRect(x: 22, y: 24, width: 160, height: 6).fill()
        } else {
            color.withAlphaComponent(0.25).setFill(); NSRect(x: 0, y: 0, width: 512, height: 320).fill()
            ("Ready" as NSString).draw(at: NSPoint(x: 206, y: 140), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.white])
        }
        img.unlockFocus(); return img
    }
    /// Wood planks (drawn, so the floor looks like real wood).
    static func woodImage() -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let img = NSImage(size: size); img.lockFocus()
        var y: CGFloat = 0, row = 0
        while y < size.height {
            var x: CGFloat = row % 2 == 0 ? 0 : -180
            while x < size.width {
                let t = CGFloat((row * 7 + Int(x)) % 11) / 11
                NSColor(calibratedRed: 0.74 + 0.06 * t, green: 0.56 + 0.05 * t, blue: 0.40 + 0.04 * t, alpha: 1).setFill()
                NSRect(x: x, y: y, width: 360, height: 64).fill()
                for g in 0..<5 { NSColor(calibratedRed: 0.62, green: 0.45, blue: 0.31, alpha: 0.18).setFill(); NSRect(x: x + 10, y: y + 10 + CGFloat(g) * 10, width: 330, height: 1.2).fill() }
                NSColor(calibratedRed: 0.45, green: 0.32, blue: 0.22, alpha: 0.6).setFill(); NSRect(x: x, y: y, width: 2, height: 64).fill()
                x += 360
            }
            NSColor(calibratedRed: 0.45, green: 0.32, blue: 0.22, alpha: 0.5).setFill(); NSRect(x: 0, y: y, width: size.width, height: 2).fill()
            y += 64; row += 1
        }
        img.unlockFocus(); return img
    }
    static func skyImage() -> NSImage {
        let img = NSImage(size: NSSize(width: 64, height: 128)); img.lockFocus()
        NSGradient(colors: [hex("#CFE8FF"), hex("#8EC5F5")])?.draw(in: NSRect(x: 0, y: 0, width: 64, height: 128), angle: 90)
        img.unlockFocus(); return img
    }
}

final class OfficeRig: NSObject, SCNSceneRendererDelegate, @unchecked Sendable {
    struct Seat { let id: String; let robot: OfficeRobot; let screen: SCNMaterial; let home: SCNVector3; let rest: CGFloat }
    let scene = SCNScene()
    private(set) var seats: [String: Seat] = [:]
    private var nik: OfficeRobot!
    private let nikHome = SCNVector3(0, 0, 1.6)
    private let card = SCNNode()
    // shared with the main actor
    private let lock = NSLock()
    private var queue: [String] = []          // desks Nik still has to visit
    private var busyIDs: Set<String> = []
    private var missionKey = Date.distantPast
    // render thread
    private var last: TimeInterval = 0, t: CGFloat = 0
    private var walkTarget: SCNVector3?, handing: CGFloat = -1, handingTo: String?
    // agents move too: a happy hop when they get a task, a walk to Nik with the result when they finish
    private var prevBusy: Set<String> = []
    private var hops: [String: CGFloat] = [:]
    private var trips: [String: (phase: Int, wait: CGFloat)] = [:]

    @MainActor init(agents: [TeamAgent]) {
        super.init()
        build(agents)
    }

    @MainActor private func build(_ agents: [TeamAgent]) {
        let root = scene.rootNode
        scene.lightingEnvironment.contents = OfficeBuilder.skyImage(); scene.lightingEnvironment.intensity = 0.9
        scene.background.contents = OfficeBuilder.hex("#1B1E2B")
        // camera: looking down into the office
        let cam = SCNCamera(); cam.fieldOfView = 34; cam.zNear = 0.1; cam.zFar = 200
        cam.wantsHDR = true; cam.bloomIntensity = 0.15; cam.screenSpaceAmbientOcclusionIntensity = 0.7; cam.screenSpaceAmbientOcclusionRadius = 0.6
        let cn = SCNNode(); cn.name = "camera"; cn.camera = cam; cn.position = SCNVector3(0, 17, 17.5); cn.look(at: SCNVector3(0, 0, 0.3)); root.addChildNode(cn)
        // light: warm sun through the windows (soft shadows) + a soft sky fill
        let sun = SCNLight(); sun.type = .directional; sun.intensity = 1700; sun.color = OfficeBuilder.hex("#FFF2E2")
        sun.castsShadow = true; sun.shadowMode = .deferred; sun.shadowRadius = 6; sun.shadowSampleCount = 16; sun.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.45)
        sun.orthographicScale = 16; sun.shadowMapSize = CGSize(width: 2048, height: 2048)
        let sn = SCNNode(); sn.light = sun; sn.position = SCNVector3(6, 14, 8); sn.look(at: SCNVector3Zero); root.addChildNode(sn)
        let amb = SCNLight(); amb.type = .ambient; amb.intensity = 420; amb.color = OfficeBuilder.hex("#E6E9FF")
        let an = SCNNode(); an.light = amb; root.addChildNode(an)
        // floor, walls, windows
        let wood = SCNMaterial(); wood.lightingModel = .physicallyBased; wood.diffuse.contents = OfficeBuilder.woodImage(); wood.roughness.contents = 0.55
        wood.diffuse.wrapS = .repeat; wood.diffuse.wrapT = .repeat; wood.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        let floor = SCNNode(geometry: SCNBox(width: 26, height: 0.2, length: 18, chamferRadius: 0)); floor.geometry?.materials = [wood]; floor.position = SCNVector3(0, -0.1, 0); root.addChildNode(floor)
        let wall = OfficeBuilder.matte(OfficeBuilder.hex("#3B4060"))
        root.addChildNode(OfficeBuilder.node(SCNBox(width: 26, height: 6, length: 0.3, chamferRadius: 0), wall, SCNVector3(0, 3, -9)))
        root.addChildNode(OfficeBuilder.node(SCNBox(width: 0.3, height: 6, length: 18, chamferRadius: 0), OfficeBuilder.matte(OfficeBuilder.hex("#343852")), SCNVector3(-13, 3, 0)))
        let glass = SCNMaterial(); glass.lightingModel = .constant; glass.diffuse.contents = OfficeBuilder.skyImage(); glass.emission.contents = OfficeBuilder.skyImage(); glass.emission.intensity = 0.6
        for x in [-8.0, -2.0, 4.0, 10.0] as [CGFloat] {
            root.addChildNode(OfficeBuilder.node(SCNBox(width: 3.6, height: 2.4, length: 0.05, chamferRadius: 0), glass, SCNVector3(x, 3.4, -8.83)))
            root.addChildNode(OfficeBuilder.node(SCNBox(width: 3.8, height: 0.12, length: 0.12, chamferRadius: 0), OfficeBuilder.matte(.white), SCNVector3(x, 2.15, -8.8)))
        }
        // a rug, a sofa corner, bookshelf, plants, coffee
        let rug = OfficeBuilder.node(SCNCylinder(radius: 2.6, height: 0.02), OfficeBuilder.matte(OfficeBuilder.hex("#5C4B8A"), rough: 1), SCNVector3(0, 0.01, 1.5)); rug.castsShadow = false; root.addChildNode(rug)
        let shelf = OfficeBuilder.node(SCNBox(width: 3.2, height: 2.2, length: 0.5, chamferRadius: 0.04), OfficeBuilder.matte(OfficeBuilder.hex("#E9E3D8")), SCNVector3(9.5, 1.1, -8.5)); root.addChildNode(shelf)
        let bookColors = ["#E5534B", "#3A6DF0", "#F5B963", "#3DBE7E", "#9B7BFF", "#2F3A67"]
        for r in 0..<3 { for i in 0..<9 { let h = 0.42 + CGFloat((i * 7 + r) % 4) * 0.05
            shelf.addChildNode(OfficeBuilder.node(SCNBox(width: 0.24, height: h, length: 0.32, chamferRadius: 0.02), OfficeBuilder.matte(OfficeBuilder.hex(bookColors[(i + r) % 6]), rough: 0.6), SCNVector3(-1.3 + CGFloat(i) * 0.3, -0.75 + CGFloat(r) * 0.72 + h / 2, 0.05))) } }
        for (x, z) in [(-11.8, -7.6), (11.8, 6.8), (-11.8, 6.8), (6.6, -8.1)] as [(CGFloat, CGFloat)] {
            let p = SCNNode(); p.position = SCNVector3(x, 0, z); root.addChildNode(p)
            p.addChildNode(OfficeBuilder.node(SCNCylinder(radius: 0.32, height: 0.55), OfficeBuilder.matte(OfficeBuilder.hex("#E7E2D8")), SCNVector3(0, 0.27, 0)))
            for i in 0..<7 { let a = CGFloat(i); let leaf = OfficeBuilder.node(SCNSphere(radius: 0.3), OfficeBuilder.matte(OfficeBuilder.hex(i % 2 == 0 ? "#3E9B63" : "#2F7D4F"), rough: 0.7), SCNVector3(cos(a) * 0.18, 0.95 + CGFloat(i % 3) * 0.12, sin(a) * 0.18), scale: SCNVector3(0.5, 1.25, 0.5)); leaf.eulerAngles.z = cos(a) * 0.5; p.addChildNode(leaf) }
        }
        // desks — one per agent, in rows of four
        for (i, a) in agents.prefix(8).enumerated() {
            let col = i % 4, row = i / 4
            let x = CGFloat(col) * 5 - 7.5, z: CGFloat = row == 0 ? -4.5 : 4.5
            let color = RobotLook.color(for: a)
            let desk = SCNNode(); desk.position = SCNVector3(x, 0, z); root.addChildNode(desk)
            desk.addChildNode(OfficeBuilder.node(SCNBox(width: 2.4, height: 0.12, length: 1.2, chamferRadius: 0.05), OfficeBuilder.matte(OfficeBuilder.hex("#F2EEE8"), rough: 0.45), SCNVector3(0, 0.95, 0)))
            for s in [-1.0, 1.0] as [CGFloat] { desk.addChildNode(OfficeBuilder.node(SCNBox(width: 0.1, height: 0.95, length: 1.0, chamferRadius: 0.03), OfficeBuilder.matte(OfficeBuilder.hex("#3B3F55")), SCNVector3(1.05 * s, 0.47, 0))) }
            desk.addChildNode(OfficeBuilder.node(SCNBox(width: 1.3, height: 0.82, length: 0.07, chamferRadius: 0.03), OfficeBuilder.matte(OfficeBuilder.hex("#1B1E2B"), rough: 0.35), SCNVector3(0, 1.55, -0.38)))
            desk.addChildNode(OfficeBuilder.node(SCNCylinder(radius: 0.04, height: 0.3), OfficeBuilder.matte(OfficeBuilder.hex("#1B1E2B")), SCNVector3(0, 1.12, -0.38)))
            let screen = SCNMaterial(); screen.lightingModel = .constant; screen.diffuse.contents = OfficeBuilder.screenImage("", "", color, busy: false)
            let sp = SCNPlane(width: 1.2, height: 0.72); sp.materials = [screen]
            let scr = SCNNode(geometry: sp); scr.position = SCNVector3(0, 1.55, -0.34); desk.addChildNode(scr)
            desk.addChildNode(OfficeBuilder.node(SCNCylinder(radius: 0.08, height: 0.16), OfficeBuilder.gloss(color), SCNVector3(0.85, 1.09, 0.2)))
            desk.addChildNode(OfficeBuilder.node(SCNBox(width: 0.5, height: 0.03, length: 0.2, chamferRadius: 0.01), OfficeBuilder.matte(OfficeBuilder.hex("#2A2D3A")), SCNVector3(-0.1, 1.03, 0.15)))
            let r = OfficeBuilder.robot(a)
            let home = SCNVector3(x + 1.55, 0, z + 0.55)
            r.root.position = home; r.root.eulerAngles.y = -0.55; r.root.scale = SCNVector3(0.85, 0.85, 0.85)
            root.addChildNode(r.root)
            seats[a.id] = Seat(id: a.id, robot: r, screen: screen, home: home, rest: -0.55)
        }
        nik = OfficeBuilder.robot(ZuffiTeam.manager)
        nik.root.position = nikHome; nik.root.scale = SCNVector3(0.95, 0.95, 0.95); root.addChildNode(nik.root)
        // the task card Nik carries
        let cm = SCNMaterial(); cm.lightingModel = .constant; cm.diffuse.contents = OfficeBuilder.screenImage("", "", OfficeBuilder.hex("#3A6DF0"), busy: false); cm.isDoubleSided = true
        let cp = SCNPlane(width: 0.62, height: 0.39); cp.materials = [cm]; card.geometry = cp; card.isHidden = true; card.constraints = [SCNBillboardConstraint()]
        root.addChildNode(card)
    }

    // MARK: from the main actor
    @MainActor func startMission(_ key: Date, agents: [String]) {
        lock.lock(); defer { lock.unlock() }
        guard key != missionKey else { return }
        missionKey = key; queue = agents.filter { seats[$0] != nil }
        nik.bubble.geometry?.firstMaterial?.diffuse.contents = OfficeBuilder.bubbleImage(agents.isEmpty ? "Let me read your task…" : "On it — I'll give this to the team!", OfficeBuilder.hex("#F5B963"))
        nik.bubble.isHidden = false
    }
    @MainActor func update(agent id: String, working: Bool, title: String, line: String, bubble: String?) {
        guard let s = seats[id] else { return }
        let col = RobotLook.color(for: ZuffiTeam.shared.agent(id) ?? ZuffiTeam.manager)
        s.screen.diffuse.contents = OfficeBuilder.screenImage(title, line, col, busy: working)
        if let b = bubble, !b.isEmpty {
            s.robot.bubble.geometry?.firstMaterial?.diffuse.contents = OfficeBuilder.bubbleImage(b, col); s.robot.bubble.isHidden = false
        } else { s.robot.bubble.isHidden = true }
        lock.lock(); if working { busyIDs.insert(id) } else { busyIDs.remove(id) }; lock.unlock()
    }

    // MARK: every frame (SceneKit's thread)
    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = CGFloat(last == 0 ? 1.0 / 60 : min(0.05, time - last)); last = time; t += dt
        lock.lock(); let busy = busyIDs; var next: String? = nil
        if walkTarget == nil, handing < 0, !queue.isEmpty { next = queue.removeFirst() }
        lock.unlock()
        // Nik: walk to the next desk, hand over the card, then go back to the middle
        if let n = next, let s = seats[n] {
            walkTarget = SCNVector3(s.home.x + 0.2, 0, s.home.z + 1.3); handingTo = n; card.isHidden = false
        }
        if let target = walkTarget {
            if walk(nik.root, to: target, dt: dt) {
                walkTarget = nil
                if handingTo != nil { handing = 0 } else { card.isHidden = true }
            }
        } else if handing >= 0, let to = handingTo, let s = seats[to] {
            handing += dt / 0.8
            let a = nik.root.position, b = s.home
            let k = min(1, handing)
            card.position = SCNVector3(a.x + (b.x - a.x) * k, 1.1, a.z + (b.z - a.z) * k)
            if handing >= 1 {
                handing = -1; handingTo = nil; card.isHidden = true
                lock.lock(); let more = !queue.isEmpty; lock.unlock()
                if !more { walkTarget = nikHome; nik.bubble.isHidden = true }
            }
        }
        if walkTarget == nil, handing < 0 { nik.root.eulerAngles.y += (0 - nik.root.eulerAngles.y) * min(1, dt * 3) }
        if !card.isHidden, handing < 0 { let p = nik.root.position; card.position = SCNVector3(p.x, 1.25, p.z + 0.2) }
        animate(nik, busy: false, phase: 0)
        for id in busy.subtracting(prevBusy) { hops[id] = 0; trips[id] = nil }
        for id in prevBusy.subtracting(busy) where seats[id] != nil { trips[id] = (0, 0) }
        prevBusy = busy
        for (i, (id, s)) in seats.enumerated() {
            let isBusy = busy.contains(id)
            animate(s.robot, busy: isBusy, phase: CGFloat(i))
            let root = s.robot.root
            if var trip = trips[id] {
                // carry the result to Nik, wait a moment, then go back to the desk
                let meet = SCNVector3(nikHome.x + (s.home.x < 0 ? -0.9 : 0.9), 0, nikHome.z + 0.3)
                switch trip.phase {
                case 0: if walk(root, to: meet, dt: dt) { trip.phase = 1 }
                        root.position.y = abs(sin(t * 9)) * 0.08
                case 1: trip.wait += dt; root.eulerAngles.y += (atan2(nikHome.x - root.position.x, nikHome.z - root.position.z) - root.eulerAngles.y) * min(1, dt * 4)
                        root.position.y = trip.wait < 0.5 ? sin(trip.wait / 0.5 * .pi) * 0.35 : 0
                        if trip.wait > 1.6 { trip.phase = 2 }
                default: if walk(root, to: s.home, dt: dt) { trips[id] = nil; root.position.y = 0; continue }
                        root.position.y = abs(sin(t * 9)) * 0.08
                }
                trips[id] = trip
                continue
            }
            if let h = hops[id] {
                // got a task: jump up with a spin, then sit back to work
                let k = h + dt / 0.75
                root.position.y = sin(min(1, k) * .pi) * 0.7
                root.eulerAngles.y = s.rest + min(1, k) * .pi * 2
                if k >= 1 { hops[id] = nil; root.position.y = 0; root.eulerAngles.y = s.rest } else { hops[id] = k }
                continue
            }
            // a working agent turns to its screen and bobs while it types; then back to face you
            let want: CGFloat = isBusy ? -0.95 : s.rest
            root.eulerAngles.y += (want - root.eulerAngles.y) * min(1, dt * 3)
            root.position.y = isBusy ? abs(sin(t * 6 + CGFloat(i))) * 0.05 : 0
        }
    }
    private func walk(_ n: SCNNode, to: SCNVector3, dt: CGFloat) -> Bool {
        let dx = to.x - n.position.x, dz = to.z - n.position.z
        let d = sqrt(dx * dx + dz * dz)
        if d < 0.05 { return true }
        let step = min(d, 2.6 * dt)
        n.position = SCNVector3(n.position.x + dx / d * step, 0, n.position.z + dz / d * step)
        n.eulerAngles.y = atan2(dx, dz)
        return false
    }
    private func animate(_ r: OfficeRobot, busy: Bool, phase: CGFloat) {
        r.body.position.y = 0.06 * sin(t * 2.2 + phase) + 0.08
        for (i, h) in r.hands.enumerated() { h.position.y = 0.5 + (busy ? 0.05 * sin(t * 16 + CGFloat(i) * 2) : 0.03 * sin(t * 2 + CGFloat(i))) }
        r.head.eulerAngles.z = 0.05 * sin(t * 0.9 + phase)
        let blink = (t + phase).truncatingRemainder(dividingBy: 3.8) > 3.7
        for e in r.eyes { e.scale.y = blink ? 0.15 : 1.15 }
    }
}

/// Keeps the office in step with the team: who's working, what their screen shows, what they're saying.
@MainActor
final class OfficeModel: ObservableObject {
    static let shared = OfficeModel()
    @Published var rig: OfficeRig?
    @Published var reply = ""
    private var watch: AnyCancellable?, watch2: AnyCancellable?
    private var agentIDs: [String] = []

    var officeAgents: [TeamAgent] {
        let team = ZuffiTeam.shared
        let biz = !ZuffiPlan.shared.isPersonal && BizNav.shared.formDone
        let list = team.hiredAgents.filter { $0.id != ZuffiTeam.manager.id && (ZuffiTeam.isPersonal($0) || biz) }
        var out: [TeamAgent] = []; for a in list where !out.contains(a) { out.append(a) }
        return Array(out.prefix(8))
    }

    func rebuild() { rig = nil; agentIDs = []; ensure() }

    func ensure() {
        let ids = officeAgents.map(\.id)
        if rig == nil || ids != agentIDs { agentIDs = ids; rig = OfficeRig(agents: officeAgents) }
        if watch == nil {
            watch = ZuffiTeam.shared.$runs.receive(on: RunLoop.main).sink { _ in MainActor.assumeIsolated { OfficeModel.shared.sync() } }
            watch2 = MissionControl.shared.$agents.receive(on: RunLoop.main).sink { _ in MainActor.assumeIsolated { OfficeModel.shared.sync() } }
        }
        sync()
    }

    func sync() {
        guard let rig else { return }
        let mc = MissionControl.shared
        if mc.started > Date.distantPast { rig.startMission(mc.started, agents: mc.agents) }
        for id in agentIDs {
            let r = ZuffiTeam.shared.runs.first { $0.agent == id && $0.started >= mc.started.addingTimeInterval(-1) }
            let working = r?.status == "Working"
            let line = r?.steps.last?.text ?? ""
            let bubble: String? = r == nil ? nil : working ? line : r!.status == "Needs input" ? "I need a bit more from you" : r!.status == "Done" ? "Done!" : nil
            rig.update(agent: id, working: working, title: r.flatMap { $0.links?.first?.url }.flatMap { URL(string: $0)?.host } ?? "working", line: line, bubble: bubble)
        }
    }
}

struct OfficeSceneView: NSViewRepresentable {
    let rig: OfficeRig
    func makeNSView(context: Context) -> SCNView {
        let v = SCNView(frame: .zero)
        v.scene = rig.scene; v.delegate = rig; v.isPlaying = true; v.rendersContinuously = true
        v.antialiasingMode = .multisampling4X; v.backgroundColor = .clear
        v.pointOfView = rig.scene.rootNode.childNode(withName: "camera", recursively: false)
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.maximumVerticalAngle = 75
        return v
    }
    func updateNSView(_ v: SCNView, context: Context) {
        if v.scene !== rig.scene { v.scene = rig.scene; v.delegate = rig; v.pointOfView = rig.scene.rootNode.childNode(withName: "camera", recursively: false) }
    }
}

/// The Agent Office page (in the dashboard).
struct AgentOfficeView: View {
    @ObservedObject private var model = OfficeModel.shared
    @ObservedObject private var mc = MissionControl.shared
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var task = ""
    var light = false
    init(light: Bool = false) { self.light = light }

    private var runs: [AgentRun] { team.runs.filter { $0.started >= mc.started.addingTimeInterval(-1) && (mc.agents.isEmpty || mc.agents.contains($0.agent)) } }
    private var asking: AgentRun? { runs.first { $0.status == "Needs input" } }

    var body: some View {
        ZStack(alignment: .top) {
            if let rig = model.rig { OfficeSceneView(rig: rig) } else { Color.clear }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.clock").foregroundColor(.white.opacity(0.7))
                    TextField("Give Nik a task — e.g. cheapest flight London to Lahore in December", text: $task)
                        .textFieldStyle(.plain).font(HubFont.p(14, .regular)).foregroundColor(.white)
                        .onSubmit(give)
                    Menu {
                        ForEach([ZuffiTeam.manager] + model.officeAgents, id: \.id) { a in Button("Edit \(AgentEdits.name(a))…") { AgentEditor.open(a) } }
                    } label: { Image(systemName: "slider.horizontal.3").foregroundColor(.white.opacity(0.8)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30).help("Edit your agents")
                    Button(action: give) {
                        Text("Give to Nik").font(HubFont.p(14)).foregroundColor(.white).padding(.horizontal, 18).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10).fill(HubTheme.blue))
                    }.buttonStyle(.plain)
                }
                .padding(.leading, 14).padding(.trailing, 5).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 16 / 255, green: 18 / 255, blue: 27 / 255).opacity(0.7)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15)))
                .padding(16)
                Spacer()
                HStack(alignment: .bottom, spacing: 16) {
                    stepsPanel
                    Spacer()
                    resultCard
                }
                .padding(16)
            }
        }
        .onAppear { model.ensure() }
    }

    private func give() {
        let q = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        task = ""
        mc.assign(q)
    }

    @ViewBuilder private var stepsPanel: some View {
        let all = runs.flatMap { r in r.steps.suffix(4).map { (team.agent(r.agent)?.name ?? "Agent", $0.text) } }
        if !all.isEmpty || !mc.question.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("What's happening").font(HubFont.p(13, .semibold)).foregroundColor(.white)
                if !mc.question.isEmpty { Text("Task: \(mc.question)").font(HubFont.p(12, .regular)).foregroundColor(.white.opacity(0.75)).lineLimit(2) }
                ForEach(Array(all.suffix(7).enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(i + 1).").font(HubFont.p(12)).foregroundColor(.white.opacity(0.5))
                        Text("\(s.0): \(s.1)").font(HubFont.p(12, .regular)).foregroundColor(i == all.suffix(7).count - 1 ? .white : .white.opacity(0.6)).lineLimit(2)
                    }
                }
            }
            .padding(14).frame(width: 320, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 16 / 255, green: 18 / 255, blue: 27 / 255).opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.12)))
        }
    }

    @ViewBuilder private var resultCard: some View {
        if let ask = asking {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(team.agent(ask.agent)?.name ?? "Agent") needs a bit more").font(HubFont.p(15, .semibold))
                ChatRichText(text: ask.result)
                HStack(spacing: 8) {
                    TextField("Your answer", text: $model.reply).textFieldStyle(.plain).font(HubFont.p(13, .regular))
                        .padding(.horizontal, 10).frame(height: 36).background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                        .onSubmit { answer() }
                    Button(action: answer) {
                        Text("Send").font(HubFont.p(13)).foregroundColor(.white).padding(.horizontal, 16).frame(height: 36).background(Capsule().fill(HubTheme.blue))
                    }.buttonStyle(.plain)
                }
            }
            .foregroundColor(.white).padding(18).frame(width: 400, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 16 / 255, green: 18 / 255, blue: 27 / 255).opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.14)))
        } else if let r = mc.result {
            VStack(alignment: .leading, spacing: 10) {
                Text("Result").font(HubFont.p(15, .semibold))
                ScrollView { ChatRichText(text: r).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 300)
                HStack(spacing: 8) {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(r, forType: .string) } label: {
                        Text("Copy").font(HubFont.p(13)).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 36).background(Capsule().fill(HubTheme.blue))
                    }.buttonStyle(.plain)
                    Button { ChatRichText.save(r) } label: {
                        Text("Save").font(HubFont.p(13)).foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 36).overlay(Capsule().stroke(Color.white.opacity(0.55)))
                    }.buttonStyle(.plain)
                }
            }
            .foregroundColor(.white).padding(18).frame(width: 420, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 16 / 255, green: 18 / 255, blue: 27 / 255).opacity(0.82)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.14)))
        }
    }

    private func answer() {
        let a = model.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !a.isEmpty else { return }
        model.reply = ""
        mc.reply(a)
    }
}

/// A small living robot face (same look as the Agent Office robots): its colour, white face, blinking eyes, a smile and a
/// bobbing antenna. It floats gently like Zuffi; when the agent is working it bobs faster and its eyes glance about.
struct RobotFace: View {
    let agent: TeamAgent
    var size: CGFloat = 30
    var working = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate + Double(abs(agent.id.hashValue % 100)) / 10
            let col = Color(nsColor: RobotLook.color(for: agent))
            let s = size
            let blink = t.truncatingRemainder(dividingBy: 3.6) > 3.47
            let look = working ? CGFloat(sin(t * 2.4)) * s * 0.035 : 0
            ZStack {
                // antenna
                Capsule().fill(Color.white).frame(width: s * 0.05, height: s * 0.16).offset(y: -s * 0.5)
                Circle().fill(col).frame(width: s * 0.15, height: s * 0.15).offset(y: -s * 0.6)
                    .shadow(color: col.opacity(working ? 0.9 : 0.3), radius: working ? 3 : 1)
                // head
                Ellipse().fill(RadialGradient(colors: [col.opacity(0.75), col], center: UnitPoint(x: 0.35, y: 0.25), startRadius: 0, endRadius: s * 0.6))
                    .frame(width: s, height: s * 0.88)
                    .overlay(Ellipse().fill(Color.white.opacity(0.35)).frame(width: s * 0.3, height: s * 0.14).offset(x: -s * 0.2, y: -s * 0.28))
                // face panel
                Ellipse().fill(Color.white).frame(width: s * 0.72, height: s * 0.54).offset(y: s * 0.04)
                HStack(spacing: s * 0.17) {
                    ForEach(0..<2, id: \.self) { _ in
                        Capsule().fill(Color(hex: "#111216")).frame(width: s * 0.12, height: blink ? s * 0.025 : s * 0.15)
                            .overlay(Circle().fill(Color.white).frame(width: s * 0.04).offset(x: s * 0.02, y: -s * 0.03).opacity(blink ? 0 : 1))
                    }
                }.offset(x: look, y: s * 0.0)
                Circle().trim(from: 0.1, to: 0.4).stroke(Color(hex: "#111216"), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))
                    .frame(width: s * 0.2, height: s * 0.2).offset(y: s * 0.06)
            }
            .frame(width: s, height: s * 1.2)
            // floats like Zuffi; hops when it's working
            .offset(x: CGFloat(sin(t * 0.7)) * s * 0.04, y: working ? -CGFloat(abs(sin(t * 5))) * s * 0.16 : CGFloat(sin(t * 2)) * s * 0.09)
            .rotationEffect(.degrees(working ? sin(t * 10) * 6 : sin(t * 1.1) * 7))
            .scaleEffect(1 + (working ? 0.04 * CGFloat(sin(t * 10)) : 0.02 * CGFloat(sin(t * 2))))
        }
        .frame(width: size, height: size * 1.2)
    }
}


// MARK: - Nik's plan for today: every hired agent's job on a timeline, with progress, plus new ideas from Nik

struct NikPlanItem: Identifiable { let id = UUID(); let agent: String; let hour: Int; let minute: Int; let title: String; let task: String }

@MainActor
final class NikPlan: ObservableObject {
    static let shared = NikPlan()
    @Published var ideas: [NikPlanItem] = []
    @Published var thinking = false
    @Published var note = ""

    enum State: String { case done = "Done", running = "Working", upcoming = "Coming up", missed = "Missed", failed = "Didn't finish" }

    /// Today's jobs in time order (weekly ones only on their day).
    var today: [TeamJob] {
        let cal = Calendar.current, wd = cal.component(.weekday, from: Date())
        return ZuffiTeam.shared.jobs.filter { $0.enabled && ($0.weekday == nil || $0.weekday == wd) }.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
    func state(_ j: TeamJob) -> State {
        let team = ZuffiTeam.shared, cal = Calendar.current
        if team.runs.contains(where: { $0.job == j.title && $0.agent == j.agent && $0.status == "Working" }) { return .running }
        if let last = j.lastRun, cal.isDateInToday(last) {
            switch j.lastStatus { case "Missed": return .missed; case "Done", "": return .done; default: return j.lastStatus.lowercased().contains("fail") ? .failed : .done }
        }
        return .upcoming
    }
    var progress: (Int, Int) { let t = today; return (t.filter { state($0) == .done }.count, t.count) }

    /// Nik looks at who you hired and suggests new everyday tasks for them (you choose which to add).
    func askNik() {
        let team = ZuffiTeam.shared
        let people = team.hiredAgents
        guard !people.isEmpty else { note = "Hire an agent first — then I'll plan their day."; return }
        thinking = true; note = ""
        let biz = ZuffiPlan.shared.isPersonal ? "" : String(ZuffiTeam.businessContext.prefix(3000))
        let list = people.map { "\($0.id): \($0.name) — \($0.description)" }.joined(separator: "\n")
        let have = team.jobs.map { "\($0.agent): \($0.title)" }.joined(separator: "\n")
        let prompt = """
        You are Nik, the team manager. Suggest up to 5 NEW useful everyday tasks for these agents. Only tasks they can really do (reading websites, researching, writing, making summaries). No buying, paying, posting or sending.
        AGENTS:
        \(list)
        TASKS THEY ALREADY HAVE:
        \(have.isEmpty ? "none" : have)
        \(biz.isEmpty ? "" : "THE BUSINESS:\n" + biz)
        Reply with JSON only: [{"agent":"<agent id>","time":"HH:MM","title":"<3-5 words>","task":"<one clear instruction>"}]
        """
        Task { @MainActor in
            defer { self.thinking = false }
            guard let raw = await AIService.shared.oneShot(prompt),
                  let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"),
                  let data = String(raw[start...end]).data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                self.note = "I couldn't plan right now — check that an AI is set up in Settings."; return
            }
            let ids = Set(people.map(\.id))
            self.ideas = arr.compactMap { d in
                guard let ag = d["agent"] as? String, ids.contains(ag), let title = d["title"] as? String, let task = d["task"] as? String else { return nil }
                let parts = ((d["time"] as? String) ?? "09:00").split(separator: ":").compactMap { Int($0) }
                return NikPlanItem(agent: ag, hour: min(23, max(0, parts.first ?? 9)), minute: min(59, max(0, parts.count > 1 ? parts[1] : 0)), title: title, task: task)
            }
            if self.ideas.isEmpty { self.note = "Nothing new to add today — your team's day looks complete." }
        }
    }
    func add(_ i: NikPlanItem) {
        let team = ZuffiTeam.shared
        team.jobs.append(TeamJob(agent: i.agent, title: i.title, task: i.task, hour: i.hour, minute: i.minute))
        team.log("Nik", "Added to the daily plan", "\(i.title) at \(String(format: "%02d:%02d", i.hour, i.minute))")
        ideas.removeAll { $0.id == i.id }
    }
}

struct NikPlanView: View {
    var light = false
    @ObservedObject private var plan = NikPlan.shared
    @ObservedObject private var team = ZuffiTeam.shared
    init(light: Bool = false) { self.light = light }
    private var T: HubTheme { HubTheme(light: light) }

    var body: some View {
        let (done, total) = plan.progress
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RobotFace(agent: ZuffiTeam.manager, size: 30, working: plan.thinking)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nik's plan for today").font(HubFont.p(17, .semibold))
                    Text(total == 0 ? "No jobs yet — hire an agent and I'll give them a daily job." : "\(done) of \(total) done").font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                }
                Spacer()
                Button { plan.askNik() } label: {
                    Text(plan.thinking ? "Nik is planning…" : "Ask Nik for new tasks").font(HubFont.p(13)).foregroundColor(.white)
                        .padding(.horizontal, 16).frame(height: 34).background(Capsule().fill(HubTheme.blue))
                }.buttonStyle(.plain).disabled(plan.thinking)
            }
            if total > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(T.content)
                        Capsule().fill(LinearGradient(colors: [HubTheme.blue, HubTheme.green], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, g.size.width * CGFloat(done) / CGFloat(max(1, total))))
                    }
                }.frame(height: 8)
                VStack(spacing: 0) {
                    ForEach(Array(plan.today.enumerated()), id: \.element.id) { i, j in
                        let st = plan.state(j)
                        HStack(spacing: 14) {
                            Text(String(format: "%02d:%02d", j.hour, j.minute)).font(HubFont.p(13)).foregroundColor(T.inactive).frame(width: 46, alignment: .leading)
                            if let a = team.agent(j.agent) { RobotFace(agent: a, size: 24, working: st == .running) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(j.title).font(HubFont.p(14))
                                Text(team.agent(j.agent)?.name ?? "").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                            }
                            Spacer()
                            Text(st.rawValue).font(HubFont.p(12)).foregroundColor(color(st))
                                .padding(.horizontal, 10).frame(height: 24).background(Capsule().fill(color(st).opacity(0.14)))
                            if st == .upcoming || st == .missed {
                                Button { Task { await ZuffiTeam.shared.runJob(j.id) } } label: { Image(systemName: "play.fill").font(.system(size: 11)).foregroundColor(T.text).frame(width: 26, height: 26).background(Circle().fill(T.content)) }
                                    .buttonStyle(.plain).help("Run now")
                            }
                        }
                        .padding(.vertical, 9)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                    }
                }
            }
            if !plan.note.isEmpty { Text(plan.note).font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
            if !plan.ideas.isEmpty {
                Text("Nik suggests adding").font(HubFont.p(14, .semibold)).padding(.top, 4)
                ForEach(plan.ideas) { i in
                    HStack(spacing: 12) {
                        if let a = team.agent(i.agent) { RobotFace(agent: a, size: 24) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(String(format: "%02d:%02d", i.hour, i.minute)) · \(i.title)").font(HubFont.p(14))
                            Text(i.task).font(HubFont.p(12, .regular)).foregroundColor(T.inactive).lineLimit(2)
                        }
                        Spacer()
                        Button { plan.add(i) } label: { Text("Add").font(HubFont.p(13)).foregroundColor(.white).padding(.horizontal, 14).frame(height: 30).background(Capsule().fill(HubTheme.blue)) }.buttonStyle(.plain)
                        Button { plan.ideas.removeAll { $0.id == i.id } } label: { Image(systemName: "xmark").font(.system(size: 11)).foregroundColor(T.inactive) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
        .padding(.bottom, 24)
    }
    private func color(_ s: NikPlan.State) -> Color {
        switch s { case .done: return Color(hex: "#3DBE7E"); case .running: return Color(hex: "#F5B963"); case .upcoming: return HubTheme.blue; case .missed, .failed: return Color(hex: "#EF6B6B") }
    }
}


// MARK: - Documents & Data agent: real files, nothing invented

@MainActor
enum DocsAgent {
    static func folder() -> URL {
        let base = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let f = base.appendingPathComponent("Zuffi", isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        return f
    }
    static func safeName(_ t: String) -> String {
        let n = t.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined().trimmingCharacters(in: .whitespaces)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"; let stamp = f.string(from: Date())
        return (n.isEmpty ? "Zuffi file" : String(n.prefix(50))) + " " + stamp
    }
    static func wantsPDF(_ t: String) -> Bool { let l = t.lowercased(); return l.contains("pdf") && ["make", "create", "edit", "change", "fix", "turn", "convert", "rewrite", "save", "new"].contains { l.contains($0) } }
    static func hasData(_ t: String) -> Bool {
        t.contains("THE FILE THE OWNER GAVE YOU") || t.components(separatedBy: "\n").filter { $0.contains(",") || $0.contains("\t") || $0.contains("|") }.count >= 2
    }

    /// Returns the answer and whether it finished (false = it asked for the data).
    static func run(_ task: String, step: (String) -> Void) async -> (String, Bool) {
        guard hasData(task) || task.count > 400 else {
            step("Asked you for the data")
            return ("I can do that — please give me the data first. You can attach a file (CSV, Excel saved as CSV, PDF, Word or text) with the + button in chat, or paste the rows here. Tell me what you want too: a clean spreadsheet, fixed data, a summary, or a new PDF.", false)
        }
        if wantsPDF(task) { return await makePDF(task, step: step) }
        return await makeSheet(task, step: step)
    }

    static func makeSheet(_ task: String, step: (String) -> Void) async -> (String, Bool) {
        step("Reading your data")
        let prompt = """
        Turn the owner's data into one clean table and do exactly what they asked (tidy, fix, sort, total, pick out rows…).
        Rules: use ONLY values that are in the data. Never invent rows, names, numbers or totals. Fix formats (dates as YYYY-MM-DD,         trimmed names, numbers without stray symbols), remove exact duplicate rows, and leave a cell empty if the value is missing.
        Reply with JSON only: {"title":"<short name>","columns":["..."],"rows":[["..."]],"changes":["<what you changed and why, one line each>"],"missing":["<anything missing or unclear>"]}
        THE OWNER'S REQUEST AND DATA:
        \(task.prefix(60_000))
        """
        step("Tidying and laying out the table")
        guard let raw = await AIService.shared.oneShot(prompt),
              let s = raw.firstIndex(of: "{"), let e = raw.lastIndex(of: "}"),
              let d = String(raw[s...e]).data(using: .utf8),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let cols = j["columns"] as? [Any], let rowsAny = j["rows"] as? [[Any]] else {
            step("Couldn't make the table")
            return ("I couldn't turn that into a table this time. Check that an AI is set up in Settings, or send the data as plain rows (one line per row, values separated by commas).", false)
        }
        let columns = cols.map { "\($0)" }
        let rows = rowsAny.map { r in r.map { v -> String in v is NSNull ? "" : "\(v)" } }
        // honesty check: every value in the table must appear in what you gave (ignoring case/spaces), except reformatted dates/numbers
        let source = task.lowercased()
        let unknown = rows.flatMap { $0 }.filter { v in
            let t = v.trimmingCharacters(in: .whitespaces).lowercased()
            return t.count > 3 && t.rangeOfCharacter(from: .letters) != nil && !source.contains(t)
        }
        let title = (j["title"] as? String) ?? "Table"
        func cell(_ v: String) -> String { v.contains(",") || v.contains("\"") || v.contains("\n") ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v }
        let csv = "\u{FEFF}" + ([columns] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n")
        let url = folder().appendingPathComponent(safeName(title) + ".csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8) } catch {
            return ("I made the table but couldn't save the file: \(error.localizedDescription)", false)
        }
        step("Saved \(url.lastPathComponent) in Downloads › Zuffi")
        var out = ["## \(title)", "\(rows.count) row\(rows.count == 1 ? "" : "s") · \(columns.count) column\(columns.count == 1 ? "" : "s"). Saved as a spreadsheet you can open in Excel or Numbers.", "• Open the spreadsheet — \(url.absoluteString)"]
        let preview = rows.prefix(8).map { $0.joined(separator: " · ") }
        if !preview.isEmpty { out.append("### First rows"); out.append(([columns.joined(separator: " · ")] + preview).map { "- " + $0 }.joined(separator: "\n")) }
        if let ch = j["changes"] as? [String], !ch.isEmpty { out.append("### What I changed"); out.append(ch.prefix(12).map { "- " + $0 }.joined(separator: "\n")) }
        if let m = j["missing"] as? [String], !m.isEmpty { out.append("### Missing or unclear"); out.append(m.prefix(8).map { "- " + $0 }.joined(separator: "\n")) }
        if !unknown.isEmpty { out.append("⚠️ Please check: \(unknown.prefix(5).joined(separator: ", ")) — I couldn't find \(unknown.count == 1 ? "this value" : "these values") word-for-word in your data.") }
        return (out.joined(separator: "\n\n"), true)
    }

    static func makePDF(_ task: String, step: (String) -> Void) async -> (String, Bool) {
        step("Reading your document")
        let prompt = """
        The owner wants a PDF made or changed. Write the FULL final text of the document with their changes applied.         Keep everything they didn't ask to change exactly as it is. Don't invent facts, names, prices or dates.         Plain text only: a title on the first line, then paragraphs separated by blank lines; lines starting with "- " are bullets.
        THE OWNER'S REQUEST AND DOCUMENT:
        \(task.prefix(60_000))
        """
        step("Writing the new text")
        guard let text = await AIService.shared.oneShot(prompt, system: "You edit documents exactly as asked. Reply with the document text only."), text.count > 20 else {
            return ("I couldn't write the document this time. Check that an AI is set up in Settings.", false)
        }
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        let title = lines.first?.trimmingCharacters(in: CharacterSet(charactersIn: "# ")) ?? "Document"
        let url = folder().appendingPathComponent(safeName(title) + ".pdf")
        step("Making the PDF")
        guard writePDF(title: title, body: lines.dropFirst().joined(separator: "\n"), to: url) else { return ("I couldn't save the PDF.", false) }
        step("Saved \(url.lastPathComponent) in Downloads › Zuffi")
        return ("""
        ## \(title)
        I made a new PDF with your changes.
        • Open the PDF — \(url.absoluteString)
        Note: I rebuild PDFs from their text, so the original's exact layout, pictures and signatures aren't kept. For forms or signed papers, keep the original and use this as the updated text.
        """, true)
    }

    /// A clean A4 PDF from text (title, paragraphs, bullets), with page breaks.
    static func writePDF(title: String, body: String, to url: URL) -> Bool {
        var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return false }
        let doc = NSMutableAttributedString()
        let tp = NSMutableParagraphStyle(); tp.paragraphSpacing = 14
        doc.append(NSAttributedString(string: title + "\n", attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.black, .paragraphStyle: tp]))
        let bp = NSMutableParagraphStyle(); bp.paragraphSpacing = 8; bp.lineSpacing = 2
        let lp = NSMutableParagraphStyle(); lp.paragraphSpacing = 4; lp.headIndent = 14; lp.firstLineHeadIndent = 0
        for line in body.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- ") || t.hasPrefix("• ") {
                doc.append(NSAttributedString(string: "•  " + String(t.dropFirst(2)) + "\n", attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor.black, .paragraphStyle: lp]))
            } else {
                doc.append(NSAttributedString(string: t + "\n", attributes: [.font: NSFont.systemFont(ofSize: 11.5), .foregroundColor: NSColor.black, .paragraphStyle: bp]))
            }
        }
        let framesetter = CTFramesetterCreateWithAttributedString(doc)
        var start = 0
        let frameRect = CGRect(x: 56, y: 56, width: 595 - 112, height: 842 - 112)
        repeat {
            ctx.beginPDFPage(nil)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            CTFrameDraw(frame, ctx)
            let r = CTFrameGetVisibleStringRange(frame)
            ctx.endPDFPage()
            if r.length == 0 { break }
            start += r.length
        } while start < doc.length
        ctx.closePDF()
        return true
    }
}


// =====================================================================
// MARK: - Zuffi Reach: agents can reach more of the internet (search, read any page, video, social, Chinese sites)
// Ideas from Agent Reach (MIT), rebuilt in Swift. Read-only: agents search and read; they never post, like or send.
// =====================================================================

struct ReachItem { var title: String; var url: String; var text: String; var via: String }

@MainActor
enum ZuffiReach {
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
    /// Backup readers (Jina Reader, Exa) send the page address or search words to those services; owners can turn them off.
    static var backupOn: Bool { UserDefaults.standard.object(forKey: "reachBackup") as? Bool ?? true }

    static func get(_ url: String, headers: [String: String] = [:], timeout: TimeInterval = 12) async -> (Data, Int)? {
        guard let u = URL(string: url) else { return nil }
        var r = URLRequest(url: u, timeoutInterval: timeout)
        r.setValue(ua, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        guard let (d, resp) = try? await URLSession.shared.data(for: r) else { return nil }
        return (d, (resp as? HTTPURLResponse)?.statusCode ?? 0)
    }
    static func json(_ url: String, headers: [String: String] = [:]) async -> Any? {
        guard let (d, code) = await get(url, headers: headers), code < 400 else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
    static func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
    static func stripHTML(_ h: String) -> String {
        var t = h.replacingOccurrences(of: #"(?is)<(script|style|noscript|svg)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</div>|</li>|</h[1-6]>"#, with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&pound;", "£")] { t = t.replacingOccurrences(of: a, with: b) }
        t = t.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression).replacingOccurrences(of: #"\n\s*\n+"#, with: "\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isBlockPage(_ t: String) -> Bool {
        let l = t.prefix(4000).lowercased()
        return l.contains("just a moment...") || l.contains("performing security verification") || l.contains("attention required! | cloudflare") || l.contains("unusual traffic") || l.contains("are you a robot")
    }

    // MARK: Search the web — Google (in an agent tab you can watch) → DuckDuckGo → Exa

    static func search(_ q: String, agent: TeamAgent, runID: String?, limit: Int = 8) async -> [ReachItem] {
        var out: [ReachItem] = []
        for r in await AgentBrowser.shared.googleResults(q, agent: agent, runID: runID) where !out.contains(where: { $0.url == r.url }) {
            out.append(ReachItem(title: r.title, url: r.url, text: r.snippet, via: "Google"))
        }
        if out.count < 3 { out += (await duck(q)).filter { i in !out.contains { $0.url == i.url } } }
        if out.count < 3, backupOn { out += (await exaSearch(q, limit: limit)).filter { i in !out.contains { $0.url == i.url } } }
        return Array(out.prefix(limit))
    }
    static func duck(_ q: String) async -> [ReachItem] {
        guard let (d, _) = await get("https://html.duckduckgo.com/html/?q=\(enc(q))&kl=uk-en"), let h = String(data: d, encoding: .utf8) else { return [] }
        var out: [ReachItem] = []
        let blocks = h.components(separatedBy: "class=\"result__a\"").dropFirst()
        for b in blocks.prefix(10) {
            guard let hr = b.range(of: #"href="([^"]+)""#, options: .regularExpression) else { continue }
            var href = String(b[hr]).replacingOccurrences(of: "href=\"", with: "").dropLast().description
            if let r = href.range(of: "uddg=") { href = String(href[r.upperBound...]).components(separatedBy: "&").first?.removingPercentEncoding ?? href }
            if href.hasPrefix("//") { href = "https:" + href }
            let title = stripHTML(String(b.drop(while: { $0 != ">" }).dropFirst().prefix(while: { $0 != "<" })))
            var snip = ""
            if let sr = b.range(of: "result__snippet") { snip = stripHTML(String(b[sr.upperBound...].drop(while: { $0 != ">" }).dropFirst().prefix(400)).components(separatedBy: "</a>").first ?? "") }
            if href.hasPrefix("http"), !href.contains("duckduckgo.com") { out.append(ReachItem(title: title, url: href, text: snip, via: "DuckDuckGo")) }
        }
        return out
    }
    static func exaCall(_ tool: String, _ args: [String: Any]) async -> String? {
        guard let u = URL(string: "https://mcp.exa.ai/mcp") else { return nil }
        var r = URLRequest(url: u, timeoutInterval: 25); r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type"); r.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": ["name": tool, "arguments": args]])
        guard let (d, _) = try? await URLSession.shared.data(for: r), let raw = String(data: d, encoding: .utf8) else { return nil }
        let payload = raw.components(separatedBy: "\n").filter { $0.hasPrefix("data:") }.last.map { String($0.dropFirst(5)) } ?? raw
        guard let j = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any], j["error"] == nil,
              let res = j["result"] as? [String: Any], (res["isError"] as? Bool) != true, let content = res["content"] as? [[String: Any]] else { return nil }
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
    static func exaSearch(_ q: String, limit: Int) async -> [ReachItem] {
        guard let text = await exaCall("web_search_exa", ["query": q, "numResults": limit]) else { return [] }
        return ("\n" + text).components(separatedBy: "\nTitle: ").dropFirst().compactMap { b in
            let lines = b.components(separatedBy: "\n")
            let title = lines.first ?? ""
            guard let url = lines.first(where: { $0.hasPrefix("URL: ") })?.dropFirst(5) else { return nil }
            let body = lines.drop { !$0.hasPrefix("Text:") && !$0.hasPrefix("Highlights:") }.dropFirst().joined(separator: "\n")
            return ReachItem(title: title, url: String(url), text: String(body.prefix(1500)), via: "Exa")
        }
    }

    // MARK: Read any page — the site's own reader first, then Jina Reader, a plain fetch, Exa, and finally the agent browser

    static func read(_ urlString: String, agent: TeamAgent, runID: String?) async -> ReachItem? {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return nil }
        if let site = await siteReader(url, host: host) { return site }
        if needsSignIn(host) { return await browserRead(url, agent: agent, runID: runID) }
        if backupOn, let (d, code) = await get("https://r.jina.ai/" + urlString, headers: ["Accept": "text/plain"], timeout: 20), code < 400,
           let t = String(data: d, encoding: .utf8), t.count > 300, !isBlockPage(t) {
            let title = t.range(of: #"(?m)^Title:\s*(.*)$"#, options: .regularExpression).map { String(t[$0].dropFirst(6)).trimmingCharacters(in: .whitespaces) } ?? host
            let body = t.components(separatedBy: "Markdown Content:").last ?? t
            return ReachItem(title: title, url: urlString, text: String(body.prefix(14000)), via: "Jina Reader")
        }
        if let (d, code) = await get(urlString), code < 400, let h = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .isoLatin1) {
            let t = stripHTML(h)
            if t.count > 800, !isBlockPage(t) {
                let title = h.range(of: #"(?is)<title[^>]*>(.*?)</title>"#, options: .regularExpression).map { stripHTML(String(h[$0])) } ?? host
                return ReachItem(title: title, url: urlString, text: String(t.prefix(14000)), via: "Page")
            }
        }
        if backupOn, let t = await exaCall("web_fetch_exa", ["urls": [urlString], "maxCharacters": 14000]), t.count > 300 {
            return ReachItem(title: host, url: urlString, text: t, via: "Exa")
        }
        return await browserRead(url, agent: agent, runID: runID)
    }
    static func browserRead(_ url: URL, agent: TeamAgent, runID: String?) async -> ReachItem? {
        let p = await AgentBrowser.shared.readPage(url, agent: agent, runID: runID)
        guard p.text.count > 200 else { return nil }
        if isBlockPage(p.text) { return ReachItem(title: url.host ?? "", url: url.absoluteString, text: "(This site showed a robot check, so I couldn't read it. You can open it yourself.)", via: "Blocked") }
        if let s = Site.forHost(url.host ?? ""), looksLoggedOut(p.text) {
            return ReachItem(title: s.name, url: url.absoluteString, text: "(\(s.name) needs you to sign in first: Settings → Agents → Sign in to sites.)", via: "Needs sign-in")
        }
        return ReachItem(title: url.host ?? "", url: p.url, text: p.text, via: "Agent browser")
    }
    static func looksLoggedOut(_ t: String) -> Bool {
        let l = t.prefix(2500).lowercased()
        return (l.contains("log in") || l.contains("sign in") || l.contains("sign up")) && t.count < 2500
    }

    // MARK: Sites that need your sign-in (in Zuffi's agent browser — you sign in yourself, once)

    struct Site: Identifiable { let id: String; let name: String; let domain: String; let cookie: String; let login: String; let search: String
        static let all: [Site] = [
            Site(id: "x", name: "X (Twitter)", domain: "x.com", cookie: "auth_token", login: "https://x.com/i/flow/login", search: "https://x.com/search?q=%@&f=live"),
            Site(id: "instagram", name: "Instagram", domain: "instagram.com", cookie: "sessionid", login: "https://www.instagram.com/accounts/login/", search: "https://www.instagram.com/explore/search/keyword/?q=%@"),
            Site(id: "facebook", name: "Facebook", domain: "facebook.com", cookie: "c_user", login: "https://www.facebook.com/login", search: "https://www.facebook.com/search/top?q=%@"),
            Site(id: "linkedin", name: "LinkedIn", domain: "linkedin.com", cookie: "li_at", login: "https://www.linkedin.com/login", search: "https://www.linkedin.com/search/results/all/?keywords=%@"),
            Site(id: "reddit", name: "Reddit", domain: "reddit.com", cookie: "reddit_session", login: "https://www.reddit.com/login/", search: "https://old.reddit.com/search?q=%@"),
            Site(id: "xiaohongshu", name: "Xiaohongshu (RED)", domain: "xiaohongshu.com", cookie: "web_session", login: "https://www.xiaohongshu.com/explore", search: "https://www.xiaohongshu.com/search_result?keyword=%@"),
            Site(id: "bilibili", name: "Bilibili", domain: "bilibili.com", cookie: "SESSDATA", login: "https://passport.bilibili.com/login", search: "https://search.bilibili.com/all?keyword=%@"),
            Site(id: "xueqiu", name: "Xueqiu", domain: "xueqiu.com", cookie: "xq_a_token", login: "https://xueqiu.com/", search: "https://xueqiu.com/k?q=%@"),
        ]
        static func forHost(_ h: String) -> Site? { all.first { h == $0.domain || h.hasSuffix("." + $0.domain) } }
    }
    static func needsSignIn(_ host: String) -> Bool { ["x.com", "twitter.com", "instagram.com", "facebook.com", "xiaohongshu.com"].contains { host == $0 || host.hasSuffix("." + $0) } }

    // MARK: Each site's own reader (public, read-only)

    static func siteReader(_ url: URL, host: String) async -> ReachItem? {
        let path = url.path
        if host.hasSuffix("youtube.com") || host == "youtu.be" {
            let id = host == "youtu.be" ? String(path.dropFirst()) : URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value ?? (path.hasPrefix("/shorts/") ? String(path.dropFirst(8)) : "")
            if !id.isEmpty { return await youtubeVideo(id) }
        }
        if host == "github.com" {
            let parts = path.split(separator: "/").map(String.init)
            if parts.count >= 2 { return await githubRepo(parts[0], parts[1], issue: parts.count >= 4 && (parts[2] == "issues" || parts[2] == "pull") ? Int(parts[3]) : nil) }
        }
        if host.hasSuffix("reddit.com"), path.contains("/comments/") { return await redditPost(url) }
        if host.hasSuffix("linkedin.com"), path.hasPrefix("/jobs/view/") {
            let id = path.split(separator: "/").last.map { String($0).components(separatedBy: "-").last ?? String($0) } ?? ""
            return await linkedinJob(id)
        }
        if host.hasSuffix("v2ex.com"), path.hasPrefix("/t/"), let id = Int(path.split(separator: "/").dropFirst().first ?? "") { return await v2exTopic(id) }
        if host.hasSuffix("bilibili.com"), let r = path.range(of: #"BV[0-9A-Za-z]{10}"#, options: .regularExpression) { return await bilibiliVideo(String(path[r])) }
        if host.hasSuffix("xueqiu.com"), path.hasPrefix("/S/") { return await stockQuote(String(path.dropFirst(3))) }
        return nil
    }

    // YouTube: title, channel, description and the subtitles (no download, no key)
    static func youtubeVideo(_ id: String) async -> ReachItem? {
        guard let (d, _) = await get("https://www.youtube.com/watch?v=\(id)&hl=en", headers: ["Accept-Language": "en-GB,en;q=0.9"]), let h = String(data: d, encoding: .utf8),
              let r = h.range(of: "ytInitialPlayerResponse = ") else { return nil }
        let rest = h[r.upperBound...]
        guard let end = rest.range(of: ";</script>") ?? rest.range(of: ";var ") else { return nil }
        guard let j = try? JSONSerialization.jsonObject(with: Data(rest[..<end.lowerBound].utf8)) as? [String: Any] else { return nil }
        let v = j["videoDetails"] as? [String: Any] ?? [:]
        let title = v["title"] as? String ?? "YouTube video", author = v["author"] as? String ?? ""
        let mins = (Int(v["lengthSeconds"] as? String ?? "") ?? 0) / 60, views = v["viewCount"] as? String ?? ""
        var text = "Channel: \(author) · \(mins) min · \(views) views\n\nDescription:\n\(v["shortDescription"] as? String ?? "")"
        let tracks = (((j["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any])?["captionTracks"] as? [[String: Any]]) ?? []
        let track = tracks.first { ($0["languageCode"] as? String)?.hasPrefix("en") == true } ?? tracks.first
        if let base = track?["baseUrl"] as? String, let cj = await json(base + "&fmt=json3") as? [String: Any], let events = cj["events"] as? [[String: Any]] {
            let words = events.compactMap { e in (e["segs"] as? [[String: Any]])?.compactMap { $0["utf8"] as? String }.joined() }.joined().replacingOccurrences(of: "\n", with: " ")
            if words.count > 50 { text += "\n\nSubtitles:\n" + String(words.prefix(20000)) }
        } else { text += "\n\n(No subtitles available for this video.)" }
        return ReachItem(title: title, url: "https://www.youtube.com/watch?v=\(id)", text: text, via: "YouTube")
    }
    static func youtubeSearch(_ q: String, limit: Int = 6) async -> [ReachItem] {
        guard let (d, _) = await get("https://www.youtube.com/results?search_query=\(enc(q))&hl=en"), let h = String(data: d, encoding: .utf8) else { return [] }
        var out: [ReachItem] = [], seen = Set<String>()
        for part in h.components(separatedBy: "\"videoRenderer\":{\"videoId\":\"").dropFirst() {
            let id = String(part.prefix(11)); guard !seen.contains(id) else { continue }; seen.insert(id)
            let title = part.range(of: #""title":\{"runs":\[\{"text":"(.*?)""#, options: .regularExpression).map { String(part[$0]).components(separatedBy: "\"text\":\"").last?.dropLast().description ?? "" } ?? ""
            let ch = part.range(of: #""ownerText":\{"runs":\[\{"text":"(.*?)""#, options: .regularExpression).map { String(part[$0]).components(separatedBy: "\"text\":\"").last?.dropLast().description ?? "" } ?? ""
            out.append(ReachItem(title: title, url: "https://www.youtube.com/watch?v=\(id)", text: ch.isEmpty ? "" : "Channel: \(ch)", via: "YouTube"))
            if out.count >= limit { break }
        }
        return out
    }
    // GitHub (public API)
    static func githubRepo(_ owner: String, _ repo: String, issue: Int? = nil) async -> ReachItem? {
        let base = "https://api.github.com/repos/\(owner)/\(repo)"
        if let n = issue, let j = await json("\(base)/issues/\(n)") as? [String: Any] {
            var text = "#\(n) \(j["title"] as? String ?? "") — \(j["state"] as? String ?? "")\n\n\(j["body"] as? String ?? "")"
            if let cs = await json("\(base)/issues/\(n)/comments?per_page=20") as? [[String: Any]] {
                text += "\n\nComments:\n" + cs.map { "- \(($0["user"] as? [String: Any])?["login"] as? String ?? ""): \(($0["body"] as? String ?? "").prefix(600))" }.joined(separator: "\n")
            }
            return ReachItem(title: "\(owner)/\(repo)#\(n)", url: "https://github.com/\(owner)/\(repo)/issues/\(n)", text: text, via: "GitHub")
        }
        guard let j = await json(base) as? [String: Any] else { return nil }
        var text = "\(j["description"] as? String ?? "")\nStars: \(j["stargazers_count"] ?? 0) · Forks: \(j["forks_count"] ?? 0) · Language: \(j["language"] as? String ?? "") · Updated: \(j["pushed_at"] as? String ?? "")"
        if let (d, c) = await get("\(base)/readme", headers: ["Accept": "application/vnd.github.raw"]), c < 400, let rd = String(data: d, encoding: .utf8) { text += "\n\nREADME:\n" + String(rd.prefix(12000)) }
        return ReachItem(title: "\(owner)/\(repo)", url: "https://github.com/\(owner)/\(repo)", text: text, via: "GitHub")
    }
    static func githubSearch(_ q: String) async -> [ReachItem] {
        guard let j = await json("https://api.github.com/search/repositories?q=\(enc(q))&per_page=6") as? [String: Any], let items = j["items"] as? [[String: Any]] else { return [] }
        return items.map { ReachItem(title: $0["full_name"] as? String ?? "", url: $0["html_url"] as? String ?? "", text: "\($0["description"] as? String ?? "") · ★\($0["stargazers_count"] ?? 0)", via: "GitHub") }
    }
    // Reddit (public JSON; falls back to the agent browser with your sign-in)
    static func redditSearch(_ q: String, agent: TeamAgent, runID: String?) async -> [ReachItem] {
        if let j = await json("https://www.reddit.com/search.json?q=\(enc(q))&limit=8&sort=relevance") as? [String: Any],
           let kids = (j["data"] as? [String: Any])?["children"] as? [[String: Any]], !kids.isEmpty {
            return kids.compactMap { $0["data"] as? [String: Any] }.map { d in
                ReachItem(title: d["title"] as? String ?? "", url: "https://www.reddit.com" + (d["permalink"] as? String ?? ""), text: "r/\(d["subreddit"] as? String ?? "") · ▲\(d["score"] ?? 0) · \(d["num_comments"] ?? 0) comments\n\((d["selftext"] as? String ?? "").prefix(800))", via: "Reddit")
            }
        }
        if let u = URL(string: "https://old.reddit.com/search?q=\(enc(q))"), let r = await browserRead(u, agent: agent, runID: runID) { return [r] }
        return []
    }
    static func redditPost(_ url: URL) async -> ReachItem? {
        let base = url.absoluteString.components(separatedBy: "?").first ?? url.absoluteString
        guard let arr = await json((base.hasSuffix("/") ? String(base.dropLast()) : base) + ".json?limit=40") as? [[String: Any]], arr.count >= 2 else { return nil }
        let post = (((arr[0]["data"] as? [String: Any])?["children"] as? [[String: Any]])?.first?["data"] as? [String: Any]) ?? [:]
        let comments = ((arr[1]["data"] as? [String: Any])?["children"] as? [[String: Any]] ?? []).compactMap { $0["data"] as? [String: Any] }
        let text = "\(post["selftext"] as? String ?? "")\n\nTop comments:\n" + comments.prefix(25).compactMap { c in (c["body"] as? String).map { "- \(c["author"] as? String ?? ""): \($0.prefix(500))" } }.joined(separator: "\n")
        return ReachItem(title: post["title"] as? String ?? "Reddit post", url: base, text: text, via: "Reddit")
    }
    // LinkedIn jobs (public guest pages)
    static func linkedinJobs(_ q: String, location: String) async -> [ReachItem] {
        guard let (d, _) = await get("https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search?keywords=\(enc(q))&location=\(enc(location))&start=0"),
              let h = String(data: d, encoding: .utf8) else { return [] }
        return h.components(separatedBy: "<li").dropFirst().prefix(10).compactMap { li in
            func pick(_ cls: String) -> String { li.range(of: "class=\"\(cls)[^\"]*\"[^>]*>([\\s\\S]*?)</", options: .regularExpression).map { stripHTML(String(li[$0]).components(separatedBy: ">").dropFirst().joined(separator: ">").replacingOccurrences(of: "</", with: "")) } ?? "" }
            guard let lr = li.range(of: #"href="(https://[a-z.]*linkedin\.com/jobs/view/[^"?]+)"#, options: .regularExpression) else { return nil }
            let link = String(li[lr]).replacingOccurrences(of: "href=\"", with: "")
            return ReachItem(title: pick("base-search-card__title"), url: link, text: "\(pick("base-search-card__subtitle")) · \(pick("job-search-card__location"))", via: "LinkedIn")
        }
    }
    static func linkedinJob(_ id: String) async -> ReachItem? {
        guard !id.isEmpty, let (d, c) = await get("https://www.linkedin.com/jobs-guest/jobs/api/jobPosting/\(id)"), c < 400, let h = String(data: d, encoding: .utf8) else { return nil }
        let t = stripHTML(h)
        return t.count > 200 ? ReachItem(title: "LinkedIn job \(id)", url: "https://www.linkedin.com/jobs/view/\(id)", text: String(t.prefix(12000)), via: "LinkedIn") : nil
    }
    // V2EX (public API)
    static func v2exHot() async -> [ReachItem] {
        guard let arr = await json("https://www.v2ex.com/api/topics/hot.json") as? [[String: Any]] else { return [] }
        return arr.prefix(10).map { ReachItem(title: $0["title"] as? String ?? "", url: $0["url"] as? String ?? "", text: String(($0["content"] as? String ?? "").prefix(500)), via: "V2EX") }
    }
    static func v2exTopic(_ id: Int) async -> ReachItem? {
        guard let t = (await json("https://www.v2ex.com/api/topics/show.json?id=\(id)") as? [[String: Any]])?.first else { return nil }
        let replies = (await json("https://www.v2ex.com/api/replies/show.json?topic_id=\(id)") as? [[String: Any]] ?? []).prefix(40)
        let text = "\(t["content"] as? String ?? "")\n\nReplies:\n" + replies.map { "- \(($0["member"] as? [String: Any])?["username"] as? String ?? ""): \(($0["content"] as? String ?? "").prefix(300))" }.joined(separator: "\n")
        return ReachItem(title: t["title"] as? String ?? "V2EX topic", url: "https://www.v2ex.com/t/\(id)", text: text, via: "V2EX")
    }
    // Bilibili (public API)
    static func bilibiliVideo(_ bvid: String) async -> ReachItem? {
        guard let j = await json("https://api.bilibili.com/x/web-interface/view?bvid=\(bvid)", headers: ["Referer": "https://www.bilibili.com/"]) as? [String: Any],
              (j["code"] as? Int) == 0, let v = j["data"] as? [String: Any] else { return nil }
        let stat = v["stat"] as? [String: Any] ?? [:]
        return ReachItem(title: v["title"] as? String ?? bvid, url: "https://www.bilibili.com/video/\(bvid)",
                         text: "UP: \((v["owner"] as? [String: Any])?["name"] as? String ?? "") · views \(stat["view"] ?? 0) · likes \(stat["like"] ?? 0)\n\n\(v["desc"] as? String ?? "")", via: "Bilibili")
    }
    static func bilibiliSearch(_ q: String) async -> [ReachItem] {
        _ = await get("https://www.bilibili.com/")       // gets the normal visitor cookie, like any browser
        guard let j = await json("https://api.bilibili.com/x/web-interface/search/type?search_type=video&keyword=\(enc(q))", headers: ["Referer": "https://search.bilibili.com/"]) as? [String: Any],
              let res = (j["data"] as? [String: Any])?["result"] as? [[String: Any]] else { return [] }
        return res.prefix(8).map { ReachItem(title: stripHTML($0["title"] as? String ?? ""), url: "https://www.bilibili.com/video/\($0["bvid"] as? String ?? "")", text: "UP: \($0["author"] as? String ?? "") · plays \($0["play"] ?? 0)", via: "Bilibili") }
    }
    static func bilibiliPopular() async -> [ReachItem] {
        guard let j = await json("https://api.bilibili.com/x/web-interface/popular?ps=10&pn=1", headers: ["Referer": "https://www.bilibili.com/"]) as? [String: Any],
              let list = (j["data"] as? [String: Any])?["list"] as? [[String: Any]] else { return [] }
        return list.map { ReachItem(title: $0["title"] as? String ?? "", url: "https://www.bilibili.com/video/\($0["bvid"] as? String ?? "")", text: String(($0["desc"] as? String ?? "").prefix(300)), via: "Bilibili") }
    }
    // Stock quotes (China / HK / US) — Tencent's public quote line, the same numbers Xueqiu shows
    static func stockQuote(_ symbol: String) async -> ReachItem? {
        var s = symbol.uppercased().replacingOccurrences(of: ".", with: "")
        if s.hasPrefix("SH") || s.hasPrefix("SZ") || s.hasPrefix("HK") { s = s.prefix(2).lowercased() + String(s.dropFirst(2)) }
        else if s.allSatisfy(\.isNumber) { s = (s.count == 5 ? "hk" : s.hasPrefix("6") ? "sh" : "sz") + s }
        else { s = "us" + s }
        guard let (d, _) = await get("https://qt.gtimg.cn/q=\(s)") else { return nil }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        guard let body = String(data: d, encoding: gbk) ?? String(data: d, encoding: .utf8),
              let r = body.range(of: #"="([^"]*)""#, options: .regularExpression) else { return nil }
        let f = String(body[r]).dropFirst(2).dropLast().split(separator: "~", omittingEmptySubsequences: false).map(String.init)
        guard f.count > 34 else { return nil }
        return ReachItem(title: "\(f[1]) (\(s.uppercased()))", url: "https://xueqiu.com/S/\(s.uppercased())",
                         text: "Price \(f[3]) · change \(f[31]) (\(f[32])%) · open \(f[5]) · high \(f[33]) · low \(f[34]) · last close \(f[4]) · time \(f[30])", via: "Stock quote")
    }
    static func stockSearch(_ q: String) async -> [ReachItem] {
        guard let (d, _) = await get("https://smartbox.gtimg.cn/s3/?v=2&q=\(enc(q))&t=all"), let body = String(data: d, encoding: .utf8),
              let r = body.range(of: #"="([^"]*)""#, options: .regularExpression) else { return [] }
        let raw = String(body[r]).dropFirst(2).dropLast()
        let decoded = (try? JSONSerialization.jsonObject(with: Data("\"\(raw)\"".utf8), options: .fragmentsAllowed) as? String) ?? String(raw)
        var out: [ReachItem] = []
        for e in decoded.split(separator: "^").prefix(5) {
            let p = e.split(separator: "~").map(String.init); guard p.count >= 3 else { continue }
            if let q = await stockQuote(p[0] + p[1]) { out.append(q) }
        }
        return out
    }
    // Signed-in sites: search inside the agent browser with your own sign-in
    static func siteSearch(_ site: Site, _ q: String, agent: TeamAgent, runID: String?) async -> [ReachItem] {
        guard let u = URL(string: site.search.replacingOccurrences(of: "%@", with: enc(q))) else { return [] }
        guard await AgentBrowser.shared.isSignedIn(site.domain, cookie: site.cookie) || site.id == "reddit" || site.id == "bilibili" || site.id == "xueqiu" else {
            return [ReachItem(title: site.name, url: site.login, text: "(\(site.name) needs you to sign in once, inside Zuffi: Settings → Agents → Sign in to sites. Agents then read it with your sign-in — read only.)", via: "Needs sign-in")]
        }
        if let r = await browserRead(u, agent: agent, runID: runID) { return [r] }
        return []
    }

    // MARK: The research a senior would do: the right places for the question, several sources, then read the best ones

    static func research(_ task: String, agent: TeamAgent, runID: String?, step: (String) -> Void) async -> (notes: String, links: [WebLink]) {
        let q = String(task.components(separatedBy: "\n").first ?? task)
            .replacingOccurrences(of: #"(?i)^(ok(ay)?,? |please |zuffi,? |hey,? )*(can you |could you )?(research|search( for)?|look up|find( out| me)?|i('m| am)? looking for|i want(ed)? to know)( about| on| the)?[: ]*"#, with: "", options: .regularExpression)
            .prefix(180).description
        let l = task.lowercased()
        var found: [ReachItem] = []
        func add(_ items: [ReachItem]) { for i in items where !i.url.isEmpty && !found.contains(where: { $0.url == i.url }) { found.append(i) } }
        // Links in the task: read them directly
        let urls = (try? NSRegularExpression(pattern: #"https?://\S+"#)).map { re in re.matches(in: task, range: NSRange(task.startIndex..., in: task)).compactMap { Range($0.range, in: task).map { String(task[$0]) } } } ?? []
        // Platform places when the question asks for them
        if l.contains("youtube") || l.contains("video") { step("Searching YouTube"); add(await youtubeSearch(q)) }
        if l.contains("reddit") || l.range(of: #"\b(opinions?|experiences?|what do people think|real reviews)\b"#, options: .regularExpression) != nil { step("Reading Reddit"); add(await redditSearch(q, agent: agent, runID: runID)) }
        if l.contains("github") || l.range(of: #"\b(open.?source|repo|library|sdk)\b"#, options: .regularExpression) != nil { step("Searching GitHub"); add(await githubSearch(q)) }
        if l.range(of: #"\b(jobs?|vacanc|hiring|career)\b"#, options: .regularExpression) != nil {
            let loc = l.range(of: #"\bin ([a-z ]{3,30})"#, options: .regularExpression).map { String(l[$0].dropFirst(3)) } ?? ""
            step("Searching LinkedIn jobs"); add(await linkedinJobs(q, location: loc))
        }
        if l.contains("bilibili") || l.contains("b站") { step("Searching Bilibili"); add(await bilibiliSearch(q)) }
        if l.contains("v2ex") { step("Reading V2EX"); add(await v2exHot()) }
        if l.range(of: #"\b(stock|share price|xueqiu|雪球|股票|nasdaq|quote)\b"#, options: .regularExpression) != nil { step("Checking stock quotes"); add(await stockSearch(q)) }
        for s in ZuffiReach.Site.all where ["x", "instagram", "facebook", "xiaohongshu", "linkedin"].contains(s.id) && (l.contains(s.id) || l.contains(s.name.lowercased()) || (s.id == "x" && l.contains("twitter")) || (s.id == "xiaohongshu" && (l.contains("rednote") || l.contains("小红书")))) {
            step("Looking on \(s.name)"); add(await siteSearch(s, q, agent: agent, runID: runID))
        }
        // The web: Google (watch it in the agent browser), then backups
        step("Searching Google for “\(q.prefix(70))”")
        add(await search(q, agent: agent, runID: runID))
        // Read the pages themselves (links you gave first, then the best results)
        var notes: [String] = []
        let toRead = urls + found.filter { $0.via != "Needs sign-in" && $0.via != "Stock quote" }.map(\.url).filter { !urls.contains($0) }
        var readCount = 0
        for u in toRead where readCount < 4 {
            guard let host = URL(string: u)?.host else { continue }
            step("Reading \(host)")
            if let page = await read(u, agent: agent, runID: runID), page.text.count > 150 {
                readCount += 1
                notes.append("SOURCE \(notes.count + 1): \(page.title) — \(page.url) (via \(page.via))\n\(page.text.prefix(4500))")
            }
        }
        // Short results (snippets, quotes, sign-in notes) also count as sources
        let shorts = found.prefix(10).map { "• \($0.title) — \($0.url)\($0.text.isEmpty ? "" : ": " + String($0.text.prefix(300))) (\($0.via))" }
        if !shorts.isEmpty { notes.append("SEARCH RESULTS:\n" + shorts.joined(separator: "\n")) }
        // Latest news (free)
        let news = await AIService.webSearch(q)
        if !news.notes.isEmpty { notes.append("NEWS AND REFERENCE:\n" + news.notes) }
        step(readCount > 0 ? "Read \(readCount) page\(readCount == 1 ? "" : "s") — comparing them" : "Couldn't open the pages — working from the search results")
        var links = found.map { WebLink(title: $0.title.isEmpty ? (URL(string: $0.url)?.host ?? $0.url) : $0.title, url: $0.url) }
        for l in news.links where !links.contains(where: { $0.url == l.url }) { links.append(l) }
        return (notes.joined(separator: "\n\n"), links)
    }
}

/// Settings → Agents: sign in to sites inside Zuffi's own agent browser, so agents can read them (read only).
struct ReachSitesView: View {
    var light = false
    @State private var signed: Set<String> = []
    init(light: Bool = false) { self.light = light }
    private var T: HubTheme { HubTheme(light: light) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sign in to sites").font(HubFont.p(17, .semibold)).padding(.bottom, 4)
            Text("Sign in once inside Zuffi's agent browser — you type your own password there; Zuffi never sees it. Agents then read these sites with your sign-in. They only read: never post, like, follow or send.")
                .font(HubFont.p(13, .regular)).foregroundColor(T.inactive).fixedSize(horizontal: false, vertical: true).padding(.bottom, 12)
            VStack(spacing: 0) {
                ForEach(Array(ZuffiReach.Site.all.enumerated()), id: \.element.id) { i, site in
                    HStack(spacing: 14) {
                        Circle().fill(signed.contains(site.id) ? Color(hex: "#3DBE7E") : T.inactive.opacity(0.5)).frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(site.name).font(HubFont.p(14))
                            Text(signed.contains(site.id) ? "Signed in — agents can read it" : "Not signed in").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                        }
                        Spacer()
                        Button { if let u = URL(string: site.login) { AgentBrowser.shared.signIn(site.name, url: u) } } label: {
                            Text(signed.contains(site.id) ? "Open" : "Sign in").font(HubFont.p(13)).foregroundColor(.white).padding(.horizontal, 14).frame(height: 30).background(Capsule().fill(HubTheme.blue))
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
        }
        .task { await refresh() }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in Task { await refresh() } }
    }
    private func refresh() async {
        var s: Set<String> = []
        for site in ZuffiReach.Site.all { if await AgentBrowser.shared.isSignedIn(site.domain, cookie: site.cookie) { s.insert(site.id) } }
        signed = s
    }
}

// MARK: - Business research: name + link → the team reads about the business and its competitors, then makes a growth plan

@MainActor
final class BusinessResearch: ObservableObject {
    static let shared = BusinessResearch()
    @Published var running = false
    @Published var report: String = UserDefaults.standard.string(forKey: "bizResearchReport") ?? ""
    @Published var at: Date? = UserDefaults.standard.object(forKey: "bizResearchAt") as? Date
    @Published var stage = ""

    private var form: [String: String] { (UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:] }

    func start() {
        guard !running else { return }
        running = true; stage = "Starting"
        Task { @MainActor in await self.run(); self.running = false }
    }

    private func run() async {
        let team = ZuffiTeam.shared
        let name = ZuffiBusiness.shared.businessName.trimmingCharacters(in: .whitespaces)
        let link = (form["website"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let area = (form["address"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let researcher = team.agent("zuffi-competitors") ?? team.agent("research-synthesist") ?? ZuffiTeam.manager
        let task = "Research \(name) and its competitors, then make a growth plan"
        MissionControl.shared.begin(task, agents: [researcher.id])
        let id = team.begin(researcher, task)
        func say(_ t: String) { stage = t; team.step(id, t, source: "Web") }
        var sources: [String] = [], links: [WebLink] = []
        func keep(_ i: ReachItem?) { guard let i, i.text.count > 120 else { return }; sources.append("SOURCE \(sources.count + 1): \(i.title) — \(i.url) (via \(i.via))\n\(i.text.prefix(5000))"); links.append(WebLink(title: i.title, url: i.url)) }

        // 1) The business's own page
        var site = link
        if !site.isEmpty, !site.hasPrefix("http") { site = "https://" + site }
        if !site.isEmpty { say("Reading your page: \(URL(string: site)?.host ?? site)"); keep(await ZuffiReach.read(site, agent: researcher, runID: id)) }
        // 2) Google: the business, its reviews
        let local = [name, area.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        say("Searching Google for \(local)")
        let mine = await ZuffiReach.search(local, agent: researcher, runID: id, limit: 8)
        say("Searching for reviews of \(name)")
        let reviews = await ZuffiReach.search("\(local) reviews", agent: researcher, runID: id, limit: 6)
        for r in (mine + reviews).prefix(4) where !links.contains(where: { $0.url == r.url }) && r.url != site { say("Reading \(URL(string: r.url)?.host ?? r.url)"); keep(await ZuffiReach.read(r.url, agent: researcher, runID: id)) }
        let snippets = (mine + reviews).map { "• \($0.title) — \($0.url): \($0.text.prefix(250))" }.joined(separator: "\n")
        // 3) What kind of business is it? → find competitors nearby
        say("Working out your type of business")
        let kind = (await AIService.shared.oneShot("From this, what kind of business is \(name)? Reply with 2-4 words only, like \"hair salon\" or \"estate agent\".\n\n" + String((sources.joined(separator: "\n") + "\n" + snippets).prefix(8000)), system: "Reply with the type of business in 2-4 words only.") ?? "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " .\"\n"))
        let place = area.isEmpty ? (ZuffiCRM.shared.country == "PK" ? "Pakistan" : "UK") : (area.components(separatedBy: ",").last ?? area).trimmingCharacters(in: .whitespaces)
        var competitors: [ReachItem] = []
        if !kind.isEmpty, kind.count < 40 {
            say("Finding \(kind) competitors in \(place)")
            competitors = (await ZuffiReach.search("best \(kind) in \(place)", agent: researcher, runID: id, limit: 8))
                .filter { c in !c.title.lowercased().contains(name.lowercased()) && !links.contains { $0.url == c.url } }
            for c in competitors.prefix(3) { say("Reading competitor: \(URL(string: c.url)?.host ?? c.url)"); keep(await ZuffiReach.read(c.url, agent: researcher, runID: id)) }
        }
        let compSnips = competitors.map { "• \($0.title) — \($0.url): \($0.text.prefix(250))" }.joined(separator: "\n")
        guard !sources.isEmpty || !snippets.isEmpty else {
            team.finish(id, "I couldn't find \(name) online yet. Add your website or Instagram/Facebook link in Business → Settings and I'll try again.", "Needs input")
            stage = "Couldn't find the business online"; return
        }
        // 4) Fill in empty form details from what was found (never overwrite yours)
        say("Filling in the details I found")
        if let raw = await AIService.shared.oneShot("""
            From these pages about \(name), copy ONLY facts that are written there. JSON only:
            {"address":"","phone":"","hours":"","services":"one per line with prices if shown","payment":"","booking":""}
            Leave a field empty if it isn't written in the pages.
            \(String(sources.joined(separator: "\n\n").prefix(16000)))
            """), let a = raw.firstIndex(of: "{"), let b = raw.lastIndex(of: "}"),
           let j = try? JSONSerialization.jsonObject(with: Data(String(raw[a...b]).utf8)) as? [String: String] {
            var f = form; var filled: [String] = []
            for (k, v) in j where !v.trimmingCharacters(in: .whitespaces).isEmpty && (f[k] ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                let all = sources.joined(separator: " ").lowercased()
                // keep only what really appears in the pages (first words check)
                let probe = v.lowercased().split(separator: " ").prefix(3).joined(separator: " ")
                if all.contains(probe) { f[k] = v; filled.append(k) }
            }
            if !filled.isEmpty { UserDefaults.standard.set(f, forKey: "bizForm"); BizDetailsForm.rebuildInfo(); say("Filled in: " + filled.joined(separator: ", ")) }
        }
        // 5) The report and plan
        say("Comparing you with your competitors and writing the plan")
        let ids = ZuffiTeam.businessTeam + ["finance-financial-analyst", "zuffi-bookings", "zuffi-crm"]
        let menu = ids.compactMap { team.agent($0) }.map { "\($0.id): \($0.name)" }.joined(separator: "\n")
        let prompt = """
        You are Nik, a senior business growth manager. Write a report for the owner of \(name)\(kind.isEmpty ? "" : " (\(kind))") in \(place).
        Use ONLY facts from the sources below; when something isn't known, say so. Every competitor fact needs its source link.
        Sections (plain text, short lines, use "- " bullets):
        ## What I found about you
        ## What customers say
        ## Your competitors (3-5: name, what they do better, prices if shown, link)
        ## What you're missing
        ## Your 30-day growth plan (week 1–4, concrete actions)
        ## Agents to hire (2-4 from this list, each with one line why)
        At the very end add one line: HIRE: id1, id2, id3 (ids from this list only)
        \(menu)
        THE BUSINESS'S DETAILS:
        \(ZuffiTeam.businessContext.prefix(2500))
        SEARCH RESULTS:
        \(snippets.prefix(3000))
        COMPETITOR RESULTS:
        \(compSnips.prefix(3000))
        PAGES READ:
        \(String(sources.joined(separator: "\n\n").prefix(26000)))
        """
        guard let text = await AIService.shared.oneShot(prompt, system: "You are a careful senior business consultant. Facts only from the sources, with links. Plain text."), text.count > 200 else {
            team.finish(id, "I read about your business but couldn't write the plan — check that an AI is set up in Settings.", "Failed"); stage = "Couldn't write the plan"; return
        }
        var body = text
        if let r = text.range(of: #"(?m)^HIRE:.*$"#, options: .regularExpression) {
            let hire = text[r].dropFirst(5).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { ids.contains($0) }
            body.removeSubrange(r)
            team.suggestions = hire.compactMap { h in team.agent(h).map { AgentSuggestion(agent: $0.id, reason: "Suggested by Nik after researching your business") } }
        }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\nSources:\n" + links.prefix(10).map { "• \($0.title.prefix(70)) — \($0.url)" }.joined(separator: "\n")
        report = body; at = Date()
        UserDefaults.standard.set(body, forKey: "bizResearchReport"); UserDefaults.standard.set(Date(), forKey: "bizResearchAt")
        if let i = team.runs.firstIndex(where: { $0.id == id }) { team.runs[i].links = Array(links.prefix(12)) }
        team.finish(id, body, "Done")
        MissionControl.shared.result = body
        stage = "Done"
        NotchInbox.shared.add("Your business plan is ready", "Nik researched \(name) and \(competitors.count) competitors", icon: "chart.line.uptrend.xyaxis", action: "dashboard")
        BizNav.shared.say("Nik's business plan is ready — see Home")
    }
}

struct BusinessReportCard: View {
    var light = false
    @ObservedObject private var br = BusinessResearch.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var open = false
    init(light: Bool = false) { self.light = light }
    private var T: HubTheme { HubTheme(light: light) }
    var body: some View {
        if nav.formDone && !ZuffiPlan.shared.isPersonal {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 16, weight: .semibold)).foregroundColor(.white).frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 9).fill(HubTheme.blue))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your business & competitors").font(HubFont.p(17, .semibold))
                        Text(br.running ? br.stage : br.at.map { "Researched " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not researched yet")
                            .font(HubFont.p(13, .regular)).foregroundColor(T.inactive).lineLimit(1)
                    }
                    Spacer()
                    if br.running { ProgressView().controlSize(.small); Button("Watch") { ZuffiHub.shared.show(.office) }.buttonStyle(.plain).font(HubFont.p(13)) }
                    else {
                        if !br.report.isEmpty { Button { open.toggle() } label: { Text(open ? "Hide" : "Read the plan").font(HubFont.p(13)).foregroundColor(T.text).padding(.horizontal, 14).frame(height: 32).overlay(Capsule().stroke(T.border)) }.buttonStyle(.plain) }
                        Button { br.start() } label: { Text(br.report.isEmpty ? "Research now" : "Research again").font(HubFont.p(13)).foregroundColor(.white).padding(.horizontal, 14).frame(height: 32).background(Capsule().fill(HubTheme.blue)) }.buttonStyle(.plain)
                    }
                }
                if open, !br.report.isEmpty {
                    ChatRichText(text: br.report).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Edit an agent: its name, colour, your own instructions and its daily jobs

struct AgentEdit: Codable { var name = ""; var color: String? = nil; var notes = "" }

enum AgentEdits {
    static func all() -> [String: AgentEdit] {
        guard let d = UserDefaults.standard.data(forKey: "agentEdits"), let m = try? JSONDecoder().decode([String: AgentEdit].self, from: d) else { return [:] }
        return m
    }
    static func get(_ id: String) -> AgentEdit { all()[id] ?? AgentEdit() }
    static func set(_ id: String, _ e: AgentEdit) {
        var m = all(); m[id] = e
        if let d = try? JSONEncoder().encode(m) { UserDefaults.standard.set(d, forKey: "agentEdits") }
    }
    static func name(_ a: TeamAgent) -> String { let n = get(a.id).name.trimmingCharacters(in: .whitespaces); return n.isEmpty ? a.name : n }
}

@MainActor
enum AgentEditor {
    private static var window: NSWindow?
    static func open(_ a: TeamAgent) {
        window?.close()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Edit \(AgentEdits.name(a))"; w.titlebarAppearsTransparent = true; w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: AgentEditView(agent: a) { w.close() })
        w.center(); window = w
        w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct AgentEditView: View {
    let agent: TeamAgent
    var done: () -> Void
    @ObservedObject private var team = ZuffiTeam.shared
    @State private var name = ""
    @State private var color = Color.blue
    @State private var useColor = false
    @State private var notes = ""
    private let swatches = ["#3A6DF0", "#33C3A4", "#F07FAA", "#F5B963", "#9B7BFF", "#E5534B", "#3DBE7E", "#E1306C", "#1877F2", "#25D366"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    RobotFace(agent: agent, size: 54).id(useColor ? color.description : "default")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.name).font(HubFont.p(18, .semibold))
                        Text(agent.description).font(HubFont.p(12, .regular)).foregroundColor(.white.opacity(0.6)).lineLimit(3)
                    }
                }
                field("Name") { TextField(agent.name, text: $name).textFieldStyle(.roundedBorder) }
                field("Colour") {
                    HStack(spacing: 8) {
                        ForEach(swatches, id: \.self) { h in
                            Circle().fill(Color(hex: h)).frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.white, lineWidth: useColor && color.description == Color(hex: h).description ? 2 : 0))
                                .onTapGesture { color = Color(hex: h); useColor = true }
                        }
                        ColorPicker("", selection: Binding(get: { color }, set: { color = $0; useColor = true })).labelsHidden()
                        Button("Default") { useColor = false }.buttonStyle(.plain).font(HubFont.p(12)).foregroundColor(.white.opacity(0.7))
                    }
                }
                field("Your instructions") {
                    TextEditor(text: $notes).font(HubFont.p(13, .regular)).frame(height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2)))
                    Text("For example: “Always give prices in PKR”, “Our budget is under £500”, “Write in a friendly, short style”.").font(HubFont.p(11, .regular)).foregroundColor(.white.opacity(0.5))
                }
                field("Daily jobs") {
                    let jobs = team.jobs.filter { $0.agent == agent.id }
                    if jobs.isEmpty { Text("No daily job. Ask Nik for new tasks on Home.").font(HubFont.p(12, .regular)).foregroundColor(.white.opacity(0.6)) }
                    ForEach(jobs) { j in
                        HStack {
                            Toggle("", isOn: Binding(get: { j.enabled }, set: { v in if let i = team.jobs.firstIndex(where: { $0.id == j.id }) { team.jobs[i].enabled = v } })).labelsHidden()
                            Text(j.title).font(HubFont.p(13))
                            Spacer()
                            DatePicker("", selection: Binding(get: {
                                Calendar.current.date(bySettingHour: j.hour, minute: j.minute, second: 0, of: Date()) ?? Date()
                            }, set: { d in
                                if let i = team.jobs.firstIndex(where: { $0.id == j.id }) { let c = Calendar.current.dateComponents([.hour, .minute], from: d); team.jobs[i].hour = c.hour ?? j.hour; team.jobs[i].minute = c.minute ?? j.minute }
                            }), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 90)
                            Button { team.jobs.removeAll { $0.id == j.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                    Button("Save") { save(); done() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(24).padding(.top, 14)
        }
        .foregroundColor(.white)
        .background(Color(hex: "#14161F"))
        .onAppear {
            let e = AgentEdits.get(agent.id)
            name = e.name; notes = e.notes
            if let c = e.color, !c.isEmpty { color = Color(hex: c); useColor = true }
        }
    }
    @ViewBuilder private func field<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(HubFont.p(12, .semibold)).foregroundColor(.white.opacity(0.7)); c() }
    }
    private func save() {
        var hex: String? = nil
        if useColor, let n = NSColor(color).usingColorSpace(.deviceRGB) {
            hex = String(format: "#%02X%02X%02X", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))
        }
        AgentEdits.set(agent.id, AgentEdit(name: name.trimmingCharacters(in: .whitespaces), color: hex, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)))
        team.objectWillChange.send()
        OfficeModel.shared.rebuild()
    }
}
