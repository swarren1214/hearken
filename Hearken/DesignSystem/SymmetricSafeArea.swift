import SwiftUI

extension View {
    /// Centers content on the whole screen while keeping it clear of the safe area on both
    /// sides, using the larger of the leading and trailing insets for each.
    ///
    /// Most screens have equal side insets (none in portrait, matching ones in landscape), so
    /// this changes nothing there. iPhone Duo puts the status bar and camera in a column on one
    /// side, so its leading and trailing insets differ; content centered in the safe area would
    /// sit off the screen's center. Use it for centered, standalone screens (sign-in, welcome),
    /// not for lists and readers that should use all the safe width.
    func symmetricSafeArea() -> some View {
        modifier(SymmetricSafeArea())
    }
}

private struct SymmetricSafeArea: ViewModifier {
    @State private var insets = EdgeInsets()

    func body(content: Content) -> some View {
        let side = max(insets.leading, insets.trailing)
        content
            .padding(.horizontal, side)
            .ignoresSafeArea(.container, edges: .horizontal)
            .background {
                // Ignores the safe area, so its geometry reports the full insets.
                Color.clear
                    .ignoresSafeArea()
                    .onGeometryChange(for: EdgeInsets.self) { $0.safeAreaInsets } action: { insets = $0 }
            }
    }
}
