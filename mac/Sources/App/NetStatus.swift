import Foundation
import Network

/// Is the internet really reachable right now? (for live talk, sharper speech recognition and the AI)
///
/// "Wi-Fi connected" is not enough: a router with no internet, a hotspot without data or a hotel login
/// page all look connected. So besides the network path we check a tiny page every 20 s (and right
/// away when the network changes). When it fails Zuffi switches to her offline voice and brain at once,
/// instead of waiting for online requests to time out.
final class NetStatus: @unchecked Sendable {
    static let shared = NetStatus()
    private let monitor = NWPathMonitor()
    private let q = DispatchQueue(label: "sparrow.net")
    private let lock = NSLock()
    private var pathOK = true
    private var reachable = true
    private var downUntil = Date.distantPast
    private var timer: DispatchSourceTimer?
    private var fails = 0

    /// Is there a network connection at all (Wi-Fi / Ethernet), regardless of whether the internet answers?
    var pathUp: Bool { lock.lock(); defer { lock.unlock() }; return pathOK }

    var online: Bool {
        lock.lock(); defer { lock.unlock() }
        return pathOK && reachable && Date() > downUntil
    }

    /// Something online just failed for network reasons: treat the Mac as offline for a minute.
    func noteNoInternet() {
        lock.lock(); downUntil = Date().addingTimeInterval(30); lock.unlock()
        q.async { self.probe() }                              // a good answer clears it straight away
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] p in
            guard let self else { return }
            self.lock.lock(); self.pathOK = p.status == .satisfied; self.lock.unlock()
            if p.status == .satisfied { self.probe() } else { self.set(false) }
        }
        monitor.start(queue: q)
        let t = DispatchSource.makeTimerSource(queue: q)
        t.schedule(deadline: .now() + 2, repeating: 20)
        t.setEventHandler { [weak self] in self?.probe() }
        t.resume()
        timer = t
    }

    private func set(_ ok: Bool) {
        lock.lock()
        let was = reachable
        reachable = ok
        if ok { downUntil = .distantPast }
        lock.unlock()
        if was != ok { appendAppLogSafe(ok ? "internet: back" : "internet: down — offline voice and brain") }
    }

    /// Apple's and Google's connectivity pages: tiny, fast and always up. Offline only after two
    /// failed rounds in a row (one slow answer is not "offline").
    private func probe() {
        lock.lock(); let path = pathOK; lock.unlock()
        guard path else { fails = 0; set(false); return }
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 6; cfg.timeoutIntervalForResource = 7; cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg)
        let urls = ["https://captive.apple.com/hotspot-detect.html", "https://www.google.com/generate_204"]
        let group = DispatchGroup(); let anyOK = OKFlag()
        for u in urls {
            group.enter()
            var req = URLRequest(url: URL(string: u)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)
            req.httpMethod = "GET"
            session.dataTask(with: req) { _, resp, _ in
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200 || code == 204 { anyOK.set() }
                group.leave()
            }.resume()
        }
        group.notify(queue: q) { [weak self] in
            guard let self else { return }
            let ok = anyOK.value
            if ok { self.fails = 0; self.set(true) }
            else { self.fails += 1; if self.fails >= 2 { self.set(false) } else { self.q.asyncAfter(deadline: .now() + 5) { self.probe() } } }
        }
    }

    private func appendAppLogSafe(_ s: String) {
        DispatchQueue.main.async { appendAppLog("voice.log", s) }
    }
}

/// A yes/no that several network callbacks can set safely.
private final class OKFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var v = false
    func set() { lock.lock(); v = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return v }
}
