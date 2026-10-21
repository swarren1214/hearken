import AVFoundation
import UIKit

/// Plays Kokoro speech verse by verse, and reports when each verse starts and finishes so the
/// reader can follow along.
///
/// Each verse (or an imported book's paragraph, which can run to several minutes) is split into
/// sentence groups of a few hundred characters. Each group is generated and scheduled as its own
/// buffer, so playback starts after the first sentence or two rather than the whole paragraph,
/// and it stays only about half a minute of audio ahead, which keeps memory and GPU work small
/// however long a paragraph is.
///
/// Speed is applied on playback (a time-pitch unit), so changing it is instant and keeps the
/// voice's pitch. While the app is in the foreground it generates further ahead on the GPU;
/// in the background iOS doesn't allow GPU work, so it carries on with the CPU.
@MainActor
final class NeuralSpeechPlayer {
    struct Item {
        let index: Int
        /// The verse's text, as read aloud; the player prepares it for Kokoro.
        let text: String
    }

    /// A scheduled buffer: one sentence group of a verse.
    private struct Segment {
        let index: Int
        let isFirst: Bool
        let isLast: Bool
        let seconds: Double
    }

    var onStart: (Int) -> Void = { _ in }
    var onFinish: (Int) -> Void = { _ in }
    /// The real length of a verse once it's generated (seconds at 1×).
    var onDuration: (Int, Double) -> Void = { _, _ in }
    /// Generation failed (e.g. the model couldn't load); the engine falls back to system voices.
    var onError: (Int, String) -> Void = { _, _ in }

    private(set) var isRunning = false
    private(set) var isPaused = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let samplePlayer = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroSynth.sampleRate, channels: 1)!

    private var generation = 0
    private var sampleGeneration = 0
    private var producer: Task<Void, Never>?
    /// Segments scheduled and not yet played, in play order.
    private var scheduled: [Segment] = []
    /// The verse last reported as started.
    private var playing: Int?

    /// Whether the nodes are attached and connected. Done on first use, not in init: touching
    /// `mainMixerNode` stands up the audio I/O unit and waits on the system audio server, and
    /// ListenEngine is created during launch. When the Watch or Siri launches Hearken in the
    /// background, that wait blocked launch long enough for iOS to suspend the app mid-launch
    /// and kill it (0xdead10cc, build 21).
    private var graphReady = false

    init() {}

    private func buildGraphIfNeeded() {
        guard !graphReady else { return }
        graphReady = true
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(samplePlayer)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.connect(samplePlayer, to: engine.mainMixerNode, format: format)
    }

    func start(_ items: [Item], voice: String, tuning: VoiceTuning, speed: Double, pause: Double) {
        stop()
        guard !items.isEmpty else { return }
        generation += 1
        let current = generation
        isRunning = true
        isPaused = false
        timePitch.rate = Float(speed)
        startEngine()
        player.play()
        producer = Task { [weak self] in
            await self?.produce(items, voice: voice, tuning: tuning, pause: pause, generation: current)
        }
    }

    func pause() {
        guard isRunning else { return }
        player.pause()
        isPaused = true
    }

    func resume() {
        guard isRunning else { return }
        startEngine()
        player.play()
        isPaused = false
    }

    func stop() {
        generation += 1
        producer?.cancel()
        producer = nil
        // Nothing to stop before the graph exists (stop() runs at the top of every start()).
        if graphReady { player.stop() }
        scheduled = []
        playing = nil
        isRunning = false
        isPaused = false
    }

    func setSpeed(_ speed: Double) {
        timePitch.rate = Float(speed)
    }

    /// A short sample in a voice (Settings › Listening).
    /// Tells the caller when the sample starts (after it's generated) and ends, or why it failed.
    func playSample(
        _ text: String, voice: String, tuning: VoiceTuning,
        onStart: @escaping () -> Void, onEnd: @escaping () -> Void, onError: @escaping (String) -> Void
    ) {
        sampleGeneration += 1
        let current = sampleGeneration
        if graphReady { samplePlayer.stop() }
        Task {
            let samples: [Float]
            do {
                samples = try await KokoroSynth.shared.synthesize(KokoroText.prepare(text), voice: voice, tuning: tuning, gpu: isForeground)
            } catch {
                if current == sampleGeneration { onError(FriendlyError.voicePlayback(error)) }
                return
            }
            guard current == sampleGeneration else { return }
            guard let buffer = makeBuffer(samples, trailingSilence: 0) else {
                onError("The voice didn't produce any sound.")
                return
            }
            startEngine()
            samplePlayer.scheduleBuffer(buffer, at: nil, options: .interrupts, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    if current == self.sampleGeneration { onEnd() }
                }
            }
            samplePlayer.play()
            onStart()
        }
    }

    func stopSample() {
        sampleGeneration += 1
        if graphReady { samplePlayer.stop() }
    }

    // MARK: Generating

    private var isForeground: Bool { UIApplication.shared.applicationState != .background }

    /// How much audio to keep generated ahead of what's playing: enough to ride out a slow
    /// sentence, without holding minutes of samples. Less in the background, where only the
    /// CPU is available.
    private var secondsAhead: Double { isForeground ? 30 : 15 }
    private static let maxSegmentsAhead = 12
    /// The breath between sentence groups inside one verse or paragraph.
    private static let segmentGap = 0.12

    private var scheduledSeconds: Double { scheduled.reduce(0) { $0 + $1.seconds } }

    private func produce(_ items: [Item], voice: String, tuning: VoiceTuning, pause: Double, generation current: Int) async {
        for (position, item) in items.enumerated() {
            guard !Task.isCancelled, current == generation else { return }
            let pieces = KokoroText.chunks(KokoroText.prepare(item.text))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !pieces.isEmpty else { continue }
            let isLastItem = position == items.count - 1
            var itemSeconds = 0.0

            for (number, piece) in pieces.enumerated() {
                // Wait while enough is already queued.
                while !scheduled.isEmpty, scheduledSeconds >= secondsAhead || scheduled.count >= Self.maxSegmentsAhead {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled, current == generation else { return }
                }
                let samples: [Float]
                do {
                    samples = try await KokoroSynth.shared.synthesize(piece, voice: voice, tuning: tuning, gpu: isForeground)
                } catch {
                    guard current == generation else { return }
                    onError(item.index, FriendlyError.voicePlayback(error))
                    return
                }
                guard !Task.isCancelled, current == generation else { return }

                let isLastPiece = number == pieces.count - 1
                let silence = isLastPiece ? (isLastItem ? 0 : pause) : Self.segmentGap
                guard let buffer = makeBuffer(samples, trailingSilence: silence) else { continue }
                let seconds = Double(samples.count) / KokoroSynth.sampleRate + silence
                itemSeconds += seconds
                if isLastPiece { onDuration(item.index, itemSeconds) }
                schedule(buffer, segment: Segment(index: item.index, isFirst: number == 0, isLast: isLastPiece, seconds: seconds), generation: current)
            }
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, segment: Segment, generation current: Int) {
        scheduled.append(segment)
        if scheduled.count == 1 { begin(segment.index) }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.played(generation: current) }
        }
        if !isPaused, !player.isPlaying {
            startEngine()
            player.play()
        }
    }

    private func played(generation current: Int) {
        guard current == generation, !scheduled.isEmpty else { return }
        let finished = scheduled.removeFirst()
        if finished.isLast { onFinish(finished.index) }
        if let next = scheduled.first { begin(next.index) }
    }

    /// Reports a verse as started once, however many segments it has.
    private func begin(_ index: Int) {
        guard playing != index else { return }
        playing = index
        onStart(index)
    }

    private func makeBuffer(_ samples: [Float], trailingSilence: Double) -> AVAudioPCMBuffer? {
        let silence = Int(trailingSilence * KokoroSynth.sampleRate)
        let frames = samples.count + silence
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { source in
            if let base = source.baseAddress { channel.update(from: base, count: samples.count) }
        }
        if silence > 0 { (channel + samples.count).update(repeating: 0, count: silence) }
        return buffer
    }

    private func startEngine() {
        buildGraphIfNeeded()
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }
}
