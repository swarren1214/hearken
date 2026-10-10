import CryptoKit
import Foundation
import KokoroSwift
import MLX
import Observation
import UIKit

// Natural voices: the Kokoro neural voice model running on the device (MLX on the GPU, or the
// CPU while the app is in the background, where iOS doesn't allow GPU work).
//
// The model (~330 MB, Apache 2.0) is downloaded from Hugging Face the first time; the 27 voice
// styles (~14 MB) ship in the app as Resources/Kokoro/kokoro-voices.bin.

// MARK: - Voices

nonisolated enum KokoroVoices {
    struct Voice: Identifiable, Hashable {
        /// Kokoro's name, e.g. "af_heart".
        let id: String
        let name: String
        let detail: String
        /// Position in kokoro-voices.bin.
        let slot: Int
    }

    /// In the order they're packed in kokoro-voices.bin (510 × 1 × 256 float32 each).
    private static let packed = [
        "af_heart", "af_bella", "af_nicole", "af_aoede", "af_kore", "af_sarah", "af_nova", "af_sky",
        "af_alloy", "af_jessica", "af_river", "am_michael", "am_fenrir", "am_puck", "am_echo", "am_eric",
        "am_liam", "am_onyx", "am_santa", "am_adam", "bf_emma", "bf_isabella", "bf_alice", "bf_lily",
        "bm_george", "bm_fable", "bm_lewis", "bm_daniel",
    ]

    /// The default: warm and clear for long reading.
    static let defaultID = "af_heart"

    static let all: [Voice] = packed.enumerated().compactMap { slot, id in
        guard id != "am_santa" else { return nil }
        let accent = id.hasPrefix("b") ? "British" : "American"
        let gender = id.dropFirst().first == "m" ? "male" : "female"
        let name = id.split(separator: "_").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? id
        return Voice(id: id, name: name, detail: "\(accent) English, \(gender)", slot: slot)
    }

    static func voice(_ id: String) -> Voice? { all.first { $0.id == id } }

    /// Featured first in Settings; the rest follow.
    static let featured = ["af_heart", "af_bella", "am_michael", "am_adam", "bf_emma", "bm_george", "bm_lewis"]
}

// MARK: - Model download

/// The Kokoro model on this device: whether it's here, downloading, or can't run.
@MainActor
@Observable
final class KokoroModel: NSObject {
    static let shared = KokoroModel()

    enum State: Equatable {
        /// The Simulator (MLX needs a real device's GPU).
        case unavailable
        case notDownloaded
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state: State = .notDownloaded

    /// Where to get the Kokoro v1.0 weights for MLX: Hugging Face first, then the copy in
    /// KokoroSwift's sample app on GitHub. Either is accepted only if it's byte-for-byte the
    /// file KokoroSwift is tested with (checked by SHA-256 below).
    static let remoteURLs = [
        URL(string: "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors")!,
        URL(string: "https://media.githubusercontent.com/media/mlalma/KokoroTestApp/main/Resources/kokoro-v1_0.safetensors")!,
    ]
    /// SHA-256 of the tested kokoro-v1_0.safetensors (327,115,152 bytes).
    nonisolated static let expectedSHA256 = "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"
    /// Roughly 330 MB; shown before downloading.
    static let approximateSize = "330 MB"

    nonisolated static var localURL: URL {
        let folder = URL.applicationSupportDirectory.appending(path: "Kokoro", directoryHint: .isDirectory)
        return folder.appending(path: "kokoro-v1_0.safetensors")
    }

    private enum Keys {
        /// Set while the model loads; still set at launch means loading crashed last time.
        static let loading = "kokoro.loading"
        static let broken = "kokoro.broken"
    }

    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var task: URLSessionDownloadTask?
    @ObservationIgnored private var sourceIndex = 0

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        state = .unavailable
        #else
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Keys.loading) {
            // The app quit while loading the model last time: don't try again automatically.
            defaults.set(false, forKey: Keys.loading)
            defaults.set(true, forKey: Keys.broken)
        }
        if defaults.bool(forKey: Keys.broken) {
            state = .failed("The natural voice couldn't load on this device.")
        } else if FileManager.default.fileExists(atPath: Self.localURL.path()) {
            state = .ready
        }
        #endif
    }

    var isReady: Bool { state == .ready }

    /// Starts the download. `wifiOnly` keeps it off cellular (used when it starts on its own).
    func download(wifiOnly: Bool = false) {
        switch state {
        case .notDownloaded, .failed: break
        default: return
        }
        UserDefaults.standard.set(false, forKey: Keys.broken)
        let configuration = URLSessionConfiguration.default
        configuration.allowsExpensiveNetworkAccess = !wifiOnly
        configuration.allowsConstrainedNetworkAccess = !wifiOnly
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        sourceIndex = 0
        state = .downloading(0)
        startTask()
    }

    private func startTask() {
        guard let session, Self.remoteURLs.indices.contains(sourceIndex) else { return }
        let task = session.downloadTask(with: Self.remoteURLs[sourceIndex])
        self.task = task
        task.resume()
    }

    /// This source failed or sent a different file: try the next one, if there is one.
    fileprivate func tryNextSource(or error: String) {
        if sourceIndex + 1 < Self.remoteURLs.count {
            sourceIndex += 1
            state = .downloading(0)
            startTask()
        } else {
            finished(error: error)
        }
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        state = .notDownloaded
    }

    /// Frees the space; Listen falls back to the system voices.
    func remove() {
        cancelDownload()
        KokoroSynth.shared.unload()
        try? FileManager.default.removeItem(at: Self.localURL)
        UserDefaults.standard.set(false, forKey: Keys.broken)
        state = .notDownloaded
    }

    nonisolated static func markLoading(_ loading: Bool) {
        UserDefaults.standard.set(loading, forKey: Keys.loading)
    }

    fileprivate func finished(error: String?) {
        session?.finishTasksAndInvalidate()
        session = nil
        task = nil
        if let error {
            state = .failed(error)
        } else {
            state = .ready
            ListenEngine.shared.voiceAvailabilityChanged()
        }
    }

    fileprivate func progressed(_ fraction: Double) {
        if case .downloading = state { state = .downloading(fraction) }
    }
}

extension KokoroModel: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in KokoroModel.shared.progressed(fraction) }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The temporary file is deleted when this returns, so check and move it now.
        var error: String?
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 200
        if status != 200 || KokoroModel.sha256(of: location) != KokoroModel.expectedSHA256 {
            Task { @MainActor in KokoroModel.shared.tryNextSource(or: "The download didn't finish correctly. Try again.") }
            return
        } else {
            do {
                let destination = KokoroModel.localURL
                var folder = destination.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Re-downloadable, so keep it out of iCloud backups.
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? folder.setResourceValues(values)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: location, to: destination)
            } catch let moveError {
                error = moveError.localizedDescription
            }
        }
        let result = error
        Task { @MainActor in KokoroModel.shared.finished(error: result) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, (error as? URLError)?.code != .cancelled else { return }
        let message = error.localizedDescription
        Task { @MainActor in KokoroModel.shared.tryNextSource(or: message) }
    }

    /// Hashes the file in 4 MB pieces, so it never needs the whole model in memory.
    nonisolated static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Synthesis

/// Runs Kokoro on its own queue. Loads the model on first use (a few seconds).
nonisolated final class KokoroSynth: @unchecked Sendable {
    static let shared = KokoroSynth()
    static let sampleRate = Double(KokoroTTS.Constants.samplingRate)

    private let queue = DispatchQueue(label: "com.stephenwarren.hearken.kokoro", qos: .userInitiated)
    private var tts: KokoroTTS?
    private var styles: [String: MLXArray] = [:]
    private var voiceData: Data?

    /// Loads the model ahead of time, so the first verse starts quickly.
    func prewarm() {
        queue.async { [self] in _ = try? loadIfNeeded() }
    }

    func unload() {
        queue.async { [self] in
            tts = nil
            styles = [:]
        }
    }

    /// Speech for `text` as 24 kHz mono samples. `gpu` is false while the app is in the background.
    func synthesize(_ text: String, voice: String, gpu: Bool) async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    let tts = try loadIfNeeded()
                    let style = try style(for: voice)
                    let language: Language = voice.hasPrefix("b") ? .enGB : .enUS
                    var samples: [Float] = []
                    for chunk in KokoroText.chunks(text) {
                        samples += try speak(chunk, tts: tts, style: style, language: language, gpu: gpu)
                    }
                    continuation.resume(returning: samples)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// One chunk; splits it further if Kokoro says it's too long.
    private func speak(_ chunk: String, tts: KokoroTTS, style: MLXArray, language: Language, gpu: Bool) throws -> [Float] {
        do {
            let run = { try tts.generateAudio(voice: style, language: language, text: chunk).0 }
            return gpu ? try run() : try Device.withDefaultDevice(.cpu, run)
        } catch KokoroTTS.KokoroTTSError.tooManyTokens {
            let halves = KokoroText.halves(chunk)
            guard halves.count == 2 else { throw KokoroTTS.KokoroTTSError.tooManyTokens }
            return try speak(halves[0], tts: tts, style: style, language: language, gpu: gpu)
                + speak(halves[1], tts: tts, style: style, language: language, gpu: gpu)
        }
    }

    private func loadIfNeeded() throws -> KokoroTTS {
        if let tts { return tts }
        let url = KokoroModel.localURL
        guard FileManager.default.fileExists(atPath: url.path()) else { throw CocoaError(.fileNoSuchFile) }
        // If loading crashes the app, the flag is still set next launch and natural voices turn off.
        KokoroModel.markLoading(true)
        let loaded = KokoroTTS(modelPath: url, g2p: .misaki)
        KokoroModel.markLoading(false)
        tts = loaded
        return loaded
    }

    private func style(for id: String) throws -> MLXArray {
        if let style = styles[id] { return style }
        guard let voice = KokoroVoices.voice(id) else { throw CocoaError(.fileNoSuchFile) }
        if voiceData == nil {
            let url = Bundle.main.url(forResource: "kokoro-voices", withExtension: "bin")
                ?? Bundle.main.url(forResource: "kokoro-voices", withExtension: "bin", subdirectory: "Kokoro")
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            voiceData = try Data(contentsOf: url, options: .mappedIfSafe)
        }
        guard let voiceData else { throw CocoaError(.fileReadCorruptFile) }
        let count = 510 * 256
        let bytes = count * MemoryLayout<Float>.size
        let start = voice.slot * bytes
        guard voiceData.count >= start + bytes else { throw CocoaError(.fileReadCorruptFile) }
        let floats: [Float] = voiceData.subdata(in: start..<(start + bytes)).withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
        let style = MLXArray(floats, [510, 1, 256])
        styles[id] = style
        return style
    }
}

// MARK: - Text

nonisolated enum KokoroText {
    /// Kokoro reads up to about 510 phonemes at once; sentences of this length stay well under.
    static let chunkLimit = 280

    /// The verse, cleaned, with known names marked in Kokoro's phoneme notation.
    static func prepare(_ text: String) -> String {
        mark(SpeechText.clean(text))
    }

    /// Wraps each known name as [Name](/phonemes/), which Kokoro reads as given.
    private static func mark(_ text: String) -> String {
        let matches = Pronunciations.matches(in: text)
        guard !matches.isEmpty else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for match in matches {
            result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            result += "[\(match.name)](/\(match.entry.kokoro)/)"
            last = match.range.location + match.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    /// Splits at sentence ends, then clause breaks, keeping each piece under `chunkLimit`.
    static func chunks(_ text: String) -> [String] {
        guard text.count > chunkLimit else { return [text] }
        var pieces: [String] = []
        var current = ""
        for sentence in sentences(text) {
            if current.count + sentence.count > chunkLimit, !current.isEmpty {
                pieces.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            current += sentence
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            pieces.append(current.trimmingCharacters(in: .whitespaces))
        }
        return pieces.flatMap { $0.count > chunkLimit * 2 ? halves($0) : [$0] }
    }

    /// Two halves split at the comma (or space) nearest the middle, never inside a [name](/…/) mark.
    static func halves(_ text: String) -> [String] {
        let characters = Array(text)
        guard characters.count > 20 else { return [text] }
        let middle = characters.count / 2
        var inMark = Array(repeating: false, count: characters.count)
        var depth = false
        for (i, c) in characters.enumerated() {
            if c == "[" { depth = true }
            inMark[i] = depth
            if c == ")" { depth = false }
        }
        let candidates = characters.indices.filter { (characters[$0] == "," || characters[$0] == ";") && !inMark[$0] }
        let spaces = characters.indices.filter { characters[$0] == " " && !inMark[$0] }
        guard let cut = (candidates.isEmpty ? spaces : candidates).min(by: { Swift.abs($0 - middle) < Swift.abs($1 - middle) }) else { return [text] }
        let first = String(characters[...cut]).trimmingCharacters(in: .whitespaces)
        let second = String(characters[(cut + 1)...]).trimmingCharacters(in: .whitespaces)
        return [first, second].filter { !$0.isEmpty }
    }

    private static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for c in text {
            current.append(c)
            if ".;:?!".contains(c) {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
