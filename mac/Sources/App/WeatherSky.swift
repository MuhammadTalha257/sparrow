import SwiftUI
import Foundation

/// The live weather where the Mac is right now, used to paint little animations on Zuffi's notch tab.
/// Free Open-Meteo, no key. Refreshes every 20 minutes; stays quiet (clear sky) when offline.
@MainActor
final class WeatherSky: ObservableObject {
    static let shared = WeatherSky()

    enum Kind: String { case clear, partly, cloudy, fog, drizzle, rain, snow, storm }

    @Published private(set) var kind: Kind = .clear
    @Published private(set) var isDay = true
    @Published private(set) var temp: Int?
    private var lastFetch: Date?
    private var loading = false

    func refreshIfNeeded() {
        if loading { return }
        if let t = lastFetch, Date().timeIntervalSince(t) < 20 * 60 { return }
        loading = true
        Task { @MainActor in
            defer { self.loading = false }
            guard let loc = await Weather.location() else { return }
            let useF = Locale.current.measurementSystem == .us
            var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            c.queryItems = [
                .init(name: "latitude", value: String(loc.lat)), .init(name: "longitude", value: String(loc.lon)),
                .init(name: "current", value: "temperature_2m,weather_code,is_day"),
                .init(name: "timezone", value: "auto"),
                .init(name: "temperature_unit", value: useF ? "fahrenheit" : "celsius"),
            ]
            guard let url = c.url, let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = json["current"] as? [String: Any] else { return }
            let code = cur["weather_code"] as? Int ?? 0
            self.kind = Self.kind(code)
            self.isDay = (cur["is_day"] as? Int ?? 1) == 1
            if let t = cur["temperature_2m"] as? Double { self.temp = Int(t.rounded()) }
            self.lastFetch = Date()
        }
    }

    static func kind(_ code: Int) -> Kind {
        switch code {
        case 0: return .clear
        case 1, 2: return .partly
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51...57: return .drizzle
        case 61...67, 80...82: return .rain
        case 71...77, 85, 86: return .snow
        case 95...99: return .storm
        default: return .clear
        }
    }

    /// Soft tint for the glass at the bottom of the tab.
    var tint: Color {
        switch (kind, isDay) {
        case (.clear, true): return Color(red: 1.0, green: 0.72, blue: 0.30)
        case (.clear, false), (.partly, false): return Color(red: 0.42, green: 0.45, blue: 0.95)
        case (.partly, true): return Color(red: 0.55, green: 0.75, blue: 1.0)
        case (.cloudy, _), (.fog, _): return Color(red: 0.70, green: 0.74, blue: 0.82)
        case (.drizzle, _), (.rain, _): return Color(red: 0.35, green: 0.62, blue: 1.0)
        case (.snow, _): return Color(red: 0.85, green: 0.93, blue: 1.0)
        case (.storm, _): return Color(red: 0.62, green: 0.45, blue: 1.0)
        }
    }

    var symbol: String {
        switch (kind, isDay) {
        case (.clear, true): return "sun.max.fill"
        case (.clear, false): return "moon.stars.fill"
        case (.partly, true): return "cloud.sun.fill"
        case (.partly, false): return "cloud.moon.fill"
        case (.cloudy, _): return "cloud.fill"
        case (.fog, _): return "cloud.fog.fill"
        case (.drizzle, _): return "cloud.drizzle.fill"
        case (.rain, _): return "cloud.rain.fill"
        case (.snow, _): return "cloud.snow.fill"
        case (.storm, _): return "cloud.bolt.rain.fill"
        }
    }
}

/// Glassy notch tab background: black where it meets the real notch, fading into a frosted, weather-tinted
/// glass at the bottom, with gentle animated weather (rain, snow, sun rays, drifting clouds, twinkling stars).
struct WeatherGlass: View {
    @ObservedObject var sky = WeatherSky.shared
    var radius: CGFloat = 26

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0), style: .continuous)
    }

    var body: some View {
        ZStack {
            shape.fill(Color.black)
            shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark).opacity(0.55)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .init(x: 0.5, y: 0.35), endPoint: .bottom))
            shape.fill(LinearGradient(colors: [.black, .black.opacity(0.85), sky.tint.opacity(0.28)],
                                      startPoint: .top, endPoint: .bottom))
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                Canvas { ctx, size in
                    WeatherPainter.paint(ctx: &ctx, size: size, t: tl.date.timeIntervalSinceReferenceDate,
                                         kind: sky.kind, day: sky.isDay)
                }
            }
            .mask(LinearGradient(colors: [.clear, .black, .black], startPoint: .top, endPoint: .bottom))
            .clipShape(shape)
            .allowsHitTesting(false)
            // glass sheen + rim light
            shape.fill(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.07), .white.opacity(0.0)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .allowsHitTesting(false)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.10), sky.tint.opacity(0.45)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: sky.tint.opacity(0.22), radius: 12, y: 4)
        .animation(.easeInOut(duration: 1.2), value: sky.kind)
        .onAppear { sky.refreshIfNeeded() }
    }
}

enum WeatherPainter {
    /// Cheap stable pseudo-random in 0...1 for particle i.
    private static func r(_ i: Int, _ salt: Int) -> Double {
        let x = sin(Double(i * 127 + salt * 311) * 12.9898) * 43758.5453
        return x - floor(x)
    }

    static func paint(ctx: inout GraphicsContext, size: CGSize, t: Double, kind: WeatherSky.Kind, day: Bool) {
        let w = size.width, h = size.height
        switch kind {
        case .clear:
            if day { sun(&ctx, w, h, t) } else { stars(&ctx, w, h, t, count: 18) }
        case .partly:
            if day { sun(&ctx, w, h, t) } else { stars(&ctx, w, h, t, count: 10) }
            clouds(&ctx, w, h, t, count: 2, alpha: 0.22)
        case .cloudy:
            clouds(&ctx, w, h, t, count: 4, alpha: 0.26)
        case .fog:
            fog(&ctx, w, h, t)
        case .drizzle:
            clouds(&ctx, w, h, t, count: 2, alpha: 0.18)
            rain(&ctx, w, h, t, count: 14, speed: 38, len: 5, alpha: 0.45)
        case .rain:
            clouds(&ctx, w, h, t, count: 2, alpha: 0.18)
            rain(&ctx, w, h, t, count: 30, speed: 70, len: 8, alpha: 0.55)
        case .snow:
            snow(&ctx, w, h, t)
        case .storm:
            clouds(&ctx, w, h, t, count: 3, alpha: 0.24)
            rain(&ctx, w, h, t, count: 34, speed: 85, len: 9, alpha: 0.55)
            lightning(&ctx, w, h, t)
        }
    }

    private static func sun(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        let c = CGPoint(x: w * 0.86, y: h * 0.62)
        let pulse = 1 + 0.08 * sin(t * 1.6)
        let glow = Path(ellipseIn: CGRect(x: c.x - 26 * pulse, y: c.y - 26 * pulse, width: 52 * pulse, height: 52 * pulse))
        ctx.fill(glow, with: .radialGradient(Gradient(colors: [Color.orange.opacity(0.45), .clear]),
                                             center: c, startRadius: 2, endRadius: 26 * pulse))
        for i in 0..<10 {
            let a = Double(i) / 10 * .pi * 2 + t * 0.25
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(a) * 9, y: c.y + sin(a) * 9))
            p.addLine(to: CGPoint(x: c.x + cos(a) * (15 + 2 * sin(t * 2 + Double(i))), y: c.y + sin(a) * (15 + 2 * sin(t * 2 + Double(i)))))
            ctx.stroke(p, with: .color(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.55)), style: .init(lineWidth: 1.4, lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)),
                 with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.85)))
    }

    private static func stars(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double, count: Int) {
        for i in 0..<count {
            let x = r(i, 1) * w, y = h * 0.3 + r(i, 2) * h * 0.65
            let tw = 0.35 + 0.65 * max(0, sin(t * (0.8 + r(i, 3) * 1.6) + r(i, 4) * 6))
            let s = 0.8 + r(i, 5) * 1.3
            ctx.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)), with: .color(.white.opacity(0.75 * tw)))
        }
        // crescent moon
        let c = CGPoint(x: w * 0.87, y: h * 0.62)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)), with: .color(Color(white: 0.95).opacity(0.8)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.5, y: c.y - 8, width: 12, height: 12)), with: .color(.black.opacity(0.9)))
    }

    private static func clouds(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double, count: Int, alpha: Double) {
        for i in 0..<count {
            let speed = 4 + r(i, 7) * 5
            let span = w + 80
            let x = (r(i, 8) * span + t * speed).truncatingRemainder(dividingBy: span) - 40
            let y = h * (0.45 + r(i, 9) * 0.35)
            let s = 0.8 + r(i, 10) * 0.6
            var p = Path()
            p.addEllipse(in: CGRect(x: x, y: y, width: 26 * s, height: 10 * s))
            p.addEllipse(in: CGRect(x: x + 6 * s, y: y - 6 * s, width: 14 * s, height: 12 * s))
            p.addEllipse(in: CGRect(x: x + 13 * s, y: y - 3 * s, width: 12 * s, height: 10 * s))
            ctx.fill(p, with: .color(.white.opacity(alpha)))
        }
    }

    private static func fog(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        for i in 0..<3 {
            let y = h * (0.5 + Double(i) * 0.16)
            let off = sin(t * 0.4 + Double(i)) * 18
            var p = Path()
            p.addRoundedRect(in: CGRect(x: -20 + off, y: y, width: w + 40, height: 4), cornerSize: CGSize(width: 2, height: 2))
            ctx.fill(p, with: .color(.white.opacity(0.12 + 0.05 * Double(i))))
        }
    }

    private static func rain(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double, count: Int, speed: Double, len: Double, alpha: Double) {
        for i in 0..<count {
            let x0 = r(i, 11) * (w + 20) - 10
            let sp = speed * (0.75 + r(i, 12) * 0.5)
            let y = (r(i, 13) * (h + len) + t * sp).truncatingRemainder(dividingBy: h + len) - len
            let x = x0 - (y / h) * 4
            var p = Path()
            p.move(to: CGPoint(x: x, y: y))
            p.addLine(to: CGPoint(x: x - 1.5, y: y + len))
            ctx.stroke(p, with: .color(Color(red: 0.7, green: 0.85, blue: 1).opacity(alpha * (0.5 + r(i, 14) * 0.5))),
                       style: .init(lineWidth: 1, lineCap: .round))
        }
    }

    private static func snow(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        for i in 0..<26 {
            let sp = 8 + r(i, 15) * 10
            let y = (r(i, 16) * (h + 6) + t * sp).truncatingRemainder(dividingBy: h + 6) - 3
            let x = r(i, 17) * w + sin(t * (0.6 + r(i, 18)) + Double(i)) * 5
            let s = 1.4 + r(i, 19) * 1.8
            ctx.fill(Path(ellipseIn: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)), with: .color(.white.opacity(0.55 + 0.35 * r(i, 20))))
        }
    }

    private static func lightning(_ ctx: inout GraphicsContext, _ w: Double, _ h: Double, _ t: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 6.0)
        guard cycle < 0.18 else { return }
        let flash = cycle < 0.06 || (cycle > 0.11 && cycle < 0.16)
        guard flash else { return }
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(Color(red: 0.8, green: 0.8, blue: 1).opacity(0.18)))
        let x = w * (0.2 + r(Int(t / 6), 21) * 0.6)
        var p = Path()
        p.move(to: CGPoint(x: x, y: h * 0.3))
        p.addLine(to: CGPoint(x: x - 4, y: h * 0.55))
        p.addLine(to: CGPoint(x: x + 2, y: h * 0.58))
        p.addLine(to: CGPoint(x: x - 3, y: h * 0.9))
        ctx.stroke(p, with: .color(.white.opacity(0.85)), style: .init(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }
}
