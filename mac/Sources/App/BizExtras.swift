import Foundation
import AppKit
import SwiftUI
import LocalAuthentication

// =====================================================================
// MARK: - Country (with what it switches on), Learn guides, and the Business lock
// =====================================================================

/// What Zuffi switches on for a country — the same rules as countries.js on the phone.
enum CountryFeatures {
    static let waHeavy: Set<String> = ["PK", "IN", "BD", "AE", "SA", "QA", "KW", "OM", "BH", "NG", "KE", "GH", "ZA", "EG", "MA", "ID", "MY", "BR", "MX", "AR", "CO", "TR", "ES", "IT", "LK", "NP"]
    static func portals(_ c: String) -> [String] {
        switch c {
        case "PK": return ["Zameen.com", "Graana", "OLX", "Facebook"]
        case "IN": return ["99acres", "MagicBricks", "Housing.com", "NoBroker"]
        case "GB": return ["Rightmove", "Zoopla", "OnTheMarket", "Checkatrade"]
        case "AE": return ["Bayut", "Property Finder", "Dubizzle"]
        case "SA": return ["Aqar", "Bayut", "Haraj"]
        case "US": return ["Zillow", "Realtor.com", "Redfin"]
        default: return ["Google", "Facebook", "Instagram", "Website"]
        }
    }
    static func payments(_ c: String) -> [String] {
        switch c {
        case "PK": return ["Cash", "Bank", "JazzCash", "Easypaisa", "Cheque"]
        case "IN": return ["UPI", "Cash", "Bank", "Card"]
        case "BD": return ["bKash", "Nagad", "Cash", "Bank"]
        case "KE": return ["M-Pesa", "Cash", "Bank"]
        case "GB": return ["Card", "Cash", "Bank transfer", "Online"]
        default: return ["Card", "Cash", "Bank transfer"]
        }
    }
    /// (SF Symbol, title, detail)
    static func list(_ c: String) -> [(String, String, String)] {
        let south = ["PK", "IN", "BD", "NP", "LK"].contains(c)
        var l: [(String, String, String)] = [
            ("bubble.left.and.bubble.right", "WhatsApp enquiries become leads", c == "PK" ? "Replies in English, Urdu or Roman Urdu" : "Replies in the client's own language"),
            ("timer", "Speed-to-lead alarm", "The notch drops down if someone waits 5 minutes"),
            ("chart.line.downtrend.xyaxis", "Lost money report", "See enquiries nobody followed up"),
            ("phone.arrow.down.left", "Missed call → WhatsApp", "On Android phones linked to this Mac"),
        ]
        if waHeavy.contains(c) { l.append(("square.grid.3x3", "WhatsApp group posts → stock", "Dealer posts become listings, matched to buyers")) }
        if south || ["AE", "SA", "EG", "TR"].contains(c) { l.append(("calendar.badge.clock", "Tokens & installments", "Due dates and reminders")) }
        if c == "GB" {
            l.append(("checkmark.shield", "Renters' Rights & safety certificates", "Gas, electrical, deposit, pet requests, rent rises (England)"))
            l.append(("doc.text", "Making Tax Digital records", "Quarterly export for your accountant"))
        }
        l.append(("arrow.uturn.backward.circle", "Rebooking & money chasers", "Clients come back, invoices get paid"))
        l.append(("creditcard", "Payments: " + payments(c).prefix(4).joined(separator: ", "), "Leads from " + portals(c).prefix(4).joined(separator: ", ")))
        return l
    }
}

/// "Where is your business?" — every country, with what Zuffi switches on there.
struct BizCountrySheet: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    @State private var sel = ZuffiCRM.shared.country

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where is your business?").font(zf(18, .semibold))
                Text("Zuffi switches on the right currency, payment apps, property portals and local rules.").font(zf(12)).foregroundColor(Ink.muted)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(Ink.faint)
                    TextField("Search country", text: $q).textFieldStyle(.plain)
                }.padding(.horizontal, 10).frame(height: 30).inkPanel(RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(ZuffiCRM.allCountries.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) || $0.code.caseInsensitiveCompare(q) == .orderedSame }) { c in
                            Button { sel = c.code } label: {
                                HStack { Text(c.flag); Text(c.name).foregroundColor(Ink.text); Spacer(); if sel == c.code { Image(systemName: "checkmark").foregroundColor(Ink.accent) } }
                                    .font(zf(13)).padding(.horizontal, 10).frame(height: 30)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(sel == c.code ? Ink.ink.opacity(0.07) : .clear))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(18).frame(width: 300)
            Rectangle().fill(Ink.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 12) {
                let name = ZuffiCRM.allCountries.first { $0.code == sel }
                Text("\(name?.flag ?? "🌍") What you get in \(name?.name ?? "your country")").font(zf(15, .semibold))
                ForEach(Array(CountryFeatures.list(sel).enumerated()), id: \.offset) { _, f in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: f.0).font(zf(13)).foregroundColor(Ink.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.1).font(zf(13, .medium))
                            Text(f.2).font(zf(11.5)).foregroundColor(Ink.muted)
                        }
                    }
                }
                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button("Use \(name?.name ?? "this country")") {
                        crm.country = sel; crm.currencyChoice = ""
                        UserDefaults.standard.set(true, forKey: "bizCountryConfirmed")
                        BizNav.shared.say("\(name?.flag ?? "") Set up for \(name?.name ?? sel)")
                        dismiss()
                    }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(Ink.accent)
                }
            }
            .padding(20).frame(width: 400)
        }
        .frame(height: 520)
        .background(Ink.bg)
        .foregroundColor(Ink.text)
    }
}

/// My business → the country row.
struct BizCountryRow: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @State private var open = false
    var body: some View {
        let c = ZuffiCRM.allCountries.first { $0.code == crm.country }
        Button { open = true } label: {
            HStack(spacing: 10) {
                Text(c?.flag ?? "🌍").font(zf(20))
                VStack(alignment: .leading, spacing: 1) {
                    Text(c?.name ?? "Another country").font(zf(13, .medium))
                    Text("Country · \(CountryFeatures.list(crm.country).count) features on").font(zf(11)).foregroundColor(Ink.muted)
                }
                Spacer()
                Text("Change").font(zf(12, .medium)).foregroundColor(Ink.accent)
            }
            .padding(.horizontal, 12).frame(height: 46).inkPanel(RoundedRectangle(cornerRadius: 10), interactive: true)
        }.buttonStyle(.plain)
        .sheet(isPresented: $open) { BizCountrySheet() }
    }
}

// MARK: - Learn (guides.json is shared with the phone and Windows apps)

struct BizGuide: Decodable, Identifiable { let id, icon, title, summary: String; let steps: [[String]] }
private struct BizGuideFile: Decodable { let guides: [BizGuide] }

struct BizLearnView: View {
    @State private var guides: [BizGuide] = []
    @State private var sel: String?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(guides) { g in
                        Button { sel = g.id } label: {
                            HStack(spacing: 10) {
                                Text(g.icon).frame(width: 28, height: 28).background(RoundedRectangle(cornerRadius: 7).fill(Ink.ink.opacity(0.05)))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(g.title).font(zf(13, .medium)).lineLimit(1)
                                    Text(g.summary).font(zf(11)).foregroundColor(Ink.muted).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8).background(RoundedRectangle(cornerRadius: 9).fill(sel == g.id ? Ink.ink.opacity(0.07) : .clear))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }
            .frame(width: 300).inkPanel(RoundedRectangle(cornerRadius: 14))
            ScrollView {
                if let g = guides.first(where: { $0.id == sel }) ?? guides.first {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("\(g.icon)  \(g.title)").font(zf(20, .semibold))
                        Text(g.summary).font(zf(13)).foregroundColor(Ink.muted)
                        ForEach(Array(g.steps.enumerated()), id: \.offset) { i, st in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)").font(zf(12, .bold)).foregroundColor(Color(hex: "#1A1206"))
                                    .frame(width: 24, height: 24).background(Circle().fill(Ink.accent))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(st.first ?? "").font(zf(14, .semibold))
                                    Text(st.count > 1 ? st[1] : "").font(zf(13)).foregroundColor(Ink.muted)
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .inkPanel(RoundedRectangle(cornerRadius: 14))
        }
        .padding(.horizontal, 22).padding(.bottom, 20)
        .onAppear(perform: load)
    }

    private func load() {
        guard guides.isEmpty,
              let u = Bundle.main.resourceURL?.appendingPathComponent("web/guides.json"),
              let d = try? Data(contentsOf: u),
              let f = try? JSONDecoder().decode(BizGuideFile.self, from: d) else { return }
        guides = f.guides
        if sel == nil { sel = f.guides.first?.id }
    }
}

// MARK: - Lock (Touch ID / Mac password), auto-lock, hide amounts

@MainActor
final class BizLock: ObservableObject {
    static let shared = BizLock()
    @Published var enabled = UserDefaults.standard.bool(forKey: "bizLock") { didSet { UserDefaults.standard.set(enabled, forKey: "bizLock"); if !enabled { locked = false } } }
    @Published var minutes = UserDefaults.standard.object(forKey: "bizLockMins") as? Int ?? 5 { didSet { UserDefaults.standard.set(minutes, forKey: "bizLockMins") } }
    @Published var locked = UserDefaults.standard.bool(forKey: "bizLock")
    @Published var hideAmounts = UserDefaults.standard.bool(forKey: "bizPrivate") { didSet { UserDefaults.standard.set(hideAmounts, forKey: "bizPrivate") } }
    @Published var message = ""
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { _ in Task { @MainActor in BizLock.shared.checkIdle() } }
    }

    private func checkIdle() {
        guard enabled, !locked else { return }
        let anyInput = CGEventType(rawValue: ~0) ?? .null
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        if idle > Double(minutes * 60) { locked = true }
    }

    func lockNow() { if enabled { locked = true } }

    func unlock() {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { message = "This Mac can't check your identity."; return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "open Zuffi Business") { @Sendable ok, _ in
            Task { @MainActor in
                BizLock.shared.locked = !ok
                BizLock.shared.message = ok ? "" : "Not unlocked."
            }
        }
    }

    /// Turning the lock on asks for Touch ID / password first.
    func setEnabled(_ on: Bool) {
        guard on else { enabled = false; return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { message = "This Mac can't check your identity."; return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "lock Zuffi Business with Touch ID or your password") { @Sendable ok, _ in
            Task { @MainActor in if ok { BizLock.shared.enabled = true; BizLock.shared.locked = false } }
        }
    }
}

struct BizLockScreen: View {
    @ObservedObject private var lock = BizLock.shared
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(zf(30)).foregroundColor(Ink.accent)
            Text("Zuffi Business is locked").font(zf(20, .semibold))
            Text("Your clients and money are hidden until you unlock.").font(zf(12.5)).foregroundColor(Ink.muted)
            Button { lock.unlock() } label: {
                Label("Unlock with Touch ID or password", systemImage: "touchid").font(zf(13, .semibold)).foregroundColor(Color(hex: "#1A1206"))
                    .padding(.horizontal, 16).frame(height: 34).background(Capsule().fill(Ink.accent))
            }.buttonStyle(.plain).keyboardShortcut(.defaultAction)
            if !lock.message.isEmpty { Text(lock.message).font(zf(11.5)).foregroundColor(Color(hex: "#EF6B6B")) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.bg)
        .foregroundColor(Ink.text)
        .onAppear { lock.unlock() }
    }
}

/// Connect & devices → Security & privacy.
struct BizSecurityBox: View {
    @ObservedObject private var lock = BizLock.shared
    @ObservedObject private var sync = BizSync.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundColor(Color(hex: "#3FC48C"))
                Text("Security & privacy").font(zf(14, .semibold))
            }
            row("internaldrive", "Your data stays on your devices", "Leads, money and staff are files on this Mac (Documents → Zuffi). Sync between devices is end-to-end encrypted.")
            Toggle(isOn: Binding(get: { lock.enabled }, set: { lock.setEnabled($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lock Business with Touch ID / password").font(zf(12.5, .medium))
                    Text("Asks when the dashboard opens and after you've been away.").font(zf(10.5)).foregroundColor(Ink.muted)
                }
            }.toggleStyle(.switch)
            if lock.enabled {
                HStack {
                    Picker("Lock after", selection: $lock.minutes) { ForEach([1, 5, 15, 60], id: \.self) { Text("\($0) min idle").tag($0) } }.frame(width: 220)
                    Button("Lock now") { lock.lockNow() }
                }
            }
            Toggle(isOn: $lock.hideAmounts) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hide amounts").font(zf(12.5, .medium))
                    Text("Blurs money on screen — useful with clients or staff around.").font(zf(10.5)).foregroundColor(Ink.muted)
                }
            }.toggleStyle(.switch)
            if sync.linked {
                HStack {
                    Text("Lost a phone or someone left?").font(zf(11.5)).foregroundColor(Ink.muted)
                    Button("Make a new link code") { sync.create() }.help("Every device with the old code is unlinked.")
                }
            }
            if !lock.message.isEmpty { Text(lock.message).font(zf(10.5)).foregroundColor(Ink.accent) }
        }
    }
    private func row(_ icon: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundColor(Ink.muted).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(t).font(zf(12.5, .medium))
                Text(d).font(zf(10.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
