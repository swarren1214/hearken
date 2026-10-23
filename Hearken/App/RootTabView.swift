import SwiftUI

/// A subject pushed onto a tab's stack (after earning a badge, See Your Path).
struct SubjectRoute: Hashable {
    let subjectID: String
}

enum AppTab: Hashable {
    case today, play, scriptures, search
}

/// The Liquid Glass tab bar: Today, Play (subjects and games together), Library, and the
/// system search tab. Icon-only on iPhone; on iPad a top tab bar, with names, that can open
/// into a sidebar pinned to the left.
struct RootTabView: View {
    @State private var selection: AppTab = .today
    @State private var todayPath = NavigationPath()
    @State private var playPath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var navigator = AppNavigator.shared
    @State private var groups = GroupStore.shared
    @State private var importer = BookImporter.shared
    @Environment(ContentService.self) private var content
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// iPad (regular width): names show in the top tab bar and the sidebar.
    private var showsTitles: Bool { sizeClass == .regular }

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.today) {
                NavigationStack(path: $todayPath) {
                    TodayView()
                        .screenshotDestinations()
                        .navigationDestination(for: ReaderRoute.self) { route in
                            ReaderView(chapterID: route.chapterID)
                        }
                        .navigationDestination(for: GroupRoute.self) { route in
                            GroupDetailView(groupID: route.id)
                        }
                        .navigationDestination(for: ThreadRoute.self) { route in
                            GroupThreadView(route: route)
                        }
                        .navigationDestination(for: SubjectRoute.self) { route in
                            if let subject = content.subject(route.subjectID) { SubjectDetailView(subject: subject) }
                        }
                        .scholarDestinations()
                }
            } label: {
                TabIcon("Today", systemImage: "house.fill", showsTitle: showsTitles)
            }

            Tab(value: AppTab.play) {
                NavigationStack(path: $playPath) {
                    PlayView()
                        .screenshotDestinations()
                        .navigationDestination(for: SubjectRoute.self) { route in
                            if let subject = content.subject(route.subjectID) { SubjectDetailView(subject: subject) }
                        }
                        .scholarDestinations()
                }
            } label: {
                TabIcon("Play", systemImage: "gamecontroller.fill", showsTitle: showsTitles)
            }

            Tab(value: AppTab.scriptures) {
                NavigationStack(path: $libraryPath) { LibraryView().screenshotDestinations() }
            } label: {
                TabIcon("Library", systemImage: "books.vertical.fill", showsTitle: showsTitles)
            }

            Tab(value: AppTab.search, role: .search) {
                SearchTab()
            } label: {
                TabIcon("Search", systemImage: "magnifyingglass", showsTitle: showsTitles)
            }
        }
        // iPad: a top tab bar that opens into a sidebar on the left. iPhone: the usual bottom tab bar.
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        // Profile, opened by the photo at the top right of every main screen.
        .hearthProfile { SettingsView() }
        // Debug: marketing screenshots (scripts/screenshots.sh). Does nothing otherwise.
        .screenshotStage(selection: $selection, todayPath: $todayPath, playPath: $playPath, libraryPath: $libraryPath)
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
        // Household invitations (HearthInviteLink) open the join sheet.
        .onOpenURL { url in
            if HearthInviteLink.open(url) { return }
            navigator.handle(url)
        }
        .onChange(of: navigator.pendingChapterID, initial: true) { _, chapterID in
            guard let chapterID else { return }
            selection = .today
            todayPath = NavigationPath()
            todayPath.append(ReaderRoute(chapterID: chapterID))
            navigator.pendingChapterID = nil
        }
        // A study-group invite link: show who's inviting and what's shared before joining.
        .sheet(isPresented: Binding(get: { groups.pendingInviteCode != nil }, set: { if !$0 { groups.pendingInviteCode = nil } })) {
            if let code = groups.pendingInviteCode {
                JoinGroupSheet(code: code)
            }
        }
        .onChange(of: groups.openGroupID, initial: true) { _, id in
            guard let id else { return }
            selection = .today
            todayPath = NavigationPath()
            todayPath.append(GroupRoute(id: id))
            // A reply notification opens its thread on top of the group.
            if let thread = groups.openThread, thread.groupID == id { todayPath.append(thread) }
            groups.openThread = nil
            groups.openGroupID = nil
        }
        // The tour (HearthTour.swift): the Welcome sheet, then each step shows its tab at its
        // top level. It starts after sign-in on a new install (HearkenApp), not here.
        .hearthTour(app: .hearken, steps: HearkenTour.steps, finishTitle: "Start Reading", doneKey: SettingsKey.tourDone, autoStart: false) { step in
            let tab = HearkenTour.tab(for: step)
            selection = tab
            switch tab {
            case .today: todayPath = NavigationPath()
            case .play: playPath = NavigationPath()
            default: break
            }
        }
        // Importing books: every way in (Files, Share sheet, drag and drop) lands on one sheet.
        .sheet(item: Binding(get: { importer.batch }, set: { value in
            if value == nil, let batch = importer.batch { importer.cancel(batch) }
        })) { batch in
            AddToLibrarySheet(batchID: batch.id)
        }
        .onChange(of: importer.addedToken) {
            selection = .scriptures
        }
        // Importing books needs Hearken Plus or Hearth+.
        .hearthPaywall(isPresented: $importer.paywallRequested, feature: HearthPaywallFeature(
            "Your own books",
            detail: "Bring EPUBs and PDFs into your Library and read them with highlights, notes and Listen.",
            symbol: "books.vertical.fill"
        ))
        // A "book is ready" notification: open the book.
        .onChange(of: navigator.pendingBookID, initial: true) { _, bookID in
            guard let bookID else { return }
            selection = .scriptures
            libraryPath = NavigationPath()
            libraryPath.append(ImportedBookRoute(bookID: bookID))
            navigator.pendingBookID = nil
        }
        // Above any open sheet, not waiting behind it (HearthProfile.swift).
        .hearthNotice(
            "Couldn't Import",
            isPresented: Binding(get: { importer.failureMessage != nil }, set: { if !$0 { importer.failureMessage = nil } }),
            message: importer.failureMessage
        )
        .overlay {
            if importer.isReading {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Copying the file…")
                        .font(.subheadline.weight(.medium))
                }
                .padding(24)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.snappy, value: importer.isReading)
    }
}

/// A tab's label: just its symbol on iPhone (the title is still read by VoiceOver), and the
/// symbol with its name on iPad.
private struct TabIcon: View {
    var title: String
    var systemImage: String
    var showsTitle: Bool

    init(_ title: String, systemImage: String, showsTitle: Bool) {
        self.title = title
        self.systemImage = systemImage
        self.showsTitle = showsTitle
    }

    var body: some View {
        if showsTitle {
            // The sidebar tints tab icons with the app's color; keep each icon the color of its
            // name instead (black in Light Mode, white in Dark Mode). See AGENT.md.
            Label { Text(title) } icon: { Image.menuIcon(systemImage) }
        } else {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
    }
}
