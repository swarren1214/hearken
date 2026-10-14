import Foundation
import Observation
import SwiftData
import WatchConnectivity

/// The iPhone side of the Apple Watch app.
///
/// Out: the reading-plan snapshot (for the watch's Smart Stack widget and Today page) and
/// Listen's state (for the watch remote), as the session's application context, plus a live
/// message while the watch app is open.
/// In: Listen commands from the watch remote. Listening always happens on the iPhone; the
/// natural voices are too large to run on the watch.
///
/// Message keys must match WatchMessage in the watch app (WatchSource/HearkenWatch).
final class WatchBridge: NSObject {
    static let shared = WatchBridge()

    nonisolated enum Key {
        static let plan = "plan"
        static let listen = "listen"
        static let command = "command"
        static let value = "value"
        static let marked = "marked"
    }

    nonisolated enum Command: String {
        case toggle, nextVerse, previousVerse, nextChapter, previousChapter, setSpeed, markVerse, listenToday
    }

    private var container: ModelContainer?
    private var planData: Data?
    private var listenState: [String: Any] = [:]
    private var activated = false

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        observeListen()
    }

    // MARK: Out

    /// Called whenever the plan snapshot is saved (PlanSideEffects).
    func send(plan: PlanSnapshot?) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = plan.flatMap { try? encoder.encode($0) }
        guard data != planData else { return }
        planData = data
        pushContext()
    }

    private func pushContext() {
        guard activated, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        var context: [String: Any] = [Key.listen: listenState]
        if let planData { context[Key.plan] = planData }
        try? session.updateApplicationContext(context)
    }

    /// Re-sends Listen's state whenever something the remote shows changes.
    private func observeListen() {
        let state = withObservationTracking {
            Self.currentListenState()
        } onChange: {
            Task { @MainActor in WatchBridge.shared.observeListen() }
        }
        guard !NSDictionary(dictionary: state).isEqual(to: listenState) else { return }
        listenState = state
        pushContext()
        let session = WCSession.default
        if activated, session.isReachable {
            session.sendMessage([Key.listen: state], replyHandler: nil, errorHandler: nil)
        }
    }

    static func currentListenState() -> [String: Any] {
        let engine = ListenEngine.shared
        guard engine.isActive, let chapterID = engine.chapterID else { return ["active": false] }
        return [
            "active": true,
            "playing": engine.isPlaying,
            "chapterID": chapterID,
            "title": engine.title,
            "book": engine.bookTitle,
            "verse": engine.currentVerse ?? 1,
            "verseCount": engine.verseCount,
            "speed": engine.speed,
        ]
    }

    // MARK: In

    private func perform(_ command: Command, value: Double?) -> [String: Any] {
        let engine = ListenEngine.shared
        if !engine.isActive, command != .listenToday { engine.restoreIfRecent() }
        var reply: [String: Any] = [:]
        switch command {
        case .toggle: engine.toggle()
        case .nextVerse: engine.nextVerse()
        case .previousVerse: engine.previousVerse()
        case .nextChapter: engine.nextChapter()
        case .previousChapter: engine.previousChapter()
        case .setSpeed:
            if let value, ListenFormat.speeds.contains(value) { engine.setSpeed(value) }
        case .markVerse:
            if let reference = markCurrentVerse() { reply[Key.marked] = reference }
        case .listenToday:
            listenToday()
        }
        reply[Key.listen] = Self.currentListenState()
        return reply
    }

    /// Saves a bookmark at the verse being heard, named so it's easy to spot in Bookmarks.
    private func markCurrentVerse() -> String? {
        let engine = ListenEngine.shared
        guard let chapterID = engine.chapterID, let verse = engine.currentVerse, let context = container?.mainContext else { return nil }
        context.insert(Bookmark(name: "From Apple Watch", chapterID: chapterID, verse: verse))
        try? context.save()
        return engine.scripture.reference(chapterID: chapterID, verse: verse)
    }

    /// Same as the "Listen to Today's Reading" shortcut.
    private func listenToday() {
        guard let plan = PlanSnapshotStore.load() else { return }
        var chapters = plan.todayChapters.filter { !$0.done }.map(\.chapterID)
        if chapters.isEmpty, let next = plan.nextChapterID { chapters = [next] }
        guard !chapters.isEmpty else { return }
        ListenEngine.shared.start(chapterIDs: chapters, source: .plan)
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            WatchBridge.shared.activated = activationState == .activated
            WatchBridge.shared.pushContext()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in WatchBridge.shared.pushContext() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let raw = message[Key.command] as? String, let command = Command(rawValue: raw) else {
            replyHandler([:])
            return
        }
        let value = message[Key.value] as? Double
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            reply(WatchBridge.shared.perform(command, value: value))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let raw = message[Key.command] as? String, let command = Command(rawValue: raw) else { return }
        let value = message[Key.value] as? Double
        Task { @MainActor in _ = WatchBridge.shared.perform(command, value: value) }
    }
}
