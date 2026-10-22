import Foundation

/// Screenshot mode, for App Store screenshots of the watch app in the Simulator.
///
/// Launched with `-Screenshots`, the watch app shows demo content kept in memory: it doesn't
/// activate WatchConnectivity, doesn't load or save the plan snapshot, and sends nothing to the
/// iPhone. Adding `-Screen <name>` opens one page (see `Screen`). Debug builds only: Release
/// ignores the arguments, so none of this can be reached in the App Store build.
nonisolated enum ScreenshotMode {
    static let isOn: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-Screenshots")
        #else
        return false
        #endif
    }()

    /// The pages the script captures, in order, by the name passed after `-Screen`.
    nonisolated enum Screen: String, CaseIterable {
        case today, listen
    }

    static let screen: Screen? = {
        guard isOn else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-Screen"), arguments.indices.contains(index + 1) else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }()
}

/// The demo reader from the iPhone's screenshot mode (Hearken/App/ScreenshotMode.swift): day 51
/// of the Book of Mormon in 90 days, on track, with every day read so far. Today's first chapter
/// is read and the next one is playing in Listen on the iPhone.
enum ScreenshotDemo {
    /// What the iPhone would send for today: Alma 36–37, Alma 36 done.
    static var plan: PlanSnapshot {
        PlanSnapshot(
            title: "Book of Mormon in 90 Days", dayNumber: 51, totalDays: 90, fraction: 131.0 / 239.0, statusLine: "On track",
            isReadingDay: true, todayRange: "Alma 36–37",
            todayChapters: [
                PlanSnapshot.Chapter(name: "Alma 36", chapterID: "bofm.alma.36", done: true),
                PlanSnapshot.Chapter(name: "Alma 37", chapterID: "bofm.alma.37", done: false),
            ],
            minutes: 17, streak: 51, nextChapterID: "bofm.alma.37", finished: false, updatedAt: .now
        )
    }

    /// Listen playing Alma 37, partway through.
    static var listen: ListenState {
        var state = ListenState()
        state.active = true
        state.playing = true
        state.chapterID = "bofm.alma.37"
        state.title = "Alma 37"
        state.book = "Book of Mormon"
        state.verse = 14
        state.verseCount = 47
        state.speed = 1
        return state
    }
}
