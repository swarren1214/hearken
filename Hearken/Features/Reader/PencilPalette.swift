import SwiftUI

/// The Apple Pencil palette at the bottom of the reader (iPad): Highlight / Underline,
/// the legend colors, the eraser, and a checkmark that puts the palette away until the Pencil
/// comes near the text again.
struct PencilPalette: View {
    let entries: [HighlightLegend.Entry]
    let name: (HighlightHue) -> String
    @Binding var hue: HighlightHue
    @Binding var style: HighlightStyle
    @Binding var erasing: Bool
    var onDone: () -> Void
    /// Off when the reader draws one shared glass bar that morphs between this and the
    /// selection bar.
    var showsChrome = true

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

            doneButton("Done", action: onDone)
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .barChrome(showsChrome)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pencil highlighter")
    }

    /// The round checkmark that closes a bar.
    private func doneButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.headline)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(title)
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

/// The iPad highlight menu at the bottom of the reader, for a selection or a tapped highlight:
/// highlight or underline, the legend colors, and Explain, Share, Note, Copy, Remove and Close.
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
    /// Explain with Apple Intelligence; nil hides the button (device can't run it).
    var onExplain: (() -> Void)? = nil
    /// Share the selection with a study group; nil hides the button (no groups).
    var onShareToGroup: (() -> Void)? = nil
    /// Off when the reader draws one shared glass bar (see PencilPalette.showsChrome).
    var showsChrome = true

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
                if let onExplain {
                    iconButton("Explain", "sparkles", action: onExplain)
                }
                if let onShareToGroup {
                    iconButton("Share to Group", "person.2", action: onShareToGroup)
                }
                iconButton("Note", "square.and.pencil", action: onNote)
                iconButton(copied ? "Copied" : "Copy", copied ? "checkmark" : "doc.on.doc") {
                    onCopy()
                    copied = true
                }
                iconButton("Remove Highlight", "trash", tint: .red, action: onRemove)
                doneButton("Done", action: onClose)
                    .padding(.leading, 4)
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .barChrome(showsChrome)
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight options for \(reference)")
    }

    /// The round checkmark that closes a bar.
    private func doneButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.headline)
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(title)
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
