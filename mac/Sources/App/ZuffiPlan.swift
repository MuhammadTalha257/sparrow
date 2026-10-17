import SwiftUI
import AppKit

/// Which Zuffi plan this Mac has. The web part of the app signs in and checks the signed licence,
/// then tells us here ("plan" message), so the native parts can follow the same rules.
@MainActor
final class ZuffiPlan: ObservableObject {
    static let shared = ZuffiPlan()
    @Published private(set) var plan: String = UserDefaults.standard.string(forKey: "zuffiPlan") ?? "free"
    @Published private(set) var email: String = UserDefaults.standard.string(forKey: "zuffiPlanEmail") ?? ""
    private(set) var freeLeads: Int = { let n = UserDefaults.standard.integer(forKey: "zuffiFreeLeads"); return n > 0 ? n : 30 }()
    private var lastAsk = Date.distantPast

    var isBusiness: Bool { plan == "business" || plan == "trial" }      // the trial switches everything on
    var isPaid: Bool { plan == "pro" || plan == "business" || plan == "trial" }
    /// No plan (trial over, or never signed in): Zuffi pauses until one is chosen. Nothing is deleted.
    /// A new install starts locked: signing in with an email starts the 3-day trial.
    var isLocked: Bool { !isPaid }
    var name: String { ["trial": "Free trial", "pro": "Pro", "business": "Business"][plan] ?? "No plan" }
    private var shownLock = false
    private var lockedBefore: Bool? = nil
    private var lastBlock = Date.distantPast

    /// What Zuffi says when someone tries to use her without a plan.
    var lockedMessage: String {
        email.isEmpty ? "Hi! Sign in with your email to start your free 3-day trial. Everything switches on, no card needed."
                      : "Your free trial has ended. Choose Pro or Business to keep using Zuffi. Nothing you saved is deleted."
    }

    /// Call before any feature. Returns true (and shows sign-in / plans) when Zuffi is locked.
    @discardableResult
    func blocked(speak: Bool = false) -> Bool {
        guard isLocked else { return false }
        if speak { VoiceEngine.shared.speak(lockedMessage) }       // asked by voice → answer by voice
        let s = AppState.shared
        s.noteMessage = "🐰 " + lockedMessage
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        if Date().timeIntervalSince(lastBlock) > 4 { lastBlock = Date(); openAccount() }
        return true
    }

    func update(plan: String, email: String, freeLeads: Int) {
        self.plan = ["trial", "pro", "business"].contains(plan) ? plan : "free"
        self.email = email
        self.freeLeads = freeLeads > 0 ? freeLeads : 30
        let d = UserDefaults.standard
        d.set(self.plan, forKey: "zuffiPlan"); d.set(email, forKey: "zuffiPlanEmail"); d.set(self.freeLeads, forKey: "zuffiFreeLeads")
        let wasLocked = lockedBefore; lockedBefore = isLocked
        if isLocked && !shownLock { shownLock = true; openAccount() }        // show the paywall once when Zuffi locks
        if !isLocked { shownLock = false }
        // "Hey Zuffi" listening pauses with the plan and comes back with it
        if wasLocked != isLocked {
            let wake = UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord)
            if isLocked { VoiceEngine.shared.setWakeWord(false) } else if wasLocked == true, wake { VoiceEngine.shared.setWakeWord(true) }
        }
    }

    func leadRoom(current: Int) -> Bool { isBusiness || current < freeLeads }

    /// Opens Settings → Zuffi account in the Zuffi panel (sign in / upgrade live there).
    func openAccount() {
        WebHub.shared.show()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            WebHub.shared.run("window.Sparrow && window.Sparrow.openSettings && window.Sparrow.openSettings('account')")
        }
    }

    func askToUpgrade() {
        guard Date().timeIntervalSince(lastAsk) > 20 else { return }   // once, not for every lead in an import
        lastAsk = Date()
        Task { @MainActor in                                           // after the current save finishes
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
                    Text(p.plan == "trial" ? "Your free trial is on — everything is switched on." : p.isPaid ? "Zuffi \(p.name) is on for this Mac." : "No plan — sign in to start your 3-day free trial, or choose a plan.")
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
