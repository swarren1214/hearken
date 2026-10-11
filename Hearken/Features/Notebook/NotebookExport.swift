import Foundation

/// Plain text and Markdown versions of Notebook entries, for the share sheet.
@MainActor
enum NotebookExport {
    enum Format {
        case plain, markdown
    }

    /// Everything currently shown, grouped the way it's shown.
    static func text(_ sections: [NotebookSection], legend: HighlightLegend, format: Format) -> String {
        var parts: [String] = []
        for section in sections {
            switch format {
            case .plain: parts.append(section.title.uppercased())
            case .markdown: parts.append("## \(section.title)")
            }
            for entry in section.entries {
                parts.append(text(for: entry, legend: legend, format: format))
            }
        }
        return parts.joined(separator: "\n\n")
    }

    static func text(for entry: NotebookEntry, legend: HighlightLegend, format: Format) -> String {
        block(
            reference: entry.reference,
            meaning: entry.hue.map { legend.name(for: $0) },
            quote: entry.hasHighlight ? entry.quote.marked : entry.quote.fullText,
            note: entry.note?.body,
            format: format
        )
    }

    /// "Alma 32:21 — Promises", the quoted words, then the note.
    static func block(reference: String, meaning: String?, quote: String, note: String?, format: Format) -> String {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let quote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = meaning ?? (note.isEmpty ? nil : "Note")
        var lines: [String] = []
        switch format {
        case .plain:
            lines.append(label.map { "\(reference) — \($0)" } ?? reference)
            if !quote.isEmpty { lines.append("“\(quote)”") }
            if !note.isEmpty { lines.append(meaning == nil ? note : "Note: \(note)") }
        case .markdown:
            lines.append(label.map { "### \(reference) · \($0)" } ?? "### \(reference)")
            if !quote.isEmpty { lines.append("> \(quote)") }
            if !note.isEmpty { lines.append((quote.isEmpty ? "" : "\n") + note) }
        }
        return lines.joined(separator: "\n")
    }
}
