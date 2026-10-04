import Foundation
import AppKit
import WebKit
import UniformTypeIdentifiers

// =====================================================================
// MARK: - Sparrow "More": every new feature, inside the Mac app
// The shared Sparrow app (habits, prayer times, memory, quotes & invoices,
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
final class WebHub: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
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
        let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 720),
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        w.title = "Sparrow"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.hidesOnDeactivate = false
        w.level = .floating
        w.backgroundColor = NSColor(red: 0.08, green: 0.05, blue: 0.03, alpha: 1)
        w.contentMinSize = NSSize(width: 380, height: 480)
        w.contentView = wv
        window = w
    }

    /// Opens the full Sparrow panel, optionally on a tab (home, chat, plan, memory, tools).
    func show(tab: String? = nil) {
        start()
        guard let w = window else { return }
        if !w.isVisible, let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let pos = SparrowPosition.current
            let x = pos == .left ? vf.minX + 12 : pos == .right ? vf.maxX - w.frame.width - 12 : vf.midX - w.frame.width / 2
            w.setFrameOrigin(NSPoint(x: x, y: vf.maxY - w.frame.height - 60))
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let tab { run("window.Sparrow && window.Sparrow.go && window.Sparrow.go('\(tab)')") }
    }

    func run(_ js: String) { webView?.evaluateJavaScript(js, completionHandler: nil) }

    var isReady: Bool { ready }

    /// Speaks with Sparrow's natural voices. true = speaking now (the end arrives as a "speaking" message).
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
        case "newchat":
            AppState.shared.newChat()
        case "speaking":
            if (o["on"] as? Bool) == false { VoiceEngine.shared.neuralEnded() }
        case "prefs":
            if let l = o["listen"] as? String, !l.isEmpty { VoiceEngine.shared.setListenLocale(l) }
            if let n = o["neural"] as? Bool { UserDefaults.standard.set(n, forKey: "neuralVoice") }
            if let st = o["studio"] as? Bool { UserDefaults.standard.set(st, forKey: "studioVoice"); if st { StudioVoice.shared.start() } }
        case "studio":
            switch o["action"] as? String {
            case "install": StudioVoice.shared.install()
            case "start": StudioVoice.shared.start()
            default: reply(id, ["installed": StudioVoice.shared.isInstalled, "running": StudioVoice.shared.isRunning])
            }
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
            save(name: o["name"] as? String ?? "Sparrow file", base64: o["base64"] as? String ?? "", id: id)
        case "http":
            http(url: o["url"] as? String ?? "", headers: o["headers"] as? [String: String] ?? [:], body: o["body"] as? String ?? "", id: id)
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

    private func http(url: String, headers: [String: String], body: String, id: Int) {
        guard let u = URL(string: url), u.scheme == "https" else { reply(id, ["status": 400, "text": "{\"error\":{\"message\":\"Blocked\"}}"]); return }
        var req = URLRequest(url: u, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = body.data(using: .utf8)
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
