import CoreData
import Foundation
import OSLog
import SwiftData

enum Persistence {
    static let schema = Schema([
        Highlight.self,
        Note.self,
        ReadingProgress.self,
        ItemReview.self,
        GameSession.self,
        XPEvent.self,
        Bookmark.self,
        PlanEnrollment.self,
        SubjectAward.self,
        ItemCompletion.self,
        AssessmentAttempt.self,
        SubjectEnrollment.self,
        RankGrant.self,
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
            // Never crash on launch over the store. Set the unreadable one aside (kept, not
            // deleted, for recovery) and start a fresh one; with sync on, iCloud fills it back in.
            log.fault("Couldn't open the data store, starting a fresh one: \(error.localizedDescription, privacy: .public)")
            setAside(configuration.url)
            if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
                UserDefaults.standard.set(Date.now, forKey: recoveredKey)
                return container
            }
            // Last resort: an in-memory store, so the app still opens.
            log.fault("The fresh store failed too; running in memory this launch")
            let memory = ModelConfiguration("Hearken", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Could not create even an in-memory Hearken store: \(error)")
            }
        }
    }

    /// When the store last had to be rebuilt (see makeContainer), for support questions.
    static let recoveredKey = "persistence.recoveredAt"

    /// Renames the store and its journal files with a timestamp, so a fresh store can be made.
    private static func setAside(_ url: URL) {
        let stamp = Int(Date.now.timeIntervalSince1970)
        let manager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            guard manager.fileExists(atPath: file.path) else { continue }
            let aside = URL(fileURLWithPath: url.path + ".unreadable-\(stamp)" + suffix)
            do {
                try manager.moveItem(at: file, to: aside)
            } catch {
                log.error("Couldn't set aside \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    #if DEBUG
    /// Bump when a model changes, so the next debug run pushes the new schema.
    private static let schemaVersion = 5

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
            Highlight.self, Note.self, ReadingProgress.self, ItemReview.self, GameSession.self, XPEvent.self, Bookmark.self, PlanEnrollment.self,
            SubjectAward.self, ItemCompletion.self, AssessmentAttempt.self, SubjectEnrollment.self, RankGrant.self,
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
        try context.delete(model: PlanEnrollment.self)
        try context.delete(model: SubjectAward.self)
        try context.delete(model: ItemCompletion.self)
        try context.delete(model: AssessmentAttempt.self)
        try context.delete(model: SubjectEnrollment.self)
        try context.delete(model: RankGrant.self)
        try context.save()
    }
}
