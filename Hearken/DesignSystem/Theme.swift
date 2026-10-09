import SwiftUI

/// Keys for settings stored with @AppStorage. Keep every key here so views stay in sync.
enum SettingsKey {
    static let accent = "settings.accent"
    static let appearance = "settings.appearance"
    static let scriptureTextSize = "settings.scriptureTextSize"
    static let showVerseNumbers = "settings.showVerseNumbers"
    static let dailyGoalMinutes = "settings.dailyGoalMinutes"
    static let studyReminder = "settings.studyReminder"
    static let onboardingDone = "onboarding.done"
}

/// The user-selectable app tint (Settings › Accent Color). Blue is the default.
enum AccentOption: String, CaseIterable, Identifiable {
    case blue, teal, indigo, purple, pink, red, orange, amber

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .blue: Color(hex: 0x0A7AFF)
        case .teal: Color(hex: 0x0E8A8A)
        case .indigo: Color(hex: 0x5E5CE6)
        case .purple: Color(hex: 0x8E44C9)
        case .pink: Color(hex: 0xC2185B)
        case .red: Color(hex: 0xD93B30)
        case .orange: Color(hex: 0xE8650F)
        case .amber: Color(hex: 0xC77C02)
        }
    }
}

/// Settings › Appearance.
enum AppearanceOption: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Answer feedback colors. Never the accent color, and always paired with a symbol.
enum Feedback {
    static let correct = Color.green
    static let incorrect = Color.red
    static let correctSymbol = "checkmark.circle.fill"
    static let incorrectSymbol = "xmark.circle.fill"
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// New York, used for scripture text and chapter titles.
    static func scripture(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
