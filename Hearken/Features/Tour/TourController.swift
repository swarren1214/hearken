import Observation
import SwiftUI

/// The first-run guided tour: a Welcome screen, then four steps that each switch to a tab and
/// point at one thing on it. Runs once after sign-in (only on a new install) and again from
/// Settings › Help. RootTabView shows the Welcome sheet and the overlay; screens mark what
/// each step points at with `.tourTarget(_:)`.
@MainActor
@Observable
final class TourController {
    static let shared = TourController()

    enum Step: Int, CaseIterable, Identifiable {
        case today, play, library, search

        var id: Int { rawValue }
        var tab: AppTab {
            switch self {
            case .today: .today
            case .play: .play
            case .library: .scriptures
            case .search: .search
            }
        }
        var title: String {
            switch self {
            case .today: "Today"
            case .play: "Play"
            case .library: "Library"
            case .search: "Search"
            }
        }
        var message: String {
            switch self {
            case .today:
                "Your reading plan, daily challenge and streak live here. Continue Reading opens right where you left off."
            case .play:
                "Subjects and games. Learn a little at a time, and earn ranks and medals as you master each subject."
            case .library:
                "Every volume of scripture. Open any chapter to read, mark it up, or listen. Your notebook and reading plans are up top."
            case .search:
                "Find any verse, word or name, or jump straight to a reference like Alma 32:21."
            }
        }
        /// The tab's own icon, so the card names the icon-only tab bar.
        var symbol: String {
            switch self {
            case .today: "house.fill"
            case .play: "gamecontroller.fill"
            case .library: "books.vertical.fill"
            case .search: "magnifyingglass"
            }
        }
        var color: Color {
            switch self {
            case .today: .blue
            case .play: .green
            case .library: .purple
            case .search: .orange
            }
        }
        var isLast: Bool { self == Step.allCases.last }
    }

    /// The step on screen, or nil when the tour isn't running.
    private(set) var step: Step?
    /// The Welcome sheet is up.
    var showsWelcome = false
    /// Where the current step's target is, in global (window) coordinates. Nil when the screen
    /// doesn't have one, or it isn't on screen yet.
    private(set) var targetFrame: CGRect?
    /// Set when the tour ends with Start Reading; Today opens the reader and clears it.
    var startReadingRequested = false

    /// Every target's latest frame. Not observed: it changes on every scroll, and only the
    /// current step's frame (`targetFrame`) should redraw anything.
    @ObservationIgnored private var frames: [Step: CGRect] = [:]

    var isActive: Bool { step != nil || showsWelcome }

    /// After sign-in on a new install. Waits for the sign-in screen to finish going away.
    func startAfterSignIn() {
        guard !UserDefaults.standard.bool(forKey: SettingsKey.tourDone) else { return }
        start(skippingWelcome: false, after: .milliseconds(450))
    }

    /// Settings › Take the Tour Again skips the Welcome and waits for the sheet to close.
    func start(skippingWelcome: Bool, after delay: Duration = .zero) {
        Task {
            if delay > .zero { try? await Task.sleep(for: delay) }
            if skippingWelcome {
                begin()
            } else {
                showsWelcome = true
            }
        }
    }

    /// Show Me Around.
    func begin() {
        showsWelcome = false
        go(to: .today)
    }

    func next() {
        guard let step else { return }
        if let following = Step(rawValue: step.rawValue + 1) {
            go(to: following)
        } else {
            finish(startReading: true)
        }
    }

    func skip() {
        finish(startReading: false)
    }

    func finish(startReading: Bool) {
        step = nil
        showsWelcome = false
        targetFrame = nil
        UserDefaults.standard.set(true, forKey: SettingsKey.tourDone)
        if startReading { startReadingRequested = true }
    }

    private func go(to next: Step) {
        step = next
        targetFrame = frames[next]
    }

    // MARK: Targets

    func report(_ frame: CGRect, for target: Step) {
        frames[target] = frame
        if step == target, targetFrame != frame { targetFrame = frame }
    }

    func forget(_ target: Step) {
        frames[target] = nil
        if step == target { targetFrame = nil }
    }
}

extension View {
    /// Marks the view a tour step points at. Reports its frame on screen as it moves (scrolling,
    /// rotation, resizing), which works across the tab and navigation containers.
    /// `isEnabled` picks one view out of a list (the first shelf, say).
    func tourTarget(_ step: TourController.Step, isEnabled: Bool = true) -> some View {
        modifier(TourTargetModifier(step: step, isEnabled: isEnabled))
    }
}

private struct TourTargetModifier: ViewModifier {
    let step: TourController.Step
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    TourController.shared.report(frame, for: step)
                }
                .onDisappear { TourController.shared.forget(step) }
        } else {
            content
        }
    }
}
