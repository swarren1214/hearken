import SwiftUI

enum AppTab: Hashable {
    case today, play, scriptures, search
}

/// The Liquid Glass tab bar: Today, Play (subjects and games together), Library, and the
/// system search tab. Icon-only.
struct RootTabView: View {
    @State private var selection: AppTab = .today
    @State private var todayPath = NavigationPath()
    @State private var navigator = AppNavigator.shared

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayView()
                        .navigationDestination(for: ReaderRoute.self) { route in
                            ReaderView(chapterID: route.chapterID)
                        }
                }
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
        // Widgets (hearken://read/<chapter>), plan reminders, Siri and Shortcuts open a chapter here.
        .onOpenURL { navigator.handle($0) }
        .onChange(of: navigator.pendingChapterID, initial: true) { _, chapterID in
            guard let chapterID else { return }
            selection = .today
            todayPath = NavigationPath()
            todayPath.append(ReaderRoute(chapterID: chapterID))
            navigator.pendingChapterID = nil
        }
    }
}
