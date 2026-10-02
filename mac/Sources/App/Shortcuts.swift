import Foundation
import AppKit
import SwiftUI

// MARK: - Shortcuts: the person's own everyday apps & websites as pills

struct QuickItem: Codable, Identifiable, Equatable {
    var id: String          // "shortcut_…"
    var name: String
    var target: String      // app path ("/Applications/Spotify.app") or URL ("https://mail.google.com")
    var color: String       // hex

    var isApp: Bool { target.hasPrefix("/") }
}

@MainActor
enum QuickItems {
    private static let key = "quickItems"

    static let palette = ["#F9A830", "#F28A3C", "#EA4335", "#F472B6", "#A78BFA", "#60A5FA", "#22D3EE", "#25D366", "#1DB954", "#D9A06E"]

    /// Ready-made everyday shortcuts for a brand-new install.
    static let defaults: [QuickItem] = [
        QuickItem(id: "shortcut_gmail",    name: "Gmail",    target: "https://mail.google.com", color: "#EA4335"),
        QuickItem(id: "shortcut_spotify",  name: "Spotify",  target: "spotify",                 color: "#1DB954"),
        QuickItem(id: "shortcut_whatsapp", name: "WhatsApp", target: "whatsapp",                color: "#25D366"),
        QuickItem(id: "shortcut_youtube",  name: "YouTube",  target: "https://www.youtube.com", color: "#F472B6"),
        QuickItem(id: "shortcut_calendar", name: "Calendar", target: "calendar",                color: "#F9A830"),
        QuickItem(id: "shortcut_chatgpt",  name: "ChatGPT",  target: "https://chatgpt.com",     color: "#60A5FA"),
    ]

    static var all: [QuickItem] {
        if let d = UserDefaults.standard.data(forKey: key),
           let items = try? JSONDecoder().decode([QuickItem].self, from: d) { return items }
        return defaults
    }

    static func save(_ items: [QuickItem]) {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func tasks() -> [AgentTask] {
        all.map { AgentTask(id: $0.id, name: $0.name, color: $0.color, state: .idle, steps: [], source: .n8n, isIntegration: true) }
    }

    static func open(id: String) {
        guard let item = all.first(where: { $0.id == id }) else { return }
        open(item)
    }

    static func open(_ item: QuickItem) {
        SoundEngine.shared.play("pop")
        if item.isApp {
            let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: item.target), configuration: cfg, completionHandler: nil)
        } else if item.target.hasPrefix("http"), let url = URL(string: item.target) {
            NSWorkspace.shared.open(url)
        } else {
            // A plain name ("spotify") — let the command engine find the app or website.
            Task { _ = await CommandEngine.shared.handle("open \(item.target)") }
        }
    }
}

// MARK: - Settings: manage shortcuts

struct ShortcutsSettings: View {
    @ObservedObject var state: AppState
    @State private var items: [QuickItem] = QuickItems.all
    @State private var newName = ""
    @State private var newKind = "app"        // "app" | "web"
    @State private var newApp = ""            // app path
    @State private var newURL = ""
    @State private var newColor = QuickItems.palette[0]

    var body: some View {
        GroupBox("Shortcuts — your everyday apps & websites") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pick up to 4 to show next to the sparrow. One tap opens them. They share the 4 slots with the integrations below.")
                    .font(.system(size: 11)).foregroundColor(.secondary)

                ForEach(items) { item in
                    HStack(spacing: 8) {
                        Circle().fill(Color(hex: item.color)).frame(width: 8, height: 8)
                        Text(item.name).font(.system(size: 12, weight: .medium))
                        Text(item.isApp ? URL(fileURLWithPath: item.target).deletingPathExtension().lastPathComponent : item.target)
                            .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                        Spacer()
                        Button { QuickItems.open(item) } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(.plain).help("Open")
                        Button { remove(item) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundColor(.secondary).help("Delete")
                        Toggle("", isOn: Binding(
                            get: { state.activeIntegrations.contains(item.id) },
                            set: { _ in state.toggleIntegration(item.id) }
                        ))
                        .toggleStyle(.checkbox)
                        .disabled(!state.activeIntegrations.contains(item.id) && state.activeIntegrations.count >= 4)
                    }
                }

                Divider()
                Text("Add a shortcut").font(.system(size: 12, weight: .semibold))
                Picker("", selection: $newKind) {
                    Text("App").tag("app")
                    Text("Website").tag("web")
                }
                .pickerStyle(.segmented).labelsHidden()

                if newKind == "app" {
                    Picker("App", selection: $newApp) {
                        Text("Choose an app…").tag("")
                        ForEach(CommandEngine.shared.allApps(), id: \.url) { app in
                            Text(app.name).tag(app.url.path)
                        }
                    }
                    .onChange(of: newApp) { _, path in
                        if !path.isEmpty { newName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
                    }
                } else {
                    TextField("Website, e.g. notion.so or https://…", text: $newURL).textFieldStyle(.roundedBorder)
                }
                TextField("Name shown on the pill", text: $newName).textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                    ForEach(QuickItems.palette, id: \.self) { hex in
                        Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Color.primary.opacity(newColor == hex ? 0.8 : 0), lineWidth: 2))
                            .onTapGesture { newColor = hex }
                    }
                }
                Button("Add shortcut") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty
                              || (newKind == "app" ? newApp.isEmpty : newURL.trimmingCharacters(in: .whitespaces).isEmpty))
            }
            .padding(6)
        }
    }

    private func add() {
        var target = newKind == "app" ? newApp : newURL.trimmingCharacters(in: .whitespaces)
        if newKind == "web", !target.hasPrefix("http") { target = "https://" + target }
        let item = QuickItem(id: "shortcut_\(UUID().uuidString.prefix(8))",
                             name: newName.trimmingCharacters(in: .whitespaces), target: target, color: newColor)
        items.append(item)
        QuickItems.save(items)
        if state.activeIntegrations.count < 4 { state.toggleIntegration(item.id) }
        newName = ""; newApp = ""; newURL = ""
    }

    private func remove(_ item: QuickItem) {
        if state.activeIntegrations.contains(item.id) { state.toggleIntegration(item.id) }
        items.removeAll { $0.id == item.id }
        QuickItems.save(items)
    }
}
