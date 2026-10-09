import CoreData
import Foundation
import Observation
import OSLog
import SwiftData

/// Tracks iCloud sync for Settings: when it last finished, whether it's running, and the
/// last error. Also runs a manual sync from the Sync Now button.
///
/// SwiftData syncs with CloudKit on its own (on launch, after saves, and when iCloud sends a
/// change). There's no public "sync now" call, so a manual sync saves any pending changes
/// (which starts an upload), pushes the iCloud key-value store (profile photo, highlight
/// legend), then waits for CloudKit to finish whatever it's doing.
@MainActor
@Observable
final class SyncService {
    private(set) var lastSynced: Date?
    private(set) var isSyncing = false
    /// CloudKit is uploading or downloading on its own (on launch, after saves, or when
    /// another device changed something).
    private(set) var isCloudKitBusy = false
    /// Syncing right now, by Sync Now or on its own.
    var isActive: Bool { isSyncing || isCloudKitBusy }
    private(set) var lastError: String?

    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "sync")
    private let defaults: UserDefaults
    private static let lastSyncedKey = "sync.lastSynced"

    /// CloudKit work that has started but not finished.
    @ObservationIgnored private var activeEvents: Set<UUID> = []
    @ObservationIgnored private var lastFailure: (date: Date, message: String)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lastSynced = defaults.object(forKey: Self.lastSyncedKey) as? Date

        // SwiftData's CloudKit mirroring reports its setup, import and export work here.
        _ = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            let id = event.identifier
            let endDate = event.endDate
            let succeeded = event.succeeded
            let message = event.error?.localizedDescription
            MainActor.assumeIsolated {
                self?.handle(id: id, endDate: endDate, succeeded: succeeded, error: message)
            }
        }
    }

    /// Saves, syncs the key-value store, and waits (up to 20 seconds) for CloudKit to finish.
    func syncNow(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }
        let started = Date.now

        do {
            if context.hasChanges { try context.save() }
        } catch {
            log.error("sync: save failed: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
            return
        }
        NSUbiquitousKeyValueStore.default.synchronize()

        if AppConfig.cloudSyncEnabled {
            // Give CloudKit a moment to pick up the save, then wait for running work to finish.
            try? await Task.sleep(for: .seconds(1.5))
            let deadline = Date.now.addingTimeInterval(20)
            while !activeEvents.isEmpty, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(300))
            }
            if let lastFailure, lastFailure.date >= started {
                lastError = lastFailure.message
                return
            }
        }
        // Nothing failed: everything is up to date as of now.
        markSynced(.now)
        log.info("sync: finished")
    }

    private func handle(id: UUID, endDate: Date?, succeeded: Bool, error: String?) {
        guard let endDate else {
            activeEvents.insert(id)
            isCloudKitBusy = true
            return
        }
        activeEvents.remove(id)
        isCloudKitBusy = !activeEvents.isEmpty
        if succeeded {
            markSynced(endDate)
        } else if let error {
            log.error("sync: CloudKit event failed: \(error, privacy: .public)")
            lastFailure = (endDate, error)
            if !isSyncing { lastError = error }
        }
    }

    private func markSynced(_ date: Date) {
        guard date > (lastSynced ?? .distantPast) else { return }
        lastSynced = date
        lastError = nil
        defaults.set(date, forKey: Self.lastSyncedKey)
    }
}
