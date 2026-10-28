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
    let width: CGFloat = 460

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
            let h: CGFloat = 520
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
        let p = ChatKeyPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 520),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = false
        p.appearance = NSAppearance(named: .darkAqua)     // the chat is dark: icons, placeholder and menus must be light
        let host = NSHostingView(rootView: ZuffiChatView(state: AppState.shared, chat: self).environment(\.colorScheme, .dark))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 520)
        p.contentView = host
        return p
    }
}

struct ZuffiChatView: View {
    @ObservedObject var state: AppState
    @ObservedObject var chat: ZuffiChat
    @ObservedObject private var voice = VoiceEngine.shared
    @FocusState private var focused: Bool
    @State private var sentAt: Date?
    @State private var meta = ""
    @State private var liked: Set<UUID> = []
    @State private var dragLast: NSPoint?

    private var thinking: Bool { state.stateOverride != nil }
    private var listening: Bool { voice.isListening && (voice.status.hasPrefix("Listening") || voice.pushToTalk) }

    var body: some View {
        VStack(spacing: 10) {
            line
            if !state.chatHistory.isEmpty || thinking {
                conversation.transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer(minLength: 0)
        }
        .frame(width: chat.width, height: 520, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: state.chatHistory.isEmpty)
        .onChange(of: chat.focusTick) { _, _ in focused = true; ZuffiChat.shared.caretToEnd() }
        .onAppear { focused = true; ZuffiChat.shared.caretToEnd() }
        .onChange(of: state.chatHistory.count) { _, _ in
            if let start = sentAt, let last = state.chatHistory.last, last.role == .assistant {
                let secs = max(0.1, Date().timeIntervalSince(start))
                meta = String(format: "%.0fs", secs)
                sentAt = nil
            }
        }
    }

    // MARK: the line

    private var line: some View {
        HStack(spacing: 10) {
            Menu {
                Button { attach(images: false) } label: { Label("Add a file (PDF, Excel, Word…)", systemImage: "paperclip") }
                Button { attach(images: true) } label: { Label("Add a picture", systemImage: "photo") }
                Button { Task { await Assistant.run("what's on my screen", spoken: true) } } label: { Label("Ask about my screen", systemImage: "eye") }
            } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundColor(.white.opacity(0.8))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            if case .file(let name, _)? = state.promptContext {
                HStack(spacing: 4) {
                    Image(systemName: "doc.fill").font(.system(size: 9))
                    Text(name).font(.system(size: 10.5, weight: .semibold)).lineLimit(1)
                    Button { state.promptContext = nil } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
                }
                .padding(.horizontal, 7).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.14)))
                .frame(maxWidth: 140)
            }
            if thinking {
                TypingDotsView()
                Text("Sending…").font(.system(size: 13, weight: .medium)).foregroundColor(.white.opacity(0.8))
                Spacer(minLength: 0)
            } else if listening {
                WaveBars().frame(width: 22, height: 14)
                Text(voice.heard.isEmpty ? "Listening…" : "“\(voice.heard)”").font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundColor(.white.opacity(0.9))
                Spacer(minLength: 0)
            } else {
                TextField(state.chatHistory.isEmpty ? "Ask Zuffi anything…" : "Ask a follow-up…", text: $chat.draft)
                    .textFieldStyle(.plain).font(.system(size: 13.5)).foregroundColor(.white)
                    .focused($focused)
                    .onSubmit(send)
            }
            if !thinking && !listening {
                ModelChip(state: state)
                TeamMenu()
            }
            if thinking || voice.speaking || listening {
                Button {
                    VoiceEngine.shared.stopSpeaking()
                    if LiveSession.shared.active { LiveSession.shared.stop("stopped") }
                    state.stateOverride = nil
                } label: {
                    Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                        .frame(width: 24, height: 24).background(Circle().fill(Color(hex: "#E5484D")))
                }.buttonStyle(.plain).help("Stop")
            } else {
                Button { VoiceEngine.shared.listenOnce() } label: {
                    Image(systemName: VoiceEngine.shared.micEnabled ? "mic.fill" : "mic.slash.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundColor(VoiceEngine.shared.micEnabled ? .white.opacity(0.85) : Color(hex: "#FF8A8F"))
                }.buttonStyle(.plain).help("Talk (turns the mic on if it was off)")
                if !chat.draft.isEmpty {
                    Button(action: send) {
                        Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold)).foregroundColor(Color(hex: "#1A1008"))
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(LinearGradient(colors: [Color(hex: "#FBC56A"), Color(hex: "#F28A3C")], startPoint: .top, endPoint: .bottom)))
                    }.buttonStyle(.plain)
                }
            }
            Button { chat.close() } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundColor(.white.opacity(0.8))
                    .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.12)))
            }.buttonStyle(.plain).help("Close (Esc)")
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(
            ZStack {
                ZuffiSpaceBackground()
                Capsule().fill(Color.black.opacity(0.25))
            }
            .clipShape(Capsule())
        )
        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .gesture(dragGesture)
    }

    // MARK: the conversation card

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { AppState.shared.newChat() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .frame(width: 26, height: 26).background(Circle().fill(Color.white.opacity(0.1)))
                }.buttonStyle(.plain).help("New chat")
                if ZuffiFocus.agents {
                Menu {
                    Button { chat.who = .zuffi } label: { Label("Zuffi — everyday help", systemImage: "sparkles") }
                    if !ZuffiPlan.shared.isPersonal {
                        Button { chat.who = .nik } label: { Label("Nik — your business manager", systemImage: "person.crop.circle.badge.checkmark") }
                    }
                    Divider()
                    ForEach(ZuffiTeam.shared.chatAgents) { a in
                        Button { chat.who = .agent(a.id) } label: { Text(a.name) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text("Talking to").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                        Text(chat.whoTitle).font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.7))
                    }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Choose who you're talking to")
                } else {
                    Text("Zuffi").font(.system(size: 14, weight: .bold, design: .rounded))
                }
                Spacer()
                ProviderMenu(state: state)
                if let last = state.chatHistory.last(where: { $0.role == .assistant }) {
                    Button { liked.insert(last.id) } label: {
                        Image(systemName: liked.contains(last.id) ? "hand.thumbsup.fill" : "hand.thumbsup").font(.system(size: 12))
                    }.buttonStyle(.plain).help("Good answer")
                }
                Button { WebHub.shared.show(tab: "chat") } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11, weight: .bold))
                }.buttonStyle(.plain).help("Open the full chat")
            }
            .foregroundColor(.white.opacity(0.9))
            .contentShape(Rectangle())
            .gesture(dragGesture)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(state.chatHistory) { m in
                            bubble(m).id(m.id)
                            if m.role == .assistant, m.id == state.chatHistory.last?.id, !thinking {
                                HStack(spacing: 8) {
                                    if !meta.isEmpty { Label(meta, systemImage: "clock").font(.system(size: 9.5)).foregroundColor(.white.opacity(0.45)) }
                                    Spacer()
                                    Button("Listen again") { VoiceEngine.shared.speak(m.content) }
                                        .buttonStyle(.plain).font(.system(size: 10.5, weight: .semibold)).foregroundColor(Color(hex: "#F58FA8"))
                                }
                            }
                        }
                        if thinking {
                            HStack(spacing: 6) {
                                Image(systemName: "text.book.closed").font(.system(size: 11)).foregroundColor(.white.opacity(0.6))
                                ShimmeringText("Reading your message…")
                            }.id("typing")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: state.chatHistory.count) { _, _ in
                    if let last = state.chatHistory.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: thinking) { _, t in if t { withAnimation { proxy.scrollTo("typing", anchor: .bottom) } } }
                .onAppear { if let last = state.chatHistory.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
        .padding(14)
        .frame(width: chat.width, height: 440)
        .background(
            ZStack {
                ZuffiSpaceBackground()
                Color.black.opacity(0.28)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
    }

    @ViewBuilder private func bubble(_ m: ChatMessage) -> some View {
        if m.role == .user {
            HStack {
                Spacer(minLength: 50)
                Text(m.content).font(.system(size: 14)).foregroundColor(Color(hex: "#2A1520"))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(0.92)))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ChatRichText(text: m.content)
                HStack(spacing: 14) {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(m.content, forType: .string) } label: {
                        Label("Copy", systemImage: "doc.on.doc").font(.system(size: 11, weight: .semibold))
                    }.buttonStyle(.plain)
                    Button { ChatRichText.save(m.content) } label: {
                        Label("Save", systemImage: "square.and.arrow.down").font(.system(size: 11, weight: .semibold))
                    }.buttonStyle(.plain)
                }
                .foregroundColor(.white.opacity(0.55))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
        }
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
