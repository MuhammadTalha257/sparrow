import SwiftUI
import AppKit
import WebKit

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
        let before = self.plan
        self.plan = ["trial", "pro", "business"].contains(plan) ? plan : "free"
        // Just bought Business: Zuffi asks for the business details first (the Business page opens with the form).
        if before != "business", self.plan == "business", before != "free" || !email.isEmpty, !BizDetailsForm.isComplete, !isPersonal {
            Task { @MainActor in try? await Task.sleep(nanoseconds: 1_200_000_000); BusinessDashboard.shared.show() }
        }
        self.email = email
        self.freeLeads = freeLeads > 0 ? freeLeads : 30
        let d = UserDefaults.standard
        d.set(self.plan, forKey: "zuffiPlan"); d.set(email, forKey: "zuffiPlanEmail"); d.set(self.freeLeads, forKey: "zuffiFreeLeads")
        let wasLocked = lockedBefore; lockedBefore = isLocked
        checkOldKeys()
        if isLocked && !shownLock { shownLock = true; openAccount() }        // show the paywall once when Zuffi locks
        if !isLocked { shownLock = false }
        // "Hey Zuffi" listening pauses with the plan and comes back with it
        if wasLocked != isLocked {
            let wake = UserDefaults.standard.bool(forKey: AssistantPrefs.wakeWord)
            if isLocked { VoiceEngine.shared.setWakeWord(false) } else if wasLocked == true, wake { VoiceEngine.shared.setWakeWord(true) }
        }
    }

    func leadRoom(current: Int) -> Bool { isBusiness || current < freeLeads }

    /// AI keys saved on this Mac before this person signed in (an old install, or someone else's)?
    /// macOS keeps them after an app is deleted, so ask once: keep them or remove them.
    private var askedKeys = false
    private func checkOldKeys() {
        guard !email.isEmpty, !askedKeys else { return }
        let owner = UserDefaults.standard.string(forKey: "aiKeysOwner") ?? ""
        guard owner != email else { return }
        let found = KeychainStore.aiKeys.filter { !(KeychainStore.shared.get($0) ?? "").isEmpty }
        if found.isEmpty { UserDefaults.standard.set(email, forKey: "aiKeysOwner"); return }
        askedKeys = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            let names = found.map { $0.replacingOccurrences(of: "-api-key", with: "").capitalized }.joined(separator: ", ")
            let a = NSAlert()
            a.messageText = "AI keys from before were found on this Mac"
            a.informativeText = "This Mac still has \(names) key\(found.count > 1 ? "s" : "") saved from before you signed in as \(self.email). macOS keeps them even after Zuffi is deleted.\n\nKeep them if they are yours. Remove them if they belong to someone else. Zuffi’s built-in AI works either way."
            a.addButton(withTitle: "Remove them"); a.addButton(withTitle: "Keep — they’re mine")
            if a.runModal() == .alertFirstButtonReturn {
                KeychainStore.shared.removeAll(onlyAI: true)
                UserDefaults.standard.removeObject(forKey: "geminiResolved")
                AIService.shared.clearConversation()
            }
            UserDefaults.standard.set(self.email, forKey: "aiKeysOwner")
        }
    }

    // MARK: Who Zuffi helps (the welcome form)

    /// "personal" (Just me) or "business". Business screens only show for a business.
    var use: String { mode.map { $0.isBusiness ? "business" : "personal" } ?? UserDefaults.standard.string(forKey: "zuffiUse") ?? "personal" }
    var isPersonal: Bool {
        if !ZuffiFocus.agents { return true }        // Zuffi is personal-only for now
        if let m = mode { return m == .personal }
        return UserDefaults.standard.string(forKey: "zuffiProfile") != nil && use != "business"
    }
    /// What Zuffi is for on this Mac (chosen once; changeable in Settings). nil = not chosen yet.
    var mode: ZuffiMode? { ZuffiMode(rawValue: UserDefaults.standard.string(forKey: "zuffiMode") ?? "") }
    func setMode(_ m: ZuffiMode) {
        objectWillChange.send()
        UserDefaults.standard.set(m.rawValue, forKey: "zuffiMode")
        UserDefaults.standard.set(m.isBusiness ? "business" : "personal", forKey: "zuffiUse")
        ZuffiTeam.shared.log("You", "Zuffi is for: \(m.title)")
    }
    var profile: [String: String] { (UserDefaults.standard.dictionary(forKey: "zuffiProfile") as? [String: String]) ?? [:] }

    func saveProfile(_ o: [String: Any]) {
        var p: [String: String] = [:]
        for (k, v) in o { if let s = v as? String { p[k] = s.trimmingCharacters(in: .whitespacesAndNewlines) } }
        let d = UserDefaults.standard
        d.set(p, forKey: "zuffiProfile")
        d.set(p["name"] ?? "", forKey: AssistantPrefs.userName)       // the name from the form — never the Mac account's
        if let c = p["city"], !c.isEmpty { d.set(c, forKey: AssistantPrefs.weatherCity) }
        d.set(p["type"] == "business" ? "business" : "personal", forKey: "zuffiUse")
        d.set(p["business"] ?? "", forKey: "zuffiBusinessName")
        if let c = p["country"], c == "PK" || c == "GB" { ZuffiCRM.shared.country = c; ZuffiCRM.shared.currencyChoice = c == "PK" ? "Rs" : "£" }
        if p["type"] == "business" {
            let map: [String: ZuffiBusiness.Pack] = ["realEstate": .realEstate, "salon": .salon, "nails": .nails, "cleaning": .cleaning, "clinic": .clinic, "shop": .shop, "restaurant": .restaurant, "services": .services, "freelancer": .freelancer]
            if let pack = map[p["kind"] ?? ""], ZuffiBusiness.shared.pack != pack {
                if pack == .realEstate, UserDefaults.standard.string(forKey: "bizCountry") == nil { ZuffiCRM.shared.country = "PK" }
                Task { _ = await ZuffiBusiness.shared.install(pack) }
            }
            ZuffiBusiness.shared.businessName = p["business"] ?? ""
        } else {
            HomeAction.right = HomeAction.defaultRight                 // no business buttons for "Just me"
        }
        objectWillChange.send()
        AIService.shared.clearConversation()
    }

    /// One paragraph for every AI prompt, so Zuffi always knows who she's helping (phone numbers are left out).
    /// "What's my date of birth / name / city?", "what do you know about me?" → the answer from the welcome form (the web part's
    /// answer first, which also knows "remember that…" notes; this Mac's own copy of the form if the page isn't ready).
    func aboutMe(_ q: String) async -> String? {
        let js = "(window.zuffiAboutMe && window.zuffiAboutMe(\(Self.jsString(q)))) || ''"
        if WebHub.shared.isReady, let r = await WebHub.shared.evalString(js), !r.isEmpty { return r }
        let t = q.lowercased(), p = profile
        let mine = t.range(of: #"\b(my|i|me|mera|meri)\b"#, options: .regularExpression) != nil
        if mine, t.range(of: #"date of birth|\bdob\b|birthday|when was i born|salgirah"#, options: .regularExpression) != nil {
            guard let d = p["dob"], d.count == 10 else { return "I don’t have your date of birth yet. Add it in Settings → You → Edit my details." }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            guard let date = f.date(from: d) else { return "Your date of birth is \(d)." }
            let out = DateFormatter(); out.dateStyle = .long
            return "Your date of birth is \(out.string(from: date))."
        }
        if t.range(of: #"^(what'?s|what is) my name\??$|^who am i\??$"#, options: .regularExpression) != nil, let n = p["name"], !n.isEmpty { return "You’re \(n)." }
        if t.range(of: #"^where do i live\??$|^(what'?s|what is) my city\??$"#, options: .regularExpression) != nil, let c = p["city"], !c.isEmpty { return "You live in \(c)." }
        return nil
    }
    nonisolated static func jsString(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        let a = String(data: d, encoding: .utf8) ?? "[\"\"]"
        return String(a.dropFirst().dropLast())
    }

    var profileLine: String {
        let p = profile
        guard !p.isEmpty else { return "" }
        var parts: [String] = []
        if let n = p["name"], !n.isEmpty { parts.append("Their name is \(n) (from their Zuffi profile — use this name, never one from the computer)") }
        if let b = p["dob"], b.count == 10 { parts.append("date of birth \(b)") }
        if let c = p["city"], !c.isEmpty { parts.append("lives in \(c)") }
        if p["type"] == "business" {
            var biz = "uses Zuffi for their business"
            if let n = p["business"], !n.isEmpty { biz += " \"\(n)\"" }
            if let k = p["kind"], !k.isEmpty { biz += " (\(ZuffiBusiness.Pack(rawValue: k)?.label ?? k))" }
            if let r = p["role"], !r.isEmpty { biz += ", they are the \(r)" }
            if let h = p["hours"], !h.isEmpty { biz += ", open \(h)" }
            if let f = p["founded"], f.count == 10 { biz += ", opened on \(f)" }
            parts.append(biz)
        } else { parts.append("uses Zuffi personally (not for a business)") }
        if let h = p["help"], !h.isEmpty { parts.append("wants help with: \(h)") }
        if let n = p["notes"], !n.isEmpty { parts.append("always remember: \(n)") }
        for (k, label) in [("job", "work/studies"), ("hobbies", "hobbies"), ("family", "family"), ("fav", "favourites")] {
            if let v = p[k], !v.isEmpty { parts.append("\(label): \(v)") }
        }
        return "\nABOUT THE USER (they filled this in when they set Zuffi up; answer questions about it): " + parts.joined(separator: "; ") + ".\n"
    }

    /// Opens Settings → Zuffi account in the Zuffi panel (sign in / upgrade live there).
    func openAccount() {
        WebHub.shared.showTool("account")   // just the account page, in a small window
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

// MARK: - Start fresh

/// Settings → General → "Start fresh on this Mac".
/// macOS keeps an app's Keychain items, settings and data even after the app is deleted and installed
/// again, so a reinstall still remembers the last person. This really wipes it: name and details, chats,
/// memories, reminders, business data, settings and AI keys. The Zuffi account and plan live on the
/// server and are not touched — just sign in again.
@MainActor
enum ZuffiReset {
    static func confirmAndRun() {
        let a = NSAlert()
        a.messageText = "Start fresh on this Mac?"
        a.informativeText = "This erases everything Zuffi saved on this Mac: your name and details, chats, memories, reminders, business data (the Documents › Zuffi folder), settings and any AI keys you added.\n\nYour Zuffi account and plan are not affected. Just sign in again afterwards.\n\nThis can't be undone."
        a.alertStyle = .warning
        a.addButton(withTitle: "Erase and start fresh")
        a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return }
        appendAppLog("voice.log", "start fresh: erasing this Mac's Zuffi data")
        KeychainStore.shared.removeAll()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            Task { @MainActor in finish() }
        }
    }

    static func confirmRemoveKeys() -> Bool {
        let a = NSAlert()
        a.messageText = "Remove all AI keys from this Mac?"
        a.informativeText = "Your own ChatGPT, Gemini, Groq, Claude and other keys are deleted from this Mac's Keychain. Zuffi's built-in AI (included with your plan) keeps working."
        a.addButton(withTitle: "Remove keys")
        a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        guard a.runModal() == .alertFirstButtonReturn else { return false }
        KeychainStore.shared.removeAll(onlyAI: true)
        UserDefaults.standard.removeObject(forKey: "geminiResolved")
        AIService.shared.clearConversation()
        return true
    }

    private static func finish() {
        let fm = FileManager.default
        let sup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for name in ["Sparrow", "Zuffi"] { try? fm.removeItem(at: sup.appendingPathComponent(name, isDirectory: true)) }
        try? fm.removeItem(at: fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Zuffi", isDirectory: true))   // business data
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            UserDefaults.standard.synchronize()
        }
        // Open Zuffi again a moment after it quits, like a brand-new install.
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1.5; /usr/bin/open \"\(Bundle.main.bundlePath)\""]
        try? relaunch.run()
        exit(0)            // quit now, so nothing writes the old settings back on the way out
    }
}

// MARK: - AI usage (Settings → AI and the notch)

/// Tokens and rough cost when someone uses their own AI keys, plus the built-in AI allowance from their plan.
/// Prices are approximate list prices (US$ per million tokens, input/output); the AI company's bill is the real number.
final class AIUsage: ObservableObject, @unchecked Sendable {
    static let shared = AIUsage()
    struct Row: Codable { var req = 0; var inT = 0; var outT = 0; var cost = 0.0 }
    @Published private(set) var month = ""
    @Published private(set) var rows: [String: Row] = [:]          // made on this Mac (native AI)
    @Published private(set) var webRows: [String: Row] = [:]       // made by the Zuffi panel (web part)
    @Published var builtInUsed = 0
    @Published var builtInLimit = 0
    /// The AI that answered last ("Gemini", "Groq", "Zuffi AI"…): the notch shows its numbers.
    @Published var current: String = UserDefaults.standard.string(forKey: "aiCurrent") ?? "" { didSet { UserDefaults.standard.set(current, forKey: "aiCurrent") } }
    private var restUntil: [String: Date] = [:]
    private let lock = NSLock()

    func rest(_ name: String, minutes: Double) { lock.lock(); restUntil[name] = Date().addingTimeInterval(minutes * 60); lock.unlock() }
    func resting(_ name: String) -> Bool { lock.lock(); defer { lock.unlock() }; return (restUntil[name] ?? .distantPast) > Date() }

    private init() { load() }
    private static var thisMonth: String { let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: Date()) }

    private func load() {
        let d = UserDefaults.standard
        month = d.string(forKey: "aiUsageMonth") ?? ""
        if let data = d.data(forKey: "aiUsageRows"), let r = try? JSONDecoder().decode([String: Row].self, from: data) { rows = r }
        if month != Self.thisMonth { month = Self.thisMonth; rows = [:]; webRows = [:] }
    }

    /// Called after every successful answer from an AI company.
    func record(url: String, model: String, json: [String: Any]) {
        let names: [(String, String)] = [("anthropic", "Claude"), ("openai.com", "ChatGPT"), ("groq", "Groq"), ("googleapis", "Gemini"), ("x.ai", "Grok"),
                                         ("deepseek", "DeepSeek"), ("mistral", "Mistral"), ("perplexity", "Perplexity"), ("openrouter", "OpenRouter")]
        guard let name = names.first(where: { url.contains($0.0) })?.1 else { return }
        let u = json["usage"] as? [String: Any] ?? [:], g = json["usageMetadata"] as? [String: Any] ?? [:]
        let inT = (u["prompt_tokens"] ?? u["input_tokens"] ?? g["promptTokenCount"]) as? Int ?? 0
        let outT = (u["completion_tokens"] ?? u["output_tokens"] ?? g["candidatesTokenCount"]) as? Int ?? 0
        let m = model.lowercased()
        let price: (Double, Double) = {
            switch name {
            case "Claude": return m.contains("opus") ? (15, 75) : m.contains("haiku") ? (1, 5) : (3, 15)
            case "ChatGPT": return (m.contains("mini") || m.contains("nano")) ? (0.15, 0.6) : (2.5, 10)
            case "Groq": return (0.59, 0.79)
            case "Gemini": return m.contains("pro") ? (1.25, 10) : (0.3, 2.5)
            case "Grok": return (3, 15)
            case "DeepSeek": return (0.27, 1.1)
            case "Mistral": return (0.4, 2)
            case "Perplexity": return (1, 1)
            default: return (0, 0)
            }
        }()
        let cost = (u["cost"] as? Double) ?? (Double(inT) * price.0 + Double(outT) * price.1) / 1_000_000
        DispatchQueue.main.async {
            if self.month != Self.thisMonth { self.month = Self.thisMonth; self.rows = [:]; self.webRows = [:] }
            var r = self.rows[name] ?? Row(); r.req += 1; r.inT += inT; r.outT += outT; r.cost += cost; self.rows[name] = r
            self.current = name
            UserDefaults.standard.set(self.month, forKey: "aiUsageMonth")
            if let data = try? JSONEncoder().encode(self.rows) { UserDefaults.standard.set(data, forKey: "aiUsageRows") }
        }
    }

    /// The panel's own count (sent by the web part).
    func fromWeb(_ o: [String: Any]) {
        if let c = o["current"] as? String, !c.isEmpty { DispatchQueue.main.async { self.current = c } }
        var out: [String: Row] = [:]
        for (k, v) in (o["byProvider"] as? [String: Any] ?? [:]) {
            guard let d = v as? [String: Any] else { continue }
            out[k] = Row(req: d["req"] as? Int ?? 0, inT: d["in"] as? Int ?? 0, outT: d["out"] as? Int ?? 0, cost: d["cost"] as? Double ?? 0)
        }
        DispatchQueue.main.async { self.webRows = out }
    }

    var all: [String: Row] { rows.merging(webRows) { a, b in Row(req: a.req + b.req, inT: a.inT + b.inT, outT: a.outT + b.outT, cost: a.cost + b.cost) } }
    var tokens: Int { all.values.reduce(0) { $0 + $1.inT + $1.outT } }
    var cost: Double { all.values.reduce(0) { $0 + $1.cost } }
    static func tok(_ n: Int) -> String { n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1000 ? "\(n / 1000)k" : "\(n)" }
    static func money(_ c: Double) -> String { c < 0.01 ? String(format: "$%.4f", c) : String(format: "$%.2f", c) }

    /// One short line for the notch: the AI in use right now and its numbers this month.
    var notchLine: String {
        if current == "Zuffi AI" || (current.isEmpty && builtInLimit > 0) {
            return builtInLimit > 0 ? "Zuffi AI · \(max(0, builtInLimit - builtInUsed)) of \(builtInLimit) left" : ""
        }
        if current.hasPrefix("Ollama") || current.hasPrefix("Apple") { return "\(current) · free" }
        if let r = all[current], r.req > 0 { return "\(current) · \(Self.tok(r.inT + r.outT)) tokens · ~\(Self.money(r.cost))" }
        return current.isEmpty ? "" : "\(current) · this month: nothing yet"
    }
}

// MARK: - What Zuffi knows about herself (same text as about.js)

enum ZuffiAbout {
    static let text = #"""
ABOUT YOU — ZUFFI (answer any question about yourself from this; never invent features)
Who: Zuffi, a friendly bunny AI assistant made by Lisan Systems (lisansystems.com/zuffi). You live in the notch at the top of the Mac screen, in a notch/island at the top of Windows, as a floating bubble on Android, and as an app on iPhone/iPad (Add to Home Screen from Safari). Same account on all of them.
Languages: English, Urdu (and Roman Urdu), Hindi, Punjabi, Arabic and more — you reply in the language they use.
Talking to you: say "Zuffi" or "Hey Zuffi" (wake word, Settings → Voice), click the mic, hold the right Option key on Mac, or type in Chat. You only act after hearing your name.
Plans: a 3-day free trial with everything on (no card), then Pro or Business. UK: Pro £6.99/month (£59/year), Business £14.99/month (£139/year), VAT included. Pakistan: Pro Rs 1,000/month, Business Rs 2,000/month. Only the price for their country is shown; cancel any time. Pro: talk or type on every device, reminders, water/coffee/medicine, prayer times, morning summary, built-in AI, up to 3 devices. Business: everything in Pro plus WhatsApp enquiries become leads, unlimited leads/clients/stock, payments and late payers, staff, same business on phone/tablet/computer, automations. Without a trial or plan you pause — nothing saved is deleted. Buy or manage: Settings → Zuffi account → Choose Pro / Business / Manage subscription.
Built-in AI: included with the plan (trial 60 answers, Pro 1,500 a month, Business 4,000 a month); the key stays on Zuffi's server; what people ask is never stored. Or use their own key (ChatGPT, Gemini, Groq, Claude, Grok, DeepSeek, Mistral, Perplexity, OpenRouter) in Settings → AI; keys stay on the device. Usage (answers left, tokens and rough cost) is in Settings → AI and on the open notch.
Works offline: opening apps, music and volume, Mac controls, reminders, notes, prayer times, memory and the business data; questions that need the internet wait until it's back. A plan keeps working offline for 7 days.
Everyday features: reminders and alarms ("remind me at 5 to call Ali"), meetings and calendar, to-dos and daily plan, water/coffee/medicine reminders (Settings → Health), prayer times with a nudge before each prayer (Settings → My day), morning summary, birthdays (you dress up and wish them), seasonal outfits (Settings → Look: winter, Ramadan, Eid, 14 August, Christmas…), notes and memory ("remember that…", files dropped on the notch), weather, translations, writing and answering anything, the walking bunny pet (Settings → Look), and a team of 289 expert personas (Settings → AI → Zuffi's team).
On the Mac you can also: open/quit apps and websites, control music, volume, brightness, Wi-Fi, Bluetooth, dark mode, take meeting notes, see and click the screen (Settings → Screen), run agents (Settings → Agents), and control the Mac from an iPhone (Settings → iPhone).
Business (Business plan): WhatsApp agent (upload your price list, menu, brochure or property list — PDF, Word, Excel, CSV — or type; Zuffi learns the business and answers customers in whatever language they write, passing bargaining and complaints to you), Posts & reels (designed posts, Status images and reels with your name, price and WhatsApp number, plus captions; listing posts for estate agents, offers and free slots for UK businesses), Today page, WhatsApp inbox (new chats become leads; Zuffi drafts replies, Autopilot can answer), pipeline of stages, records table, money in/out and late payers, team and staff pay, automations, linked devices. The features follow the country and business type. In Pakistan Zuffi is set up for estate agents; in the UK for small businesses. Estate agents (Pakistan — plots, marla/kanal, DHA/Bahria areas, token money, installments, commission, dealer share, Zameen/Facebook leads), salons/barbers, restaurants/cafés, clinics/dentists (bookings, regulars, reminders), shops (orders, stock, delivery), trades (jobs, quotes, invoices) and freelancers (clients, projects, invoices). Business → Connect & devices can disconnect WhatsApp or erase business data.
The Zuffi panel (one dashboard: tabs are just Zuffi, Business and Settings; search features at the top; the bell opens the Inbox with reminders, WhatsApp chats, unread Mail and files from your devices): Activity & undo (say "undo that"); Word, Excel & PowerPoint from a sentence (Business can export leads, money and late payers to Excel); Make a picture (OpenAI, Gemini, Grok, Together, Stability or OpenRouter keys, or offline with an Ollama picture model); Photo studio (auto fix, looks, Instagram/Status/portal sizes, watermark); Quick reels (trim, vertical crop, title, captions, your name); Convert files (photos to JPG/PNG/WebP/PDF, text to PDF); Sign a PDF; Send to my devices (link phone and computers once by QR code, then send files, photos, text and links, end-to-end encrypted). Meeting notes record the whole meeting and write an accurate transcript with speakers, summary, decisions and action items into Apple Notes.
Your details: the welcome form (Just me / My business) — change it in Settings → You → Edit my details. "Just me" hides the business screens.
New: Plan my day (fits tasks around meetings and your Google/Outlook/iCloud calendar — connect it in Settings → My day with the calendar's private iCal link); personalities (Settings → AI: Friendly, Professional, Butler, Big brother/sister, Coach, Teacher, Funny friend); Blur faces & private info in pictures (faces, emails, phone numbers, names); Screen recorder (Mac and Windows: “record my screen”, “stop recording”); meeting & call detection (Zoom, Teams, Google Meet, FaceTime, WhatsApp calls — Zuffi asks to take notes and stops when the call ends); drop any file and press Convert (photos, PDF, Word, Excel, CSV, text); type anywhere on Windows (Ctrl+Alt+Space, then again to type what you said); email in the Inbox is sorted into bills, invitations, security codes and orders (Mac); reminders in the Mac notch have Done and Later.
Privacy and security: data stays on the device unless they link devices; sign-in is a 6-digit email code (no password); licences are signed so they can't be faked; Settings → General → Start fresh on this Mac erases everything on that Mac; Settings → AI → Remove all keys removes their keys.
Help: Settings → How to use Zuffi (the guide), Business → Learn & help, or lisansystems.com/zuffi (questions form). Signed out or locked? Settings → Zuffi account → sign in with the email code.
"""#
}

/// Speech engines sometimes send markers like "<no speech>" or "{pause}": never show or say them.
func zClean(_ s: String) -> String {
    s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        .replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"<[^<>]{1,30}>|\{[^{}]{1,30}\}|\[(noise|music|silence|inaudible|pause)\]"#, with: " ", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}


// MARK: - What Zuffi is for: a personal assistant, or a business (business · freelancer · one-person company · content creator)

enum ZuffiMode: String, CaseIterable, Identifiable {
    case personal, business, freelancer, company, creator
    var id: String { rawValue }
    var isBusiness: Bool { self != .personal }
    var title: String {
        switch self {
        case .personal: return "Personal assistant"
        case .business: return "Business"
        case .freelancer: return "Freelancer"
        case .company: return "One-person company"
        case .creator: return "Content creator"
        }
    }
    var sub: String {
        switch self {
        case .personal: return "Zuffi and her helpers run your Mac: research, writing, travel, tasks on websites, reminders, screen recording and more"
        case .business: return "A shop, salon, café, clinic, trade… your AI team posts, watches reviews and competitors, and reports every week"
        case .freelancer: return "Win and keep clients: posts, research, proposals and a weekly report"
        case .company: return "You are the company: an AI team for marketing, research and admin"
        case .creator: return "Plan, write and schedule content, follow trends and see what works"
        }
    }
    var icon: String {
        switch self {
        case .personal: return "person.crop.circle.fill"
        case .business: return "storefront.fill"
        case .freelancer: return "laptopcomputer"
        case .company: return "building.2.fill"
        case .creator: return "camera.aperture"
        }
    }
}

/// Parts of Zuffi switched off for now (kept in the app, ready to come back).
enum ZuffiFocus {
    /// WhatsApp linking, inbox and auto-replies.
    static let whatsapp = false
    /// The full list of 289 specialists (Zuffi's own focused team is shown instead).
    static let allAgents = false
    /// Agents, the Agent Office, channels, automations and business pages — hidden for now (all the code stays, switch back on here).
    static let agents = false
    /// Business pages hidden for now.
    static let hiddenBizTabs: Set<String> = ["Inbox", "Pipeline", "Properties", "Customers", "WhatsApp contacts", "Money", "Staff", "Data sources"]
}

/// "What's Zuffi for?" — asked once on this Mac.
@MainActor
final class ZuffiModeWindow {
    static let shared = ZuffiModeWindow()
    private var window: NSWindow?
    func showIfNeeded() { if ZuffiFocus.agents, ZuffiPlan.shared.mode == nil, !ZuffiPlan.shared.isLocked { show() } }
    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true; w.titleVisibility = .hidden; w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: ZuffiModePicker { [weak self] in self?.window?.close() })
        w.center(); window = w
        w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

struct ZuffiModePicker: View {
    var done: () -> Void
    @State private var pick: ZuffiMode? = ZuffiPlan.shared.mode
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                LiveBunnyFace(size: 80, mood: .happy)
                VStack(alignment: .leading, spacing: 3) {
                    Text("What's Zuffi for?").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("I'll show only what you need. You can change this any time in Settings.").font(.system(size: 12)).foregroundColor(.secondary)
                }
            }
            ForEach(ZuffiMode.allCases) { m in
                Button { pick = m } label: {
                    HStack(spacing: 12) {
                        Image(systemName: m.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 11).fill(m.isBusiness ? Color(hex: "#5B6CFF").gradient : Color(hex: "#F59E3B").gradient))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(.system(size: 13.5, weight: .bold)).foregroundColor(.primary)
                            Text(m.sub).font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Image(systemName: pick == m ? "checkmark.circle.fill" : "circle").foregroundColor(pick == m ? Color(hex: "#F59E3B") : .secondary)
                    }
                    .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(pick == m ? 0.1 : 0.04)))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Continue") {
                    guard let m = pick else { return }
                    ZuffiPlan.shared.setMode(m)
                    done()
                    if m.isBusiness { BusinessDashboard.shared.show() }
                }.buttonStyle(.borderedProminent).tint(Color(hex: "#F59E3B")).disabled(pick == nil).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 620)
    }
}
