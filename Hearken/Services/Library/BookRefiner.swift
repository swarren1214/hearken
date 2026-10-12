import Foundation
import FoundationModels
import Observation
import OSLog
import SwiftData
import UIKit

/// A short title for a part of a book that had none, written by the on-device model.
@Generable
nonisolated struct PartTitle {
    @Guide(description: "A title of 2 to 6 words for this passage, in the plain style of a book's chapter titles. No quotation marks, no numbering, no ending punctuation.")
    var title: String
}

/// Names untitled parts ("Part 3") with Apple's on-device model, after a book is ready.
///
/// It only renames parts that had no title; it never touches the text. It runs while the
/// app is open (the model refuses requests in the background), one part at a time, and
/// picks up where it left off next time. Without Apple Intelligence, parts keep "Part 3".
@MainActor
final class BookRefiner {
    static let shared = BookRefiner()

    private var running: Set<String> = []
    private let log = Logger(subsystem: "com.stephenwarren.hearken", category: "library")
    /// Books this device has finished with (so launches don't re-read every book's text).
    private static let doneKey = "library.titledBooks"

    private var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Titles the untitled parts of every book that still has some.
    func refineAll() {
        guard isAvailable else { return }
        let done = Set(UserDefaults.standard.stringArray(forKey: Self.doneKey) ?? [])
        guard let context = ImportedLibrary.shared.modelContext else { return }
        let books = (try? context.fetch(FetchDescriptor<ImportedBook>())) ?? []
        for book in books where book.status == .ready && !done.contains(book.id) {
            refine(book.id)
        }
    }

    func refine(_ bookID: String) {
        guard isAvailable, !running.contains(bookID) else { return }
        let library = ImportedLibrary.shared
        guard let model = library.model(bookID), let data = model.contentData,
              let content = try? JSONDecoder().decode(ImportedContent.self, from: data), content.hasVerses else { return }
        let untitled = content.chapters.indices.filter { content.chapters[$0].titleSource == .generic }
        guard content.titlesRefined != true, !untitled.isEmpty else {
            markDone(bookID)
            return
        }

        running.insert(bookID)
        library.stage[bookID] = .naming
        let bookTitle = model.title
        Task {
            var content = content
            defer {
                running.remove(bookID)
                if library.stage[bookID] == .naming { library.stage[bookID] = nil }
            }
            var finished = true
            for index in untitled {
                guard UIApplication.shared.applicationState == .active else {
                    finished = false
                    break
                }
                let excerpt = String(content.chapters[index].paragraphs.joined(separator: " ").prefix(1_500))
                do {
                    let session = LanguageModelSession(instructions: "You name sections of books. Read the passage and give it a short, plain title that says what it is about. Use only what the passage says.")
                    let response = try await session.respond(
                        to: "Book: \(bookTitle)\n\nPassage:\n\(excerpt)",
                        generating: PartTitle.self,
                        options: GenerationOptions(temperature: 0.3)
                    )
                    if let title = Self.usable(response.content.title, bookTitle: bookTitle) {
                        content.chapters[index].title = title
                        content.chapters[index].titleSource = .model
                    }
                } catch {
                    // Rate limited or in the background: try again next time. Anything else
                    // (a refusal, an unsupported language): leave this part as "Part 3".
                    if let error = error as? LanguageModelSession.GenerationError, case .rateLimited = error {
                        finished = false
                        break
                    }
                    log.info("No title for a part of \(bookID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            if finished { content.titlesRefined = true }
            // The book may have been removed or edited meanwhile.
            guard let model = library.model(bookID), let newData = try? JSONEncoder().encode(content) else { return }
            model.contentData = newData
            model.updatedAt = .now
            try? model.modelContext?.save()
            library.refresh()
            if finished { markDone(bookID) }
        }
    }

    private func markDone(_ bookID: String) {
        var done = UserDefaults.standard.stringArray(forKey: Self.doneKey) ?? []
        guard !done.contains(bookID) else { return }
        done.append(bookID)
        UserDefaults.standard.set(done, forKey: Self.doneKey)
    }

    /// The model's title, tidied, or nil when it isn't one: empty, too long, or just the book's name.
    private static func usable(_ raw: String, bookTitle: String) -> String? {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'‘’.:;"))
        if title.lowercased().hasPrefix("title:") { title = String(title.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        let words = title.split(separator: " ").count
        guard words >= 1, words <= 8, title.count <= 60, !BookStructurer.sameWords(title, bookTitle) else { return nil }
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}
