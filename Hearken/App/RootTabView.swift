import SwiftUI

enum AppTab: Hashable {
    case today, play, scriptures, search
}

/// The Liquid Glass tab bar: Today, Play (subjects and games together), Library, and the
/// system search tab. Icon-only.
struct RootTabView: View {
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.today) {
                NavigationStack { TodayView() }
            } label: {
                Image(systemName: "house.fill").accessibilityLabel("Today")
            }

            Tab(value: AppTab.play) {
                NavigationStack { PlayView() }
            } label: {
                Image(systemName: "play.fill").accessibilityLabel("Play")
            }

            Tab(value: AppTab.scriptures) {
                NavigationStack { LibraryView() }
            } label: {
                Image(systemName: "book.fill").accessibilityLabel("Library")
            }

            Tab(value: AppTab.search, role: .search) {
                SearchTab()
            } label: {
                Image(systemName: "magnifyingglass").accessibilityLabel("Search")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}
