import Foundation
import UserNotifications

/// The reading plan's daily reminder: one notification per upcoming reading day at the
/// chosen time, naming that day's chapters. A day that's already read gets none.
/// Rescheduled whenever progress or the plan changes (see PlanSideEffects).
@MainActor
enum PlanReminders {
    private static let prefix = "hearken.plan."
    /// Notifications are scheduled this many reading days ahead.
    private static let horizon = 10

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func update(state: PlanState?, enabled: Bool, minutes: Int, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })

        guard let state, enabled, !state.isFinished else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let calendar = Calendar.current
        var scheduled = 0
        for day in state.days where day.date >= state.today && scheduled < horizon {
            if state.isDone(day) { continue }
            guard let fire = calendar.date(byAdding: .minute, value: minutes, to: day.date), fire > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Today's reading: \(PlanFormat.range(day.chapterIDs))"
            content.body = "About \(day.minutes) minutes · Day \(day.number) of \(state.totalDays), \(state.plan.title)"
            content.sound = .default
            content.threadIdentifier = "reading-plan"
            if let first = day.chapterIDs.first(where: { !state.read.contains($0) }) {
                content.userInfo = ["chapterID": first]
            }
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
                repeats: false
            )
            let id = prefix + day.date.formatted(.iso8601.year().month().day())
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            scheduled += 1
        }
    }
}
