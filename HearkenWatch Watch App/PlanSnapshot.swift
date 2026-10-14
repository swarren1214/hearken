import Foundation
import WidgetKit

/// What the widgets, Siri and Shortcuts show about the active plan, saved as a small file
/// the app writes after every change. Widgets run in their own process and can't open the
/// app's data store, so they read this instead (from the shared App Group container).
///
/// Apple Watch copy of the app's PlanSnapshot (Services/Plans). Keep the copies in sync.
/// The watch app saves it (from the iPhone, via WatchStore); the watch widget reads it.
struct PlanSnapshot: Codable, Hashable {
    struct Chapter: Codable, Hashable {
        let name: String
        let chapterID: String
        let done: Bool
    }

    var title: String
    var dayNumber: Int
    var totalDays: Int
    var fraction: Double
    var statusLine: String
    var isReadingDay: Bool
    var todayRange: String
    var todayChapters: [Chapter]
    var minutes: Int
    var streak: Int
    var nextChapterID: String?
    var finished: Bool
    var updatedAt: Date
}

enum PlanSnapshotStore {
    /// Add this App Group to both the watch app and the watch widget extension (Signing & Capabilities).
    /// On the watch it's a separate container from the iPhone's, filled by the watch app.
    static let appGroupID = "group.com.stephenwarren.hearken"
    private static let fileName = "plan-snapshot.json"

    /// The shared App Group container when it's set up, otherwise the app's own support folder
    /// (enough for Siri and Shortcuts, which run in the app).
    static var fileURL: URL? {
        let manager = FileManager.default
        if let group = manager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return group.appendingPathComponent(fileName)
        }
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? manager.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent(fileName)
    }

    static func load() -> PlanSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PlanSnapshot.self, from: data)
    }

    /// Saves (or with nil, removes) the snapshot, and refreshes the widgets if it changed.
    static func save(_ snapshot: PlanSnapshot?) {
        guard let url = fileURL else { return }
        var previous = load()
        previous?.updatedAt = .distantPast
        var comparable = snapshot
        comparable?.updatedAt = .distantPast
        if let snapshot {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
        if previous != comparable {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension PlanSnapshot {
    /// For previews and the widget gallery.
    static let sample = PlanSnapshot(
        title: "Book of Mormon in 90 Days", dayNumber: 38, totalDays: 90, fraction: 0.41, statusLine: "On track",
        isReadingDay: true, todayRange: "Alma 5–7",
        todayChapters: [
            Chapter(name: "Alma 5", chapterID: "bofm.alma.5", done: true),
            Chapter(name: "Alma 6", chapterID: "bofm.alma.6", done: false),
            Chapter(name: "Alma 7", chapterID: "bofm.alma.7", done: false),
        ],
        minutes: 18, streak: 12, nextChapterID: "bofm.alma.6", finished: false, updatedAt: .now
    )

    var chaptersDone: Int { todayChapters.filter(\.done).count }
    var todayDone: Bool { !todayChapters.isEmpty && chaptersDone == todayChapters.count }
}
