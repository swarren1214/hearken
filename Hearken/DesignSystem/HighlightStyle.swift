import SwiftUI

/// The fixed set of highlight colors. Users give each one a meaning in Settings › Highlight Colors.
/// System colors adapt to light and dark mode automatically.
enum HighlightHue: String, CaseIterable, Codable, Identifiable {
    case yellow, blue, green, pink, purple, orange, teal, indigo

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .yellow: .yellow
        case .blue: .cyan
        case .green: .green
        case .pink: .pink
        case .purple: .purple
        case .orange: .orange
        case .teal: .teal
        case .indigo: .indigo
        }
    }

    /// The color's plain name, for VoiceOver and as a fallback label.
    var colorName: String { rawValue.capitalized }
}

/// How a highlight is drawn.
enum HighlightStyle: String, CaseIterable, Codable, Identifiable {
    case fill, underline

    var id: String { rawValue }
    var name: String { self == .fill ? "Highlight" : "Underline" }
}

extension AttributedString {
    /// Applies a highlight to the whole string.
    mutating func applyHighlight(_ hue: HighlightHue, style: HighlightStyle) {
        switch style {
        case .fill:
            self.swiftUI.backgroundColor = hue.color.opacity(0.32)
        case .underline:
            self.swiftUI.underlineStyle = Text.LineStyle(pattern: .solid, color: hue.color)
        }
    }
}
