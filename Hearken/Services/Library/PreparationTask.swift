import BackgroundTasks
import Foundation
import OSLog

/// Keeps books preparing after the app is closed, with the system's progress indicator
/// (a BGContinuedProcessingTask, iOS 26), started from the Add to Library sheet's Add.
///
/// The work itself is BookImporter's; this only asks iOS for time and reports progress:
/// "Preparing The Book of Enoch · Adding verses · 72%". Stop in that indicator, or iOS
/// running out of time for it, leaves the books to finish next time the app is open.
@MainActor
final class PreparationTask {
    static let shared = PreparationTask()

    /// Declared in Info.plist (BGTaskSchedulerPermittedIdentifiers) as "<prefix>.*".
    nonisolated static let identifierPrefix = "com.stephenwarren.hearken.prepare"

    private var task: BGContinuedProcessingTask?
    private var submitted = false
    private var title = ""
    /// The books this run is waiting on.
    private var bookIDs: Set<String> = []
    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "import")

    /// What to do when iOS starts the task. Continued-processing tasks are registered just
    /// before they're submitted, each with its own identifier; a request without a
    /// registered handler would be an exception, so nothing is submitted unless this worked.
    nonisolated private static func registerHandler(for identifier: String) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            // iOS calls this on a queue of its own; the work is tracked on the main actor.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let task = task as? BGContinuedProcessingTask else {
                        task.setTaskCompleted(success: false)
                        return
                    }
                    PreparationTask.shared.started(task)
                }
            }
        }
    }

    /// Asks iOS to keep the app running for these books; joins a run already going.
    func begin(bookIDs ids: [String], title: String) {
        guard !ids.isEmpty else { return }
        bookIDs.formUnion(ids)
        if submitted {
            self.title = bookIDs.count == 1 ? title : "Preparing \(bookIDs.count) books"
            update()
            return
        }
        self.title = title
        let identifier = "\(Self.identifierPrefix).\(UUID().uuidString)"
        guard Self.registerHandler(for: identifier) else {
            log.info("Background preparing not available: couldn't register \(identifier, privacy: .public)")
            return
        }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "Reading file")
        // Start now or not at all: the books prepare anyway while the app is open.
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            submitted = true
        } catch {
            log.info("Background preparing not available: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func started(_ task: BGContinuedProcessingTask) {
        self.task = task
        task.progress.totalUnitCount = 100
        task.expirationHandler = Self.expirationHandler()
        update()
        if bookIDs.isEmpty { complete(success: true) }
    }

    /// Built outside the main actor: iOS calls it on a queue of its own.
    nonisolated private static func expirationHandler() -> @Sendable () -> Void {
        {
            Task { @MainActor in PreparationTask.shared.complete(success: false) }
        }
    }

    /// Progress and stage across the books in this run, for the system indicator.
    func update() {
        guard let task else { return }
        let library = ImportedLibrary.shared
        let active = bookIDs.filter { library.progress[$0] != nil }
        let done = bookIDs.count - active.count
        let fraction = bookIDs.isEmpty ? 1 : (Double(done) + active.reduce(0) { $0 + (library.progress[$1] ?? 0) }) / Double(bookIDs.count)
        task.progress.completedUnitCount = Int64((fraction * 100).rounded())
        let stage = active.first.flatMap { id in
            library.stage[id].map { $0.title(for: library.model(id)?.format ?? .epub) }
        } ?? "Finishing"
        task.updateTitle(title, subtitle: "\(stage) · \(Int((fraction * 100).rounded()))%")
    }

    /// A book is done (ready or failed); when they all are, so is the task.
    func finished(_ bookID: String) {
        guard bookIDs.contains(bookID) else { return }
        update()
        let library = ImportedLibrary.shared
        if bookIDs.allSatisfy({ library.progress[$0] == nil && !BookImporter.shared.isPreparing($0) }) {
            complete(success: true)
        }
    }

    private func complete(success: Bool) {
        if let task {
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.setTaskCompleted(success: success)
        }
        task = nil
        submitted = false
        bookIDs = []
    }
}
