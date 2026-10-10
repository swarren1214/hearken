import Foundation
import WidgetKit

/// What the widgets, Siri and Shortcuts show about the active plan, saved as a small file
/// the app writes after every change. Widgets run in their own process and can't open the
/// app's data store, so they read this instead (from the shared App Group container).
///
/// Keep in sync with the copy in the HearkenWidgets target.
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

extension PlanSnapshot {
    init(state: PlanState, streak: Int, now: Date = .now) {
        let day = state.currentDay
        self.init(
            title: state.plan.title,
            dayNumber: state.dayNumber,
            totalDays: state.totalDays,
            fraction: state.fraction,
            statusLine: state.statusLine,
            isReadingDay: state.isReadingDayToday,
            todayRange: PlanFormat.range(day?.chapterIDs ?? []),
            todayChapters: (day?.chapterIDs ?? []).map {
                Chapter(name: PlanFormat.chapterName($0), chapterID: $0, done: state.read.contains($0))
            },
            minutes: day?.minutes ?? 0,
            streak: streak,
            nextChapterID: state.nextChapterID,
            finished: state.isFinished,
            updatedAt: now
        )
    }
}

enum PlanSnapshotStore {
    /// Add this App Group to both the app and the widget extension (Signing & Capabilities).
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
