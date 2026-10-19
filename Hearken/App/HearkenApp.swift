import SwiftData
import SwiftUI
import TipKit
import UIKit
import UserNotifications

@main
struct HearkenApp: App {
    /// Study-group invites (CloudKit share links) and their silent pushes.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var content = ContentService()
    @State private var account = AccountService()
    @State private var legend = HighlightLegend()
    @State private var sync = SyncService()
    // Screenshot mode (Debug only) runs on an in-memory store of demo content.
    private let container = Persistence.makeContainer(inMemory: ScreenshotMode.isOn)

    init() {
        ScreenshotMode.prepareLaunch()
        // Text size, reader layout and other settings follow the user through iCloud.
        SettingsSync.shared.start()
        // Alerts and confirmation dialogs use the system label color (black in Light Mode,
        // white in Dark Mode) rather than the app's accent. Destructive buttons stay red.
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .label
        // Plan reminders: show while open, and open the chapter when tapped.
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        // Listen mode marks chapters read when heard to the end, even when Siri started it in the background.
        ListenEngine.shared.attach(container: container)
        // Review questions can be answered from a notification while Hearken is in the background.
        ReviewNotifications.attach(container: container)
        // The Apple Watch app: plan snapshot and Listen state out, Listen commands in.
        WatchBridge.shared.activate(container: container)
        // Imported books: served to the reader, and any left half-prepared carry on.
        ImportedLibrary.shared.attach(container: container)
        BookImporter.shared.attach(container: container)
        BookImporter.shared.resumeUnfinished()
        // The reader's one-time tips.
        ReaderTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(content)
                .environment(account)
                .environment(legend)
                .environment(sync)
                // Decode scripture in the background, so search and long plans never stall.
                .task { await content.preloadVolumes() }
        }
        .modelContainer(container)
    }
}

/// Applies the tint and appearance, gates first launch on sign-in, and re-checks the account.
struct AppRoot: View {
    @Environment(AccountService.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false

    var body: some View {
        RootTabView()
            .tint(Accent.color)
            .fullScreenCover(isPresented: showOnboarding) {
                SignInView {
                    onboardingDone = true
                    // A new install: show them around once the sign-in screen is gone.
                    TourController.shared.startAfterSignIn()
                }
                .tint(Accent.color)
            }
            .task {
                await account.refresh()
                #if DEBUG
                // Ready the study-group record types in the CloudKit development database.
                if AppConfig.cloudSyncEnabled { await GroupStore.shared.initializeSchemaIfNeeded() }
                #endif
            }
            // The Hearth household: invitations land here, and the reader is one of its people.
            .hearthHouseholdInvitations()
            // Every Hearth app works inside a household; after onboarding, the household step
            // if there's none yet.
            .hearthHouseholdRequired(isActive: onboardingDone && !ScreenshotMode.isOn, accent: Accent.color)
            .task {
                guard !ScreenshotMode.isOn else { return }
                HearthHouseholdStore.shared.start(app: .hearken)
                HearthLink.shared.claimReaderIfNeeded()
            }
            .onChange(of: HearthHouseholdStore.shared.snapshot) { _, _ in
                HearthLink.shared.claimReaderIfNeeded()
            }
            .modifier(PlanSideEffects())
            .modifier(ReviewSideEffects())
            .modifier(GroupSideEffects())
            .modifier(ListenSideEffects())
            .onChange(of: appearance, initial: true) { _, option in
                applyAppearance(option)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    applyAppearance(appearance)
                    Task { await account.refresh() }
                    // Untitled parts of imported books get titles while the app is open.
                    BookRefiner.shared.refineAll()
                }
            }
    }

    /// Sets the style on every window, so sheets and full-screen covers follow it too.
    /// (preferredColorScheme only reaches the presentation it's applied in.)
    private func applyAppearance(_ option: AppearanceOption) {
        let style: UIUserInterfaceStyle = switch option {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    private var showOnboarding: Binding<Bool> {
        Binding(get: { !onboardingDone }, set: { onboardingDone = !$0 })
    }
}
