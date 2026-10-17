import Foundation
import AppKit
import SwiftUI
import IOKit.ps

// =====================================================================
// MARK: - Keep working while charging / with the lid closed, and speed-to-lead alerts in the notch
// =====================================================================

@MainActor
final class MacPower: ObservableObject {
    static let shared = MacPower()

    /// Stay awake on the charger (the screen may still turn off).
    @Published var awakeCharging = UserDefaults.standard.bool(forKey: "awakeCharging") {
        didSet { UserDefaults.standard.set(awakeCharging, forKey: "awakeCharging"); update() }
    }
    /// macOS "disablesleep": keeps running with the lid closed. Needs the owner's password (macOS asks, not Zuffi).
    @Published private(set) var lidMode = UserDefaults.standard.bool(forKey: "lidMode")
    @Published private(set) var message = ""

    private var activity: NSObjectProtocol?
    private var warnedOnBattery = false

    var onAC: Bool {
        guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let raw = IOPSGetProvidingPowerSourceType(snap)?.takeUnretainedValue() else { return true }
        return (raw as String) == kIOPMACPowerKey
    }

    func update() {
        let want = (awakeCharging || lidMode) && onAC
        if want, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .suddenTerminationDisabled],
                                                             reason: "Zuffi keeps answering clients while the Mac is charging")
        } else if !want, let a = activity {
            ProcessInfo.processInfo.endActivity(a); activity = nil
        }
    }

    func setLid(_ on: Bool) {
        let script = "do shell script \"pmset -a disablesleep \(on ? 1 : 0)\" with administrator privileges with prompt \"Zuffi: \(on ? "keep working when the lid is closed" : "let the Mac sleep when the lid is closed again")\""
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err == nil {
            lidMode = on
            UserDefaults.standard.set(on, forKey: "lidMode")
            message = on ? "Zuffi keeps working with the lid closed. Turn this off before you put the Mac in a bag on battery." : "The Mac sleeps again when you close the lid."
            warnedOnBattery = false
        } else {
            message = "Not changed — macOS needs your password to allow this."
        }
        update()
    }

    /// Every few seconds from ZuffiCRM.tick.
    func tick() {
        update()
        if lidMode, !onAC, !warnedOnBattery {
            warnedOnBattery = true
            AppState.shared.noteMessage = "🔋 Lid-closed mode is on and the Mac is on battery — it won't sleep in a bag. Business → Connect & devices to turn it off."
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
        }
        if onAC { warnedOnBattery = false }
        SpeedToLead.check()
    }
}

/// Someone wrote and nobody answered: the notch drops down at 5 minutes, and again at 15.
@MainActor
enum SpeedToLead {
    private static var told: [String: Int] = [:]
    private static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f }()

    static func check() {
        guard !ZuffiPlan.shared.isPersonal, ZuffiPlan.shared.isBusiness else { return }   // business alerts only for a business
        let now = Date()
        for l in ZuffiCRM.shared.leads where l.stage == "New" {
            guard let at = fmt.date(from: l.lastMessageAt) else { continue }
            let mins = Int(now.timeIntervalSince(at) / 60)
            guard mins >= 5, mins < 24 * 60 else { continue }
            if !l.lastContact.isEmpty, l.lastContact >= String(l.lastMessageAt.prefix(10)), l.status != "New" { continue }
            let stage = mins >= 15 ? 15 : 5
            let key = l.key + "|" + l.lastMessageAt
            if (told[key] ?? 0) >= stage { continue }
            told[key] = stage
            // Notch layout: "from" line (green) · message · card ("✓ title — detail")
            let msg = "WhatsApp · \(l.display)\n" + (stage == 15 ? "Has waited \(mins) min — reply now or they'll go elsewhere." : "Is waiting for your reply (\(mins) min).")
                + "\n✓ Reply now — Business → Inbox"
            AppState.shared.noteMessage = msg
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.note)
            NotificationCenter.default.post(name: .petSay, object: msg)
        }
        if told.count > 400 { told.removeAll() }
    }
}

/// Business → Connect & devices: power options.
struct BizPowerBox: View {
    @ObservedObject private var power = MacPower.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.batteryblock.fill").foregroundColor(Color(hex: "#FBC56A"))
                Text("Keep Zuffi working").font(.system(size: 14, weight: .bold))
                Spacer()
                Text(power.onAC ? "Charging" : "On battery").font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 9).frame(height: 22).inkPanel(Capsule())
            }
            Toggle(isOn: $power.awakeCharging) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("While charging, don't sleep").font(.system(size: 12.5, weight: .semibold))
                    Text("Zuffi keeps answering WhatsApp and syncing. The screen can still turn off.").font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6))
                }
            }.toggleStyle(.switch)
            Toggle(isOn: Binding(get: { power.lidMode }, set: { power.setLid($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep working with the lid closed").font(.system(size: 12.5, weight: .semibold))
                    Text("macOS asks for your password. Best on the charger — don't leave a closed, running Mac in a bag for long, it can get hot.")
                        .font(.system(size: 10.5)).foregroundColor(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
                }
            }.toggleStyle(.switch)
            if !power.message.isEmpty { Text(power.message).font(.system(size: 10.5)).foregroundColor(Color(hex: "#FBC56A")) }
        }
    }
}
