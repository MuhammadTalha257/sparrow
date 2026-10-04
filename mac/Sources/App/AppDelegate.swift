import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when nb-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Sparrow")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "Sparrow"
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Sparrow", action: #selector(openIsland), keyEquivalent: "")
        menu.addItem(withTitle: "Today — meetings & tasks…", action: #selector(openToday), keyEquivalent: "t")
        menu.addItem(withTitle: "More — habits, prayer, memory, invoices, tools…", action: #selector(openMore), keyEquivalent: "m")
        let pet = NSMenuItem(title: "Show Sparrow on screen", action: #selector(togglePet), keyEquivalent: "p")
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
    @objc private func openMore() { WebHub.shared.show() }

    @objc private func togglePet() {
        PetController.shared.toggle()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.updatePetMenuTitle() }
    }

    func updatePetMenuTitle() {
        statusItem?.menu?.item(withTag: 42)?.title = PetController.shared.isShown ? "Hide Sparrow from screen" : "Show Sparrow on screen"
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Settings — Sparrow"
        let host = NSHostingView(rootView: SettingsView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 420, height: 320)
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
        let islandBottom = screen.frame.maxY - 320 - 12   // island panel height + margin
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
        HookServer.shared.start()
        N8nPoller.shared.start()
        VercelPoller.shared.start()
        ResendPoller.shared.start()
        GithubPoller.shared.start()
        StripePoller.shared.start()
        CalcomPoller.shared.start()
        NotionPoller.shared.start()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettings),
                                               name: .openFullSettings, object: nil)
        // Voice, greeting, weather and notification reading
        Assistant.start()
        WebHub.shared.start()
        StudioVoice.shared.start()
        NativeSpeech.shared.start()
        HoldToTalk.start()
        BackgroundKeeper.start()
        // Pet mode: bring the sparrow back if it was on screen last time
        if UserDefaults.standard.bool(forKey: "petVisible") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                PetController.shared.show(); self?.updatePetMenuTitle()
            }
        }
    }
}
