import Foundation

/// The family rules the TV enforces by itself (`GET/POST /rules`). Times are minutes after midnight.
struct FamilyRules: Codable, Equatable {
    struct Schedule: Codable, Equatable {
        var enabled: Bool
        var weekdayFrom: Int
        var weekdayTo: Int
        var weekendFrom: Int
        var weekendTo: Int
    }

    struct Limit: Codable, Equatable {
        var enabled: Bool
        var weekdayMin: Int
        var weekendMin: Int
    }

    var enabled: Bool
    var turnOff: Bool
    /// Any lock left on screen this long turns the TV off (0 = never). Agent 1.3+, works with the rules off.
    var lockOffMin: Int?
    var schedule: Schedule
    var limit: Limit

    var json: [String: Any] {
        var o: [String: Any] = [
            "enabled": enabled,
            "turnOff": turnOff,
            "schedule": ["enabled": schedule.enabled,
                         "weekdayFrom": schedule.weekdayFrom, "weekdayTo": schedule.weekdayTo,
                         "weekendFrom": schedule.weekendFrom, "weekendTo": schedule.weekendTo],
            "limit": ["enabled": limit.enabled, "weekdayMin": limit.weekdayMin, "weekendMin": limit.weekendMin],
        ]
        if let lockOffMin { o["lockOffMin"] = lockOffMin }
        return o
    }
}

struct RulesToday: Codable, Equatable {
    var usedSec: Int
    var limitSec: Int
    var bonusSec: Int
    var remainingSec: Int?
    var from: Int
    var to: Int
    var weekend: Bool
    var paused: Bool
    var grantUntil: Double
    var blocked: String?
}

struct RulesState: Codable, Equatable {
    var rules: FamilyRules
    var today: RulesToday
}

enum Clock {
    static func text(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    static func date(_ minutes: Int) -> Date {
        Calendar.current.date(bySettingHour: (minutes / 60) % 24, minute: minutes % 60, second: 0, of: Date()) ?? Date()
    }

    static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    static func limit(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m) min" }
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }
}
