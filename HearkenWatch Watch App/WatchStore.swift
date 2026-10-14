import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Message keys shared with the iPhone. Must match WatchBridge in the iPhone app.
nonisolated enum WatchMessage {
    static let plan = "plan"
    static let listen = "listen"
    static let command = "command"
    static let value = "value"
    static let marked = "marked"

    enum Command: String {
        case toggle, nextVerse, previousVerse, nextChapter, previousChapter, setSpeed, markVerse, listenToday
    }
}

/// What the iPhone is playing in Listen mode.
struct ListenState: Equatable {
    var active = false
    var playing = false
    var chapterID = ""
    var title = ""
    var book = ""
    var verse = 1
    var verseCount = 1
    var speed = 1.0

    init() {}

    init(_ info: [String: Any]) {
        active = info["active"] as? Bool ?? false
        playing = info["playing"] as? Bool ?? false
        chapterID = info["chapterID"] as? String ?? ""
        title = info["title"] as? String ?? ""
        book = info["book"] as? String ?? ""
        verse = info["verse"] as? Int ?? 1
        verseCount = max(info["verseCount"] as? Int ?? 1, 1)
        speed = info["speed"] as? Double ?? 1
    }

    static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]

    var nextSpeed: Double {
        let index = Self.speeds.firstIndex(of: speed) ?? 1
        return Self.speeds[(index + 1) % Self.speeds.count]
    }

    var speedLabel: String {
        speed.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}

/// The watch's link to Hearken on the iPhone. Receives the plan snapshot and Listen's state,
/// saves the snapshot for the Smart Stack widget, and sends Listen commands.
@Observable
final class WatchStore: NSObject {
    static let shared = WatchStore()

    private(set) var plan: PlanSnapshot? = PlanSnapshotStore.load()
    private(set) var listen = ListenState()
    /// The reference of the verse just bookmarked, shown briefly on the remote.
    var marked: String?
    /// Shown when the iPhone can't be reached.
    var problem: String?

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ command: WatchMessage.Command, value: Double? = nil) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            problem = "Can't reach your iPhone right now."
            return
        }
        problem = nil
        // Feels instant; the iPhone's reply corrects it if needed.
        if command == .toggle, listen.active { listen.playing.toggle() }
        if command == .setSpeed, let value { listen.speed = value }

        var message: [String: Any] = [WatchMessage.command: command.rawValue]
        if let value { message[WatchMessage.value] = value }
        session.sendMessage(message, replyHandler: { reply in
            let listen = reply[WatchMessage.listen] as? [String: Any]
            let marked = reply[WatchMessage.marked] as? String
            Task { @MainActor in
                if let listen { WatchStore.shared.listen = ListenState(listen) }
                if let marked { WatchStore.shared.marked = marked }
            }
        }, errorHandler: { _ in
            Task { @MainActor in WatchStore.shared.problem = "Can't reach your iPhone right now." }
        })
    }

    fileprivate func apply(plan data: Data?, listen info: [String: Any]?) {
        if let info { listen = ListenState(info) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = data.flatMap { try? decoder.decode(PlanSnapshot.self, from: $0) }
        guard snapshot != plan else { return }
        plan = snapshot
        PlanSnapshotStore.save(snapshot)
    }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        guard !context.isEmpty else { return }
        let data = context[WatchMessage.plan] as? Data
        let listen = context[WatchMessage.listen] as? [String: Any]
        nonisolated(unsafe) let info = listen
        Task { @MainActor in WatchStore.shared.apply(plan: data, listen: info) }
    }

    /// The iPhone's latest plan and Listen state, delivered even when the watch app wasn't running.
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        let data = context[WatchMessage.plan] as? Data
        nonisolated(unsafe) let info = context[WatchMessage.listen] as? [String: Any]
        Task { @MainActor in WatchStore.shared.apply(plan: data, listen: info) }
    }

    /// Live Listen updates while the watch app is open.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        nonisolated(unsafe) let info = message[WatchMessage.listen] as? [String: Any]
        guard info != nil else { return }
        Task { @MainActor in WatchStore.shared.listen = ListenState(info ?? [:]) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in if reachable { WatchStore.shared.problem = nil } }
    }
}
