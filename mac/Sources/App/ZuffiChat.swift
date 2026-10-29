import SwiftUI
import AppKit
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Chat: its own line under the notch, and the conversation below it
//
//   ╭──────────────────────────────────────────────╮
//   │ 📎  Ask Zuffi anything…          🎤  ■   ✕  │   ← the line (type, add a file/picture, talk, stop, close)
//   ╰──────────────────────────────────────────────╯
//   ╭──────────────────────────────────────────────╮
//   │ ‹ Conversation                       👍  ⤢  │   ← appears once you've asked something
//   │                       Hey Zuffi, how are you?│
//   │ Reading your message…                        │
//   ╰──────────────────────────────────────────────╯
// Separate from the main Zuffi panel; drag it anywhere; ✕ or Esc closes it.
// =====================================================================

final class ChatKeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { MainActor.assumeIsolated { ZuffiChat.shared.close() } }
}

@MainActor
final class ZuffiChat: ObservableObject {
    static let shared = ZuffiChat()
    @Published var draft = ""
    /// Who you're talking to: Zuffi (everyday, no business data), Nik (your business manager) or one agent.
    enum Who: Equatable { case zuffi, nik, agent(String) }
    @Published var who: Who = .zuffi {
        didSet {
            switch who {
            case .agent(let id): ZuffiTeam.shared.activeIDs = [id]
            default: ZuffiTeam.shared.activeIDs = []
            }
            ZuffiTeam.shared.awaiting = nil
        }
    }
    var whoTitle: String {
        switch who {
        case .zuffi: return "Zuffi"
        case .nik: return "Nik · your business manager"
        case .agent(let id): return ZuffiTeam.shared.agent(id)?.name ?? "Agent"
        }
    }
    @Published var focusTick = 0
    private var panel: ChatKeyPanel?
    /// The list of past chats, shown at the side of the chat.
    @Published var showHistory = false { didSet { if showHistory != oldValue { resizeForHistory() } } }
    var width: CGFloat { showHistory ? 700 : 460 }
    let height: CGFloat = 580
    private func resizeForHistory() {
        guard let p = panel else { return }
        let f = p.frame
        p.setFrame(NSRect(x: f.midX - width / 2, y: f.minY, width: width, height: f.height), display: true, animate: true)
    }
    /// Open one of your past chats right here in the chat.
    func openPast(_ c: ChatArchive.Chat) {
        ChatArchive.shared.open(c)
        open()
    }

    var isOpen: Bool { panel?.isVisible == true }

    /// macOS selects all the text when a field gets focus — with a prefilled line that looked like a white-on-peach block.
    /// Put the cursor at the end instead, ready to type.
    func caretToEnd() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            MainActor.assumeIsolated {
                if let tv = ZuffiChat.shared.panel?.firstResponder as? NSTextView {
                    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
                    tv.selectedTextAttributes = [.backgroundColor: NSColor(white: 1, alpha: 0.22), .foregroundColor: NSColor.white]
                }
            }
        }
    }

    /// Open the chat and send this right away (used by "Give a task").
    func ask(_ q: String) {
        open()
        if ZuffiPlan.shared.isLocked { return }
        let st = AppState.shared
        st.chatHistory.append(ChatMessage(role: .user, content: q))
        st.stateOverride = .thinking
        Task { await AIService.shared.chat(query: q, context: nil, state: st) }
    }

    /// Ask from the dashboard's chat bar (the answer shows there, no chat window).
    func askInline(_ q: String) {
        if ZuffiPlan.shared.isLocked { ZuffiPlan.shared.openAccount(); return }
        let st = AppState.shared
        st.chatHistory.append(ChatMessage(role: .user, content: q))
        st.stateOverride = .thinking
        Task { await AIService.shared.chat(query: q, context: nil, state: st) }
    }

    func open(prefill: String = "") {
        if ZuffiPlan.shared.isLocked { ZuffiPlan.shared.openAccount(); return }   // trial over: choose a plan first
        if !prefill.isEmpty { draft = prefill }
        AppState.shared.unreadReplies = 0
        // fold the main panel away — chat lives on its own
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
        let p = panel ?? make()
        panel = p
        if !p.isVisible {
            let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? NSScreen.screens[0]
            let h: CGFloat = height
            let top = screen.frame.maxY - max(AppState.shared.notchHeight, 24) - 8
            var origin = NSPoint(x: screen.frame.midX - width / 2, y: top - h)
            if let s = UserDefaults.standard.string(forKey: "chatOrigin"), !s.isEmpty {
                let o = NSPointFromString(s)
                if NSScreen.screens.contains(where: { $0.frame.contains(NSPoint(x: o.x + 40, y: o.y + h - 20)) }) { origin = o }
            }
            p.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: h)), display: true)
            p.alphaValue = 0
            p.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in ctx.duration = 0.18; p.animator().alphaValue = 1 }
            SoundEngine.shared.play("open")
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKey()
        focusTick += 1
    }

    func close() {
        guard let p = panel, p.isVisible else { return }
        UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "chatOrigin")
        NSAnimationContext.runAnimationGroup({ ctx in ctx.duration = 0.15; p.animator().alphaValue = 0 }, completionHandler: {
            MainActor.assumeIsolated { ZuffiChat.shared.panel?.orderOut(nil) }
        })
        SoundEngine.shared.play("close")
    }

    func toggle() { isOpen ? close() : open() }

    func moveBy(_ dx: CGFloat, _ dy: CGFloat) {
        guard let p = panel else { return }
        p.setFrameOrigin(NSPoint(x: p.frame.minX + dx, y: p.frame.minY + dy))
    }
    func savePosition() { if let p = panel { UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "chatOrigin") } }

    private func make() -> ChatKeyPanel {
        let p = ChatKeyPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.appearance = NSAppearance(named: .darkAqua)     // the chat is dark: icons, placeholder and menus must be light
        let host = NSHostingView(rootView: ZuffiChatView(state: AppState.shared, chat: self).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        return p
    }
}

struct ZuffiChatView: View {
    @ObservedObject var state: AppState
    @ObservedObject var chat: ZuffiChat
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var archive = ChatArchive.shared
    @FocusState private var focused: Bool
    @State private var sentAt: Date?
    @State private var meta = ""
    @State private var liked: Set<UUID> = []
    @State private var dragLast: NSPoint?
    @State private var search = ""

    private var thinking: Bool { state.stateOverride != nil }
    private var listening: Bool { voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) }
    private let ink = Color(hex: "#0B0A0E"), field = Color(hex: "#16141B"), soft = Color(hex: "#9E99AC")

    var body: some View {
        HStack(spacing: 0) {
            if chat.showHistory {
                historyPane.frame(width: 240)
                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            }
            VStack(spacing: 0) {
                header
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                if state.chatHistory.isEmpty && !thinking { welcome } else { conversation }
                composer
            }
        }
        .frame(width: chat.width, height: chat.height)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(ink))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: chat.showHistory)
        .onChange(of: chat.focusTick) { _, _ in focused = true; ZuffiChat.shared.caretToEnd() }
        .onAppear { focused = true; ZuffiChat.shared.caretToEnd() }
        .onChange(of: state.chatHistory.count) { _, _ in
            if let start = sentAt, let last = state.chatHistory.last, last.role == .assistant {
                meta = String(format: "%.0fs", max(0.1, Date().timeIntervalSince(start)))
                sentAt = nil
            }
        }
    }

    // MARK: header — who you're talking to

    private var header: some View {
        HStack(spacing: 10) {
            circleButton(chat.showHistory ? "sidebar.left" : "clock.arrow.circlepath", help: chat.showHistory ? "Hide your chats" : "Your past chats") { chat.showHistory.toggle() }
            Menu {
                Button { chat.who = .zuffi } label: { Label("Zuffi — everyday help", systemImage: "sparkles") }
                if ZuffiFocus.agents, !ZuffiPlan.shared.isPersonal {
                    Button { chat.who = .nik } label: { Label("Nik — your business manager", systemImage: "person.crop.circle.badge.checkmark") }
                }
                Divider()
                ForEach(ZuffiTeam.shared.chatAgents) { a in Button { chat.who = .agent(a.id) } label: { Text(AgentEdits.name(a)) } }
                Divider()
                ForEach(ZuffiTeam.shared.agentGroups, id: \.0) { g in
                    Menu(g.0) { ForEach(g.1) { a in Button(a.name) { chat.who = .agent(a.id) } } }
                }
            } label: {
                HStack(spacing: 10) {
                    Group {
                        if case .agent(let id) = chat.who, let a = ZuffiTeam.shared.agent(id) { RobotFace(agent: a, size: 26) }
                        else { LiveBunnyFace(size: 34) }
                    }
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(chat.whoTitle).font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundColor(soft)
                        }
                        HStack(spacing: 4) {
                            Circle().fill(thinking ? Color(hex: "#F5B963") : Color(hex: "#7CE0A3")).frame(width: 6, height: 6)
                            Text(thinking ? "thinking…" : listening ? "listening…" : voice.speaking ? "talking…" : "ready")
                                .font(.system(size: 11)).foregroundColor(thinking ? Color(hex: "#F5B963") : Color(hex: "#7CE0A3"))
                        }
                    }
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Choose who you're talking to")
            Spacer(minLength: 0)
            if !state.chatHistory.isEmpty { circleButton("square.and.pencil", help: "New chat") { state.newChat() } }
            circleButton("xmark", help: "Close (Esc)") { chat.close() }
        }
        .padding(.horizontal, 16).frame(height: 62)
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    private func circleButton(_ icon: String, help: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                .frame(width: 32, height: 32).background(Circle().fill(Color.white.opacity(0.07)))
        }.buttonStyle(.plain).help(help)
    }

    // MARK: past chats — pick one and it opens right here

    private var historyPane: some View {
        let today = Calendar.current.startOfDay(for: Date())
        let list = archive.chats.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.messages.contains { ($0["content"] ?? "").localizedCaseInsensitiveContains(search) } }
        let groups: [(String, [ChatArchive.Chat])] = [
            ("TODAY", list.filter { $0.date >= today }),
            ("YESTERDAY", list.filter { $0.date < today && $0.date >= today.addingTimeInterval(-86400) }),
            ("EARLIER", list.filter { $0.date < today.addingTimeInterval(-86400) }),
        ].filter { !$0.1.isEmpty }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Chats").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { state.newChat(); focused = true } label: {
                    Label("New", systemImage: "plus").font(.system(size: 11.5, weight: .semibold)).foregroundColor(Color(hex: "#141218"))
                        .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color(hex: "#F2F1F6")))
                }.buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundColor(soft)
                TextField("", text: $search, prompt: Text("Search chats").foregroundColor(soft.opacity(0.8))).textFieldStyle(.plain).font(.system(size: 12)).foregroundColor(.white)
            }
            .padding(.horizontal, 10).frame(height: 32).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if !state.chatHistory.isEmpty {
                        pastRow(title: state.chatHistory.first { $0.role == .user }?.content ?? "This chat", sub: "Open now", active: true) {}
                    }
                    if groups.isEmpty && state.chatHistory.isEmpty {
                        Text(search.isEmpty ? "Your chats will be kept here." : "No chats match.").font(.system(size: 12)).foregroundColor(soft).padding(.top, 8)
                    }
                    ForEach(groups, id: \.0) { g in
                        Text(g.0).font(.system(size: 10, weight: .bold)).tracking(1).foregroundColor(Color(hex: "#6F6A80")).padding(.top, 10).padding(.leading, 6)
                        ForEach(g.1) { c in
                            pastRow(title: c.title, sub: (c.messages.last?["content"] ?? "").replacingOccurrences(of: "\n", with: " "), active: false) { chat.openPast(c) }
                                .contextMenu { Button("Delete", role: .destructive) { archive.delete(c) } }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "#08070B"))
    }

    private func pastRow(title: String, sub: String, active: Bool, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: active ? .semibold : .medium)).foregroundColor(.white).lineLimit(1)
                Text(sub).font(.system(size: 11)).foregroundColor(soft).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(active ? Color(hex: "#8E7CFF").opacity(0.2) : Color.clear))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: empty — a friendly start

    private var welcome: some View {
        let first = (ZuffiPlan.shared.profile["name"] ?? "").components(separatedBy: " ").first ?? ""
        return VStack(spacing: 12) {
            Spacer(minLength: 0)
            LiveBunnyFace(size: 120)
            Text(first.isEmpty ? "Hi, what can I do?" : "Hi \(first), what can I do?").font(.system(size: 20, weight: .bold)).foregroundColor(.white)
            Text("Ask anything, add a file, or hold Z to talk.").font(.system(size: 13)).foregroundColor(soft)
            VStack(spacing: 8) {
                suggestion("Explain what's on my screen") { Task { await Assistant.run("what's on my screen", spoken: true) } }
                suggestion("Write a polite reply to a customer") { chat.draft = "Write a polite reply to a customer who asked: "; focused = true; ZuffiChat.shared.caretToEnd() }
                suggestion("Summarise a file for me") { attach(images: false) }
            }
            .padding(.top, 6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func suggestion(_ t: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack {
                Text(t).font(.system(size: 13)).foregroundColor(.white.opacity(0.92))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundColor(soft)
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(field))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    // MARK: the conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(state.chatHistory) { m in bubble(m).id(m.id) }
                    if thinking {
                        HStack(spacing: 10) {
                            LiveBunnyFace(size: 28).frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            TypingDotsView()
                        }.id("typing")
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 18)
            }
            .onChange(of: state.chatHistory.count) { _, _ in
                if let last = state.chatHistory.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            .onChange(of: thinking) { _, t in if t { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
            .onAppear { if let last = state.chatHistory.last { proxy.scrollTo(last.id, anchor: .bottom) } }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        if m.role == .user {
            HStack {
                Spacer(minLength: 70)
                Text(m.content).font(.system(size: 13.5)).foregroundColor(Color(hex: "#141218"))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(UnevenRoundedRectangle(cornerRadii: .init(topLeading: 18, bottomLeading: 18, bottomTrailing: 6, topTrailing: 18), style: .continuous).fill(Color(hex: "#F2F1F6")))
                    .textSelection(.enabled)
                    .help(m.at.formatted(date: .omitted, time: .shortened))
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if case .agent(let id) = chat.who, let a = ZuffiTeam.shared.agent(id) { RobotFace(agent: a, size: 22) }
                    else { LiveBunnyFace(size: 28) }
                }
                .frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    ChatRichText(text: m.content).foregroundColor(Color(hex: "#ECEAF2"))
                    HStack(spacing: 14) {
                        action("Copy", "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.content, forType: .string) }
                        action("Listen", "speaker.wave.2") { VoiceEngine.shared.speak(m.content) }
                        action("Save", "square.and.arrow.down") { ChatRichText.save(m.content) }
                        if m.id == state.chatHistory.last?.id {
                            Button { liked.insert(m.id) } label: { Image(systemName: liked.contains(m.id) ? "hand.thumbsup.fill" : "hand.thumbsup").font(.system(size: 11)) }
                                .buttonStyle(.plain).foregroundColor(soft).help("Good answer")
                            if !meta.isEmpty { Text(meta).font(.system(size: 10.5)).foregroundColor(soft.opacity(0.7)) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func action(_ t: String, _ icon: String, _ go: @escaping () -> Void) -> some View {
        Button(action: go) { Label(t, systemImage: icon).font(.system(size: 11, weight: .medium)) }
            .buttonStyle(.plain).foregroundColor(soft)
    }

    // MARK: the composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if case .file(let name, _)? = state.promptContext {
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill").font(.system(size: 10))
                    Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Button { state.promptContext = nil } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
                }
                .foregroundColor(.white).padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(Color.white.opacity(0.1)))
            }
            HStack(spacing: 8) {
                Menu {
                    Button { attach(images: false) } label: { Label("Add a file (PDF, Excel, Word…)", systemImage: "paperclip") }
                    Button { attach(images: true) } label: { Label("Add a picture", systemImage: "photo") }
                    Button { Task { await Assistant.run("what's on my screen", spoken: true) } } label: { Label("Ask about my screen", systemImage: "eye") }
                } label: {
                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold)).foregroundColor(Color(hex: "#C9C3DA")).frame(width: 26, height: 26)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                if listening {
                    WaveBars().frame(width: 22, height: 14)
                    Text(voice.heard.isEmpty ? "Listening…" : "“\(voice.heard)”").font(.system(size: 13.5, weight: .medium)).foregroundColor(.white).lineLimit(1)
                    Spacer(minLength: 0)
                } else {
                    TextField("", text: $chat.draft, prompt: Text(state.chatHistory.isEmpty ? "Ask Zuffi anything…" : "Ask a follow-up…").foregroundColor(Color(hex: "#77728A")))
                        .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(.white)
                        .focused($focused).onSubmit(send)
                }
                ProviderMenu(state: state, tint: .white)
                Button { VoiceEngine.shared.setMic(!voice.micEnabled) } label: {
                    Image(systemName: voice.micEnabled ? "mic.fill" : "mic.slash.fill").font(.system(size: 11, weight: .bold))
                        .foregroundColor(voice.micEnabled ? Color(hex: "#7CE0A3") : Color(hex: "#FF7A7A"))
                        .frame(width: 28, height: 28).background(Circle().fill((voice.micEnabled ? Color(hex: "#7CE0A3") : Color(hex: "#FF7A7A")).opacity(0.14)))
                }.buttonStyle(.plain).help(voice.micEnabled ? "Mic on — click to turn off" : "Mic off — click to turn on")
                if thinking || voice.speaking || listening {
                    Button {
                        VoiceEngine.shared.stopSpeaking()
                        if LiveSession.shared.active { LiveSession.shared.stop("stopped") }
                        state.stateOverride = nil
                    } label: {
                        RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 10, height: 10)
                            .frame(width: 36, height: 36).background(Circle().fill(Color(hex: "#E5484D")))
                    }.buttonStyle(.plain).help("Stop")
                } else if chat.draft.trimmingCharacters(in: .whitespaces).isEmpty && state.promptContext == nil {
                    Button { VoiceEngine.shared.listenOnce() } label: {
                        Image(systemName: "waveform").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: "#141218"))
                            .frame(width: 36, height: 36).background(Circle().fill(Color(hex: "#F2F1F6")))
                    }.buttonStyle(.plain).help("Talk")
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: "#141218"))
                            .frame(width: 36, height: 36).background(Circle().fill(Color(hex: "#F2F1F6")))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.leading, 12).padding(.trailing, 7).frame(height: 52)
            .background(Capsule().fill(field))
            .overlay(Capsule().stroke(Color.white.opacity(focused ? 0.18 : 0.08), lineWidth: 1))
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 14)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                let m = NSEvent.mouseLocation
                if let l = dragLast { chat.moveBy(m.x - l.x, m.y - l.y) }
                dragLast = m
            }
            .onEnded { _ in dragLast = nil; chat.savePosition() }
    }

    private func attach(images: Bool) {
        let p = NSOpenPanel()
        p.allowedContentTypes = images ? [.image] : [.item]
        p.allowsMultipleSelection = false
        guard p.runModal() == .OK, let u = p.url else { return }
        state.promptContext = .file(name: u.lastPathComponent, fileURL: u)
        focused = true
    }

    private func send() {
        let q = chat.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty || state.promptContext != nil else { return }
        chat.draft = ""
        sentAt = Date()
        state.chatHistory.append(ChatMessage(role: .user, content: q.isEmpty ? "Here's a file" : q))
        state.stateOverride = .thinking
        let ctx = state.promptContext
        Task {
            await AIService.shared.chat(query: q, context: ctx, state: state)
            await MainActor.run { focused = true }
        }
    }
}


/// An answer laid out to read easily: paragraphs, headings, bullet and numbered lists, and links as small cards.
struct ChatRichText: View {
    let text: String
    enum Block: Hashable { case para(String), heading(String), bullet(String), number(String, String), link(String, String) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, b in block(b) }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder private func block(_ b: Block) -> some View {
        switch b {
        case .para(let t):
            Text(t).font(.system(size: 14)).lineSpacing(4).foregroundColor(.white.opacity(0.95)).fixedSize(horizontal: false, vertical: true)
        case .heading(let t):
            Text(t).font(.system(size: 14.5, weight: .bold)).foregroundColor(.white).padding(.top, 2)
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Color(hex: "#F5B963")).frame(width: 5, height: 5).offset(y: -2)
                Text(t).font(.system(size: 14)).lineSpacing(3).foregroundColor(.white.opacity(0.95)).fixedSize(horizontal: false, vertical: true)
            }
        case .number(let n, let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(n).font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: "#F5B963")).frame(minWidth: 16, alignment: .trailing)
                Text(t).font(.system(size: 14)).lineSpacing(3).foregroundColor(.white.opacity(0.95)).fixedSize(horizontal: false, vertical: true)
            }
        case .link(let title, let url):
            Button { if let u = URL(string: url) { NSWorkspace.shared.open(u) } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#8FB4FF"))
                        .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.system(size: 12.5, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                        Text(URL(string: url)?.host?.replacingOccurrences(of: "www.", with: "") ?? "").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.5))
                }
                .padding(8).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    static func parse(_ raw: String) -> [Block] {
        var out: [Block] = []
        let urlRE = try? NSRegularExpression(pattern: #"(?:https?|file)://\S+"#)
        for line0 in raw.components(separatedBy: .newlines) {
            var line = line0.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.lowercased() == "links:" || line.lowercased() == "sources:" { out.append(.heading("Sources")); continue }
            // a link line: "• Title — https://…" or just a URL
            let ns = line as NSString
            if let m = urlRE?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let url = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".,)"))
                var title = ns.replacingCharacters(in: m.range, with: "").replacingOccurrences(of: #"^[•\-\*]\s*"#, with: "", options: .regularExpression)
                title = title.trimmingCharacters(in: CharacterSet(charactersIn: " —-:–"))
                if title.count < 120 { out.append(.link(title.isEmpty ? (URL(string: url)?.host ?? "Link") : title, url)); continue }
            }
            line = line.replacingOccurrences(of: "**", with: "")
            if let r = line.range(of: #"^[•\-\*]\s+"#, options: .regularExpression) { out.append(.bullet(String(line[r.upperBound...]))); continue }
            if let r = line.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) {
                out.append(.number(String(line[..<r.upperBound]).trimmingCharacters(in: .whitespaces), String(line[r.upperBound...]))); continue
            }
            if line.hasSuffix(":"), line.count < 60 { out.append(.heading(String(line.dropLast()))); continue }
            // "options: * hair cut * nail * …" written on one line → a list
            let inline = line.components(separatedBy: CharacterSet(charactersIn: "•")).count > 2 ? "•" : (line.components(separatedBy: " * ").count > 2 ? " * " : "")
            if !inline.isEmpty {
                let bits = line.components(separatedBy: inline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if let first = bits.first { out.append(.para(first)) }
                for b in bits.dropFirst() { out.append(.bullet(b)) }
                continue
            }
            out.append(.para(line))
        }
        return out
    }

    /// Save an answer as a text file you choose.
    @MainActor static func save(_ text: String) {
        let p = NSSavePanel()
        p.nameFieldStringValue = "Zuffi answer.txt"
        p.allowedContentTypes = [.plainText]
        if p.runModal() == .OK, let u = p.url { try? text.write(to: u, atomically: true, encoding: .utf8) }
    }
}
