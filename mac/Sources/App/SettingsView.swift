import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var apiKey: String = KeychainStore.shared.get("anthropic-api-key") ?? ""

    // Claude model — dynamic list fetched from the API, static fallback if unavailable
    private static let fallbackModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6",         "Claude Sonnet 4.6"),
        ("claude-sonnet-5-5",         "Claude Sonnet 5.5"),
        ("claude-opus-5-5",           "Claude Opus 5.5"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]
    private static let customModelTag = "__custom__"
    @State private var fetchedModels: [(id: String, label: String)] = []
    @State private var modelChoice: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? m : SettingsView.customModelTag
    }()
    @State private var customModel: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? "" : m
    }()
    private var displayModels: [(id: String, label: String)] {
        fetchedModels.isEmpty ? Self.fallbackModels : fetchedModels
    }
    @State private var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var statusMessage: String = ""
    // Hotkey
    @State private var hotkeyFlags: UInt    = AppState.shared.hotkeyFlags
    @State private var hotkeyCode: UInt16   = AppState.shared.hotkeyCode

    // Bindings in minutes for the absence field
    private var absenceMinutes: Binding<Double> {
        Binding(
            get: { state.absenceInterval / 60 },
            set: { state.absenceInterval = max(1, $0) * 60 }
        )
    }

    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsHeader(tab: $tab)
            Divider().opacity(0.5)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {

                if tab == .general {
                // MARK: Look & position
                AppearanceSettings(state: state)

                // MARK: Son
                GroupBox("Sound") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable sounds", isOn: $state.soundEnabled)
                        HStack(spacing: 8) {
                            Text("Volume")
                                .frame(width: 56, alignment: .leading)
                            Slider(value: $state.soundVolume, in: 0...0.2)
                                .disabled(!state.soundEnabled)
                            Text("\(Int(state.soundVolume / 0.2 * 100)) %")
                                .frame(width: 36, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                    .padding(6)
                }

                // MARK: Timings
                GroupBox("Behavior") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("Close after")
                            TextField("60", value: $state.autoCloseInterval, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                            Text("s inactive")
                        }
                        HStack(spacing: 8) {
                            Text("Hide after")
                            TextField("3", value: absenceMinutes, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 48)
                            Text("min without movement")
                        }
                    }
                    .padding(6)
                }

                // MARK: Hotkey
                GroupBox("Hotkey") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Ask Sparrow with a keyboard shortcut (opens the chat)", isOn: $state.hotkeyEnabled)
                        if state.hotkeyEnabled {
                            HStack(spacing: 8) {
                                Text("Shortcut")
                                    .frame(width: 70, alignment: .leading)
                                ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                                    .onChange(of: hotkeyFlags) { _, v in state.hotkeyFlags = v }
                                    .onChange(of: hotkeyCode)  { _, v in state.hotkeyCode  = v }
                                Text("presses this → island opens")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(6)
                }

                // MARK: Startup
                GroupBox("Startup") {
                    Toggle("Launch at Mac startup", isOn: $launchAtStartup)
                        .onChange(of: launchAtStartup) { _, on in toggleStartup(on) }
                        .padding(6)
                }
                }

                if tab == .routine {
                RoutineSettings()
                }

                if tab == .voice {
                // MARK: Voice, greeting, notifications, apps
                AssistantSettings(parts: [.voice, .greeting, .notifications])
                }

                if tab == .ai {
                // MARK: AI models (ChatGPT, Gemini, Ollama, Apple)
                AIModelsSettings(state: state)

                // MARK: API
                GroupBox("Claude (Anthropic)") {
                    VStack(alignment: .leading, spacing: 8) {
                        SecureField("API key (sk-ant-…)", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            KeychainStore.shared.set("anthropic-api-key", value: apiKey)
                            statusMessage = "✓ Key saved."
                        }
                        .buttonStyle(.borderedProminent)

                        Divider().padding(.vertical, 2)

                        Picker("Model", selection: $modelChoice) {
                            ForEach(displayModels, id: \.id) { preset in
                                Text(preset.label).tag(preset.id)
                            }
                            Text("Custom…").tag(Self.customModelTag)
                        }
                        .onChange(of: modelChoice) { _, choice in
                            if choice != Self.customModelTag {
                                state.claudeModel = choice
                            } else {
                                applyCustomModel(customModel)
                            }
                        }

                        if modelChoice == Self.customModelTag {
                            TextField("Model ID (e.g. claude-sonnet-4-6)", text: $customModel)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: customModel) { _, value in applyCustomModel(value) }
                        }

                        Text("Used by the chat. The list comes from your Anthropic account.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                }
                }

                if tab == .apps {
                // MARK: Shortcuts (everyday apps & sites)
                ShortcutsSettings(state: state)

                AssistantSettings(parts: [.apps])
                }

                if tab == .health {
                // MARK: Water, coffee & medicine
                HealthSettingsView()
                }

                if tab == .iphone {
                // MARK: Control this Mac from the iPhone
                PhoneLinkSettingsView()
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(statusMessage.hasPrefix("❌") ? .red : .secondary)
                        .padding(.horizontal, 2)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
        }
        }
        .onAppear {
            guard fetchedModels.isEmpty,
                  let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else { return }
            Task {
                let models = await ClaudeService.fetchModels(apiKey: key)
                guard !models.isEmpty else { return }
                await MainActor.run {
                    fetchedModels = models
                    let m = state.claudeModel
                    if models.contains(where: { $0.id == m }) {
                        modelChoice = m
                        customModel = ""
                    } else if modelChoice != Self.customModelTag {
                        modelChoice = Self.customModelTag
                        customModel = m
                    }
                }
            }
        }
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 320, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func applyCustomModel(_ value: String) {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { state.claudeModel = id }
    }

    private func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            statusMessage = "❌ Startup: \(error.localizedDescription)"
            launchAtStartup = !on
        }
    }
}

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                }
                return nil
            }
        } label: {
            Text(isRecording ? "Press keys…" : shortcutLabel)
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? "None" : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Space", 50:"`", 27:"-"
        ]
        return map[c] ?? "·"
    }
}

// MARK: - Settings tabs (friendlier than one long page)

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, routine, voice, ai, apps, health, iphone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general:   return "General"
        case .routine:   return "My day"
        case .voice:     return "Voice"
        case .ai:        return "AI"
        case .apps:      return "Apps"
        case .health:    return "Health"
        case .iphone:    return "iPhone"
        }
    }
    var icon: String {
        switch self {
        case .general:   return "slider.horizontal.3"
        case .routine:   return "sun.horizon.fill"
        case .voice:     return "waveform"
        case .ai:        return "sparkles"
        case .apps:      return "square.grid.2x2"
        case .health:    return "heart.fill"
        case .iphone:    return "iphone"
        }
    }
}

struct SettingsHeader: View {
    @Binding var tab: SettingsTab

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sparrow").font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Your little helper — set it up your way")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }
            HStack(spacing: 6) {
                ForEach(SettingsTab.allCases) { t in
                    Button { withAnimation(.easeOut(duration: 0.15)) { tab = t } } label: {
                        VStack(spacing: 3) {
                            Image(systemName: t.icon).font(.system(size: 14, weight: .semibold))
                            Text(t.title).font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(tab == t ? Color(hex: "#F9A830").opacity(0.22) : Color.clear)
                        )
                        .foregroundColor(tab == t ? Color(hex: "#F28A3C") : .secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}
