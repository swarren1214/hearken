import AppIntents
import Foundation

/// "Open today's reading in Hearken": opens the reader at the next chapter in the plan.
struct OpenTodaysReadingIntent: AppIntent {
    static var title: LocalizedStringResource { "Open Today's Reading" }
    static var description: IntentDescription { IntentDescription("Opens Hearken to the next chapter in your reading plan.") }
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let chapterID = PlanSnapshotStore.load()?.nextChapterID {
            AppNavigator.shared.open(chapterID: chapterID)
        }
        return .result()
    }
}

/// "How's my Hearken plan?": where you are, without opening the app.
struct PlanProgressIntent: AppIntent {
    static var title: LocalizedStringResource { "Reading Plan Progress" }
    static var description: IntentDescription { IntentDescription("Tells you where you are in your reading plan and what's next.") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let plan = PlanSnapshotStore.load() else {
            return .result(dialog: "You don't have a reading plan yet. Start one from the Library in Hearken.")
        }
        let percent = plan.fraction.formatted(.percent.precision(.fractionLength(0)))
        let text: String
        if plan.finished {
            text = "You've finished \(plan.title). Nice work."
        } else if plan.isReadingDay {
            text = "You're on day \(plan.dayNumber) of \(plan.totalDays) of \(plan.title), \(percent) done and \(plan.statusLine.lowercased()). Today's reading is \(plan.todayRange), about \(plan.minutes) minutes."
        } else {
            text = "No reading today. You're \(percent) through \(plan.title); next up is \(plan.todayRange)."
        }
        return .result(dialog: "\(text)")
    }
}

struct HearkenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodaysReadingIntent(),
            phrases: [
                "Open today's reading in \(.applicationName)",
                "Start my \(.applicationName) reading",
            ],
            shortTitle: "Today's Reading",
            systemImageName: "book"
        )
        AppShortcut(
            intent: PlanProgressIntent(),
            phrases: [
                "How's my \(.applicationName) plan",
                "\(.applicationName) reading plan progress",
            ],
            shortTitle: "Plan Progress",
            systemImageName: "chart.bar"
        )
    }
}
