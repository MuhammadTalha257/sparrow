import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Zuffi "More": every new feature, inside the Mac app
// The shared Zuffi app (habits, prayer times, memory, quotes & invoices,
// time tracking, PDF tools, sync…) runs in a web view that ships inside the
// Mac app. The island still does the talking: Apple speech, Apple voices.
// =====================================================================

/// Serves the bundled app files at app://sparrow/… (works offline).
final class SparrowSchemeHandler: NSObject, WKURLSchemeHandler {
    nonisolated func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, let base = Bundle.main.resourceURL?.appendingPathComponent("web") else { return }
        var path = url.path
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = base.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let ext = file.pathExtension.lowercased()
        let mime: String = [
            "html": "text/html", "js": "text/javascript", "mjs": "text/javascript", "css": "text/css", "json": "application/json",
            "webmanifest": "application/manifest+json", "png": "image/png", "svg": "image/svg+xml", "wasm": "application/wasm",
        ][ext] ?? "application/octet-stream"
        let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)", "Access-Control-Allow-Origin": "*",
                                                  // lets the voice engine use several CPU cores (SharedArrayBuffer)
                                                  "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp",
                                                  "Cross-Origin-Resource-Policy": "same-origin"])!
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }
    nonisolated func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
final class WebHub: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    static let shared = WebHub()
    private(set) var webView: WKWebView!
    private var window: NSWindow?
    private var ready = false
    private let scheme = SparrowSchemeHandler()

    private static let shim = """
    window.SparrowHost = 'mac';
    (() => {
      let id = 0; const wait = new Map();
      window.__sparrowReply = (i, v) => { const f = wait.get(i); if (f) { wait.delete(i); f(v); } };
      window.SparrowMac = {
        call: (cmd, args = {}) => new Promise(res => { const i = ++id; wait.set(i, res); window.webkit.messageHandlers.sparrow.postMessage({ id: i, cmd, ...args }); }),
        post: (cmd, args = {}) => window.webkit.messageHandlers.sparrow.postMessage({ id: 0, cmd, ...args }),
      };
    })();
    """

    /// Loads the app in the background at launch so voice and reminders work right away.
    func start() {
        guard webView == nil else { return }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(scheme, forURLScheme: "app")
        config.userContentController.add(self, name: "sparrow")
        config.userContentController.addUserScript(WKUserScript(source: Self.shim, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        if #available(macOS 14.0, *) { config.preferences.inactiveSchedulingPolicy = .none }   // keep reminders ticking when hidden
        config.mediaTypesRequiringUserActionForPlayback = []
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 440, height: 700), configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.setValue(false, forKey: "drawsBackground")
        webView = wv
        wv.load(URLRequest(url: URL(string: "app://sparrow/index.html")!))
        // A window that stays alive (hidden) so the page keeps running.
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        w.title = "Zuffi"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.level = .floating
        w.contentMinSize = NSSize(width: 340, height: 420)
        w.isOpaque = false
        w.backgroundColor = NSColor(red: 0.105, green: 0.055, blue: 0.075, alpha: 0.97)   // Blossom rose
        if let v = w.contentView?.superview { v.wantsLayer = true; v.layer?.cornerRadius = 18; v.layer?.masksToBounds = true }
        w.contentView = wv
        w.delegate = self
        window = w
    }

    /// Opens the full Zuffi panel, optionally on a tab (home, chat, plan, memory, tools).
    func show(tab: String? = nil) {
        start()
        guard let w = window else { return }
        if !w.isVisible, let saved = UserDefaults.standard.string(forKey: "moreFrame").map(NSRectFromString),
           saved.width > 0, NSScreen.screens.contains(where: { $0.visibleFrame.intersects(saved.insetBy(dx: 40, dy: 40)) }) {
            // Opens where you last dragged it
            w.setFrame(saved, display: false)
        } else if !w.isVisible, let screen = NSScreen.main {
            // Opens right under the island, never covering the whole screen
            let vf = screen.visibleFrame
            var x = vf.midX - w.frame.width / 2
            var top = vf.maxY - 8
            if let island = IslandDrag.panel {
                x = island.frame.midX - w.frame.width / 2
                top = min(vf.maxY - 8, island.frame.maxY - 175)
            }
            x = min(max(x, vf.minX + 8), vf.maxX - w.frame.width - 8)
            let h = min(w.frame.height, top - vf.minY - 8)
            w.setFrame(NSRect(x: x, y: top - h, width: w.frame.width, height: h), display: false)
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let tab { run("window.Sparrow && window.Sparrow.go && window.Sparrow.go('\(tab)')") }
    }

    /// Drag the panel by its top bar (the web page swallows normal window drags).
    private var dragTimer: Timer?
    private func dragPanel() {
        guard let w = window, NSEvent.pressedMouseButtons & 1 == 1 else { return }
        let start = NSEvent.mouseLocation, origin = w.frame.origin
        dragTimer?.invalidate()
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            MainActor.assumeIsolated {
                let hub = WebHub.shared
                guard let w = hub.window else { hub.dragTimer?.invalidate(); return }
                let m = NSEvent.mouseLocation
                w.setFrameOrigin(NSPoint(x: origin.x + m.x - start.x, y: origin.y + m.y - start.y))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    hub.dragTimer?.invalidate(); hub.dragTimer = nil
                    UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: "moreFrame")
                }
            }
        }
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        if let w = window { UserDefaults.standard.set(NSStringFromRect(w.frame), forKey: "moreFrame") }
    }

    func run(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }

    func hide() { window?.orderOut(nil) }
    /// Click anywhere else → the panel tucks away (like a popover).
    func windowDidResignKey(_ notification: Notification) {
        guard UserDefaults.standard.object(forKey: "morePinned") as? Bool != true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MainActor.assumeIsolated {
                guard let w = WebHub.shared.window, !w.isKeyWindow, NSApp.modalWindow == nil, w.attachedSheet == nil else { return }
                if NSApp.windows.contains(where: { $0 is NSOpenPanel || $0 is NSSavePanel }) { return }
                w.orderOut(nil)
            }
        }
    }

    var isReady: Bool { ready }

    /// Saves a file you dropped on the island into Zuffi's memory (text for search + a copy).
    func rememberFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url), data.count < 30_000_000, let wv = webView else { return }
        let ext = url.pathExtension.lowercased()
        let mime = ["pdf": "application/pdf", "txt": "text/plain", "md": "text/markdown", "csv": "text/csv", "json": "application/json",
                    "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                    "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"][ext] ?? "application/octet-stream"
        Task {
            for _ in 0..<30 where !self.ready { try? await Task.sleep(nanoseconds: 100_000_000) }
            _ = try? await wv.callAsyncJavaScript("return await window.Sparrow.rememberFile(n, t, b)",
                                                 arguments: ["n": url.lastPathComponent, "t": mime, "b": data.base64EncodedString()],
                                                 in: nil, contentWorld: .page)
        }
    }

    /// Speaks with Zuffi's natural voices. true = speaking now (the end arrives as a "speaking" message).
    func say(_ text: String) async -> Bool {
        guard ready, let wv = webView else { return false }
        do {
            let r = try await wv.callAsyncJavaScript("return await window.Sparrow.neuralSay(t)", arguments: ["t": text], in: nil, contentWorld: .page)
            return (r as? Bool) == true || (r as? NSNumber)?.boolValue == true
        } catch {
            appendAppLog("web.log", "neural voice failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Runs a snippet in the shared app (reminders, tasks…) and returns its value. `body` must `return` something.
    func callJS(_ body: String, _ args: [String: Any] = [:]) async -> Any? {
        start()
        for _ in 0..<30 where !ready { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard ready, let wv = webView else { return nil }
        do { return try await wv.callAsyncJavaScript(body, arguments: args, in: nil, contentWorld: .page) }
        catch { appendAppLog("web.log", "callJS failed: \(error.localizedDescription)"); return nil }
    }

    /// A value from the job agent's CV profile ("email", "phone", "cover letter"…), for "Zuffi, type my email".
    func jobField(_ name: String) async -> String? {
        start()
        for _ in 0..<30 where !ready { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard ready, let wv = webView else { return nil }
        let r = try? await wv.callAsyncJavaScript("return window.Sparrow.jobField ? window.Sparrow.jobField(n) : ''", arguments: ["n": name], in: nil, contentWorld: .page)
        return (r as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    func hush() { run("window.Sparrow && window.Sparrow.neuralStop && window.Sparrow.neuralStop()") }

    /// Lets the shared app answer things the island doesn't know (habits, invoices, memory…). nil = not handled.
    func ask(_ text: String) async -> String? {
        start()
        for _ in 0..<30 where !ready { try? await Task.sleep(nanoseconds: 100_000_000) }
        guard ready, let wv = webView else { return nil }
        do {
            let r = try await wv.callAsyncJavaScript("return await window.Sparrow.voiceAsk(t)", arguments: ["t": text], in: nil, contentWorld: .page)
            if let s = r as? String, !s.isEmpty { return s }
        } catch { appendAppLog("web.log", "ask failed: \(error.localizedDescription)") }
        return nil
    }

    // MARK: messages from the page
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let o = message.body as? [String: Any], let cmd = o["cmd"] as? String else { return }
        let id = o["id"] as? Int ?? 0
        switch cmd {
        case "ready":
            ready = true
        case "speak":
            if let t = o["text"] as? String { VoiceEngine.shared.speak(t) }
        case "listen":
            VoiceEngine.shared.listenOnce()
        case "mem":
            reply(id, MemoryStore.shared.handle(o))
        case "hide":
            hide()
        case "newchat":
            AppState.shared.newChat()
        case "speaking":
            if (o["on"] as? Bool) == false { VoiceEngine.shared.neuralEnded() }
        case "prefs":
            if let l = o["listen"] as? String, !l.isEmpty { VoiceEngine.shared.setListenLocale(l) }
            if let n = o["neural"] as? Bool { UserDefaults.standard.set(n, forKey: "neuralVoice") }
            if let l = o["lang"] as? String { UserDefaults.standard.set(l, forKey: "sparrowLang") }
            if let v = o["voiceName"] as? String { UserDefaults.standard.set(v, forKey: "voiceName") }
            if let g = o["gender"] as? String { UserDefaults.standard.set(g, forKey: AssistantPrefs.voiceGender) }
            if let h = o["handsFree"] as? Bool { UserDefaults.standard.set(h, forKey: "handsFree") }
        case "studio":
            reply(id, ["installed": false, "running": false])      // the old Studio voice was replaced by Jarvis mode
        case "locales":
            reply(id, VoiceEngine.supportedListenLocales)
        case "log":
            appendAppLog("web.log", o["text"] as? String ?? "")
        case "note":
            let title = o["title"] as? String ?? ""
            AppState.shared.noteMessage = [title, o["sub"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
            NotificationCenter.default.post(name: .petSay, object: title)
        case "open":
            if let s = o["url"] as? String {
                if s.hasPrefix("app:") {
                    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/open"); p.arguments = ["-a", String(s.dropFirst(4))]
                    try? p.run()
                } else if let u = URL(string: s) { NSWorkspace.shared.open(u) }
            }
        case "show":
            show(tab: o["tab"] as? String)
        case "save":
            save(name: o["name"] as? String ?? "Zuffi file", base64: o["base64"] as? String ?? "", id: id)
        case "http":
            http(url: o["url"] as? String ?? "", method: o["method"] as? String ?? "POST", headers: o["headers"] as? [String: String] ?? [:], body: o["body"] as? String ?? "", id: id)
        case "dragWindow":
            dragPanel()
        case "reminder":
            // a meeting / task / reminder is due → Zuffi walks across with a banner
            ZuffiWalk.shared.arrive(kind: o["kind"] as? String ?? "reminder", title: o["title"] as? String ?? "Reminder",
                                    sub: o["sub"] as? String ?? "", itemId: o["itemId"] as? String)
        case "health":
            // water / coffee / medicine time → the sparrow flies in carrying it
            PetController.shared.deliver(kind: o["kind"] as? String ?? "water", text: o["text"] as? String ?? "Time for a break")
        case "complete":
            // The job agent's AI fallback: uses the keys saved in Zuffi's own settings.
            let prompt = o["prompt"] as? String ?? ""
            Task { if let t = await SmartPlanner.shared.complete(prompt) { self.reply(id, t) } else { self.reply(id, NSNull()) } }
        case "location":
            Task {
                if let l = await LocationProvider.shared.current() { self.reply(id, ["lat": l.lat, "lon": l.lon, "city": l.city]) }
                else { self.reply(id, NSNull()) }
            }
        default: break
        }
    }

    private func reply(_ id: Int, _ value: Any) {
        guard id > 0 else { return }
        let json: String
        if value is NSNull { json = "null" }
        else if let d = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]), let s = String(data: d, encoding: .utf8) { json = s }
        else { json = "null" }
        run("window.__sparrowReply(\(id), \(json))")
    }

    private func save(name: String, base64: String, id: Int) {
        guard let data = Data(base64Encoded: base64) else { reply(id, NSNull()); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url); NSWorkspace.shared.activateFileViewerSelecting([url]); reply(id, url.path) }
            catch { reply(id, NSNull()) }
        } else { reply(id, NSNull()) }
    }

    private func http(url: String, method: String = "POST", headers: [String: String], body: String, id: Int) {
        guard let u = URL(string: url), u.scheme == "https" else { reply(id, ["status": 400, "text": "{\"error\":{\"message\":\"Blocked\"}}"]); return }
        var req = URLRequest(url: u, timeoutInterval: method == "GET" ? 20 : 90)
        req.httpMethod = method == "GET" ? "GET" : "POST"
        req.setValue("application/json", forHTTPHeaderField: method == "GET" ? "Accept" : "Content-Type")
        if method == "GET" { req.setValue("Sparrow/1.0 (Macintosh)", forHTTPHeaderField: "User-Agent") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if method != "GET" { req.httpBody = body.data(using: .utf8) }
        Task {
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                self.reply(id, ["status": status, "text": String(data: data, encoding: .utf8) ?? ""])
            } catch {
                self.reply(id, ["status": 0, "text": "{\"error\":{\"message\":\"No internet: \(error.localizedDescription.replacingOccurrences(of: "\"", with: "'"))\"}}"])
            }
        }
    }

    // MARK: navigation & file pickers
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if let u = navigationAction.request.url, u.scheme != "app", u.scheme != "about", u.scheme != "blob", u.scheme != "data" {
            NSWorkspace.shared.open(u)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url { NSWorkspace.shared.open(u) }
        return nil
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let p = NSOpenPanel()
        p.allowsMultipleSelection = parameters.allowsMultipleSelection
        p.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        completionHandler(p.runModal() == .OK ? p.urls : nil)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let a = NSAlert(); a.messageText = message; a.runModal(); completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let a = NSAlert(); a.messageText = message; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        completionHandler(a.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
        let a = NSAlert(); a.messageText = prompt; a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24)); field.stringValue = defaultText ?? ""
        a.accessoryView = field
        completionHandler(a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil)
    }
}
