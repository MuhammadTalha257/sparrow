import SwiftUI

// =====================================================================
// MARK: - Liquid glass for every macOS
//
// On macOS 26 (Tahoe) Zuffi uses Apple's own Liquid Glass. On macOS 14–15 this draws the same
// feel by hand: a real blur of what's behind, a tinted body, a bright sheen across the top,
// a soft coloured glow inside, a light rim that catches the light and a gentle lift on hover.
// (Same look as liquidGL on the phone / web app.)
// =====================================================================

struct LiquidGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var tint: Color? = nil
    var glow: Color = Color(hex: "#F58FA8")
    var interactive = false
    @State private var hover = false

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else { drawn(content) }
        #else
        drawn(content)
        #endif
    }

    private func drawn(_ content: Content) -> some View {
        content
            .background(
                ZStack {
                    shape.fill(.ultraThinMaterial)                                   // real blur of what's behind
                    shape.fill(LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.13 : 0.34), (tint ?? .white).opacity(tint == nil ? 0.03 : 0.12)],
                                              startPoint: .top, endPoint: .bottom))   // glass body
                    shape.fill(LinearGradient(stops: [.init(color: .white.opacity(hover ? 0.36 : 0.26), location: 0),
                                                      .init(color: .white.opacity(0.07), location: 0.34),
                                                      .init(color: .clear, location: 0.52)], startPoint: .top, endPoint: .bottom))   // sheen
                    shape.fill(RadialGradient(colors: [glow.opacity(hover ? 0.28 : 0.16), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 180))   // inner glow
                }
            )
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.10), .white.opacity(0.30)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))   // rim light
            .overlay(shape.inset(by: 1.5).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))                             // inner rim
            .shadow(color: .black.opacity(0.28), radius: hover ? 18 : 12, y: hover ? 9 : 6)
            .scaleEffect(interactive && hover ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
            .onHover { if interactive { hover = $0 } }
    }
}

extension View {
    func liquidGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, glow: Color = Color(hex: "#F58FA8"), interactive: Bool = false) -> some View {
        modifier(LiquidGlass(shape: shape, tint: tint, glow: glow, interactive: interactive))
    }
}

/// Glass for the side buttons on Zuffi's home: circle / rounded square / capsule.
struct SideGlass: ViewModifier {
    var round: Bool
    var square: Bool
    var tint: Color
    func body(content: Content) -> some View {
        Group {
            if round && square { content.liquidGlass(RoundedRectangle(cornerRadius: 10, style: .continuous), tint: tint.opacity(0.35), glow: tint, interactive: true) }
            else if round { content.liquidGlass(Circle(), tint: tint.opacity(0.35), glow: tint, interactive: true) }
            else { content.liquidGlass(Capsule(), tint: tint.opacity(0.35), glow: tint, interactive: true) }
        }
        .shadow(color: tint.opacity(0.35), radius: 7)
    }
}
