import Foundation

/// Tunable numbers for mastery, XP and streaks. First guesses; adjust from TestFlight feedback.
struct MasteryConfig {
    var recallWeight = 0.8
    var readingWeight = 0.2
    var firstCorrectStability = 1.0
    var correctGrowth = 2.5
    var lapseStability = 0.5
    var lapseFactor = 0.4
    var xpPerCorrect = 10
    var dailyChallengeBonus = 50
    var chapterReadXP = 5
    var noteXP = 5
    var xpPerLevel = 200

    static let standard = MasteryConfig()
}

/// Seeker → Master, per subject.
enum Tier: Int, CaseIterable, Identifiable, Comparable {
    case seeker, student, scholar, master

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .seeker: "Seeker"
        case .student: "Student"
        case .scholar: "Scholar"
        case .master: "Master"
        }
    }

    var lowerBound: Double { Double(rawValue) * 0.25 }
    var upperBound: Double { lowerBound + 0.25 }

    init(mastery: Double) {
        switch mastery {
        case ..<0.25: self = .seeker
        case ..<0.5: self = .student
        case ..<0.75: self = .scholar
        default: self = .master
        }
    }

    static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct LevelProgress: Equatable {
    let level: Int
    let totalXP: Int
    let levelStartXP: Int
    let nextLevelXP: Int

    var fraction: Double {
        let span = nextLevelXP - levelStartXP
        return span > 0 ? Double(totalXP - levelStartXP) / Double(span) : 0
    }

    var xpToNext: Int { max(nextLevelXP - totalXP, 0) }
}

/// Pure functions behind mastery, levels and streaks. No storage, so they're easy to test.
enum MasteryMath {
    /// Predicted recall (0...1) after `days` with the given stability (FSRS-style curve).
    /// Unseen items (stability 0) count as 0.
    static func recall(days: Double, stability: Double) -> Double {
        guard stability > 0 else { return 0 }
        return pow(1 + max(days, 0) / (9 * stability), -1)
    }

    static func recall(lastReviewed: Date?, stability: Double, now: Date) -> Double {
        guard let lastReviewed else { return 0 }
        return recall(days: now.timeIntervalSince(lastReviewed) / 86_400, stability: stability)
    }

    /// A correct answer grows stability; a miss shrinks it so the item comes back soon.
    static func nextStability(current: Double, correct: Bool, config: MasteryConfig = .standard) -> Double {
        if correct {
            return current > 0 ? current * config.correctGrowth : config.firstCorrectStability
        }
        return current > 0 ? max(config.lapseStability, current * config.lapseFactor) : config.lapseStability
    }

    /// Unit mastery = recall weight × average recall + reading weight × share of readings finished.
    /// A unit with no questions yet is measured by reading alone.
    static func unitMastery(recalls: [Double], readingFraction: Double?, config: MasteryConfig = .standard) -> Double {
        let averageRecall = recalls.isEmpty ? nil : recalls.reduce(0, +) / Double(recalls.count)
        switch (averageRecall, readingFraction) {
        case let (recall?, reading?):
            return config.recallWeight * recall + config.readingWeight * reading
        case let (recall?, nil):
            return recall
        case let (nil, reading?):
            return reading
        case (nil, nil):
            return 0
        }
    }

    /// Subject mastery = unit mastery weighted by each unit's item count (plain average if none have items).
    static func subjectMastery(units: [(mastery: Double, weight: Int)]) -> Double {
        guard !units.isEmpty else { return 0 }
        let totalWeight = units.reduce(0) { $0 + $1.weight }
        if totalWeight == 0 {
            return units.reduce(0) { $0 + $1.mastery } / Double(units.count)
        }
        return units.reduce(0) { $0 + $1.mastery * Double($1.weight) } / Double(totalWeight)
    }

    /// Level n starts at n × xpPerLevel total XP (Level 15 = 3,000 XP). Level 1 covers everything below level 2.
    static func level(forXP xp: Int, config: MasteryConfig = .standard) -> LevelProgress {
        let perLevel = config.xpPerLevel
        let level = max(1, xp / perLevel)
        let start = level == 1 ? 0 : level * perLevel
        return LevelProgress(level: level, totalXP: xp, levelStartXP: start, nextLevelXP: (level + 1) * perLevel)
    }

    /// Consecutive days with activity, ending today (or yesterday, so a streak isn't lost before bedtime).
    static func streak(activityDates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(activityDates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
