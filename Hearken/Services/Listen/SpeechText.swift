import AVFoundation
import Foundation

/// Turns verses into utterances: cleans the text, adds "Verse 21." when asked, and teaches
/// the voice how to say Book of Mormon and Bible names it would otherwise guess at.
enum SpeechText {
    /// One utterance for one verse.
    static func utterance(
        for verse: Verse,
        readsNumber: Bool,
        voice: AVSpeechSynthesisVoice?,
        speed: Double,
        pause: VersePause,
        isFirst: Bool
    ) -> AVSpeechUtterance {
        let spoken = (readsNumber ? "Verse \(verse.number). " : "") + clean(verse.text)
        let utterance = AVSpeechUtterance(attributedString: pronounced(spoken))
        utterance.voice = voice
        utterance.rate = rate(for: speed)
        utterance.preUtteranceDelay = isFirst ? 0 : pause.seconds
        return utterance
    }

    /// The synthesizer's rate isn't linear in perceived speed: 0.5 is normal, and small steps
    /// above it speed up quickly. These points sound close to 0.75×–2× on the system voices.
    static func rate(for speed: Double) -> Float {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let value = speed >= 1 ? base + (speed - 1) * 0.125 : base - (1 - speed) * 0.4
        return Float(min(max(value, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }

    /// About how long a verse takes to speak, for the lock screen's time and "min left".
    /// Narration runs near 155 words a minute at 1×.
    static func seconds(for verse: Verse, speed: Double, pause: VersePause) -> Double {
        let words = verse.text.split(whereSeparator: \.isWhitespace).count
        return Double(words) / (2.6 * max(speed, 0.5)) + pause.seconds
    }

    static func clean(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "¶", with: "")
        // Footnote letters some sources leave in, like "faith^a".
        result = result.replacingOccurrences(of: #"\^[a-z]"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Marks each known name with its IPA pronunciation.
    static func pronounced(_ text: String) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let key = NSAttributedString.Key(rawValue: AVSpeechSynthesisIPANotationAttribute)
        let whole = NSRange(location: 0, length: (text as NSString).length)
        for (name, ipa) in pronunciations where text.contains(name) {
            guard let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b") else { continue }
            for match in regex.matches(in: text, range: whole) {
                attributed.addAttribute(key, value: ipa, range: match.range)
            }
        }
        return attributed
    }

    /// From the Book of Mormon pronunciation guide (NEE-fy, mo-RO-nye, and so on). Add to this
    /// as testers report names the voices get wrong.
    static let pronunciations: [String: String] = [
        "Nephi": "ˈniːfaɪ",
        "Nephites": "ˈniːfaɪts",
        "Nephihah": "niˈfaɪə",
        "Lehi": "ˈliːhaɪ",
        "Laman": "ˈleɪmən",
        "Lamanites": "ˈleɪmənaɪts",
        "Lemuel": "ˈlɛmjuəl",
        "Sariah": "səˈraɪə",
        "Moroni": "mɔˈroʊnaɪ",
        "Moronihah": "ˌmɔːroʊˈnaɪə",
        "Mormon": "ˈmɔːrmən",
        "Mosiah": "moʊˈsaɪə",
        "Helaman": "ˈhiːləmən",
        "Abinadi": "əˈbɪnədaɪ",
        "Amulek": "ˈæmjʊlɛk",
        "Ammonihah": "ˌæməˈnaɪə",
        "Zeezrom": "ˈziːzrəm",
        "Zarahemla": "ˌzærəˈhɛmlə",
        "Liahona": "ˌliːəˈhoʊnə",
        "Gadianton": "ˌɡædiˈæntən",
        "Kishkumen": "kɪʃˈkjuːmən",
        "Teancum": "ˈtiːæŋkəm",
        "Pahoran": "pəˈhɔːrən",
        "Lachoneus": "ləˈkoʊniəs",
        "Gidgiddoni": "ˌɡɪdɡɪˈdoʊnaɪ",
        "Corianton": "ˌkɔːriˈæntən",
        "Shiblon": "ˈʃɪblən",
        "Cumorah": "kəˈmɔːrə",
        "Jaredites": "ˈdʒærədaɪts",
        "Ether": "ˈiːθər",
        "Melchizedek": "mɛlˈkɪzədɛk",
        "Hagoth": "ˈheɪɡɑθ",
    ]
}

/// The pause between verses (Settings › Listening).
enum VersePause: String, CaseIterable, Identifiable {
    case none, short, long

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "None"
        case .short: "Short"
        case .long: "Long"
        }
    }
    var seconds: Double {
        switch self {
        case .none: 0
        case .short: 0.35
        case .long: 0.9
        }
    }
}

/// The voices Hearken can use: the system's English voices, best first.
enum ListenVoices {
    struct Option: Identifiable, Hashable {
        let id: String
        let name: String
        let detail: String
        let tier: Tier
    }

    enum Tier: Int, Comparable {
        case premium, enhanced, personal, standard

        var title: String {
            switch self {
            case .premium: "Premium"
            case .enhanced: "Enhanced"
            case .personal: "Personal"
            case .standard: "Default"
            }
        }

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    static func tier(of voice: AVSpeechSynthesisVoice) -> Tier {
        if voice.voiceTraits.contains(.isPersonalVoice) { return .personal }
        switch voice.quality {
        case .premium: return .premium
        case .enhanced: return .enhanced
        default: return .standard
        }
    }

    /// English voices without the novelty ones (Bells, Bubbles…). Default-quality voices are
    /// limited to US English and the device's own region, so the list stays short.
    static func available() -> [Option] {
        let region = Locale.current.region?.identifier ?? "US"
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { voice in
            guard voice.language.hasPrefix("en"), !voice.voiceTraits.contains(.isNoveltyVoice) else { return false }
            if tier(of: voice) == .standard {
                return voice.language == "en-US" || voice.language == "en-\(region)"
            }
            return true
        }
        return voices
            .map { voice in
                Option(id: voice.identifier, name: voice.name, detail: languageName(voice.language), tier: tier(of: voice))
            }
            .sorted { ($0.tier, $0.name) < ($1.tier, $1.name) }
    }

    /// The best installed voice for the device's English: Premium, then Enhanced, then default.
    static func best() -> AVSpeechSynthesisVoice? {
        let region = Locale.current.region?.identifier ?? "US"
        let english = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix("en") && !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        let preferred = english.filter { $0.language == "en-\(region)" || $0.language == "en-US" }
        let pool = preferred.isEmpty ? english : preferred
        return pool.min { tier(of: $0) < tier(of: $1) } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    /// True when only the robotic default voices are installed.
    static var onlyBasicVoices: Bool {
        available().allSatisfy { $0.tier == .standard }
    }

    private static func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
