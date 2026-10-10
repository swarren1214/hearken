import Foundation
import SwiftData

// User data, stored with SwiftData. Every property is optional or has a default and
// there are no unique constraints, so the same models can sync through CloudKit
// once AppConfig.cloudSyncEnabled is turned on.
//
// Content (scripture, subjects, questions) never lives here. Models point at content
// by its stable string ID, for example "bofm.alma.32" or "q.bofm.0001".

/// A highlighted or underlined run of text. It can be part of a verse or span several:
/// it runs from `startOffset` in `startVerse` to `endOffset` in `endVerse`, where offsets
/// are UTF-16 positions in the verse text and an `endOffset` of -1 means the end of the verse.
@Model
final class Highlight {
    var chapterID: String = ""
    var startVerse: Int = 0
    var endVerse: Int = 0
    var startOffset: Int = 0
    var endOffset: Int = -1
    var hueRaw: String = "yellow"
    var styleRaw: String = "fill"
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// A whole verse.
    init(chapterID: String, verse: Int, hue: HighlightHue, style: HighlightStyle) {
        self.chapterID = chapterID
        self.startVerse = verse
        self.endVerse = verse
        self.hueRaw = hue.rawValue
        self.styleRaw = style.rawValue
    }

    /// Any run of text.
    init(chapterID: String, start: VersePosition, end: VersePosition, hue: HighlightHue, style: HighlightStyle) {
        self.chapterID = chapterID
        self.startVerse = start.verse
        self.startOffset = start.offset
        self.endVerse = end.verse
        self.endOffset = end.offset
        self.hueRaw = hue.rawValue
        self.styleRaw = style.rawValue
    }

    var start: VersePosition { VersePosition(verse: startVerse, offset: startOffset) }
    var end: VersePosition { VersePosition(verse: endVerse, offset: endOffset) }

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
    var hasEarnedReadXP: Bool = false
    var updatedAt: Date = Date.now

    init(chapterID: String, lastVerse: Int = 0) {
        self.chapterID = chapterID
        self.lastVerse = lastVerse
    }
}

/// A named place in the scriptures: a verse in a chapter. A blank name shows the reference.
@Model
final class Bookmark {
    var name: String = ""
    var chapterID: String = ""
    var verse: Int = 1
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String = "", chapterID: String, verse: Int) {
        self.name = name
        self.chapterID = chapterID
        self.verse = verse
    }
}

/// Someone following a reading plan. The schedule itself is computed (see PlanEngine) from
/// the plan's chapters and an anchor: the start, or the last time it was rescheduled.
@Model
final class PlanEnrollment {
    var planID: String = ""
    var startDate: Date = Date.now
    /// Reading weekdays as a bitmask: Sunday = 1 << 0 … Saturday = 1 << 6 (see ReadingDays).
    var readingDays: Int = 127
    var reminderEnabled: Bool = false
    /// Minutes after midnight, e.g. 420 = 7:00 AM.
    var reminderMinutes: Int = 420
    /// Custom plans only.
    var customTitle: String = ""
    var customChapterIDs: [String] = []
    /// The schedule runs from chapter `anchorIndex` over `anchorDays` reading days starting
    /// `anchorDate`, numbered from `anchorDayNumber`. Reschedule moves the anchor.
    var anchorDate: Date = Date.now
    var anchorIndex: Int = 0
    var anchorDays: Int = 0
    var anchorDayNumber: Int = 1
    var createdAt: Date = Date.now
    /// Set when the plan is finished or ended. Only one plan is active at a time.
    var endedAt: Date?

    init(planID: String, startDate: Date, days: Int, readingDays: Int, reminderEnabled: Bool, reminderMinutes: Int) {
        let start = Calendar.current.startOfDay(for: startDate)
        self.planID = planID
        self.startDate = start
        self.readingDays = readingDays
        self.reminderEnabled = reminderEnabled
        self.reminderMinutes = reminderMinutes
        self.anchorDate = start
        self.anchorDays = days
    }

    /// Reading days in the whole plan, including any before the last reschedule.
    var totalDays: Int { anchorDayNumber - 1 + anchorDays }
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
