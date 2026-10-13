import Foundation
import SwiftUI

// =====================================================================
// MARK: - Zuffi's outfits & seasons on the Mac
// The same nine looks as the phone and Windows (web/mascots/outfits/…): winter, Ramadan, Eid,
// 14 August, Christmas, Halloween, Valentine's, birthday, summer. "Automatic" follows the calendar —
// the Islamic calendar for Ramadan and Eid — and your birthday comes first.
// =====================================================================

struct ZuffiSeason: Identifiable, Equatable {
    let id: String, name: String, icon: String
    let accent: String?          // the season's colour
    let sky: [String]            // top → bottom, empty = everyday graphite
    let fx: String?              // snow · stars · confetti · hearts · embers · sun
    let says: String
}

enum ZuffiSeasons {
    static let all: [ZuffiSeason] = [
        .init(id: "none", name: "Everyday", icon: "🐰", accent: nil, sky: [], fx: nil, says: ""),
        .init(id: "winter", name: "Winter", icon: "❄️", accent: "#8EC5FF", sky: ["#13213A", "#2B4A6E"], fx: "snow", says: "Wrap up warm today."),
        .init(id: "ramadan", name: "Ramadan", icon: "🌙", accent: "#E9C46A", sky: ["#0B1A24", "#1B3546"], fx: "stars", says: "Ramadan Mubarak."),
        .init(id: "eid", name: "Eid", icon: "✨", accent: "#4FD1A5", sky: ["#0E2823", "#1D4A3F"], fx: "confetti", says: "Eid Mubarak!"),
        .init(id: "independence", name: "14 August", icon: "🇵🇰", accent: "#2FA866", sky: ["#0A2414", "#145230"], fx: "confetti", says: "Jashn-e-Azadi Mubarak!"),
        .init(id: "christmas", name: "Christmas", icon: "🎄", accent: "#F0525A", sky: ["#1E1115", "#3A1D24"], fx: "snow", says: "Merry Christmas!"),
        .init(id: "halloween", name: "Halloween", icon: "🎃", accent: "#F28A3C", sky: ["#16101D", "#33203B"], fx: "embers", says: "Happy Halloween!"),
        .init(id: "valentine", name: "Valentine’s", icon: "💗", accent: "#F27BA1", sky: ["#25101B", "#47203A"], fx: "hearts", says: "Happy Valentine’s Day."),
        .init(id: "birthday", name: "My birthday", icon: "🎂", accent: "#B79CFF", sky: ["#19152E", "#352C5E"], fx: "confetti", says: "Happy birthday!"),
        .init(id: "summer", name: "Summer", icon: "🌺", accent: "#FFC857", sky: ["#0E2C3C", "#1B5A70"], fx: "sun", says: "Stay cool and drink water."),
    ]
    static func find(_ id: String) -> ZuffiSeason { all.first { $0.id == id } ?? all[0] }

    /// Which season it is on a date (the same rules as seasons.js).
    static func auto(_ d: Date = Date(), birthday: String, pakistan: Bool, south: Bool) -> String {
        let g = Calendar(identifier: .gregorian)
        let m = g.component(.month, from: d), day = g.component(.day, from: d), md = m * 100 + day
        if birthday.count >= 10, birthday.suffix(5) == String(format: "%02d-%02d", m, day) { return "birthday" }
        let h = Calendar(identifier: .islamicUmmAlQura)
        let hm = h.component(.month, from: d), hd = h.component(.day, from: d)
        if (hm == 10 && hd <= 3) || (hm == 12 && (10...13).contains(hd)) { return "eid" }
        if hm == 9 { return "ramadan" }
        if pakistan && (808...815).contains(md) { return "independence" }
        if (1210...1226).contains(md) { return "christmas" }
        if (1024...1031).contains(md) { return "halloween" }
        if (210...214).contains(md) { return "valentine" }
        if (!south && (m == 12 || m <= 2)) || (south && (6...8).contains(m)) { return "winter" }
        if (!south && (6...8).contains(m)) || (south && (m == 12 || m <= 2)) { return "summer" }
        return "none"
    }

    /// The outfit to wear right now, straight from the saved settings (safe to call from anywhere).
    static func activeId(_ d: Date = Date()) -> String {
        let ud = UserDefaults.standard
        let choice = ud.string(forKey: "zuffiOutfit") ?? "auto"
        if choice != "auto" { return find(choice).id }
        let region = Locale.current.region?.identifier ?? ""
        let pk = region == "PK" || (Locale.preferredLanguages.first ?? "").hasPrefix("ur") || ud.string(forKey: "bizCountry") == "PK"
        return auto(d, birthday: ud.string(forKey: "zuffiBirthday") ?? "", pakistan: pk, south: false)
    }

    /// A Zuffi picture in the current outfit, or the plain one.
    static func file(_ name: String, outfit: String = activeId()) -> URL? {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("web/mascots") else { return nil }
        if outfit != "none" {
            let dressed = base.appendingPathComponent("outfits/" + name.replacingOccurrences(of: ".webp", with: "-\(outfit).webp"))
            if FileManager.default.fileExists(atPath: dressed.path) { return dressed }
        }
        return base.appendingPathComponent(name)
    }
}

/// Settings → Zuffi's outfit & seasons.
struct ZuffiSeasonSettings: View {
    @ObservedObject private var look = ZuffiLook.shared
    @State private var birthday = Date()

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("Outfit & seasons").font(.system(size: 13, weight: .semibold))
                Text("Zuffi dresses up for the season — a scarf and woolly hat in winter, a lantern sky in Ramadan, confetti for Eid and your birthday. Automatic follows the calendar.")
                    .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(84), spacing: 8), count: 6), alignment: .leading, spacing: 8) {
                    tile(id: "auto", name: "Automatic", sub: "Today: " + ZuffiSeasons.find(ZuffiSeasons.activeId()).name, face: ZuffiSeasons.auto(Date(), birthday: look.birthday, pakistan: false, south: false))
                    ForEach(ZuffiSeasons.all) { s in tile(id: s.id, name: s.name, sub: nil, face: s.id) }
                }
                HStack(spacing: 10) {
                    Toggle("Birthday", isOn: Binding(get: { !look.birthday.isEmpty }, set: { on in look.birthday = on ? Self.fmt.string(from: birthday) : "" }))
                    if !look.birthday.isEmpty {
                        DatePicker("", selection: $birthday, displayedComponents: .date).labelsHidden().frame(width: 130)
                            .onChange(of: birthday) { _, d in look.birthday = Self.fmt.string(from: d) }
                    }
                    Text("Zuffi wishes you happy birthday on the day and dresses up.").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
            .padding(6)
        }
        .onAppear { if let d = Self.fmt.date(from: look.birthday) { birthday = d } }
    }
    static let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()

    private func tile(id: String, name: String, sub: String?, face: String) -> some View {
        let on = look.outfit == id
        let accent = Color(hex: ZuffiSeasons.find(id == "auto" ? face : id).accent ?? "#EDB24E")
        return Button { look.outfit = id } label: {
            VStack(spacing: 3) {
                OutfitFace(outfit: face).frame(width: 56, height: 56)
                Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                if let sub { Text(sub).font(.system(size: 9.5)).foregroundColor(.secondary).lineLimit(1) }
            }
            .frame(width: 84, height: sub == nil ? 86 : 96)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? accent : Color.primary.opacity(0.1), lineWidth: on ? 2.5 : 1))
        }.buttonStyle(.plain)
    }
}

/// The front-facing head in one outfit (for the picker).
struct OutfitFace: View {
    let outfit: String
    var body: some View {
        if let u = ZuffiSeasons.file("zuffi-directions.webp", outfit: outfit), let img = NSImage(contentsOf: u),
           let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let w = cg.width / 3, h = cg.height / 3
            if let c = cg.cropping(to: CGRect(x: w, y: h, width: w, height: h)) { Image(decorative: c, scale: 1).resizable().scaledToFit() }
        } else { Text("🐰").font(.system(size: 34)) }
    }
}
