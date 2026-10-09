import SwiftUI

enum AppTab: Hashable {
    case today, subjects, play, scriptures, search
}

/// The Liquid Glass tab bar: four icon-only tabs plus the system search tab.
struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.today) {
                NavigationStack { TodayView() }
            } label: {
                Image(systemName: "house.fill").accessibilityLabel("Today")
            }

            Tab(value: AppTab.subjects) {
                NavigationStack { SubjectsView() }
            } label: {
                Image(systemName: "square.grid.2x2.fill").accessibilityLabel("Subjects")
            }

            Tab(value: AppTab.play) {
                NavigationStack { PlayView() }
            } label: {
                Image(systemName: "gamecontroller.fill").accessibilityLabel("Play")
            }

            Tab(value: AppTab.scriptures) {
                NavigationStack { LibraryView() }
            } label: {
                Image(systemName: "book.fill").accessibilityLabel("Scriptures")
            }

            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView() }
            } label: {
                Image(systemName: "magnifyingglass").accessibilityLabel("Search")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
