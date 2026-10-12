import SwiftUI
import UIKit

/// An imported book's cover: the book's own art when it has some (a PDF's first page), or a
/// generated cloth cover in the Library's style. While the book is being prepared it shows a
/// progress ring; if it couldn't be read, a warning.
struct ImportedBookCover: View {
    let book: ImportedBook
    var size = CGSize(width: 120, height: 180)
    var showsRibbon = false
    var showsStatus = true

    @State private var library = ImportedLibrary.shared

    private var scale: CGFloat { size.width / 120 }

    var body: some View {
        art
            .overlay {
                if showsStatus { status }
            }
    }

    @ViewBuilder
    private var art: some View {
        if let image = CoverImageCache.image(for: book) {
            let shape = UnevenRoundedRectangle(
                topLeadingRadius: 3 * scale, bottomLeadingRadius: 3 * scale,
                bottomTrailingRadius: 8 * scale, topTrailingRadius: 8 * scale
            )
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .overlay {
                    // The spine's crease.
                    shape.fill(LinearGradient(stops: [
                        .init(color: .black.opacity(0.28), location: 0),
                        .init(color: .black.opacity(0.06), location: 0.06),
                        .init(color: .clear, location: 0.12),
                    ], startPoint: .leading, endPoint: .trailing))
                }
                .overlay { shape.strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5) }
                .overlay(alignment: .bottomTrailing) {
                    if book.format == .pdf && size.width >= 80 { formatTag }
                }
                .overlay(alignment: .topTrailing) {
                    if showsRibbon {
                        CoverRibbon()
                            .fill(.tint)
                            .frame(width: 10 * scale, height: 40 * scale)
                            .offset(x: -14 * scale, y: -2)
                            .accessibilityHidden(true)
                    }
                }
                .compositingGroup()
                .shadow(color: .black.opacity(0.22), radius: 8 * min(scale, 2), y: 8 * min(scale, 2))
        } else {
            BookCover(work: book.coverWork, size: size, showsRibbon: showsRibbon)
                .overlay(alignment: .bottomTrailing) {
                    if book.format == .pdf && size.width >= 80 { formatTag }
                }
        }
    }

    private var formatTag: some View {
        Text(book.format.title)
            .font(.system(size: 9 * scale, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 2 * scale)
            .background(Color(hex: 0xC4302B), in: .rect(cornerRadius: 3 * scale))
            .padding(8 * scale)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var status: some View {
        switch book.status {
        case .ready:
            EmptyView()
        case .preparing:
            let value = library.progress[book.id]
            ZStack {
                RoundedRectangle(cornerRadius: 6 * scale).fill(.black.opacity(0.45))
                ZStack {
                    Circle().stroke(.white.opacity(0.3), lineWidth: 4 * scale)
                    if let value {
                        Circle()
                            .trim(from: 0, to: max(0.03, value))
                            .stroke(.white, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: value)
                    } else {
                        // Waiting for the text to arrive from another device.
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 16 * scale, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 40 * scale, height: 40 * scale)
            }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
        case .failed:
            ZStack {
                RoundedRectangle(cornerRadius: 6 * scale).fill(.black.opacity(0.5))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26 * scale))
                    .foregroundStyle(.yellow)
            }
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
        }
    }
}

// SwiftData models aren't main-actor isolated; these build main-actor UI values.
@MainActor
extension ImportedBook {
    /// The generated cloth cover's description, as one of the Library's works.
    var coverWork: LibraryWork {
        LibraryWork(
            id: workID, title: title, subtitle: author,
            coverHex: UInt32(truncatingIfNeeded: coverHex == 0 ? BookImporter.coverColor(for: title) : coverHex),
            summary: "", volumes: []
        )
    }

    /// "EPUB · 108 chapters"
    var formatSummary: String {
        var parts = [format.title]
        if chapterCount > 0 { parts.append(LibraryBook.Unit.chapter.count(chapterCount)) }
        if format == .pdf, pageCount > 0 { parts.append("\(pageCount.formatted()) pages") }
        return parts.joined(separator: " · ")
    }

    var accessibilityStatus: String {
        switch status {
        case .ready: ""
        case .preparing: "Preparing"
        case .failed: "Couldn't be read"
        }
    }
}

/// Decoded cover art, so a shelf doesn't decode JPEGs on every redraw.
@MainActor
enum CoverImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for book: ImportedBook) -> UIImage? {
        guard let data = book.coverData else { return nil }
        let key = "\(book.id)-\(data.count)" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The line under a cover while its book is being prepared: the stage, then how far along.
/// Hidden once the book is ready.
struct BookStatusCaption: View {
    let book: ImportedBook

    @State private var library = ImportedLibrary.shared

    var body: some View {
        if let status = status {
            VStack(alignment: .leading, spacing: 1) {
                Text(status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(status.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .frame(width: 120, alignment: .leading)
            .accessibilityElement(children: .combine)
            .animation(.snappy, value: status.detail)
        }
    }

    private var status: (title: String, detail: String)? {
        switch book.status {
        case .preparing:
            guard let progress = library.progress[book.id] else {
                // Imported on another device: the text arrives through iCloud.
                return ("Waiting for iCloud", "Preparing elsewhere")
            }
            let stage = library.stage[book.id] ?? .reading
            if stage == .reading, book.format == .pdf, book.pageCount > 0 {
                // Reading is the first 80% of the bar.
                let page = min(book.pageCount, max(1, Int((progress / 0.8 * Double(book.pageCount)).rounded())))
                return (stage.title(for: book.format), "\(page) of \(book.pageCount)")
            }
            return (stage.title(for: book.format), "\(Int((progress * 100).rounded()))%")
        case .failed:
            return ("Couldn't read", "Tap to try again")
        case .ready:
            if library.stage[book.id] == .naming { return ("Naming parts", "Ready to read") }
            return nil
        }
    }
}
