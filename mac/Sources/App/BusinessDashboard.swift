import SwiftUI
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

    func show(_ tab: BizTab? = nil) {
        if let tab { BizNav.shared.tab = tab }
        ZuffiCRM.shared.reload()
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Zuffi Business"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
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
    case today = "Today", inbox = "Inbox", pipeline = "Pipeline", team = "Team", automations = "Automations", connect = "Connect WhatsApp"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .inbox: return "tray.full.fill"
        case .pipeline: return "rectangle.split.3x1.fill"
        case .team: return "person.3.fill"
        case .automations: return "bolt.fill"
        case .connect: return "link"
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
    func say(_ s: String) {
        toast = s
        Task { @MainActor in try? await Task.sleep(nanoseconds: 4_000_000_000); if self.toast == s { self.toast = "" } }
    }
}

private enum Biz {
    static let pink = Color(hex: "#F58FA8"), amber = Color(hex: "#FBC56A"), orange = Color(hex: "#F28A3C"), green = Color(hex: "#34D399"), blue = Color(hex: "#7CC4FF"), red = Color(hex: "#FF7A85")
    static let card = Color.white.opacity(0.07), stroke = Color.white.opacity(0.12)
    static var accent: LinearGradient { LinearGradient(colors: [amber, orange], startPoint: .top, endPoint: .bottom) }
    static func stageColor(_ s: String) -> Color {
        switch s { case "New": return blue; case "Contacted": return Color(hex: "#C4B5FD"); case "Site visit", "Booked": return amber
        case "Negotiating", "Regular": return orange; case "Won": return green; case "Lost": return Color.white.opacity(0.4); default: return pink }
    }
}

private struct GlassBox<C: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> C
    var body: some View {
        content().padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Biz.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Biz.stroke, lineWidth: 0.8))
    }
}

private struct Pill: View {
    let text: String; var color: Color = Biz.pink; var filled = false
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundColor(filled ? Color(hex: "#1A1008") : color)
            .padding(.horizontal, 8).frame(height: 20)
            .background(Capsule().fill(filled ? color : color.opacity(0.16)))
    }
}

private struct PrimaryButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { if let icon { Image(systemName: icon) }; Text(title) }
                .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(Color(hex: "#1A1008"))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(Biz.accent))
        }.buttonStyle(.plain)
    }
}

private struct SoftButton: View {
    let title: String; var icon: String? = nil; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) { if let icon { Image(systemName: icon) }; Text(title) }
                .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundColor(.white)
                .padding(.horizontal, 11).frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.1)))
                .overlay(Capsule().stroke(Biz.stroke, lineWidth: 0.7))
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

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 210)
            Divider().overlay(Biz.stroke)
            VStack(spacing: 0) {
                topBar
                Group {
                    switch nav.tab {
                    case .today: BizTodayView()
                    case .inbox: BizInboxView()
                    case .pipeline: BizPipelineView()
                    case .team: BizTeamView()
                    case .automations: BizAutomationsView()
                    case .connect: BizConnectView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundColor(.white)
        .background(ZStack { Color(hex: "#0D0B1E"); ZuffiSpaceBackground(intensity: 0.55) }.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if !nav.toast.isEmpty || !crm.busy.isEmpty {
                Text(crm.busy.isEmpty ? nav.toast : crm.busy).font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Capsule().fill(Color.black.opacity(0.8))).overlay(Capsule().stroke(Biz.stroke))
                    .padding(.bottom, 16).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 18).stroke(Biz.pink, style: StrokeStyle(lineWidth: 3, dash: [8, 6])).padding(8)
                    .overlay(Text("Drop a voice note or a leads file").font(.system(size: 18, weight: .bold, design: .rounded)))
                    .background(Color.black.opacity(0.35))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in await BusinessFiles.take(url) }
                }
            }
            return true
        }
        .sheet(isPresented: $adding) { BizLeadEditor(lead: nil) }
        .animation(.easeInOut(duration: 0.2), value: nav.toast)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZuffiMini(state: AppState.shared, height: 40).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(biz.businessName.isEmpty ? "My business" : biz.businessName).font(.system(size: 14, weight: .heavy, design: .rounded)).lineLimit(1)
                    Text(biz.pack == .salon ? "Salon / shop" : biz.pack == .realEstate ? "Estate agent" : "Zuffi Business").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.55))
                }
            }
            .padding(.top, 34).padding(.bottom, 14).padding(.horizontal, 6)
            ForEach(BizTab.allCases) { t in
                Button { nav.tab = t } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.icon).frame(width: 18)
                        Text(t.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        if t == .inbox, crm.drafts.count > 0 { Pill(text: "\(crm.drafts.count)", color: Biz.pink, filled: true) }
                        if t == .today { let d = crm.leads.filter(\.dueToday).count; if d > 0 { Pill(text: "\(d)", color: Biz.amber) } }
                    }
                    .padding(.horizontal, 10).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10).fill(nav.tab == t ? Color.white.opacity(0.13) : .clear))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Spacer()
            if biz.pack == nil {
                Text("Pick your business:").font(.system(size: 10.5, weight: .bold)).foregroundColor(.white.opacity(0.6))
                HStack {
                    SoftButton(title: "Estate", icon: "house.fill") { Task { nav.say(await biz.install(.realEstate)); crm.reload() } }
                    SoftButton(title: "Salon", icon: "scissors") { Task { nav.say(await biz.install(.salon)); crm.reload() } }
                }
            }
            // Talk to Zuffi about the business
            HStack(spacing: 8) {
                Button { VoiceEngine.shared.listenOnce() } label: {
                    Image(systemName: voice.isListening ? "waveform" : "mic.fill").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: "#1A1008"))
                        .frame(width: 34, height: 34).background(Circle().fill(Biz.accent))
                }.buttonStyle(.plain).help("Talk: “new lead Ali 0333… from Facebook”, “who isn't following up?”")
                Button { ZuffiChat.shared.open() } label: {
                    Label("Ask Zuffi", systemImage: "bubble.left.fill").font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(Color.white.opacity(0.1)))
                }.buttonStyle(.plain)
            }
            Text(voice.isListening ? (voice.heard.isEmpty ? "Listening…" : voice.heard) : "Mic or chat: “new lead…”, “mark Ali as hot”, “team report”")
                .font(.system(size: 10)).foregroundColor(.white.opacity(0.5)).lineLimit(2).padding(.bottom, 14)
        }
        .padding(.horizontal, 12)
        .background(Color.black.opacity(0.25))
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Text(nav.tab.rawValue).font(.system(size: 22, weight: .heavy, design: .rounded))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.white.opacity(0.5))
                TextField("Search name, number, area…", text: $nav.search).textFieldStyle(.plain).frame(width: 200)
            }
            .padding(.horizontal, 10).frame(height: 30).background(Capsule().fill(Color.white.opacity(0.08)))
            SoftButton(title: "Voice note", icon: "waveform.badge.mic") { BusinessFiles.pickVoiceNote(for: nil) }
            PrimaryButton(title: "Add lead", icon: "plus") { adding = true }
        }
        .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 12)
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
                let today = ZuffiBusiness.iso(Date())
                let monthAgo = ZuffiBusiness.iso(Date().addingTimeInterval(-30 * 86400))
                HStack(spacing: 12) {
                    tile("New today", "\(crm.leads.filter { $0.added == today }.count)", "tray.and.arrow.down.fill", Biz.blue)
                    tile("Follow up today", "\(crm.leads.filter(\.dueToday).count)", "phone.fill", Biz.amber)
                    tile("Hot leads", "\(crm.leads.filter { $0.isOpen && $0.priority.lowercased() == "hot" }.count)", "flame.fill", Biz.pink)
                    tile("Overdue", "\(crm.leads.filter(\.overdue).count)", "exclamationmark.triangle.fill", Biz.red)
                    tile("Won · 30 days", "\(crm.leads.filter { $0.stage == "Won" && $0.lastContact >= monthAgo }.count)", "trophy.fill", Biz.green)
                }
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 14) {
                        GlassBox {
                            VStack(alignment: .leading, spacing: 8) {
                                header("Follow up today", "phone.arrow.up.right.fill")
                                let due = crm.leads.filter(\.dueToday).sorted { $0.overdue && !$1.overdue }
                                if due.isEmpty { empty("Nobody to chase today 🎉") }
                                ForEach(due.prefix(10)) { l in BizLeadRow(lead: l, showDue: true) }
                            }
                        }
                        GlassBox {
                            VStack(alignment: .leading, spacing: 8) {
                                header("Hot leads", "flame.fill")
                                let hot = crm.leads.filter { $0.isOpen && $0.priority.lowercased() == "hot" }
                                if hot.isEmpty { empty("Mark a lead hot: open it, or say “mark Ali as hot”.") }
                                ForEach(hot.prefix(8)) { l in BizLeadRow(lead: l) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        GlassBox {
                            VStack(alignment: .leading, spacing: 8) {
                                header("Who isn't following up", "person.fill.questionmark")
                                if crm.team.isEmpty { empty("Add your team in the Team tab to see this.") }
                                ForEach(crm.reports()) { r in
                                    HStack {
                                        Text(r.name).font(.system(size: 12.5, weight: .semibold))
                                        Spacer()
                                        if r.overdue > 0 { Pill(text: "\(r.overdue) overdue", color: Biz.red) } else { Pill(text: "on track", color: Biz.green) }
                                    }
                                }
                            }
                        }
                        GlassBox {
                            VStack(alignment: .leading, spacing: 8) {
                                header("Owner's daily summary", "doc.text.fill")
                                Text(crm.summary()).font(.system(size: 11.5, design: .rounded)).foregroundColor(.white.opacity(0.85))
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                HStack {
                                    PrimaryButton(title: sending ? "Sending…" : "Send to my WhatsApp", icon: "paperplane.fill") {
                                        sending = true
                                        Task { nav.say(await crm.sendSummaryNow()); sending = false }
                                    }
                                    SoftButton(title: "Copy", icon: "doc.on.doc") {
                                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(crm.summary(), forType: .string); nav.say("Copied")
                                    }
                                }
                                Text(crm.isOn(.ownerSummary) ? "Sent by itself every day at \(crm.summaryHour):00." : "Turn on the daily send in Automations.")
                                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
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
        GlassBox(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundColor(c)
                Text(v).font(.system(size: 26, weight: .heavy, design: .rounded))
                Text(t).font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6))
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private func header(_ t: String, _ icon: String) -> some View {
    Label(t, systemImage: icon).font(.system(size: 13, weight: .heavy, design: .rounded))
}
private func empty(_ t: String) -> some View {
    Text(t).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.5))
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
                    Text(lead.display).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text([lead.interest, lead.area, lead.budget].filter { !$0.isEmpty }.joined(separator: " · ").ifEmpty(lead.lastMessage))
                        .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.55)).lineLimit(1)
                }
                Spacer()
                if showDue && lead.overdue { Pill(text: "overdue", color: Biz.red) }
                if !lead.assigned.isEmpty { Text(lead.assigned).font(.system(size: 10)).foregroundColor(.white.opacity(0.5)) }
                Pill(text: lead.stage, color: Biz.stageColor(lead.stage))
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct Avatar: View {
    let lead: CRMLead; var size: CGFloat = 34
    var body: some View {
        let c = Biz.stageColor(lead.stage)
        Text(lead.initials.isEmpty ? "?" : lead.initials).font(.system(size: size * 0.36, weight: .heavy, design: .rounded))
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

    private var list: [CRMLead] {
        var l = crm.leads
        switch filter {
        case "Needs reply": l = l.filter { crm.drafts[$0.key] != nil }
        case "WhatsApp": l = l.filter { $0.source.lowercased().contains("whatsapp") }
        case "Mine due": l = l.filter(\.dueToday)
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
                Picker("", selection: $filter) { ForEach(["All", "Needs reply", "WhatsApp", "Mine due"], id: \.self) { Text($0) } }
                    .pickerStyle(.segmented).labelsHidden()
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(list) { l in
                            Button { nav.selected = l.key } label: {
                                HStack(spacing: 10) {
                                    Avatar(lead: l)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(l.display).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
                                            Spacer()
                                            Text(shortTime(l.lastMessageAt.isEmpty ? l.added : l.lastMessageAt)).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45))
                                        }
                                        Text(l.lastMessage.isEmpty ? (l.interest.isEmpty ? l.source : l.interest) : l.lastMessage)
                                            .font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                                        HStack(spacing: 4) {
                                            if crm.drafts[l.key] != nil { Pill(text: "reply ready", color: Biz.pink, filled: true) }
                                            Pill(text: l.stage, color: Biz.stageColor(l.stage))
                                            if !l.assigned.isEmpty { Pill(text: l.assigned, color: .white.opacity(0.7)) }
                                        }
                                    }
                                }
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(nav.selected == l.key ? Color.white.opacity(0.12) : .clear))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if list.isEmpty {
                            empty(filter == "Needs reply" ? "No replies waiting." : "No leads yet. Open WhatsApp on this Mac — new chats appear here by themselves. Or press “Add lead”.")
                                .padding(.top, 30).multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .frame(width: 330).padding(.leading, 18).padding(.bottom, 14)
            Divider().overlay(Biz.stroke).padding(.horizontal, 10)
            if let key = nav.selected, let l = crm.leads.first(where: { $0.key == key }) {
                BizLeadDetail(lead: l).id(l.key)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill").font(.system(size: 40)).foregroundColor(.white.opacity(0.3))
                    Text("Pick a chat").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.6))
                    Text(crm.whatsAppStatus).font(.system(size: 11)).foregroundColor(.white.opacity(0.45))
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
                        Text(lead.display).font(.system(size: 19, weight: .heavy, design: .rounded))
                        Text([lead.phone, lead.source].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.6)).textSelection(.enabled)
                    }
                    Spacer()
                    SoftButton(title: "Edit", icon: "pencil") { editing = true }
                    SoftButton(title: "WhatsApp", icon: "message.fill") { openChat() }
                }
                // Stage + priority + owner
                HStack(spacing: 8) {
                    Menu {
                        ForEach(crm.stages, id: \.self) { s in Button(s) { crm.setStage(lead.key, s) } }
                    } label: { Pill(text: "Stage: \(lead.stage) ▾", color: Biz.stageColor(lead.stage)) }.menuStyle(.borderlessButton).fixedSize()
                    Menu {
                        ForEach(["Hot", "Warm", "Cold", ""], id: \.self) { p in Button(p.isEmpty ? "None" : p) { var l = lead; l.priority = p; crm.update(l) } }
                    } label: { Pill(text: lead.priority.isEmpty ? "Priority ▾" : "\(lead.priority) ▾", color: lead.priority == "Hot" ? Biz.red : Biz.amber) }.menuStyle(.borderlessButton).fixedSize()
                    Menu {
                        Button("Nobody") { crm.assign(lead.key, to: "") }
                        ForEach(crm.team) { s in Button(s.name) { crm.assign(lead.key, to: s.name) } }
                        if crm.team.isEmpty { Button("Add team members in Team…") { nav.tab = .team } }
                    } label: { Pill(text: lead.assigned.isEmpty ? "Assign to… ▾" : "👤 \(lead.assigned) ▾", color: .white.opacity(0.8)) }.menuStyle(.borderlessButton).fixedSize()
                    Spacer()
                }
                // What they want
                GlassBox {
                    HStack(alignment: .top, spacing: 18) {
                        fact("Wants", lead.interest); fact("Area", lead.area); fact("Budget", lead.budget)
                        fact("Added", lead.added); fact("Last contact", lead.lastContact)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Follow up").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.5))
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
                                Text(lead.lastMessage).font(.system(size: 12.5)).padding(10)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                                Spacer(minLength: 60)
                            }
                        } else { empty("No message yet.") }
                        if lead.lastMessage.hasPrefix("🎤") || lead.notes.contains("voice note") {
                            SoftButton(title: "Write out a voice note from \(lead.display.split(separator: " ").first.map(String.init) ?? "them")", icon: "waveform") { BusinessFiles.pickVoiceNote(for: lead.key) }
                        }
                        TextEditor(text: $reply).font(.system(size: 12.5)).scrollContentBackground(.hidden)
                            .frame(minHeight: 70).padding(8)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.3)))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Biz.stroke))
                        HStack {
                            PrimaryButton(title: working ? "Sending…" : "Send on WhatsApp", icon: "paperplane.fill") {
                                guard !reply.isEmpty, !working else { return }
                                working = true
                                Task { nav.say(await crm.send(lead.key, reply)); reply = ""; working = false }
                            }
                            SoftButton(title: "Write a reply for me", icon: "sparkles") {
                                working = true
                                Task { reply = await crm.draftReply(for: lead, incoming: lead.lastMessage, first: lead.stage == "New"); working = false }
                            }
                            Spacer()
                            if crm.drafts[lead.key] != nil { Button("Skip") { crm.drafts[lead.key] = nil; reply = "" }.buttonStyle(.plain).foregroundColor(.white.opacity(0.6)) }
                        }
                    }
                }
                // Notes
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        header("Notes", "note.text")
                        if !lead.notes.isEmpty {
                            ForEach(lead.notes.components(separatedBy: " | "), id: \.self) { n in
                                Text("• " + n).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.8)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        HStack {
                            TextField("Add a note…", text: $note).textFieldStyle(.roundedBorder)
                                .onSubmit(addNote)
                            SoftButton(title: "Add", action: addNote)
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
                                Text("\(a.date) \(a.time) · \(a.staff) · \(a.kind) \(a.detail)").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6))
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
            Text(t).font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.5))
            Text(v.isEmpty ? "—" : v).font(.system(size: 12.5, weight: .semibold)).lineLimit(2)
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
            Text(lead == nil ? "New lead" : "Edit \(lead!.display)").font(.system(size: 17, weight: .heavy, design: .rounded))
            Form {
                TextField("Name", text: $l.name)
                TextField("Phone (WhatsApp)", text: $l.phone)
                TextField("Source (Facebook, Zameen, walk-in…)", text: $l.source)
                TextField(crm.isEstate ? "Wants (e.g. 10 marla house)" : "Service", text: $l.interest)
                TextField("Area", text: $l.area)
                TextField("Budget", text: $l.budget)
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
                                               "status": l.status, "assigned": l.assigned, "notes": l.notes])
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
                Text("Drag a card to move it.").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
            }.padding(.horizontal, 22)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(crm.stages, id: \.self) { stage in
                        let cards = crm.leads.filter { $0.stage == stage && (who == "Everyone" || $0.assigned == who) && matches($0) }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle().fill(Biz.stageColor(stage)).frame(width: 8, height: 8)
                                Text(stage).font(.system(size: 13, weight: .heavy, design: .rounded))
                                Spacer()
                                Text("\(cards.count)").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5))
                            }
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(cards) { l in card(l).draggable(l.key) }
                                    if cards.isEmpty { empty("—").frame(maxWidth: .infinity).padding(.vertical, 20) }
                                }
                            }
                        }
                        .padding(10).frame(width: 220).frame(maxHeight: .infinity, alignment: .top)
                        .background(RoundedRectangle(cornerRadius: 16).fill(target == stage ? Biz.stageColor(stage).opacity(0.18) : Color.white.opacity(0.05)))
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
                    Text(l.display).font(.system(size: 12.5, weight: .bold)).lineLimit(1)
                    Spacer()
                    if l.priority.lowercased() == "hot" { Text("🔥") }
                }
                if !l.interest.isEmpty || !l.area.isEmpty { Text([l.interest, l.area].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.65)).lineLimit(2) }
                HStack(spacing: 4) {
                    if !l.budget.isEmpty { Pill(text: l.budget, color: Biz.green) }
                    if l.overdue { Pill(text: "overdue", color: Biz.red) }
                    Spacer()
                    if !l.assigned.isEmpty { Text(l.assigned).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.5)) }
                }
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Biz.stroke, lineWidth: 0.6))
        }.buttonStyle(.plain)
    }
}

// MARK: - Team

struct BizTeamView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    @ObservedObject private var nav = BizNav.shared
    @State private var name = "", phone = "", role = "Agent"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GlassBox {
                    VStack(alignment: .leading, spacing: 10) {
                        header("Add a team member", "person.badge.plus")
                        HStack {
                            TextField("Name", text: $name).textFieldStyle(.roundedBorder)
                            TextField("WhatsApp number", text: $phone).textFieldStyle(.roundedBorder)
                            Picker("", selection: $role) { ForEach(["Agent", "Manager", "Receptionist", "Stylist"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 130)
                            PrimaryButton(title: "Add", icon: "plus") {
                                crm.addStaff(name: name, phone: phone, role: role); name = ""; phone = ""
                            }
                        }
                        Toggle("Share new leads among the team (round robin)", isOn: Binding(get: { crm.isOn(.roundRobin) }, set: { crm.set(.roundRobin, $0) }))
                        Text("Each person gets a PIN. With the always-on server they open the team page on their phone, see only their leads and update them.")
                            .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.5))
                    }
                }
                GlassBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            header("Team report", "chart.bar.fill")
                            Spacer()
                            let un = crm.leads.filter { $0.isOpen && $0.assigned.isEmpty }
                            if !un.isEmpty, !crm.team.isEmpty {
                                SoftButton(title: "Share \(un.count) unassigned", icon: "arrow.triangle.branch") {
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
                            }.font(.system(size: 10.5, weight: .bold)).foregroundColor(.white.opacity(0.5))
                            ForEach(crm.reports()) { r in
                                let s = crm.team.first { $0.name == r.name }
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.name).font(.system(size: 12.5, weight: .bold))
                                        Text("\(s?.role ?? "") · PIN \(s?.pin ?? "")").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45))
                                    }.frame(width: 150, alignment: .leading)
                                    ForEach(Array([r.assigned, r.open, r.newToday, r.contacted7, r.won].enumerated()), id: \.offset) { _, v in Text("\(v)").frame(width: 80) }
                                    Group { if r.overdue > 0 { Pill(text: "\(r.overdue)", color: Biz.red, filled: true) } else { Pill(text: "0", color: Biz.green) } }.frame(width: 80)
                                    Spacer()
                                    Menu {
                                        Button("Show their leads") { nav.search = ""; nav.tab = .pipeline }
                                        if let s { Button("Remove \(s.name)", role: .destructive) { crm.removeStaff(s) } }
                                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).fixedSize()
                                }
                                .font(.system(size: 12.5, design: .rounded))
                                if !r.overdueNames.isEmpty {
                                    Text("Overdue: " + r.overdueNames.joined(separator: ", ")).font(.system(size: 10.5)).foregroundColor(Biz.red.opacity(0.85)).padding(.leading, 4)
                                }
                                Divider().overlay(Biz.stroke)
                            }
                        }
                    }
                }
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }
    }
}

// MARK: - Automations

struct BizAutomationsView: View {
    @ObservedObject private var crm = ZuffiCRM.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                        }.font(.system(size: 12))
                    }
                }
                ForEach(ZuffiCRM.Auto.allCases) { a in
                    GlassBox(padding: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: icon(a)).font(.system(size: 16)).foregroundColor(Biz.amber).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(a.title).font(.system(size: 13, weight: .bold, design: .rounded))
                                Text(a.detail).font(.system(size: 11)).foregroundColor(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
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
                    .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.45))
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }
    }
    private func icon(_ a: ZuffiCRM.Auto) -> String {
        switch a {
        case .watchWhatsApp: return "message.badge.filled.fill"
        case .draftReplies: return "text.bubble.fill"
        case .autoReply: return "paperplane.fill"
        case .voiceNotes: return "waveform"
        case .leadExports: return "square.and.arrow.down.fill"
        case .roundRobin: return "arrow.triangle.2.circlepath"
        case .quietFollowUp: return "hourglass"
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
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { header("1 · WhatsApp on this Mac", "laptopcomputer"); Spacer(); Pill(text: "works now", color: Biz.green) }
                        Text("Zuffi reads new chats in the WhatsApp app on this Mac, makes them leads and writes replies. Nothing extra to set up — but it only works while the Mac is awake and WhatsApp is open.")
                            .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                        check("WhatsApp app open", NSWorkspace.shared.runningApplications.contains(where: WhatsAppAgent.isWhatsApp))
                        check("Accessibility allowed for Zuffi", AXIsProcessTrusted())
                        check("Turning chats into leads", crm.isOn(.watchWhatsApp))
                        HStack {
                            Text(crm.whatsAppStatus + (crm.lastWhatsAppCheck.map { " · \(ZuffiPA.hm($0))" } ?? "")).font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                            Spacer()
                            SoftButton(title: "Check now", icon: "arrow.clockwise") { Task { await crm.watchWhatsApp() } }
                            if !AXIsProcessTrusted() { SoftButton(title: "Allow Accessibility") { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) } }
                        }
                    }
                }
                GlassBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { header("2 · Always-on (WhatsApp Business API + Coexistence)", "antenna.radiowaves.left.and.right"); Spacer(); Pill(text: "best for a business", color: Biz.amber) }
                        Text("Replies within seconds even when the Mac is off. The business keeps using the WhatsApp Business app on the phone with the same number — chats show in both. Voice notes are written out automatically, Facebook / Instagram lead forms arrive instantly, and each team member gets their own page.")
                            .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 4) {
                            step("1", "Set up the Zuffi server (one time) — see server/README.md: Cloudflare, free plan is enough.")
                            step("2", "Create a Meta business app and add WhatsApp. Connect the business's number using “WhatsApp Business app number” (Coexistence) and scan the QR code with the phone.")
                            step("3", "Paste the server address and the admin key below, then press Test.")
                        }
                        HStack {
                            TextField("Server address, e.g. https://zuffi-wa.yourname.workers.dev", text: $crm.serverURL).textFieldStyle(.roundedBorder)
                            SecureField("Admin key", text: $key).textFieldStyle(.roundedBorder).frame(width: 200)
                            PrimaryButton(title: "Test") {
                                let v = key.trimmingCharacters(in: .whitespaces)
                                if v.isEmpty { KeychainStore.shared.remove("zuffi-server-key") } else { KeychainStore.shared.set("zuffi-server-key", value: v) }
                                Task { await crm.testServer(); if crm.serverStatus.hasPrefix("Connected") { await crm.pushTeam(); await crm.pushLeads() } }
                            }
                        }
                        if !crm.serverStatus.isEmpty { Text(crm.serverStatus).font(.system(size: 11.5, weight: .semibold)).foregroundColor(crm.serverStatus.hasPrefix("Connected") ? Biz.green : Biz.amber) }
                        Text("Costs from Meta: replies within 24 hours of a client's message are free; messages you start (reminders, offers) are charged per message.")
                            .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.45))
                    }
                }
                GlassBox {
                    VStack(alignment: .leading, spacing: 6) {
                        header("Leads from ads and portals", "megaphone.fill")
                        Text("Facebook / Instagram lead forms: with the server they arrive instantly. Without it, download them from Meta Leads Center into Downloads (or drop the file here) — Zuffi adds them within a minute. Zameen, Graana, OLX and Google Forms files work the same way.")
                            .font(.system(size: 11.5)).foregroundColor(.white.opacity(0.7)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }
    }
    private func check(_ t: String, _ ok: Bool) -> some View {
        Label(t, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle").font(.system(size: 12)).foregroundColor(ok ? Biz.green : Biz.red)
    }
    private func step(_ n: String, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(n).font(.system(size: 11, weight: .heavy)).frame(width: 20, height: 20).background(Circle().fill(Color.white.opacity(0.12)))
            Text(t).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
