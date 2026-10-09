import Foundation
import SwiftData

// User data, stored with SwiftData. Every property is optional or has a default and
// there are no unique constraints, so the same models can sync through CloudKit
// once AppConfig.cloudSyncEnabled is turned on.
//
// Content (scripture, subjects, questions) never lives here. Models point at content
// by its stable string ID, for example "bofm.alma.32" or "q.bofm.0001".

@Model
final class Highlight {
    var chapterID: String = ""
    var startVerse: Int = 0
    var endVerse: Int = 0
    var hueRaw: String = "yellow"
    var styleRaw: String = "fill"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(chapterID: String, verse: Int, hue: HighlightHue, style: HighlightStyle) {
        self.chapterID = chapterID
        self.startVerse = verse
        self.endVerse = verse
        self.hueRaw = hue.rawValue
        self.styleRaw = style.rawValue
    }

    var hue: HighlightHue {
        get { HighlightHue(rawValue: hueRaw) ?? .yellow }
        set { hueRaw = newValue.rawValue; updatedAt = .now }
    }

    var style: HighlightStyle {
        get { HighlightStyle(rawValue: styleRaw) ?? .fill }
        set { styleRaw = newValue.rawValue; updatedAt = .now }
    }

    func covers(verse: Int) -> Bool {
        verse >= startVerse && verse <= endVerse
    }
}

@Model
final class Note {
    var chapterID: String = ""
    var verse: Int = 0
    var body: String = ""
    var tags: [String] = []
    var linkedVerseIDs: [String] = []
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(chapterID: String, verse: Int, body: String, tags: [String] = []) {
        self.chapterID = chapterID
        self.verse = verse
        self.body = body
        self.tags = tags
    }
}

@Model
final class ReadingProgress {
    var chapterID: String = ""
    var lastVerse: Int = 0
    var completedAt: Date?
    var updatedAt: Date = Date.now

    init(chapterID: String, lastVerse: Int = 0) {
        self.chapterID = chapterID
        self.lastVerse = lastVerse
    }
}

/// Spaced repetition state for one question.
@Model
final class ItemReview {
    var questionID: String = ""
    /// Days until predicted recall falls to 90%.
    var stability: Double = 0
    var lastReviewed: Date?
    var reps: Int = 0
    var lapses: Int = 0
    var lastCorrect: Bool = false

    init(questionID: String) {
        self.questionID = questionID
    }
}

@Model
final class GameSession {
    var gameType: String = ""
    var subjectID: String = ""
    var correct: Int = 0
    var total: Int = 0
    var xpEarned: Int = 0
    var playedAt: Date = Date.now

    init(gameType: String, subjectID: String, correct: Int, total: Int, xpEarned: Int) {
        self.gameType = gameType
        self.subjectID = subjectID
        self.correct = correct
        self.total = total
        self.xpEarned = xpEarned
    }
}

/// One XP award. Totals, levels and streaks are computed from these, never stored.
@Model
final class XPEvent {
    var amount: Int = 0
    var reason: String = ""
    var createdAt: Date = Date.now

    init(amount: Int, reason: String) {
        self.amount = amount
        self.reason = reason
    }
}
