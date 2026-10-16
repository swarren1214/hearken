import Foundation

/// Settings that follow the user to their other devices: text size, verse
/// numbers, reader layout, the daily goal, and the Apple Pencil highlight color and style.
///
/// Like the highlight legend, each one is stored in UserDefaults (where `@AppStorage` reads
/// it) and mirrored to iCloud key-value storage (NSUbiquitousKeyValueStore). A change made
/// here is copied up; a change from another device is copied down into UserDefaults, which
/// updates every `@AppStorage` showing it. Settings that belong to this device (appearance,
/// reminders and their times, Pencil highlighting on or off, Listen voices) aren't listed.
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()

    private static let keys: [String] = [
        SettingsKey.scriptureTextSize,
        SettingsKey.showVerseNumbers,
        SettingsKey.readerLayout,
        SettingsKey.dailyGoalMinutes,
        SettingsKey.pencilHue,
        SettingsKey.pencilStyle,
    ]

    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private var observers: [any NSObjectProtocol] = []
    /// Each key's value as last copied up or down, so only real local changes are uploaded
    /// (never a stale value racing a change that just arrived from another device).
    private var known: [String: Any] = [:]

    private init() {}

    /// Starts mirroring. Call once at launch.
    func start() {
        guard observers.isEmpty, !ScreenshotMode.isOn else { return }
        // As with the legend, iCloud's value wins; a setting only made here is copied up.
        for key in Self.keys {
            if let value = cloud.object(forKey: key) {
                apply(value, to: key)
            } else if let value = defaults.object(forKey: key) {
                cloud.set(value, forKey: key)
                known[key] = value
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: cloud, queue: .main) { notification in
            let changed = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            MainActor.assumeIsolated { SettingsSync.shared.pullFromCloud(changed) }
        })
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { SettingsSync.shared.pushToCloud() }
        })
        cloud.synchronize()
    }

    /// Another device changed something (or iCloud finished its first download).
    private func pullFromCloud(_ changedKeys: [String]?) {
        for key in Self.keys where changedKeys?.contains(key) ?? true {
            guard let value = cloud.object(forKey: key) else { continue }
            apply(value, to: key)
        }
    }

    /// Something in UserDefaults changed: upload the listed settings that changed here.
    private func pushToCloud() {
        for key in Self.keys {
            let local = defaults.object(forKey: key)
            guard !Self.same(local, known[key]) else { continue }
            known[key] = local
            if let local {
                cloud.set(local, forKey: key)
            } else {
                cloud.removeObject(forKey: key)
            }
        }
    }

    private func apply(_ value: Any, to key: String) {
        known[key] = value
        guard !Self.same(defaults.object(forKey: key), value) else { return }
        defaults.set(value, forKey: key)
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as? NSObject)?.isEqual(b) ?? false
        default: return false
        }
    }
}
