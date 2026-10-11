import Foundation

/// App-wide settings: iCloud, links shown in Settings, and the disclaimer.
enum AppConfig {
    /// Highlights, notes, progress and XP sync through the person's private CloudKit database.
    /// Needs the iCloud (CloudKit), Push Notifications and Background Modes › Remote
    /// notifications capabilities. When false, user data stays on this device.
    static let cloudSyncEnabled = true
    static let cloudKitContainerID = "iCloud.com.stephenwarren.hearken"

    // Placeholders until the site is live.
    static let termsURL = URL(string: "https://example.com/hearken/terms")!
    static let privacyURL = URL(string: "https://example.com/hearken/privacy")!
    static let supportURL = URL(string: "https://example.com/hearken/support")!

    static let disclaimer = "Hearken is an independent study app. It is not made, sponsored or endorsed by The Church of Jesus Christ of Latter-day Saints."
}
