import Foundation

/// The Scholar Path's rules as pure functions, so they're easy to test.
enum ScholarRules {
    /// Bump when the rules change; stored on every award and grant.
    static let ruleVersion = 1

    static let checkpointXP = 100
    static let capstoneXP = 200
    /// A written response shorter than this doesn't count as completing an item.
    static let minimumResponseWords = 20

    /// XP for a learning item's first completion, by kind.
    static func xp(for kind: PathItem.Kind) -> Int {
        switch kind {
        case .lesson: 20
        case .reading: 30
        case .video: 20
        case .practice: 10
        }
    }

    /// The highest rank earned: its XP threshold met and stages 1…n complete in order.
    /// `completedStages` counts contiguous complete stages from Stage 1. Nil until the first
    /// learning item is done. Never lower than `stored`, and never past `ceiling`.
    static func rank(xp: Int, completedStages: Int, hasCompletedAnItem: Bool, stored: ScholarRank?, ceiling: ScholarRank = .sage) -> ScholarRank? {
        var best: ScholarRank? = hasCompletedAnItem ? .novice : nil
        for rank in ScholarRank.allCases where rank > .novice && rank <= ceiling {
            if xp >= rank.xpThreshold && completedStages >= rank.requiredStages {
                best = rank
            } else {
                break
            }
        }
        switch (best, stored) {
        case let (best?, stored?): return max(best, stored)
        case let (best, stored): return best ?? stored
        }
    }

    /// Points needed to pass: the pass percentage of the points available, rounded up.
    static func pointsToPass(maxPoints: Int, passPercent: Int) -> Int {
        Int((Double(maxPoints * passPercent) / 100).rounded(.up))
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
