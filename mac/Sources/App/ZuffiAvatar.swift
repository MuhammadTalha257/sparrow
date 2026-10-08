import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

// =====================================================================
// MARK: - How Zuffi looks
//
// The fluffy bunny (in eight fur colours), any emoji, or your own picture.
// The full-body bunny walks across the screen on its own two feet, and while
// it listens it cups a paw to its ear.
// =====================================================================

@MainActor
final class ZuffiLook: ObservableObject {
    static let shared = ZuffiLook()

    enum Kind: String, CaseIterable { case bunny, emoji, photo }

    struct Fur: Identifiable { let id: String; let name: String; let multiply: String; let hue: Double }
    static let furs: [Fur] = [
        Fur(id: "snow", name: "Snow", multiply: "#FFFFFF", hue: 0),
        Fur(id: "blush", name: "Blush", multiply: "#FFD3DF", hue: 0),
        Fur(id: "peach", name: "Peach", multiply: "#FFDDBF", hue: 0),
        Fur(id: "honey", name: "Honey", multiply: "#F7DA94", hue: 0),
        Fur(id: "mint", name: "Mint", multiply: "#C8F2DD", hue: 120),
        Fur(id: "sky", name: "Sky", multiply: "#C9E4FF", hue: 190),
        Fur(id: "lilac", name: "Lilac", multiply: "#E2D2FF", hue: 250),
        Fur(id: "cocoa", name: "Cocoa", multiply: "#C9A27E", hue: 0),
        Fur(id: "storm", name: "Storm", multiply: "#A9B2C6", hue: 200),
    ]

    /// Emoji you can pick instead of the bunny (like Coucou), grouped loosely.
    static let emojis: [String] = [
        "🐰", "🐇", "🐱", "🐶", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧",
        "🐦", "🐤", "🦉", "🦄", "🐝", "🦋", "🐢", "🐙", "🐳", "🐬", "🦭", "🦦", "🦥", "🐿️", "🦔", "🐹",
        "😀", "😊", "🥰", "😎", "🤓", "🥳", "🤩", "😇", "🤗", "🤠", "😺", "👻", "👽", "🤖", "🎃", "💩",
        "🧸", "🌸", "🌻", "🌈", "⭐️", "🌙", "☀️", "🔥", "💎", "🍓", "🍑", "🍩", "🧁", "🍪", "☕️", "🎀",
        "💗", "💜", "💙", "💚", "🧡", "🤍", "✨", "🎈", "🎮", "🎧", "📚", "🚀", "🪐", "🍀", "🌵", "🪴",
    ]

    @Published var kind: Kind { didSet { save() } }
    @Published var fur: String { didSet { save() } }
    @Published var emoji: String { didSet { save() } }
    @Published private(set) var photo: CGImage?
    /// Softly shifting colours behind the chat (on by default).
    @Published var animatedBackground: Bool { didSet { save() } }

    private let ud = UserDefaults.standard
    private static var folder: URL {
        let d = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Zuffi")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static var photoURL: URL { folder.appendingPathComponent("avatar.png") }

    private init() {
        kind = Kind(rawValue: UserDefaults.standard.string(forKey: "zuffiKind") ?? "") ?? .bunny
        fur = UserDefaults.standard.string(forKey: "zuffiFur") ?? "snow"
        emoji = UserDefaults.standard.string(forKey: "zuffiEmoji") ?? "🐰"
        animatedBackground = UserDefaults.standard.object(forKey: "zuffiAnimatedBg") as? Bool ?? true
        photo = Self.load(Self.photoURL)
        if kind == .photo && photo == nil { kind = .bunny }
    }

    private func save() {
        ud.set(kind.rawValue, forKey: "zuffiKind")
        ud.set(fur, forKey: "zuffiFur")
        ud.set(emoji, forKey: "zuffiEmoji")
        ud.set(animatedBackground, forKey: "zuffiAnimatedBg")
    }

    var currentFur: Fur { Self.furs.first { $0.id == fur } ?? Self.furs[0] }
    var furColor: Color { Color(hex: currentFur.multiply) }

    private static func load(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(src, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }

    /// Lets the person pick a picture; it's copied (512 px) so the original can move.
    func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Pick a picture for Zuffi"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let img = Self.load(url) else { return }
        if let dest = CGImageDestinationCreateWithURL(Self.photoURL as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
        photo = img
        kind = .photo
    }

    func removePhoto() {
        try? FileManager.default.removeItem(at: Self.photoURL)
        photo = nil
        if kind == .photo { kind = .bunny }
    }
}

/// The full-body bunny, cut into body + two legs so it can step.
@MainActor
final class ZuffiBodyArt {
    static let shared = ZuffiBodyArt()
    let top: CGImage?, legL: CGImage?, legR: CGImage?, armL: CGImage?, armR: CGImage?, paw: CGImage?
    private init() {
        func load(_ n: String) -> CGImage? {
            guard let u = Bundle.main.resourceURL?.appendingPathComponent("web/mascots/\(n)"),
                  let s = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(s, 0, nil)
        }
        top = load("zuffi-walk-top.webp"); legL = load("zuffi-walk-legL.webp"); legR = load("zuffi-walk-legR.webp")
        armL = load("zuffi-walk-armL.webp"); armR = load("zuffi-walk-armR.webp")
        paw = load("zuffi-paw.webp")
    }
    var available: Bool { top != nil && legL != nil && legR != nil && armL != nil && armR != nil }
}

/// The face part of the avatar — the bunny frame, an emoji or a photo.
struct ZuffiFace: View {
    let frame: CGImage?
    let size: CGFloat
    var mood: SpriteMood = .idle
    @ObservedObject private var look = ZuffiLook.shared

    var body: some View {
        switch look.kind {
        case .emoji:
            Text(look.emoji)
                .font(.system(size: size * 0.7))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        case .photo:
            if let p = look.photo {
                Image(decorative: p, scale: 1).resizable().interpolation(.high).scaledToFill()
                    .frame(width: size * 0.84, height: size * 0.84)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: max(2, size * 0.03)))
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                    .frame(width: size, height: size)
            }
        case .bunny:
            if let f = frame {
                ZStack {
                    Image(decorative: f, scale: 1).resizable().interpolation(.high).antialiased(true)
                        .frame(width: size, height: size)
                        .zuffiFur(look)
                    if mood == .listening, let paw = ZuffiBodyArt.shared.paw {
                        // a paw cupped to the ear, like someone listening closely
                        Image(decorative: paw, scale: 1).resizable().interpolation(.high)
                            .frame(width: size * 0.24, height: size * 0.25)
                            .zuffiFur(look)
                            .rotationEffect(.degrees(-28))
                            .offset(x: size * 0.33, y: -size * 0.02)
                            .shadow(color: .black.opacity(0.15), radius: 2, x: -1, y: 1)
                            .transition(.scale(scale: 0.3, anchor: .bottomTrailing).combined(with: .opacity))
                    }
                }
                .rotationEffect(.degrees(mood == .listening ? 7 : 0))
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: mood)
            }
        }
    }
}

extension View {
    /// Dyes the white fur (pink inner ears and cheeks shift with it).
    func zuffiFur(_ look: ZuffiLook) -> some View {
        let f = look.currentFur
        return self.hueRotation(.degrees(f.hue)).colorMultiply(Color(hex: f.multiply))
    }
}

/// The whole bunny walking on its feet: legs take turns, the body bobs and leans into the step.
struct ZuffiWalker: View {
    var height: CGFloat
    var walking: Bool
    var facingLeft: Bool = false
    var speed: Double = 1
    @ObservedObject private var look = ZuffiLook.shared
    @State private var start = Date()

    var body: some View {
        let art = ZuffiBodyArt.shared
        let w = height * 330 / 648
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !walking)) { tl in
            let t = tl.date.timeIntervalSince(start) * 4.4 * speed      // about 1.4 steps a second
            let s = walking ? sin(t) : 0
            let px = w / 330                                              // art pixels → points
            Group {
                if look.kind == .bunny, art.available {
                    ZStack {
                        // legs: one foot lifts while the other carries the weight
                        Image(decorative: art.legL!, scale: 1).resizable().interpolation(.high)
                            .offset(x: -max(0, s) * 3 * px, y: -max(0, s) * height * 0.045)
                        Image(decorative: art.legR!, scale: 1).resizable().interpolation(.high)
                            .offset(x: max(0, -s) * 3 * px, y: -max(0, -s) * height * 0.045)
                        // body + swinging arms, waddling over the planted foot
                        ZStack {
                            Image(decorative: art.top!, scale: 1).resizable().interpolation(.high)
                            Image(decorative: art.armL!, scale: 1).resizable().interpolation(.high)
                                .rotationEffect(.degrees(s * 16), anchor: UnitPoint(x: 0.194, y: 0.665))
                            Image(decorative: art.armR!, scale: 1).resizable().interpolation(.high)
                                .rotationEffect(.degrees(s * 16), anchor: UnitPoint(x: 0.806, y: 0.671))
                        }
                        .rotationEffect(.degrees(-s * 3.5), anchor: UnitPoint(x: 0.5, y: 0.85))
                        .offset(x: s * 5 * px, y: -abs(s) * height * 0.012)
                    }
                    .frame(width: w, height: height)
                    .zuffiFur(look)
                    .scaleEffect(x: facingLeft ? -1 : 1, y: 1)
                } else {
                    // emoji / photo: little hops instead of steps
                    ZuffiFace(frame: SparrowSprites.shared.directions.count == 9 ? SparrowSprites.shared.directions[facingLeft ? 3 : 5] : nil, size: w * 1.5)
                        .offset(y: -abs(s) * height * 0.08)
                        .frame(width: w * 1.5, height: height, alignment: .bottom)
                }
            }
        }
        .frame(width: max(w, look.kind == .bunny ? w : w * 1.5), height: height)
    }
}

// MARK: - Settings → Look

struct ZuffiLookSettings: View {
    @ObservedObject private var look = ZuffiLook.shared

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How Zuffi looks").font(.system(size: 13, weight: .semibold))
                        Picker("", selection: $look.kind) {
                            Text("Bunny").tag(ZuffiLook.Kind.bunny)
                            Text("Emoji").tag(ZuffiLook.Kind.emoji)
                            if look.photo != nil { Text("My picture").tag(ZuffiLook.Kind.photo) }
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 260)
                        HStack {
                            Button(look.photo == nil ? "Use my own picture…" : "Change picture…") { look.choosePhoto() }
                            if look.photo != nil { Button("Remove picture") { look.removePhoto() } }
                        }.controlSize(.small)
                    }
                }
                if look.kind == .bunny {
                    Text("Fur colour").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        ForEach(ZuffiLook.furs) { f in
                            Button { look.fur = f.id } label: {
                                Circle().fill(Color(hex: f.multiply))
                                    .overlay(Circle().strokeBorder(look.fur == f.id ? Color(hex: "#E2648A") : Color.black.opacity(0.15), lineWidth: look.fur == f.id ? 3 : 1))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain).help(f.name)
                        }
                    }
                }
                if look.kind == .emoji {
                    Text("Pick an emoji").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 16), spacing: 4) {
                        ForEach(ZuffiLook.emojis, id: \.self) { e in
                            Button { look.emoji = e } label: {
                                Text(e).font(.system(size: 20)).frame(width: 30, height: 30)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(look.emoji == e ? Color(hex: "#E2648A").opacity(0.25) : .clear))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Toggle("Softly moving colours behind the chat", isOn: $look.animatedBackground)
            }
            .padding(6)
        }
    }

    private var preview: some View {
        ZStack {
            Circle().fill(Color(hex: "#FBE3EB")).frame(width: 78, height: 78)
            if look.kind == .bunny && ZuffiBodyArt.shared.available {
                ZuffiWalker(height: 74, walking: false)
            } else {
                ZuffiFace(frame: SparrowSprites.shared.directions.count == 9 ? SparrowSprites.shared.directions[4] : nil, size: 70)
            }
        }
        .frame(width: 80, height: 80)
    }
}

// MARK: - Animated background

/// Slow drifting colour blobs (pink, peach, lilac) behind the chat — the "alive" feel from the video.
struct ZuffiAnimatedBackground: View {
    var base: Color = Color(hex: "#1A1014")
    @ObservedObject private var look = ZuffiLook.shared

    var body: some View {
        if look.animatedBackground {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
                    let blobs: [(String, Double, Double, Double)] = [
                        ("#E2648A", 0.11, 0.0, 0.75), ("#F7A072", 0.07, 2.1, 0.6), ("#8B5CF6", 0.09, 4.2, 0.7), ("#4FA7FF", 0.05, 1.3, 0.5),
                    ]
                    var g = ctx
                    g.addFilter(.blur(radius: min(size.width, size.height) * 0.22))
                    for (hex, sp, ph, r) in blobs {
                        let x = size.width * (0.5 + 0.42 * cos(t * sp + ph))
                        let y = size.height * (0.5 + 0.38 * sin(t * sp * 1.3 + ph))
                        let rad = min(size.width, size.height) * r * 0.5
                        g.fill(Path(ellipseIn: CGRect(x: x - rad, y: y - rad, width: rad * 2, height: rad * 2)), with: .color(Color(hex: hex).opacity(0.38)))
                    }
                }
            }
            .allowsHitTesting(false)
        } else {
            base.allowsHitTesting(false)
        }
    }
}

/// Little switches: the notch glow, the "hey" on open, the pet's strolls.
struct ZuffiExtrasSettings: View {
    @ObservedObject private var glow = EdgeGlow.shared
    @AppStorage("helloOnOpen") private var hello = true
    @AppStorage("petStroll") private var stroll = true
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Glow around the notch (charging, Caps Lock, Cut, agents needing you)", isOn: $glow.enabled)
                Toggle("Pop up and say hey when Zuffi opens", isOn: $hello)
                Toggle("Let the bunny stroll around the screen now and then", isOn: $stroll)
            }
            .padding(6)
        }
    }
}
