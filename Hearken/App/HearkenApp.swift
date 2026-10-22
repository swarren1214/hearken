import Combine
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
        // Hearken Plus and Hearth+ (RevenueCat), and the household's plan through the Hearth API.
        Self.configurePurchases()
    }

    /// Reading, study and Explain are always free; Listen, starting or joining study groups,
    /// the games beyond the Daily Challenge, and imported books need Hearken
    /// Plus or Hearth+. Skipped until the RevenueCat key is filled in.
    private static func configurePurchases() {
        let purchases = HearthPurchases.shared
        if ScreenshotMode.isOn { purchases.previewUnlocked = true }
        guard AppConfig.revenueCatAPIKey != "REVENUECAT_PUBLIC_KEY" else { return }
        purchases.configure(
            app: .hearken,
            apiKey: AppConfig.revenueCatAPIKey,
            apiBaseURL: AppConfig.apiBaseURL,
            accessToken: {
                let api = HearthAPI.shared
                guard await api.isConnected else { return nil }
                return try? await api.accessToken()
            },
            signInButton: { AnyView(HearthSignInButton()) }
        )
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                // The Hearth launch splash.
                .hearthSplash(.hearken, isEnabled: !ScreenshotMode.isOn)
                .environment(content)
                .environment(account)
                .environment(legend)
                .environment(sync)
                // Decode scripture in the background, so search and long plans never stall.
                .task { await content.preloadVolumes() }
                // iPhone Duo: reads the pose (outer display, open, Book, Laptop) for the whole
                // window and passes it down as `\.hearthDuoPose` (HearthDuo.swift).
                .hearthDuoPose()
        }
        .modelContainer(container)
    }
}

/// Applies the tint, gates first launch on sign-in, and re-checks the account.
struct AppRoot: View {
    @Environment(AccountService.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false
    /// A new install asks iCloud first whether this person already onboarded on another device,
    /// so their iPad doesn't make them do it again.
    @State private var cloudChecked = UserDefaults.standard.bool(forKey: SettingsKey.onboardingDone) || ScreenshotMode.isOn

    var body: some View {
        RootTabView()
            .tint(Accent.color)
            .fullScreenCover(isPresented: showOnboarding) {
                // First run (Features/Onboarding/OnboardingView.swift): it ends by starting the
                // tour or opening the reader, so nothing starts the tour here.
                OnboardingView {
                    onboardingDone = true
                }
                .interactiveDismissDisabled()
            }
            .task {
                if onboardingDone {
                    // Also for people who onboarded before iCloud remembered it.
                    if !ScreenshotMode.isOn { HearthOnboarding.rememberInCloud(.hearken) }
                } else if await HearthOnboarding.waitForOtherDevices(.hearken, timeout: .seconds(3)) {
                    skipOnboarding()
                }
                cloudChecked = true
            }
            // Finished on another device while onboarding is showing here.
            .onReceive(NotificationCenter.default.publisher(for: NSUbiquitousKeyValueStore.didChangeExternallyNotification).receive(on: RunLoop.main)) { _ in
                if !onboardingDone, !ScreenshotMode.isOn, HearthOnboarding.isDoneOnAnotherDevice(.hearken) { skipOnboarding() }
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
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task { await account.refresh() }
                    // Untitled parts of imported books get titles while the app is open.
                    BookRefiner.shared.refineAll()
                }
            }
    }

    /// Onboarding's done for this person on another device: none of it here.
    private func skipOnboarding() {
        HearthOnboarding.finishWithoutSteps(.hearken)
        onboardingDone = true
    }

    private var showOnboarding: Binding<Bool> {
        Binding(get: { cloudChecked && !onboardingDone }, set: { onboardingDone = !$0 })
    }
}
