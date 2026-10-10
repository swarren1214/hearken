import SwiftUI

/// The floating Liquid Glass toolbar shown when a verse or highlight is tapped:
/// the color's legend name, the legend colors, a Highlight / Underline switch,
/// and Note, Copy and Remove.
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
    /// Explain with Apple Intelligence; nil hides the button (device can't run it).
    var onExplain: (() -> Void)? = nil

    @State private var copied = false

    private var tint: Color { selectedHue?.color ?? .secondary }

    var body: some View {
        VStack(spacing: 12) {
            headerRow
            swatchRow
            actionRow
        }
        .padding(14)
        // Regular (frosted) glass keeps the text behind it from competing with the controls;
        // interactive makes it respond to touch. A soft shadow lifts it off the page.
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 12, height: 12)
            Text(selectedHue.map(name) ?? "Choose a color")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("· \(reference)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Close", systemImage: "xmark", action: onClose)
                .labelStyle(.iconOnly)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: Circle())
                .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
    }

    private var swatchRow: some View {
        HStack(spacing: 0) {
            ForEach(entries) { entry in
                let isSelected = entry.hue == selectedHue
                Button {
                    onPick(entry.hue)
                } label: {
                    Circle()
                        .fill(entry.hue.color)
                        .frame(width: 38, height: 38)
                        .overlay {
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.black.opacity(0.7))
                            }
                        }
                        .padding(3)
                        .overlay {
                            if isSelected {
                                Circle().strokeBorder(entry.hue.color, lineWidth: 2.5)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showNames ? name(entry.hue) : entry.hue.colorName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                styleButton(.fill)
                styleButton(.underline)
            }
            .padding(3)
            .background(.quaternary.opacity(0.6), in: Capsule())
            .padding(.trailing, 4)

            if let onExplain {
                iconButton("sparkles", label: "Explain", action: onExplain)
            }
            iconButton("square.and.pencil", label: "Add note", action: onNote)
            iconButton(copied ? "checkmark" : "doc.on.doc", label: "Copy verse") {
                onCopy()
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .sensoryFeedback(.success, trigger: copied)
            iconButton("trash", label: "Remove highlight", role: .destructive, action: onRemove)
                .disabled(selectedHue == nil)
        }
    }

    private func styleButton(_ option: HighlightStyle) -> some View {
        let isSelected = option == style
        return Button {
            onStyle(option)
        } label: {
            sample(option)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color(.systemBackground))
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
                .font(.scripture(size: 16))
                .padding(.horizontal, 3)
                .background(tint.opacity(0.38), in: .rect(cornerRadius: 3))
        case .underline:
            Text("Aa")
                .font(.scripture(size: 16))
                .underline(true, color: tint)
        }
    }

    private func iconButton(_ symbol: String, label: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        .accessibilityLabel(label)
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
