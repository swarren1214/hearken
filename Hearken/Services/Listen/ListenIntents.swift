import AppIntents
import Foundation

/// "Read today's chapter in Hearken": listens to today's plan chapters, without opening the app.
struct ListenTodayIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Listen to Today's Reading" }
    static var description: IntentDescription { IntentDescription("Reads today's chapters in your reading plan aloud.") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let plan = PlanSnapshotStore.load() else {
            return .result(dialog: "You don't have a reading plan yet. Start one from the Library in Hearken.")
        }
        var chapters = plan.todayChapters.filter { !$0.done }.map(\.chapterID)
        if chapters.isEmpty, let next = plan.nextChapterID { chapters = [next] }
        guard !chapters.isEmpty else {
            return .result(dialog: "You've finished \(plan.title). Nice work.")
        }
        ListenEngine.shared.start(chapterIDs: chapters, source: .plan)
        guard ListenEngine.shared.isPlaying else {
            return .result(dialog: "Today's chapters aren't available to listen to yet.")
        }
        return .result(dialog: "Reading \(plan.todayRange).")
    }
}

/// Pauses or resumes Listen mode.
struct ListenToggleIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource { "Pause or Resume Listening" }
    static var description: IntentDescription { IntentDescription("Pauses or resumes Hearken's Listen mode.") }

    @MainActor
    func perform() async throws -> some IntentResult {
        let engine = ListenEngine.shared
        if !engine.isActive { engine.restoreIfRecent() }
        engine.toggle()
        return .result()
    }
}
