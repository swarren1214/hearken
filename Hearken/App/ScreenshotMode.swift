import SwiftData
import SwiftUI
import TipKit

/// Screenshot mode, for marketing screenshots (scripts/screenshots.sh).
///
/// Launched with `-HearkenScreenshots`, Hearken runs on an in-memory store filled with demo
/// content, is signed in as a demo reader, shows demo study groups instead of loading them
/// from CloudKit, and keeps tips, the tour and badge celebrations out of the way. Adding
/// `-HearkenScreen <name>` opens one screen (see `Screen`). Debug builds only: Release
/// ignores the arguments, so none of this can be reached in the App Store build.
nonisolated enum ScreenshotMode {
    static let isOn: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-HearkenScreenshots")
        #else
        return false
        #endif
    }()

    /// The screens the script captures, by the name passed after `-HearkenScreen`.
    nonisolated enum Screen: String, CaseIterable {
        case today, reader, listen, group, play, path, badges, quiz, mapquest, library, notebook, plans
    }

    static let screen: Screen? = {
        guard isOn else { return nil }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-HearkenScreen"), arguments.indices.contains(index + 1) else { return nil }
        return Screen(rawValue: arguments[index + 1])
    }()

    /// The demo reader.
    static let demoName = "Sarah Jensen"
    static let demoUserID = "screenshots-me"

    /// At launch, before anything reads them: the settings that would otherwise show first-run screens.
    @MainActor
    static func prepareLaunch() {
        guard isOn else { return }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: SettingsKey.onboardingDone)
        defaults.set(true, forKey: SettingsKey.tourDone)
        defaults.set(NotebookGrouping.book.rawValue, forKey: SettingsKey.notebookGrouping)
        // Must come before Tips.configure (ReaderTips.configure, in HearkenApp.init).
        Tips.hideAllTipsForTesting()
    }
}

/// Screens pushed only in screenshot mode (the app reaches them through inline links).
enum ScreenshotRoute: Hashable {
    case reader(chapterID: String, verse: Int)
    case notebook
    case plans
}

extension View {
    /// Destinations for `ScreenshotRoute`, added to each tab's root view.
    func screenshotDestinations() -> some View {
        navigationDestination(for: ScreenshotRoute.self) { route in
            switch route {
            case .reader(let chapterID, let verse): ReaderView(chapterID: chapterID, verse: verse)
            case .notebook: NotebookView()
            case .plans: ReadingPlansView()
            }
        }
    }

    /// Screenshot mode: fills the store with demo content, then opens the requested screen.
    /// Does nothing otherwise.
    func screenshotStage(selection: Binding<AppTab>, todayPath: Binding<NavigationPath>,
                         playPath: Binding<NavigationPath>, libraryPath: Binding<NavigationPath>) -> some View {
        modifier(ScreenshotStage(selection: selection, todayPath: todayPath, playPath: playPath, libraryPath: libraryPath))
    }
}

private struct ScreenshotStage: ViewModifier {
    @Binding var selection: AppTab
    @Binding var todayPath: NavigationPath
    @Binding var playPath: NavigationPath
    @Binding var libraryPath: NavigationPath

    @Environment(ContentService.self) private var content
    @Environment(\.modelContext) private var modelContext
    @State private var game: GameRequest?
    @State private var mapQuest: MapQuestCategory?

    func body(content view: Content) -> some View {
        if ScreenshotMode.isOn {
            view
                .task { await stage() }
                .fullScreenCover(item: $game) { GameView(request: $0) }
                .fullScreenCover(item: $mapQuest) { MapQuestView(category: $0) }
        } else {
            view
        }
    }

    private func stage() async {
        ScreenshotSeed.seed(context: modelContext, content: content)
        await GroupStore.shared.refresh()
        // Let the first screen settle before moving on from it.
        try? await Task.sleep(for: .milliseconds(400))
        guard let screen = ScreenshotMode.screen else { return }
        switch screen {
        case .today:
            selection = .today
        case .reader:
            selection = .today
            todayPath.append(ScreenshotRoute.reader(chapterID: ScreenshotSeed.readerChapterID, verse: 21))
        case .listen:
            selection = .today
            todayPath.append(ScreenshotRoute.reader(chapterID: ScreenshotSeed.readerChapterID, verse: 21))
            try? await Task.sleep(for: .milliseconds(600))
            ListenEngine.shared.start(chapterID: ScreenshotSeed.readerChapterID, fromVerse: 21)
            try? await Task.sleep(for: .milliseconds(800))
            ListenEngine.shared.showsPlayer = true
        case .group:
            selection = .today
            todayPath.append(GroupRoute(id: GroupStore.demoGroupID))
        case .play:
            selection = .play
        case .path:
            selection = .play
            playPath.append(SubjectRoute(subjectID: ScreenshotSeed.pathSubjectID))
        case .badges:
            selection = .play
            playPath.append(BadgesRoute())
        case .quiz:
            selection = .play
            game = ScreenshotSeed.quiz(content: content)
        case .mapquest:
            selection = .play
            mapQuest = MapQuestCatalog.all.first
        case .library:
            selection = .scriptures
        case .notebook:
            selection = .scriptures
            libraryPath.append(ScreenshotRoute.notebook)
        case .plans:
            selection = .scriptures
            libraryPath.append(ScreenshotRoute.plans)
        }
    }
}

// MARK: - Demo content

/// The demo reader: 50 days into the Book of Mormon in 90 days and on track, with highlights
/// and notes, a few weeks of games, and Stage 1 of the Scholar Path behind them.
@MainActor
enum ScreenshotSeed {
    static let readerChapterID = "bofm.alma.32"
    static let pathSubjectID = "lds-doctrine"
    static let planStartDaysAgo = 50

    private static var seeded = false

    static func seed(context: ModelContext, content: ContentService) {
        guard ScreenshotMode.isOn, !seeded else { return }
        seeded = true
        seedPlan(context: context, content: content)
        seedMarks(context: context)
        seedGames(context: context, content: content)
        try? context.save()
        seedScholarPath(context: context)
        try? context.save()
    }

    /// The Daily Challenge in the quiz screenshot: Book of Mormon questions.
    static func quiz(content: ContentService) -> GameRequest {
        let preferred = content.questions(forSubject: "bofm-history")
        let questions = Array((preferred.count >= 5 ? preferred : content.questions).prefix(5))
        return GameRequest(title: "Daily Challenge", kind: .daily, subjectID: nil, questions: questions)
    }

    /// Midnight `daysAgo` days back, plus `hour` hours.
    private static func date(daysAgo: Int, hour: Double = 7) -> Date {
        let today = Calendar.current.startOfDay(for: .now)
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
        return day.addingTimeInterval(hour * 3600)
    }

    // MARK: Plan and reading

    private static func seedPlan(context: ModelContext, content: ContentService) {
        let start = date(daysAgo: planStartDaysAgo, hour: 0)
        let enrollment = PlanEnrollment(planID: "bofm-90", startDate: start, days: 90, readingDays: ReadingDays.everyDay.rawValue,
                                        reminderEnabled: false, reminderMinutes: 420)
        enrollment.createdAt = start
        context.insert(enrollment)

        // Every day so far read on its day; today, the first chapter read and the next one started.
        guard let state = PlanEngine.shared.state(for: enrollment, content: content, read: []) else { return }
        let today = Calendar.current.startOfDay(for: .now)
        for day in state.days where day.date <= today {
            let isToday = day.date == today
            let chapters = isToday ? Array(day.chapterIDs.prefix(1)) : day.chapterIDs
            for (index, chapterID) in chapters.enumerated() {
                let finished = day.date.addingTimeInterval(TimeInterval(6.5 * 3600 + Double(index) * 900))
                let progress = ReadingProgress(chapterID: chapterID)
                progress.completedAt = finished
                progress.updatedAt = finished
                progress.hasEarnedReadXP = true
                context.insert(progress)
                let xp = XPEvent(amount: 10, reason: "read")
                xp.createdAt = finished
                context.insert(xp)
            }
            if isToday, day.chapterIDs.count > 1 {
                let started = ReadingProgress(chapterID: day.chapterIDs[1], lastVerse: 9)
                started.updatedAt = .now.addingTimeInterval(-40 * 60)
                context.insert(started)
            }
        }
    }

    // MARK: Highlights, notes and bookmarks

    private struct Mark {
        let chapterID: String
        let verses: ClosedRange<Int>
        let hue: HighlightHue
        var style: HighlightStyle = .fill
        var note: String? = nil
        var tags: [String] = []
        let daysAgo: Int
    }

    private static let marks: [Mark] = [
        Mark(chapterID: "bofm.alma.32", verses: 21...21, hue: .yellow,
             note: "Faith isn't certainty. It's hope in something true, and it grows when I act on it.", tags: ["faith"], daysAgo: 5),
        Mark(chapterID: "bofm.alma.32", verses: 27...28, hue: .blue,
             note: "Even a desire to believe is enough to start. Trying the experiment this week: pray before reading each morning.",
             tags: ["faith", "goals"], daysAgo: 5),
        Mark(chapterID: "bofm.alma.32", verses: 41...41, hue: .green, style: .underline, daysAgo: 5),
        Mark(chapterID: "bofm.1-ne.3", verses: 7...7, hue: .yellow, daysAgo: 48),
        Mark(chapterID: "bofm.2-ne.2", verses: 25...25, hue: .pink,
             note: "Joy is the purpose, not an afterthought.", tags: ["joy"], daysAgo: 44),
        Mark(chapterID: "bofm.2-ne.31", verses: 20...20, hue: .green, daysAgo: 40),
        Mark(chapterID: "bofm.mosiah.2", verses: 17...17, hue: .orange,
             note: "Service this month: help the Nguyens move, and sub for Primary on the 20th.", tags: ["service"], daysAgo: 27),
        Mark(chapterID: "bofm.mosiah.3", verses: 19...19, hue: .purple, daysAgo: 26),
        Mark(chapterID: "bofm.alma.7", verses: 11...12, hue: .purple,
             note: "He knows how to help me because He chose to feel it all.", tags: ["Jesus Christ"], daysAgo: 16),
        Mark(chapterID: "bofm.alma.34", verses: 32...32, hue: .orange, daysAgo: 1),
        Mark(chapterID: "bofm.ether.12", verses: 27...27, hue: .teal,
             note: "Weakness is given so I come to Him, and then it can become strength.", tags: ["grace"], daysAgo: 3),
        Mark(chapterID: "bofm.moro.10", verses: 4...5, hue: .blue, daysAgo: 2),
    ]

    private static func seedMarks(context: ModelContext) {
        for mark in marks {
            let when = date(daysAgo: mark.daysAgo, hour: 7.25)
            let highlight = Highlight(chapterID: mark.chapterID,
                                      start: VersePosition(verse: mark.verses.lowerBound, offset: 0),
                                      end: VersePosition(verse: mark.verses.upperBound, offset: -1),
                                      hue: mark.hue, style: mark.style)
            highlight.createdAt = when
            highlight.updatedAt = when
            context.insert(highlight)
            if let body = mark.note {
                let note = Note(chapterID: mark.chapterID, verse: mark.verses.lowerBound, body: body, tags: mark.tags)
                note.createdAt = when.addingTimeInterval(120)
                note.updatedAt = when.addingTimeInterval(120)
                context.insert(note)
            }
        }
        let bookmark = Bookmark(name: "The faith experiment", chapterID: readerChapterID, verse: 27)
        bookmark.createdAt = date(daysAgo: 5)
        context.insert(bookmark)
    }

    // MARK: Games and review

    private static func seedGames(context: ModelContext, content: ContentService) {
        let mastery = MasteryService()
        let questions = content.questions.filter { $0.subjectID != pathSubjectID }
        for (index, question) in questions.prefix(30).enumerated() {
            // Mostly right, reviewed over the last two weeks.
            mastery.record(questionID: question.id, correct: index % 6 != 4, in: context, now: date(daysAgo: index % 14, hour: 20))
        }
        let sessions: [(GameKind, Int, Int, Int)] = [
            (.daily, 1, 5, 5), (.daily, 2, 4, 5), (.review, 3, 7, 8), (.daily, 4, 5, 5),
            (.chronology, 6, 6, 8), (.daily, 7, 3, 5), (.review, 9, 8, 8), (.daily, 11, 4, 5),
        ]
        for (kind, daysAgo, correct, total) in sessions {
            let session = GameSession(gameType: kind.rawValue, subjectID: "", correct: correct, total: total,
                                      xpEarned: correct * MasteryConfig.standard.xpPerCorrect)
            session.playedAt = date(daysAgo: daysAgo, hour: 20.5)
            context.insert(session)
        }
    }

    // MARK: Scholar Path

    /// Stage 1 complete (Novice and Apprentice earned), Stage 2 under way.
    private static func seedScholarPath(context: ModelContext) {
        guard let path = PathCatalog.shared.path(for: pathSubjectID) else { return }
        let ledger = ScholarLedger(context: context)
        func pass(_ assessment: PathAssessment?, kind: String) {
            guard let assessment else { return }
            ledger.record(AssessmentAttempt(assessmentID: assessment.id, subjectID: path.subjectID, kind: kind, questionIDs: [],
                                            points: 9, maxPoints: 10, passed: true, aiScored: false, answersJSON: "[]"), in: path)
            try? context.save()
        }
        func complete(_ items: [PathItem]) {
            for item in items {
                ledger.complete(item, in: path, response: "", feedback: "")
                try? context.save()
            }
        }

        let stages = path.publishedStages.sorted { $0.number < $1.number }
        if let first = stages.first {
            for course in first.courses {
                complete(course.requiredItems)
                pass(course.checkpoint, kind: "checkpoint")
            }
            pass(first.advancementCheck, kind: "advancement")
        }
        if stages.count > 1, let course = stages[1].courses.first {
            let items = course.requiredItems
            complete(Array(items.prefix(max(1, items.count / 2))))
        }

        // Already celebrated, earned over the last month.
        let grants = (try? context.fetch(FetchDescriptor<RankGrant>(sortBy: [SortDescriptor(\.rankRaw)]))) ?? []
        for (index, grant) in grants.enumerated() {
            grant.celebrated = true
            grant.earnedAt = date(daysAgo: max(30 - index * 22, 2), hour: 21)
        }
    }
}
