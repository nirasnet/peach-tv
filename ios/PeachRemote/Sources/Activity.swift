import Foundation

/// One day of TV history from the agent's `GET /activity?date=YYYY-MM-DD`. Times are epoch ms.
struct ActivityDay: Codable, Equatable {
    struct Span: Codable, Equatable, Identifiable {
        var start: Double
        var end: Double
        var ongoing: Bool
        var app: String?
        var label: String?

        var id: Double { start }
        var startDate: Date { Date(timeIntervalSince1970: start / 1000) }
        var endDate: Date { Date(timeIntervalSince1970: end / 1000) }
        var seconds: Int { Int((end - start) / 1000) }
    }

    struct Total: Codable, Equatable, Identifiable {
        var app: String
        var label: String
        var seconds: Int
        var id: String { app }
    }

    struct Mark: Codable, Equatable {
        var time: Double
        var kind: String
        var date: Date { Date(timeIntervalSince1970: time / 1000) }
    }

    var date: String
    var onSeconds: Int
    var sessions: [Span]
    var apps: [Span]
    var totals: [Total]
    var marks: [Mark]
    var days: [String]

    /// The day read top to bottom: TV on, each app from–to, lock/unlock, TV off.
    var timeline: [TimelineItem] {
        var items: [TimelineItem] = []
        for s in sessions {
            items.append(.init(time: s.startDate, kind: .on))
            if !s.ongoing { items.append(.init(time: s.endDate, kind: .off)) }
        }
        for a in apps where a.seconds >= 5 {
            items.append(.init(time: a.startDate, kind: .app(a)))
        }
        for m in marks {
            let kind: TimelineItem.Kind
            switch m.kind {
            case "lock": kind = .lock
            case "unlock": kind = .unlock
            case "schedule": kind = .rule("🌙 Outside TV hours, locked")
            case "limit": kind = .rule("⏰ Screen time used up, locked")
            case "allowed": kind = .rule("✅ TV time again")
            case "lockoff": kind = .rule("💤 Locked too long, TV turned off")
            default: continue
            }
            items.append(.init(time: m.date, kind: kind))
        }
        return items.sorted { a, b in
            a.time == b.time ? a.kind.order < b.kind.order : a.time > b.time
        }
    }
}

struct TimelineItem: Identifiable {
    enum Kind {
        case on, off, lock, unlock
        case rule(String)
        case app(ActivityDay.Span)

        // On equal times, newest-first reading should show "off" above the last app and the app above "on".
        var order: Int {
            switch self {
            case .off: return 0
            case .lock, .unlock, .rule: return 1
            case .app: return 2
            case .on: return 3
            }
        }
    }

    let time: Date
    let kind: Kind
    var id: String {
        switch kind {
        case .on: return "on\(time.timeIntervalSince1970)"
        case .off: return "off\(time.timeIntervalSince1970)"
        case .lock: return "lock\(time.timeIntervalSince1970)"
        case .unlock: return "unlock\(time.timeIntervalSince1970)"
        case .rule(let text): return "rule\(text)\(time.timeIntervalSince1970)"
        case .app(let s): return "app\(s.start)"
        }
    }
}

enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ key: String) -> Date? { formatter.date(from: key) }
}

/// Keeps the last copy of each day so history still shows while the TV is off.
enum ActivityCache {
    private static var dir: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("activity")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func save(_ data: Data, for day: String) {
        try? data.write(to: dir.appendingPathComponent("\(day).json"), options: .atomic)
    }

    static func load(_ day: String) -> (ActivityDay, Date)? {
        let url = dir.appendingPathComponent("\(day).json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ActivityDay.self, from: data) else { return nil }
        let saved = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return (decoded, saved)
    }
}
