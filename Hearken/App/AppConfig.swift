import Foundation

/// App-wide settings: iCloud, links shown in Settings, and the disclaimer.
enum AppConfig {
    /// Highlights, notes, progress and XP sync through the person's private CloudKit database.
    /// Needs the iCloud (CloudKit), Push Notifications and Background Modes › Remote
    /// notifications capabilities. When false, user data stays on this device.
    static let cloudSyncEnabled = true
    static let cloudKitContainerID = "iCloud.com.stephenwarren.hearken"

    /// The shared Hearth API (study groups) and the Hearth Supabase project it signs in with.
    /// The publishable key is meant to ship in apps; it only reaches Supabase's sign-in.
    nonisolated static let apiBaseURL = URL(string: "https://api.hearthapps.com")!
    nonisolated static let supabaseURL = URL(string: "https://kvhvsztvfpydhfpzicyy.supabase.co")!
    nonisolated static let supabasePublishableKey = "sb_publishable_j0eyoaQiN3fogFINKooaDA_V0yjXkgY"

    static let termsURL = URL(string: "http://hearkenstudy.com/terms.html")!
    static let privacyURL = URL(string: "http://hearkenstudy.com/privacy.html")!
    static let supportURL = URL(string: "http://hearkenstudy.com/support.html")!

    static let disclaimer = "Hearken is an independent study app. It is not made, sponsored or endorsed by The Church of Jesus Christ of Latter-day Saints."
}
