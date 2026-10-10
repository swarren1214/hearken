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
        if let groupID = info["groupID"] as? String {
            await MainActor.run { GroupStore.shared.openGroupID = groupID }
        } else if let chapterID = info["chapterID"] as? String {
            await MainActor.run { AppNavigator.shared.open(chapterID: chapterID) }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
        PlanSnapshotStore.save(state.map { PlanSnapshot(state: $0, streak: streak) })
        await PlanReminders.update(state: state, enabled: active?.reminderEnabled ?? false, minutes: active?.reminderMinutes ?? 420)
    }
}
