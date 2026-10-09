import SwiftUI

extension Color {
    /// The selected segment in the Highlight / Underline switch: white in Light Mode, a lighter
    /// gray in Dark Mode so it stands out from the track.
    static let segmentSelected = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white
    })
}

extension View {
    /// Liquid Glass with extra frost, for bars that sit over scripture text: the glass is tinted
    /// toward the background so the text behind it doesn't compete with the controls.
    func frostedGlass<S: Shape>(in shape: S) -> some View {
        glassEffect(.regular.tint(Color(.systemBackground).opacity(0.6)).interactive(), in: shape)
    }

    func frostedGlass() -> some View {
        frostedGlass(in: Capsule())
    }
}

/// The Apple Pencil palette at the bottom of the reader (iPad): Highlight / Underline,
/// the legend colors, the eraser, and Done (turns Pencil mode off).
struct PencilPalette: View {
    let entries: [HighlightLegend.Entry]
    let name: (HighlightHue) -> String
    @Binding var hue: HighlightHue
    @Binding var style: HighlightStyle
    @Binding var erasing: Bool
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                styleButton(.fill)
                styleButton(.underline)
            }
            .padding(3)
            .background(.quaternary, in: Capsule())
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Style")

            Divider().frame(height: 28)

            HStack(spacing: 10) {
                ForEach(entries) { entry in
                    let selected = entry.hue == hue && !erasing
                    Button {
                        hue = entry.hue
                        erasing = false
                    } label: {
                        Circle()
                            .fill(entry.hue.color)
                            .frame(width: selected ? 32 : 28, height: selected ? 32 : 28)
                            .overlay {
                                if selected {
                                    Circle().strokeBorder(Color(.systemBackground), lineWidth: 3)
                                }
                            }
                            .background {
                                if selected {
                                    Circle().stroke(entry.hue.color, lineWidth: 2).padding(-2)
                                }
                            }
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name(entry.hue))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .animation(.snappy(duration: 0.2), value: hue)

            Divider().frame(height: 28)

            Button {
                erasing.toggle()
            } label: {
                Image(systemName: erasing ? "eraser.fill" : "eraser")
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(erasing ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Eraser")
            .accessibilityHint("Draw over a highlight to remove it.")
            .accessibilityAddTraits(erasing ? .isSelected : [])

            Button("Done", action: onDone)
                .buttonStyle(.glassProminent)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frostedGlass()
        .shadow(color: .black.opacity(0.1), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pencil highlighter")
    }

    private func styleButton(_ option: HighlightStyle) -> some View {
        let selected = option == style
        return Button {
            style = option
        } label: {
            sample(option)
                .frame(width: 50, height: 34)
                .background(selected ? AnyShapeStyle(Color.segmentSelected) : AnyShapeStyle(.clear), in: Capsule())
                .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sample(_ option: HighlightStyle) -> some View {
        var text = AttributedString("Aa")
        text.applyHighlight(hue, style: option)
        return Text(text).font(.scripture(size: 17))
    }
}

/// Shown for a few seconds after a Pencil stroke: the color's legend name and the reference,
/// with Note, Remove and Undo.
struct PencilStrokePill: View {
    let hue: HighlightHue
    let name: String
    let reference: String
    var onNote: () -> Void
    var onRemove: () -> Void
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(hue.color).frame(width: 12, height: 12)
            Text(name).font(.subheadline.weight(.semibold))
            Text(reference).font(.footnote).foregroundStyle(.secondary)
            Divider().frame(height: 22)
            Button("Note", systemImage: "square.and.pencil", action: onNote)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                .foregroundStyle(.red)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
            Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.body)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
        .frostedGlass()
        .shadow(color: .black.opacity(0.1), radius: 12, y: 5)
        .accessibilityElement(children: .contain)
    }
}

/// iPad's highlight bar for a text selection (finger or Pencil): it takes the Pencil palette's
/// place at the bottom of the reader instead of the iPhone's floating toolbar.
struct IPadSelectionBar: View {
    let reference: String
    let entries: [HighlightLegend.Entry]
    let name: (HighlightHue) -> String
    let selectedHue: HighlightHue?
    let style: HighlightStyle
    var onPick: (HighlightHue) -> Void
    var onStyle: (HighlightStyle) -> Void
    var onNote: () -> Void
    var onCopy: () -> Void
    var onRemove: () -> Void
    var onClose: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedHue.map(name) ?? "Highlight")
                    .font(.subheadline.weight(.semibold))
                Text(reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(minWidth: 96, alignment: .leading)

            HStack(spacing: 2) {
                styleButton(.fill)
                styleButton(.underline)
            }
            .padding(3)
            .background(.quaternary, in: Capsule())

            Divider().frame(height: 28)

            HStack(spacing: 10) {
                ForEach(entries) { entry in
                    let selected = entry.hue == selectedHue
                    Button {
                        onPick(entry.hue)
                    } label: {
                        Circle()
                            .fill(entry.hue.color)
                            .frame(width: selected ? 32 : 28, height: selected ? 32 : 28)
                            .overlay {
                                if selected {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.black.opacity(0.7))
                                }
                            }
                            .frame(width: 36, height: 36)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name(entry.hue))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }

            Divider().frame(height: 28)

            HStack(spacing: 4) {
                iconButton("Note", "square.and.pencil", action: onNote)
                iconButton(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc") {
                    onCopy()
                    copied = true
                }
                iconButton("Remove Highlight", "trash", tint: .red, action: onRemove)
                iconButton("Close", "xmark", action: onClose)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frostedGlass()
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight options for \(reference)")
    }

    private func styleButton(_ option: HighlightStyle) -> some View {
        let selected = option == style
        return Button {
            onStyle(option)
        } label: {
            sample(option)
                .frame(width: 50, height: 34)
                .background(selected ? AnyShapeStyle(Color.segmentSelected) : AnyShapeStyle(.clear), in: Capsule())
                .shadow(color: .black.opacity(selected ? 0.1 : 0), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func sample(_ option: HighlightStyle) -> some View {
        var text = AttributedString("Aa")
        text.applyHighlight(selectedHue ?? .yellow, style: option)
        return Text(text).font(.scripture(size: 17))
    }

    private func iconButton(_ title: String, _ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
