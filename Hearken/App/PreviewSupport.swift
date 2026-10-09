import SwiftData
import SwiftUI

extension View {
    /// Supplies the app's services and an in-memory store to SwiftUI previews.
    func previewEnvironment(signedIn: Bool = false) -> some View {
        modifier(PreviewEnvironment(signedIn: signedIn))
    }
}

private struct PreviewEnvironment: ViewModifier {
    let signedIn: Bool
    @State private var content = ContentService()
    @State private var account = AccountService()
    @State private var legend = HighlightLegend(defaults: UserDefaults(suiteName: "preview") ?? .standard)
    @State private var sync = SyncService(defaults: UserDefaults(suiteName: "preview") ?? .standard)
    @State private var container = Persistence.makeContainer(inMemory: true)

    func body(content view: Content) -> some View {
        view
            .environment(content)
            .environment(account)
            .environment(legend)
            .environment(sync)
            .modelContainer(container)
            .tint(AccentOption.blue.color)
            .onAppear {
                if signedIn { account.markSignedInForPreview() }
            }
    }
}
