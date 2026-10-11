import SwiftUI

/// A subject pushed onto a tab's stack (after earning a badge, See Your Path).
struct SubjectRoute: Hashable {
    let subjectID: String
}

enum AppTab: Hashable {
    case today, play, scriptures, search
}

/// The Liquid Glass tab bar: Today, Play (subjects and games together), Library, and the
/// system search tab. Icon-only.
struct RootTabView: View {
    @State private var selection: AppTab = .today
    @State private var todayPath = NavigationPath()
    @State private var playPath = NavigationPath()
    @State private var navigator = AppNavigator.shared
    @State private var groups = GroupStore.shared
    @State private var tour = TourController.shared
    @Environment(ContentService.self) private var content

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
                        .navigationDestination(for: SubjectRoute.self) { route in
                            if let subject = content.subject(route.subjectID) { SubjectDetailView(subject: subject) }
                        }
                        .scholarDestinations()
                }
            } label: {
                Image(systemName: "house.fill").accessibilityLabel("Today")
            }

            Tab(value: AppTab.play) {
                NavigationStack(path: $playPath) {
                    PlayView()
                        .navigationDestination(for: SubjectRoute.self) { route in
                            if let subject = content.subject(route.subjectID) { SubjectDetailView(subject: subject) }
                        }
                        .scholarDestinations()
                }
            } label: {
                Image(systemName: "gamecontroller.fill").accessibilityLabel("Play")
            }

            Tab(value: AppTab.scriptures) {
                NavigationStack { LibraryView() }
            } label: {
                Image(systemName: "books.vertical.fill").accessibilityLabel("Library")
            }

            Tab(value: AppTab.search, role: .search) {
                SearchTab()
            } label: {
                Image(systemName: "magnifyingglass").accessibilityLabel("Search")
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Scholar Path: the unlock celebration for each newly earned rank.
        .scholarCelebrations()
        .onChange(of: navigator.pendingSubjectID) { _, subjectID in
            guard let subjectID else { return }
            selection = .play
            playPath = NavigationPath()
            playPath.append(SubjectRoute(subjectID: subjectID))
            navigator.pendingSubjectID = nil
        }
        // Listen mode: the mini player above the tab bar, and the full player sheet.
        .listenPlayer()
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
        // The first-run tour: the Welcome sheet, then each step shows its tab at its top level.
        .sheet(isPresented: $tour.showsWelcome) {
            WelcomeView()
        }
        .onChange(of: tour.step) { _, step in
            guard let step else { return }
            selection = step.tab
            switch step.tab {
            case .today: todayPath = NavigationPath()
            case .play: playPath = NavigationPath()
            default: break
            }
        }
        .overlay { TourOverlay() }
    }
}
