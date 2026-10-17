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

    var online: Bool {
        lock.lock(); defer { lock.unlock() }
        return pathOK && reachable && Date() > downUntil
    }

    /// Something online just failed for network reasons: treat the Mac as offline for a minute.
    func noteNoInternet() {
        lock.lock(); downUntil = Date().addingTimeInterval(60); reachable = false; lock.unlock()
        q.async { self.probe() }
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

    /// Apple's own connectivity check page: tiny, fast and always up.
    private func probe() {
        lock.lock(); let path = pathOK; lock.unlock()
        guard path else { set(false); return }
        var req = URLRequest(url: URL(string: "https://captive.apple.com/hotspot-detect.html")!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        req.httpMethod = "GET"
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3; cfg.timeoutIntervalForResource = 4; cfg.waitsForConnectivity = false
        URLSession(configuration: cfg).dataTask(with: req) { [weak self] data, resp, _ in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200 && (data.map { String(decoding: $0, as: UTF8.self).contains("Success") } ?? false)
            self?.q.async { self?.set(ok) }
        }.resume()
    }

    private func appendAppLogSafe(_ s: String) {
        DispatchQueue.main.async { appendAppLog("voice.log", s) }
    }
}
