import SwiftUI

/// Settings › Highlight Colors: the user's own color legend.
struct HighlightColorsView: View {
    @Environment(HighlightLegend.self) private var legend

    var body: some View {
        List {
            Section("Preview") {
                preview
            }

            Section {
                ForEach(legend.entries) { entry in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(entry.hue.color)
                            .frame(width: 28, height: 28)
                            .accessibilityHidden(true)
                        TextField("Name this color", text: nameBinding(for: entry.hue))
                            .accessibilityLabel("\(entry.hue.colorName) highlight name")
                    }
                }
                .onMove { legend.move(from: $0, to: $1) }
                .onDelete { legend.remove(at: $0) }

                if legend.canAdd {
                    Button("Add Color", systemImage: "plus.circle.fill") { legend.addNextColor() }
                }
            } header: {
                Text("Your Legend")
            } footer: {
                Text("Give each color a meaning. The name shows in the highlight toolbar and lets you filter your notes by color. Up to \(HighlightLegend.maxColors) colors.")
            }

            Section {
                Picker("New Highlights", selection: Binding(get: { legend.defaultStyle }, set: { legend.setDefaultStyle($0) })) {
                    ForEach(HighlightStyle.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Show Names in Toolbar", isOn: Binding(get: { legend.showNames }, set: { legend.setShowNames($0) }))
            } header: {
                Text("Defaults")
            } footer: {
                Text("Your legend syncs to your other devices with iCloud.")
            }
        }
        .navigationTitle("Highlight Colors")
        .toolbar { EditButton() }
    }

    private func nameBinding(for hue: HighlightHue) -> Binding<String> {
        Binding(
            get: { legend.entries.first { $0.hue == hue }?.name ?? "" },
            set: { legend.rename(hue, to: $0) }
        )
    }

    private var preview: some View {
        let hue = legend.entries.first?.hue ?? .yellow
        var verse = AttributedString("faith is not to have a perfect knowledge of things")
        verse.applyHighlight(hue, style: legend.defaultStyle)
        let before = Text("And now as I said concerning faith—")
        let after = Text("; therefore if ye have faith ye hope for things which are not seen, which are true.")
        return VStack(alignment: .leading, spacing: 6) {
            Text("Alma 32:21").font(.footnote).foregroundStyle(.secondary)
            Text("\(before)\(Text(verse))\(after)")
                .font(.scripture(size: 18))
                .lineSpacing(5)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { HighlightColorsView() }
        .previewEnvironment()
}
