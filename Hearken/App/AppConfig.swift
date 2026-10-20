import Foundation

/// App-wide settings: iCloud, the Hearth API (study groups), links shown in Settings, and the
/// disclaimer.
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

    /// RevenueCat's public SDK key for Hearken (Hearken Plus, Hearth+ and tips). The same key in
    /// Debug. Until the real `appl_…` key is filled in, purchases stay off (see `HearkenApp`).
    nonisolated static let revenueCatAPIKey = "appl_lwbZGMslpUCfXbmaXsSrZUdMbss"

    /// The Hearth apps share one set of legal pages and one support address.
    static let termsURL = URL(string: "https://hearthapps.com/terms")!
    static let privacyURL = URL(string: "https://hearthapps.com/privacy")!
    static let supportURL = URL(string: "https://hearthapps.com/support")!
    static let supportEmail = "support@hearthapps.com"
    static let supportEmailURL = URL(string: "mailto:support@hearthapps.com?subject=Hearken")!

    static let disclaimer = "Hearken is an independent study app. It is not made, sponsored or endorsed by The Church of Jesus Christ of Latter-day Saints."
}
