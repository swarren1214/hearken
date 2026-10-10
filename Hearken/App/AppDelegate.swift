import CloudKit
import UIKit

/// App and scene delegates for what SwiftUI doesn't cover: accepting a study-group invite
/// (a CloudKit share link) and silent pushes when a group changes.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard GroupStore.isGroupNotification(userInfo) else { return .noData }
        await GroupStore.shared.refresh(notify: true)
        return .newData
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
            GroupStore.shared.pendingInvite = metadata
        }
    }

    /// Tapped an invite link while Hearken was already running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        GroupStore.shared.pendingInvite = cloudKitShareMetadata
    }
}
