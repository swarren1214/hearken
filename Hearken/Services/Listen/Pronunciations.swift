import Foundation

/// How Listen mode says scripture names the voices would otherwise guess at (Nephi, Moroni,
/// Zarahemla…). Built from scripts/pronunciations.txt by scripts/build_pronunciations.py into
/// Resources/Kokoro/pronunciations.json, with each name in Kokoro's notation and in IPA.
nonisolated enum Pronunciations {
    struct Entry: Decodable, Sendable {
        /// Kokoro's phoneme notation (misaki), for the natural voices.
        let kokoro: String
        /// Standard IPA, for the system voices.
        let ipa: String
    }

    struct Match {
        let name: String
        let range: NSRange
        let entry: Entry
    }

    private struct File: Decodable {
        let names: [String: Entry]
    }

    static let names: [String: Entry] = {
        let url = Bundle.main.url(forResource: "pronunciations", withExtension: "json")
            ?? Bundle.main.url(forResource: "pronunciations", withExtension: "json", subdirectory: "Kokoro")
        guard let url, let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [:] }
        return file.names
    }()

    /// Longest names first, so "Anti-Nephi-Lehi" wins over "Nephi".
    private static let pattern: NSRegularExpression? = {
        guard !names.isEmpty else { return nil }
        let alternatives = names.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        return try? NSRegularExpression(pattern: "\\b(?:" + alternatives.joined(separator: "|") + ")\\b")
    }()

    /// Every known name in `text`, in order.
    static func matches(in text: String) -> [Match] {
        guard let pattern else { return [] }
        let ns = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { result in
            let name = ns.substring(with: result.range)
            return names[name].map { Match(name: name, range: result.range, entry: $0) }
        }
    }
}
