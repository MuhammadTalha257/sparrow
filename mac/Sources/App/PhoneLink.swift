import Foundation
import AppKit
import CryptoKit
import CoreImage
import SwiftUI

// =====================================================================
// MARK: - iPhone ↔ Mac link (free, no Apple developer account)
//
// The iPhone web app sends commands ("lock my Mac", "play music", "shut down
// the Mac") to this Mac from anywhere. They travel through a free public
// message relay (ntfy.sh) on a random private channel, end-to-end encrypted
// with AES-GCM: the relay only ever sees scrambled bytes. The channel and the
// key are made on this Mac and handed to the iPhone once, by scanning a QR code.
// Commands older than two minutes, or seen before, are ignored.
// =====================================================================

@MainActor
final class PhoneLink: ObservableObject {
    static let shared = PhoneLink()

    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "phoneLinkOn")
    @Published private(set) var connected = false
    @Published private(set) var recent: [String] = []

    static let relay = "https://ntfy.sh"
    static let webApp = "https://muhammadtalha257.github.io/sparrow/test/"

    private var streamTask: Task<Void, Never>?
    private var awake: NSObjectProtocol?
    private var seen: [String] = []
    private var lastMessageID: String?

    // MARK: Pairing secrets (made here, never leave except in the QR code)

    var topic: String {
        if let t = UserDefaults.standard.string(forKey: "phoneLinkTopic"), t.count >= 20 { return t }
        let t = Self.randomToken(18)
        UserDefaults.standard.set(t, forKey: "phoneLinkTopic")
        return t
    }
    private var key: SymmetricKey {
        if let s = UserDefaults.standard.string(forKey: "phoneLinkKey"), let d = Data(b64url: s), d.count == 32 {
            return SymmetricKey(data: d)
        }
        let k = SymmetricKey(size: .bits256)
        UserDefaults.standard.set(k.withUnsafeBytes { Data($0) }.b64url, forKey: "phoneLinkKey")
        return k
    }
    /// What the QR code holds: the iPhone web app's address with the link in the part after # (never sent to any server).
    var pairingURL: String { "\(Self.webApp)#link=\(topic).\(key.withUnsafeBytes { Data($0) }.b64url)" }

    func newCode() {
        UserDefaults.standard.removeObject(forKey: "phoneLinkTopic")
        UserDefaults.standard.removeObject(forKey: "phoneLinkKey")
        seen = []; lastMessageID = nil
        if enabled { stop(); start() }
        objectWillChange.send()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: "phoneLinkOn")
        on ? start() : stop()
    }

    func startIfEnabled() { if enabled { start() } }

    // MARK: Listening for the iPhone

    private func start() {
        guard streamTask == nil else { return }
        log("on")
        // Keep the Mac from dozing off on its own while the iPhone may need it (the screen can still sleep).
        awake = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Zuffi: iPhone can control this Mac")
        streamTask = Task { [weak self] in
            var delay: UInt64 = 2
            while !Task.isCancelled {
                guard let self else { return }
                let ok = await self.listenOnce()
                self.connected = false
                if Task.isCancelled { break }
                delay = ok ? 2 : min(delay * 2, 60)
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }
    }

    private func stop() {
        streamTask?.cancel(); streamTask = nil
        if let a = awake { ProcessInfo.processInfo.endActivity(a); awake = nil }
        connected = false
        log("off")
    }

    /// One long-lived connection; returns true if it was up for a while (so reconnect quickly).
    private func listenOnce() async -> Bool {
        let since = lastMessageID ?? "2m"
        guard let url = URL(string: "\(Self.relay)/\(topic)-mac/json?since=\(since)") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 600
        let began = Date()
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            connected = true
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let d = line.data(using: .utf8),
                      let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      o["event"] as? String == "message" else { continue }
                if let id = o["id"] as? String { lastMessageID = id }
                if let body = o["message"] as? String { await handle(body) }
            }
        } catch {
            if !Task.isCancelled { log("connection dropped: \(error.localizedDescription)") }
        }
        return Date().timeIntervalSince(began) > 30
    }

    private func handle(_ sealed: String) async {
        guard let plain = open(sealed),
              let o = try? JSONSerialization.jsonObject(with: plain) as? [String: Any],
              let id = o["id"] as? String, !seen.contains(id) else { return }
        seen.append(id); if seen.count > 200 { seen.removeFirst(50) }
        let at = (o["at"] as? NSNumber)?.doubleValue ?? 0
        guard abs(Date().timeIntervalSince1970 * 1000 - at) < 120_000 else { log("ignored an old command"); return }
        switch o["t"] as? String {
        case "ping":
            await send(["t": "status", "re": id, "text": status()])
        case "cmd":
            let text = (o["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            log("📱 \(text)")
            let reply = await Self.run(text)
            log("→ \(reply)")
            await send(["t": "reply", "re": id, "text": reply])
        default: break
        }
    }

    private func status() -> String {
        let name = Host.current().localizedName ?? "your Mac"
        return "\(name) is on and listening. \(CommandEngine.batteryText())"
    }

    /// Does the command on this Mac and returns what to tell the iPhone (nothing is spoken out loud here).
    static func run(_ raw: String) async -> String {
        // "open Spotify on my Mac" → "open Spotify"; "turn off my laptop" → "shut down mac"
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func sub(_ p: String, _ r: String) { text = text.replacingOccurrences(of: p, with: r, options: [.regularExpression, .caseInsensitive]) }
        sub(#"^(?:hey |ok )?sparrow[, ]*"#, "")
        sub(#"^(?:(?:turn|switch|power) off|band karo|band kar do|off karo)\s+(?:my |the )?(?:mac|macbook|imac|laptop|computer)\b.*$|^(?:my |the )?(?:mac|macbook|laptop|computer)\s+(?:ko\s+)?(?:band karo|band kar do|off karo|turn off|shut down)$"#, "shut down mac")
        sub(#"^lock\s+(?:my |the )?(?:mac|macbook|imac|laptop|computer)$"#, "lock screen")
        sub(#"^(?:mac|macbook|laptop|computer)\s+(battery|volume.*)$"#, "$1")
        sub(#"\s+(?:on|in|from|at)\s+(?:my |the )?(?:mac|macbook|imac|laptop|computer)\b"#, "")
        sub(#"^(?:my |the )?(?:mac|macbook|laptop|computer)\s+(?:pe|par|par\s+)\s*"#, "")
        if text.lowercased() == "cancel" { text = "cancel" }
        let low = text.lowercased()
        // Turning off Wi-Fi from far away would cut the link to the iPhone.
        if low.range(of: #"\b(wi-?fi|wifi|internet)\b.*\b(off|band|disable)\b|\b(off|disable)\b.*\b(wi-?fi|wifi)\b"#, options: .regularExpression) != nil {
            return "If I turn Wi-Fi off I'd lose the link to your iPhone, so I won't do that remotely."
        }
        AppState.shared.noteMessage = "📱 From your iPhone: \(text)"
        NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        if let r = await AgentRouter.shared.handle(text) { return r }
        if let r = await WebHub.shared.ask(text) { return r }
        if let plan = await SmartPlanner.shared.plan(text) {
            if !plan.commands.isEmpty { return await SmartPlanner.shared.run(plan) }
            if !plan.say.isEmpty { return plan.say }
        }
        return "I couldn't do that on the Mac. Try something like “lock my Mac”, “play music” or “open Spotify”."
    }

    // MARK: Sending back

    private func send(_ obj: [String: Any]) async {
        var o = obj
        o["at"] = Int(Date().timeIntervalSince1970 * 1000)
        o["id"] = UUID().uuidString
        guard let d = try? JSONSerialization.data(withJSONObject: o), let sealed = seal(d),
              let url = URL(string: "\(Self.relay)/\(topic)-phone") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(sealed.utf8)
        req.setValue("1h", forHTTPHeaderField: "Cache")      // ntfy: keep briefly so the phone can fetch it
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: Encryption (AES-GCM: 12-byte nonce + ciphertext + 16-byte tag, base64url)

    private func seal(_ d: Data) -> String? {
        (try? AES.GCM.seal(d, using: key))?.combined?.b64url
    }
    private func open(_ s: String) -> Data? {
        guard let d = Data(b64url: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let box = try? AES.GCM.SealedBox(combined: d) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    private func log(_ s: String) {
        appendAppLog("phone.log", s)
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        recent.insert("\(f.string(from: Date()))  \(s)", at: 0)
        if recent.count > 12 { recent.removeLast() }
    }

    private static func randomToken(_ bytes: Int) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return "sp" + Data(b).b64url.replacingOccurrences(of: "-", with: "x").replacingOccurrences(of: "_", with: "y")
    }

    static func qrImage(_ text: String) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size); img.addRepresentation(rep)
        return img
    }
}

extension Data {
    var b64url: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    init?(b64url s: String) {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        self.init(base64Encoded: t)
    }
}

// MARK: - Settings → iPhone

struct PhoneLinkSettingsView: View {
    @ObservedObject private var link = PhoneLink.shared
    @State private var showCode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "iphone.radiowaves.left.and.right").font(.system(size: 24)).foregroundColor(Color(hex: "#E2648A"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Control this Mac from your iPhone").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Say or type “lock my Mac”, “play music”, “shut down the Mac”… in Zuffi on your iPhone, from anywhere.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Let my iPhone control this Mac", isOn: Binding(get: { link.enabled }, set: { link.setEnabled($0) }))
                        .toggleStyle(.switch)
                    if link.enabled {
                        HStack(spacing: 6) {
                            Circle().fill(link.connected ? Color.green : Color.orange).frame(width: 8, height: 8)
                            Text(link.connected ? "Ready — waiting for your iPhone" : "Connecting…").font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }.padding(6)
            }
            if link.enabled {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Link your iPhone (once)").font(.system(size: 13, weight: .semibold))
                        Text("1. On your iPhone, open the Camera and point it at this code.\n2. Tap the link — Zuffi opens and says “Linked to your Mac”.\n3. If you use Zuffi from your Home Screen, open it there instead: Settings → Control my Mac → Scan code.")
                            .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                        if showCode, let img = PhoneLink.qrImage(link.pairingURL) {
                            Image(nsImage: img).interpolation(.none).resizable().frame(width: 190, height: 190)
                                .padding(8).background(Color.white).cornerRadius(10)
                            HStack {
                                Button("Copy link") {
                                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(link.pairingURL, forType: .string)
                                }.controlSize(.small)
                                Button("Hide code") { showCode = false }.controlSize(.small)
                                Button("Make a new code (unlinks old phones)") { link.newCode() }.controlSize(.small)
                            }
                            Text("Keep this code private — anyone who scans it can control this Mac.")
                                .font(.system(size: 10)).foregroundColor(.orange)
                        } else {
                            Button("Show link code") { showCode = true }.buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A"))
                        }
                    }.padding(6)
                }
                if !link.recent.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Recent").font(.system(size: 12, weight: .semibold))
                            ForEach(link.recent, id: \.self) { Text($0).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary).lineLimit(1) }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                    }
                }
            }
            Text("Your Mac needs to be on, awake and online, with Zuffi open. Messages pass through the free ntfy.sh relay, end-to-end encrypted — the relay can't read them.")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
