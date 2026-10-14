import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// Spaced Review questions you answer straight from the notification (Settings › Review Questions).
///
/// One question a day at the chosen time, its answers as notification buttons. iPhone
/// notifications mirror to Apple Watch with their buttons, so this works on the wrist with
/// no watch app. Picking an answer records it exactly like answering in a game, then a short
/// follow-up says whether it was right (which also taps the wrist).
///
/// Only "watch-friendly" questions are used: a short prompt and short options, so they read
/// well on a watch and fit on a button. Rescheduled by ReviewSideEffects.
@MainActor
enum ReviewNotifications {
    private static let prefix = "hearken.review."
    private static let categoryPrefix = "hearken.review.category."
    nonisolated static let actionPrefix = "hearken.review.answer."
    /// Questions are scheduled this many days ahead, one per day.
    static let horizon = 7
    static let maxPromptLength = 150
    static let maxOptionLength = 38

    /// userInfo keys. Everything needed to grade the answer travels with the notification,
    /// so answering never has to load the question bank.
    nonisolated enum Key {
        static let questionID = "reviewQuestionID"
        static let answer = "reviewAnswer"
        static let options = "reviewOptions"
        static let explanation = "reviewExplanation"
        static let reference = "reviewReference"
    }

    private static var container: ModelContainer?

    /// Answers can arrive with Hearken in the background, so the store is attached at launch.
    static func attach(container: ModelContainer) {
        self.container = container
    }

    static func isWatchFriendly(_ question: Question) -> Bool {
        question.prompt.count <= maxPromptLength
            && (2...4).contains(question.options.count)
            && question.options.allSatisfy { $0.count <= maxOptionLength }
            && question.options.indices.contains(question.answer)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    // MARK: Scheduling

    /// Replaces the pending review questions with `questions` (most due first), one a day at `minutes` past midnight.
    static func update(questions: [Question], enabled: Bool, minutes: Int, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        // Keep the buttons working on any question already showing in Notification Center.
        let delivered = await center.deliveredNotifications().map(\.request).filter { $0.identifier.hasPrefix(prefix) }
        var categories = Set(delivered.compactMap { category(for: $0.content.userInfo) })

        guard enabled else {
            await setCategories(categories)
            return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var remaining = questions.filter(isWatchFriendly)[...]
        for offset in 0..<horizon {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(byAdding: .minute, value: minutes, to: day),
                  fire > now,
                  let question = remaining.popFirst()
            else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Quick review"
            content.subtitle = question.reference
            content.body = question.prompt
            content.sound = .default
            content.threadIdentifier = "spaced-review"
            content.categoryIdentifier = categoryPrefix + question.id
            content.userInfo = [
                Key.questionID: question.id,
                Key.answer: question.answer,
                Key.options: question.options,
                Key.explanation: question.explanation,
                Key.reference: question.reference,
            ]
            categories.insert(makeCategory(id: content.categoryIdentifier, options: question.options))

            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            let id = prefix + day.formatted(.iso8601.year().month().day())
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        await setCategories(categories)
    }

    /// Each question gets its own category, since a category's buttons are fixed when registered.
    private static func makeCategory(id: String, options: [String]) -> UNNotificationCategory {
        let actions = options.enumerated().map { index, option in
            UNNotificationAction(identifier: actionPrefix + String(index), title: option, options: [])
        }
        return UNNotificationCategory(identifier: id, actions: actions, intentIdentifiers: [], options: [])
    }

    private static func category(for info: [AnyHashable: Any]) -> UNNotificationCategory? {
        guard let id = info[Key.questionID] as? String, let options = info[Key.options] as? [String] else { return nil }
        return makeCategory(id: categoryPrefix + id, options: options)
    }

    /// Hearken has no other notification categories, so this set is the whole list.
    private static func setCategories(_ categories: Set<UNNotificationCategory>) async {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    // MARK: Answering

    /// A button on a review notification was pressed (iPhone or Apple Watch).
    static func answer(questionID: String, picked: Int, correctIndex: Int, options: [String], explanation: String, reference: String) async {
        let correct = picked == correctIndex
        if let context = container?.mainContext {
            MasteryService().record(questionID: questionID, correct: correct, in: context)
            try? context.save()
        }

        let content = UNMutableNotificationContent()
        if correct {
            content.title = "Correct"
            content.body = "+\(MasteryConfig.standard.xpPerCorrect) XP. \(explanation)"
        } else {
            content.title = "Not quite"
            let right = options.indices.contains(correctIndex) ? options[correctIndex] : ""
            content.body = "The answer is “\(right)”. \(explanation) It'll come back in Spaced Review."
        }
        content.subtitle = reference
        content.sound = .default
        content.threadIdentifier = "spaced-review"
        let request = UNNotificationRequest(identifier: prefix + "result." + questionID, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

/// Keeps the review notifications scheduled with the questions most in need of review:
/// on launch, each new day, after answering anything, and when the setting changes.
struct ReviewSideEffects: ViewModifier {
    @Environment(ContentService.self) private var content
    @Environment(\.scenePhase) private var scenePhase
    @Query private var reviews: [ItemReview]
    @Query private var progress: [ReadingProgress]
    @AppStorage(SettingsKey.reviewNotifications) private var enabled = false
    @AppStorage(SettingsKey.reviewNotificationMinutes) private var minutes = ReviewNotifications.defaultMinutes

    func body(content view: Content) -> some View {
        view.task(id: fingerprint) { await refresh() }
    }

    private var fingerprint: String {
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        let reps = reviews.reduce(0) { $0 + $1.reps }
        return "\(enabled)|\(minutes)|\(reps)|\(day)|\(scenePhase == .active)"
    }

    private func refresh() async {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        let pool = content.questions.filter(ReviewNotifications.isWatchFriendly)
        let due = MasteryService().dueQuestions(from: pool, snapshot: snapshot, limit: ReviewNotifications.horizon)
        await ReviewNotifications.update(questions: due, enabled: enabled, minutes: minutes)
    }
}

extension ReviewNotifications {
    /// 12:30 pm: a midday question, apart from the evening reading reminder.
    static let defaultMinutes = 12 * 60 + 30
}
