import SwiftData
import SwiftUI
import UIKit

@main
struct HearkenApp: App {
    @State private var content = ContentService()
    @State private var account = AccountService()
    @State private var legend = HighlightLegend()
    @State private var sync = SyncService()
    private let container = Persistence.makeContainer()

    init() {
        // Alerts and confirmation dialogs use the system label color (black in Light Mode,
        // white in Dark Mode) rather than the app's accent. Destructive buttons stay red.
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = .label
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environment(content)
                .environment(account)
                .environment(legend)
                .environment(sync)
        }
        .modelContainer(container)
    }
}

/// Applies the user's accent and appearance, gates first launch on sign-in, and re-checks the account.
struct AppRoot: View {
    @Environment(AccountService.self) private var account
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false

    var body: some View {
        RootTabView()
            .tint(accent.color)
            .fullScreenCover(isPresented: showOnboarding) {
                SignInView { onboardingDone = true }
                    .tint(accent.color)
            }
            .task { await account.refresh() }
            .onChange(of: appearance, initial: true) { _, option in
                applyAppearance(option)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    applyAppearance(appearance)
                    Task { await account.refresh() }
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
