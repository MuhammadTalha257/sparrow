import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    /// Opening Zuffi again (Finder, Spotlight, Launchpad) brings the island back to where you can see it and opens it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        IslandDrag.rescueIfLost()
        islandController?.window?.orderFrontRegardless()
        islandController?.expand(to: .overview)
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when nb-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // One look everywhere: the dark dashboard and the new black notch.
        UserDefaults.standard.set(false, forKey: "hubLight")
        UserDefaults.standard.set(true, forKey: "notchWide")
        // Offline brain ready before you need it (loaded once, then kept warm while you're offline).
        Task { try? await Task.sleep(nanoseconds: 8_000_000_000); await AIService.warmOllama() }
        AppUsage.shared.start()      // "Your day" in the small screen (kept only on this Mac)
        Timer.scheduledTimer(withTimeInterval: 1200, repeats: true) { _ in if !NetStatus.shared.online { Task { await AIService.warmOllama() } } }
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        // Ask to take notes when a Zoom / Teams / Meet / FaceTime / WhatsApp call starts
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { MainActor.assumeIsolated { MeetingWatcher.shared.start(); MacStatus.shared.start() } }
        NSApp.setActivationPolicy(.accessory)
        // First run: open Zuffi when the Mac starts (signed in already — the plan is remembered on this Mac).
        // Settings → General → Startup turns it off.
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        }
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Zuffi")
        button.image?.size = NSSize(width: 18, height: 18)
        button.image?.accessibilityDescription = "Zuffi"
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Zuffi", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(withTitle: "Dashboard — home, team & settings…", action: #selector(openHub), keyEquivalent: "d")
        menu.addItem(withTitle: "Today — meetings & tasks…", action: #selector(openToday), keyEquivalent: "t")
        menu.addItem(withTitle: "More — habits, prayer, memory, invoices, tools…", action: #selector(openMore), keyEquivalent: "m")
        let pet = NSMenuItem(title: "Show Zuffi on screen", action: #selector(togglePet), keyEquivalent: "p")
        pet.tag = 42
        menu.addItem(pet)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem?.menu = menu
    }

    // MARK: - Actions

    @objc private func openIsland() {
        if SparrowBubble.shared.isHidden { SparrowBubble.shared.restore() }
        islandController?.expand(to: .overview)
    }

    @objc private func openToday() { TodayWindow.shared.show() }
    @objc private func openHub() { ZuffiHub.shared.show(.home) }
    @objc private func openMore() { ZuffiNav.go(.features) }

    @objc private func togglePet() {
        PetController.shared.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.updatePetMenuTitle() }
    }

    func updatePetMenuTitle() {
        statusItem?.menu?.item(withTag: 42)?.title = PetController.shared.isShown ? "Hide Zuffi from screen" : "Show Zuffi on screen"
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        if ZuffiHub.oneWindow { ZuffiHub.shared.show(.settings); return }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "Settings — Zuffi"
        win.appearance = NSAppearance(named: .darkAqua)               // the same night look as Zuffi's other windows
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = NSColor(red: 0.043, green: 0.039, blue: 0.122, alpha: 1)
        let host = NSHostingView(rootView: SettingsView().preferredColorScheme(.dark))
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 680, height: 420)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Centres the window horizontally and keeps its title bar clear of the island panel
    /// (320 pt tall at the top of the notch screen), shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? win.screen
        guard let screen else { win.center(); return }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - 500 - 12   // island panel height + margin
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
    }

    // MARK: - Island setup

    private func setupIsland() {
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        // Developer-service monitors only run when you've connected them (keeps Zuffi light).
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
        // Voice, greeting, weather and notification reading
        Assistant.start()
        PhoneLink.shared.startIfEnabled()
        AgentStage.shared.start()
        NotchHang.shared.start()                       // music bars and working agents under the notch
        // At start only the notch says hi — the "What's Zuffi for?" choice and the first-run setup wait until you open the dashboard.
        if ZuffiFocus.agents { BizSync.shared.startIfLinked() }
        WebHub.shared.start()
        NativeSpeech.shared.start()
        HoldToTalk.start()
        FaceDrop.shared.start()
        BackgroundKeeper.start()
        // Agents (Claude Code / Codex / GitHub) and the glowing notch edge
        AgentHub.shared.start()
        VoiceboxVoice.shared.startWatching()
        ZuffiData.shared.start()
        EdgeGlow.shared.start()
        NowPlaying.shared.start()             // music in the notch (only asks Spotify/Music when they're open)
        WhatsAppLink.shared.startIfEnabled()  // linked WhatsApp (only if you linked it)
        ZuffiMemory.shared.start()            // reminders & tasks in every answer
        // Old "Sparrow" permission entries → fresh "Zuffi" ones (once)
        if SetupWizard.done { Task { await ScreenAgent.migrateFromSparrowOnce() } }
        // The bunny pops out and says hey, then the island opens with its tabs
        if UserDefaults.standard.object(forKey: "helloOnOpen") as? Bool ?? true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { ZuffiHello.shared.show() }
        }
        // (the pet stays away at start — "Show pet" in the notch brings Aurora)
    }
}
