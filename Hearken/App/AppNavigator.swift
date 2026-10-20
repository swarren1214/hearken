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

/// Shows plan reminders while the app is open, and opens what a tapped notification is about.
///
/// Uses the completion-handler forms of the delegate methods, and calls the handlers on the
/// main thread. With the async forms, Swift calls UIKit's completion handler from whatever
/// thread the work finished on; UIKit's handler then updates the app snapshot off the main
/// thread and aborts (build 27: a tapped notification launching Hearken crashed it).
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()

    /// What a tapped notification asks for, read from it up front so only plain values cross
    /// to the main actor.
    private enum Tap: Sendable {
        case reviewAnswer(questionID: String, picked: Int, correctIndex: Int, options: [String], explanation: String, reference: String)
        case book(String)
        case group(id: String, kind: String?, targetType: String?, targetID: String?)
        case legacyGroup(String)
        case chapter(String)
        case none
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let tap = Self.tap(info: response.notification.request.content.userInfo, action: response.actionIdentifier)
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            await Self.handle(tap)
            done()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let isGroup = notification.request.content.userInfo["hearken"] != nil
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            // Show it first; a study group notification then brings the group up to date.
            done([.banner, .sound])
            if isGroup { await GroupStore.shared.refresh() }
        }
    }

    private nonisolated static func tap(info: [AnyHashable: Any], action: String) -> Tap {
        // An answer button on a review question (Settings › Review Questions), on iPhone or Apple Watch.
        if let questionID = info[ReviewNotifications.Key.questionID] as? String {
            guard action.hasPrefix(ReviewNotifications.actionPrefix),
                  let picked = Int(action.dropFirst(ReviewNotifications.actionPrefix.count))
            else { return .none } // Tapped rather than answered: just open the app.
            return .reviewAnswer(
                questionID: questionID, picked: picked,
                correctIndex: info[ReviewNotifications.Key.answer] as? Int ?? -1,
                options: info[ReviewNotifications.Key.options] as? [String] ?? [],
                explanation: info[ReviewNotifications.Key.explanation] as? String ?? "",
                reference: info[ReviewNotifications.Key.reference] as? String ?? ""
            )
        }
        if let bookID = info["bookID"] as? String { return .book(bookID) }
        if let hearken = info["hearken"] as? [String: Any], let groupID = hearken["groupId"] as? String {
            // A study group notification (from the Hearth API): open what it's about.
            return .group(id: groupID, kind: hearken["kind"] as? String,
                          targetType: hearken["targetType"] as? String, targetID: hearken["targetId"] as? String)
        }
        if let groupID = info["groupID"] as? String { return .legacyGroup(groupID) }
        if let chapterID = info["chapterID"] as? String { return .chapter(chapterID) }
        return .none
    }

    @MainActor
    private static func handle(_ tap: Tap) async {
        switch tap {
        case let .reviewAnswer(questionID, picked, correctIndex, options, explanation, reference):
            await ReviewNotifications.answer(
                questionID: questionID, picked: picked, correctIndex: correctIndex,
                options: options, explanation: explanation, reference: reference
            )
        case .book(let bookID):
            AppNavigator.shared.pendingBookID = bookID
        case let .group(id, kind, targetType, targetID):
            GroupStore.shared.open(groupID: id, kind: kind, targetType: targetType, targetID: targetID)
        case .legacyGroup(let groupID):
            GroupStore.shared.openGroupID = groupID
        case .chapter(let chapterID):
            AppNavigator.shared.open(chapterID: chapterID)
        case .none:
            break
        }
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
