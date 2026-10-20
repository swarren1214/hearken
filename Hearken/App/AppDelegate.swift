import CloudKit
import CoreData
import UIKit

/// App and scene delegates for what SwiftUI doesn't cover: push notifications for study groups,
/// and CloudKit share links (the Hearth household, and study-group invites from Hearken 1.x).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        StoreSetupGuard.begin(application)
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    /// Study group notifications come from the Hearth API, which needs this device's token.
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await GroupStore.shared.updatePushToken(deviceToken) }
    }

    /// The completion-handler form, called back on the main thread (see `NotificationRouter`:
    /// the async form can call UIKit back from a background thread).
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard GroupStore.isGroupNotification(userInfo) else {
            completionHandler(.noData)
            return
        }
        Task { @MainActor in
            await GroupStore.shared.refresh()
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Launched by tapping an invite link.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            if HearthHouseholdStore.handles(metadata) {
                HearthHouseholdStore.shared.receive(metadata)
            } else {
                Self.acceptLegacyGroupInvite(metadata)
            }
        }
    }

    /// Tapped an invite link while Hearken was already running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        if HearthHouseholdStore.handles(cloudKitShareMetadata) {
            HearthHouseholdStore.shared.receive(cloudKitShareMetadata)
        } else {
            Self.acceptLegacyGroupInvite(cloudKitShareMetadata)
        }
    }

    /// An invite link to a study group from Hearken 1.x (a CloudKit share). Accepting it puts the
    /// old zone in this person's shared database, where the move to the Hearth API finds it and
    /// claims a seat in the group, once its owner has moved it.
    private static func acceptLegacyGroupInvite(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            _ = try? await CKContainer(identifier: metadata.containerIdentifier).accept(metadata)
            GroupMigration.reset()
            await GroupStore.shared.refresh()
        }
    }
}

/// Keeps Hearken from being suspended while the data store finishes opening.
///
/// The store lives in the shared App Group container. When the Watch or Siri launches Hearken
/// in the background, iOS gives it only a moment before suspending it, and CloudKit's setup can
/// still be writing to the store then, holding its file lock. iOS kills an app that is suspended
/// holding a lock on a shared file (0xdead10cc, build 21). A background task keeps the app
/// running until CloudKit reports its setup finished, the app comes to the foreground, or
/// 20 seconds pass, whichever is first.
@MainActor
enum StoreSetupGuard {
    private static var task: UIBackgroundTaskIdentifier = .invalid
    private static var observers: [any NSObjectProtocol] = []

    static func begin(_ application: UIApplication) {
        guard task == .invalid else { return }
        task = application.beginBackgroundTask(withName: "Open data store") { end() }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  event.type == .setup, event.endDate != nil else { return }
            MainActor.assumeIsolated { end() }
        })
        // In the foreground the app isn't about to be suspended.
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { end() }
        })
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(20))
            end()
        }
    }

    private static func end() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}
