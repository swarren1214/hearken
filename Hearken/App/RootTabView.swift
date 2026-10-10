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
    @State private var groups = GroupStore.shared

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayView()
                        .navigationDestination(for: ReaderRoute.self) { route in
                            ReaderView(chapterID: route.chapterID)
                        }
                        .navigationDestination(for: GroupRoute.self) { route in
                            GroupDetailView(groupID: route.id)
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
        // A study-group invite link: show who's inviting and what's shared before joining.
        .sheet(isPresented: Binding(get: { groups.pendingInvite != nil }, set: { if !$0 { groups.pendingInvite = nil } })) {
            if let metadata = groups.pendingInvite {
                JoinGroupSheet(metadata: metadata)
            }
        }
        .onChange(of: groups.openGroupID) { _, id in
            guard let id else { return }
            selection = .today
            todayPath = NavigationPath()
            todayPath.append(GroupRoute(id: id))
            groups.openGroupID = nil
        }
    }
}
