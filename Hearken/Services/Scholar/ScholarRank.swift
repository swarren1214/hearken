import SwiftUI

/// The five earned ranks of the Scholar Path, per subject: Novice → Sage.
///
/// A rank needs both its XP threshold and every stage before it complete, in order.
/// Novice has no threshold: it's earned with the first completed learning item.
enum ScholarRank: Int, CaseIterable, Identifiable, Comparable {
    case novice = 1, apprentice, investigator, scholar, sage

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .novice: "Novice"
        case .apprentice: "Apprentice"
        case .investigator: "Investigator"
        case .scholar: "Scholar"
        case .sage: "Sage"
        }
    }

    /// The fixed thresholds of rules version 1. Version 2 computes each path's thresholds from
    /// its required work (ScholarPathFile.xpThreshold(for:)); these remain the fallback.
    var xpThreshold: Int {
        switch self {
        case .novice: 0
        case .apprentice: 500
        case .investigator: 1_500
        case .scholar: 3_000
        case .sage: 5_000
        }
    }

    /// Stages 1…n that must be complete. Novice needs none.
    var requiredStages: Int { rawValue - 1 }

    var next: ScholarRank? { ScholarRank(rawValue: rawValue + 1) }

    /// "1,500 XP and Stage 2", or "First completed learning item", for a given threshold.
    func requirement(xp: Int) -> String {
        switch self {
        case .novice: "First completed learning item"
        case .sage: "\(xp.formatted()) XP, Stage 4 and the capstone"
        default: "\(xp.formatted()) XP and Stage \(requiredStages)"
        }
    }

    var palette: MedalPalette {
        switch self {
        case .novice: MedalPalette(rim: 0xC9875A, rimDark: 0x7A4A30, light: 0xF6C99A, mid: 0xD08A58, top: 0x5A3428, bottom: 0x1E171B)
        case .apprentice: MedalPalette(rim: 0x3FA27E, rimDark: 0x1F5E4A, light: 0x8BE3BC, mid: 0x4FB88E, top: 0x164A42, bottom: 0x0E1E22)
        case .investigator: MedalPalette(rim: 0x5A95D6, rimDark: 0x24467A, light: 0xA6DBFF, mid: 0x5FA8E6, top: 0x1A3A6A, bottom: 0x0F1A2C)
        case .scholar: MedalPalette(rim: 0xA585E8, rimDark: 0x4E3684, light: 0xD9C2FF, mid: 0xA884F0, top: 0x40266A, bottom: 0x18142C)
        case .sage: MedalPalette(rim: 0xEBD08A, rimDark: 0x8A7434, light: 0xFFF0C4, mid: 0xE2C46E, top: 0x6A5826, bottom: 0x22201B)
        }
    }

    /// Readable text color for the rank name on a plain background.
    func ink(dark: Bool) -> Color {
        if dark { return palette.light }
        switch self {
        case .novice: return Color(hex: 0x9A5A34)
        case .apprentice: return Color(hex: 0x1F7A5A)
        case .investigator: return Color(hex: 0x2766AE)
        case .scholar: return Color(hex: 0x6A48B8)
        case .sage: return Color(hex: 0x8A6E1E)
        }
    }

    static func < (lhs: ScholarRank, rhs: ScholarRank) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A medal's colors, matching the design canvas exactly.
struct MedalPalette {
    let rim: Color
    let rimDark: Color
    let light: Color
    let mid: Color
    let top: Color
    let bottom: Color

    init(rim: UInt32, rimDark: UInt32, light: UInt32, mid: UInt32, top: UInt32, bottom: UInt32) {
        self.rim = Color(hex: rim)
        self.rimDark = Color(hex: rimDark)
        self.light = Color(hex: light)
        self.mid = Color(hex: mid)
        self.top = Color(hex: top)
        self.bottom = Color(hex: bottom)
    }
}
