import SwiftUI

/// Hearken's stops on the shared tour (HearthTour.swift): Today, Play, Library and Search. It runs
/// once after sign-in on a new install and again from Profile › Take the Tour. Screens mark what
/// each step points at with `.hearthTourTarget(_:)`.
enum HearkenTour {
    static let today = "today"
    static let play = "play"
    static let library = "library"
    static let search = "search"

    static let steps: [HearthTourStep] = [
        HearthTourStep(today, title: "Today", message: "Your reading plan, daily challenge and streak live here. Continue Reading opens right where you left off.", symbol: "house.fill", color: .blue),
        HearthTourStep(play, title: "Play", message: "Subjects and games. Learn a little at a time, and earn ranks and medals as you master each subject.", symbol: "gamecontroller.fill", color: .green),
        HearthTourStep(library, title: "Library", message: "Every volume of scripture. Open any chapter to read, mark it up, or listen. Your notebook and reading plans are up top.", symbol: "books.vertical.fill", color: .purple),
        HearthTourStep(search, title: "Search", message: "Find any verse, word or name, or jump straight to a reference like Alma 32:21.", symbol: "magnifyingglass", color: .orange),
    ]

    static func tab(for step: HearthTourStep) -> AppTab {
        switch step.id {
        case play: .play
        case library: .scriptures
        case search: .search
        default: .today
        }
    }
}
