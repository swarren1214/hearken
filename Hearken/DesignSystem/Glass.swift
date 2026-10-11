import SwiftUI

extension Color {
    /// The selected segment in the Highlight / Underline switch: white in Light Mode, a lighter
    /// gray in Dark Mode so it stands out from the track.
    static let segmentSelected = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
}

extension View {
    /// Liquid Glass with real frost, for bars that sit over scripture text: a thick blur under
    /// the glass keeps the text behind it from showing through and competing with the controls.
    func frostedGlass<S: Shape>(in shape: S) -> some View {
        background(.thickMaterial, in: shape)
            .glassEffect(.regular.tint(Color(.systemBackground).opacity(0.35)).interactive(), in: shape)
    }

    func frostedGlass() -> some View {
        frostedGlass(in: Capsule())
    }

    /// The floating bar look: frosted capsule and a soft shadow. Off when a shared bar draws it.
    @ViewBuilder
    func barChrome(_ on: Bool) -> some View {
        if on {
            frostedGlass().shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        } else {
            self
        }
    }
}
