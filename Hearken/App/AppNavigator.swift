import Observation
import SwiftData
import SwiftUI
import UserNotifications

/// Opens the reader from outside a screen: widgets, notifications, Siri and Shortcuts.
@MainActor
@Observable
final class AppNavigator {
    static let shared = AppNavigator()

    /// A chapter waiting to be opened; RootTabView pushes it and clears it.
    var pendingChapterID: String?
    /// A subject's Scholar Path to open on the Play tab (after earning a badge).
    var pendingSubjectID: String?
    /// An imported book to open on the Library tab (its "ready" notification was tapped).
    var pendingBookID: String?

    func open(chapterID: String) {
        pendingChapterID = chapterID
    }

    /// `hearken://read/bofm.alma.5`
    static func readURL(_ chapterID: String) -> URL {
        URL(string: "hearken://read/\(chapterID)") ?? URL(string: "hearken://read")!
    }

    /// `hearken://listen/bofm.alma.5`
    static func listenURL(_ chapterID: String) -> URL {
        URL(string: "hearken://listen/\(chapterID)") ?? URL(string: "hearken://listen")!
    }

    func handle(_ url: URL) {
        // An EPUB or PDF opened in Hearken from the Share sheet or Files: add it to the Library.
        if url.isFileURL {
            BookImporter.shared.inspect([url])
            return
        }
        // A study group invite: https://api.hearthapps.com/hearken/join/ABCD2345 (a universal
        // link) or hearken://join/ABCD2345.
        if (url.scheme == "hearken" && url.host() == "join") || (url.scheme == "https" && url.path().hasPrefix("/hearken/join/")) {
            if let code = GroupStore.inviteCode(from: url.lastPathComponent) { GroupStore.shared.pendingInviteCode = code }
            return
        }
        guard url.scheme == "hearken", let host = url.host(), host == "read" || host == "listen" else { return }
        let chapterID = url.lastPathComponent
        guard !chapterID.isEmpty, chapterID != "/" else { return }
        if host == "listen" {
            ListenEngine.shared.start(chapterID: chapterID)
            if ListenEngine.shared.isActive { ListenEngine.shared.showsPlayer = true }
        } else {
            open(chapterID: chapterID)
        }
    }
}

/// A chapter pushed onto Today's navigation stack.
struct ReaderRoute: Hashable {
    let chapterID: String
}

/// Shows plan reminders while the app is open, and opens the chapter when one is tapped.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        // An answer button on a review question (Settings › Review Questions), on iPhone or Apple Watch.
        if let questionID = info[ReviewNotifications.Key.questionID] as? String {
            let action = response.actionIdentifier
            guard action.hasPrefix(ReviewNotifications.actionPrefix),
                  let picked = Int(action.dropFirst(ReviewNotifications.actionPrefix.count))
            else { return } // Tapped rather than answered: just open the app.
            let correctIndex = info[ReviewNotifications.Key.answer] as? Int ?? -1
            let options = info[ReviewNotifications.Key.options] as? [String] ?? []
            let explanation = info[ReviewNotifications.Key.explanation] as? String ?? ""
            let reference = info[ReviewNotifications.Key.reference] as? String ?? ""
            await ReviewNotifications.answer(
                questionID: questionID, picked: picked, correctIndex: correctIndex,
                options: options, explanation: explanation, reference: reference
            )
            return
        }
        if let bookID = info["bookID"] as? String {
            await MainActor.run { AppNavigator.shared.pendingBookID = bookID }
        } else if let hearken = info["hearken"] as? [String: Any], let groupID = hearken["groupId"] as? String {
            // A study group notification (from the Hearth API): open what it's about.
            let kind = hearken["kind"] as? String
            let targetType = hearken["targetType"] as? String
            let targetID = hearken["targetId"] as? String
            await MainActor.run { GroupStore.shared.open(groupID: groupID, kind: kind, targetType: targetType, targetID: targetID) }
        } else if let groupID = info["groupID"] as? String {
            await MainActor.run { GroupStore.shared.openGroupID = groupID }
        } else if let chapterID = info["chapterID"] as? String {
            await MainActor.run { AppNavigator.shared.open(chapterID: chapterID) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // A study group notification while Hearken is open: bring the group up to date too.
        if notification.request.content.userInfo["hearken"] != nil {
            await GroupStore.shared.refresh()
        }
        return [.banner, .sound]
    }
}

/// Keeps the plan's reminders and the widget snapshot current: on launch, on returning to
/// the app, at the start of a new day, and whenever the plan or what's been read changes.
struct PlanSideEffects: ViewModifier {
    @Environment(ContentService.self) private var scripture
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PlanEnrollment.createdAt, order: .reverse) private var enrollments: [PlanEnrollment]
    @Query private var progress: [ReadingProgress]
    @Query private var xpEvents: [XPEvent]

    func body(content: Content) -> some View {
        content.task(id: fingerprint) { await refresh() }
    }

    private var fingerprint: String {
        let active = PlanReading.active(enrollments)
        let read = progress.reduce(0) { $0 + ($1.completedAt == nil ? 0 : 1) }
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSinceReferenceDate
        let plan = active.map {
            "\($0.planID)|\($0.anchorDate.timeIntervalSinceReferenceDate)|\($0.anchorIndex)|\($0.anchorDays)|\($0.readingDays)|\($0.reminderEnabled)|\($0.reminderMinutes)"
        } ?? "none"
        return "\(plan)|\(read)|\(day)|\(scenePhase == .active)|\(xpEvents.count)"
    }

    private func refresh() async {
        let active = PlanReading.active(enrollments)
        let state = active.flatMap { PlanEngine.shared.state(for: $0, content: scripture, read: PlanReading.readSet(progress)) }
        let streak = MasteryMath.streak(activityDates: xpEvents.map(\.createdAt), now: .now)
        let snapshot = state.map { PlanSnapshot(state: $0, streak: streak) }
        PlanSnapshotStore.save(snapshot)
        // The Apple Watch's Smart Stack widget and Today page.
        WatchBridge.shared.send(plan: snapshot)
        // Caloma shows each day's reading on the family calendar.
        HearthLink.publishReading(state: state, enrollment: active)
        await PlanReminders.update(state: state, enabled: active?.reminderEnabled ?? false, minutes: active?.reminderMinutes ?? 420)
    }
}
