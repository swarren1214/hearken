import AVFoundation
import SwiftData
import SwiftUI

/// The verse a board shows.
struct VerseBoardItem: Identifiable {
    let id = UUID()
    let reference: String
    let text: String
}

/// iPhone Duo Tent ("Verse of the week"): one verse, big enough to read from across a desk or
/// nightstand, on the outer display. The eye switches between the full text and first letters,
/// for practising it from memory; Listen reads it aloud; Spaced Review opens the day's review,
/// which is always free. Opened by the person from the reader (the system can't tell Tent from
/// Closed), and it works on any iPhone or iPad too.
struct VerseGlanceBoard: View {
    let reference: String
    let text: String

    @Environment(ContentService.self) private var content
    @Query private var reviews: [ItemReview]
    @Query private var progress: [ReadingProgress]
    @State private var firstLettersOnly = false
    @State private var speaker = VerseSpeaker()
    @State private var review: GameRequest?
    @State private var showsPaywall = false

    private let mastery = MasteryService()

    init(reference: String, text: String) {
        self.reference = reference
        self.text = text
    }

    var body: some View {
        HearthGlanceBoard("Verse Board", color: Accent.color) {
            VStack(spacing: 16) {
                Text(firstLettersOnly ? Self.firstLetters(of: text) : text)
                    .font(.scripture(size: 44, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.3)
                    .contentTransition(.opacity)
                    .accessibilityLabel(text)
                Text(reference)
                    .font(.title2.weight(.semibold))
                    .opacity(0.85)
            }
            .animation(.snappy, value: firstLettersOnly)
        } actions: {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(firstLettersOnly ? "Show Words" : "First Letters",
                       systemImage: firstLettersOnly ? "eye" : "eye.slash") {
                    firstLettersOnly.toggle()
                }
                Button(speaker.isSpeaking ? "Stop" : "Listen",
                       systemImage: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2") {
                    listen()
                }
                // Spaced Review, always free: what you're closest to forgetting.
                Button("Spaced Review", systemImage: "arrow.counterclockwise") {
                    review = GameRequest(title: "Spaced Review", kind: .review, subjectID: nil, questions: dueQuestions)
                }
                .disabled(dueQuestions.isEmpty)
            }
        }
        // White controls on the app's color, Close included (the text color here is white).
        .tint(.white)
        .onDisappear { speaker.stop() }
        .fullScreenCover(item: $review) { GameView(request: $0).hearthDuoPose() }
        // Reading aloud is part of Listen, which needs Hearken Plus or Hearth+.
        .hearthPaywall(isPresented: $showsPaywall, feature: HearthPaywallFeature(
            "Listen",
            detail: "Hear the scriptures read aloud, verse by verse.",
            symbol: "headphones"
        ))
    }

    private var dueQuestions: [Question] {
        let snapshot = MasterySnapshot(reviews: reviews, progress: progress)
        return mastery.dueQuestions(from: content.questions, snapshot: snapshot, limit: 10)
    }

    private func listen() {
        if speaker.isSpeaking {
            speaker.stop()
            return
        }
        guard HearthPurchases.shared.isUnlocked else {
            showsPaywall = true
            return
        }
        if ListenEngine.shared.isPlaying { ListenEngine.shared.pause() }
        speaker.speak("\(reference). \(text)")
    }

    /// Each word cut to its first letter, keeping punctuation: "And it came to pass," → "A i c t p,".
    static func firstLetters(of text: String) -> String {
        text.split(separator: " ").map { word -> String in
            var result = ""
            var tookLetter = false
            for character in word {
                if character.isLetter || character.isNumber {
                    if !tookLetter {
                        result.append(character)
                        tookLetter = true
                    }
                } else {
                    result.append(character)
                }
            }
            return result
        }
        .joined(separator: " ")
    }
}

/// Reads one verse aloud with the best installed voice (the same one Listen prefers).
@MainActor
@Observable
final class VerseSpeaker: NSObject {
    private(set) var isSpeaking = false
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// The utterance being spoken, so a late callback for one that was replaced is ignored.
    @ObservationIgnored private var current: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = ListenVoices.best()
        current = ObjectIdentifier(utterance)
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    fileprivate func ended(_ id: ObjectIdentifier) {
        guard id == current else { return }
        current = nil
        isSpeaking = false
    }

}

extension VerseSpeaker: AVSpeechSynthesizerDelegate {
    // As in ListenEngine: hop to the main actor with the utterance's identity only.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.ended(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.ended(id) }
    }
}
