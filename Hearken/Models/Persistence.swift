import CoreData
import Foundation
import OSLog
import SwiftData

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

enum Persistence {
    static let schema = Schema([
        Highlight.self,
        Note.self,
        ReadingProgress.self,
        ItemReview.self,
        GameSession.self,
        XPEvent.self,
        Bookmark.self,
    ])

    private static let log = Logger(subsystem: "com.stephenwarren.hearken", category: "persistence")

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        // Previews and tests use an in-memory store and never touch iCloud.
        let syncs = AppConfig.cloudSyncEnabled && !inMemory
        let configuration = ModelConfiguration(
            "Hearken",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncs ? .private(AppConfig.cloudKitContainerID) : .none
        )
        #if DEBUG
        if syncs { initializeCloudKitSchemaIfNeeded(storeURL: configuration.url) }
        #endif
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create the Hearken data store: \(error)")
        }
    }

    #if DEBUG
    /// Bump when a model changes, so the next debug run pushes the new schema.
    private static let schemaVersion = 2

    /// Creates every record type and field in the CloudKit development environment, once per
    /// schema version, on debug builds. CloudKit otherwise only learns about a type when a
    /// record of it is first saved, and a type missing from the schema you deploy to
    /// production would fail to sync in TestFlight and the App Store.
    ///
    /// Afterwards, deploy it: CloudKit Console › iCloud.com.stephenwarren.hearken ›
    /// Schema › Deploy Schema Changes… (before each TestFlight build that changes models).
    private static func initializeCloudKitSchemaIfNeeded(storeURL: URL) {
        let key = "cloudkit.schemaInitialized"
        guard UserDefaults.standard.integer(forKey: key) < schemaVersion else { return }
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [
            Highlight.self, Note.self, ReadingProgress.self, ItemReview.self, GameSession.self, XPEvent.self, Bookmark.self,
        ]) else { return }

        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: AppConfig.cloudKitContainerID)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "Hearken", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: (any Error)?
        container.loadPersistentStores { _, error in loadError = error }
        defer {
            // Release the store so SwiftData can open it.
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }
        if let loadError {
            log.error("CloudKit schema: couldn't open the store: \(loadError.localizedDescription, privacy: .public)")
            return
        }
        do {
            try container.initializeCloudKitSchema()
            UserDefaults.standard.set(schemaVersion, forKey: key)
            log.info("CloudKit schema initialized (version \(schemaVersion))")
        } catch {
            // Usually: not signed in to iCloud on this device. It tries again next launch.
            log.error("CloudKit schema: \(error.localizedDescription, privacy: .public)")
        }
    }
    #endif

    /// Removes every user record. Used by Settings › Delete Account.
    static func eraseAll(in context: ModelContext) throws {
        try context.delete(model: Highlight.self)
        try context.delete(model: Note.self)
        try context.delete(model: ReadingProgress.self)
        try context.delete(model: ItemReview.self)
        try context.delete(model: GameSession.self)
        try context.delete(model: XPEvent.self)
        try context.delete(model: Bookmark.self)
        try context.save()
    }
}
