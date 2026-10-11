import SwiftUI

/// The iPhone highlight bar: one floating Liquid Glass capsule at the bottom of the reader, like
/// the iPad bar folded to phone width. Highlight or underline, the legend colors (scroll for
/// more), a ··· menu with Add Note, Explain, Share to Group, Copy and Remove, and a checkmark
/// to finish.
struct HighlightToolbar: View {
    let reference: String
    let entries: [HighlightLegend.Entry]
    let name: (HighlightHue) -> String
    let showNames: Bool
    let selectedHue: HighlightHue?
    let style: HighlightStyle
    var onPick: (HighlightHue) -> Void
    var onStyle: (HighlightStyle) -> Void
    var onNote: () -> Void
    var onCopy: () -> Void
    var onRemove: () -> Void
    var onClose: () -> Void
    /// Explain with Apple Intelligence; nil hides the item (device can't run it).
    var onExplain: (() -> Void)? = nil
    /// Share the selection with a study group; nil hides the item (no groups).
    var onShareToGroup: (() -> Void)? = nil

    @State private var copied = false

    private var tint: Color { selectedHue?.color ?? .secondary }

    var body: some View {
        HStack(spacing: 6) {
            styleSwitch
            swatches
            actionsMenu
            doneButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frostedGlass()
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight options for \(reference)")
    }

    // MARK: Pieces

    private var styleSwitch: some View {
        HStack(spacing: 2) {
            styleButton(.fill)
            styleButton(.underline)
        }
        .padding(3)
        .background(.quaternary.opacity(0.6), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Style")
    }

    /// The legend colors. Those that don't fit scroll, fading out at the trailing edge.
    private var swatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(entries) { entry in
                    swatch(entry)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }

    private func swatch(_ entry: HighlightLegend.Entry) -> some View {
        let isSelected = entry.hue == selectedHue
        return Button {
            onPick(entry.hue)
        } label: {
            Circle()
                .fill(entry.hue.color)
                .frame(width: 28, height: 28)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black.opacity(0.7))
                    }
                }
                .padding(3)
                .overlay {
                    if isSelected {
                        Circle().strokeBorder(entry.hue.color, lineWidth: 2.5)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showNames ? name(entry.hue) : entry.hue.colorName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var actionsMenu: some View {
        Menu {
            Button("Add Note", systemImage: "square.and.pencil", action: onNote)
            if let onExplain {
                Button("Explain", systemImage: "sparkles", action: onExplain)
            }
            if let onShareToGroup {
                Button("Share to Group", systemImage: "person.2", action: onShareToGroup)
            }
            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                onCopy()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            Divider()
            Button("Remove Highlight", systemImage: "trash", role: .destructive, action: onRemove)
                .disabled(selectedHue == nil)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .background(.quaternary.opacity(0.6), in: Circle())
                .contentShape(Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("More actions")
    }

    private var doneButton: some View {
        Button(action: onClose) {
            Image(systemName: "checkmark")
                .font(.headline)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Done")
    }

    private func styleButton(_ option: HighlightStyle) -> some View {
        let isSelected = option == style
        return Button {
            onStyle(option)
        } label: {
            sample(option)
                .frame(width: 38, height: 30)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.segmentSelected)
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func sample(_ option: HighlightStyle) -> some View {
        switch option {
        case .fill:
            Text("Aa")
                .font(.scripture(size: 15))
                .padding(.horizontal, 3)
                .background(tint.opacity(0.38), in: .rect(cornerRadius: 3))
        case .underline:
            Text("Aa")
                .font(.scripture(size: 15))
                .underline(true, color: tint)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        HighlightToolbar(
            reference: "Alma 32:28",
            entries: HighlightLegend.defaultEntries,
            name: { hue in HighlightLegend.defaultEntries.first { $0.hue == hue }?.name ?? hue.colorName },
            showNames: true,
            selectedHue: .blue,
            style: .underline,
            onPick: { _ in }, onStyle: { _ in }, onNote: {}, onCopy: {}, onRemove: {}, onClose: {}
        )
    }
}
