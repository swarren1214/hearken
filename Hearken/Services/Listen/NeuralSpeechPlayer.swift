import AVFoundation
import UIKit

/// Plays Kokoro speech verse by verse: generates a few verses ahead, schedules each as its own
/// buffer, and reports when each verse starts and finishes so the reader can follow along.
///
/// Speed is applied on playback (a time-pitch unit), so changing it is instant and keeps the
/// voice's pitch. While the app is in the foreground it generates further ahead on the GPU;
/// in the background iOS doesn't allow GPU work, so it carries on with the CPU.
@MainActor
final class NeuralSpeechPlayer {
    struct Item {
        let index: Int
        let text: String
    }

    var onStart: (Int) -> Void = { _ in }
    var onFinish: (Int) -> Void = { _ in }
    /// The real length of a verse once it's generated (seconds at 1×).
    var onDuration: (Int, Double) -> Void = { _, _ in }
    /// Generation failed (e.g. the model couldn't load); the engine falls back to system voices.
    var onError: (Int) -> Void = { _ in }

    private(set) var isRunning = false
    private(set) var isPaused = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let samplePlayer = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroSynth.sampleRate, channels: 1)!

    private var generation = 0
    private var producer: Task<Void, Never>?
    /// Verses scheduled and not yet finished, in play order.
    private var scheduled: [Int] = []
    private var playing: Int?

    init() {
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(samplePlayer)
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.connect(samplePlayer, to: engine.mainMixerNode, format: format)
    }

    func start(_ items: [Item], voice: String, speed: Double, pause: Double) {
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
            await self?.produce(items, voice: voice, pause: pause, generation: current)
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
        player.stop()
        scheduled = []
        playing = nil
        isRunning = false
        isPaused = false
    }

    func setSpeed(_ speed: Double) {
        timePitch.rate = Float(speed)
    }

    /// A short sample in a voice (Settings › Listening).
    func playSample(_ text: String, voice: String) {
        Task {
            guard let samples = try? await KokoroSynth.shared.synthesize(KokoroText.prepare(text), voice: voice, gpu: isForeground),
                  let buffer = makeBuffer(samples, trailingSilence: 0) else { return }
            startEngine()
            samplePlayer.stop()
            samplePlayer.scheduleBuffer(buffer, at: nil, options: .interrupts)
            samplePlayer.play()
        }
    }

    // MARK: Generating

    private var isForeground: Bool { UIApplication.shared.applicationState != .background }

    /// How many verses to keep ready: lots while the GPU is available, a couple in the background.
    private var lookahead: Int { isForeground ? 8 : 2 }

    private func produce(_ items: [Item], voice: String, pause: Double, generation current: Int) async {
        for (position, item) in items.enumerated() {
            while scheduled.count >= lookahead {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, current == generation else { return }
            }
            let samples: [Float]
            do {
                samples = try await KokoroSynth.shared.synthesize(item.text, voice: voice, gpu: isForeground)
            } catch {
                guard current == generation else { return }
                onError(item.index)
                return
            }
            guard !Task.isCancelled, current == generation else { return }
            let isLast = position == items.count - 1
            guard let buffer = makeBuffer(samples, trailingSilence: isLast ? 0 : pause) else { continue }
            onDuration(item.index, Double(samples.count) / KokoroSynth.sampleRate + (isLast ? 0 : pause))
            schedule(buffer, index: item.index, generation: current)
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer, index: Int, generation current: Int) {
        scheduled.append(index)
        if playing == nil {
            playing = index
            onStart(index)
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.played(index, generation: current) }
        }
        if !isPaused, !player.isPlaying {
            startEngine()
            player.play()
        }
    }

    private func played(_ index: Int, generation current: Int) {
        guard current == generation, let first = scheduled.first, first == index else { return }
        scheduled.removeFirst()
        onFinish(index)
        playing = scheduled.first
        if let next = playing { onStart(next) }
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
        guard !engine.isRunning else { return }
        engine.prepare()
        try? engine.start()
    }
}
