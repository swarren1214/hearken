import Foundation
import FoundationModels
import NaturalLanguage
import OSLog

/// What the reader asked to have explained, with the nearby text the model needs for context.
struct ExplainRequest: Identifiable, Hashable {
    let id = UUID()
    let chapterID: String
    /// "Alma 32"
    let chapterTitle: String
    /// "Alma 32:27" or "Alma 32:27–28"
    let reference: String
    let selectedText: String
    let heading: String?
    let before: String
    let after: String
    let startVerse: Int
    let endVerse: Int

    /// The longest selection sent to the model; the context window holds about 4,000 tokens.
    static let maxSelection = 2_400
    static let maxContext = 700

    var cacheKey: String { "\(chapterID)|\(startVerse)|\(endVerse)|\(selectedText.hashValue)" }

    /// The Church's own study page for this chapter, offered next to every AI explanation.
    var studyHelpsURL: URL? {
        URL(string: "https://www.churchofjesuschrist.org/study/scriptures/\(chapterID.replacingOccurrences(of: ".", with: "/"))?lang=eng")
    }
}

// MARK: - Model output

@Generable
struct VerseExplanation {
    @Guide(description: "What the selected text says, in 2 to 4 plain, modern sentences. Faithful to the text; no added doctrine or opinion.")
    var summary: String

    @Guide(description: "Up to 4 words or short phrases copied exactly from the selected text that a modern reader may not know, each with a short plain definition. Leave empty if there are none.", .maximumCount(4))
    var terms: [VerseTerm]

    @Guide(description: "1 or 2 sentences on who is speaking, to whom, and what is happening, based only on the chapter summary and nearby verses provided.")
    var context: String
}

@Generable
struct VerseTerm {
    @Guide(description: "A word or short phrase copied exactly from the selected text")
    var word: String

    @Guide(description: "Its meaning here, in a few plain words")
    var meaning: String
}

// MARK: - Engine

/// Apple's on-device model, set up for explaining scripture.
@MainActor
final class ExplainEngine {
    static let shared = ExplainEngine()

    enum Availability: Equatable {
        case available
        /// Supported device, but Apple Intelligence is off.
        case notEnabled
        /// Turned on, but the model is still downloading.
        case notReady
        /// The device can't run Apple Intelligence: Explain isn't offered.
        case unsupported

        var message: String {
            switch self {
            case .available: ""
            case .notEnabled: "Explain uses Apple Intelligence, which is turned off. Turn it on in Settings › Apple Intelligence & Siri."
            case .notReady: "Apple Intelligence is still getting ready on this device. Try again in a little while."
            case .unsupported: "Explain needs a device that supports Apple Intelligence."
            }
        }
    }

    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "explain")
    private var prepared: LanguageModelSession?

    var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.appleIntelligenceNotEnabled): .notEnabled
        case .unavailable(.modelNotReady): .notReady
        case .unavailable: .unsupported
        }
    }

    /// Whether to show the Explain button at all.
    var isOffered: Bool { availability != .unsupported }

    /// Loads the model ahead of time when a selection appears, so the first words come quickly.
    func prewarm() {
        guard availability == .available, prepared == nil else { return }
        let session = makeSession()
        session.prewarm()
        prepared = session
    }

    func takeSession() -> LanguageModelSession {
        if let prepared {
            self.prepared = nil
            return prepared
        }
        return makeSession()
    }

    func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: Self.instructions)
    }

    static let instructions = """
    You are a study helper inside Hearken, a scripture-reading app used by members of The Church of Jesus Christ of Latter-day Saints. \
    Help a modern reader understand the selected passage.

    Rules:
    - Explain what the text says. Stay faithful to its words and stay within the passage, its chapter summary and the nearby verses given.
    - Use plain, warm, respectful language a teenager could follow.
    - Never invent quotes, references, verse numbers, names, dates or historical claims. If something is unclear, say so briefly.
    - Do not state Church doctrine or policy, speak for the Church or its leaders, interpret prophecy with certainty, or take sides on contested questions.
    - Do not argue for or against any belief. Do not give personal advice.
    - If asked about anything outside the passage, gently say you can only help with this passage.
    """

    static func prompt(for request: ExplainRequest) -> String {
        var lines = ["Chapter: \(request.chapterTitle)"]
        if let heading = request.heading, !heading.isEmpty { lines.append("Chapter summary: \(heading)") }
        if !request.before.isEmpty { lines.append("Verses just before: \(request.before)") }
        lines.append("Selected text (\(request.reference)): \"\(request.selectedText)\"")
        if !request.after.isEmpty { lines.append("Verses just after: \(request.after)") }
        lines.append("Explain the selected text.")
        return lines.joined(separator: "\n\n")
    }

    static func followUpPrompt(_ question: String, request: ExplainRequest, includePassage: Bool) -> String {
        let ask = "Follow-up question about \(request.reference): \(question)\n\nAnswer in 2 to 4 plain sentences, staying within this passage and its chapter."
        return includePassage ? prompt(for: request) + "\n\n" + ask : ask
    }

    func message(for error: Error) -> String {
        log.error("explain failed: \(String(describing: error), privacy: .public)")
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation:
                return "This passage can't be explained here. The Church's study helps for this chapter may help."
            case .exceededContextWindowSize:
                return "That selection is too long to explain at once. Try a verse or two."
            default:
                break
            }
        }
        return "Explain isn't available right now. Try again in a moment."
    }
}

/// Finished explanations, kept for this launch so reopening one is instant.
@MainActor
final class ExplainCache {
    static let shared = ExplainCache()

    struct Entry {
        let summary: String
        let terms: [ExplainModel.Term]
        let context: String
    }

    private var entries: [String: Entry] = [:]

    subscript(key: String) -> Entry? {
        get { entries[key] }
        set {
            if entries.count > 60 { entries.removeAll() }
            entries[key] = newValue
        }
    }
}

// MARK: - Explaining one selection

@MainActor
@Observable
final class ExplainModel {
    enum Phase: Equatable {
        case generating
        case done
        case failed(String)
        case unavailable(String)
    }

    struct Term: Identifiable, Hashable {
        let id: Int
        var word: String
        var meaning: String
    }

    struct Exchange: Identifiable {
        let id = UUID()
        let question: String
        var answer = ""
        var done = false
    }

    let request: ExplainRequest
    private(set) var phase: Phase = .generating
    private(set) var summary = ""
    private(set) var terms: [Term] = []
    private(set) var context = ""
    private(set) var related: [RelatedPassage] = []
    private(set) var relatedLoaded = false
    private(set) var exchanges: [Exchange] = []

    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private var passageInSession = false

    init(request: ExplainRequest) {
        self.request = request
    }

    var isAnswering: Bool { exchanges.last.map { !$0.done } ?? false }

    /// Everything shown, as plain text for Copy and Save as Note.
    var plainText: String {
        var parts = [summary]
        if !terms.isEmpty {
            parts.append(terms.map { "\($0.word): \($0.meaning)" }.joined(separator: "\n"))
        }
        if !context.isEmpty { parts.append(context) }
        for exchange in exchanges where exchange.done {
            parts.append("Q: \(exchange.question)\n\(exchange.answer)")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    func start() async {
        async let relatedTask: Void = findRelated()

        if let cached = ExplainCache.shared[request.cacheKey] {
            summary = cached.summary
            terms = cached.terms
            context = cached.context
            phase = .done
        } else {
            let engine = ExplainEngine.shared
            let availability = engine.availability
            if availability != .available {
                phase = .unavailable(availability.message)
            } else {
                await generate(engine: engine)
            }
        }
        await relatedTask
    }

    private func generate(engine: ExplainEngine) async {
        let session = engine.takeSession()
        self.session = session
        passageInSession = true
        do {
            let stream = session.streamResponse(
                to: ExplainEngine.prompt(for: request),
                generating: VerseExplanation.self,
                options: GenerationOptions(temperature: 0.3)
            )
            for try await snapshot in stream {
                apply(snapshot.content)
            }
            keepOnlyRealTerms()
            phase = .done
            ExplainCache.shared[request.cacheKey] = ExplainCache.Entry(summary: summary, terms: terms, context: context)
        } catch {
            phase = .failed(engine.message(for: error))
        }
    }

    private func apply(_ partial: VerseExplanation.PartiallyGenerated) {
        if let text = partial.summary { summary = text }
        if let text = partial.context { context = text }
        if let list = partial.terms {
            terms = list.enumerated().compactMap { index, term in
                guard let word = term.word, !word.isEmpty else { return nil }
                return Term(id: index, word: word, meaning: term.meaning ?? "")
            }
        }
    }

    /// Drops any "word to know" that isn't actually in the selection.
    private func keepOnlyRealTerms() {
        let text = request.selectedText.lowercased()
        terms = terms.filter { !$0.meaning.isEmpty && text.contains($0.word.lowercased()) }
    }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnswering else { return }
        let engine = ExplainEngine.shared
        guard engine.availability == .available else { return }

        let session = self.session ?? engine.makeSession()
        self.session = session
        let prompt = ExplainEngine.followUpPrompt(trimmed, request: request, includePassage: !passageInSession)
        passageInSession = true

        exchanges.append(Exchange(question: trimmed))
        let index = exchanges.count - 1
        do {
            let stream = session.streamResponse(to: prompt, options: GenerationOptions(temperature: 0.3))
            for try await snapshot in stream {
                exchanges[index].answer = snapshot.content
            }
        } catch {
            exchanges[index].answer = engine.message(for: error)
        }
        exchanges[index].done = true
    }

    private func findRelated() async {
        let keywords = RelatedPassageIndex.keywords(in: request.selectedText)
        related = await RelatedPassageIndex.shared.related(to: keywords, excludingChapter: request.chapterID)
        relatedLoaded = true
    }
}

// MARK: - Related passages

/// A verse elsewhere that shares the selection's key words. These come from the app's own
/// scripture text, never from the model, so every reference is real.
struct RelatedPassage: Identifiable, Hashable, Sendable {
    let chapterID: String
    let verse: Int
    let reference: String
    let text: String
    var id: String { "\(chapterID):\(verse)" }
}

actor RelatedPassageIndex {
    static let shared = RelatedPassageIndex()

    private struct Entry: Sendable {
        let chapterID: String
        let verse: Int
        let reference: String
        let text: String
        let lower: String
    }

    private var entries: [Entry]?

    /// Words that appear so often in scripture they say nothing about a passage.
    private static let stopwords: Set<String> = [
        "behold", "come", "came", "cometh", "unto", "thee", "thou", "thy", "thine", "shall", "shalt", "have", "hath",
        "said", "saith", "say", "make", "made", "take", "know", "knew", "also", "even", "things", "thing", "therefore",
        "were", "will", "would", "upon", "into", "that", "this", "these", "those", "they", "them", "their", "there",
        "which", "what", "when", "with", "from", "pass", "people", "lord", "god", "yea", "being", "great", "time",
        "give", "given", "word", "words", "many", "much", "day", "days", "man", "men", "speak", "spake", "go", "went",
    ]

    /// Nouns, verbs and adjectives from the selection, lemmatized where possible.
    nonisolated static func keywords(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        var result: [String] = []
        let wanted: Set<NLTag> = [.noun, .verb, .adjective]
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitPunctuation, .omitWhitespace, .omitOther]) { tag, range in
            guard let tag, wanted.contains(tag) else { return true }
            let word = String(text[range]).lowercased()
            let lemma = tagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue.lowercased() ?? word
            let stem = lemma.count >= 4 ? lemma : word
            if stem.count >= 4, !stopwords.contains(stem), !stopwords.contains(word), !result.contains(stem) {
                result.append(stem)
            }
            return true
        }
        return Array(result.prefix(10))
    }

    /// Up to `limit` verses from other chapters, scored by the rarer key words they share.
    func related(to keywords: [String], excludingChapter chapterID: String, limit: Int = 3) -> [RelatedPassage] {
        guard keywords.count >= 2 else { return [] }
        let all = loadedEntries()
        guard !all.isEmpty else { return [] }

        // How many verses each key word appears in, so rare shared words count for more.
        var frequency = [Int](repeating: 0, count: keywords.count)
        for entry in all {
            for (index, keyword) in keywords.enumerated() where entry.lower.contains(keyword) {
                frequency[index] += 1
            }
        }
        let total = Double(all.count)
        let weights = frequency.map { $0 == 0 ? 0 : log(total / Double($0)) }

        var scored: [(score: Double, entry: Entry)] = []
        for entry in all where entry.chapterID != chapterID {
            var matches = 0
            var score = 0.0
            for (index, keyword) in keywords.enumerated() where entry.lower.contains(keyword) {
                matches += 1
                score += weights[index]
            }
            if matches >= 2 { scored.append((score, entry)) }
        }
        scored.sort { $0.score > $1.score }

        var seenChapters: Set<String> = []
        var picks: [RelatedPassage] = []
        for (_, entry) in scored where !seenChapters.contains(entry.chapterID) {
            seenChapters.insert(entry.chapterID)
            picks.append(RelatedPassage(chapterID: entry.chapterID, verse: entry.verse, reference: entry.reference, text: entry.text))
            if picks.count == limit { break }
        }
        return picks
    }

    /// Every verse of every volume, read once from the bundle on first use.
    private func loadedEntries() -> [Entry] {
        if let entries { return entries }
        var built: [Entry] = []
        built.reserveCapacity(42_000)
        for id in ContentService.volumeIDs {
            guard let url = Bundle.main.url(forResource: "scripture-\(id)", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(ScriptureVolumeFile.self, from: data) else { continue }
            for book in file.volume.books {
                for chapter in book.chapters {
                    for verse in chapter.verses {
                        built.append(Entry(
                            chapterID: chapter.id,
                            verse: verse.number,
                            reference: "\(book.title) \(chapter.number):\(verse.number)",
                            text: verse.text,
                            lower: verse.text.lowercased()
                        ))
                    }
                }
            }
        }
        entries = built
        return built
    }
}
