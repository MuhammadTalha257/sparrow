import Foundation
import SwiftUI

// =====================================================================
// MARK: - Zuffi's team (agency-agents, MIT licence — see THIRD_PARTY_NOTICES.md)
//
// 289 specialists (sales, marketing, finance, engineering, support, real estate…).
// Pick one in the chat line or say "use the sales coach agent"; Zuffi then answers
// as that specialist until you say "back to normal" / "stop the agent".
// =====================================================================

struct TeamAgent: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let division: String
    let name: String
    let description: String
    let emoji: String
    let prompt: String
}

@MainActor
final class ZuffiTeam: ObservableObject {
    static let shared = ZuffiTeam()

    @Published private(set) var agents: [TeamAgent] = []
    @Published var activeID: String = UserDefaults.standard.string(forKey: "teamAgent") ?? "" {
        didSet { UserDefaults.standard.set(activeID, forKey: "teamAgent") }
    }

    var active: TeamAgent? { activeID.isEmpty ? nil : agents.first { $0.id == activeID } }

    /// Divisions in a friendly order: business ones first.
    var divisions: [String] {
        let order = ["sales", "marketing", "paid-media", "support", "finance", "strategy", "project-management", "product",
                     "specialized", "design", "engineering", "testing", "security", "healthcare", "academic", "research"]
        let all = Set(agents.map(\.division))
        return order.filter(all.contains) + all.subtracting(order).sorted()
    }

    func members(of division: String) -> [TeamAgent] { agents.filter { $0.division == division }.sorted { $0.name < $1.name } }

    static func divisionLabel(_ d: String) -> String {
        d.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
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
        }
    }

    /// Extra instructions added to every AI's system prompt while an agent is active.
    var persona: String {
        guard let a = active else { return "" }
        return """


        For this conversation you are working as "\(a.name)" from Zuffi's team (\(Self.divisionLabel(a.division))). \
        Keep Zuffi's friendly voice and plain text, but think and answer as this specialist:

        \(a.prompt.prefix(9000))
        """
    }

    func use(_ a: TeamAgent?) {
        activeID = a?.id ?? ""
        AIService.shared.clearConversation()
    }

    /// Finds an agent by words the user said ("sales coach", "seo", "real estate").
    func find(_ words: String) -> TeamAgent? {
        let w = words.lowercased().replacingOccurrences(of: #"\b(the|a|an|agent|specialist|expert|team|member)\b"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return nil }
        if let exact = agents.first(where: { $0.name.lowercased() == w }) { return exact }
        let tokens = w.split(separator: " ").map(String.init).filter { $0.count > 1 }
        let scored = agents.map { a -> (TeamAgent, Int) in
            let n = a.name.lowercased(), d = a.description.lowercased()
            return (a, tokens.reduce(0) { $0 + (n.contains($1) ? 3 : 0) + (d.contains($1) ? 1 : 0) })
        }.filter { $0.1 > 0 }
        return scored.max { $0.1 < $1.1 }?.0
    }

    /// "use the sales coach agent", "switch to SEO specialist", "stop the agent", "who is on my team?"
    func handle(_ raw: String) -> String? {
        let t = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        if t.range(of: #"^(stop|leave|exit|end|close|drop) (the |this )?(agent|specialist|team member)$|^back to (normal|zuffi)$|^be (normal|zuffi) again$"#, options: .regularExpression) != nil {
            guard active != nil else { return "You're already talking to plain Zuffi." }
            use(nil); return "Okay, I'm just Zuffi again."
        }
        if t.range(of: #"^(who('s| is) (on )?(my|your) team|list (the |my |your )?(team|agents)|show (me )?(the |my |your )?(team|agents))$"#, options: .regularExpression) != nil {
            let lines = divisions.map { "\(Self.divisionLabel($0)): \(members(of: $0).count)" }
            return "I have \(agents.count) specialists:\n" + lines.joined(separator: "\n") + "\n\nSay “use the sales coach agent”, or pick one with the people button in the chat line."
        }
        if t.range(of: #"^(which|what) agent"#, options: .regularExpression) != nil {
            return active.map { "Right now I'm working as \($0.emoji) \($0.name)." } ?? "No agent — I'm plain Zuffi."
        }
        let pattern = #"^(?:use|switch to|talk to|call|bring in|get|act as|be) (?:the |my |a |an )?(.+?) (?:agent|specialist|expert)$|^(?:use|switch to|act as) agent (.+)$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        let r = m.range(at: 1).location != NSNotFound ? m.range(at: 1) : m.range(at: 2)
        guard let rr = Range(r, in: t) else { return nil }
        guard let a = find(String(t[rr])) else { return "I couldn't find that agent. Say “show my team” to see who's here." }
        use(a)
        return "\(a.emoji) \(a.name) here. \(a.description.prefix(160)) What do you need?"
    }
}

// MARK: - Team picker (chat line + settings)

struct TeamMenu: View {
    @ObservedObject private var team = ZuffiTeam.shared
    var compact = true

    var body: some View {
        Menu {
            if team.active != nil {
                Button { team.use(nil) } label: { Label("Plain Zuffi (no agent)", systemImage: "xmark.circle") }
                Divider()
            }
            ForEach(team.divisions, id: \.self) { d in
                Menu(ZuffiTeam.divisionLabel(d)) {
                    ForEach(team.members(of: d)) { a in
                        Button { team.use(a) } label: {
                            Text("\(a.emoji) \(a.name)\(a.id == team.activeID ? "  ✓" : "")")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                if let a = team.active {
                    Text(a.emoji).font(.system(size: 11))
                    if !compact { Text(a.name).font(.system(size: 10, weight: .medium)).lineLimit(1) }
                } else {
                    Image(systemName: "person.3.fill").font(.system(size: 10, weight: .semibold))
                    if !compact { Text("Team").font(.system(size: 10, weight: .medium)) }
                }
            }
            .foregroundColor(.white.opacity(0.8))
            .padding(.horizontal, 7).frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(team.active == nil ? 0.08 : 0.2)))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(team.active.map { "Working as \($0.name)" } ?? "Pick a specialist from Zuffi's team")
    }
}

/// Compact model chip for the chat line (icon only).
struct ModelChip: View {
    @ObservedObject var state: AppState
    var body: some View {
        let current = AIProvider(rawValue: state.aiProvider) ?? .auto
        Menu {
            ForEach(AIProvider.allCases) { p in
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
                Text("\(team.agents.count) specialists — sales, marketing, finance, support, engineering and more. Pick one and Zuffi answers as that expert. Say “back to normal” to stop.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack { Text("Working as:"); Text(team.active.map { "\($0.emoji) \($0.name)" } ?? "Plain Zuffi").bold(); Spacer()
                    if team.active != nil { Button("Stop") { team.use(nil) }.controlSize(.small) } }
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
                            Button(a.id == team.activeID ? "In use" : "Use") { team.use(a) }.controlSize(.small).disabled(a.id == team.activeID)
                        }
                    }
                }
                Text("Team from “agency-agents” (MIT licence).").font(.system(size: 9.5)).foregroundColor(.secondary)
            }.padding(6)
        }
    }
}
