import Foundation
import UserNotifications

/// The optional daily study reminder (Settings › Study Reminder).
enum ReminderScheduler {
    private static let identifier = "hearken.daily-reminder"

    /// Asks for permission if needed and schedules a repeating reminder. Returns false if permission is denied.
    static func enable(hour: Int = 20, minute: Int = 0) async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { return false }

            let content = UNMutableNotificationContent()
            content.title = "Time to hearken"
            content.body = "A few minutes in the scriptures keeps your streak going."
            content.sound = .default

            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            return true
        } catch {
            return false
        }
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
