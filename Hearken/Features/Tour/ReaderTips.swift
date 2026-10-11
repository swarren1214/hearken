import SwiftUI
import TipKit

/// The reader's one-time tips (Apple's TipKit). Each shows the first time someone reaches the
/// feature, at most one new tip a day, and never again once used or closed.
enum ReaderTips {
    /// Once, at launch. Settings › Show All Tips Again asks for a reset here, since TipKit's
    /// records can only be cleared before it's configured.
    static func configure() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: SettingsKey.tipsResetPending) {
            try? Tips.resetDatastore()
            defaults.set(false, forKey: SettingsKey.tipsResetPending)
        }
        try? Tips.configure([
            .displayFrequency(.daily),
            .datastoreLocation(.applicationDefault),
        ])
    }

    /// A highlight was made (touch and hold, or the Pencil).
    static func highlighted() {
        HighlightTip().invalidate(reason: .actionPerformed)
        Task { await HighlightTip.highlighted.donate() }
    }

    /// A chapter was opened in the reader.
    static func chapterOpened() {
        Task { await ListenTip.chapterOpened.donate() }
    }
}

/// First chapter opened: how to highlight.
struct HighlightTip: Tip {
    static let highlighted = Tips.Event(id: "reader.highlighted")

    var title: Text { Text("Mark what stands out") }
    var message: Text? {
        Text(UIDevice.isPad
             ? "Touch and hold a verse to highlight it, or just draw on the words with Apple Pencil."
             : "Touch and hold a verse to highlight it. Drag the handles to mark just the words you want.")
    }
    var image: Image? { Image(systemName: "highlighter") }
}

/// Right after the first highlight (iPhone): the actions behind ···.
struct HighlightMenuTip: Tip {
    var title: Text { Text("More in here") }
    var message: Text? { Text("Add a note, ask Explain what a verse means, share with your study group, or copy.") }
    var image: Image? { Image(systemName: "ellipsis.circle") }
    var rules: [Rule] {
        [#Rule(HighlightTip.highlighted) { $0.donations.count >= 1 }]
    }
    /// It follows straight on from the highlight tip, so it doesn't wait a day.
    var options: [any TipOption] {
        [Tips.IgnoresDisplayFrequency(true)]
    }
}

/// From the second chapter opened: Listen.
struct ListenTip: Tip {
    static let chapterOpened = Tips.Event(id: "reader.chapterOpened")
    static let tryIt = "try"

    var title: Text { Text("Listen to this chapter") }
    var message: Text? { Text("Hear it read aloud. Verses light up as they're read, and it keeps going with your screen locked.") }
    var image: Image? { Image(systemName: "headphones") }
    var rules: [Rule] {
        [#Rule(Self.chapterOpened) { $0.donations.count >= 2 }]
    }
    var actions: [Action] {
        [Action(id: Self.tryIt, title: "Try It")]
    }
}
