import SwiftUI
import AppKit

// =====================================================================
// MARK: - Sparrow home: glass cards, a glowing sparrow, and app tiles
// with little sparrows dressed in each app's colours.
// =====================================================================

/// A small sparrow drawn in any colour (used on app tiles instead of logos).
struct MiniSparrow: View {
    let color: Color
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            // head tuft
            Ellipse()
                .fill(color)
                .frame(width: size * 0.2, height: size * 0.3)
                .rotationEffect(.degrees(-24))
                .offset(x: -size * 0.06, y: -size * 0.46)
            // little wing (behind the body edge)
            Ellipse()
                .fill(color.opacity(0.9))
                .frame(width: size * 0.3, height: size * 0.44)
                .rotationEffect(.degrees(28))
                .offset(x: size * 0.4, y: size * 0.1)
            // body
            Circle()
                .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)))
                .frame(width: size, height: size)
            // face / belly
            Ellipse()
                .fill(Color.white.opacity(0.94))
                .frame(width: size * 0.64, height: size * 0.52)
                .offset(y: size * 0.13)
            // eyes
            HStack(spacing: size * 0.17) {
                Circle().fill(Color(hex: "#1A1410")).frame(width: size * 0.12, height: size * 0.12)
                Circle().fill(Color(hex: "#1A1410")).frame(width: size * 0.12, height: size * 0.12)
            }
            .offset(y: size * 0.02)
            // cheeks
            HStack(spacing: size * 0.38) {
                Circle().fill(Color(hex: "#F9A8B8").opacity(0.7)).frame(width: size * 0.09, height: size * 0.09)
                Circle().fill(Color(hex: "#F9A8B8").opacity(0.7)).frame(width: size * 0.09, height: size * 0.09)
            }
            .offset(y: size * 0.13)
            // beak
            BeakShape()
                .fill(Color(hex: "#F59E0B"))
                .frame(width: size * 0.16, height: size * 0.11)
                .offset(y: size * 0.13)
        }
        .frame(width: size * 1.2, height: size * 1.2)
    }
}

private struct BeakShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// One app tile: brand-coloured glass, a sparrow in the app's colours, the name and an arrow.
struct SparrowAppTile: View {
    let item: QuickItem
    @State private var hovered = false

    var body: some View {
        let brand = Color(hex: item.color)
        Button { QuickItems.open(item) } label: {
            HStack(spacing: 7) {
                MiniSparrow(color: brand, size: 22)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.white.opacity(0.16)))
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.5))
                Text(item.name)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 2)
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(hovered ? 1 : 0.75))
                    .offset(x: hovered ? 2 : 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 42, maxHeight: 42)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(LinearGradient(colors: [brand.opacity(hovered ? 0.62 : 0.5), brand.opacity(0.22)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.35), brand.opacity(0.5)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
            )
            .shadow(color: brand.opacity(hovered ? 0.55 : 0.25), radius: hovered ? 9 : 5, y: 2)
            .scaleEffect(hovered ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Open \(item.name)")
    }
}

/// The right-hand card: four favourite apps.
struct SparrowAppGrid: View {
    var body: some View {
        let items = Array(QuickItems.all.prefix(4))
        GlassCard {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(items) { SparrowAppTile(item: $0) }
            }
            .padding(7)
        }
    }
}

/// The left-hand card: the app you're using, whether Sparrow is listening, and a quick action.
/// The sparrow itself (with its golden glow) is drawn on top by the island at the left of this card.
struct SparrowContextCard: View {
    @ObservedObject var state: AppState
    @ObservedObject private var voice = VoiceEngine.shared

    private var appName: String? {
        guard let a = state.lastExternalApp, a.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return a.localizedName
    }

    var body: some View {
        GlassCard(glow: true) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 100)          // room for the sparrow
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "#34D399")).frame(width: 7, height: 7)
                            .shadow(color: Color(hex: "#34D399"), radius: 3)
                        Text(appName ?? "Sparrow")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(appName == nil ? "Assistant" : "In use")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.75))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(Color.white.opacity(0.1)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                    }
                    HStack(spacing: 5) {
                        Circle().fill(voice.isListening ? Color(hex: "#34D399") : Color(hex: "#A39486")).frame(width: 6, height: 6)
                        Text(voice.isListening ? "Listening · just talk to me" : (voice.status.isEmpty ? "Ready · tap the mic or say “Sparrow”" : voice.status))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.78))
                            .lineLimit(1)
                    }
                    HStack(spacing: 7) {
                        Button {
                            if let a = state.lastExternalApp { a.activate(options: .activateIgnoringOtherApps) }
                            else { state.view = .prompt }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: appName == nil ? "sparkles" : "macwindow")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(appName.map { "Open \($0)" } ?? "Ask Sparrow anything")
                                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).opacity(0.7)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Capsule().fill(Color.white.opacity(0.09)))
                            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        Button { VoiceEngine.shared.listenOnce() } label: {
                            Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(voice.isListening ? Color(hex: "#F9A830") : .white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(Color.white.opacity(0.09)))
                                .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Talk to Sparrow")
                    }
                }
                .padding(.trailing, 12)
                Spacer(minLength: 0)
            }
        }
    }
}

/// Frosted glass card with a soft border (and an optional golden glow behind the sparrow).
struct GlassCard<Content: View>: View {
    var glow = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.11), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom))
            if glow {
                RadialGradient(colors: [Color(hex: "#F9A830").opacity(0.42), .clear], center: UnitPoint(x: 0.17, y: 0.55), startRadius: 2, endRadius: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Circle()
                    .stroke(LinearGradient(colors: [Color(hex: "#FFD27A"), Color(hex: "#F28A3C").opacity(0.4)], startPoint: .top, endPoint: .bottom), lineWidth: 1.6)
                    .frame(width: 78, height: 78)
                    .shadow(color: Color(hex: "#F9A830").opacity(0.8), radius: 6)
                    .offset(x: 19)
            }
            content()
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 0.8)
        )
    }
}

// MARK: - Move the island by dragging it

@MainActor
enum IslandDrag {
    private static var startMouse: NSPoint?
    private static var startOrigin: NSPoint?

    static var panel: NSWindow? { NSApp.windows.first { $0 is IslandPanel } }

    static func changed() {
        guard let p = panel else { return }
        let m = NSEvent.mouseLocation
        if startMouse == nil { startMouse = m; startOrigin = p.frame.origin }
        guard let sm = startMouse, let so = startOrigin else { return }
        var o = NSPoint(x: so.x + m.x - sm.x, y: so.y + m.y - sm.y)
        if let s = p.screen ?? NSScreen.main {
            let f = s.frame
            o.x = min(max(o.x, f.minX - 40), f.maxX - p.frame.width + 40)
            o.y = min(max(o.y, f.minY), f.maxY - p.frame.height)
        }
        p.setFrameOrigin(o)
    }

    static func ended() {
        startMouse = nil; startOrigin = nil
        guard let p = panel else { return }
        UserDefaults.standard.set(NSStringFromPoint(p.frame.origin), forKey: "islandOrigin")
    }

    /// Where the person last left the island (nil = default place).
    static var savedOrigin: NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: "islandOrigin"), !s.isEmpty else { return nil }
        return NSPointFromString(s)
    }
}

extension View {
    /// Drag this area to move the whole island anywhere on screen.
    func movesIsland() -> some View {
        gesture(DragGesture(minimumDistance: 3)
            .onChanged { _ in IslandDrag.changed() }
            .onEnded { _ in IslandDrag.ended() })
    }
}
