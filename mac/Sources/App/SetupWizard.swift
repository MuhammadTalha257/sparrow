import SwiftUI
import AppKit
import AVFoundation
import Speech

// =====================================================================
// MARK: - First run: "install and start using"
//
// For people who aren't technical. On the very first launch Zuffi opens a friendly setup:
//   1. Permissions — one button each, with a tick when done.
//   2. A brain — the AI they already have (Claude Code, Codex, ChatGPT/Claude apps), or
//      "Set up free AI for me": Zuffi downloads Ollama and a model that fits this Mac by
//      itself (no Terminal), or a free Gemini key with step-by-step help.
//   3. Done — "say Zuffi…".
// =====================================================================

@MainActor
final class SetupWizard: NSObject, NSWindowDelegate {
    static let shared = SetupWizard()
    private var window: NSWindow?

    static var done: Bool { UserDefaults.standard.bool(forKey: "zuffiSetupDone") }

    func showIfFirstRun() { if !Self.done { DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { MainActor.assumeIsolated { SetupWizard.shared.show() } } } }

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Welcome to Zuffi"
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SetupView(state: AppState.shared) { SetupWizard.shared.finish() })
        w.center()
        w.delegate = self
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func finish() {
        UserDefaults.standard.set(true, forKey: "zuffiSetupDone")
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: "zuffiSetupDone")
        window = nil
    }
}

// MARK: - Free AI on this Mac (Ollama), set up automatically

@MainActor
final class LocalAISetup: ObservableObject {
    static let shared = LocalAISetup()
    @Published var step = ""
    @Published var progress: Double = 0
    @Published var busy = false
    @Published var ready = false
    @Published var failed: String?

    /// A model that fits this Mac's memory.
    static var model: String {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return gb < 9 ? "llama3.2:1b" : gb < 17 ? "llama3.2:3b" : "qwen2.5:7b"
    }

    func start() {
        guard !busy else { return }
        busy = true; failed = nil; ready = false; progress = 0
        Task {
            do {
                try await installOllamaIfNeeded()
                try await waitForServer()
                try await pullModel(Self.model)
                AppState.shared.aiProvider = AIProvider.ollama.rawValue
                UserDefaults.standard.set(AIProvider.ollama.rawValue, forKey: "aiProvider")
                step = "Ready! Zuffi now thinks on your Mac — free and private."
                ready = true
            } catch {
                failed = error.localizedDescription
                appendAppLog("ai.log", "local AI setup failed: \(error.localizedDescription)")
            }
            busy = false
        }
    }

    private var installedApp: URL? {
        for p in ["/Applications/Ollama.app", FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/Ollama.app"]
        where FileManager.default.fileExists(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }

    private func installOllamaIfNeeded() async throws {
        if await serverUp() { return }
        if let app = installedApp {
            step = "Starting the free AI…"
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            return
        }
        step = "Downloading the free AI engine (Ollama, about 200 MB)…"
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("Ollama-darwin.zip")
        try await download(URL(string: "https://ollama.com/download/Ollama-darwin.zip")!, to: zip, share: 0.35)
        step = "Installing…"
        let apps = FileManager.default.isWritableFile(atPath: "/Applications")
            ? URL(fileURLWithPath: "/Applications")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        try? FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
        let ok = await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, apps.path])
        try? FileManager.default.removeItem(at: zip)
        guard ok, let app = installedApp else { throw Self.err("Couldn't install Ollama. You can install it yourself from ollama.com, then press the button again.") }
        step = "Starting the free AI…"
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    private func serverUp() async -> Bool {
        var r = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/version")!); r.timeoutInterval = 2
        return ((try? await URLSession.shared.data(for: r))?.1 as? HTTPURLResponse)?.statusCode == 200
    }

    private func waitForServer() async throws {
        for _ in 0..<60 { if await serverUp() { return }; try? await Task.sleep(nanoseconds: 1_000_000_000) }
        throw Self.err("The free AI didn't start. Open the Ollama app once, then press the button again.")
    }

    private func pullModel(_ name: String) async throws {
        if (await AIService.ollamaModels()).contains(where: { $0.hasPrefix(name.split(separator: ":").first.map(String.init) ?? name) }) { progress = 1; return }
        step = "Downloading Zuffi's brain (\(name))… this can take a few minutes."
        var req = URLRequest(url: URL(string: "http://127.0.0.1:11434/api/pull")!)
        req.httpMethod = "POST"; req.timeoutInterval = 3600
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "stream": true])
        let (bytes, _) = try await URLSession.shared.bytes(for: req)
        for try await line in bytes.lines {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let e = o["error"] as? String { throw Self.err(e) }
            if let total = (o["total"] as? NSNumber)?.doubleValue, total > 0, let done = (o["completed"] as? NSNumber)?.doubleValue {
                progress = 0.35 + 0.65 * min(1, done / total)
            }
            if (o["status"] as? String) == "success" { progress = 1 }
        }
    }

    private func download(_ url: URL, to file: URL, share: Double) async throws {
        let (bytes, resp) = try await URLSession.shared.bytes(from: url)
        let total = Double(resp.expectedContentLength)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let h = try FileHandle(forWritingTo: file)
        defer { try? h.close() }
        var buf = Data(); var got = 0.0
        for try await b in bytes {
            buf.append(b)
            if buf.count >= 1 << 20 { h.write(buf); got += Double(buf.count); buf.removeAll(keepingCapacity: true); if total > 0 { progress = share * got / total } }
        }
        h.write(buf)
    }

    nonisolated static func run(_ exe: String, _ args: [String]) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
                do { try p.run(); p.waitUntilExit(); c.resume(returning: p.terminationStatus == 0) } catch { c.resume(returning: false) }
            }
        }
    }
    private static func err(_ s: String) -> NSError { NSError(domain: "Zuffi", code: 1, userInfo: [NSLocalizedDescriptionKey: s]) }
}

// MARK: - The setup screen

struct SetupView: View {
    @ObservedObject var state: AppState
    var onDone: () -> Void
    @ObservedObject private var local = LocalAISetup.shared
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var speech = SFSpeechRecognizer.authorizationStatus() == .authorized
    @State private var hands = AXIsProcessTrusted()
    @State private var see = CGPreflightScreenCaptureAccess()
    @State private var tools = InstalledAI.detect(refresh: true)
    @State private var geminiKey = ""
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    if SparrowSprites.shared.available {
                        Image(decorative: SparrowSprites.shared.reactions[8], scale: 1).resizable().frame(width: 84, height: 84)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hi, I'm Zuffi!").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Let's get me ready in two minutes. Just press the pink buttons.").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                }

                section("1", "Let me hear you and help you") {
                    permission("Microphone", "so I can hear you say “Zuffi…”", mic) {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in }
                    }
                    permission("Speech recognition", "so I understand your words, on this Mac", speech) {
                        SFSpeechRecognizer.requestAuthorization { _ in }
                    }
                    permission("Accessibility", "so I can open apps, type and click for you", hands) { ScreenAgent.askToAct() }
                    permission("Screen recording", "so I can see your screen when you ask", see) { ScreenAgent.askToSee() }
                    Text("A box from macOS will appear for each one — choose Allow. For the last two, switch Zuffi on in the list that opens.")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }

                section("2", "Give me a brain (AI)") {
                    if !tools.filter({ $0.isCLI }).isEmpty {
                        Text("Good news — you already have AI on this Mac:").font(.system(size: 12, weight: .semibold))
                        ForEach(tools.filter { $0.isCLI }) { t in
                            let pick = t.id == "claude-code" ? AIProvider.claudeCode.rawValue : AIProvider.codex.rawValue
                            HStack {
                                Image(systemName: "checkmark.seal.fill").foregroundColor(Color(hex: "#E2648A"))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(t.name).font(.system(size: 13, weight: .semibold))
                                    Text(t.detail).font(.system(size: 11)).foregroundColor(.secondary)
                                }
                                Spacer()
                                if state.aiProvider == pick { Label("Using this", systemImage: "checkmark.circle.fill").foregroundColor(.green).font(.system(size: 12)) }
                                else { Button("Use this") { state.aiProvider = pick }.buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A")) }
                            }
                        }
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Free AI on this Mac (private, works offline)").font(.system(size: 13, weight: .semibold))
                        Text("I'll download and set everything up myself — no Terminal, nothing to configure. It needs about \(LocalAISetup.model.contains("1b") ? "1.5" : LocalAISetup.model.contains("3b") ? "2.5" : "5") GB of space.")
                            .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        if local.busy || local.ready || local.failed != nil {
                            if local.busy { ProgressView(value: local.progress).tint(Color(hex: "#E2648A")) }
                            Text(local.failed ?? local.step).font(.system(size: 11)).foregroundColor(local.failed == nil ? .primary : .orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !local.ready {
                            Button(local.busy ? "Setting up…" : "Set up free AI for me") { local.start() }
                                .buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A")).disabled(local.busy)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Or: a free Google Gemini key (smarter, needs internet)").font(.system(size: 13, weight: .semibold))
                        Text("1. Open the Gemini key page and sign in with Google.\n2. Press “Create API key” and copy it.\n3. Paste it here and press Save.")
                            .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open the Gemini key page") { NSWorkspace.shared.open(URL(string: "https://aistudio.google.com/apikey")!) }
                            SecureField("Paste the key here", text: $geminiKey).textFieldStyle(.roundedBorder)
                            Button("Save") {
                                let k = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !k.isEmpty else { return }
                                KeychainStore.shared.set("gemini-api-key", value: k)
                                state.aiProvider = AIProvider.gemini.rawValue
                                geminiKey = ""
                            }.disabled(geminiKey.isEmpty)
                        }
                    }
                }

                section("3", "That's it!") {
                    Text("Say “Zuffi, what's the weather?” or “Zuffi, remind me to call Mum at 6”. Click me any time to talk. The mic and camera buttons let you switch them off whenever you like.")
                        .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    Button("Start using Zuffi") { onDone() }.buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A")).controlSize(.large)
                }
            }
            .padding(28)
        }
        .frame(width: 560, height: 640)
        .onReceive(tick) { _ in
            mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            speech = SFSpeechRecognizer.authorizationStatus() == .authorized
            hands = AXIsProcessTrusted(); see = CGPreflightScreenCaptureAccess()
        }
    }

    private func section<C: View>(_ n: String, _ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(n).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.white)
                    .frame(width: 22, height: 22).background(Circle().fill(Color(hex: "#E2648A")))
                Text(title).font(.system(size: 16, weight: .bold, design: .rounded))
            }
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "#E2648A").opacity(0.06)))
        }
    }

    private func permission(_ name: String, _ why: String, _ ok: Bool, ask: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle").foregroundColor(ok ? .green : .secondary).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .semibold))
                Text(why).font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            if !ok { Button("Allow") { ask() }.buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A")).controlSize(.small) }
        }
    }
}
