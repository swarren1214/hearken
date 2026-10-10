import AVFoundation
import MediaPlayer
import Observation
import SwiftData
import SwiftUI
import UIKit

/// Where the chapters being listened to came from.
enum ListenSource: Equatable {
    /// One chapter, then (with Continue on) the next chapter in the book.
    case book
    /// Today's reading in the plan: plays those chapters in order, then stops.
    case plan
}

/// Settings › Listening and the player's moon button.
enum ListenSleep: Hashable, Identifiable {
    case off, minutes(Int), endOfChapter

    var id: String { title }
    static let options: [ListenSleep] = [.off, .minutes(15), .minutes(30), .minutes(45), .endOfChapter]

    var title: String {
        switch self {
        case .off: "Off"
        case .minutes(let minutes): "\(minutes) Minutes"
        case .endOfChapter: "End of Chapter"
        }
    }
}

/// A chapter heard to the end, for ListenSideEffects to mark as read.
struct FinishedChapter: Equatable {
    let chapterID: String
    let token = UUID()
}

/// Listen mode: reads chapters aloud verse by verse with a system voice, like an audiobook.
///
/// One utterance per verse, so the reader can light up the verse being spoken and the
/// scrubber can jump by verse. Keeps playing in the background and on the lock screen
/// (UIBackgroundModes: audio), and answers the lock screen, Control Center and AirPods.
@MainActor
@Observable
final class ListenEngine: NSObject {
    static let shared = ListenEngine()

    // MARK: Session

    /// The chapter being listened to; nil when Listen mode is off.
    private(set) var chapterID: String?
    private(set) var verses: [Verse] = []
    /// Index into `verses` of the verse being spoken (or next up, when paused).
    private(set) var index = 0
    private(set) var isPlaying = false
    /// Chapters queued after this one (today's plan).
    private(set) var upNext: [String] = []
    private(set) var source: ListenSource = .book
    private(set) var sleep: ListenSleep = .off
    private(set) var sleepDeadline: Date?
    /// Set when a chapter is heard to the end (at least half its verses spoken).
    private(set) var finished: FinishedChapter?
    /// The full player sheet.
    var showsPlayer = false

    // MARK: Settings (saved)

    private(set) var speed: Double
    private(set) var voiceID: String?
    private(set) var versePause: VersePause
    private(set) var readsVerseNumbers: Bool
    private(set) var autoContinue: Bool
    /// Pace and expressiveness for the natural voices.
    private(set) var tuning: VoiceTuning

    var isActive: Bool { chapterID != nil }
    var verseCount: Int { verses.count }
    var currentVerse: Int? { verses.indices.contains(index) ? verses[index].number : nil }
    var title: String { chapterID.map { scripture.title(forChapter: $0) } ?? "" }
    var bookTitle: String { chapterID.map { LibraryCatalog.location(ofChapter: $0)?.work.title ?? scripture.bookTitle(forChapter: $0) } ?? "" }

    /// What plays after this chapter, if anything.
    var nextChapterID: String? {
        autoContinue ? followingChapterID : nil
    }

    /// The chapter Continue would play next: the plan's next chapter, or the next in the book.
    var followingChapterID: String? {
        guard let chapterID else { return nil }
        if let next = upNext.first { return next }
        return source == .book ? LibraryCatalog.adjacentChapter(to: chapterID, offset: 1) : nil
    }

    /// Estimated seconds left in this chapter, from the current verse.
    var secondsLeft: Double {
        guard verses.indices.contains(index) else { return 0 }
        return verseSeconds[index...].reduce(0, +)
    }
    var secondsElapsed: Double { verseSeconds.prefix(index).reduce(0, +) }
    var chapterSeconds: Double { verseSeconds.reduce(0, +) }

    var voiceName: String {
        if let natural = naturalVoiceID { return KokoroVoices.voice(natural)?.name ?? "Natural" }
        guard let voice = resolvedVoice else { return "Voice" }
        return ListenVoices.tier(of: voice) == .personal ? "Personal Voice" : voice.name
    }

    /// The Kokoro voice to read with, when the natural voice model is on this device. With no
    /// choice saved yet, natural voices win over the system ones.
    var naturalVoiceID: String? {
        guard KokoroModel.shared.isReady, !naturalVoiceFailed else { return nil }
        guard let voiceID else { return KokoroVoices.defaultID }
        return voiceID.hasPrefix(Self.naturalPrefix) ? String(voiceID.dropFirst(Self.naturalPrefix.count)) : nil
    }

    /// Saved voice IDs for Kokoro voices look like "kokoro:af_heart".
    static let naturalPrefix = "kokoro:"

    // MARK: Internals

    @ObservationIgnored private var contentService: ContentService?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// The utterances queued now, by identity, mapped to their verse index.
    @ObservationIgnored private var queued: [ObjectIdentifier: (utterance: AVSpeechUtterance, index: Int)] = [:]
    @ObservationIgnored private var spoken = Set<Int>()
    @ObservationIgnored private var verseSeconds: [Double] = []
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var commandsInstalled = false
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var artworkWorkID: String?
    /// Plays a voice sample from Settings without touching the session.
    @ObservationIgnored private let sampler = AVSpeechSynthesizer()
    /// Kokoro playback, used instead of the synthesizer when a natural voice is chosen.
    @ObservationIgnored private let neural = NeuralSpeechPlayer()
    /// Set if Kokoro fails this session (e.g. out of memory); the system voice takes over.
    @ObservationIgnored private var naturalVoiceFailed = false

    private enum Keys {
        static let speed = "listen.speed"
        static let voice = "listen.voice"
        static let pause = "listen.pause"
        static let numbers = "listen.readsVerseNumbers"
        static let autoContinue = "listen.autoContinue"
        static let pace = "listen.pace"
        static let expressiveness = "listen.expressiveness"
        static let position = "listen.position"
    }

    override init() {
        let defaults = UserDefaults.standard
        speed = defaults.object(forKey: Keys.speed) as? Double ?? 1
        voiceID = defaults.string(forKey: Keys.voice)
        versePause = VersePause(rawValue: defaults.string(forKey: Keys.pause) ?? "") ?? .short
        readsVerseNumbers = defaults.bool(forKey: Keys.numbers)
        autoContinue = defaults.object(forKey: Keys.autoContinue) as? Bool ?? true
        tuning = VoiceTuning(
            pace: defaults.object(forKey: Keys.pace) as? Double ?? 1,
            expressiveness: defaults.object(forKey: Keys.expressiveness) as? Double ?? 1
        )
        super.init()
        synthesizer.delegate = self
        // The app sets up and activates the audio session itself (spoken audio, background).
        synthesizer.usesApplicationAudioSession = true
        observeAudioSession()
        neural.onStart = { [weak self] index in self?.verseStarted(index) }
        neural.onFinish = { [weak self] index in self?.verseFinished(index) }
        neural.onDuration = { [weak self] index, seconds in
            guard let self, self.verseSeconds.indices.contains(index) else { return }
            self.verseSeconds[index] = seconds / self.speed
        }
        neural.onError = { [weak self] index in
            guard let self else { return }
            self.naturalVoiceFailed = true
            if self.isPlaying { self.speak(from: index) }
        }
    }

    /// The natural voice model finished downloading: switch to it, from the verse being read.
    func voiceAvailabilityChanged() {
        naturalVoiceFailed = false
        if isPlaying, !neural.isRunning, naturalVoiceID != nil { speak(from: index) }
    }

    /// The app's ContentService (one is made on demand, e.g. for a Siri request in the background).
    var scripture: ContentService {
        if let contentService { return contentService }
        let made = ContentService()
        contentService = made
        return made
    }

    func attach(content: ContentService) {
        if contentService == nil || !isActive { contentService = content }
    }

    /// The app's data store, for marking chapters read (set at launch, before any UI).
    @ObservationIgnored private var modelContainer: ModelContainer?

    func attach(container: ModelContainer) {
        modelContainer = container
    }

    /// Hearing a chapter to the end counts the same as reading it (same XP, same streak).
    private func markRead(_ chapterID: String) {
        guard let context = modelContainer?.mainContext else { return }
        let id = chapterID
        let descriptor = FetchDescriptor<ReadingProgress>(predicate: #Predicate { $0.chapterID == id })
        let record = (try? context.fetch(descriptor).first) ?? {
            let new = ReadingProgress(chapterID: chapterID)
            context.insert(new)
            return new
        }()
        MasteryService().setChapterRead(true, progress: record, in: context)
        try? context.save()
    }

    // MARK: Starting and stopping

    /// Starts listening to `chapterIDs` in order, from `verse` in the first one.
    func start(chapterIDs: [String], fromVerse verse: Int? = nil, source: ListenSource = .book) {
        guard let first = chapterIDs.first else { return }
        upNext = Array(chapterIDs.dropFirst())
        self.source = source
        // Skip chapters whose text isn't imported yet.
        var loaded = load(first, fromVerse: verse)
        while !loaded, !upNext.isEmpty {
            loaded = load(upNext.removeFirst(), fromVerse: nil)
        }
        guard loaded else { return }
        play()
        // Natural voices download on their own over Wi-Fi the first time someone listens.
        if KokoroModel.shared.state == .notDownloaded { KokoroModel.shared.download(wifiOnly: true) }
    }

    /// Listen to one chapter (from the reader or the Library), continuing through the book.
    func start(chapterID: String, fromVerse verse: Int? = nil) {
        start(chapterIDs: [chapterID], fromVerse: verse, source: .book)
    }

    func stop() {
        stopSpeech()
        isPlaying = false
        chapterID = nil
        verses = []
        index = 0
        upNext = []
        showsPlayer = false
        setSleep(.off)
        UserDefaults.standard.removeObject(forKey: Keys.position)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// After a relaunch, offers the last chapter again (paused) if it was within the last 12 hours.
    func restoreIfRecent() {
        guard !isActive,
              let saved = UserDefaults.standard.dictionary(forKey: Keys.position),
              let id = saved["chapterID"] as? String,
              let verse = saved["verse"] as? Int,
              let date = saved["date"] as? Date,
              Date.now.timeIntervalSince(date) < 12 * 3600 else { return }
        upNext = saved["upNext"] as? [String] ?? []
        source = (saved["plan"] as? Bool ?? false) ? .plan : .book
        // Keep the saved time, so the 12 hours count from when listening stopped.
        _ = load(id, fromVerse: verse, save: false)
        updateNowPlaying()
    }

    // MARK: Transport

    func play() {
        guard isActive else { return }
        activateSession()
        installRemoteCommands()
        if reachedEnd {
            reachedEnd = false
            index = 0
        }
        isPlaying = true
        if neural.isRunning, neural.isPaused {
            neural.resume()
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            speak(from: index)
        }
        updateNowPlaying()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        if neural.isRunning { neural.pause() } else { synthesizer.pauseSpeaking(at: .word) }
        updateNowPlaying()
        savePosition()
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    /// Jump to a verse by its index in the chapter.
    func seek(toIndex target: Int) {
        guard !verses.isEmpty else { return }
        index = min(max(target, 0), verses.count - 1)
        reachedEnd = false
        if isPlaying {
            speak(from: index)
        } else {
            stopSpeech()
        }
        updateNowPlaying()
        savePosition()
    }

    func seek(toVerse number: Int) {
        guard let target = verses.firstIndex(where: { $0.number == number }) else { return }
        seek(toIndex: target)
    }

    func nextVerse() {
        if index + 1 < verses.count {
            seek(toIndex: index + 1)
        } else {
            nextChapter()
        }
    }

    func previousVerse() {
        seek(toIndex: index - 1)
    }

    func nextChapter() {
        guard let chapterID else { return }
        let next = upNext.first ?? LibraryCatalog.adjacentChapter(to: chapterID, offset: 1)
        if !upNext.isEmpty { upNext.removeFirst() }
        guard let next else { return }
        let wasPlaying = isPlaying
        guard load(next, fromVerse: nil) else { return }
        if wasPlaying { play() } else { updateNowPlaying() }
    }

    /// Back to the start of this chapter, or (already near the start) the previous chapter.
    func previousChapter() {
        guard let chapterID else { return }
        if index > 1 {
            seek(toIndex: 0)
            return
        }
        guard let previous = LibraryCatalog.adjacentChapter(to: chapterID, offset: -1) else {
            seek(toIndex: 0)
            return
        }
        let wasPlaying = isPlaying
        guard load(previous, fromVerse: nil) else { return }
        if wasPlaying { play() } else { updateNowPlaying() }
    }

    func setSleep(_ option: ListenSleep) {
        sleepTask?.cancel()
        sleepTask = nil
        sleep = option
        sleepDeadline = nil
        if case .minutes(let minutes) = option {
            let deadline = Date.now.addingTimeInterval(Double(minutes) * 60)
            sleepDeadline = deadline
            sleepTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Double(minutes) * 60))
                guard !Task.isCancelled, let self else { return }
                self.pause()
                self.sleep = .off
                self.sleepDeadline = nil
            }
        }
    }

    // MARK: Settings

    func setSpeed(_ value: Double) {
        speed = value
        UserDefaults.standard.set(value, forKey: Keys.speed)
        if neural.isRunning {
            // Natural voices change speed on playback, instantly, without regenerating.
            neural.setSpeed(value)
            verseSeconds = verses.map { SpeechText.seconds(for: $0, speed: speed, pause: versePause) }
            updateNowPlaying()
            return
        }
        settingsChanged()
    }

    func setVoice(_ id: String?) {
        voiceID = id
        UserDefaults.standard.set(id, forKey: Keys.voice)
        settingsChanged()
    }

    func setVersePause(_ value: VersePause) {
        versePause = value
        UserDefaults.standard.set(value.rawValue, forKey: Keys.pause)
        settingsChanged()
    }

    func setReadsVerseNumbers(_ value: Bool) {
        readsVerseNumbers = value
        UserDefaults.standard.set(value, forKey: Keys.numbers)
        settingsChanged()
    }

    /// Natural voices only: regenerates from the verse being read.
    func setPace(_ value: Double) {
        tuning.pace = value
        UserDefaults.standard.set(value, forKey: Keys.pace)
        if neural.isRunning, isPlaying { speak(from: index) } else if neural.isRunning { stopSpeech() }
    }

    func setExpressiveness(_ value: Double) {
        tuning.expressiveness = value
        UserDefaults.standard.set(value, forKey: Keys.expressiveness)
        if neural.isRunning, isPlaying { speak(from: index) } else if neural.isRunning { stopSpeech() }
    }

    func setAutoContinue(_ value: Bool) {
        autoContinue = value
        UserDefaults.standard.set(value, forKey: Keys.autoContinue)
    }

    /// Speaks a short sample in `voiceID` (Settings › Listening).
    func playSample(voiceID: String) {
        let sample = "And now as I said concerning faith—faith is not to have a perfect knowledge of things."
        if voiceID.hasPrefix(Self.naturalPrefix) {
            if !isPlaying { activateSession() }
            neural.playSample(sample, voice: String(voiceID.dropFirst(Self.naturalPrefix.count)), tuning: tuning)
            return
        }
        sampler.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: "And now as I said concerning faith—faith is not to have a perfect knowledge of things.")
        utterance.voice = AVSpeechSynthesisVoice(identifier: voiceID)
        utterance.rate = SpeechText.rate(for: speed)
        if !isPlaying { activateSession() }
        sampler.speak(utterance)
    }

    /// Asks to use the person's Personal Voice; true when allowed.
    func requestPersonalVoice() async -> Bool {
        await withCheckedContinuation { continuation in
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    var personalVoiceStatus: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus {
        AVSpeechSynthesizer.personalVoiceAuthorizationStatus
    }

    private var resolvedVoice: AVSpeechSynthesisVoice? {
        voiceID.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? ListenVoices.best()
    }

    /// Speed and voice apply from the verse being spoken.
    private func settingsChanged() {
        verseSeconds = verses.map { SpeechText.seconds(for: $0, speed: speed, pause: versePause) }
        if isPlaying { speak(from: index) } else if isActive { stopSpeech() }
        updateNowPlaying()
    }

    // MARK: Speaking

    /// Loads a chapter; false (and nothing changes) if its text isn't available.
    @discardableResult
    private func load(_ id: String, fromVerse verse: Int?, save: Bool = true) -> Bool {
        guard let chapter = scripture.chapter(id), !chapter.verses.isEmpty else { return false }
        stopSpeech()
        chapterID = id
        verses = chapter.verses
        index = verse.flatMap { number in chapter.verses.firstIndex { $0.number == number } } ?? 0
        spoken = []
        reachedEnd = false
        verseSeconds = verses.map { SpeechText.seconds(for: $0, speed: speed, pause: versePause) }
        makeArtwork(for: id)
        if save { savePosition() }
        return true
    }

    /// Queues the rest of the chapter from `start`, replacing anything queued before.
    private func speak(from start: Int) {
        stopSpeech()
        guard verses.indices.contains(start) else { return }
        if let natural = naturalVoiceID {
            let items = (start..<verses.count).map { position in
                let verse = verses[position]
                let text = (readsVerseNumbers ? "Verse \(verse.number). " : "") + verse.text
                return NeuralSpeechPlayer.Item(index: position, text: KokoroText.prepare(text))
            }
            neural.start(items, voice: natural, tuning: tuning, speed: speed, pause: versePause.seconds)
            return
        }
        let voice = resolvedVoice
        for position in start..<verses.count {
            let utterance = SpeechText.utterance(
                for: verses[position],
                readsNumber: readsVerseNumbers,
                voice: voice,
                speed: speed,
                pause: versePause,
                isFirst: position == start
            )
            queued[ObjectIdentifier(utterance)] = (utterance, position)
            synthesizer.speak(utterance)
        }
    }

    private func stopSpeech() {
        neural.stop()
        queued = [:]
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    fileprivate func didStart(_ id: ObjectIdentifier) {
        guard let entry = queued[id] else { return }
        verseStarted(entry.index)
    }

    fileprivate func didFinish(_ id: ObjectIdentifier) {
        guard let entry = queued.removeValue(forKey: id) else { return }
        verseFinished(entry.index)
    }

    private func verseStarted(_ position: Int) {
        index = position
        updateNowPlaying()
        savePosition()
    }

    private func verseFinished(_ position: Int) {
        spoken.insert(position)
        if position == verses.count - 1 { chapterDidFinish() }
    }

    private func chapterDidFinish() {
        guard let chapterID else { return }
        // Skipping through doesn't count; hearing at least half the chapter does.
        if spoken.count * 2 >= verses.count {
            finished = FinishedChapter(chapterID: chapterID)
            markRead(chapterID)
        }
        if sleep == .endOfChapter {
            setSleep(.off)
            endHere()
            return
        }
        while let next = nextChapterID {
            if !upNext.isEmpty { upNext.removeFirst() }
            if load(next, fromVerse: nil) {
                speak(from: 0)
                updateNowPlaying()
                return
            }
            // Not imported yet: try the one after it (plan), or stop at the end of the book's text.
            if source == .book { break }
        }
        endHere()
    }

    /// Finished: stays on the last verse, paused; Play starts the chapter over.
    private func endHere() {
        isPlaying = false
        reachedEnd = true
        index = max(verses.count - 1, 0)
        updateNowPlaying()
    }

    private func savePosition() {
        guard let chapterID, let verse = currentVerse else { return }
        UserDefaults.standard.set([
            "chapterID": chapterID, "verse": verse, "date": Date.now,
            "upNext": upNext, "plan": source == .plan,
        ] as [String: Any], forKey: Keys.position)
    }

    // MARK: Audio session

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = AVAudioSession.InterruptionOptions(rawValue: note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            MainActor.assumeIsolated { self?.interrupted(type, options: options) }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            // Headphones unplugged or AirPods taken out: pause, like Music.
            guard reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.pause() }
        })
    }

    private func interrupted(_ type: AVAudioSession.InterruptionType?, options: AVAudioSession.InterruptionOptions) {
        switch type {
        case .began:
            resumeAfterInterruption = isPlaying
            if isPlaying { pause() }
        case .ended:
            if resumeAfterInterruption, options.contains(.shouldResume) { play() }
            resumeAfterInterruption = false
        default:
            break
        }
    }

    // MARK: Lock screen, Control Center, AirPods

    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.toggle()
            return .success
        }
        // Track buttons (and an AirPods double or triple press) move by verse.
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextVerse()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previousVerse()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.seek(toSeconds: event.positionTime)
            return .success
        }
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false
    }

    private func seek(toSeconds seconds: Double) {
        var total = 0.0
        for (position, length) in verseSeconds.enumerated() {
            total += length
            if total > seconds {
                seek(toIndex: position)
                return
            }
        }
        seek(toIndex: verses.count - 1)
    }

    private func updateNowPlaying() {
        guard let chapterID, let verse = currentVerse else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: "\(scripture.title(forChapter: chapterID)) · Verse \(verse)",
            MPMediaItemPropertyArtist: "Hearken",
            MPMediaItemPropertyAlbumTitle: bookTitle,
            MPMediaItemPropertyPlaybackDuration: chapterSeconds,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: secondsElapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// The book's cover, square, for the lock screen.
    private func makeArtwork(for chapterID: String) {
        guard let work = LibraryCatalog.location(ofChapter: chapterID)?.work else { return }
        guard work.id != artworkWorkID else { return }
        artworkWorkID = work.id
        let side: CGFloat = 600
        let renderer = ImageRenderer(content:
            ZStack {
                work.coverColor.opacity(0.35)
                BookCover(work: work, size: CGSize(width: side * 0.58, height: side * 0.87))
            }
            .frame(width: side, height: side)
        )
        renderer.scale = 1
        if let image = renderer.uiImage {
            artwork = Self.artwork(image)
        }
    }

    /// Built outside the main actor: the system asks for the image on its own queue.
    nonisolated private static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}

extension ListenEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in ListenEngine.shared.didStart(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in ListenEngine.shared.didFinish(id) }
    }
}
