import Compression
import Foundation

/// Reads files out of a ZIP archive (an EPUB is one). Supports stored and deflated entries,
/// which is all EPUBs use. Read-only, in memory.
nonisolated struct ZipArchive: Sendable {
    enum ZipError: LocalizedError {
        case notAnArchive
        case damaged
        case unsupportedCompression(UInt16)
        case missingEntry(String)

        var errorDescription: String? {
            switch self {
            case .notAnArchive: "The file isn't a valid EPUB."
            case .damaged: "The file is damaged."
            case .unsupportedCompression: "The file uses a kind of compression Hearken can't read."
            case .missingEntry(let path): "The book is missing \(path)."
            }
        }
    }

    struct Entry: Sendable {
        let path: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    /// Keyed by the path as stored in the archive.
    let entries: [String: Entry]

    init(data: Data) throws {
        self.data = data
        let reader = ByteReader(data: data)
        guard data.count >= 22 else { throw ZipError.notAnArchive }

        // The end-of-central-directory record sits in the last 64 KB (it can be followed by a comment).
        var eocd: Int?
        let lowest = max(0, data.count - 22 - 65_535)
        var position = data.count - 22
        while position >= lowest {
            if reader.u32(position) == 0x0605_4B50 {
                eocd = position
                break
            }
            position -= 1
        }
        guard let eocd else { throw ZipError.notAnArchive }

        let count = Int(reader.u16(eocd + 10))
        var offset = Int(reader.u32(eocd + 16))
        guard offset < data.count else { throw ZipError.damaged }

        var entries: [String: Entry] = [:]
        for _ in 0..<count {
            guard offset + 46 <= data.count, reader.u32(offset) == 0x0201_4B50 else { throw ZipError.damaged }
            let method = reader.u16(offset + 10)
            let compressed = Int(reader.u32(offset + 20))
            let uncompressed = Int(reader.u32(offset + 24))
            let nameLength = Int(reader.u16(offset + 28))
            let extraLength = Int(reader.u16(offset + 30))
            let commentLength = Int(reader.u16(offset + 32))
            let local = Int(reader.u32(offset + 42))
            guard offset + 46 + nameLength <= data.count else { throw ZipError.damaged }
            let nameData = reader.slice(offset + 46, nameLength)
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            if !name.hasSuffix("/") {
                entries[name] = Entry(path: name, method: method, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: local)
            }
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// The entry at `path`, matched exactly, then without percent-encoding, then ignoring case.
    func entry(_ path: String) -> Entry? {
        if let entry = entries[path] { return entry }
        if let decoded = path.removingPercentEncoding, let entry = entries[decoded] { return entry }
        let lowered = (path.removingPercentEncoding ?? path).lowercased()
        return entries.first { $0.key.lowercased() == lowered }?.value
    }

    func contains(_ path: String) -> Bool { entry(path) != nil }

    /// The uncompressed contents of the file at `path`.
    func contents(of path: String) throws -> Data {
        guard let entry = entry(path) else { throw ZipError.missingEntry(path) }
        let reader = ByteReader(data: data)
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, reader.u32(header) == 0x0403_4B50 else { throw ZipError.damaged }
        let start = header + 30 + Int(reader.u16(header + 26)) + Int(reader.u16(header + 28))
        guard start + entry.compressedSize <= data.count else { throw ZipError.damaged }
        let compressed = reader.slice(start, entry.compressedSize)

        switch entry.method {
        case 0:
            return compressed
        case 8:
            return try Self.inflate(compressed, size: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    func text(of path: String) throws -> String {
        let data = try contents(of: path)
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    /// Raw DEFLATE (what ZIP stores) is what the Compression framework calls ZLIB.
    private static func inflate(_ input: Data, size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        guard !input.isEmpty else { throw ZipError.damaged }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            input.withUnsafeBytes { source -> Int in
                guard let to = destination.bindMemory(to: UInt8.self).baseAddress,
                      let from = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(to, size, from, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError.damaged }
        return output
    }
}

/// Little-endian reads from Data at offsets from its start.
nonisolated private struct ByteReader {
    let data: Data

    func u16(_ offset: Int) -> UInt16 {
        let i = data.startIndex + offset
        return UInt16(data[i]) | UInt16(data[i + 1]) << 8
    }

    func u32(_ offset: Int) -> UInt32 {
        let i = data.startIndex + offset
        return UInt32(data[i]) | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2]) << 16 | UInt32(data[i + 3]) << 24
    }

    func slice(_ offset: Int, _ length: Int) -> Data {
        let start = data.startIndex + offset
        return data.subdata(in: start..<(start + length))
    }
}
