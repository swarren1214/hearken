import CloudKit
import CoreData
import Foundation

/// Pull to refresh for every screen that shows data kept in iCloud
/// (`.refreshable { await CloudRefresh.refresh() }`).
///
/// SwiftData's CloudKit sync has no public "fetch now" call: iOS schedules imports itself
/// (on launch, on returning to the app, and when CloudKit's silent push says another device
/// changed something). So a refresh syncs the iCloud key-value store (highlight legend,
/// profile photo, settings), reloads study groups straight from CloudKit, and waits for the
/// next SwiftData import to finish, or about 6 seconds, whichever comes first.
@MainActor
enum CloudRefresh {
    /// How long to wait for SwiftData's next import before letting the spinner go.
    private static let importTimeout: Duration = .seconds(6)

    static func refresh() async {
        // Screenshot mode (Debug) and previews never touch iCloud.
        guard AppConfig.cloudSyncEnabled, !ScreenshotMode.isOn else { return }
        // Not signed in to iCloud (or iCloud is restricted): there's nothing to fetch.
        let status = try? await CKContainer(identifier: AppConfig.cloudKitContainerID).accountStatus()
        guard status == .available else { return }

        NSUbiquitousKeyValueStore.default.synchronize()
        let started = Date.now
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await GroupStore.shared.refresh() }
            group.addTask { await waitForImport(endingAfter: started) }
        }
    }

    /// Waits until a SwiftData CloudKit import that was running or started after `date`
    /// finishes, or `importTimeout` passes.
    private static func waitForImport(endingAfter date: Date) async {
        let timeout = importTimeout
        let (imports, continuation) = AsyncStream.makeStream(of: Void.self)
        // SwiftData's CloudKit mirroring reports its setup, import and export work here.
        let observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
                event.type == .import,
                let endDate = event.endDate, endDate >= date else { return }
            continuation.yield()
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            continuation.finish()
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in imports { return }
            }
            group.addTask { try? await Task.sleep(for: timeout) }
            // Whichever finishes first ends the wait; the other is cancelled.
            _ = await group.next()
            group.cancelAll()
        }
    }
}
