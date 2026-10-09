import Foundation
import SwiftData

enum AppConfig {
    /// Turn on once the iCloud capability is set up for your team (see README).
    /// When false, user data stays on this device.
    static let cloudSyncEnabled = false
    static let cloudKitContainerID = "iCloud.com.stephenwarren.hearken"

    // Placeholders until the site is live.
    static let termsURL = URL(string: "https://example.com/hearken/terms")!
    static let privacyURL = URL(string: "https://example.com/hearken/privacy")!
    static let supportURL = URL(string: "https://example.com/hearken/support")!

    static let disclaimer = "Hearken is an independent study app. It is not made, sponsored or endorsed by The Church of Jesus Christ of Latter-day Saints."
}

enum Persistence {
    static let schema = Schema([
        Highlight.self,
        Note.self,
        ReadingProgress.self,
        ItemReview.self,
        GameSession.self,
        XPEvent.self,
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            "Hearken",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: AppConfig.cloudSyncEnabled ? .private(AppConfig.cloudKitContainerID) : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the Hearken data store: \(error)")
        }
    }

    /// Removes every user record. Used by Settings › Delete Account.
    static func eraseAll(in context: ModelContext) throws {
        try context.delete(model: Highlight.self)
        try context.delete(model: Note.self)
        try context.delete(model: ReadingProgress.self)
        try context.delete(model: ItemReview.self)
        try context.delete(model: GameSession.self)
        try context.delete(model: XPEvent.self)
        try context.save()
    }
}
