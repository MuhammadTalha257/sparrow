import Foundation

/// Zuffi's memory on disk (~/Library/Application Support/Sparrow/Memory): the timeline of what you did,
/// and the files you gave it (text for searching, plus a copy when kept). Shared by the island and "More".
@MainActor
final class MemoryStore {
    static let shared = MemoryStore()

    private let dir: URL = {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Sparrow/Memory")
        try? FileManager.default.createDirectory(at: d.appendingPathComponent("blobs"), withIntermediateDirectories: true)
        return d
    }()
    private var log: [[String: Any]] = []
    private var files: [[String: Any]] = []
    private var loaded = false
    private var nextId = 1

    private func load() {
        guard !loaded else { return }
        loaded = true
        log = Self.read(dir.appendingPathComponent("log.json"))
        files = Self.read(dir.appendingPathComponent("files.json"))
        nextId = (log.compactMap { $0["id"] as? Int }.max() ?? 0) + 1
    }
    private static func read(_ url: URL) -> [[String: Any]] {
        guard let d = try? Data(contentsOf: url), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return a
    }
    private func save() {
        if let d = try? JSONSerialization.data(withJSONObject: log) { try? d.write(to: dir.appendingPathComponent("log.json"), options: .atomic) }
        if let d = try? JSONSerialization.data(withJSONObject: files) { try? d.write(to: dir.appendingPathComponent("files.json"), options: .atomic) }
    }

    /// Handles a request from the Zuffi web app. Returns a JSON-able value.
    func handle(_ o: [String: Any]) -> Any {
        load()
        switch o["op"] as? String {
        case "logAdd":
            guard var r = o["rec"] as? [String: Any] else { return NSNull() }
            r["id"] = nextId; nextId += 1
            log.append(r)
            if log.count > 8000 { log.removeFirst(log.count - 8000) }
            save(); return r["id"] ?? NSNull()
        case "logAll": return log
        case "logDel":
            let id = o["id"] as? Int
            log.removeAll { ($0["id"] as? Int) == id }; save(); return true
        case "filePut":
            guard var r = o["rec"] as? [String: Any], let id = r["id"] as? String else { return NSNull() }
            if let b = o["base64"] as? String, !b.isEmpty, let data = Data(base64Encoded: b) {
                try? data.write(to: dir.appendingPathComponent("blobs/\(id)"))
                r["hasCopy"] = true
            }
            files.removeAll { ($0["id"] as? String) == id }
            files.append(r); save(); return true
        case "fileAll": return files
        case "fileGet":
            guard let id = o["id"] as? String, var r = files.first(where: { ($0["id"] as? String) == id }) else { return NSNull() }
            if let d = try? Data(contentsOf: dir.appendingPathComponent("blobs/\(id)")) { r["base64"] = d.base64EncodedString() }
            return r
        case "fileDel":
            let id = o["id"] as? String ?? ""
            files.removeAll { ($0["id"] as? String) == id }
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("blobs/\(id)"))
            save(); return true
        case "wipe":
            log = []; files = []
            try? FileManager.default.removeItem(at: dir.appendingPathComponent("blobs"))
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent("blobs"), withIntermediateDirectories: true)
            save(); return true
        default: return NSNull()
        }
    }
}
