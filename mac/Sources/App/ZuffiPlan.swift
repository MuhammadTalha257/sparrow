import SwiftUI
import AppKit

/// Which Zuffi plan this Mac has. The web part of the app signs in and checks the signed licence,
/// then tells us here ("plan" message), so the native parts can follow the same rules.
final class ZuffiPlan: ObservableObject {
    static let shared = ZuffiPlan()
    @Published private(set) var plan: String = UserDefaults.standard.string(forKey: "zuffiPlan") ?? "free"
    @Published private(set) var email: String = UserDefaults.standard.string(forKey: "zuffiPlanEmail") ?? ""
    private(set) var freeLeads: Int = { let n = UserDefaults.standard.integer(forKey: "zuffiFreeLeads"); return n > 0 ? n : 30 }()
    private var lastAsk = Date.distantPast

    var isBusiness: Bool { plan == "business" }
    var isPaid: Bool { plan == "pro" || plan == "business" }
    var name: String { ["pro": "Pro", "business": "Business"][plan] ?? "Free" }

    func update(plan: String, email: String, freeLeads: Int) {
        DispatchQueue.main.async {
            self.plan = ["pro", "business"].contains(plan) ? plan : "free"
            self.email = email
            self.freeLeads = freeLeads > 0 ? freeLeads : 30
            let d = UserDefaults.standard
            d.set(self.plan, forKey: "zuffiPlan"); d.set(email, forKey: "zuffiPlanEmail"); d.set(self.freeLeads, forKey: "zuffiFreeLeads")
        }
    }

    func leadRoom(current: Int) -> Bool { isBusiness || current < freeLeads }

    /// Opens Settings → Zuffi account in the Zuffi panel (sign in / upgrade live there).
    func openAccount() {
        WebHub.shared.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            WebHub.shared.run("window.Sparrow && window.Sparrow.openSettings && window.Sparrow.openSettings('account')")
        }
    }

    func askToUpgrade() {
        DispatchQueue.main.async {
            guard Date().timeIntervalSince(self.lastAsk) > 20 else { return }   // once, not for every lead in an import
            self.lastAsk = Date()
            let a = NSAlert()
            a.messageText = "You’ve reached \(self.freeLeads) leads"
            a.informativeText = "The free plan keeps up to \(self.freeLeads) leads. Zuffi Business gives you unlimited leads, the same business on every device and the automations."
            a.addButton(withTitle: "See Business"); a.addButton(withTitle: "Not now")
            if a.runModal() == .alertFirstButtonReturn { self.openAccount() }
        }
    }
}

/// Settings → "Zuffi account" row on the Mac.
struct ZuffiPlanSettings: View {
    @ObservedObject private var p = ZuffiPlan.shared
    var body: some View {
        GroupBox("Zuffi account & plan") {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.email.isEmpty ? "Not signed in" : p.email).font(.system(size: 13, weight: .semibold))
                    Text(p.isPaid ? "Zuffi \(p.name) is on for this Mac." : "Free plan — sign in to use Pro or Business here.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(p.name).font(.system(size: 11, weight: .bold)).padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Capsule().fill(p.isPaid ? Color(hex: "#E2648A") : Color.secondary.opacity(0.2)))
                    .foregroundStyle(p.isPaid ? Color.white : Color.primary)
                Button(p.email.isEmpty ? "Sign in…" : "Manage…") { p.openAccount() }
            }
            .padding(6)
        }
    }
}
