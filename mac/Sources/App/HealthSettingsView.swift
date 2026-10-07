import SwiftUI

// =====================================================================
// MARK: - Settings → Health: water, coffee and medicine reminders
// Each one: on/off, every N minutes or at set times, only between two times.
// When one is due the pink sparrow flies in carrying a water bottle, a coffee
// cup or pills, and says it. (The reminders live in Zuffi's shared app, so
// they work the same on iPhone and Windows.)
// =====================================================================

struct HealthReminder: Equatable {
    var on = false
    var mode = "every"          // "every" | "times"
    var every = 120             // minutes
    var times = ""
    var start = "09:00"
    var end = "22:00"
    var name = "medicine"

    init() {}
    init(_ d: [String: Any]) {
        on = d["on"] as? Bool ?? false
        mode = d["mode"] as? String ?? "every"
        every = (d["every"] as? NSNumber)?.intValue ?? 120
        times = d["times"] as? String ?? ""
        start = d["start"] as? String ?? "09:00"
        end = d["end"] as? String ?? "22:00"
        name = d["name"] as? String ?? "medicine"
    }
    var dict: [String: Any] { ["on": on, "mode": mode, "every": every, "times": times, "start": start, "end": end, "name": name] }
}

struct HealthSettingsView: View {
    @State private var items: [String: HealthReminder] = [:]
    @State private var loaded = false
    @State private var saved = false

    private let kinds: [(id: String, title: String, icon: String, color: String, hint: String)] = [
        ("water", "Water", "waterbottle.fill", "#4FA7FF", "Stay hydrated through the day"),
        ("coffee", "Coffee", "cup.and.saucer.fill", "#9A6A48", "A little break — coffee or tea"),
        ("meds", "Medicine", "pills.fill", "#F06A8A", "Never miss your medicine"),
    ]
    private let intervals = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 360]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                LittleSparrow(color: nil, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Little reminders").font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("When it's time, Zuffi flies in carrying your water, coffee or pills.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            if !loaded {
                ProgressView().controlSize(.small)
            } else {
                ForEach(kinds, id: \.id) { k in card(k) }
                HStack {
                    Button(saved ? "Saved ✓" : "Save") { save() }.buttonStyle(.borderedProminent).tint(Color(hex: "#E2648A"))
                    Text("You can also say “Zuffi, remind me to drink water every 30 minutes”.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func card(_ k: (id: String, title: String, icon: String, color: String, hint: String)) -> some View {
        let binding = Binding<HealthReminder>(get: { items[k.id] ?? HealthReminder() }, set: { items[k.id] = $0; saved = false })
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: k.icon).font(.system(size: 18, weight: .semibold)).foregroundColor(Color(hex: k.color))
                        .frame(width: 30, height: 30).background(Circle().fill(Color(hex: k.color).opacity(0.15)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(k.title).font(.system(size: 13, weight: .semibold))
                        Text(k.hint).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: binding.on).toggleStyle(.switch).labelsHidden()
                }
                if binding.wrappedValue.on {
                    if k.id == "meds" {
                        TextField("Medicine name", text: binding.name).textFieldStyle(.roundedBorder).frame(maxWidth: 240)
                    }
                    Picker("", selection: binding.mode) {
                        Text("Every…").tag("every"); Text("At set times").tag("times")
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                    if binding.wrappedValue.mode == "every" {
                        Picker("Remind me every", selection: binding.every) {
                            ForEach(intervals, id: \.self) { m in Text(label(m)).tag(m) }
                        }.frame(maxWidth: 260)
                    } else {
                        HStack {
                            Text("At")
                            TextField("09:00, 13:00, 18:00", text: binding.times).textFieldStyle(.roundedBorder).frame(maxWidth: 200)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("Only between")
                        TextField("09:00", text: binding.start).textFieldStyle(.roundedBorder).frame(width: 64)
                        Text("and")
                        TextField("22:00", text: binding.end).textFieldStyle(.roundedBorder).frame(width: 64)
                        Spacer()
                        Button("Show me") {
                            Task { _ = await WebHub.shared.callJS("return window.Sparrow.testHealth(k)", ["k": k.id]) }
                        }.controlSize(.small)
                    }.font(.system(size: 12))
                }
            }
            .padding(6)
        }
    }

    private func label(_ m: Int) -> String {
        m < 60 ? "\(m) minutes" : m % 60 == 0 ? "\(m / 60) hour\(m > 60 ? "s" : "")" : "\(m / 60)½ hours"
    }

    private func load() async {
        let r = await WebHub.shared.callJS("return window.Sparrow.getHealth ? window.Sparrow.getHealth() : {}") as? [String: Any] ?? [:]
        var out: [String: HealthReminder] = [:]
        for k in ["water", "coffee", "meds"] { out[k] = HealthReminder(r[k] as? [String: Any] ?? [:]) }
        if r["coffee"] == nil { out["coffee"]?.mode = "times"; out["coffee"]?.times = "10:00, 15:00"; out["coffee"]?.start = "08:00"; out["coffee"]?.end = "18:00" }
        if r["meds"] == nil { out["meds"]?.mode = "times"; out["meds"]?.times = "09:00, 21:00" }
        items = out
        loaded = true
    }

    private func save() {
        var payload: [String: Any] = [:]
        for (k, v) in items { payload[k] = v.dict }
        Task {
            _ = await WebHub.shared.callJS("return window.Sparrow.setHealth(h)", ["h": payload])
            saved = true
        }
    }
}
