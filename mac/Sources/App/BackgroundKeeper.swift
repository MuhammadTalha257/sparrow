import AppKit

/// Keeps Sparrow awake for reminders and listening when the screen is off or locked (no App Nap),
/// and wakes everything back up after the Mac sleeps.
@MainActor
enum BackgroundKeeper {
    private static var activity: NSObjectProtocol?

    static func start() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .suddenTerminationDisabled],
                                                         reason: "Sparrow reminders and listening")
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                appendAppLog("voice.log", "Mac woke up — catching up")
                NativeSpeech.shared.start()
                WebHub.shared.run("window.Sparrow && window.Sparrow.catchUp && window.Sparrow.catchUp()")
            }
        }
    }
}
