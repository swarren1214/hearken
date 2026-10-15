import SwiftUI

/// A row that becomes a column at accessibility text sizes. Rows of an icon, a title and a
/// button fit side by side at ordinary sizes; at the largest sizes they'd push past the edge
/// of the screen, so their parts stack instead, leading-aligned.
struct AdaptiveStack<Content: View>: View {
    private let alignment: VerticalAlignment
    private let spacing: CGFloat?
    private let content: Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}
