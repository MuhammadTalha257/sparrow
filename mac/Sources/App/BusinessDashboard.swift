import SwiftUI
import ServiceManagement
import AppKit
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Business dashboard (opens from the "Business" button beside Mic and Chat)
//   Today · Inbox · Pipeline · Team · Automations · Connect WhatsApp
// =====================================================================

@MainActor
final class BusinessDashboard {
    static let shared = BusinessDashboard()
    private var window: NSWindow?

    func applyLook() { window?.appearance = NSAppearance(named: Ink.dark ? .darkAqua : .aqua) }

    func show(_ tab: BizTab? = nil) {
        if ZuffiPlan.shared.blocked() { return }
        if !ZuffiPlan.shared.isBusiness {
            let a = NSAlert()
            a.messageText = "Business is part of Zuffi Business"
            a.informativeText = "You’re on Pro. Zuffi Business adds the WhatsApp inbox, leads and follow-ups, money and late payers, staff and automations — set up for your type of business."
            a.addButton(withTitle: "See Business"); a.addButton(withTitle: "Not now")
            if a.runModal() == .alertFirstButtonReturn { ZuffiPlan.shared.openAccount() }
            return
        }
        if ZuffiPlan.shared.isPersonal {
            let a = NSAlert()
            a.messageText = "Business is switched off"
            a.informativeText = "You chose “Just me”, so Zuffi hides the business screens. To use them, change it to “My business” in Zuffi → Settings → You → Edit my details."
            a.addButton(withTitle: "Edit my details"); a.addButton(withTitle: "OK")
            if a.runModal() == .alertFirstButtonReturn { WebHub.shared.showTool("profile") }
            return
        }
        if let tab { BizNav.shared.tab = tab }
        if ZuffiHub.oneWindow { ZuffiHub.shared.show(.biz(tab ?? BizNav.shared.tab)); return }
        ZuffiCRM.shared.reload()
        if window?.isVisible != true, BizLock.shared.enabled { BizLock.shared.locked = true }
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Zuffi Business"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: Ink.dark ? .darkAqua : .aqua)
        w.contentMinSize = NSSize(width: 900, height: 560)
        w.contentView = NSHostingView(rootView: BusinessDashboardView())
        w.center()
        w.setFrameAutosaveName("ZuffiBusinessWindow")
        window = w
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum BizTab: String, CaseIterable, Identifiable {
    // Daily work · the business · set-up
    case today = "Overview", inbox = "Inbox", aiTeam = "My Team", reports = "Reports",
         money = "Money", pipeline = "Pipeline", properties = "Properties", records = "Customers", contacts = "WhatsApp contacts", team = "Staff",
         sources = "Data sources", automations = "Automations", business = "My business", connect = "Connect & devices", learn = "Learn & help"
    var id: String { rawValue }
    /// Each page's own colour — its tile in the list and its header.
    var tint: String {
        switch self {
        case .today: return "#F2A516"
        case .inbox: return "#1FAF5F"
        case .aiTeam: return "#5B6CFF"
        case .reports: return "#EAB308"
        case .pipeline: return "#7357E8"
        case .properties: return "#C77D1A"
        case .records: return "#2F80ED"
        case .contacts: return "#25D366"
        case .money: return "#0F9F76"
        case .team: return "#0EA5C6"
        case .sources: return "#4C5BD4"
        case .business: return "#E0527E"
        case .automations: return "#F06B3C"
        case .connect: return "#6366F1"
        case .learn: return "#7A8496"
        }
    }
    /// Groups in the list: daily work · the business · set-up.
    var group: Int {
        switch self {
        case .today, .inbox, .aiTeam, .reports: return 0
        case .money, .pipeline, .properties, .records, .contacts, .team: return 1
        default: return 2
        }
    }
    var icon: String {
        switch self {
        case .today: return "square.grid.2x2.fill"
        case .inbox: return "tray.full.fill"
        case .aiTeam: return "person.3.sequence.fill"
        case .reports: return "doc.text.magnifyingglass"
        case .pipeline: return "rectangle.split.3x1.fill"
        case .records: return "person.crop.rectangle.stack.fill"
        case .contacts: return "message.fill"
        case .properties: return "house.lodge.fill"
        case .money: return "banknote.fill"
        case .business: return "building.2.fill"
        case .team: return "person.2.badge.gearshape.fill"
        case .sources: return "rectangle.on.rectangle.angled"
        case .automations: return "bolt.fill"
        case .connect: return "link"
        case .learn: return "graduationcap.fill"
        }
    }
    /// One line in plain words: what this page is for.
    var subtitle: String {
        switch self {
        case .today: return "Your business at a glance"
        case .inbox: return "WhatsApp messages & replies"
        case .aiTeam: return "Your AI agents, what they're doing and their results"
        case .reports: return "Daily reports from your team"
        case .pipeline: return "Where each client is up to"
        case .properties: return "Plots, houses & shops you're selling"
        case .records: return "Every client in one table"
        case .contacts: return "Everyone who messaged you, with name and number"
        case .money: return "Money in, money out, profit"
        case .team: return "People who work for you, pay & hours"
        case .sources: return "Business dashboards Zuffi reads from your screen"
        case .business: return "Your details, FAQ and replies"
        case .automations: return "Jobs Zuffi does for you"
        case .connect: return "WhatsApp, your phone & other devices"
        case .learn: return "How Zuffi works, step by step"
        }
    }
    /// "What is this page?" — three short tips.
    var tips: [String] {
        switch self {
        case .today: return ["The numbers at the top are today's work at a glance.", "“Needs you today” lists the people you promised to call back.", "Tap any name to open it, change its stage or add a note."]
        case .inbox: return ["New WhatsApp chats arrive here and become clients automatically.", "Zuffi writes a reply from your FAQ — check it, then tap Send.", "Turn on Autopilot in My business to let Zuffi answer by itself."]
        case .aiTeam: return ["Hire agents — or show Zuffi your business dashboard and it suggests the right ones.", "Each card shows what the agent is doing, the data it used and its last result. Open it to see every step.", "Agents never guess numbers, and anything that sends, posts or pays waits for your OK."]
        case .reports: return ["Each hired agent runs its daily job and its report lands here.", "Reports also go to your phone when it's linked (Connect & devices).", "A job that couldn't run says so — it never pretends."]
        case .pipeline: return ["Each column is a step: New → Contacted → … → Won.", "Drag a client to the next column when things move on.", "Clients stuck too long are shown so nobody is forgotten."]
        case .properties: return ["Add each plot, house, flat or shop you're selling or renting.", "Zuffi matches properties to buyers looking for that area and budget.", "Deal desk: sizes, price per marla, instalments, token money and papers."]
        case .records: return ["Everyone who ever contacted you, like a spreadsheet.", "Click a column title to sort; search at the top.", "It's saved as a normal file in Documents → Zuffi, so it's always yours."]
        case .contacts: return ["Everyone who messages your linked WhatsApp is saved once, with their number in international format.", "If WhatsApp doesn't share a name it says “Unknown name” — type it in.", "Add tags and notes; open the list in Excel or Numbers any time."]
        case .money: return ["Add money in (sales) and money out (rent, wages, supplies).", "Profit is worked out from what's recorded — your Financial Analyst uses exactly these numbers.", "Say it instead: “expense 60 supplies”, “income 450 haircuts”."]
        case .team: return ["Add the people who work for you with their pay (monthly, hourly or commission).", "Log hours and pay salaries — each payment is added to Money.", "Give leads to a staff member and see who's following up."]
        case .sources: return ["Open your booking or payments dashboard, logged in, and press “This is my business dashboard”.", "Zuffi reads it from the screen — no API, no password.", "Your agents read it again when their daily job runs; keep it open and the Mac awake."]
        case .business: return ["Write your prices, hours, location and the questions customers ask.", "WhatsApp replies come only from these answers unless you switch that off.", "Your country comes from your Zuffi details."]
        case .automations: return ["Switch on the jobs you want Zuffi to do: follow-ups, summaries, reminders.", "Each switch says exactly what it does.", "You can turn any of them off at any time."]
        case .connect: return ["Connect WhatsApp so new chats become clients and contacts.", "Link your phone or tablet with the QR code: agent reports arrive there too.", "Changes on one device appear on the others by themselves."]
        case .learn: return ["Short guides for every part of Zuffi Business.", "Includes setting up a free AI model on your own computer.", "The same guides are on your phone and Windows PC."]
        }
    }
}

@MainActor
final class BizNav: ObservableObject {
    static let shared = BizNav()
    @Published var tab: BizTab = .today
    @Published var selected: String?
    @Published var search = ""
    @Published var toast = ""
    /// The business details form is filled in (name, address, phone, hours, services).
    @Published var formDone = BizDetailsForm.isComplete
    func say(_ s: String) {
        toast = s
        Task { @MainActor in try? await Task.sleep(nanoseconds: 4_000_000_000); if self.toast == s { self.toast = "" } }
    }
}

/// Business colours. Two looks — Porcelain (light, the default) and Night — and an accent the owner picks.
/// Every page also has its own colour (its icon tile), so you always know where you are.
enum Ink {
    /// Inside the one dashboard window, the business pages wear the dashboard's look (frosted glass, Poppins, blue).
    static var hub: Bool { UserDefaults.standard.object(forKey: "hubOneWindow") as? Bool ?? true }
    static var hubTheme: HubTheme { HubTheme(light: UserDefaults.standard.bool(forKey: "hubLight")) }
    /// Night (like the notch: dark glass, warm amber) is the default; Porcelain (light) is a choice.
    static var dark: Bool { hub ? !UserDefaults.standard.bool(forKey: "hubLight") : UserDefaults.standard.object(forKey: "bizDarkLook") as? Bool ?? true }
    static var accentHex: String { hub ? "#3A6DF0" : UserDefaults.standard.string(forKey: "bizAccentHex") ?? "#F59E3B" }
    /// The colour text and hairlines are made from.
    static var ink: Color { dark ? .white : Color(hex: "#141A26") }
    static var bg: Color { hub ? .clear : dark ? Color(hex: "#07080C") : Color(hex: "#EEF1F7") }
    static var bgTop: Color { hub ? .clear : dark ? Color(hex: "#12131B") : Color(hex: "#F6F8FC") }
    static var sidebar: Color { dark ? Color(hex: "#0B0C11") : Color(hex: "#FFFFFF") }
    static var panel: Color { hub ? hubTheme.content : dark ? Color(hex: "#13151C") : Color(hex: "#FFFFFF") }
    static var panelHi: Color { hub ? (dark ? Color.white.opacity(0.07) : Color.white.opacity(0.55)) : dark ? Color(hex: "#1A1D26") : Color(hex: "#F4F7FD") }
    static var line: Color { hub ? hubTheme.border : ink.opacity(dark ? 0.10 : 0.08) }
    static var text: Color { hub ? hubTheme.text : dark ? Color(hex: "#ECEEF3") : Color(hex: "#141A26") }
    static var muted: Color { hub ? (dark ? Color(hex: "#A3A8BD") : Color(hex: "#4A4A52")) : dark ? Color(hex: "#9AA1B1") : Color(hex: "#596173") }
    static var faint: Color { hub ? (dark ? Color(hex: "#717790") : Color(hex: "#7A7A84")) : dark ? Color(hex: "#6C7385") : Color(hex: "#8A92A4") }
    static var accent: Color { Color(hex: accentHex) }
    static let onAccent = Color.white
    static var shadow: Color { hub ? .clear : .black.opacity(dark ? 0.28 : 0.06) }
    /// Accents to choose from (named so they're easy to talk about).
    static let accents: [(String, String)] = [("Zuffi amber", "#F59E3B"), ("Ocean", "#3B6EF5"), ("Mint", "#0F9F76"), ("Berry", "#D2457A"), ("Marigold", "#DE8E12"), ("Violet", "#7357E8"), ("Coral", "#EA5A3D"), ("Teal", "#0E8FA3"), ("Graphite", "#3D4555")]
}

/// The dashboard's font (Poppins) on business pages inside the dashboard; the system font elsewhere.
func zf(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
    guard Ink.hub else { return .system(size: size, weight: w) }
    let name = [.semibold, .bold, .heavy, .black].contains(w) ? "Poppins-SemiBold" : w == .medium ? "Poppins-Medium" : "Poppins-Regular"
    return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: w)
}

/// Re-draws the Business window when the look changes.
@MainActor
final class BizLook: ObservableObject {
    static let shared = BizLook()
    @Published var version = 0
    func set(dark: Bool? = nil, accent: String? = nil) {
        if let dark { UserDefaults.standard.set(dark, forKey: "bizDarkLook") }
        if let accent { UserDefaults.standard.set(accent, forKey: "bizAccentHex") }
        version += 1
        BusinessDashboard.shared.applyLook()
    }
}

/// A flat professional card: graphite surface, hairline border, soft shadow.
struct InkPanel<S: InsettableShape>: ViewModifier {
    var shape: S
    var raised = false
    @State private var hover = false
    var interactive = false
    func body(content: Content) -> some View {
        content
            .background(shape.fill(raised || hover ? Ink.panelHi : Ink.panel))
            .overlay(shape.strokeBorder(Ink.line, lineWidth: 1))
            .shadow(color: Ink.shadow, radius: 10, y: 4)
            .onHover { if interactive { hover = $0 } }
            .animation(.easeOut(duration: 0.15), value: hover)
    }
}
extension View {
    func inkPanel<S: InsettableShape>(_ shape: S, raised: Bool = false, interactive: Bool = false) -> some View { modifier(InkPanel(shape: shape, raised: raised, interactive: interactive)) }
}

private enum Biz {
    // Soft on Night, deeper on Porcelain so they read on white.
    static var pink: Color { Color(hex: Ink.dark ? "#E8899E" : "#D2457A") }
    static var amber: Color { Color(hex: Ink.dark ? "#EDB24E" : "#C98208") }
    static var orange: Color { Color(hex: Ink.dark ? "#E0963F" : "#D06A12") }
    static var green: Color { Color(hex: Ink.dark ? "#3FC48C" : "#0F9F6A") }
    static var blue: Color { Color(hex: Ink.dark ? "#6EA8F7" : "#2F67E0") }
    static var red: Color { Color(hex: Ink.dark ? "#EF6B6B" : "#D93C3C") }
    static let card = Ink.panel, stroke = Ink.line
    static var accent: LinearGradient { LinearGradient(colors: [Ink.accent, Ink.accent.opacity(0.85)], startPoint: .top, endPoint: .bottom) }
    static func stageColor(_ s: String) -> Color {
        switch s { case "New": return blue; case "Contacted": return Color(hex: "#C4B5FD"); case "Site visit", "Booked": return amber
        case "Negotiating", "Regular": return orange; case "Won": return green; case "Lost": return Ink.ink.opacity(0.4); default: return pink }
    }
}

/// Apple's Liquid Glass on macOS 26 (Tahoe); Zuffi's drawn liquid glass on older macOS.
struct ZGlass: ViewModifier {
    var radius: CGFloat = 16
    var tint: Color? = nil
    var interactive = false
    func body(content: Content) -> some View {
        content.inkPanel(RoundedRectangle(cornerRadius: radius, style: .continuous), interactive: interactive)
    }
}

extension View {
    func zGlass(_ radius: CGFloat = 16, tint: Color? = nil, interactive: Bool = false) -> some View { modifier(ZGlass(radius: radius, tint: tint, interactive: interactive)) }
}

private struct GlassBox<C: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> C
    var body: some View {
        content().padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // cards side by side line up
            .zGlass(18)
    }
}

private struct Pill: View {
    let text: String; var color: Color = Biz.pink; var filled = false
    var body: some View {
        Text(text).font(zf(10.5, .bold))
            .foregroundColor(filled ? Ink.onAccent : color)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(filled ? color : color.opacity(0.16)))
    }
}

private struct BizMainButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { if let icon { Image(systemName: icon) }; Text(title) }
                .font(zf(12, .bold)).foregroundColor(Ink.onAccent)
                .padding(.horizontal, 13).frame(height: 31)
                .background(Capsule().fill(Biz.accent))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }.buttonStyle(.plain)
    }
}

private struct BizSoftButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { if let icon { Image(systemName: icon) }; Text(title) }
                .font(zf(12, .semibold)).foregroundColor(Ink.text)
                .padding(.horizontal, 12).frame(height: 31)
                .zGlass(16, interactive: true)
        }.buttonStyle(.plain)
    }
}

// MARK: - Root

struct BusinessDashboardView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @ObservedObject private var biz = ZuffiBusiness.shared
    @ObservedObject private var voice = VoiceEngine.shared
    @State private var dropping = false
    @State private var adding = false
    @State private var showTips = false
    @State private var showLook = false
    @ObservedObject private var lock = BizLock.shared
    @ObservedObject private var look = BizLook.shared

    var body: some View {
        if !nav.formDone {
            BizSetupGate()                    // the Business page opens once the business details are filled in
                .foregroundColor(Ink.text)
                .background(LinearGradient(colors: [Ink.bgTop, Ink.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
                .id(look.version)
        } else { dashboard }
    }

    /// One page of the dashboard (kept apart so the compiler checks it quickly).
    @ViewBuilder private func page(_ tab: BizTab) -> some View {
        switch tab {
        case .today: BizTodayView()
        case .inbox: BizInboxView()
        case .aiTeam: BizAITeamView()
        case .reports: BizReportsView()
        case .contacts: BizContactsView()
        case .sources: BizDataSourcesView()
        case .pipeline: BizPipelineView()
        case .records: BizRecordsView()
        case .properties: BizPropertiesView()
        case .money: BizMoneyView()
        case .business: BizBusinessView()
        case .team: BizTeamView()
        case .automations: BizAutomationsView()
        case .connect: BizConnectView()
        case .learn: BizLearnView()
        }
    }

    private var dashboard: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 244)
                .background(Ink.sidebar.ignoresSafeArea())
                .overlay(alignment: .trailing) { Rectangle().fill(Ink.line).frame(width: 1) }
            VStack(spacing: 0) {
                topBar
                page(nav.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundColor(Ink.text)
        .background(LinearGradient(colors: [Ink.bgTop, Ink.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
        .foregroundStyle(Ink.text)
        .overlay(alignment: .bottom) {
            if !nav.toast.isEmpty || !crm.busy.isEmpty {
                Text(crm.busy.isEmpty ? nav.toast : crm.busy).font(zf(12, .semibold))
                    .padding(.horizontal, 14).frame(height: 32)
                    .foregroundColor(.white).background(Capsule().fill(Color(hex: "#1B2130").opacity(0.94))).overlay(Capsule().stroke(Biz.stroke))
                    .padding(.bottom, 16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 18).stroke(Biz.pink, style: StrokeStyle(lineWidth: 3, dash: [8, 6])).padding(8)
                    .overlay(Text("Drop a voice note or a leads file").font(zf(18, .bold)))
                    .background(Color.black.opacity(0.35))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { @Sendable url, _ in
                    guard let url else { return }
                    Task { @MainActor in await BusinessFiles.take(url) }
                }
            }
            return true
        }
        .sheet(isPresented: $adding) { BizLeadEditor(lead: nil) }
        .overlay { if lock.locked { BizLockScreen().transition(.opacity) } }
        .animation(.easeInOut(duration: 0.2), value: nav.toast)
        .id(look.version)          // a new look re-draws every page
    }

    private var tabs: [BizTab] { BizTab.allCases.filter { !ZuffiFocus.hiddenBizTabs.contains($0.rawValue) && ($0 != .properties || crm.isEstate) && ($0 != .team || crm.kind != .freelancer) } }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZuffiMini(state: AppState.shared, height: 38).frame(width: 42, height: 42)
                    .background(Circle().fill(Ink.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(biz.businessName.isEmpty ? "My business" : biz.businessName).font(zf(14.5, .bold)).lineLimit(1)
                    Text(biz.pack?.label ?? "Choose your type of business").font(zf(10.5)).foregroundColor(Ink.faint).lineLimit(1)
                }
            }
            .padding(.top, 36).padding(.bottom, 16).padding(.horizontal, 8)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(0..<3, id: \.self) { g in
                        let rows = tabs.filter { $0.group == g }
                        VStack(spacing: 2) {
                            ForEach(rows) { t in tabRow(t) }
                        }
                        .padding(4)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Ink.panelHi.opacity(Ink.dark ? 0.6 : 1)))
                    }
                }
            }
            Spacer(minLength: 8)
            if biz.pack == nil {
                Text("Choose your type of business").font(zf(10.5, .semibold)).foregroundColor(Ink.muted)
                BizTypeMenu().padding(.bottom, 8)
            }
            HStack(spacing: 8) {
                Button { VoiceEngine.shared.listenOnce() } label: {
                    Image(systemName: voice.isListening ? "waveform" : "mic.fill").font(zf(13, .bold)).foregroundColor(Ink.onAccent)
                        .frame(width: 34, height: 34).background(Circle().fill(Ink.accent))
                }.buttonStyle(.plain).help("Talk to Zuffi: add a lead, ask who needs a follow-up")
                Button { ZuffiChat.shared.open() } label: {
                    Label("Ask Zuffi", systemImage: "bubble.left.fill").font(zf(12, .semibold))
                        .padding(.horizontal, 12).frame(height: 34).inkPanel(Capsule(), interactive: true)
                }.buttonStyle(.plain)
                Spacer()
                Button { showLook.toggle() } label: {
                    Image(systemName: "paintpalette.fill").font(zf(13)).foregroundStyle(Ink.accent)
                        .frame(width: 34, height: 34).inkPanel(Circle(), interactive: true)
                }.buttonStyle(.plain).help("Colours and light or dark")
                .popover(isPresented: $showLook, arrowEdge: .top) { BizLookPicker() }
            }
            Text(voice.isListening ? (voice.heard.isEmpty ? "Listening…" : voice.heard) : "Say “new lead…” or “who needs a follow-up?”")
                .font(zf(10)).foregroundColor(Ink.faint).lineLimit(2).padding(.top, 6).padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
    }

    private func tabRow(_ t: BizTab) -> some View {
        let on = nav.tab == t
        return Button { nav.tab = t } label: {
            HStack(spacing: 10) {
                Image(systemName: t.icon).font(zf(11.5, .semibold)).foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(hex: t.tint).gradient))
                Text(t.rawValue).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundColor(Ink.text)
                Spacer()
                if t == .inbox, crm.drafts.count > 0 { Pill(text: "\(crm.drafts.count)", color: Biz.pink, filled: true) }
                if t == .today { let d = crm.leads.filter(\.dueToday).count; if d > 0 { Pill(text: "\(d)", color: Color(hex: t.tint)) } }
                if t == .aiTeam { let n = ZuffiTeam.shared.hiredAgents.filter { [.waiting, .attention].contains(ZuffiTeam.shared.status($0)) }.count; if n > 0 { Pill(text: "\(n)", color: Biz.red, filled: true) } else if !ZuffiTeam.shared.hired.isEmpty { Pill(text: "\(ZuffiTeam.shared.hired.count)", color: Color(hex: t.tint)) } }
                if t == .contacts, !WAContactBook.shared.list.isEmpty { Pill(text: "\(WAContactBook.shared.list.count)", color: Color(hex: t.tint)) }
                if t == .business, crm.isOn(.autopilot) { Pill(text: "Autopilot", color: Biz.green) }
            }
            .padding(.horizontal, 8).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Ink.accent.opacity(Ink.dark ? 0.22 : 0.12) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).help(t.subtitle)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: nav.tab.icon).font(zf(15, .semibold)).foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: nav.tab.tint).gradient))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        Text(nav.tab.rawValue).font(zf(22, .bold)).lineLimit(1)
                        Button { showTips.toggle() } label: {
                            Image(systemName: "questionmark").font(zf(10, .bold)).foregroundColor(Ink.muted).frame(width: 20, height: 20).inkPanel(Circle(), interactive: true)
                        }.buttonStyle(.plain).help("What is this page?")
                        .popover(isPresented: $showTips, arrowEdge: .bottom) { BizTipsView(tab: nav.tab) }
                    }
                    Text(nav.tab.subtitle).font(zf(12)).foregroundColor(Ink.muted).lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 12)
                // Actions: they shrink before anything overflows (the window never gets pushed sideways).
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(Ink.faint)
                    TextField("Search name, number, area…", text: $nav.search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 12).frame(minWidth: 120, idealWidth: 220, maxWidth: 240).frame(height: 32).inkPanel(Capsule())
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        BizSoftButton(title: "Voice note", icon: "waveform.badge.mic") { BusinessFiles.pickVoiceNote(for: nil) }
                        BizMainButton(title: "Add lead", icon: "plus") { adding = true }
                    }
                    BizMainButton(title: "Add", icon: "plus") { adding = true }
                }
            }
            // Tabs for the pages next to this one (like a web dashboard header)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(tabs.filter { $0.group == nav.tab.group }) { t in
                        Button { nav.tab = t } label: {
                            VStack(spacing: 6) {
                                Text(t.rawValue).font(.system(size: 12.5, weight: nav.tab == t ? .semibold : .regular))
                                    .foregroundColor(nav.tab == t ? Ink.text : Ink.muted).fixedSize()
                                Rectangle().fill(nav.tab == t ? Ink.accent : .clear).frame(height: 2)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
            .overlay(alignment: .bottom) { Rectangle().fill(Ink.line).frame(height: 1) }
        }
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 8)
    }
}

// MARK: - Files (voice notes, lead exports)

@MainActor
enum BusinessFiles {
    static func take(_ url: URL, lead: String? = nil) async {
        let ext = url.pathExtension.lowercased()
        if ["opus", "ogg", "oga", "m4a", "mp3", "aac", "wav", "caf", "mp4"].contains(ext) {
            BizNav.shared.say(await ZuffiCRM.shared.voiceNoteToLead(url, for: lead))
        } else if ZuffiData.isSheet(url) {
            let dest = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/leads-import-\(Int(Date().timeIntervalSince1970)).\(ext == "xlsx" ? "csv" : ext)")
            if ext == "xlsx" {
                let tables = await ZuffiData.readXLSX(url)
                if let t = tables.first { try? t.1.map { $0.map(ZuffiData.csvCell).joined(separator: ",") }.joined(separator: "\n").write(to: dest, atomically: true, encoding: .utf8) }
            } else { try? FileManager.default.copyItem(at: url, to: dest) }
            ZuffiCRM.shared.set(.leadExports, true)
            ZuffiPA.shared.scanDownloads()
            ZuffiCRM.shared.reload()
            BizNav.shared.say("Checked \(url.lastPathComponent) for leads.")
        } else {
            BizNav.shared.say("Drop a voice note (.opus, .m4a…) or a leads file (.csv, .xlsx).")
        }
    }

    static func pickVoiceNote(for lead: String?) {
        let p = NSOpenPanel()
        p.allowedContentTypes = ["opus", "ogg", "oga", "m4a", "mp3", "aac", "wav", "mp4"].compactMap { UTType(filenameExtension: $0) }
        p.message = "Pick a voice note (in WhatsApp: right-click the voice note → Save As)"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        Task { await take(u, lead: lead) }
    }
}

// MARK: - Today

struct BizTodayView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var sending = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BizStartGuide()
                let today = ZuffiBusiness.iso(Date())
                let monthAgo = ZuffiBusiness.iso(Date().addingTimeInterval(-30 * 86400))
                let sales = crm.leads.filter { $0.isSale && $0.lastContact >= monthAgo }
                // four numbers, short words, never cut off (they wrap onto two rows on a small window)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    tile("New today", "\(crm.leads.filter { $0.added == today }.count)", "tray.and.arrow.down.fill", Biz.blue)
                    tile("To call", "\(crm.leads.filter(\.dueToday).count)", "phone.fill", Ink.accent)
                    tile("Hot", "\(crm.leads.filter { $0.isOpen && $0.priority.lowercased() == "hot" }.count)", "flame.fill", Biz.pink)
                    tile("Sales (30 days)", "\(sales.count)", "trophy.fill", Biz.green)
                }
                if !sales.isEmpty {
                    Text("Money from sales in the last 30 days: \(crm.currency) \(Int(sales.reduce(0) { $0 + $1.valueNumber }).formatted())")
                        .font(zf(12)).foregroundColor(Ink.muted)
                }
                BizTodayExtras()
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        GlassBox {
                            VStack(alignment: .leading, spacing: 8) {
                                // one list: who to call back (overdue first), then hot leads — no duplicates
                                let due = crm.leads.filter(\.dueToday).sorted { $0.overdue && !$1.overdue }
                                let hot = crm.leads.filter { $0.isOpen && $0.priority.lowercased() == "hot" && !$0.dueToday }
                                HStack {
                                    header("Needs you today", "person.crop.circle.badge.exclamationmark")
                                    Spacer()
                                    Text("\(due.count + hot.count)").font(zf(12, .semibold)).foregroundColor(Ink.muted)
                                }
                                if due.isEmpty && hot.isEmpty { empty("Nobody to chase today 🎉 New chats will show up here.") }
                                ForEach(due.prefix(10)) { l in BizLeadRow(lead: l, showDue: true) }
                                ForEach(hot.prefix(6)) { l in BizLeadRow(lead: l) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        if !crm.team.isEmpty { GlassBox {
                            VStack(alignment: .leading, spacing: 8) {
                                header("Who isn't following up", "person.fill.questionmark")
                                ForEach(crm.reports()) { r in
                                    HStack {
                                        Text(r.name).font(zf(12.5, .semibold))
                                        Spacer()
                                        if r.overdue > 0 { Pill(text: "\(r.overdue) overdue", color: Biz.red) } else { Pill(text: "on track", color: Biz.green) }
                                    }
                                }
                            }
                        } }
                        GlassBox {
                            VStack(alignment: .leading, spacing: 8) {
                                header("Your daily summary", "doc.text.fill")
                                Text(crm.summary()).font(zf(11.5)).foregroundColor(Ink.ink.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                HStack {
                                    BizMainButton(title: sending ? "Sending…" : "Send to my WhatsApp", icon: "paperplane.fill") {
                                        sending = true
                                        Task { nav.say(await crm.sendSummaryNow()); sending = false }
                                    }
                                    BizSoftButton(title: "Copy", icon: "doc.on.doc") {
                                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(crm.summary(), forType: .string); nav.say("Copied")
                                    }
                                }
                                Text(crm.isOn(.ownerSummary) ? "Sent by itself every day at \(crm.summaryHour):00." : "Turn on the daily send in Automations.")
                                    .font(zf(10)).foregroundColor(Ink.faint)
                            }
                        }
                    }
                    .frame(width: 360)
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 22)
        }
    }

    private func tile(_ t: String, _ v: String, _ icon: String, _ c: Color) -> some View {
        BizTile(title: t, value: v, icon: icon, color: c)
    }
}

private func header(_ t: String, _ icon: String) -> some View {
    Label(t, systemImage: icon).font(zf(13, .heavy))
}
private func empty(_ t: String) -> some View {
    Text(t).font(zf(11.5)).foregroundColor(Ink.faint)
}

struct BizLeadRow: View {
    let lead: CRMLead
    var showDue = false
    @ObservedObject private var nav = BizNav.shared
    var body: some View {
        Button { nav.selected = lead.key; nav.tab = .inbox } label: {
            HStack(spacing: 10) {
                Avatar(lead: lead, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lead.display).font(zf(12.5, .semibold)).lineLimit(1)
                    Text([lead.interest, lead.area, lead.budget].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(lead.lastMessage))
                        .font(zf(10.5)).foregroundColor(Ink.faint).lineLimit(1)
                }
                Spacer()
                if showDue && lead.overdue { Pill(text: "overdue", color: Biz.red) }
                if !lead.assigned.isEmpty { Text(lead.assigned).font(zf(10)).foregroundColor(Ink.faint) }
                StatusDot(text: lead.stage, color: Biz.stageColor(lead.stage))
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct Avatar: View {
    let lead: CRMLead; var size: CGFloat = 34
    var body: some View {
        let c = Biz.stageColor(lead.stage)
        Text(lead.initials.isEmpty ? "?" : lead.initials).font(.system(size: size * 0.36, weight: .heavy))
            .foregroundColor(.white).frame(width: size, height: size)
            .background(Circle().fill(LinearGradient(colors: [c.opacity(0.9), c.opacity(0.45)], startPoint: .top, endPoint: .bottom)))
            .overlay(alignment: .bottomTrailing) {
                if lead.priority.lowercased() == "hot" { Text("🔥").font(.system(size: size * 0.32)).offset(x: 3, y: 3) }
            }
    }
}

extension String { fileprivate func ifEmpty(_ s: String) -> String { isEmpty ? s : self } }

// MARK: - Inbox (WhatsApp chats → leads, suggested replies)

struct BizInboxView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var filter = "All"

    @ObservedObject private var wa = WhatsAppLink.shared
    @State private var confirmDelete: CRMLead?

    private var list: [CRMLead] {
        // Chats that came through linked WhatsApp only show while it's linked (link again → they're back).
        var l = crm.leads.filter { wa.enabled || $0.source != WhatsAppLink.leadSource }
        switch filter {
        case "Needs reply": l = l.filter { crm.drafts[$0.key] != nil }
        case "WhatsApp": l = l.filter { $0.source.lowercased().contains("whatsapp") }
        case "Mine due": l = l.filter(\.dueToday)
        case "Needs you": l = l.filter { $0.isOpen && $0.priority == "Hot" && crm.drafts[$0.key] != nil }
        default: break
        }
        let q = nav.search.lowercased()
        if !q.isEmpty { l = l.filter { ($0.name + $0.phone + $0.area + $0.interest + $0.notes + $0.lastMessage).lowercased().contains(q) } }
        return l.sorted { a, b in
            let da = crm.drafts[a.key] != nil, db = crm.drafts[b.key] != nil
            if da != db { return da }
            return (a.lastMessageAt.isEmpty ? a.added : a.lastMessageAt) > (b.lastMessageAt.isEmpty ? b.added : b.lastMessageAt)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 8) {
                // WhatsApp status + the auto-reply switch, always in view
                HStack(spacing: 8) {
                    Circle().fill(wa.ready ? Biz.green : Ink.faint).frame(width: 8, height: 8)
                    Text(wa.ready ? "WhatsApp linked" : wa.enabled ? "WhatsApp connecting…" : "WhatsApp not linked").font(zf(11.5, .semibold))
                    if !wa.ready { Button(wa.enabled ? "Show code" : "Link") { wa.showWindow() }.buttonStyle(.link).font(zf(11.5, .semibold)) }
                    Spacer()
                    Toggle("Auto-reply", isOn: Binding(get: { crm.isOn(.autopilot) }, set: { crm.set(.autopilot, $0) }))
                        .toggleStyle(.switch).controlSize(.mini).font(zf(11.5, .semibold))
                        .help("Zuffi answers customers by itself from your business info, in their language — and hands over to you for bargaining, complaints or anything it doesn't know.")
                }
                .padding(.horizontal, 10).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 10).fill(Ink.panel))
                Picker("", selection: $filter) { ForEach(["All", "Needs reply", "Needs you", "WhatsApp", "Mine due"], id: \.self) { Text($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(list) { l in
                            Button { nav.selected = l.key } label: {
                                HStack(spacing: 10) {
                                    Avatar(lead: l)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(l.display).font(zf(12.5, .bold)).lineLimit(1)
                                            Spacer()
                                            Text(shortTime(l.lastMessageAt.isEmpty ? l.added : l.lastMessageAt)).font(zf(9.5)).foregroundColor(Ink.ink.opacity(0.45))
                                        }
                                        Text(l.lastMessage.isEmpty ? (l.interest.isEmpty ? l.source : l.interest) : l.lastMessage)
                                            .font(zf(11)).foregroundColor(Ink.muted).lineLimit(1)
                                        HStack(spacing: 4) {
                                            if crm.drafts[l.key] != nil { Pill(text: "reply ready", color: Biz.pink, filled: true) }
                                            Pill(text: l.stage, color: Biz.stageColor(l.stage))
                                            if !l.assigned.isEmpty { Pill(text: l.assigned, color: Ink.ink.opacity(0.7)) }
                                        }
                                    }
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(nav.selected == l.key ? Ink.ink.opacity(0.12) : .clear))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete chat…", role: .destructive) { confirmDelete = l }
                            }
                        }
                        if list.isEmpty {
                            empty(filter == "Needs reply" ? "No replies waiting." : "No leads yet. Open WhatsApp on this Mac — new chats appear here by themselves. Or press “Add lead”.")
                                .padding(.top, 30).multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .frame(width: 330).padding(.leading, 18).padding(.bottom, 14)
            .alert("Delete \(confirmDelete?.display ?? "this chat")?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
                Button("Delete", role: .destructive) { if let l = confirmDelete { if nav.selected == l.key { nav.selected = nil }; crm.delete(l.key) }; confirmDelete = nil }
                Button("Cancel", role: .cancel) { confirmDelete = nil }
            } message: { Text("Removes the lead and its notes from Zuffi. The chat stays in WhatsApp on your phone.") }
            Divider().overlay(Biz.stroke).padding(.horizontal, 10)
            if let key = nav.selected, let l = crm.leads.first(where: { $0.key == key }) {
                BizLeadDetail(lead: l).id(l.key)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill").font(zf(40)).foregroundColor(Ink.ink.opacity(0.3))
                    Text("Pick a chat").font(zf(15, .bold)).foregroundColor(Ink.muted)
                    Text(crm.whatsAppStatus).font(zf(11)).foregroundColor(Ink.ink.opacity(0.45))
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func shortTime(_ s: String) -> String {
        if s.hasPrefix(ZuffiBusiness.iso(Date())) { return String(s.dropFirst(11)) }
        return String(s.prefix(10).dropFirst(5))
    }
}

struct BizLeadDetail: View {
    let lead: CRMLead
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var reply = ""
    @State private var working = false
    @State private var editing = false
    @State private var follow = Date()
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Avatar(lead: lead, size: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lead.display).font(zf(19, .heavy))
                        Text([lead.phone, lead.source].filter { !$0.isEmpty }.joined(separator: " · ")).font(zf(11.5)).foregroundColor(Ink.muted).textSelection(.enabled)
                    }
                    Spacer()
                    BizSoftButton(title: "Edit", icon: "pencil") { editing = true }
                    BizSoftButton(title: "WhatsApp", icon: "message.fill") { openChat() }
                }
                // Stage + priority + owner
                HStack(spacing: 8) {
                    Menu {
                        ForEach(crm.stages, id: \.self) { s in Button(s) { crm.setStage(lead.key, s) } }
                    } label: { Pill(text: "Stage: \(lead.stage) ▾", color: Biz.stageColor(lead.stage)) }.menuStyle(.borderlessButton).fixedSize()
                    Menu {
                        ForEach(["Hot", "Warm", "Cold", ""], id: \.self) { p in Button(p.isEmpty ? "None" : p) { var l = lead; l.priority = p; crm.update(l) } }
                    } label: { Pill(text: lead.priority.isEmpty ? "Priority ▾" : "\(lead.priority) ▾", color: lead.priority == "Hot" ? Biz.red : Ink.accent) }.menuStyle(.borderlessButton).fixedSize()
                    Menu {
                        Button("Nobody") { crm.assign(lead.key, to: "") }
                        ForEach(crm.team) { s in Button(s.name) { crm.assign(lead.key, to: s.name) } }
                        if crm.team.isEmpty { Button("Add team members in Team…") { nav.tab = .team } }
                    } label: { Pill(text: lead.assigned.isEmpty ? "Assign to… ▾" : "👤 \(lead.assigned) ▾", color: Ink.ink.opacity(0.8)) }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                }
                // What they want
                GlassBox {
                    // wraps onto more rows instead of squeezing words ("2026-10…")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 14, alignment: .topLeading)], alignment: .leading, spacing: 12) {
                        fact(crm.labels.interest, lead.interest); fact(crm.labels.area, lead.area); fact(crm.labels.budget, lead.budget); fact(crm.labels.value, lead.value.isEmpty ? "" : crm.currency + " " + lead.value)
                        fact("Added", String(lead.added.prefix(10))); fact("Last contact", String(lead.lastContact.prefix(10)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Follow up").font(zf(10, .bold)).foregroundColor(Ink.faint)
                            DatePicker("", selection: $follow, displayedComponents: .date).labelsHidden().datePickerStyle(.compact)
                                .onChange(of: follow) { _, d in
                                    let iso = ZuffiBusiness.iso(d)
                                    if iso != lead.nextFollowUp {
                                        var l = lead; l.nextFollowUp = iso; crm.update(l)
                                        crm.log(lead: lead.display, staff: lead.assigned, kind: "Follow-up", detail: iso)
                                    }
                                }
                        }
                    }
                }
                // Last message + reply
                GlassBox {
                    VStack(alignment: .leading, spacing: 10) {
                        header("Conversation", "bubble.left.and.bubble.right.fill")
                        if !lead.lastMessage.isEmpty {
                            HStack(alignment: .top) {
                                Text(lead.lastMessage).font(zf(12.5)).padding(10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Ink.ink.opacity(0.1)))
                                Spacer(minLength: 60)
                            }
                        } else { empty("No message yet.") }
                        if lead.lastMessage.hasPrefix("🎤") || lead.notes.contains("voice note") {
                            BizSoftButton(title: "Write out a voice note from \(lead.display.split(separator: " ").first.map(String.init) ?? "them")", icon: "waveform") { BusinessFiles.pickVoiceNote(for: lead.key) }
                        }
                        TextEditor(text: $reply).font(zf(12.5)).scrollContentBackground(.hidden)
                            .frame(minHeight: 70).padding(8)
                            .foregroundColor(Ink.text)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Biz.stroke))
                        HStack {
                            BizMainButton(title: working ? "Sending…" : "Send on WhatsApp", icon: "paperplane.fill") {
                                guard !reply.isEmpty, !working else { return }
                                working = true
                                Task { nav.say(await crm.send(lead.key, reply)); reply = ""; working = false }
                            }
                            BizSoftButton(title: "Write a reply for me", icon: "sparkles") {
                                working = true
                                Task { reply = await crm.draftReply(for: lead, incoming: lead.lastMessage, first: lead.stage == "New"); working = false }
                            }
                            Spacer()
                            if crm.drafts[lead.key] != nil { Button("Skip") { crm.drafts[lead.key] = nil; reply = "" }.buttonStyle(.plain).foregroundColor(Ink.muted) }
                        }
                    }
                }
                // Notes
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        header("Notes", "note.text")
                        if !lead.notes.isEmpty {
                            ForEach(lead.notes.components(separatedBy: " | "), id: \.self) { n in
                                Text("• " + n).font(zf(11.5)).foregroundColor(Ink.ink.opacity(0.8)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack {
                            TextField("Add a note…", text: $note).textFieldStyle(.roundedBorder)
                                .onSubmit(addNote)
                            BizSoftButton(title: "Add", action: addNote)
                        }
                    }
                }
                // History
                let hist = crm.activity.filter { $0.lead == lead.display }.suffix(12).reversed()
                if !hist.isEmpty {
                    GlassBox {
                        VStack(alignment: .leading, spacing: 5) {
                            header("History", "clock.arrow.circlepath")
                            ForEach(Array(hist)) { a in
                                Text("\(a.date) \(a.time) · \(a.staff) · \(a.kind) \(a.detail)").font(zf(10.5)).foregroundColor(Ink.muted)
                            }
                        }
                    }
                }
            }
            .padding(.trailing, 22).padding(.bottom, 22)
        }
        .onAppear {
            reply = crm.drafts[lead.key] ?? ""
            follow = lead.followDate ?? Date()
        }
        .sheet(isPresented: $editing) { BizLeadEditor(lead: lead) }
    }

    private func addNote() {
        let n = note.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        var l = lead; l.notes = l.notes.isEmpty ? n : l.notes + " | " + n
        crm.update(l); crm.log(lead: lead.display, staff: lead.assigned, kind: "Note", detail: String(n.prefix(60)))
        note = ""
    }

    private func openChat() {
        let digits = lead.phone.filter(\.isNumber)
        guard !digits.isEmpty else { nav.say("No number for \(lead.display) yet — add it with Edit."); return }
        var d = digits
        if d.hasPrefix("0") { d = (crm.isEstate ? "92" : "44") + d.dropFirst() }
        if let u = URL(string: "whatsapp://send?phone=\(d)") { NSWorkspace.shared.open(u) }
    }

    private func fact(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(t).font(zf(10, .bold)).foregroundColor(Ink.faint)
            Text(v.isEmpty ? "—" : v).font(zf(12.5, .semibold)).lineLimit(2)
        }
    }
}

struct BizLeadEditor: View {
    let lead: CRMLead?
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var crm = ZuffiCRM.shared
    @State private var l = CRMLead(key: "")
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(lead == nil ? "New lead" : "Edit \(lead!.display)").font(zf(17, .heavy))
            Form {
                TextField("Name", text: $l.name)
                TextField("Phone (WhatsApp)", text: $l.phone)
                TextField("Source (Facebook, Zameen, walk-in…)", text: $l.source)
                TextField(crm.isEstate ? "What they want (type and size)" : crm.labels.interest, text: $l.interest)
                TextField(crm.labels.area, text: $l.area)
                TextField(crm.labels.budget, text: $l.budget)
                TextField("\(crm.labels.value) (\(crm.currency))", text: $l.value)
                Picker("Stage", selection: $l.status) { ForEach(crm.stages, id: \.self) { Text($0).tag($0) } }
                Picker("Assigned to", selection: $l.assigned) { Text("Nobody").tag(""); ForEach(crm.team) { Text($0.name).tag($0.name) } }
                TextField("Notes", text: $l.notes)
            }
            HStack {
                if let lead { Button("Delete", role: .destructive) { crm.delete(lead.key); BizNav.shared.selected = nil; dismiss() } }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if lead == nil {
                        let key = crm.addLead(["name": l.name, "phone": l.phone, "source": l.source, "interest": l.interest, "area": l.area, "budget": l.budget,
                                               "status": l.status, "assigned": l.assigned, "notes": l.notes, "value": l.value])
                        BizNav.shared.selected = key; BizNav.shared.tab = .inbox
                    } else { crm.update(l) }
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(l.name.isEmpty && l.phone.isEmpty)
            }
        }
        .padding(20).frame(width: 440)
        .onAppear { l = lead ?? CRMLead(key: "", status: "New") }
    }
}

// MARK: - Pipeline (drag cards between stages)

struct BizPipelineView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var target: String?
    @State private var who = "Everyone"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Show", selection: $who) {
                    Text("Everyone").tag("Everyone"); Text("Nobody assigned").tag("")
                    ForEach(crm.team) { Text($0.name).tag($0.name) }
                }.frame(width: 240)
                Spacer()
                Text("Drag a card to move it.").font(zf(11)).foregroundColor(Ink.faint)
            }.padding(.horizontal, 22)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(crm.stages, id: \.self) { stage in
                        let cards = crm.leads.filter { $0.stage == stage && (who == "Everyone" || $0.assigned == who) && matches($0) }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle().fill(Biz.stageColor(stage)).frame(width: 8, height: 8)
                                Text(stage).font(zf(13, .heavy))
                                Spacer()
                                Text("\(cards.count)").font(zf(11, .bold)).foregroundColor(Ink.faint)
                            }
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(cards) { l in card(l).draggable(l.key) }
                                    if cards.isEmpty { empty("—").frame(maxWidth: .infinity).padding(.vertical, 20) }
                                }
                            }
                        }
                        .padding(10).frame(width: 220).frame(maxHeight: .infinity, alignment: .top)
                        .background(RoundedRectangle(cornerRadius: 16).fill(target == stage ? Biz.stageColor(stage).opacity(0.18) : Ink.ink.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(target == stage ? Biz.stageColor(stage) : Biz.stroke))
                        .dropDestination(for: String.self) { keys, _ in
                            for k in keys { crm.setStage(k, stage) }
                            return true
                        } isTargeted: { on in target = on ? stage : (target == stage ? nil : target) }
                    }
                }.padding(.horizontal, 22).padding(.bottom, 18)
            }
        }
    }

    private func matches(_ l: CRMLead) -> Bool {
        let q = nav.search.lowercased()
        return q.isEmpty || (l.name + l.phone + l.area + l.interest).lowercased().contains(q)
    }

    private func card(_ l: CRMLead) -> some View {
        Button { nav.selected = l.key; nav.tab = .inbox } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(l.display).font(zf(12.5, .bold)).lineLimit(1)
                    Spacer()
                    if l.priority.lowercased() == "hot" { Text("🔥") }
                }
                if !l.interest.isEmpty || !l.area.isEmpty { Text([l.interest, l.area].filter { !$0.isEmpty }.joined(separator: " · ")).font(zf(10.5)).foregroundColor(Ink.muted).lineLimit(2) }
                HStack(spacing: 4) {
                    if !l.budget.isEmpty { Pill(text: l.budget, color: Biz.green) }
                    if l.overdue { Pill(text: "overdue", color: Biz.red) }
                    Spacer()
                    if !l.assigned.isEmpty { Text(l.assigned).font(zf(9.5)).foregroundColor(Ink.faint) }
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.ink.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Biz.stroke, lineWidth: 0.6))
        }.buttonStyle(.plain)
    }
}

// MARK: - Team

struct BizTeamView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var name = ""
    @State private var phone = ""
    @State private var role = "Agent"
    @State private var payType = "Commission"
    @State private var rate = ""
    @State private var editing: CRMStaff?
    @ObservedObject private var money = ZuffiMoney.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassBox {
                    VStack(alignment: .leading, spacing: 10) {
                        header("Add a team member", "person.badge.plus")
                        HStack {
                            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                            TextField("WhatsApp number", text: $phone).textFieldStyle(.roundedBorder)
                            Picker("", selection: $role) { ForEach(["Agent", "Manager", "Receptionist", "Stylist", "Assistant", "Accountant"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 120)
                        }
                        HStack {
                            Picker("Paid by", selection: $payType) { ForEach(["Commission", "Monthly", "Hourly"], id: \.self) { Text($0) } }.frame(width: 200)
                            TextField(payType == "Commission" ? "Commission %" : payType == "Hourly" ? "Pay per hour (\(crm.currency))" : "Salary per month (\(crm.currency))", text: $rate).textFieldStyle(.roundedBorder).frame(width: 200)
                            Spacer()
                            BizMainButton(title: "Add", icon: "plus") {
                                crm.addStaff(name: name, phone: phone, role: role, payType: payType, rate: rate); name = ""; phone = ""; rate = ""
                            }
                        }
                        Toggle("Share new leads among the team (round robin)", isOn: Binding(get: { crm.isOn(.roundRobin) }, set: { crm.set(.roundRobin, $0) }))
                        Text("Each person gets a PIN. With the always-on server they open the team page on their phone, see only their leads and update them.")
                            .font(zf(10.5)).foregroundColor(Ink.faint)
                    }
                }
                GlassBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            header("Team report", "chart.bar.fill")
                            Spacer()
                            let un = crm.leads.filter { $0.isOpen && $0.assigned.isEmpty }
                            if !un.isEmpty, !crm.team.isEmpty {
                                BizSoftButton(title: "Share \(un.count) unassigned", icon: "arrow.triangle.branch") {
                                    let agents = crm.team.map(\.name)
                                    for (i, l) in un.enumerated() { crm.assign(l.key, to: agents[i % agents.count]) }
                                    nav.say("Shared \(un.count) leads among \(agents.count) people.")
                                }
                            }
                        }
                        if crm.team.isEmpty { empty("No team yet — add the people who handle leads above.") }
                        else {
                            HStack {
                                Text("Name").frame(width: 150, alignment: .leading)
                                ForEach(["Leads", "Open", "New today", "Contacts · 7d", "Won", "Overdue"], id: \.self) { Text($0).frame(width: 80) }
                                Spacer()
                            }.font(zf(10.5, .bold)).foregroundColor(Ink.faint)
                            ForEach(crm.reports()) { r in
                                let s = crm.team.first { $0.name == r.name }
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.name).font(zf(12.5, .bold))
                                        Text("\(s?.role ?? "") · PIN \(s?.pin ?? "")").font(zf(9.5)).foregroundColor(Ink.ink.opacity(0.45))
                                    }.frame(width: 150, alignment: .leading)
                                    ForEach(Array([r.assigned, r.open, r.newToday, r.contacted7, r.won].enumerated()), id: \.offset) { _, v in Text("\(v)").frame(width: 80) }
                                    Group { if r.overdue > 0 { Pill(text: "\(r.overdue)", color: Biz.red, filled: true) } else { Pill(text: "0", color: Biz.green) } }.frame(width: 80)
                                    Spacer()
                                    Menu {
                                        if let s { Button("Edit \(s.name)'s details & pay") { editing = s } }
                                        Button("Show their leads") { nav.search = ""; nav.tab = .pipeline }
                                        if let s { Button("Remove \(s.name)", role: .destructive) { crm.removeStaff(s) } }
                                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                                }
                                .font(zf(12.5))
                                if !r.overdueNames.isEmpty {
                                    Text("Overdue: " + r.overdueNames.joined(separator: ", ")).font(zf(10.5)).foregroundColor(Biz.red.opacity(0.85)).padding(.leading, 4)
                                }
                                Divider().overlay(Biz.stroke)
                            }
                        }
                    }
                }
                BizPayrollBox(editing: $editing)
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }
        .sheet(item: $editing) { st in StaffEditor(staff: st) }
    }
}

// MARK: - Automations

struct BizAutomationsView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @AppStorage("bizOpenHour") private var openHour = 9
    @AppStorage("bizCloseHour") private var closeHour = 20
    @AppStorage("bizClosedSunday") private var closedSunday = false
    @AppStorage("bizReviewLink") private var reviewLink = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        header("Opening hours & reviews", "clock.fill")
                        HStack {
                            Stepper("Open from \(openHour):00", value: $openHour, in: 0...23)
                            Spacer()
                            Stepper("until \(closeHour):00", value: $closeHour, in: 1...24)
                            Spacer()
                            Toggle("Closed on Sundays", isOn: $closedSunday)
                        }.font(zf(12))
                        TextField("Your review link (Google, Facebook…) — used in thank-you messages", text: $reviewLink).textFieldStyle(.roundedBorder)
                    }
                }
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        header("You", "person.crop.circle.fill")
                        HStack {
                            TextField("Your name", text: $crm.ownerName).textFieldStyle(.roundedBorder)
                            TextField("Your WhatsApp number (for the daily summary)", text: $crm.ownerPhone).textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Stepper("Daily summary at \(crm.summaryHour):00", value: $crm.summaryHour, in: 5...22)
                            Spacer()
                            Stepper("Follow up after \(crm.quietDays) quiet day\(crm.quietDays == 1 ? "" : "s")", value: $crm.quietDays, in: 1...14)
                        }.font(zf(12))
                    }
                }
                ForEach(ZuffiCRM.Auto.allCases) { a in
                    GlassBox(padding: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(a)).font(zf(16)).foregroundColor(Ink.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(zf(13, .bold))
                                Text(a.detail).font(zf(11)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                                if a == .autoReply {
                                    TextField("Welcome message (optional — use {name}). Empty = Zuffi writes one for each client.", text: $crm.welcomeText).textFieldStyle(.roundedBorder).padding(.top, 4)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { crm.isOn(a) }, set: { crm.set(a, $0); if !crm.serverURL.isEmpty { Task { await crm.pushTeam() } } }))
                                .toggleStyle(.switch).labelsHidden()
                        }
                    }
                }
                Text("Every message Zuffi sends is logged in the lead's history. Marketing messages in the UK need the client's OK first.")
                    .font(zf(10.5)).foregroundColor(Ink.ink.opacity(0.45))
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }
    }
    private func icon(_ a: ZuffiCRM.Auto) -> String {
        switch a {
        case .autopilot: return "airplane"
        case .morningAsk: return "sunrise.fill"
        case .includeContacts: return "person.crop.circle.badge.checkmark"
        case .watchWhatsApp: return "message.badge.filled.fill"
        case .draftReplies: return "text.bubble.fill"
        case .autoReply: return "paperplane.fill"
        case .voiceNotes: return "waveform"
        case .leadExports: return "square.and.arrow.down.fill"
        case .roundRobin: return "arrow.triangle.2.circlepath"
        case .quietFollowUp: return "hourglass"
        case .afterHours: return "moon.zzz.fill"
        case .thankAndReview: return "star.bubble.fill"
        case .paymentReminders: return "banknote.fill"
        case .hotLeadAlert: return "flame.fill"
        case .ownerSummary: return "doc.text.fill"
        case .staffDigest: return "person.3.sequence.fill"
        }
    }
}

// MARK: - Connect WhatsApp

struct BizConnectView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @State private var key = KeychainStore.shared.get("zuffi-server-key") ?? ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassBox { BizWALinkBox() }
                GlassBox { BizSyncBox() }
                GlassBox { BizPowerBox() }
                GlassBox { BizSecurityBox() }
                GlassBox { BizEraseBox() }
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { header("1 · WhatsApp on this Mac", "laptopcomputer"); Spacer(); Pill(text: "works now", color: Biz.green) }
                        Text("Zuffi reads new chats in the WhatsApp app on this Mac, makes them leads and writes replies. Nothing extra to set up — but it only works while the Mac is awake and WhatsApp is open.")
                            .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        TimelineView(.periodic(from: .now, by: 2)) { _ in
                            let running = NSWorkspace.shared.runningApplications.contains(where: WhatsAppAgent.isWhatsApp)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    check(running ? "WhatsApp app open" : WhatsAppAgent.installed ? "WhatsApp installed but not open" : "WhatsApp for Mac not installed", running)
                                    Spacer()
                                    if !running {
                                        BizMainButton(title: WhatsAppAgent.installed ? "Open WhatsApp" : "Get WhatsApp for Mac", icon: "arrow.up.forward.app") { WhatsAppAgent.openApp() }
                                    }
                                }
                                check("Accessibility allowed for Zuffi", AXIsProcessTrusted())
                                check("Turning chats into leads", crm.isOn(.watchWhatsApp))
                                check("Autopilot replies (Business → My business)", crm.isOn(.autopilot))
                                if !running {
                                    Text(WhatsAppAgent.installed ? "Open WhatsApp and keep it open (you can minimise it)." : "Messages you see from your iPhone (notifications) are saved as leads, but to send replies Zuffi needs the WhatsApp app on this Mac: install it, open it, and link it to your phone (WhatsApp on the phone → Settings → Linked devices → Link a device).")
                                        .font(zf(11)).foregroundColor(Ink.accent).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        HStack {
                            Text(crm.whatsAppStatus + (crm.lastWhatsAppCheck.map { " · \(ZuffiPA.hm($0))" } ?? "")).font(zf(11)).foregroundColor(Ink.muted)
                            Spacer()
                            BizSoftButton(title: "Check now", icon: "arrow.clockwise") { Task { await crm.watchWhatsApp() } }
                            if !AXIsProcessTrusted() { BizSoftButton(title: "Allow Accessibility") { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) } }
                        }
                    }
                }
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { header("2 · Always-on (WhatsApp Business API + Coexistence)", "antenna.radiowaves.left.and.right"); Spacer(); Pill(text: "best for a business", color: Ink.accent) }
                        Text("Replies within seconds even when the Mac is off. The business keeps using the WhatsApp Business app on the phone with the same number — chats show in both. Voice notes are written out automatically, Facebook / Instagram lead forms arrive instantly, and each team member gets their own page.")
                            .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 4) {
                            step("1", "Set up the Zuffi server (one time) — see server/README.md: Cloudflare, free plan is enough.")
                            step("2", "Create a Meta business app and add WhatsApp. To keep the WhatsApp Business app on the phone (Coexistence), connect through a Meta partner (or Zuffi as a Tech Provider) and scan the QR code. Or use a number that isn't on WhatsApp yet — that one you can add directly.")
                            step("3", "Paste the server address and the admin key below, then press Test.")
                        }
                        HStack {
                            TextField("Server address, e.g. https://zuffi-wa.yourname.workers.dev", text: $crm.serverURL).textFieldStyle(.roundedBorder)
                            SecureField("Admin key", text: $key).textFieldStyle(.roundedBorder).frame(width: 200)
                            BizMainButton(title: "Test") {
                                let v = key.trimmingCharacters(in: .whitespaces)
                                if v.isEmpty { KeychainStore.shared.remove("zuffi-server-key") } else { KeychainStore.shared.set("zuffi-server-key", value: v) }
                                Task { await crm.testServer(); if crm.serverStatus.hasPrefix("Connected") { await crm.pushTeam(); await crm.pushLeads() } }
                            }
                        }
                        if !crm.serverStatus.isEmpty { Text(crm.serverStatus).font(zf(11.5, .semibold)).foregroundColor(crm.serverStatus.hasPrefix("Connected") ? Biz.green : Ink.accent) }
                        Text("Costs from Meta: replies within 24 hours of a client's message are free; messages you start (reminders, offers) are charged per message.")
                            .font(zf(10.5)).foregroundColor(Ink.ink.opacity(0.45))
                    }
                }
                GlassBox {
                    VStack(alignment: .leading, spacing: 6) {
                        header("Leads from ads and portals", "megaphone.fill")
                        Text("Facebook / Instagram lead forms: with the server they arrive instantly. Without it, download them from Meta Leads Center into Downloads (or drop the file here) — Zuffi adds them within a minute. Zameen, Graana, OLX and Google Forms files work the same way.")
                            .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }
    }
    private func check(_ t: String, _ ok: Bool) -> some View {
        Label(t, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle").font(zf(12)).foregroundColor(ok ? Biz.green : Biz.red)
    }
    private func step(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(zf(11, .heavy)).frame(width: 20, height: 20).background(Circle().fill(Ink.ink.opacity(0.12)))
            Text(t).font(zf(11.5)).foregroundColor(Ink.ink.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Business type picker

struct BizTypeMenu: View {
    @ObservedObject private var biz = ZuffiBusiness.shared
    var body: some View {
        Menu {
            ForEach(ZuffiCRM.shared.packsForCountry) { p in
                Button { Task { BizNav.shared.say(await biz.install(p)); ZuffiCRM.shared.reload() } } label: { Label(p.label + (biz.pack == p ? "  ✓" : ""), systemImage: p.icon) }
            }
            let others = ZuffiBusiness.Pack.allCases.filter { !ZuffiCRM.shared.packsForCountry.contains($0) }
            if !others.isEmpty, !["PK", "GB"].contains(ZuffiCRM.shared.country) {
                Menu("Other types") {
                    ForEach(others) { p in Button { Task { BizNav.shared.say(await biz.install(p)); ZuffiCRM.shared.reload() } } label: { Label(p.label, systemImage: p.icon) } }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: biz.pack?.icon ?? "briefcase.fill")
                Text(biz.pack?.label ?? "Pick your business").lineLimit(1)
                Image(systemName: "chevron.down").font(zf(9, .bold))
            }
            .font(zf(12, .bold)).foregroundColor(Ink.text)
            .padding(.horizontal, 11).frame(height: 30)
            .background(Capsule().fill(Ink.ink.opacity(0.1))).overlay(Capsule().stroke(Biz.stroke, lineWidth: 0.7))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

// MARK: - My business: what Zuffi tells clients + autopilot

struct BizBusinessView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var biz = ZuffiBusiness.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Autopilot
                GlassBox {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "airplane").font(zf(22)).foregroundColor(crm.isOn(.autopilot) ? Biz.green : Ink.ink.opacity(0.5))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(crm.isOn(.autopilot) ? "Autopilot is ON — Zuffi is chatting with your clients" : "Autopilot is off — Zuffi only writes drafts")
                                .font(zf(15, .heavy))
                            Text("Zuffi answers WhatsApp messages by itself using what you write below and today's update. When someone wants to bargain, complains, asks for a person or asks something you haven't told Zuffi, it doesn't guess: it says the team will reply, marks the chat 🔥 and tells you.")
                                .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                            if crm.businessInfo.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
                                Label("Write about your business below first, so Zuffi answers correctly.", systemImage: "exclamationmark.triangle.fill")
                                    .font(zf(11, .semibold)).foregroundColor(Ink.accent)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { crm.isOn(.autopilot) }, set: { crm.set(.autopilot, $0); if $0 { crm.set(.watchWhatsApp, true) } }))
                            .toggleStyle(.switch).labelsHidden().controlSize(.large)
                    }
                }
                GlassBox {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "checklist.checked").font(zf(20)).foregroundColor(Biz.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Reply only with my answers (recommended)").font(zf(13.5, .bold))
                            Text("Zuffi answers customers only from your details and the questions & answers you write below. Anything else gets “thanks, we'll reply shortly” and you're told what they asked — so you can answer and add it to your FAQ. Turn off to let the AI write replies from your details.")
                                .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: $crm.faqOnly).toggleStyle(.switch).labelsHidden()
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    // Today's update
                    GlassBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                header("Today's update", "sunrise.fill")
                                Spacer()
                                Text(Date().formatted(date: .abbreviated, time: .omitted)).font(zf(10.5)).foregroundColor(Ink.faint)
                            }
                            Text("Offers, new items, who's in, what's available — Zuffi mentions it in replies today only.")
                                .font(zf(11)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                            editor(Binding(get: { crm.todaysUpdate }, set: { crm.todayUpdate = $0 }), minHeight: 110)
                            Text(example(for: "today")).font(zf(10.5)).foregroundColor(Ink.ink.opacity(0.45)).fixedSize(horizontal: false, vertical: true)
                            Text("Tip: in the morning just say or type “today's update: …” to Zuffi.").font(zf(10.5)).foregroundColor(Biz.pink)
                        }
                    }
                    // Recently sent by autopilot
                    GlassBox {
                        VStack(alignment: .leading, spacing: 6) {
                            header("Sent by Zuffi", "paperplane.fill")
                            if crm.autoSent.isEmpty { empty("Nothing yet. Replies Zuffi sends by itself show here (and in each client's history).") }
                            ForEach(crm.autoSent.prefix(10), id: \.self) { t in
                                Text(t).font(zf(11)).foregroundColor(Ink.ink.opacity(0.8)).lineLimit(2)
                            }
                        }
                    }
                    .frame(width: 300)
                }
                // About the business
                GlassBox { BizDetailsForm() }
                GlassBox { BizFAQEditor() }
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            header("About your business", "building.2.fill")
                            Spacer()
                            BizTypeMenu()
                        }
                        HStack {
                            TextField("Business name (used in messages)", text: Binding(get: { biz.businessName }, set: { biz.businessName = $0; UserDefaults.standard.set($0, forKey: "zuffiBusinessName") }))
                                .textFieldStyle(.roundedBorder)
                            // The country comes from your Zuffi details (set when you joined) — not chosen here.
                            let c = ZuffiCRM.allCountries.first { $0.code == crm.country }
                            Label("\(c?.flag ?? "🌍") \(c?.name ?? "Your country") · \(crm.currency)", systemImage: "mappin.and.ellipse")
                                .font(zf(12, .medium)).foregroundColor(Ink.muted).lineLimit(1).fixedSize()
                                .help("From your details. To change it: Zuffi → Settings → You → Edit my details.")
                        }
                        Text(crm.country == "PK" ? "Pakistan: set up for estate agencies — properties, agents on commission, installments, Zameen / Facebook leads, Urdu replies."
                             : crm.country == "GB" ? "United Kingdom: set up for small businesses — bookings, staff hours and wages, deposits, expenses and VAT categories."
                             : "Pick the business type that fits you.")
                            .font(zf(10.5)).foregroundColor(Biz.pink)
                        Text("Everything Zuffi knows about your business (the form above fills this in). Add anything else clients ask about. Zuffi only uses what's written here.")
                            .font(zf(11)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                        editor($crm.businessInfo, minHeight: 220)
                        HStack {
                            BizSoftButton(title: "Open as a file", icon: "doc.text") { NSWorkspace.shared.open(ZuffiCRM.infoURL) }
                            Spacer()
                            Text("Saved automatically").font(zf(10)).foregroundColor(Ink.ink.opacity(0.4))
                        }
                    }
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 22)
        }
    }

    private func editor(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text).font(zf(12.5)).scrollContentBackground(.hidden)
            .frame(minHeight: minHeight).padding(8)
            .foregroundColor(Ink.text)
            .background(RoundedRectangle(cornerRadius: 12).fill(Ink.panelHi))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Biz.stroke))
    }

    private func example(for part: String) -> String {
        let name = biz.businessName.isEmpty ? "" : biz.businessName
        switch (crm.kind, part) {
        case (.realEstate, "today"): return "For example: new listings, price changes or site-visit times for today."
        case (.realEstate, _): return "\(name.isEmpty ? "We are a property agency" : name) in [your city and the areas you cover].\nWe deal in plots, houses and apartments — buying, selling and rent.\nOffice: [address]. Open 10am–8pm, Monday to Saturday.\nSite visits are free — clients choose a day and time.\nCommission: 1% from buyer and 1% from seller.\nWe need: area, size (marla / sq ft) and budget to suggest options.\nWe speak Urdu and English."
        case (.salon, "today"): return "For example: today’s offer, who’s in today, or free slots."
        case (.salon, _): return "\(name.isEmpty ? "Our salon" : name), [address]. Open Tue–Sat 9am–6pm, Thursday till 8pm.\nPrices: Cut & blow dry £45 · Colour from £85 · Highlights from £95 · Gel nails £30.\nBooking: tell us the service and a day; we'll offer times. £10 deposit for colour.\nPatch test needed 48 hours before a first colour.\nParking behind the salon. Card and cash."
        case (.clinic, "today"): return "For example: who’s in today, or a special offer this week."
        case (.clinic, _): return "\(name.isEmpty ? "Our clinic" : name), [address]. Open Mon–Fri 9am–5pm.\nServices and prices: Check-up £50 · Hygienist £65 · Whitening £250.\nNew patients: bring ID; arrive 10 minutes early.\nEmergencies: call [number]. We can't give medical advice on WhatsApp."
        case (.shop, "today"): return "For example: new stock, today’s offer or delivery changes."
        case (.shop, _): return "\(name.isEmpty ? "Our shop" : name). We sell [products].\nPrices: [main items and prices].\nDelivery: UK 2–3 days, £3.99, free over £50. Collection from [address].\nPayment: card, bank transfer, cash on collection.\nReturns within 14 days, unused with tags."
        case (.restaurant, "today"): return "For example: today’s special, or when tables are free."
        case (.restaurant, _): return "\(name.isEmpty ? "Our restaurant" : name), [address]. Open daily 12pm–11pm.\nBookings for up to 12 people; bigger groups call us.\nMenu highlights and prices: [dishes].\nHalal. Vegetarian options. Takeaway and delivery via [apps]."
        case (.services, "today"): return "e.g. Free quotes this week. Available for jobs from Thursday."
        case (.freelancer, "today"): return "e.g. Taking 2 new projects this month. Next free start date: the 20th."
        case (.freelancer, _): return "\(name.isEmpty ? "I'm a freelancer" : name). I do [services, e.g. websites, design, writing].\nPrices: [day rate or typical project prices]. 50% upfront, rest on delivery.\nUsual turnaround: [e.g. 1–2 weeks].\nTo start: tell me what you need, your deadline and budget, and I'll send a quote.\nInvoices by bank transfer within 14 days."
        case (_, _): return "\(name.isEmpty ? "We" : name) do [services] in [areas].\nPrices: [typical prices or how quotes work].\nHours: [days and times]. Free quotes: send photos and your postcode.\nPayment: [terms]. Guarantee: [details]."
        }
    }
}

// MARK: - Records: every client in one table (sort, filter, open in Excel)

struct BizRecordsView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var sort = [KeyPathComparator(\CRMLead.added, order: .reverse)]
    @State private var stage = "All"
    @State private var selection = Set<String>()

    private var rows: [CRMLead] {
        let q = nav.search.lowercased()
        return crm.leads.filter { l in
            (stage == "All" || l.stage == stage) &&
            (q.isEmpty || (l.name + l.phone + l.area + l.interest + l.notes + l.source).lowercased().contains(q))
        }.sorted(using: sort)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("", selection: $stage) {
                    Text("All stages").tag("All")
                    ForEach(crm.stages, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 160)
                Text("\(rows.count) record\(rows.count == 1 ? "" : "s")").font(zf(11.5)).foregroundColor(Ink.muted)
                Spacer()
                BizSoftButton(title: "Open in Excel / Numbers", icon: "tablecells") { NSWorkspace.shared.open(ZuffiPA.url("Leads")) }
                BizSoftButton(title: "Save a copy", icon: "square.and.arrow.down") { saveCopy() }
                BizSoftButton(title: "Import", icon: "square.and.arrow.up") { importFile() }
            }
            .padding(.horizontal, 22)
            Table(rows, selection: $selection, sortOrder: $sort) {
                TableColumn("Name", value: \.display) { l in HStack(spacing: 8) { Avatar(lead: l, size: 22); Text(l.display).fontWeight(.semibold).lineLimit(1) } }
                TableColumn("Phone", value: \.phone)
                TableColumn("Stage", value: \.status) { l in StatusDot(text: l.stage, color: Biz.stageColor(l.stage)) }
                TableColumn(crm.labels.interest, value: \.interest)
                TableColumn(crm.labels.area, value: \.area)
                TableColumn(crm.labels.budget, value: \.budget)
                TableColumn(crm.labels.value, value: \.value)
                TableColumn("Assigned", value: \.assigned)
                TableColumn("Next follow-up", value: \.nextFollowUp) { l in Text(l.nextFollowUp).foregroundColor(l.overdue ? Biz.red : Ink.text) }
                TableColumn("Source", value: \.source)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                Button("Open") { if let k = keys.first { nav.selected = k; nav.tab = .inbox } }
                Menu("Move to stage") { ForEach(crm.stages, id: \.self) { s in Button(s) { for k in keys { crm.setStage(k, s) } } } }
                Menu("Assign to") {
                    Button("Nobody") { for k in keys { crm.assign(k, to: "") } }
                    ForEach(crm.team) { t in Button(t.name) { for k in keys { crm.assign(k, to: t.name) } } }
                }
                Button("Delete", role: .destructive) { for k in keys { crm.delete(k) } }
            } primaryAction: { keys in
                if let k = keys.first { nav.selected = k; nav.tab = .inbox }
            }
            .scrollContentBackground(.hidden)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.25)))
            .padding(.horizontal, 22).padding(.bottom, 18)
        }
    }

    private func saveCopy() {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Zuffi clients \(ZuffiBusiness.iso(Date())).csv"
        p.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        try? FileManager.default.removeItem(at: u)
        try? FileManager.default.copyItem(at: ZuffiPA.url("Leads"), to: u)
        nav.say("Saved \(u.lastPathComponent)")
    }

    private func importFile() {
        let p = NSOpenPanel()
        p.allowedContentTypes = ["csv", "xlsx", "tsv"].compactMap { UTType(filenameExtension: $0) }
        p.message = "Pick a list of clients or leads (Excel or CSV) — Zuffi adds the new people"
        NSApp.activate(ignoringOtherApps: true)
        guard p.runModal() == .OK, let u = p.url else { return }
        Task { await BusinessFiles.take(u) }
    }
}

// MARK: - Today: visits and money to collect

struct BizTodayExtras: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var props = ZuffiProperties.shared
    @ObservedObject private var money = ZuffiMoney.shared
    var body: some View {
        let visits = props.upcomingVisits.prefix(6)
        let dues = money.dueOpen.filter { $0.due <= ZuffiBusiness.iso(Date().addingTimeInterval(3 * 86400)) }.prefix(6)
        if (crm.isEstate && !visits.isEmpty) || !dues.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                if crm.isEstate && !visits.isEmpty {
                    GlassBox {
                        VStack(alignment: .leading, spacing: 6) {
                            header("Site visits", "figure.walk")
                            ForEach(Array(visits)) { v in
                                Text("\(v.date == ZuffiBusiness.iso(Date()) ? "Today" : v.date) \(v.time) · \(v.client) · \(v.property)").font(zf(12))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if !dues.isEmpty {
                    GlassBox {
                        VStack(alignment: .leading, spacing: 6) {
                            header("Money to collect", "banknote.fill")
                            ForEach(Array(dues)) { d in
                                HStack {
                                    Text("\(d.client) · \(d.what) · \(crm.currency) \(ZuffiMoney.pretty(d.amount))").font(zf(12))
                                    Spacer()
                                    Text(d.overdue ? "overdue" : d.due).font(zf(10.5, .bold)).foregroundColor(d.overdue ? Biz.red : Ink.accent)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

// MARK: - Team & staff: pay, hours, commission

struct BizPayrollBox: View {
    @Binding var editing: CRMStaff?
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var money = ZuffiMoney.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var hoursFor: String?
    @State private var hoursText = ""

    var body: some View {
        GlassBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    header("Pay this month · \(money.monthName(money.month))", "creditcard.fill")
                    Spacer()
                    let unpaid = money.payLines(money.month).filter { !$0.paid && $0.net > 0 }
                    if !unpaid.isEmpty {
                        BizMainButton(title: "Pay \(unpaid.count) · \(crm.currency) \(ZuffiMoney.pretty(unpaid.reduce(0) { $0 + $1.net }))", icon: "checkmark.seal.fill") {
                            nav.say(money.paySalaries())
                        }
                    }
                }
                if crm.team.isEmpty { empty("Add your team above. Set how each person is paid: commission %, monthly salary or per hour.") }
                else {
                    HStack {
                        Text("Name").frame(width: 150, alignment: .leading)
                        ForEach(["Paid by", "Rate", "Hours", "Commission", "Advances", "To pay", ""], id: \.self) { Text($0).frame(width: 88, alignment: .leading) }
                    }.font(zf(10.5, .bold)).foregroundColor(Ink.faint)
                    ForEach(money.payLines(money.month)) { p in
                        HStack {
                            Text(p.name).font(zf(12.5, .bold)).frame(width: 150, alignment: .leading)
                            Text(p.payType).frame(width: 88, alignment: .leading)
                            Text(p.rate == 0 ? "—" : p.payType == "Commission" ? "\(ZuffiMoney.plain(p.rate))%" : "\(crm.currency) \(ZuffiMoney.pretty(p.rate))").frame(width: 88, alignment: .leading)
                            Button { hoursFor = p.name; hoursText = "" } label: { Text("\(ZuffiMoney.plain(p.hours)) h ＋").underline() }.buttonStyle(.plain).frame(width: 88, alignment: .leading)
                            Text(p.commission == 0 ? "—" : "\(crm.currency) \(ZuffiMoney.pretty(p.commission))").frame(width: 88, alignment: .leading)
                            Text(p.advances == 0 ? "—" : "−\(ZuffiMoney.pretty(p.advances))").foregroundColor(p.advances > 0 ? Biz.red : Ink.text).frame(width: 88, alignment: .leading)
                            Text("\(crm.currency) \(ZuffiMoney.pretty(p.net))").fontWeight(.bold).frame(width: 88, alignment: .leading)
                            Group {
                                if p.paid { Pill(text: "paid", color: Biz.green) }
                                else if p.net > 0 { Button("Pay") { nav.say(money.paySalaries(p.name)) }.controlSize(.small) }
                                else if crm.team.first(where: { $0.name == p.name })?.rate.isEmpty ?? true {
                                    Button("Set pay") { editing = crm.team.first { $0.name == p.name } }.controlSize(.small)
                                }
                            }.frame(width: 88, alignment: .leading)
                        }.font(zf(12))
                    }
                    Text("Commission is worked out from the value of deals each agent won this month (set the deal value on the client). Advances you give (expense “Advance to staff”) are taken off. Paying adds a salaries expense in Money.")
                        .font(zf(10.5)).foregroundColor(Ink.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(item: Binding(get: { hoursFor.map { HoursTarget(name: $0) } }, set: { hoursFor = $0?.name })) { t in
            VStack(alignment: .leading, spacing: 12) {
                Text("Hours for \(t.name) today").font(zf(15, .bold))
                TextField("e.g. 7.5", text: $hoursText).textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { hoursFor = nil }
                    Button("Save") { money.logHours(t.name, ZuffiMoney.number(hoursText)); hoursFor = nil }.keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 300)
        }
    }
}

struct HoursTarget: Identifiable { var id: String { name }; let name: String }

struct StaffEditor: View {
    let staff: CRMStaff
    @Environment(\.dismiss) private var dismiss
    @State private var s = CRMStaff(name: "", phone: "", role: "", pin: "")
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.name).font(zf(17, .heavy))
            Form {
                TextField("WhatsApp number", text: $s.phone)
                TextField("Role", text: $s.role)
                Picker("Paid by", selection: $s.payType) { ForEach(["Commission", "Monthly", "Hourly"], id: \.self) { Text($0).tag($0) } }
                TextField(s.payType == "Commission" ? "Commission %" : s.payType == "Hourly" ? "Pay per hour" : "Salary per month", text: $s.rate)
                TextField("Start date (yyyy-mm-dd)", text: $s.start)
                TextField("Notes (ID / NI number, bank, emergency contact…)", text: $s.notes)
                TextField("PIN for the team page", text: $s.pin)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { ZuffiCRM.shared.updateStaff(s); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20).frame(width: 440)
        .onAppear { s = staff }
    }
}

// MARK: - Money tab

struct BizMoneyView: View {
    @ObservedObject private var money = ZuffiMoney.shared
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var month = ZuffiMoney.shared.month
    @State private var type = "Expense"
    @State private var amount = ""
    @State private var category = ""
    @State private var party = ""
    @State private var method = ""
    @State private var note = ""
    @State private var dueClient = ""
    @State private var dueWhat = "Installment"
    @State private var dueAmount = ""
    @State private var dueDate = Date().addingTimeInterval(7 * 86400)

    private var dueKinds: [String] { crm.isEstate ? ["Installment", "Token", "Advance", "Balance", "Rent"] : ["Invoice", "Deposit", "Balance"] }

    private var months: [String] {
        let all = Set(money.entries.map { String($0.date.prefix(7)) } + [money.month])
        return all.sorted(by: >)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("", selection: $month) { ForEach(months, id: \.self) { Text(money.monthName($0)).tag($0) } }.labelsHidden().frame(width: 180)
                    Spacer()
                    BizSoftButton(title: "Open in Excel / Numbers", icon: "tablecells") { NSWorkspace.shared.open(ZuffiPA.url("Money")) }
                }
                let inc = money.income(month), exp = money.expenses(month)
                HStack(spacing: 12) {
                    tile("Income", inc, Biz.green, "arrow.down.circle.fill")
                    tile("Expenses", exp, Biz.red, "arrow.up.circle.fill")
                    tile(inc - exp >= 0 ? "Profit" : "Loss", abs(inc - exp), inc - exp >= 0 ? Biz.green : Biz.red, "chart.line.uptrend.xyaxis")
                    tile("To collect", money.dueOpen.reduce(0) { $0 + $1.amount }, Ink.accent, "hourglass")
                }
                HStack(alignment: .top, spacing: 14) {
                    // Add an entry
                    GlassBox {
                        VStack(alignment: .leading, spacing: 8) {
                            header("Add income or expense", "plus.circle.fill")
                            Picker("", selection: $type) { Text("Expense").tag("Expense"); Text("Income").tag("Income") }.pickerStyle(.segmented).labelsHidden()
                            HStack {
                                TextField(crm.isEstate || crm.country == "PK" ? "Amount (\(crm.currency)) — e.g. 2 lakh" : "Amount (\(crm.currency)) — e.g. 45", text: $amount).textFieldStyle(.roundedBorder)
                                Picker("", selection: $category) {
                                    Text("Category").tag("")
                                    ForEach(type == "Income" ? money.incomeCategories : money.expenseCategories, id: \.self) { Text($0).tag($0) }
                                }.labelsHidden().frame(width: 190)
                            }
                            HStack {
                                TextField(type == "Income" ? "From (client)" : "To (supplier / staff)", text: $party).textFieldStyle(.roundedBorder)
                                Picker("", selection: $method) { Text("Paid by").tag(""); ForEach(money.methods, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 130)
                            }
                            TextField("Note", text: $note).textFieldStyle(.roundedBorder)
                            HStack {
                                BizMainButton(title: "Save", icon: "checkmark") {
                                    let a = ZuffiMoney.number(amount)
                                    guard a > 0 else { nav.say("Type an amount first."); return }
                                    nav.say(money.add(type: type, category: category.isEmpty ? (type == "Income" ? money.incomeCategories[0] : "Other") : category, amount: a, party: party, method: method, note: note))
                                    amount = ""; party = ""; note = ""
                                }
                                Text(crm.country == "PK" ? "Or just tell Zuffi: “expense 5000 petrol”, “income 2 lakh commission”." : "Or just tell Zuffi: “expense 60 supplies”, “income 450 haircuts”.").font(zf(10.5)).foregroundColor(Ink.faint).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    // Breakdown
                    GlassBox {
                        VStack(alignment: .leading, spacing: 6) {
                            header("Where the money went", "chart.pie.fill")
                            let cats = money.byCategory(month, type: "Expense")
                            if cats.isEmpty { empty("No expenses this month.") }
                            Spacer(minLength: 0)
                            let top = cats.first?.1 ?? 1
                            ForEach(cats.prefix(8), id: \.0) { c in
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack { Text(c.0).font(zf(11.5)); Spacer(); Text("\(crm.currency) \(ZuffiMoney.pretty(c.1))").font(zf(11.5, .semibold)) }
                                    GeometryReader { g in Capsule().fill(Biz.red.opacity(0.7)).frame(width: max(4, g.size.width * c.1 / top)) }.frame(height: 5)
                                }
                            }
                        }
                    }.frame(width: 300).frame(maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                // Payments due (installments, tokens, invoices)
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        header(crm.isEstate ? "Installments & payments to collect" : "Payments to collect", "calendar.badge.clock")
                        HStack {
                            TextField("Client", text: $dueClient).textFieldStyle(.roundedBorder)
                            Picker("", selection: $dueWhat) { ForEach(dueKinds, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 120)
                                .onAppear { if !dueKinds.contains(dueWhat) { dueWhat = dueKinds[0] } }
                            TextField("Amount", text: $dueAmount).textFieldStyle(.roundedBorder).frame(width: 120)
                            DatePicker("", selection: $dueDate, displayedComponents: .date).labelsHidden()
                            BizSoftButton(title: "Add", icon: "plus") {
                                let a = ZuffiMoney.number(dueAmount)
                                guard a > 0, !dueClient.isEmpty else { return }
                                let phone = crm.leads.first { $0.name.lowercased().hasPrefix(dueClient.lowercased()) }?.phone ?? ""
                                money.addDue(client: dueClient, phone: phone, what: dueWhat, amount: a, due: ZuffiBusiness.iso(dueDate))
                                dueClient = ""; dueAmount = ""
                            }
                        }
                        let open = money.dueOpen
                        if open.isEmpty { empty("Nothing to collect. Zuffi reminds you the day before each payment is due.") }
                        ForEach(open) { d in
                            HStack {
                                Text(d.client).font(zf(12.5, .semibold)).frame(width: 150, alignment: .leading)
                                Text(d.what).frame(width: 100, alignment: .leading)
                                Text("\(crm.currency) \(ZuffiMoney.pretty(d.amount))").frame(width: 130, alignment: .leading)
                                Text(d.due).foregroundColor(d.overdue ? Biz.red : Ink.text).frame(width: 100, alignment: .leading)
                                Spacer()
                                if !d.phone.isEmpty {
                                    Button("Remind on WhatsApp") {
                                        let biz = ZuffiBusiness.shared.businessName
                                        let text = "Assalam o Alaikum \(d.client.split(separator: " ").first ?? ""), a gentle reminder that your \(d.what.lowercased()) of \(crm.currency) \(ZuffiMoney.pretty(d.amount)) is due on \(d.due). Thank you\(biz.isEmpty ? "" : " — \(biz)")."
                                        let fixed = crm.isEstate ? text : text.replacingOccurrences(of: "Assalam o Alaikum", with: "Hi")
                                        Task { nav.say(await WhatsAppAgent.shared.sendScheduled(to: d.phone, text: fixed)) }
                                    }.controlSize(.small)
                                }
                                Button("Mark paid") { money.markPaid(d); nav.say("Marked paid and added to income ✅") }.controlSize(.small)
                            }.font(zf(12))
                        }
                    }
                }
                // Entries
                GlassBox {
                    VStack(alignment: .leading, spacing: 6) {
                        header("Entries · \(money.monthName(month))", "list.bullet.rectangle")
                        let list = money.inMonth(month).reversed()
                        if list.isEmpty { empty("No entries yet.") }
                        ForEach(Array(list)) { e in
                            HStack {
                                Text(e.date).frame(width: 90, alignment: .leading).foregroundColor(Ink.muted)
                                Text(e.category).frame(width: 170, alignment: .leading)
                                Text(e.party).frame(width: 130, alignment: .leading).lineLimit(1)
                                Text(e.note).foregroundColor(Ink.muted).lineLimit(1)
                                Spacer()
                                Text("\(e.type == "Income" ? "+" : "−")\(crm.currency) \(ZuffiMoney.pretty(e.amount))").fontWeight(.bold).foregroundColor(e.type == "Income" ? Biz.green : Biz.red)
                                Button { money.delete(e) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundColor(Ink.ink.opacity(0.4))
                            }.font(zf(12))
                        }
                    }
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 22)
        }
        .onAppear { money.reload() }
    }

    private func tile(_ t: String, _ v: Double, _ c: Color, _ icon: String) -> some View {
        BizTile(title: t, value: "\(crm.currency) \(ZuffiMoney.pretty(v))", icon: icon, color: c)
    }
}


// MARK: - Friendlier pieces: glass number tiles, "What is this page?", getting-started guide

private struct BizTile: View {
    let title: String, value: String, icon: String, color: Color
    @ObservedObject private var lock = BizLock.shared
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title.uppercased()).font(zf(10, .semibold)).tracking(0.4).foregroundColor(Ink.faint)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(value).font(zf(24, .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.55).foregroundColor(Ink.text)
                    .blur(radius: lock.hideAmounts && value.contains(ZuffiCRM.shared.currency) ? 8 : 0)
            }
            Spacer(minLength: 4)
            Image(systemName: icon).font(zf(14, .semibold)).foregroundColor(.white)
                .frame(width: 40, height: 40).background(Circle().fill(color.gradient))
                .shadow(color: color.opacity(0.35), radius: 6, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .inkPanel(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
    }
}

/// A status with a coloured dot (tables and lists).
struct StatusDot: View {
    let text: String; let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(zf(11, .medium)).foregroundColor(Ink.muted).lineLimit(1).fixedSize()
        }
    }
}

struct BizTipsView: View {
    let tab: BizTab
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(tab.rawValue, systemImage: tab.icon).font(zf(15, .heavy))
            Text(tab.subtitle).font(zf(12)).foregroundColor(.secondary)
            ForEach(Array(tab.tips.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(i + 1)").font(zf(11, .heavy)).foregroundColor(.white)
                        .frame(width: 20, height: 20).background(Circle().fill(Color(hex: "#E2648A")))
                    Text(t).font(zf(12.5)).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Tip: you can also just tell Zuffi — tap the mic and say it.").font(zf(11)).foregroundColor(.secondary)
        }
        .padding(16).frame(width: 320)
    }
}

/// The first thing a new owner sees: six simple steps, ticked off as they're done. Hides itself when finished.
struct BizStartGuide: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var biz = ZuffiBusiness.shared
    @ObservedObject private var sync = BizSync.shared
    @ObservedObject private var nav = BizNav.shared
    @AppStorage("bizGuideHidden") private var hidden = false

    private struct Step: Identifiable { let id: Int; let title: String; let detail: String; let done: Bool; let button: String; let go: () -> Void }

    private var steps: [Step] {
        [
            Step(id: 1, title: "Tell Zuffi about your business", detail: "Your business name and type", done: !biz.businessName.isEmpty && biz.pack != nil, button: "Fill in") { nav.tab = .business },
            Step(id: 2, title: "Write your prices & opening hours", detail: "Zuffi uses this to answer clients", done: crm.businessInfo.trimmingCharacters(in: .whitespacesAndNewlines).count > 20, button: "Write") { nav.tab = .business },
            Step(id: 3, title: "Connect WhatsApp", detail: "New chats become clients automatically", done: crm.isOn(.watchWhatsApp) && (WhatsAppLink.shared.ready || WhatsAppAgent.installed), button: "Connect") { nav.tab = .connect },
            Step(id: 4, title: "Add your first client", detail: "Or just tell Zuffi about a new lead", done: !crm.leads.isEmpty, button: "Add") { nav.tab = .records },
            Step(id: 5, title: "Link your phone", detail: "Same business on your phone — scan a QR code", done: sync.linked, button: "Link") { nav.tab = .connect },
            Step(id: 6, title: "Add your staff (optional)", detail: "Salaries, hours, who follows up", done: !crm.team.isEmpty, button: "Add") { nav.tab = .team },
        ]
    }

    var body: some View {
        let s = steps, done = s.filter(\.done).count
        if !hidden && done < s.count, let next = s.first(where: { !$0.done }) {
            // One slim bar: how far you are and the next step — the finished ones don't need space.
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Ink.ink.opacity(0.12), lineWidth: 4)
                    Circle().trim(from: 0, to: CGFloat(done) / CGFloat(s.count))
                        .stroke(Ink.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                    Text("\(done)/\(s.count)").font(zf(10.5, .bold)).monospacedDigit()
                }.frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next step: \(next.title)").font(zf(13.5, .semibold)).lineLimit(1)
                    Text(next.detail).font(zf(11.5)).foregroundColor(Ink.muted).lineLimit(1)
                }
                Spacer(minLength: 8)
                Button(next.button, action: next.go).buttonStyle(.plain)
                    .font(zf(12, .semibold)).foregroundColor(Ink.onAccent)
                    .padding(.horizontal, 14).frame(height: 30).background(Capsule().fill(Ink.accent))
                Button { hidden = true } label: { Image(systemName: "xmark").font(zf(10, .bold)).foregroundColor(Ink.faint) }
                    .buttonStyle(.plain).help("Hide")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .inkPanel(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Connect & devices → disconnect WhatsApp / erase business data

struct BizEraseBox: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @State private var done = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) { Image(systemName: "trash.circle.fill").foregroundColor(Biz.red); Text("Disconnect & erase").font(zf(13, .bold)) }
            Text("Stop Zuffi reading WhatsApp and remove what it saved from WhatsApp, or wipe all business data on this Mac. Your WhatsApp app and chats on your phone are not touched.")
                .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                BizSoftButton(title: "Disconnect WhatsApp", icon: "bolt.slash") {
                    guard confirm("Disconnect WhatsApp?", "Zuffi stops reading WhatsApp and stops Autopilot replies. Clients that came from WhatsApp, and their messages, are removed from this Mac.") else { return }
                    crm.set(.watchWhatsApp, false); crm.set(.autopilot, false)
                    let wa = crm.leads.filter { $0.source.lowercased().contains("whatsapp") || !$0.lastMessageAt.isEmpty }
                    for l in wa { crm.delete(l.key) }
                    crm.reload()
                    done = "WhatsApp disconnected · \(wa.count) WhatsApp client\(wa.count == 1 ? "" : "s") removed"
                }
                BizSoftButton(title: "Erase all business data", icon: "trash") {
                    guard confirm("Erase all business data on this Mac?", "Clients, properties, money, staff, bookings and notes saved by Zuffi on this Mac are deleted, and linked devices are unlinked. This can’t be undone.") else { return }
                    crm.set(.watchWhatsApp, false); crm.set(.autopilot, false)
                    BizSync.shared.unlink()
                    try? FileManager.default.removeItem(at: ZuffiBusiness.docs)
                    crm.reload()
                    done = "All business data erased from this Mac"
                }
            }
            if !done.isEmpty { Text("✓ " + done).font(zf(11)).foregroundColor(Biz.green) }
        }
    }
    private func confirm(_ title: String, _ text: String) -> Bool {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.alertStyle = .warning
        a.addButton(withTitle: "Yes, do it"); a.addButton(withTitle: "Cancel"); a.buttons.first?.hasDestructiveAction = true
        return a.runModal() == .alertFirstButtonReturn
    }
}


/// Colours and light/dark for the Business window.
struct BizLookPicker: View {
    @ObservedObject private var look = BizLook.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Look").font(zf(13, .bold))
            Picker("", selection: Binding(get: { Ink.dark }, set: { look.set(dark: $0) })) {
                Text("Light").tag(false); Text("Dark").tag(true)
            }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
            Text("Colour").font(zf(11, .semibold)).foregroundColor(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 4), spacing: 10) {
                ForEach(Ink.accents, id: \.1) { a in
                    Button { look.set(accent: a.1); UserDefaults.standard.set(a.1, forKey: "zuffiAccentHex") } label: {
                        VStack(spacing: 3) {
                            Circle().fill(Color(hex: a.1)).frame(width: 26, height: 26)
                                .overlay(Circle().stroke(Color.primary.opacity(Ink.accentHex == a.1 ? 0.8 : 0), lineWidth: 2).padding(-3))
                            Text(a.0).font(zf(9.5)).foregroundColor(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            Text("The notch uses the same colour.").font(zf(10)).foregroundColor(.secondary)
        }
        .padding(16)
    }
}


/// Business → Connect: link WhatsApp to Zuffi (instant messages and replies, no typing on the screen).
struct BizWALinkBox: View {
    @ObservedObject private var wa = WhatsAppLink.shared
    @ObservedObject private var crm = ZuffiCRM.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "message.fill").foregroundColor(.white).frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: "#1FAF5F")))
                Text("Link WhatsApp to Zuffi").font(zf(14, .bold))
                Spacer()
                Pill(text: wa.ready ? "Linked" : wa.state == "qr" ? "Scan the code" : wa.enabled ? "Connecting…" : "Off", color: wa.ready ? Biz.green : Ink.accent)
            }
            Text("Like WhatsApp Web, inside Zuffi. New messages arrive the moment they’re sent, become leads, and with Autopilot Zuffi replies in a second or two — in the customer’s language — without using your screen.")
                .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if wa.ready {
                    BizSoftButton(title: "Show WhatsApp", icon: "macwindow") { wa.showWindow() }
                    BizSoftButton(title: "Unlink", icon: "link.badge.plus") { Task { await wa.unlink() } }
                } else {
                    BizMainButton(title: wa.enabled ? "Show the code" : "Link WhatsApp", icon: "qrcode") { wa.showWindow() }
                }
                Toggle("Autopilot replies", isOn: Binding(get: { crm.isOn(.autopilot) }, set: { crm.set(.autopilot, $0) })).toggleStyle(.switch).controlSize(.small)
            }
            Text("Phone: WhatsApp → Settings → Linked devices → Link a device. This uses WhatsApp Web, which isn’t an official business API — WhatsApp can limit numbers that send a lot of automatic messages, so keep Autopilot for replies to people who wrote to you.")
                .font(zf(10.5)).foregroundColor(Ink.faint).fixedSize(horizontal: false, vertical: true)
        }
    }
}


/// Business → My business: a simple form. Saving it writes a clear brief Zuffi answers customers from.
struct BizDetailsForm: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var biz = ZuffiBusiness.shared
    @State private var f: [String: String] = (UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:]
    @State private var saved = false

    static let fields: [(key: String, label: String, hint: String, tall: Bool)] = [
        ("website", "Website or social page link", "https://yourbusiness.co.uk or your Instagram / Facebook page", false),
        ("address", "Address / area", "Shop 4, High Street, Maidstone ME14", false),
        ("phone", "Phone / WhatsApp", "Customers message this number", false),
        ("hours", "Opening hours", "Mon–Sat 9am–6pm, closed Sunday", false),
        ("services", "Services or products & prices", "One per line, e.g.\nHaircut £25\nColour from £85", true),
        ("payment", "Payment", "Cash, card, bank transfer, instalments…", false),
        ("booking", "How to book / buy", "Message us the service and a day; £10 deposit for colour", false),
        ("extra", "Delivery, parking, anything else", "Free parking behind the shop", false),
        ("faq", "Questions customers often ask (with answers)", "Do you do walk-ins? Yes, if a chair is free.", true),
    ]

    /// Must be filled before the Business page opens.
    /// Just the name plus a website link or the area — your agents research the rest (and fill in what they find).
    static let required: Set<String> = []
    static var isComplete: Bool {
        let f = (UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:]
        let name = (UserDefaults.standard.string(forKey: "zuffiBusinessName") ?? "").trimmingCharacters(in: .whitespaces)
        let link = (f["website"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines), area = (f["address"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && (!link.isEmpty || !area.isEmpty)
    }
    var missing: [String] {
        var m = biz.businessName.trimmingCharacters(in: .whitespaces).isEmpty ? ["Business name"] : []
        if (f["website"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (f["address"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { m.append("Website link or area") }
        return m
    }

    private var filled: Int { Self.fields.filter { !(f[$0.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Your business details", systemImage: "list.clipboard.fill").font(zf(13, .heavy))
                Spacer()
                Text("\(filled) of \(Self.fields.count) filled").font(zf(11, .semibold)).foregroundColor(filled >= 4 ? Biz.green : Ink.accent)
            }
            Text("Zuffi answers WhatsApp customers only from these details. The more you fill in, the better she answers.")
                .font(zf(11.5)).foregroundColor(Ink.muted)
            TextField("Business name *", text: Binding(get: { biz.businessName }, set: { biz.businessName = $0; UserDefaults.standard.set($0, forKey: "zuffiBusinessName") }))
                .textFieldStyle(.roundedBorder)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 10) {
                ForEach(Self.fields.filter { !$0.tall }, id: \.key) { fd in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fd.label + (Self.required.contains(fd.key) ? " *" : "")).font(zf(11, .semibold)).foregroundColor(Ink.muted)
                        TextField(fd.hint, text: binding(fd.key)).textFieldStyle(.roundedBorder)
                    }
                }
            }
            ForEach(Self.fields.filter { $0.tall && $0.key != "faq" }, id: \.key) { fd in
                VStack(alignment: .leading, spacing: 3) {
                    Text(fd.label + (Self.required.contains(fd.key) ? " *" : "")).font(zf(11, .semibold)).foregroundColor(Ink.muted)
                    TextEditor(text: binding(fd.key)).font(zf(12.5)).scrollContentBackground(.hidden)
                        .frame(minHeight: 70).padding(6).foregroundColor(Ink.text)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.panelHi))
                        .overlay(alignment: .topLeading) {
                            if (f[fd.key] ?? "").isEmpty { Text(fd.hint).font(zf(12)).foregroundColor(Ink.faint).padding(.horizontal, 11).padding(.vertical, 8).allowsHitTesting(false) }
                        }
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Biz.stroke))
                }
            }
            HStack {
                BizMainButton(title: saved ? "Saved ✓" : "Save — Zuffi will use this", icon: "checkmark") { save() }
                Spacer()
            }
            // How replies work, in one line — and the one thing that makes them smarter on a slow Mac.
            let cloud = ["groq-api-key", "gemini-api-key", "openai-api-key"].contains { !(KeychainStore.shared.get($0) ?? "").isEmpty }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bolt.fill").foregroundColor(Ink.accent)
                Text(cloud ? "Questions about hours, address, prices, payment, booking and your own Q&As get an instant answer from these details. Anything else goes to your AI."
                           : "Questions about hours, address, prices, payment, booking and your own Q&As get an instant answer from these details — no AI needed. For other questions, add a free Groq key: it runs online, so it's fast even on a slow Mac.")
                    .font(zf(11)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                if !cloud {
                    Spacer(minLength: 6)
                    BizSoftButton(title: "Add Groq key", icon: "key.fill") { NotificationCenter.default.post(name: .openFullSettings, object: nil) }
                }
            }
            .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Ink.accent.opacity(0.08)))
        }
    }

    private func binding(_ k: String) -> Binding<String> {
        Binding(get: { f[k] ?? "" }, set: { f[k] = $0; saved = false })
    }

    private func save() {
        // The FAQ is edited in its own box (questions & answers) — keep what's saved there.
        f["faq"] = ((UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:])["faq"] ?? f["faq"]
        UserDefaults.standard.set(f, forKey: "bizForm")
        Self.rebuildInfo()
        saved = true
        let wasDone = BizNav.shared.formDone
        BizNav.shared.formDone = Self.isComplete
        // First time (or a new link): the team researches the business by itself.
        let link = (f["website"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isComplete, !wasDone || link != (UserDefaults.standard.string(forKey: "bizResearchedLink") ?? "") {
            UserDefaults.standard.set(link, forKey: "bizResearchedLink")
            BusinessResearch.shared.start()
        }
        BizNav.shared.say(missing.isEmpty ? "Saved — Zuffi and your AI team will use these details." : "Saved. Still needed: " + missing.joined(separator: ", "))
    }

    /// Writes the form (and FAQ) into the business details every reply uses, keeping notes written by hand below.
    static func rebuildInfo() {
        let f = (UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:]
        let crm = ZuffiCRM.shared, biz = ZuffiBusiness.shared
        var lines: [String] = []
        if !biz.businessName.isEmpty { lines.append("Business: \(biz.businessName)") }
        for fd in Self.fields {
            let v = (f[fd.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { lines.append(fd.tall ? "\(fd.label):\n\(v)" : "\(fd.label): \(v)") }
        }
        let marker = "\n— More notes —\n"
        // keep anything written by hand below the form part (and drop the old example text)
        var rest = crm.businessInfo.components(separatedBy: marker).count > 1 ? crm.businessInfo.components(separatedBy: marker).last ?? "" : crm.businessInfo
        if rest.contains("[address]") || lines.isEmpty == false && rest.hasPrefix("Business:") { rest = "" }
        rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        crm.businessInfo = lines.joined(separator: "\n") + (rest.isEmpty ? "" : marker + rest)
    }
}


/// Business plan, first time: Zuffi takes the business details before the Business page opens.
struct BizSetupGate: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var biz = ZuffiBusiness.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZuffiMini(state: AppState.shared, height: 46).frame(width: 52, height: 52).background(Circle().fill(Ink.accent.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Welcome to Zuffi Business").font(zf(24, .bold))
                        Text("Just give your business name and a link (website, Instagram or Facebook) or your area. Your agents search Google, read your pages and your competitors', fill in what they find, and make a plan to grow. Add more details any time.")
                            .font(zf(12.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 10) {
                    let c = ZuffiCRM.allCountries.first { $0.code == crm.country }
                    Label("\(c?.flag ?? "🌍") \(c?.name ?? "Your country")", systemImage: "mappin.and.ellipse")
                    Text("·").foregroundColor(Ink.faint)
                    Text(crm.country == "PK" ? "Set up for estate agents" : crm.country == "GB" ? "Set up for UK small businesses" : "Pick your type of business")
                    Spacer()
                    BizTypeMenu()
                }
                .font(zf(12, .medium)).padding(12).zGlass(14)
                BizDetailsForm().padding(16).zGlass(18)
            }
            .padding(28).frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
    }
}


/// The questions customers ask, with your answers — WhatsApp replies use exactly these.
struct BizFAQEditor: View {
    struct QA: Identifiable, Hashable { var id = UUID(); var q: String; var a: String }
    @State private var items: [QA] = BizFAQEditor.load()
    @State private var newQ = ""
    @State private var newA = ""
    @State private var editing: UUID?

    static func load() -> [QA] {
        let text = ((UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:])["faq"] ?? ""
        var out: [QA] = []
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var i = 0
        while i < lines.count {
            let l = lines[i]
            if let q = l.firstIndex(of: "?"), l.index(after: q) < l.endIndex {
                out.append(QA(q: String(l[...q]).trimmingCharacters(in: .whitespaces), a: String(l[l.index(after: q)...]).trimmingCharacters(in: CharacterSet(charactersIn: " -–:"))))
            } else if l.hasSuffix("?"), i + 1 < lines.count, !lines[i + 1].contains("?") {
                out.append(QA(q: l, a: lines[i + 1])); i += 1
            } else if !l.isEmpty { out.append(QA(q: l, a: "")) }
            i += 1
        }
        return out
    }
    private func persist() {
        var f = (UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:]
        f["faq"] = items.filter { !$0.q.isEmpty && !$0.a.isEmpty }.map { ($0.q.hasSuffix("?") ? $0.q : $0.q + "?") + " " + $0.a }.joined(separator: "\n")
        UserDefaults.standard.set(f, forKey: "bizForm")
        BizDetailsForm.rebuildInfo()
        ZuffiTeam.shared.log("You", "Updated the WhatsApp FAQ", "\(items.count) questions")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("WhatsApp FAQ — your questions & answers", systemImage: "questionmark.bubble.fill").font(zf(13, .heavy))
                Spacer()
                Text("\(items.count) answer\(items.count == 1 ? "" : "s")").font(zf(11, .semibold)).foregroundColor(Ink.muted)
            }
            Text("Customers who ask one of these get your answer straight away, in their language style. Questions you haven't answered here are passed to you.")
                .font(zf(11.5)).foregroundColor(Ink.muted).fixedSize(horizontal: false, vertical: true)
            ForEach($items) { $it in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        if editing == it.id {
                            TextField("Question", text: $it.q).textFieldStyle(.roundedBorder)
                            TextField("Your answer", text: $it.a, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
                        } else {
                            Text(it.q).font(zf(12.5, .semibold))
                            Text(it.a.isEmpty ? "No answer yet — add one" : it.a).font(zf(12)).foregroundColor(it.a.isEmpty ? Color(hex: "#EF6B6B") : Ink.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    Button(editing == it.id ? "Done" : "Edit") { if editing == it.id { editing = nil; persist() } else { editing = it.id } }
                        .buttonStyle(.plain).font(zf(11, .semibold)).foregroundColor(Ink.accent)
                    Button { items.removeAll { $0.id == it.id }; persist() } label: { Image(systemName: "trash").font(zf(11)) }
                        .buttonStyle(.plain).foregroundColor(Ink.faint).help("Delete")
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Ink.panelHi))
            }
            VStack(alignment: .leading, spacing: 6) {
                TextField("New question, e.g. Do you take walk-ins?", text: $newQ).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("Your answer, e.g. Yes, if a chair is free — message us first.", text: $newA).textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let q = newQ.trimmingCharacters(in: .whitespaces), a = newA.trimmingCharacters(in: .whitespaces)
                        guard !q.isEmpty, !a.isEmpty else { BizNav.shared.say("Write the question and your answer."); return }
                        items.append(QA(q: q.hasSuffix("?") ? q : q + "?", a: a)); newQ = ""; newA = ""; persist()
                        BizNav.shared.say("Added to your FAQ")
                    }.buttonStyle(.borderedProminent).tint(Ink.accent)
                }
            }
            .padding(.top, 4)
        }
    }
}

// =====================================================================
// MARK: - Zuffi: one window for everything (Home · Team · Missions · Settings, + business pages for businesses)
//
// A frosted-glass window over your desktop: a top bar with the main tabs, a side menu, and the page. Personal users
// only see personal things; business, freelancer, one-person-company and creator modes also get the business pages.
// Settings live here as a page — no separate Settings window.
// =====================================================================

enum HubSection: Hashable {
    case home, team, office, library, missions, routines, settings, channels, look, automations, business, study, languages, tryon, biz(BizTab)
    var title: String {
        switch self {
        case .home: return "Home"
        case .team: return "Team"
        case .office: return "Office"
        case .library: return "Results"
        case .channels: return "Channels"
        case .study: return "Study"
        case .languages: return "Languages"
        case .tryon: return "Try-On"
        case .look: return "Pet & look"
        case .automations: return "Automations"
        case .business: return "Business"
        case .missions: return "Missions"
        case .routines: return "Routines"
        case .settings: return "Settings"
        case .biz(let t): return t.rawValue
        }
    }
}

@MainActor
final class ZuffiHub: ObservableObject {
    static let shared = ZuffiHub()
    @Published var section: HubSection = .home
    @Published var asking = false
    private var window: NSWindow?

    func show(_ s: HubSection? = nil) {
        if let s { section = s }
        // first time: the setup and "What's Zuffi for?" come here, not at start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MainActor.assumeIsolated { SetupWizard.shared.showIfFirstRun(); ZuffiModeWindow.shared.showIfNeeded() }
        }
        if case .biz = section { ZuffiCRM.shared.reload() }
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1250, height: 820),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Zuffi"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.backgroundColor = .clear
        w.contentMinSize = NSSize(width: 980, height: 640)
        w.contentView = NSHostingView(rootView: ZuffiDashboard())
        w.center()
        w.setFrameAutosaveName("ZuffiHubWindow")
        window = w
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var isOpen: Bool { window?.isVisible == true }

    /// Settings and Business open in this one window (Settings can switch back to the old separate windows).
    static var oneWindow: Bool { UserDefaults.standard.object(forKey: "hubOneWindow") as? Bool ?? true }

    /// Business pages are shown only when Zuffi is set up for work (business, freelancer, one-person company, creator).
    var showsBusiness: Bool { !ZuffiPlan.shared.isPersonal }
}

/// One business page, on its own.
struct BizPageView: View {
    let tab: BizTab
    var body: some View {
        switch tab {
        case .today: BizTodayView()
        case .inbox: BizInboxView()
        case .aiTeam: BizAITeamView()
        case .reports: BizReportsView()
        case .contacts: BizContactsView()
        case .sources: BizDataSourcesView()
        case .pipeline: BizPipelineView()
        case .records: BizRecordsView()
        case .properties: BizPropertiesView()
        case .money: BizMoneyView()
        case .business: BizBusinessView()
        case .team: BizTeamView()
        case .automations: BizAutomationsView()
        case .connect: BizConnectView()
        case .learn: BizLearnView()
        }
    }
}

// The look of your dashboard code: frosted glass, Poppins, blue #3A6DF0, a light/dark switch.
@MainActor
enum HubFont {
    private static var done = false
    static func register() {
        guard !done else { return }; done = true
        for n in ["Poppins-Regular", "Poppins-Medium", "Poppins-SemiBold"] {
            if let u = Bundle.main.url(forResource: n, withExtension: "ttf", subdirectory: "agents/fonts") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        }
    }
    static func p(_ size: CGFloat, _ w: Font.Weight = .medium) -> Font {
        let name = w == .semibold || w == .bold ? "Poppins-SemiBold" : w == .regular ? "Poppins-Regular" : "Poppins-Medium"
        return NSFont(name: name, size: size) != nil ? .custom(name, size: size) : .system(size: size, weight: w)
    }
}

struct HubTheme {
    let light: Bool
    var app: Color { light ? Color.white.opacity(0.31) : Color(red: 16 / 255, green: 18 / 255, blue: 27 / 255).opacity(0.40) }
    var border: Color { light ? Color.white.opacity(0.35) : Color(red: 113 / 255, green: 119 / 255, blue: 144 / 255).opacity(0.25) }
    var text: Color { light ? Color(hex: "#3C3A3A") : Color(hex: "#F9FAFB") }
    var inactive: Color { light ? Color(hex: "#333333") : Color(red: 113 / 255, green: 119 / 255, blue: 144 / 255).opacity(0.78) }
    var hover: Color { light ? Color.white.opacity(0.35) : Color(red: 12 / 255, green: 15 / 255, blue: 25 / 255).opacity(0.30) }
    var title: Color { light ? Color(hex: "#3C3A3A") : Color(hex: "#999BA5") }
    var content: Color { Color(red: 146 / 255, green: 151 / 255, blue: 179 / 255).opacity(0.13) }
    var buttonInactive: Color { light ? Color(hex: "#3C3A3A") : Color(hex: "#F9FAFB").opacity(0.55) }
    var dropdown: Color { light ? Color(hex: "#F7F7F7") : Color(hex: "#21242D") }
    var popup: Color { light ? .white : Color(red: 22 / 255, green: 25 / 255, blue: 37 / 255) }
    var search: Color { light ? Color.white.opacity(0.31) : Color(hex: "#14162B") }
    static let blue = Color(hex: "#3A6DF0")
    static let green = Color(hex: "#3BF083")
}

enum HubPage: Hashable {
    case home, team, office, library, missions, routines, settings, biz(BizTab)
}

struct ZuffiHubView: View {
    @ObservedObject private var hub = ZuffiHub.shared
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var nav = BizNav.shared
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var plan = ZuffiPlan.shared
    @AppStorage("hubLight") private var light = false
    @State private var sub: [String: String] = [:]
    @State private var search = ""
    @State private var task = ""
    @State private var askBefore = true
    @State private var showNik = true
    @State private var menuFor: String?

    private var T: HubTheme { HubTheme(light: light) }
    private var agents: [TeamAgent] {
        let list = [ZuffiTeam.manager] + team.hiredAgents.filter { $0.id != ZuffiTeam.manager.id }
        return nav.formDone ? list : list.filter { $0.id == ZuffiTeam.manager.id || ZuffiTeam.isPersonal($0) }
    }
    private var bizTabs: [BizTab] {
        BizTab.allCases.filter { !ZuffiFocus.hiddenBizTabs.contains($0.rawValue) && ($0 != .properties || crm.isEstate) && ($0 != .team || crm.kind != .freelancer) && $0 != .aiTeam }
    }
    private var page: HubPage {
        switch hub.section {
        case .home: return .home
        case .team: return .team
        case .office: return .office
        case .library: return .library
        case .channels, .look, .automations, .business, .study, .languages, .tryon: return .settings
        case .missions: return .missions
        case .routines: return .routines
        case .settings: return .settings
        case .biz(let t): return .biz(t)
        }
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .fullScreenUI).ignoresSafeArea()
            (light ? LinearGradient(colors: [Color.white.opacity(0.72), Color.white.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                   : LinearGradient(colors: [Color(hex: "#0B0D16").opacity(0.35), Color(hex: "#0B0D16").opacity(0.35)], startPoint: .top, endPoint: .bottom)).ignoresSafeArea()
            VStack(spacing: 0) {
                header
                HStack(spacing: 0) {
                    leftSide
                    VStack(spacing: 0) {
                        mainHeader
                        if hub.section == .office {
                            AgentOfficeView(light: light).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
                        } else {
                            ScrollView { content.padding(.horizontal, 40).padding(.vertical, 20) }
                                .background(T.app)
                        }
                    }
                }
            }
            .background(T.app)
            if hub.asking { popup }
            VStack { Spacer(); HStack { Spacer(); darkLight } }.padding(.trailing, 30).padding(.bottom, 50)
        }
        .foregroundColor(T.text)
        .font(HubFont.p(15))
        .onAppear { HubFont.register() }
        .preferredColorScheme(light ? .light : .dark)
    }

    // MARK: header (window dots are the real ones, top-left)
    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 80, height: 1)
            HStack(spacing: 10) {
                LiveBunnyFace(size: 30)
                Text("Zuffi").font(HubFont.p(16, .semibold))
            }.padding(.trailing, 40)
            ForEach(topLinks, id: \.0) { l in
                Button { hub.section = l.1 } label: {
                    Text(l.0).font(HubFont.p(15)).foregroundColor(isTop(l.1) ? T.text : T.inactive)
                        .padding(.horizontal, 26).frame(height: 58)
                        .overlay(alignment: .bottom) { Rectangle().fill(isTop(l.1) ? T.text : .clear).frame(height: 2) }
                        .overlay(alignment: .topTrailing) { if l.2 { Circle().fill(HubTheme.blue).frame(width: 6, height: 6).offset(x: -16, y: 16) } }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundColor(T.inactive)
                TextField("Search", text: $search).textFieldStyle(.plain).font(HubFont.p(15))
                    .onSubmit { let q = search; search = ""; if !q.isEmpty { ZuffiChat.shared.open(prefill: q) } }
            }
            .padding(.horizontal, 16).frame(height: 40).frame(maxWidth: 400)
            .background(RoundedRectangle(cornerRadius: 4).fill(T.search))
            .padding(.leading, 16)
            Spacer(minLength: 16)
            HStack(spacing: 22) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "bell.fill").font(.system(size: 19)).foregroundColor(T.text)
                    if NotchInbox.shared.notes.count > 0 {
                        Text("\(min(9, NotchInbox.shared.notes.count))").font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
                            .frame(width: 16, height: 16).background(Circle().fill(HubTheme.blue)).offset(x: 6, y: -6)
                    }
                }
                .onTapGesture { NotificationCenter.default.post(name: .hookExpand, object: IslandView.overview) }
                .help("Notifications (opens the notch)")
                let initial = String(AssistantPrefs.displayName.prefix(1)).uppercased()
                Text(initial.isEmpty ? "Z" : initial).font(HubFont.p(13, .semibold)).foregroundColor(.white)
                    .frame(width: 32, height: 32).background(Circle().fill(HubTheme.blue))
                    .overlay(Circle().stroke(T.text, lineWidth: 2))
            }
            .padding(.leading, 40).padding(.trailing, 30)
        }
        .frame(height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(T.border).frame(height: 1) }
    }
    private var topLinks: [(String, HubSection, Bool)] {
        var l: [(String, HubSection, Bool)] = [("Home", .home, false), ("Team", .team, team.runs.contains { $0.status == "Working" }), ("Office", .office, false), ("Results", .library, false), ("Missions", .missions, false)]
        if hub.showsBusiness { l.append(("Business", .biz(bizTabs.first ?? .today), !NotchInbox.shared.notes.isEmpty)) }
        l.append(("Settings", .settings, false))
        return l
    }
    private func isTop(_ s: HubSection) -> Bool {
        if case .biz = s, case .biz = hub.section { return true }
        return s == hub.section
    }

    // MARK: left side
    private var leftSide: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                side("Zuffi") {
                    sideLink("square.grid.2x2.fill", "Home", .home)
                    sideLink("building.2.fill", "Agent Office", .office)
                    sideLink("tray.full.fill", "Results & chats", .library)
                    sideLink("flag.fill", "Missions", .missions, badge: team.runs.filter { $0.status == "Working" }.count)
                    sideLink("clock.fill", "Routines", .routines)
                    Button { ZuffiChat.shared.open() } label: { sideLabel("bubble.left.fill", "Chat", active: false) }.buttonStyle(.plain)
                }
                side("Your team") {
                    ForEach(Array(agents.prefix(7))) { a in
                        Button { hub.section = .team } label: {
                            HStack(spacing: 8) {
                                RobotFace(agent: a, size: 18)
                                Text(a.name).font(HubFont.p(14, .regular)).lineLimit(1)
                                Spacer(minLength: 4)
                                if team.status(a) == .working { Circle().fill(HubTheme.blue).frame(width: 6, height: 6) }
                            }
                            .padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if hub.showsBusiness {
                    side("Business") { ForEach(bizTabs) { t in sideLink(t.icon, t.rawValue, .biz(t)) } }
                }
                side("Settings") {
                    sideLink("hare.fill", "Pet & look", .settings, key: "Pet")
                    sideLink("rectangle.topthird.inset.filled", "Notch", .settings, key: "Notch")
                    sideLink("person.3.fill", "Agents", .settings, key: "Agents")
                    sideLink("lock.fill", "Privacy & voice", .settings, key: "Privacy")
                    sideLink("slider.horizontal.3", "More settings", .settings, key: "More")
                }
            }
            .padding(26)
        }
        .frame(width: 240)
        .overlay(alignment: .trailing) { Rectangle().fill(T.border).frame(width: 1) }
    }
    private func side<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).foregroundColor(T.inactive).padding(.bottom, 14)
            c()
        }
    }
    private func sideLink(_ icon: String, _ label: String, _ s: HubSection, badge: Int = 0, key: String? = nil) -> some View {
        let active = hub.section == s && (key == nil || subFor(s) == key)
        return Button {
            hub.section = s
            if let key { sub[subKey(s)] = key }
        } label: { sideLabel(icon, label, active: active, badge: badge) }.buttonStyle(.plain)
    }
    private func sideLabel(_ icon: String, _ label: String, active: Bool, badge: Int = 0) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).frame(width: 16)
            Text(label).font(HubFont.p(14, .regular)).lineLimit(1)
            Spacer(minLength: 4)
            if badge > 0 {
                Text("\(badge)").font(.system(size: 11, weight: .semibold)).foregroundColor(.white).frame(width: 18, height: 18).background(Circle().fill(HubTheme.blue))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(active ? T.hover : .clear))
        .contentShape(Rectangle())
    }

    // MARK: main header (page name + its own links)
    private func subKey(_ s: HubSection) -> String { if case .biz = s { return "biz" }; return "\(s)" }
    private func subs(_ s: HubSection) -> [String] {
        switch s {
        case .home: return ["Overview", "Routines", "Activity"]
        case .team: return ["All", "Working", "Hire"]
        case .missions: return ["Running", "Done"]
        case .library: return ["Agent results", "Chats"]
        case .settings: return ["Pet", "Notch", "Agents", "Privacy", "More"]
        default: return []
        }
    }
    private func subFor(_ s: HubSection) -> String { sub[subKey(s)] ?? subs(s).first ?? "" }
    private var pageName: String {
        switch hub.section {
        case .home: return "Home"
        case .team: return "Your team"
        case .office: return "Agent Office"
        case .library: return "Results & chats"
        case .channels, .look, .automations, .business, .study, .languages, .tryon: return hub.section.title
        case .missions: return "Missions"
        case .routines: return "Routines"
        case .settings: return "Settings"
        case .biz(let t): return t.rawValue
        }
    }
    private var mainHeader: some View {
        HStack(spacing: 0) {
            Text(pageName).padding(.horizontal, 30).frame(minWidth: 180, alignment: .leading)
            HStack(spacing: 0) {
                ForEach(subs(hub.section), id: \.self) { n in
                    Button { sub[subKey(hub.section)] = n } label: {
                        Text(n).foregroundColor(subFor(hub.section) == n ? T.text : T.inactive)
                            .padding(.horizontal, 24).frame(height: 58)
                            .overlay(alignment: .bottom) { Rectangle().fill(subFor(hub.section) == n ? T.text : .clear).frame(height: 2) }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .padding(.leading, 60)
            Spacer()
        }
        .frame(height: 58)
        .overlay(alignment: .bottom) { Rectangle().fill(T.border).frame(height: 1) }
    }

    // MARK: pages
    @ViewBuilder private var content: some View {
        switch hub.section {
        case .home:
            VStack(alignment: .leading, spacing: 0) {
                banner
                switch subFor(.home) {
                case "Routines": NikPlanView(light: light); routinesSection
                case "Activity": activitySection
                default: BusinessReportCard(light: light); NikPlanView(light: light); teamSection("Your team", agents)
                }
            }
        case .team:
            VStack(alignment: .leading, spacing: 0) {
                switch subFor(.team) {
                case "Working": teamSection("Working now", agents.filter { team.status($0) == .working }, emptyText: "Nobody is working right now. Give Nik a task from Home.")
                case "Hire": hireSection
                default: teamSection("Everyone on your team", agents)
                }
            }
        case .office: EmptyView()
        case .library: LibraryView(light: light, chats: subFor(.library) == "Chats")
        case .channels, .look, .automations, .business, .study, .languages, .tryon: EmptyView()
        case .missions: activitySection
        case .routines: routinesSection
        case .settings: settingsPage
        case .biz(let t):
            Group { if !nav.formDone { BizSetupGate().foregroundColor(Ink.text) } else { BizPageView(tab: t).foregroundColor(Ink.text).frame(minHeight: 600) } }.id("\(light)")
        }
    }

    // the colourful banner (content-wrapper-header)
    private var banner: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    LiveBunnyFace(size: 30).background(Circle().fill(Color.white.opacity(0.9)).frame(width: 32, height: 32))
                    Text("Nik, your manager").font(HubFont.p(17))
                }
                Text("Give Nik any job. He picks the right agent, shows you every step, and asks you before anything is paid, sent or posted.")
                    .font(HubFont.p(14, .regular)).foregroundColor(Color(hex: "#EBECEC")).lineSpacing(6).padding(.top, 16)
                    .fixedSize(horizontal: false, vertical: true)
                Button { hub.asking = true } label: {
                    Text("Give a task").font(HubFont.p(15)).foregroundColor(.white).padding(.horizontal, 26).padding(.vertical, 8)
                        .background(Capsule().fill(HubTheme.blue))
                }.buttonStyle(.plain).padding(.top, 16)
            }
            .frame(maxWidth: 350, alignment: .leading)
            .foregroundColor(.white)
            Spacer()
            RealAuroraHead(width: 118).frame(width: 186, height: 186)
        }
        .padding(.horizontal, 40).padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: ["#CF4AF3", "#E73BD7", "#F631BC", "#FD31A2", "#FF3A8B", "#FF4B78", "#FF5E68", "#FF705C", "#FF8C51", "#FFAA49", "#FFC848", "#FFE652"].map { Color(hex: $0) }, startPoint: .bottomLeading, endPoint: .topTrailing)))
    }

    private func sectionTitle(_ t: String) -> some View { Text(t).foregroundColor(T.title).padding(.bottom, 14).padding(.top, 30) }

    // a list like "Installed": one agent per row
    private func teamSection(_ title: String, _ list: [TeamAgent], emptyText: String = "No agents yet — hire one from Team → Hire.") -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
            VStack(spacing: 0) {
                if list.isEmpty { Text(emptyText).font(HubFont.p(14, .regular)).foregroundColor(T.inactive).padding(18).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                    agentRow(a).overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.app))
        }
    }
    private func agentRow(_ a: TeamAgent) -> some View {
        let st = team.status(a), working = st == .working
        let run = team.runs.first { $0.agent == a.id }
        let f = AgentField.of(a)
        return HStack(spacing: 0) {
            HStack(spacing: 16) {
                RobotFace(agent: a, size: 28).overlay(RoundedRectangle(cornerRadius: 8).stroke(f.color, lineWidth: 1))
                Text(AgentEdits.name(a)).font(HubFont.p(16)).lineLimit(1)
            }.frame(width: 230, alignment: .leading)
            Text(working ? (run?.steps.last?.text ?? run?.task ?? "Working…") : a.description)
                .font(HubFont.p(13, .regular)).foregroundColor(T.inactive).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 16)
            HStack(spacing: 14) {
                Circle().fill(working ? HubTheme.blue : st == .active ? HubTheme.green : ZuffiTeam.color(st)).frame(width: 6, height: 6)
                Text(working ? "Working" : st == .active ? "Ready" : st.rawValue).font(HubFont.p(15))
            }.frame(width: 140, alignment: .leading)
            HStack(spacing: 0) {
                Button {
                    if working { MissionControl.shared.show() } else { task = "\(a.name), "; hub.asking = true }
                } label: { statusButton(working ? "Watch" : "Give task", filled: !working) }.buttonStyle(.plain)
                Menu {
                    Button("Give a task") { task = "\(a.name), "; hub.asking = true }
                    Button("Chat with \(a.name)") { team.use(a); ZuffiChat.shared.open() }
                    Button("Edit agent…") { AgentEditor.open(a) }
                    Button(team.paused.contains(a.id) ? "Resume" : "Pause") { if team.paused.contains(a.id) { team.paused.remove(a.id) } else { team.paused.insert(a.id) } }
                    if team.hired.contains(a.id) { Button("Remove from team") { team.fire(a) } }
                } label: { dots }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 40)
            }
            .frame(width: 187, alignment: .trailing)
        }
        .padding(.horizontal, 18).padding(.vertical, 10).frame(minHeight: 56)
    }
    private var dots: some View {
        HStack(spacing: 2) { ForEach(0..<3, id: \.self) { _ in Circle().fill(T.buttonInactive).frame(width: 5, height: 5) } }.padding(.horizontal, 10)
    }
    private func statusButton(_ t: String, filled: Bool) -> some View {
        Text(t).font(HubFont.p(15)).foregroundColor(filled ? .white : T.buttonInactive)
            .padding(.horizontal, 24).padding(.vertical, 6)
            .background(Capsule().fill(filled ? HubTheme.blue : .clear))
            .overlay(Capsule().stroke(filled ? .clear : T.buttonInactive, lineWidth: 1))
    }

    // cards like "Apps in your plan": routines
    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Routines")
            if team.jobs.isEmpty {
                Text("No routines yet. Hiring an agent adds its everyday job — like a morning brief or a weekly report.")
                    .font(HubFont.p(14, .regular)).foregroundColor(T.inactive).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], spacing: 20) {
                    ForEach(team.jobs) { j in routineCard(j) }
                }
            }
        }
    }
    private func routineCard(_ j: TeamJob) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let a = team.agent(j.agent) { RobotFace(agent: a, size: 28) }
                Text(j.title).font(HubFont.p(16)).lineLimit(1)
            }
            Text(j.task).font(HubFont.p(14, .regular)).lineSpacing(5).lineLimit(3)
                .padding(.top, 20).padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) { Rectangle().fill(T.border).frame(height: 1) }
            HStack {
                Text(String(format: "%02d:%02d", j.hour, j.minute) + (j.weekday == nil ? " · daily" : " · weekly")).font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                Spacer()
                Button { Task { await ZuffiTeam.shared.runJob(j.id) } } label: { statusButton("Run now", filled: true) }.buttonStyle(.plain)
            }.padding(.top, 16)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.app))
    }

    private var activitySection: some View {
        let done = subFor(.missions) == "Done"
        let runs = team.runs.filter { hub.section == .missions ? (done ? $0.status != "Working" : $0.status == "Working") : true }.prefix(30)
        return VStack(alignment: .leading, spacing: 0) {
            sectionTitle(hub.section == .missions ? (done ? "Finished" : "Running now") : "Recent work")
            VStack(spacing: 0) {
                if runs.isEmpty { Text(done ? "Nothing finished yet." : "Nothing running. Give Nik a task.").font(HubFont.p(14, .regular)).foregroundColor(T.inactive).padding(18).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(Array(runs.enumerated()), id: \.element.id) { i, r in
                    HStack(spacing: 16) {
                        if let a = team.agent(r.agent) { RobotFace(agent: a, size: 28) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(team.agent(r.agent)?.name ?? "Agent").font(HubFont.p(15))
                            Text(r.task).font(HubFont.p(13, .regular)).foregroundColor(T.inactive).lineLimit(1)
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Circle().fill(r.status == "Working" ? HubTheme.blue : r.status == "Done" ? HubTheme.green : Color(hex: "#EF6B6B")).frame(width: 6, height: 6)
                            Text(r.status).font(HubFont.p(14))
                        }.frame(width: 130, alignment: .leading)
                        Text(r.started.formatted(date: .omitted, time: .shortened)).font(HubFont.p(13, .regular)).foregroundColor(T.inactive).frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
        }
    }

    private var hireSection: some View {
        let options = ZuffiTeam.builtins.filter { !team.hired.contains($0.id) && ((hub.showsBusiness && nav.formDone) || ZuffiTeam.personalTeam.contains($0.id)) }
        // Zuffi's picks for you: what it found in your business first, then the agents that fit your kind of work
        var picks = team.suggestions.map(\.agent)
        if hub.showsBusiness && nav.formDone { picks += ZuffiTeam.businessTeam + ["finance-financial-analyst", "zuffi-bookings", "zuffi-crm"] }
        picks += ZuffiTeam.personalTeam
        var seen = Set<String>()
        let suggested = picks.filter { seen.insert($0).inserted }.compactMap { id in options.first { $0.id == id } }.prefix(5)
        let rest = options.filter { a in !suggested.contains { $0.id == a.id } }
        return VStack(alignment: .leading, spacing: 24) {
            if !suggested.isEmpty {
                teamListPlain("Zuffi suggests for you", Array(suggested)) { a in
                    Button { team.hire(a, why: "Suggested by Zuffi") } label: { statusButton("Hire", filled: true) }.buttonStyle(.plain)
                }
            }
            teamListPlain("More agents you can add", rest) { a in
                Button { team.hire(a) } label: { statusButton("Hire", filled: false) }.buttonStyle(.plain)
            }
        }
    }
    private func teamListPlain<B: View>(_ title: String, _ list: [TeamAgent], @ViewBuilder button: @escaping (TeamAgent) -> B) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
            VStack(spacing: 0) {
                if list.isEmpty { Text("Everyone is already on your team.").font(HubFont.p(14, .regular)).foregroundColor(T.inactive).padding(18).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                    HStack(spacing: 16) {
                        RobotFace(agent: a, size: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(AgentEdits.name(a)).font(HubFont.p(16))
                            Text(a.description).font(HubFont.p(13, .regular)).foregroundColor(T.inactive).lineLimit(2)
                        }
                        Spacer()
                        button(a)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
        }
    }

    // MARK: Settings (inside the dashboard)
    @ViewBuilder private var settingsPage: some View {
        switch subFor(.settings) {
        case "Notch":
            settingsList("Notch", [
                toggleRow("rectangle.topthird.inset.filled", "New glass notch", "The wide notch with your agents and notifications", key: "notchWide", def: true),
                toggleRow("rectangle.connected.to.line.below", "Show Nik's window for tasks", "Watch Nik hand out the work", key: "missionWindow", def: true),
                toggleRow("hand.wave.fill", "Say hi when Zuffi starts", "Only the notch, nothing else pops up", key: "helloOnOpen", def: true),
            ])
        case "Agents":
            settingsList("Agents", [
                fixedRow("person.3.sequence.fill", "Agents work in the Agent Office", "They never cover your screen — watch them in their tab"),
                fixedRow("checkmark.shield.fill", "Ask me before paying, sending or posting", "Always on, for your safety"),
                fixedRow("globe", "Agents use websites in their own window", "Your mouse and browser stay free"),
                toggleRow("arrow.triangle.2.circlepath", "Backup page readers", "When a page won't open, agents may read it through Jina Reader or Exa (they see the page address or search words)", key: "reachBackup", def: true),
            ])
            ReachSitesView(light: light).padding(.top, 24)
        case "Privacy":
            settingsList("Privacy & voice", [
                fixedRow("lock.fill", "Your chats stay on this Mac", "Zuffi doesn't keep what you ask on its servers"),
                actionRow("mic.fill", "Microphone and wake word", "Talk to Zuffi with “Hey Zuffi”", "Open") { NotificationCenter.default.post(name: .openFullSettings, object: nil) },
            ])
        case "More":
            VStack(alignment: .leading, spacing: 0) {
                sectionTitle("More settings")
                SettingsView().frame(minHeight: 620).clipShape(RoundedRectangle(cornerRadius: 14))
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                settingsList("Pet", [
                    actionRow("hare.fill", "Aurora on screen", PetController.shared.isShown ? "She's on your screen" : "She's hidden", PetController.shared.isShown ? "Hide" : "Show") { PetController.shared.toggle() },
                    toggleRow("bell.and.waves.left.and.right", "She brings reminders", "She comes to the front and holds them up", key: "petReminders", def: true),
                    toggleRow("eye.slash.fill", "Never show the pet", "Reminders come to the notch instead", key: "petNever", def: false),
                ])
                sectionTitle("Aurora's colour")
                AuroraColorPicker().padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
            }
        }
    }
    private struct SRow: Identifiable { let id = UUID(); let view: AnyView }
    private func settingsList(_ title: String, _ rows: [SRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle(title)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                    r.view.overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
        }
    }
    private func rowShell<R: View>(_ icon: String, _ title: String, _ sub: String, @ViewBuilder right: () -> R) -> SRow {
        SRow(view: AnyView(
            HStack(spacing: 16) {
                Image(systemName: icon).font(.system(size: 13)).foregroundColor(HubTheme.blue)
                    .frame(width: 28, height: 28).overlay(RoundedRectangle(cornerRadius: 6).stroke(HubTheme.blue.opacity(0.6)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(HubFont.p(15))
                    Text(sub).font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
                }
                Spacer()
                right()
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        ))
    }
    private func toggleRow(_ icon: String, _ title: String, _ sub: String, key: String, def: Bool) -> SRow {
        rowShell(icon, title, sub) {
            Toggle("", isOn: Binding(get: { UserDefaults.standard.object(forKey: key) as? Bool ?? def }, set: { UserDefaults.standard.set($0, forKey: key); if key == "petNever", $0 { PetController.shared.hide() } }))
                .toggleStyle(.switch).labelsHidden().tint(HubTheme.blue)
        }
    }
    private func fixedRow(_ icon: String, _ title: String, _ sub: String) -> SRow {
        rowShell(icon, title, sub) { Image(systemName: "checkmark.circle.fill").foregroundColor(HubTheme.green) }
    }
    private func actionRow(_ icon: String, _ title: String, _ sub: String, _ button: String, _ go: @escaping () -> Void) -> SRow {
        rowShell(icon, title, sub) { Button(action: go) { statusButton(button, filled: false) }.buttonStyle(.plain) }
    }

    // MARK: pop-up: give Nik a task
    private var popup: some View {
        ZStack {
            Color(red: 36 / 255, green: 39 / 255, blue: 59 / 255).opacity(0.8).ignoresSafeArea().onTapGesture { hub.asking = false }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Give Nik a task").font(HubFont.p(16))
                    Spacer()
                    Button { hub.asking = false } label: { Image(systemName: "xmark.circle").font(.system(size: 22)) }.buttonStyle(.plain)
                }
                .padding(.bottom, 20).overlay(alignment: .bottom) { Rectangle().fill(T.border).frame(height: 1) }
                Text("Say it in your own words. Nik splits it into jobs and gives each one to the right agent. The answer shows in Nik's window, not in the chat.")
                    .font(HubFont.p(14, .regular)).lineSpacing(7).padding(.vertical, 20).fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $task).font(HubFont.p(14, .regular)).scrollContentBackground(.hidden)
                    .padding(10).frame(height: 90)
                    .background(RoundedRectangle(cornerRadius: 6).fill(T.search))
                checkbox("Ask me before paying, sending or posting", $askBefore, locked: true).padding(.top, 20)
                checkbox("Show me Nik's window while they work", $showNik).padding(.top, 14).padding(.bottom, 30)
                HStack(spacing: 8) {
                    Spacer()
                    Button { hub.asking = false } label: { statusButton("Cancel", filled: false) }.buttonStyle(.plain)
                    Button { start() } label: { statusButton("Start", filled: true) }.buttonStyle(.plain)
                        .disabled(task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 40).padding(.vertical, 30).frame(width: 500)
            .background(RoundedRectangle(cornerRadius: 6).fill(T.popup))
            .shadow(color: .black.opacity(0.4), radius: 30, y: 6)
        }
    }
    private func checkbox(_ label: String, _ on: Binding<Bool>, locked: Bool = false) -> some View {
        Button { if !locked { on.wrappedValue.toggle() } } label: {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(on.wrappedValue ? HubTheme.blue : .clear).frame(width: 15, height: 15)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(on.wrappedValue ? HubTheme.blue : T.text, lineWidth: 1))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundColor(.white).opacity(on.wrappedValue ? 1 : 0))
                Text(label).font(HubFont.p(14, .regular))
            }
        }.buttonStyle(.plain)
    }
    private func start() {
        let q = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        hub.asking = false; task = ""
        UserDefaults.standard.set(showNik, forKey: "missionWindow")
        MissionControl.shared.assign(q)
    }

    // MARK: the round light/dark button
    private var darkLight: some View {
        Button { light.toggle() } label: {
            Image(systemName: "moon.fill").font(.system(size: 20)).foregroundColor(light ? T.text : Color(hex: "#FFCE45"))
                .frame(width: 40, height: 40).background(Circle().fill(T.dropdown))
                .shadow(color: .black.opacity(0.2), radius: 8, x: -1, y: 3)
        }.buttonStyle(.plain).help("Light or dark")
    }
}

// =====================================================================
// MARK: - The new dashboard: seven simple pages
//   Dashboard · Routines · Channels · Business · Pet & look · Automations · Settings
// =====================================================================

enum DashTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", study = "Learn", languages = "Languages", tryon = "Try-On", routines = "Routines", channels = "Channels", business = "Business", look = "Pet & look", automations = "Automations", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .study: return "graduationcap.fill"
        case .languages: return "character.bubble.fill"
        case .tryon: return "hand.raised.fingers.spread.fill"
        case .routines: return "clock.arrow.circlepath"
        case .channels: return "bubble.left.and.text.bubble.right.fill"
        case .business: return "storefront.fill"
        case .look: return "hare.fill"
        case .automations: return "bolt.fill"
        case .settings: return "gearshape.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .dashboard: return ZuffiFocus.agents ? "Talk to your agents, watch them work and see everything they did" : "Ask Zuffi anything and find all your chats"
        case .study: return "Chat with Nik, your teacher · study your notes · 50 languages · your progress"
        case .languages: return "Learn English, Spanish, French, German or Arabic with a senior teacher who talks with you"
        case .tryon: return "See nail designs on your own hand and a new hair colour — live on your camera"
        case .routines: return "Your agents' daily pipeline and the end-of-day report"
        case .channels: return "Hand your social apps to agents — one inbox for every message"
        case .business: return "Your agents use these details for everything they do"
        case .look: return "Aurora, the notch and how Zuffi looks"
        case .automations: return "Switch on what your agents run for you"
        case .settings: return "Your profile, AI models, voice and privacy"
        }
    }
    var section: HubSection {
        switch self {
        case .dashboard: return .home
        case .study: return .study
        case .languages: return .languages
        case .tryon: return .tryon
        case .routines: return .routines
        case .channels: return .channels
        case .business: return .business
        case .look: return .look
        case .automations: return .automations
        case .settings: return .settings
        }
    }
    static func of(_ s: HubSection) -> DashTab {
        switch s {
        case .routines: return .routines
        case .study: return .study
        case .languages: return .languages
        case .tryon: return .tryon
        case .channels: return .channels
        case .business, .biz: return .business
        case .look: return .look
        case .automations: return .automations
        case .settings: return .settings
        default: return .dashboard
        }
    }
}

/// Card used across the dashboard pages.
struct DashCard<C: View>: View {
    var title: String = ""
    var sub: String = ""
    var light: Bool
    @ViewBuilder var content: () -> C
    var body: some View {
        let T = HubTheme(light: light)
        VStack(alignment: .leading, spacing: 14) {
            if !title.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(HubFont.p(17, .semibold)).foregroundColor(T.text)
                    if !sub.isEmpty { Text(sub).font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive).fixedSize(horizontal: false, vertical: true) }
                }
            }
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(light ? Color.white.opacity(0.62) : Color(hex: "#151823").opacity(0.78)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(T.border))
        .shadow(color: .black.opacity(light ? 0.06 : 0.25), radius: 18, y: 8)
    }
}

struct DashButton: View {
    let title: String
    var icon: String? = nil
    var filled = true
    var light = false
    let go: () -> Void
    var body: some View {
        Button(action: go) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(HubFont.p(13))
            }
            .foregroundColor(filled ? .white : HubTheme(light: light).text)
            .padding(.horizontal, 16).frame(height: 34)
            .background(Capsule().fill(filled ? HubTheme.blue : Color.clear))
            .overlay(Capsule().stroke(filled ? Color.clear : HubTheme(light: light).border))
            .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

struct ZuffiDashboard: View {
    @ObservedObject private var hub = ZuffiHub.shared
    @ObservedObject private var plan = ZuffiPlan.shared
    @AppStorage("hubLight") private var light = false
    private var tab: DashTab { DashTab.of(hub.section) }
    private var T: HubTheme { HubTheme(light: light) }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .fullScreenUI).ignoresSafeArea()
            LinearGradient(colors: light ? [Color(hex: "#F3F4FA").opacity(0.94), Color(hex: "#E8EAF4").opacity(0.9)] : [Color(hex: "#0B0C10").opacity(0.92), Color(hex: "#1A1D28").opacity(0.9)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                VStack(spacing: 0) {
                    topbar
                    if tab == .dashboard {
                        ScrollView { DashHomePage(light: light).padding(.horizontal, 32).padding(.vertical, 24) }
                    } else {
                        ScrollView { page.padding(.horizontal, 32).padding(.vertical, 24).frame(maxWidth: 1100, alignment: .leading) }
                    }
                }
            }
        }
        .foregroundColor(T.text)
        .font(HubFont.p(14, .regular))
        .preferredColorScheme(light ? .light : .dark)
        .tint(ZInk.accent)
        .onAppear {
            HubFont.register()
            if ZuffiFocus.agents { SocialHub.shared.start(); DailyReport.shared.start(); OfficeModel.shared.ensure() }
            else if ![.home, .look, .settings].contains(hub.section) && !(ZuffiFocus.learn && [.study, .languages].contains(hub.section)) { hub.section = .home }
        }
    }

    @ViewBuilder private var page: some View {
        switch tab {
        case .dashboard: DashHomePage(light: light)
        case .study: StudyPage(light: light)
        case .languages: LanguagePage(light: light)
        case .tryon: TryOnPage(light: light)
        case .routines: DashRoutinesPage(light: light)
        case .channels: DashChannelsPage(light: light)
        case .business: DashBusinessPage(light: light)
        case .look: DashLookPage(light: light)
        case .automations: DashAutomationsPage(light: light)
        case .settings: DashSettingsPage(light: light)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                LiveBunnyFace(size: 34)
                Text("Zuffi").font(HubFont.p(20, .semibold))
            }
            .padding(.leading, 18).padding(.top, 46).padding(.bottom, 26)
            ForEach(DashTab.allCases.filter { ZuffiFocus.agents || [.dashboard, .look, .settings].contains($0) || ($0 == .study && ZuffiFocus.learn) }) { t in
                Button { withAnimation(.easeOut(duration: 0.15)) { hub.section = t.section } } label: {
                    HStack(spacing: 12) {
                        Image(systemName: t.icon).font(.system(size: 14, weight: .semibold)).frame(width: 22)
                        Text(t.rawValue).font(HubFont.p(14, tab == t ? .semibold : .medium))
                        Spacer()
                    }
                    .foregroundColor(tab == t ? .white : T.text.opacity(0.78))
                    .padding(.horizontal, 14).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tab == t ? AnyShapeStyle(ZInk.accentGradient) : AnyShapeStyle(Color.clear)))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12)
            }
            Spacer()
            if false { Button { light.toggle() } label: {
                HStack(spacing: 10) {
                    Image(systemName: light ? "moon.fill" : "sun.max.fill")
                    Text(light ? "Dark look" : "Light look").font(HubFont.p(13))
                    Spacer()
                }.foregroundColor(T.inactive).padding(.horizontal, 26).frame(height: 40).contentShape(Rectangle())
            }.buttonStyle(.plain) }
            Button { UserDefaults.standard.set("Profile", forKey: "settingsTab"); hub.section = .settings } label: {
                HStack(spacing: 10) {
                    ProfileAvatar(size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(plan.profile["name"]?.isEmpty == false ? plan.profile["name"]! : "Your profile").font(HubFont.p(13, .semibold)).foregroundColor(T.text).lineLimit(1)
                        Text("Profile & settings").font(HubFont.p(11, .regular)).foregroundColor(T.inactive)
                    }
                    Spacer()
                }
                .padding(10).background(RoundedRectangle(cornerRadius: 12).fill(T.content)).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 16)
        }
        .frame(width: 230)
        .background(light ? Color.white.opacity(0.45) : Color.black.opacity(0.28))
        .overlay(alignment: .trailing) { Rectangle().fill(T.border).frame(width: 1) }
    }

    private var topbar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tab.rawValue).font(HubFont.p(24, .semibold))
                Text(tab.subtitle).font(HubFont.p(13, .regular)).foregroundColor(T.inactive)
            }
            Spacer()
            if ZuffiFocus.agents { DashButton(title: "Give Nik a task", icon: "plus", light: light) { hub.section = .home; ZuffiChat.shared.who = .nik } }
        }
        .padding(.horizontal, 32).padding(.top, 40).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(T.border).frame(height: 1) }
    }
}

// MARK: 1 · Dashboard — chat with an agent, the live office, activity, the team

struct DashHomePage: View {
    var light: Bool
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var chat = ZuffiChat.shared
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var mc = MissionControl.shared
    @State private var text = ""
    @State private var showLibrary = false
    @State private var libraryChats = false
    @State private var showHire = false
    private var T: HubTheme { HubTheme(light: light) }

    private var people: [TeamAgent] {
        var l = ZuffiTeam.personalTeam.compactMap { team.agent($0) }
        for a in team.hiredAgents where !l.contains(a) { l.append(a) }
        return l
    }
    private var whoAgent: TeamAgent? {
        switch chat.who { case .zuffi: return nil; case .nik: return ZuffiTeam.manager; case .agent(let id): return team.agent(id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !ZuffiFocus.agents { YourDayCards(light: light) }
            if ZuffiFocus.agents {
            chatCard
            DashCard(title: "Agent Office", sub: mc.question.isEmpty ? "Your agents at their desks. When they work, they get up, go desk to desk and bring the result to Nik." : "Working on: \(mc.question)", light: light) {
                AgentOfficeView(light: light, showTaskBar: false)
                    .frame(height: 440)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(alignment: .top, spacing: 22) {
                activityCard
                teamCard.frame(width: 360)
            }
            }
        }
        .sheet(isPresented: $showLibrary) {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(libraryChats ? "Chats" : "Agent results").font(HubFont.p(18, .semibold)); Spacer(); Button("Done") { showLibrary = false }.keyboardShortcut(.cancelAction) }
                Picker("", selection: $libraryChats) { Text("Agent results").tag(false); Text("Chats").tag(true) }.pickerStyle(.segmented).frame(width: 260)
                ScrollView { LibraryView(light: light, chats: libraryChats) }
            }
            .padding(24).frame(width: 1000, height: 700)
        }
        .sheet(isPresented: $showHire) { DashHireSheet(light: light) { showHire = false } }
    }

    private var chatCard: some View {
        DashCard(light: light) {
            HStack(spacing: 10) {
                if ZuffiFocus.agents {
                Menu {
                    Button("Zuffi — everyday help") { chat.who = .zuffi }
                    Button("Nik — your manager") { chat.who = .nik }
                    Divider()
                    ForEach(people, id: \.id) { a in Button(AgentEdits.name(a)) { chat.who = .agent(a.id) } }
                } label: {
                    HStack(spacing: 8) {
                        if let a = whoAgent { RobotFace(agent: a, size: 22) } else { LiveBunnyFace(size: 24) }
                        Text(chat.who == .zuffi ? "Zuffi" : whoAgent.map(AgentEdits.name) ?? "Agent").font(HubFont.p(13))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(Capsule().fill(T.content))
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble").foregroundColor(T.inactive)
                    TextField(ZuffiFocus.agents ? "Ask or give a task — e.g. find the 3 best cheap hotels in Dubai for March" : "Ask Zuffi anything — e.g. explain photosynthesis simply", text: $text)
                        .textFieldStyle(.plain).font(HubFont.p(14, .regular)).onSubmit(send)
                }
                .padding(.horizontal, 14).frame(height: 42)
                .background(Capsule().fill(T.content))
                DashButton(title: "Send", icon: "paperplane.fill", light: light, go: send)
            }
            let recent = Array(app.chatHistory.suffix(6))
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(recent) { m in
                        let mine = m.role == .user
                        HStack(alignment: .top, spacing: 10) {
                            if mine { Spacer(minLength: 80) }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(mine ? "You" : chat.whoTitle).font(HubFont.p(11, .semibold)).foregroundColor(T.inactive)
                                    Text(m.at.formatted(date: .abbreviated, time: .shortened)).font(HubFont.p(10.5, .regular)).foregroundColor(T.inactive.opacity(0.8))
                                    if !mine {
                                        Button { ResultExport.copy(m.content) } label: { Image(systemName: "doc.on.doc").font(.system(size: 10)) }.buttonStyle(.plain).foregroundColor(T.inactive).help("Copy")
                                        Button { ResultExport.save("Zuffi answer", m.content, pdf: false) } label: { Image(systemName: "arrow.down.circle").font(.system(size: 10)) }.buttonStyle(.plain).foregroundColor(T.inactive).help("Download")
                                    }
                                }
                                if mine { Text(m.content).font(HubFont.p(14, .regular)).textSelection(.enabled) } else { ChatRichText(text: m.content) }
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(mine ? HubTheme.blue.opacity(0.22) : T.content))
                            if !mine { Spacer(minLength: 80) }
                        }
                    }
                    if app.stateOverride == .thinking {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("\(chat.whoTitle) is working on it…").font(HubFont.p(12, .regular)).foregroundColor(T.inactive) }
                    }
                }
            }
            HStack(spacing: 14) {
                Button { libraryChats = true; showLibrary = true } label: { Label("Chat history", systemImage: "clock").font(HubFont.p(12)) }.buttonStyle(.plain).foregroundColor(HubTheme.blue)
                if ZuffiFocus.agents { Button { libraryChats = false; showLibrary = true } label: { Label("All agent results", systemImage: "tray.full").font(HubFont.p(12)) }.buttonStyle(.plain).foregroundColor(HubTheme.blue) }
                Spacer()
                if !app.chatHistory.isEmpty { Button { app.newChat() } label: { Label("New chat", systemImage: "square.and.pencil").font(HubFont.p(12)) }.buttonStyle(.plain).foregroundColor(T.inactive) }
            }
        }
    }

    private func send() {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        text = ""
        chat.askInline(q)
    }

    private var activityCard: some View {
        DashCard(title: "Activity", sub: "Everything your agents did, newest first", light: light) {
            let runs = Array(team.runs.sorted { $0.started > $1.started }.prefix(12))
            if runs.isEmpty { Text("Nothing yet. Ask something above or give Nik a task.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
            VStack(spacing: 0) {
                ForEach(Array(runs.enumerated()), id: \.element.id) { i, r in
                    Button { libraryChats = false; showLibrary = true } label: {
                        HStack(spacing: 12) {
                            if let a = team.agent(r.agent) { RobotFace(agent: a, size: 24, working: r.status == "Working") }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.task).font(HubFont.p(13)).lineLimit(1)
                                Text("\(team.agent(r.agent).map(AgentEdits.name) ?? r.agent) · \(r.started.formatted(date: .abbreviated, time: .shortened))").font(HubFont.p(11, .regular)).foregroundColor(T.inactive)
                            }
                            Spacer()
                            DashStatus(status: r.status)
                        }
                        .padding(.vertical, 9).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    .overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                }
            }
        }
    }

    private var teamCard: some View {
        DashCard(title: "Your team", sub: "Nik leads. Hire more or edit any agent.", light: light) {
            let list = [ZuffiTeam.manager] + team.hiredAgents.filter { $0.id != ZuffiTeam.manager.id }
            VStack(spacing: 8) {
                ForEach(list, id: \.id) { a in
                    HStack(spacing: 12) {
                        RobotFace(agent: a, size: 28, working: team.status(a) == .working)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AgentEdits.name(a)).font(HubFont.p(13.5))
                            Text(team.status(a) == .working ? (team.runs.first { $0.agent == a.id }?.steps.last?.text ?? "Working…") : a.id == ZuffiTeam.manager.id ? "Your manager" : "Ready")
                                .font(HubFont.p(11, .regular)).foregroundColor(T.inactive).lineLimit(1)
                        }
                        Spacer()
                        Button { AgentEditor.open(a) } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.plain).foregroundColor(T.inactive).help("Edit")
                        Button { chat.who = a.id == ZuffiTeam.manager.id ? .nik : .agent(a.id) } label: { Image(systemName: "bubble.left") }.buttonStyle(.plain).foregroundColor(T.inactive).help("Chat")
                    }
                }
            }
            DashButton(title: "Hire agents", icon: "person.badge.plus", light: light) { showHire = true }
        }
    }
}

struct DashStatus: View {
    let status: String
    var body: some View {
        let c: Color = status == "Done" ? Color(hex: "#3DBE7E") : status == "Working" ? Color(hex: "#F5B963") : status == "Needs input" ? HubTheme.blue : Color(hex: "#EF6B6B")
        Text(status == "Needs input" ? "Asks you" : status).font(HubFont.p(11)).foregroundColor(c)
            .padding(.horizontal, 9).frame(height: 22).background(Capsule().fill(c.opacity(0.15)))
    }
}

struct DashHireSheet: View {
    var light: Bool
    var done: () -> Void
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var nav = BizNav.shared
    var body: some View {
        let T = HubTheme(light: light)
        let biz = !ZuffiPlan.shared.isPersonal && nav.formDone
        let options = ZuffiTeam.builtins.filter { $0.id != ZuffiTeam.manager.id && (biz || ZuffiTeam.personalTeam.contains($0.id)) }
        let picks = Set(team.suggestions.map(\.agent))
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Hire agents").font(HubFont.p(18, .semibold)); Spacer(); Button("Done", action: done).keyboardShortcut(.cancelAction) }
            if !biz && !ZuffiPlan.shared.isPersonal { Text("Fill in the Business page first — then business agents (Instagram, Facebook, WhatsApp…) appear here.").font(HubFont.p(12, .regular)).foregroundColor(T.inactive) }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(options.sorted { picks.contains($0.id) && !picks.contains($1.id) }, id: \.id) { a in
                        HStack(spacing: 12) {
                            RobotFace(agent: a, size: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(a.name).font(HubFont.p(14)); if picks.contains(a.id) { Text("Nik suggests").font(HubFont.p(10.5)).foregroundColor(HubTheme.blue) } }
                                Text(a.description).font(HubFont.p(12, .regular)).foregroundColor(T.inactive).lineLimit(2)
                            }
                            Spacer()
                            if team.hired.contains(a.id) { DashButton(title: "Remove", filled: false, light: light) { team.fire(a) } }
                            else { DashButton(title: "Hire", light: light) { team.hire(a, why: picks.contains(a.id) ? "Suggested by Nik" : "") } }
                        }
                        .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(T.content))
                    }
                }
            }
        }
        .padding(24).frame(width: 640, height: 620)
    }
}

// MARK: 2 · Routines — the daily pipeline and the end-of-day report

struct DashRoutinesPage: View {
    var light: Bool
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var report = DailyReport.shared
    @State private var agentID = ""
    @State private var task = ""
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var day = 0
    @AppStorage("eodOn") private var eodOn = true
    @AppStorage("eodHour") private var eodHour = 18
    @AppStorage("eodPDF") private var eodPDF = true
    private var T: HubTheme { HubTheme(light: light) }
    private var people: [TeamAgent] { var l = team.hiredAgents; for id in ZuffiTeam.personalTeam { if let a = team.agent(id), !l.contains(a) { l.append(a) } }; return l }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            NikPlanView(light: light)
            DashCard(title: "Your pipeline", sub: "Every day, these agents do these tasks in this order. Add a step, set the time, switch any off.", light: light) {
                let jobs = team.jobs.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
                if jobs.isEmpty { Text("No steps yet — add the first one below.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
                VStack(spacing: 0) {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { i, j in
                        HStack(spacing: 14) {
                            Text("\(i + 1)").font(HubFont.p(12, .semibold)).foregroundColor(.white).frame(width: 24, height: 24).background(Circle().fill(HubTheme.blue))
                            Text(String(format: "%02d:%02d", j.hour, j.minute)).font(HubFont.p(13)).frame(width: 46, alignment: .leading)
                            if let a = team.agent(j.agent) { RobotFace(agent: a, size: 24) }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(j.title).font(HubFont.p(13.5))
                                Text("\(team.agent(j.agent).map(AgentEdits.name) ?? "") · \(j.weekday == nil ? "every day" : Calendar.current.weekdaySymbols[(j.weekday! - 1) % 7]) · \(j.lastStatus.isEmpty ? "not run yet" : j.lastStatus)")
                                    .font(HubFont.p(11, .regular)).foregroundColor(T.inactive)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { j.enabled }, set: { v in if let k = team.jobs.firstIndex(where: { $0.id == j.id }) { team.jobs[k].enabled = v } })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                            Button { Task { await team.runJob(j.id) } } label: { Image(systemName: "play.fill") }.buttonStyle(.plain).foregroundColor(T.inactive).help("Run now")
                            Button { team.jobs.removeAll { $0.id == j.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundColor(T.inactive).help("Remove")
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .top) { if i > 0 { Rectangle().fill(T.border).frame(height: 1) } }
                    }
                }
                // add a step
                HStack(spacing: 10) {
                    Picker("", selection: $agentID) {
                        Text("Pick an agent").tag("")
                        ForEach(people, id: \.id) { a in Text(AgentEdits.name(a)).tag(a.id) }
                    }.labelsHidden().frame(width: 180)
                    TextField("What should it do? e.g. Check new reviews and draft replies", text: $task).textFieldStyle(.roundedBorder)
                    DatePicker("", selection: $time, displayedComponents: .hourAndMinute).labelsHidden().frame(width: 90)
                    Picker("", selection: $day) {
                        Text("Every day").tag(0)
                        ForEach(1...7, id: \.self) { d in Text(Calendar.current.weekdaySymbols[d - 1]).tag(d) }
                    }.labelsHidden().frame(width: 120)
                    DashButton(title: "Add step", icon: "plus", light: light) {
                        let t = task.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !agentID.isEmpty, !t.isEmpty else { return }
                        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                        var j = TeamJob(agent: agentID, title: String(t.prefix(40)), task: t, hour: c.hour ?? 9, minute: c.minute ?? 0)
                        j.weekday = day == 0 ? nil : day
                        if !team.hired.contains(agentID), let a = team.agent(agentID), !ZuffiTeam.isPersonal(a) { team.hire(a, why: "Added to the pipeline") }
                        team.jobs.append(j); task = ""
                    }
                }
            }
            DashCard(title: "End-of-day report", sub: "Every evening your agents write what happened today, what each one did and what failed — saved in Downloads › Zuffi › Reports.", light: light) {
                HStack(spacing: 18) {
                    Toggle("Make it every day", isOn: $eodOn).toggleStyle(.switch)
                    Stepper("At \(String(format: "%02d:00", eodHour))", value: $eodHour, in: 12...23).frame(width: 140)
                    Picker("", selection: $eodPDF) { Text("PDF").tag(true); Text("Text file").tag(false) }.pickerStyle(.segmented).frame(width: 180)
                    Spacer()
                    DashButton(title: "Make today's report now", icon: "doc.text", light: light) { if let u = report.make() { NSWorkspace.shared.open(u) } }
                }
                if !report.files.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(report.files.prefix(10), id: \.self) { f in
                            HStack {
                                Image(systemName: f.pathExtension == "pdf" ? "doc.richtext" : "doc.text").foregroundColor(HubTheme.blue)
                                Text(f.deletingPathExtension().lastPathComponent).font(HubFont.p(13))
                                Spacer()
                                Button("Open") { NSWorkspace.shared.open(f) }.buttonStyle(.plain).foregroundColor(HubTheme.blue).font(HubFont.p(12))
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([f]) }.buttonStyle(.plain).foregroundColor(T.inactive).font(HubFont.p(12))
                            }
                        }
                    }
                }
            }
        }
        .onAppear { report.list(); if agentID.isEmpty { agentID = people.first?.id ?? "" } }
    }
}

// MARK: 3 · Channels — connect your apps, hand them to agents, one inbox, posting

struct DashChannelsPage: View {
    var light: Bool
    @ObservedObject private var hub = SocialHub.shared
    @ObservedObject private var team = ZuffiTeam.shared
    @ObservedObject private var wa = WhatsAppLink.shared
    @State private var filter = "all"
    @State private var image: URL?
    @State private var about = ""
    @State private var caption = ""
    @State private var postTo = "instagram"
    @State private var writing = false
    @State private var posting = false
    @State private var postNote = ""
    private var T: HubTheme { HubTheme(light: light) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashCard(title: "Your channels", sub: "Connect each app once inside Zuffi (you sign in yourself — Zuffi never sees your password), then choose which agent looks after it.", light: light) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(SocialChannel.all) { ch in channelCard(ch) }
                }
                Text("“Reply by itself” lets the agent answer and post without asking you. Apps like Instagram and Facebook don't allow automated accounts, so they may limit an account that replies too fast — Zuffi replies at a human pace, but the choice is yours.")
                    .font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive).fixedSize(horizontal: false, vertical: true)
            }
            inboxCard
            postCard
            ReachSitesView(light: light)
        }
        .task { await hub.refresh() }
    }

    private func channelCard(_ ch: SocialChannel) -> some View {
        let on = hub.connected.contains(ch.id)
        let agents = team.hiredAgents + ZuffiTeam.builtins.filter { ["zuffi-instagram", "zuffi-facebook", "zuffi-whatsapp", "zuffi-social"].contains($0.id) && !team.hired.contains($0.id) }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: ch.icon).font(.system(size: 17, weight: .bold)).foregroundColor(.white).frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: ch.color)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ch.name).font(HubFont.p(15, .semibold))
                    HStack(spacing: 5) {
                        Circle().fill(on ? Color(hex: "#3DBE7E") : T.inactive.opacity(0.5)).frame(width: 7, height: 7)
                        Text(on ? "Connected" : ch.id == "whatsapp" && wa.state == "qr" ? "Scan the code on your phone" : "Not connected").font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive)
                    }
                }
                Spacer()
                DashButton(title: on ? "Open" : "Connect", filled: !on, light: light) { hub.connect(ch) }
            }
            HStack(spacing: 8) {
                Text("Agent").font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                Picker("", selection: Binding(get: { hub.agentFor(ch.id).id }, set: { id in
                    hub.setAgent(ch.id, id)
                    if let a = team.agent(id), !team.hired.contains(id) { team.hire(a, why: "Looks after \(ch.name)") }
                })) {
                    ForEach(agents, id: \.id) { a in Text(AgentEdits.name(a)).tag(a.id) }
                }.labelsHidden().frame(width: 170)
                Spacer()
                if ch.id != "whatsapp" {
                    Button { Task { await hub.check(ch) } } label: {
                        if hub.busy.contains(ch.id) { ProgressView().controlSize(.small) } else { Label("Check now", systemImage: "arrow.clockwise").font(HubFont.p(12)) }
                    }.buttonStyle(.plain).foregroundColor(HubTheme.blue).disabled(!on)
                }
            }
            Picker("", selection: Binding(get: { hub.mode(ch.id) }, set: { hub.setMode(ch.id, $0) })) {
                Text("Off").tag("off"); Text("Ask me first").tag("ask"); Text("Reply by itself").tag("auto")
            }.pickerStyle(.segmented).labelsHidden()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
    }

    private var inboxCard: some View {
        DashCard(title: "Inbox", sub: "Every comment and message from your channels, with your agent's reply. Edit a reply before sending, or let agents reply by themselves.", light: light) {
            HStack(spacing: 8) {
                ForEach(["all"] + SocialChannel.all.map(\.id), id: \.self) { id in
                    let name = id == "all" ? "All" : SocialChannel.of(id)?.name ?? id
                    Button { filter = id } label: {
                        Text(name).font(HubFont.p(12)).foregroundColor(filter == id ? .white : T.text).padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule().fill(filter == id ? HubTheme.blue : T.content))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Button { Task { await hub.checkAll() } } label: { Label("Check all", systemImage: "arrow.clockwise").font(HubFont.p(12)) }.buttonStyle(.plain).foregroundColor(HubTheme.blue)
            }
            let list = hub.inbox.filter { filter == "all" || $0.channel == filter }.prefix(40)
            if list.isEmpty { Text("No messages yet. Connect a channel and press “Check now”.").font(HubFont.p(13, .regular)).foregroundColor(T.inactive) }
            VStack(spacing: 10) { ForEach(Array(list)) { m in DashInboxRow(message: m, light: light) } }
        }
    }

    private var postCard: some View {
        DashCard(title: "Create a post", sub: "Add a picture and say what it's about. The agent looks at the picture, writes the caption and hashtags, then posts it for you.", light: light) {
            HStack(alignment: .top, spacing: 18) {
                Button {
                    let p = NSOpenPanel(); p.allowedContentTypes = [.image]; p.allowsMultipleSelection = false
                    if p.runModal() == .OK { image = p.url; caption = "" }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(T.content).frame(width: 180, height: 180)
                        if let image, let img = NSImage(contentsOf: image) { Image(nsImage: img).resizable().scaledToFill().frame(width: 180, height: 180).clipShape(RoundedRectangle(cornerRadius: 14)) }
                        else { VStack(spacing: 6) { Image(systemName: "photo.badge.plus").font(.system(size: 26)); Text("Choose picture").font(HubFont.p(12)) }.foregroundColor(T.inactive) }
                    }
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Picker("", selection: $postTo) { ForEach(SocialChannel.all.filter { $0.id != "whatsapp" }) { ch in Text(ch.name).tag(ch.id) } }.labelsHidden().frame(width: 160)
                        TextField("What's it about? e.g. new summer menu, 20% off this week", text: $about).textFieldStyle(.roundedBorder)
                    }
                    TextEditor(text: $caption).font(HubFont.p(13, .regular)).frame(height: 110)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.border))
                        .overlay(alignment: .topLeading) { if caption.isEmpty { Text("The caption appears here — you can edit it").font(HubFont.p(12, .regular)).foregroundColor(T.inactive).padding(8).allowsHitTesting(false) } }
                    HStack(spacing: 10) {
                        DashButton(title: writing ? "Writing…" : "Write caption", icon: "sparkles", filled: false, light: light) {
                            guard let image, !writing else { postNote = "Choose a picture first."; return }
                            writing = true; postNote = ""
                            Task { caption = await hub.writeCaption(image: image, about: about, channel: postTo); writing = false; if caption.isEmpty { postNote = "Couldn't write it — check an AI is set up in Settings." } }
                        }
                        DashButton(title: posting ? "Posting…" : "Post now", icon: "paperplane.fill", light: light) {
                            guard let image, !caption.isEmpty, !posting else { postNote = "Add a picture and a caption first."; return }
                            guard hub.connected.contains(postTo) else { postNote = "Connect \(SocialChannel.of(postTo)?.name ?? postTo) first."; return }
                            posting = true; postNote = "Your agent is posting — watch it in the Agent Office."
                            Task { let ok = await hub.post(image: image, caption: caption, channel: postTo); posting = false; postNote = ok ? "Posted ✓" : "Couldn't post this time — see Activity on the Dashboard." }
                        }
                        Text(postNote).font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
                    }
                }
            }
        }
    }
}

struct DashInboxRow: View {
    let message: SocialMessage
    var light: Bool
    @ObservedObject private var hub = SocialHub.shared
    @State private var sending = false
    var body: some View {
        let T = HubTheme(light: light)
        let ch = SocialChannel.of(message.channel)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: ch?.icon ?? "bubble.left").font(.system(size: 12, weight: .bold)).foregroundColor(.white).frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(hex: ch?.color ?? "#3A6DF0")))
                Text(message.from).font(HubFont.p(13.5, .semibold))
                Text("· \(message.kind) · \(message.at.formatted(date: .abbreviated, time: .shortened))").font(HubFont.p(11, .regular)).foregroundColor(T.inactive)
                Spacer()
                DashStatus(status: message.status == "sent" ? "Done" : message.status == "failed" ? "Failed" : message.status == "drafted" ? "Needs input" : "Working")
            }
            Text(message.text).font(HubFont.p(13.5, .regular)).textSelection(.enabled)
            if message.status != "skipped" {
                HStack(alignment: .top, spacing: 10) {
                    RobotFace(agent: hub.agentFor(message.channel), size: 22)
                    TextEditor(text: Binding(get: { hub.inbox.first { $0.id == message.id }?.reply ?? "" },
                                             set: { v in if let i = hub.inbox.firstIndex(where: { $0.id == message.id }) { hub.inbox[i].reply = v } }))
                        .font(HubFont.p(13, .regular)).frame(height: 64)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.border))
                        .disabled(message.status == "sent")
                }
                if message.status != "sent" {
                    HStack(spacing: 10) {
                        Spacer()
                        Button("Skip") { if let i = hub.inbox.firstIndex(where: { $0.id == message.id }) { hub.inbox[i].status = "skipped" } }.buttonStyle(.plain).foregroundColor(T.inactive).font(HubFont.p(12))
                        Button("Rewrite") { Task { await hub.draft(message.id) } }.buttonStyle(.plain).foregroundColor(HubTheme.blue).font(HubFont.p(12))
                        DashButton(title: sending ? "Sending…" : "Send reply", icon: "paperplane.fill", light: light) {
                            guard !sending else { return }
                            sending = true
                            Task { await hub.send(message.id); sending = false }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(T.content))
    }
}

// MARK: 4 · Business — one clear form; agents use it for everything

struct DashBusinessPage: View {
    var light: Bool
    @ObservedObject private var biz = ZuffiBusiness.shared
    @ObservedObject private var research = BusinessResearch.shared
    @State private var f: [String: String] = (UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:]
    @State private var name = UserDefaults.standard.string(forKey: "zuffiBusinessName") ?? ""
    @State private var saved = ""
    private var T: HubTheme { HubTheme(light: light) }

    private let groups: [(String, String, [(key: String, label: String, hint: String, tall: Bool)])] = [
        ("About your business", "building.2.fill", [
            ("type", "Type of business", "Hair salon, estate agent, restaurant, online shop…", false),
            ("about", "What you do", "Two or three lines in your own words", true),
            ("goals", "Your goals right now", "More bookings on weekdays, more Instagram followers…", true)]),
        ("Links agents read", "link", [
            ("website", "Website", "https://yourbusiness.co.uk", false),
            ("instagram", "Instagram", "https://instagram.com/yourbusiness", false),
            ("facebook", "Facebook page", "https://facebook.com/yourbusiness", false),
            ("tiktok", "TikTok", "https://tiktok.com/@yourbusiness", false),
            ("google", "Google Maps / Business profile", "Paste the link to your Google listing", false)]),
        ("Contact & hours", "phone.fill", [
            ("phone", "Phone / WhatsApp", "+44 7…", false),
            ("address", "Address / area", "Shop 4, High Street, Maidstone ME14", false),
            ("hours", "Opening hours", "Mon–Sat 9am–6pm, closed Sunday", false)]),
        ("What you sell", "tag.fill", [
            ("services", "Services or products & prices", "One per line, e.g.\nHaircut £25\nColour from £85", true),
            ("payment", "Payment", "Cash, card, bank transfer…", false),
            ("booking", "How to book or buy", "Message us the service and a day", false),
            ("extra", "Anything else customers should know", "Free parking behind the shop", false)]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashCard(light: light) {
                HStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Business name").font(HubFont.p(12, .semibold)).foregroundColor(T.inactive)
                        TextField("e.g. Bella Hair Studio", text: $name).textFieldStyle(.plain).font(HubFont.p(22, .semibold))
                            .padding(.horizontal, 14).frame(height: 50).background(RoundedRectangle(cornerRadius: 12).fill(T.content))
                    }
                    VStack(alignment: .trailing, spacing: 8) {
                        DashButton(title: "Save", icon: "checkmark", light: light, go: save)
                        if !saved.isEmpty { Text(saved).font(HubFont.p(11.5, .regular)).foregroundColor(T.inactive) }
                    }
                }
                Text("Only the name and one link (or your area) are needed — your agents search Google, read your pages and your competitors', and fill in what they find.")
                    .font(HubFont.p(12, .regular)).foregroundColor(T.inactive)
            }
            ForEach(groups, id: \.0) { g in
                DashCard(title: g.0, light: light) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], alignment: .leading, spacing: 14) {
                        ForEach(g.2, id: \.key) { fd in field(fd) }
                    }
                }
            }
            BusinessReportCard(light: light)
        }
    }

    private func field(_ fd: (key: String, label: String, hint: String, tall: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(fd.label).font(HubFont.p(12, .semibold)).foregroundColor(T.inactive)
            if fd.tall {
                TextEditor(text: bind(fd.key)).font(HubFont.p(13, .regular)).frame(height: 84).padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(T.content))
                    .overlay(alignment: .topLeading) { if (f[fd.key] ?? "").isEmpty { Text(fd.hint).font(HubFont.p(12, .regular)).foregroundColor(T.inactive.opacity(0.7)).padding(11).allowsHitTesting(false) } }
            } else {
                TextField(fd.hint, text: bind(fd.key)).textFieldStyle(.plain).font(HubFont.p(13, .regular))
                    .padding(.horizontal, 12).frame(height: 38).background(RoundedRectangle(cornerRadius: 10).fill(T.content))
            }
        }
    }
    private func bind(_ k: String) -> Binding<String> { Binding(get: { f[k] ?? "" }, set: { f[k] = $0; saved = "" }) }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(n, forKey: "zuffiBusinessName"); biz.businessName = n
        var all = (UserDefaults.standard.dictionary(forKey: "bizForm") as? [String: String]) ?? [:]
        for (k, v) in f { all[k] = v }
        UserDefaults.standard.set(all, forKey: "bizForm")
        BizDetailsForm.rebuildInfo()
        let wasDone = BizNav.shared.formDone
        BizNav.shared.formDone = BizDetailsForm.isComplete
        let link = [all["website"], all["instagram"], all["facebook"]].compactMap { $0 }.joined(separator: " ")
        if BizDetailsForm.isComplete, !wasDone || link != (UserDefaults.standard.string(forKey: "bizResearchedLink") ?? "") {
            UserDefaults.standard.set(link, forKey: "bizResearchedLink")
            BusinessResearch.shared.start()
            saved = "Saved — your agents are researching your business now."
        } else {
            saved = BizDetailsForm.isComplete ? "Saved ✓" : "Saved. Add a link or your area so agents can research you."
        }
    }
}

// MARK: 5 · Pet & look

struct DashLookPage: View {
    var light: Bool
    @AppStorage("hubLight") private var hubLight = false
    @AppStorage("petReminders") private var petReminders = true
    @AppStorage("petNever") private var petNever = false
    @AppStorage("notchWide") private var notchWide = true
    @AppStorage("helloOnOpen") private var hello = true
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            DashCard(title: "Aurora", sub: "Your pet — pick her colour", light: light) {
                AuroraColorPicker()
                HStack(spacing: 12) {
                    DashButton(title: PetController.shared.isShown ? "Hide Aurora" : "Show Aurora", icon: "hare.fill", light: light) { PetController.shared.toggle() }
                }
                Toggle("She brings reminders to the front", isOn: $petReminders).toggleStyle(.switch)
                Toggle("Never show the pet (reminders go to the notch)", isOn: $petNever).toggleStyle(.switch)
            }
            DashCard(title: "Notch", light: light) {
                Toggle("Say hi when Zuffi starts", isOn: $hello).toggleStyle(.switch)
            }
        }
        .font(HubFont.p(13.5, .regular))
    }
}

// MARK: 6 · Automations — one switch per thing, per app

struct DashAutomationsPage: View {
    var light: Bool
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var hub = SocialHub.shared
    @ObservedObject private var team = ZuffiTeam.shared
    private var T: HubTheme { HubTheme(light: light) }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)], alignment: .leading, spacing: 20) {
            ForEach(SocialChannel.all) { ch in
                DashCard(light: light) {
                    HStack(spacing: 12) {
                        Image(systemName: ch.icon).font(.system(size: 16, weight: .bold)).foregroundColor(.white).frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: ch.color)))
                        Text("Automate \(ch.name)").font(HubFont.p(16, .semibold))
                        Spacer()
                        if !hub.connected.contains(ch.id) { DashButton(title: "Connect", filled: false, light: light) { hub.connect(ch) } }
                    }
                    switchRow("Read new comments and messages", on: hub.mode(ch.id) != "off") { hub.setMode(ch.id, $0 ? "ask" : "off") }
                    switchRow("Reply by itself (no asking)", on: hub.mode(ch.id) == "auto") { hub.setMode(ch.id, $0 ? "auto" : "ask") }
                    if ch.id == "whatsapp" {
                        switchRow("Autopilot — chat with customers", on: crm.isOn(.autopilot)) { crm.set(.autopilot, $0) }
                        switchRow("Follow up people who go quiet", on: crm.isOn(.quietFollowUp)) { crm.set(.quietFollowUp, $0) }
                        switchRow("Out-of-hours reply", on: crm.isOn(.afterHours)) { crm.set(.afterHours, $0) }
                        switchRow("Thank customers and ask for a review", on: crm.isOn(.thankAndReview)) { crm.set(.thankAndReview, $0) }
                        switchRow("Polite reminders for late payments", on: crm.isOn(.paymentReminders)) { crm.set(.paymentReminders, $0) }
                    } else {
                        let title = "Daily \(ch.name) post idea"
                        switchRow("A post idea every morning", on: team.jobs.contains { $0.title == title }) { on in
                            if on {
                                let a = hub.agentFor(ch.id)
                                if !team.hired.contains(a.id) { team.hire(a, why: "Daily \(ch.name) posts") }
                                team.jobs.append(TeamJob(agent: a.id, title: title, task: "Look at my \(ch.name) and my competitors, then give me today's \(ch.name) post: the idea, the caption and hashtags, and the best time to post.", hour: 9, minute: 30))
                            } else { team.jobs.removeAll { $0.title == title } }
                        }
                    }
                }
            }
        }
    }
    private func switchRow(_ t: String, on: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { on }, set: set)) { Text(t).font(HubFont.p(13.5, .regular)) }.toggleStyle(.switch)
    }
}

// MARK: 7 · Settings — see "Settings: everything in the new design" below

// =====================================================================
// MARK: - Beautiful inputs: a floating label, a bar that grows from the middle on focus, and a quick highlight
// =====================================================================

enum ZInk {
    /// Zuffi's accent: the notch's pink → lilac, with the dashboard blue.
    static let accent = Color(hex: "#7C6CF2")
    static let accentGradient = LinearGradient(colors: [Color(hex: "#F58FA8"), Color(hex: "#B79CFF"), Color(hex: "#6E8BFF")], startPoint: .leading, endPoint: .trailing)
    static func text(_ light: Bool) -> Color { light ? Color(hex: "#1E2130") : Color(hex: "#F4F5FA") }
    static func label(_ light: Bool) -> Color { light ? Color(hex: "#6B7086") : Color(hex: "#9AA0B8") }
    static func line(_ light: Bool) -> Color { light ? Color(hex: "#C9CDD9") : Color.white.opacity(0.18) }
    static func fill(_ light: Bool) -> Color { light ? Color.white.opacity(0.7) : Color.white.opacity(0.05) }
}

struct ZField: View {
    let label: String
    @Binding var text: String
    var secure = false
    var light = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool
    @State private var sweep: CGFloat = 0
    private var up: Bool { focused || !text.isEmpty }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(label)
                .font(HubFont.p(up ? 11 : 14, up ? .medium : .regular))
                .foregroundColor(focused ? ZInk.accent : (up ? ZInk.accent.opacity(0.85) : ZInk.label(light)))
                .offset(y: up ? -15 : 0)
                .allowsHitTesting(false)
            Group {
                if secure { SecureField("", text: $text) } else { TextField("", text: $text) }
            }
            .textFieldStyle(.plain).font(HubFont.p(14, .regular)).foregroundColor(ZInk.text(light))
            .focused($focused).onSubmit(onSubmit)
            .padding(.top, 10)
        }
        .padding(.horizontal, 12).frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ZInk.fill(light)))
        .overlay(alignment: .bottom) {
            ZStack {
                Rectangle().fill(!text.isEmpty ? ZInk.accent.opacity(0.6) : ZInk.line(light)).frame(height: 1)
                Rectangle().fill(ZInk.accentGradient).frame(height: 2).scaleEffect(x: focused ? 1 : 0.001, anchor: .center)
            }
            .clipShape(RoundedRectangle(cornerRadius: 1))
            .padding(.horizontal, 4)
        }
        .overlay {
            // the quick highlight that sweeps across when you click in
            GeometryReader { g in
                Rectangle().fill(ZInk.accent.opacity(0.28 * (1 - sweep))).frame(width: max(1, g.size.width * sweep)).position(x: g.size.width / 2, y: g.size.height / 2).allowsHitTesting(false)
            }.clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .animation(.easeOut(duration: 0.2), value: focused)
        .animation(.easeOut(duration: 0.2), value: up)
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .onChange(of: focused) { _, f in
            guard f else { return }
            sweep = 0.02
            withAnimation(.easeOut(duration: 0.5)) { sweep = 1 }
        }
    }
}

struct ZTextArea: View {
    let label: String
    @Binding var text: String
    var light = false
    var height: CGFloat = 120
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(HubFont.p(11, .medium)).foregroundColor(focused ? ZInk.accent : ZInk.label(light))
            TextEditor(text: $text).font(HubFont.p(14, .regular)).foregroundColor(ZInk.text(light))
                .scrollContentBackground(.hidden).focused($focused).frame(height: height)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ZInk.fill(light)))
        .overlay(alignment: .bottom) {
            ZStack {
                Rectangle().fill(ZInk.line(light)).frame(height: 1)
                Rectangle().fill(ZInk.accentGradient).frame(height: 2).scaleEffect(x: focused ? 1 : 0.001, anchor: .center)
            }.padding(.horizontal, 4)
        }
        .animation(.easeOut(duration: 0.2), value: focused)
    }
}

/// A dropdown that looks like the fields: floating label, the value, a chevron.
struct ZSelect: View {
    let label: String
    @Binding var value: String
    let options: [(String, String)]          // (tag, shown)
    var light = false
    var body: some View {
        Menu {
            ForEach(options, id: \.0) { o in Button { value = o.0 } label: { if o.0 == value { Label(o.1, systemImage: "checkmark") } else { Text(o.1) } } }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(HubFont.p(11, .medium)).foregroundColor(ZInk.accent.opacity(0.85))
                HStack {
                    Text(options.first { $0.0 == value }?.1 ?? value).font(HubFont.p(14, .regular)).foregroundColor(ZInk.text(light)).lineLimit(1)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundColor(ZInk.label(light))
                }
            }
            .padding(.horizontal, 12).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ZInk.fill(light)))
            .overlay(alignment: .bottom) { Rectangle().fill(ZInk.line(light)).frame(height: 1).padding(.horizontal, 4) }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
    }
}

/// A switch row in the same style.
struct ZToggle: View {
    let title: String
    var sub = ""
    @Binding var on: Bool
    var light = false
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(HubFont.p(14)).foregroundColor(ZInk.text(light))
                if !sub.isEmpty { Text(sub).font(HubFont.p(12, .regular)).foregroundColor(ZInk.label(light)).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer()
            Toggle("", isOn: $on).labelsHidden().toggleStyle(.switch).tint(ZInk.accent)
        }
        .padding(.vertical, 6)
    }
}

// =====================================================================
// MARK: - Settings: everything in the new design (no old windows)
// =====================================================================

enum ProfilePhoto {
    static var url: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Zuffi", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("profile.jpg")
    }
    static var image: NSImage? { NSImage(contentsOf: url) }
    static func set(_ from: URL) {
        guard let img = NSImage(contentsOf: from), let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let d = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        try? d.write(to: url)
        NotificationCenter.default.post(name: .profileChanged, object: nil)
    }
}
extension Notification.Name { static let profileChanged = Notification.Name("zuffiProfileChanged") }

/// Your picture (or your first letter) in a ring — used in Settings and the notch.
struct ProfileAvatar: View {
    var size: CGFloat = 40
    @State private var version = 0
    var body: some View {
        let name = ZuffiPlan.shared.profile["name"] ?? ""
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hex: "#F5B963"), Color(hex: "#F58FA8"), Color(hex: "#B79CFF")], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let img = ProfilePhoto.image { Image(nsImage: img).resizable().scaledToFill().clipShape(Circle()).padding(size * 0.06) }
            else { Text(String(name.prefix(1)).uppercased().isEmpty ? "🙂" : String(name.prefix(1)).uppercased()).font(.system(size: size * 0.45, weight: .bold, design: .rounded)).foregroundColor(.white) }
        }
        .frame(width: size, height: size)
        .id(version)
        .onReceive(NotificationCenter.default.publisher(for: .profileChanged)) { _ in version += 1 }
    }
}

struct DashSettingsPage: View {
    var light: Bool
    @AppStorage("settingsTab") private var tab = "Profile"
    private let tabs: [(String, String)] = [("Profile", "person.crop.circle.fill"), ("AI models", "cpu.fill"), ("Voice & sound", "waveform"), ("General", "gearshape.fill"), ("Privacy", "lock.fill")]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ForEach(tabs, id: \.0) { t in
                    Button { tab = t.0 } label: {
                        Label(t.0, systemImage: t.1).font(HubFont.p(13)).foregroundColor(tab == t.0 ? .white : ZInk.text(light))
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Capsule().fill(tab == t.0 ? AnyShapeStyle(ZInk.accentGradient) : AnyShapeStyle(ZInk.fill(light))))
                    }.buttonStyle(.plain)
                }
            }
            switch tab {
            case "AI models": AIModelsPane(light: light)
            case "Voice & sound": VoicePane(light: light)
            case "General": GeneralPane(light: light)
            case "Privacy": PrivacyPane(light: light)
            default: ProfilePane(light: light)
            }
        }
    }
}

struct ProfilePane: View {
    var light: Bool
    @State private var p: [String: String] = ZuffiPlan.shared.profile
    @State private var saved = ""
    private let fields: [(String, String)] = [("name", "Your name"), ("school", "School / college / university"), ("course", "Course or subjects"), ("year", "Year / grade"),
                                              ("dob", "Birthday (YYYY-MM-DD)"), ("city", "City"), ("country", "Country"), ("langs", "Languages you speak"),
                                              ("goals", "What do you want help with?"), ("hobbies", "Hobbies")]
    var body: some View {
        DashCard(light: light) {
            HStack(spacing: 18) {
                ProfileAvatar(size: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(p["name"]?.isEmpty == false ? p["name"]! : "Your profile").font(HubFont.p(20, .semibold)).foregroundColor(ZInk.text(light))
                    Text("Zuffi uses this to help you better. It stays on your Mac.").font(HubFont.p(12.5, .regular)).foregroundColor(ZInk.label(light))
                    HStack(spacing: 8) {
                        DashButton(title: "Change photo", icon: "camera.fill", filled: false, light: light) {
                            let o = NSOpenPanel(); o.allowedContentTypes = [.image]
                            if o.runModal() == .OK, let u = o.url { ProfilePhoto.set(u) }
                        }
                        if ProfilePhoto.image != nil {
                            Button("Remove") { try? FileManager.default.removeItem(at: ProfilePhoto.url); NotificationCenter.default.post(name: .profileChanged, object: nil) }
                                .buttonStyle(.plain).foregroundColor(ZInk.label(light)).font(HubFont.p(12))
                        }
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 14) {
                ForEach(fields, id: \.0) { f in ZField(label: f.1, text: Binding(get: { p[f.0] ?? "" }, set: { p[f.0] = $0; saved = "" }), light: light) }
            }
            ZTextArea(label: "Anything else Zuffi should know about you", text: Binding(get: { p["notes"] ?? "" }, set: { p["notes"] = $0; saved = "" }), light: light, height: 70)
            HStack(spacing: 12) {
                DashButton(title: "Save profile", icon: "checkmark", light: light) {
                    var all: [String: Any] = ZuffiPlan.shared.profile
                    for (k, v) in p { all[k] = v }
                    all["type"] = "personal"
                    ZuffiPlan.shared.saveProfile(all)
                    NotificationCenter.default.post(name: .profileChanged, object: nil)
                    saved = "Saved ✓"
                }
                Text(saved).font(HubFont.p(12.5, .regular)).foregroundColor(Color(hex: "#3DBE7E"))
            }
        }
    }
}

struct AIModelsPane: View {
    var light: Bool
    @ObservedObject private var state = AppState.shared
    @State private var keys: [String: String] = [:]
    @State private var saved = ""
    @State private var ollama = "Checking…"
    @State private var pulling: Double?
    private let providers: [(String, String, String, String)] = [   // keychain key, name, placeholder, help
        ("anthropic-api-key", "Claude (Anthropic)", "sk-ant-…", "Best for studying and writing. Sees pictures."),
        ("openai-api-key", "ChatGPT (OpenAI)", "sk-…", "Sees pictures."),
        ("gemini-api-key", "Gemini (Google)", "AIza…", "Free tier available. Sees pictures (Flash models)."),
        ("groq-api-key", "Groq", "gsk_…", "Very fast, free tier. Text only."),
        ("openrouter-api-key", "OpenRouter", "sk-or-…", "Many models with one key."),
        ("deepseek-api-key", "DeepSeek", "sk-…", "Text only."),
        ("mistral-api-key", "Mistral", "…", "Text only."),
        ("xai-api-key", "Grok (xAI)", "xai-…", ""),
        ("perplexity-api-key", "Perplexity", "pplx-…", "Answers with web sources."),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DashCard(title: "Which AI answers", sub: "Auto picks the best one you've set up. Your own keys stay in your Mac's Keychain.", light: light) {
                ZSelect(label: "AI", value: $state.aiProvider, options: AIProvider.allCases.filter { ![.claudeCode, .codex, .geminiCLI].contains($0) }.map { ($0.rawValue, $0 == .auto ? "Auto (best available)" : $0.label) }, light: light)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 14) {
                    ZField(label: "Claude model (optional)", text: $state.claudeModel, light: light)
                    ZField(label: "ChatGPT model (optional)", text: $state.openaiModel, light: light)
                    ZField(label: "Gemini model (optional)", text: $state.geminiModel, light: light)
                }
            }
            DashCard(title: "Free AI on your Mac (Ollama)", sub: "Works offline and costs nothing. Needs the free Ollama app.", light: light) {
                HStack(spacing: 12) {
                    Circle().fill(ollama.hasPrefix("Ready") ? Color(hex: "#3DBE7E") : Color(hex: "#F5B963")).frame(width: 9, height: 9)
                    Text(ollama).font(HubFont.p(13.5)).foregroundColor(ZInk.text(light))
                    Spacer()
                    if let p = pulling { ProgressView(value: p).frame(width: 140) }
                    DashButton(title: "Get Ollama", icon: "arrow.down.circle", filled: false, light: light) { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
                    DashButton(title: "Download the free model", icon: "cpu", light: light) {
                        pulling = 0
                        Task { let ok = await AIService.pullOllama(AIService.recommendedOllama) { v, _ in pulling = v }; pulling = nil; ollama = ok ? "Ready — \(AIService.recommendedOllama)" : "Couldn't download — is Ollama open?" }
                    }
                }
            }
            DashCard(title: "Your own keys", sub: "Paste a key to use that AI. Leave empty to skip.", light: light) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 14) {
                    ForEach(providers, id: \.0) { pr in
                        VStack(alignment: .leading, spacing: 4) {
                            ZField(label: pr.1, text: Binding(get: { keys[pr.0] ?? "" }, set: { keys[pr.0] = $0; saved = "" }), secure: true, light: light)
                            if !pr.3.isEmpty { Text(pr.3).font(HubFont.p(11, .regular)).foregroundColor(ZInk.label(light)).padding(.leading, 4) }
                        }
                    }
                }
                HStack(spacing: 12) {
                    DashButton(title: "Save keys", icon: "key.fill", light: light) {
                        for (k, v) in keys { KeychainStore.shared.set(k, value: v.trimmingCharacters(in: .whitespacesAndNewlines)) }
                        UserDefaults.standard.removeObject(forKey: "geminiResolved")
                        saved = "Saved ✓"
                    }
                    Text(saved).font(HubFont.p(12.5, .regular)).foregroundColor(Color(hex: "#3DBE7E"))
                }
            }
        }
        .onAppear {
            for pr in providers { keys[pr.0] = KeychainStore.shared.get(pr.0) ?? "" }
            Task {
                let running = await AIService.ollamaRunning()
                let models = await AIService.ollamaModels()
                ollama = !running ? "Ollama isn't running" : models.isEmpty ? "Ollama is running — no model yet" : "Ready — \(models.first ?? "")"
            }
        }
    }
}

struct VoicePane: View {
    var light: Bool
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var voice = VoiceEngine.shared
    @AppStorage(AssistantPrefs.wakeWord) private var wake = true
    @AppStorage(AssistantPrefs.speakReplies) private var speak = true
    @AppStorage(AssistantPrefs.voiceGender) private var gender = "female"
    @AppStorage(AssistantPrefs.voiceRate) private var rate = 0.5
    @AppStorage(AssistantPrefs.greetEnabled) private var greet = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DashCard(title: "Voice", light: light) {
                ZToggle(title: "Microphone on", sub: "Talk to Zuffi. You can also switch it from the notch.", on: Binding(get: { voice.micEnabled }, set: { voice.setMic($0) }), light: light)
                ZToggle(title: "“Hey Zuffi”", sub: "Start talking without clicking (takes effect the next time Zuffi starts)", on: $wake, light: light)
                ZToggle(title: "Read answers out loud", on: $speak, light: light)
                ZToggle(title: "Say hello when Zuffi starts", on: $greet, light: light)
                HStack(spacing: 16) {
                    ZSelect(label: "Voice", value: $gender, options: [("female", "Female"), ("male", "Male")], light: light).frame(width: 220)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speed").font(HubFont.p(11, .medium)).foregroundColor(ZInk.label(light))
                        Slider(value: $rate, in: 0.35...0.65).tint(ZInk.accent)
                    }
                    DashButton(title: "Test", icon: "speaker.wave.2.fill", filled: false, light: light) { VoiceEngine.shared.speak("Hi! This is how I sound.") }
                }
            }
            DashCard(title: "Sounds", light: light) {
                ZToggle(title: "Little sounds", sub: "When Zuffi opens, answers or reminds you", on: $state.soundEnabled, light: light)
                HStack { Text("Volume").font(HubFont.p(13)).foregroundColor(ZInk.text(light)); Slider(value: $state.soundVolume, in: 0...0.2).tint(ZInk.accent).disabled(!state.soundEnabled) }
            }
        }
    }
}

struct GeneralPane: View {
    var light: Bool
    @ObservedObject private var state = AppState.shared
    @State private var login = SMAppService.mainApp.status == .enabled
    @AppStorage("notchWide") private var notchWide = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DashCard(title: "General", light: light) {
                ZToggle(title: "Open Zuffi when the Mac starts", on: Binding(get: { login }, set: { v in
                    login = v
                    if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }), light: light)
                ZToggle(title: "Keyboard shortcut opens the chat", on: $state.hotkeyEnabled, light: light)
                ZToggle(title: "Small glass notch", on: $notchWide, light: light)
                HStack(spacing: 16) {
                    ZField(label: "Close the notch after (seconds)", text: Binding(get: { String(Int(state.autoCloseInterval)) }, set: { state.autoCloseInterval = TimeInterval(Int($0) ?? 15) }), light: light).frame(width: 280)
                    DashButton(title: "Open the setup again", icon: "wand.and.stars", filled: false, light: light) { SetupWizard.shared.show() }
                }
            }
            MessagesInNotchCard(light: light)
        }
    }
}

/// WhatsApp and email at the notch: a new message drops down and you can reply right there.
struct MessagesInNotchCard: View {
    var light: Bool
    @ObservedObject private var wa = WhatsAppLink.shared
    private var T: HubTheme { HubTheme(light: light) }
    var body: some View {
        DashCard(title: "Messages in the notch", sub: "New messages drop down from the notch. Reply right there — nothing is sent until you press Send. Click anywhere else to fold it away.", light: light) {
            ZToggle(title: "WhatsApp messages", sub: wa.ready ? "Linked — new chats show at the notch" : wa.state == "qr" ? "Scan the code with WhatsApp on your phone (Linked devices)" : "Link your WhatsApp once with a QR code", on: $wa.enabled, light: light)
            if wa.enabled && !wa.ready { DashButton(title: "Show the QR code", icon: "qrcode", filled: false, light: light) { wa.showWindow() } }
            Text("Email: every account in Apple Mail (Gmail, Outlook, iCloud…) shows at the notch while the Mail app is open.").font(HubFont.p(12.5, .regular)).foregroundColor(T.inactive)
        }
    }
}

struct PrivacyPane: View {
    var light: Bool
    @State private var cleared = ""
    private func open(_ pane: String) { if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(u) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            DashCard(title: "Permissions", sub: "Zuffi only uses these when you ask.", light: light) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    DashButton(title: "Microphone", icon: "mic.fill", filled: false, light: light) { open("Privacy_Microphone") }
                    DashButton(title: "Screen (explain my screen)", icon: "rectangle.dashed", filled: false, light: light) { open("Privacy_ScreenCapture") }
                    DashButton(title: "Camera", icon: "camera.fill", filled: false, light: light) { open("Privacy_Camera") }
                    DashButton(title: "Accessibility (control the Mac)", icon: "hand.point.up.left.fill", filled: false, light: light) { open("Privacy_Accessibility") }
                    DashButton(title: "Automation (Notes, Music…)", icon: "gearshape.2.fill", filled: false, light: light) { open("Privacy_Automation") }
                    DashButton(title: "Speech recognition", icon: "waveform", filled: false, light: light) { open("Privacy_SpeechRecognition") }
                }
            }
            DashCard(title: "Your data", sub: "Your chats, study sets, words and profile stay on this Mac.", light: light) {
                HStack(spacing: 12) {
                    DashButton(title: "Clear chat history", icon: "trash", filled: false, light: light) {
                        for c in ChatArchive.shared.chats { ChatArchive.shared.delete(c) }
                        cleared = "Chat history cleared"
                    }
                    Text(cleared).font(HubFont.p(12.5, .regular)).foregroundColor(ZInk.label(light))
                }
            }
            DashCard(title: "Screen helpers", sub: "Ways to call Zuffi about what's on your screen.", light: light) {
                ZToggle(title: "Hold Z to talk", sub: "Hold Z for a second when you're not typing in a box", on: Binding(get: { UserDefaults.standard.object(forKey: "holdZ") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "holdZ") }), light: light)
                ZToggle(title: "Show the action bar when I select text", sub: "Explain · Translate · Reply · Rewrite · Read aloud", on: Binding(get: { UserDefaults.standard.object(forKey: "selectionBar") as? Bool ?? true }, set: { UserDefaults.standard.set($0, forKey: "selectionBar") }), light: light)
                DashButton(title: MeetingHelper.shared.on ? "Stop meeting helper" : "Start meeting helper (private)", icon: "person.2.wave.2.fill", filled: false, light: light) { MeetingHelper.shared.toggle() }
            }
            DashCard(title: "Start fresh", sub: "Erase everything Zuffi saved on this Mac — profile, chats, memory, courses, settings — and open the first-run setup again. Your Zuffi account and plan stay; just sign in again.", light: light) {
                HStack(spacing: 12) {
                    DashButton(title: "Erase and start fresh…", icon: "arrow.counterclockwise", filled: false, light: light) { ZuffiReset.confirmAndRun() }
                }
            }
        }
    }
}

