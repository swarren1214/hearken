import SwiftUI

/// Hearken on Apple Watch: today's reading and a remote for Listen on the iPhone.
/// Review questions don't need this app: they arrive as iPhone notifications with answer buttons.
@main
struct HearkenWatchApp: App {
    init() {
        WatchStore.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRoot()
                .environment(WatchStore.shared)
        }
    }
}

/// Two pages, Digital Crown to move between them. Opens on the remote while something's playing.
struct WatchRoot: View {
    enum Page: Hashable { case today, listen }

    @Environment(WatchStore.self) private var store
    @State private var page: Page = WatchStore.shared.listen.active ? .listen : .today

    var body: some View {
        TabView(selection: $page) {
            TodayPage { page = .listen }
                .tag(Page.today)
            ListenRemote()
                .tag(Page.listen)
        }
        .tabViewStyle(.verticalPage)
    }
}
