import Foundation
import AppKit

/// Optional "Studio voice": OmniVoice running privately on this Mac (installed once from Settings).
/// Sparrow's built-in voices are used whenever it isn't installed, still loading, or slow.
@MainActor
final class StudioVoice {
    static let shared = StudioVoice()

    private var process: Process?
    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Sparrow/studio")

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("installed").path)
            && FileManager.default.isExecutableFile(atPath: dir.appendingPathComponent("env/bin/python").path)
    }
    var isRunning: Bool { process?.isRunning == true }

    /// Opens Terminal and runs the installer so the person can watch the (long) download.
    func install() {
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("studio/install-studio-voice.sh") else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let local = home.appendingPathComponent("Documents/projects for ai/OmniVoice-master")
        let src = FileManager.default.fileExists(atPath: local.appendingPathComponent("pyproject.toml").path) ? local.path : ""
        let cmd = FileManager.default.temporaryDirectory.appendingPathComponent("Install Sparrow Studio Voice.command")
        let body = "#!/bin/bash\n/bin/bash \(q(script.path)) \(q(src))\n"
        do {
            try body.write(to: cmd, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cmd.path)
            NSWorkspace.shared.open(cmd)
            UserDefaults.standard.set(true, forKey: "studioVoice")
            waitForInstall()
        } catch { appendAppLog("studio.log", "couldn't start installer: \(error.localizedDescription)") }
    }

    private func waitForInstall() {
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { t in
            MainActor.assumeIsolated {
                if StudioVoice.shared.isInstalled { t.invalidate(); StudioVoice.shared.start() }
            }
        }
    }

    /// Starts the local OmniVoice server (127.0.0.1:47321) in the background.
    func start() {
        guard isInstalled, !isRunning, UserDefaults.standard.bool(forKey: "studioVoice") else { return }
        let p = Process()
        p.executableURL = dir.appendingPathComponent("env/bin/python")
        let server = dir.appendingPathComponent("sparrow_studio.py")
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("studio/sparrow_studio.py") {
            try? FileManager.default.removeItem(at: server)
            try? FileManager.default.copyItem(at: bundled, to: server)      // keep the server up to date with the app
        }
        p.arguments = [server.path]
        var env = ProcessInfo.processInfo.environment
        env["PYTORCH_ENABLE_MPS_FALLBACK"] = "1"
        env["TOKENIZERS_PARALLELISM"] = "false"
        p.environment = env
        let logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Sparrow")
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let logURL = logs.appendingPathComponent("studio.log")
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); p.standardOutput = h; p.standardError = h }
        do { try p.run(); process = p } catch { appendAppLog("studio.log", "couldn't start: \(error.localizedDescription)") }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { StudioVoice.shared.process?.terminate() }
        }
    }

    private func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
