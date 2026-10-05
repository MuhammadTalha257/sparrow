import Network

/// Is the Mac online right now? (for sharper speech recognition and the AI planner)
final class NetStatus: @unchecked Sendable {
    static let shared = NetStatus()
    private let monitor = NWPathMonitor()
    private(set) var online = true
    private init() {
        monitor.pathUpdateHandler = { [weak self] p in self?.online = p.status == .satisfied }
        monitor.start(queue: DispatchQueue(label: "sparrow.net"))
    }
}
