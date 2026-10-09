import Foundation
import Observation

/// The user's highlight color legend: which colors they use, what each one means,
/// and the default style for new highlights.
///
/// Stored as JSON in UserDefaults and mirrored to iCloud key-value storage
/// (NSUbiquitousKeyValueStore), so it follows the user to their other devices.
@Observable
final class HighlightLegend {
    struct Entry: Codable, Identifiable, Hashable {
        var hue: HighlightHue
        var name: String
        var id: HighlightHue { hue }
    }

    private struct Snapshot: Codable {
        var entries: [Entry]
        var defaultStyle: HighlightStyle
        var showNames: Bool
    }

    static let maxColors = 8
    static let defaultEntries: [Entry] = [
        Entry(hue: .yellow, name: "Promises"),
        Entry(hue: .blue, name: "Jesus Christ"),
        Entry(hue: .green, name: "Commandments"),
        Entry(hue: .pink, name: "Covenants"),
        Entry(hue: .purple, name: "Questions"),
        Entry(hue: .orange, name: "Prophecy"),
    ]

    private(set) var entries: [Entry] = HighlightLegend.defaultEntries
    private(set) var defaultStyle: HighlightStyle = .fill
    private(set) var showNames: Bool = true

    private let storageKey = "highlightLegend.v1"
    private let defaults: UserDefaults
    private let cloud = NSUbiquitousKeyValueStore.default
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
        cloud.synchronize()
    }

    // MARK: Reading

    var canAdd: Bool { entries.count < Self.maxColors }

    func name(for hue: HighlightHue) -> String {
        let name = entries.first(where: { $0.hue == hue })?.name ?? ""
        return name.isEmpty ? hue.colorName : name
    }

    // MARK: Editing

    func rename(_ hue: HighlightHue, to name: String) {
        guard let index = entries.firstIndex(where: { $0.hue == hue }) else { return }
        entries[index].name = name
        save()
    }

    func addNextColor() {
        guard canAdd, let hue = HighlightHue.allCases.first(where: { hue in !entries.contains(where: { $0.hue == hue }) }) else { return }
        entries.append(Entry(hue: hue, name: ""))
        save()
    }

    func remove(at offsets: IndexSet) {
        guard entries.count - offsets.count >= 1 else { return }
        entries.remove(atOffsets: offsets)
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func setDefaultStyle(_ style: HighlightStyle) {
        defaultStyle = style
        save()
    }

    func setShowNames(_ show: Bool) {
        showNames = show
        save()
    }

    // MARK: Persistence

    private func load() {
        let data = cloud.data(forKey: storageKey) ?? defaults.data(forKey: storageKey)
        guard let data, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data), !snapshot.entries.isEmpty else { return }
        entries = snapshot.entries
        defaultStyle = snapshot.defaultStyle
        showNames = snapshot.showNames
    }

    private func save() {
        let snapshot = Snapshot(entries: entries, defaultStyle: defaultStyle, showNames: showNames)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
        cloud.set(data, forKey: storageKey)
    }
}
