import SwiftUI
import UIKit

/// Keys for settings stored with @AppStorage. Keep every key here so views stay in sync.
enum SettingsKey {
    static let appearance = "settings.appearance"
    static let scriptureTextSize = "settings.scriptureTextSize"
    static let showVerseNumbers = "settings.showVerseNumbers"
    static let readerLayout = "settings.readerLayout"
    static let pencilHighlighting = "settings.pencilHighlighting"
    static let pencilHue = "settings.pencilHue"
    static let pencilStyle = "settings.pencilStyle"
    static let dailyGoalMinutes = "settings.dailyGoalMinutes"
    static let studyReminder = "settings.studyReminder"
    /// Settings › Review Questions: a daily Spaced Review question answered from the notification.
    static let reviewNotifications = "settings.reviewNotifications"
    static let reviewNotificationMinutes = "settings.reviewNotificationMinutes"
    static let onboardingDone = "onboarding.done"
    /// The first-run tour has been finished or skipped.
    static let tourDone = "tour.done"
    /// Settings › Show All Tips Again: TipKit's records are cleared at the next launch.
    static let tipsResetPending = "tips.resetPending"
}

/// How the reader presents a chapter: one long scroll, or pages that turn with a page curl.
enum ReaderLayout: String, CaseIterable, Identifiable {
    case scroll, pages

    var id: String { rawValue }
    var title: String { self == .scroll ? "Scroll" : "Page Turn" }
    var symbol: String { self == .scroll ? "scroll" : "book.pages" }
}

/// Hearken's tint everywhere. (It used to be a setting, Accent Color.)
enum Accent {
    static let color = Color(hex: 0x0A7AFF)
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

extension UIDevice {
    /// Apple Pencil features only appear on iPad.
    static var isPad: Bool { current.userInterfaceIdiom == .pad }
}
