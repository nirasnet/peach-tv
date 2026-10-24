import SwiftUI

/// The lock screen's look and wording on the TV (`GET/POST /look`, agent 1.4+).
struct LockLook: Codable, Equatable {
    var theme: String
    var emoji: String
    var sprinkle: Bool
    var animate: Bool
    var parentSub: String
    var scheduleText: String
    var limitText: String
    var warnText: String
    /// Per-lock-kind styles (agent 1.5+): "parent", "schedule", "limit". The top-level fields mirror "parent".
    var styles: [String: LockStyle]?

    static let kinds = ["parent", "schedule", "limit"]

    /// The style of a lock kind; the warning pop-up has none, so it falls back to the parent lock's.
    func style(_ kind: String) -> LockStyle {
        styles?[kind] ?? styles?["parent"] ?? LockStyle(theme: theme, emoji: emoji, sprinkle: sprinkle, animate: animate)
    }

    mutating func setStyle(_ s: LockStyle, for kind: String) {
        guard Self.kinds.contains(kind) else { return }
        var all = styles ?? [:]
        for k in Self.kinds where all[k] == nil { all[k] = style(k) }
        all[kind] = s
        styles = all
        if kind == "parent" { theme = s.theme; emoji = s.emoji; sprinkle = s.sprinkle; animate = s.animate }
    }

    mutating func setStyleForAll(_ s: LockStyle) {
        for k in Self.kinds { setStyle(s, for: k) }
    }

    var json: [String: Any] {
        var o: [String: Any] = ["theme": theme, "emoji": emoji, "sprinkle": sprinkle, "animate": animate,
                                "parentSub": parentSub, "scheduleText": scheduleText, "limitText": limitText,
                                "warnText": warnText]
        if let styles { o["styles"] = styles.mapValues(\.json) }
        return o
    }
}

/// Background, big picture and decorations of one kind of lock.
struct LockStyle: Codable, Equatable {
    var theme: String
    var emoji: String
    var sprinkle: Bool
    var animate: Bool

    var json: [String: Any] { ["theme": theme, "emoji": emoji, "sprinkle": sprinkle, "animate": animate] }
}

struct LookState: Codable {
    var look: LockLook
    var themes: [String]
}

/// Mirrors Look.java's themes so the phone can draw previews.
struct LockTheme: Identifiable {
    let id: String
    let name: String
    let colors: [Color]
    let emoji: String
    let sprinkle: String
    let text: Color
    let accent: Color

    private static func c(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    private init(_ id: String, _ name: String, _ bg: [UInt32], _ emoji: String, _ sprinkle: String, _ text: UInt32, _ accent: UInt32) {
        self.id = id
        self.name = name
        colors = bg.map(Self.c)
        self.emoji = emoji
        self.sprinkle = sprinkle
        self.text = Self.c(text)
        self.accent = Self.c(accent)
    }

    static let all: [LockTheme] = [
        .init("peach", "Peach", [0x2A1210, 0x140806, 0x060303], "🍑", "🍑", 0xFFF1E6, 0xFFB38A),
        .init("night", "Night sky", [0x101845, 0x070B24, 0x02030A], "🌙", "✨", 0xEFF2FF, 0xB9C7FF),
        .init("ocean", "Ocean", [0x07405A, 0x042436, 0x010A10], "🐳", "🫧", 0xE8FBFF, 0x7FE3F0),
        .init("forest", "Forest", [0x143A1E, 0x09190D, 0x020703], "🌳", "🍃", 0xEFFFEA, 0x9BE58F),
        .init("sakura", "Sakura", [0x4A1834, 0x240B1A, 0x0A0307], "🌸", "🌸", 0xFFF0F6, 0xFFB3D1),
        .init("sunset", "Sunset", [0x5A250C, 0x2E1014, 0x0A0408], "🌅", "☁️", 0xFFF4E6, 0xFFC27A),
        .init("space", "Space", [0x22104A, 0x0D0624, 0x030108], "🚀", "⭐", 0xF3EDFF, 0xC9A7FF),
        .init("candy", "Candy", [0x4A1F52, 0x231240, 0x0A0614], "🍭", "🍬", 0xFFF0FB, 0xFF9AE6),
        .init("teddy", "Teddy", [0x44291A, 0x22140B, 0x0A0603], "🧸", "🍯", 0xFFF5EA, 0xE8C39E),
        .init("dino", "Dino", [0x24401A, 0x13230D, 0x050A03], "🦖", "🌴", 0xF2FFE8, 0xC4F08A),
        .init("mono", "Simple", [0x1E1E1E, 0x0D0D0D, 0x000000], "🔒", "", 0xF2F2F2, 0xBDBDBD),
    ]

    static func named(_ id: String) -> LockTheme { all.first { $0.id == id } ?? all[0] }
}

/// Built-in wording plus the family's own saved templates (kept on the phone).
enum Templates {
    enum Field: String {
        case lock, message, parentSub, scheduleText, limitText, warnText
    }

    static func builtIn(_ field: Field) -> [String] {
        switch field {
        case .lock:
            return Peach.lockPresets + ["ไปอาบน้ำก่อนนะ 🛁", "ช่วยเก็บของเล่นก่อนนะ 🧸", "อ่านหนังสือกันก่อนนะ 📖",
                                        "ออกไปวิ่งเล่นข้างนอกกันเถอะ ☀️", "พ่อแม่ขอคุยด้วยหน่อยจ้า 💬"]
        case .message:
            return Peach.messagePresets + ["เก่งมาก ภูมิใจในตัวหนูนะ 🌟", "แปรงฟันแล้วเข้านอนนะ 🪥", "ปิดทีวีแล้วมาช่วยกันหน่อย 🙌"]
        case .parentSub:
            return ["TV locked by Look Peach Family", "LOOK PEACH FAMILY 🍑", "ด้วยรักจากพ่อแม่ 💕", "PAUSE · BACK SOON", ""]
        case .scheduleText:
            return ["ตอนนี้ไม่ใช่เวลาดูทีวีนะ 🌙", "ทีวีหลับแล้ว เจอกัน {from} นะ 😴", "ได้เวลานอนแล้ว ฝันดีนะ 🌙✨",
                    "ยังไม่ถึงเวลาดูทีวีนะ ดูได้ตั้งแต่ {from} 📺", "พักสายตา ไปเล่นอย่างอื่นกันนะ 🎨"]
        case .limitText:
            return ["วันนี้ดูทีวีครบเวลาแล้วนะ ⏰", "ครบ {limit} แล้ว เก่งมากที่ทำตามกติกา 🌟", "หมดเวลาของวันนี้ พรุ่งนี้เจอกันใหม่ 👋",
                    "ไปเล่นข้างนอกกันเถอะ ☀️", "พักสายตาแล้วไปช่วยคุณแม่หน่อยนะ 💕"]
        case .warnText:
            return ["อีก {min} นาทีหมดเวลาดูทีวีนะ ⏰", "เหลืออีก {min} นาที เตรียมปิดทีวีนะ 👀", "อีก {min} นาที ดูตอนนี้ให้จบแล้วพักกันนะ 🍑"]
        }
    }

    static func saved(_ field: Field) -> [String] {
        UserDefaults.standard.stringArray(forKey: "templates.\(field.rawValue)") ?? []
    }

    static func all(_ field: Field) -> [String] {
        let built = builtIn(field)
        return saved(field).filter { !built.contains($0) } + built
    }

    static func save(_ text: String, _ field: Field) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !builtIn(field).contains(t) else { return }
        var list = saved(field).filter { $0 != t }
        list.insert(t, at: 0)
        UserDefaults.standard.set(Array(list.prefix(30)), forKey: "templates.\(field.rawValue)")
    }

    static func remove(_ text: String, _ field: Field) {
        UserDefaults.standard.set(saved(field).filter { $0 != text }, forKey: "templates.\(field.rawValue)")
    }

    /// What {from} {to} {limit} {min} turn into, for previews on the phone.
    static func sample(_ text: String, rules: RulesState?) -> String {
        let t = rules?.today
        let limit = (t?.limitSec ?? 3600) / 60
        let h = limit / 60, m = limit % 60
        let limitText = h == 0 ? "\(m) นาที" : (m == 0 ? "\(h) ชั่วโมง" : "\(h) ชั่วโมง \(m) นาที")
        return text
            .replacingOccurrences(of: "{from}", with: Clock.text(t?.from ?? 420))
            .replacingOccurrences(of: "{to}", with: Clock.text(t?.to ?? 1230))
            .replacingOccurrences(of: "{limit}", with: limitText)
            .replacingOccurrences(of: "{min}", with: "5")
    }
}

/// A small 16:9 drawing of the TV lock screen.
struct LockPreview: View {
    let theme: LockTheme
    var emoji: String = ""
    var message: String
    var sub: String
    var sprinkle = true
    var scale: CGFloat = 1

    private static let spots: [(CGFloat, CGFloat, CGFloat)] = [
        (0.06, 0.10, 34), (0.20, 0.78, 26), (0.88, 0.14, 30), (0.93, 0.66, 38), (0.72, 0.88, 24), (0.12, 0.45, 22),
        (0.80, 0.40, 20), (0.35, 0.08, 20), (0.55, 0.92, 28), (0.04, 0.88, 30), (0.64, 0.06, 26), (0.97, 0.92, 22),
    ]

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / 960
            ZStack {
                LinearGradient(colors: theme.colors, startPoint: .top, endPoint: .bottom)
                if sprinkle && !theme.sprinkle.isEmpty {
                    ForEach(Self.spots.indices, id: \.self) { i in
                        let s = Self.spots[i]
                        Text(theme.sprinkle).font(.system(size: s.2 * k * 1.4))
                            .opacity(0.22)
                            .rotationEffect(.degrees(Double((s.0 * 97).truncatingRemainder(dividingBy: 40) - 20)))
                            .position(x: s.0 * geo.size.width, y: s.1 * geo.size.height)
                    }
                }
                VStack(spacing: 6 * k) {
                    Text(emoji.isEmpty ? theme.emoji : emoji).font(.system(size: 120 * k))
                    Text(message).font(.system(size: 44 * k, weight: .light)).foregroundStyle(theme.text)
                        .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.6)
                    if !sub.isEmpty {
                        Text(sub.uppercased()).font(.system(size: 20 * k, weight: .light)).kerning(2 * k)
                            .foregroundStyle(theme.accent).lineLimit(1).minimumScaleFactor(0.5)
                            .padding(.top, 10 * k)
                    }
                }
                .padding(.horizontal, 40 * k)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
