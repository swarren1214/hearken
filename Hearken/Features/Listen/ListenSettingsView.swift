import AVFoundation
import Combine
import SwiftUI

/// Settings › Listening: the voice (best first, with samples), speed, the pause between
/// verses, reading verse numbers, and continuing to the next chapter.
struct ListenSettingsView: View {
    @State private var engine = ListenEngine.shared
    @State private var model = KokoroModel.shared
    @State private var voices: [ListenVoices.Option] = []
    @State private var bestID: String?
    @State private var personalStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
    @State private var showsVoiceHelp = false
    /// Which natural-voice groups are open, and the accent tab inside each.
    @State private var femaleOpen = false
    @State private var maleOpen = false
    @State private var femaleBritish = false
    @State private var maleBritish = false

    var body: some View {
        Form {
            naturalVoices

            Section {
                ForEach(voices) { option in
                    voiceRow(option)
                }
                Button("Get Better System Voices") { showsVoiceHelp = true }
            } header: {
                Text("System Voices")
            } footer: {
                Text("Used when natural voices aren't downloaded. Premium voices sound best; download more in the Settings app under Accessibility › Spoken Content › Voices.")
            }

            if personalStatus == .notDetermined {
                Section {
                    Button("Use My Personal Voice") {
                        Task {
                            _ = await engine.requestPersonalVoice()
                            personalStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
                            reload()
                        }
                    }
                } footer: {
                    Text("Hear scripture in your own voice. Make a Personal Voice in the Settings app under Accessibility › Personal Voice.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Speed", value: ListenFormat.speed(engine.speed))
                    Picker("Speed", selection: Binding(get: { engine.speed }, set: { engine.setSpeed($0) })) {
                        ForEach(ListenFormat.speeds, id: \.self) { speed in
                            Text(ListenFormat.speed(speed)).tag(speed)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(.vertical, 4)
                CheckPicker(
                    "Pause Between Verses",
                    selection: Binding(get: { engine.versePause }, set: { engine.setVersePause($0) }),
                    options: VersePause.allCases.map { .init(value: $0, title: $0.title) }
                )
                Toggle("Read Verse Numbers", isOn: Binding(get: { engine.readsVerseNumbers }, set: { engine.setReadsVerseNumbers($0) }))
                Toggle("Continue to Next Chapter", isOn: Binding(get: { engine.autoContinue }, set: { engine.setAutoContinue($0) }))
            } header: {
                Text("Playback")
            } footer: {
                Text("Listening to the end of a chapter marks it read, the same as reading it.")
            }
        }
        .navigationTitle("Listening")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            openCurrentGroup()
            if model.isReady { KokoroSynth.shared.prewarm() }
        }
        .onDisappear { engine.stopSample() }
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            reload()
        }
        .alert("Get Better Voices", isPresented: $showsVoiceHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open the Settings app, then go to Accessibility › Spoken Content › Voices › English and download a Premium voice such as Ava or Zoe. It will appear here right away.")
        }
    }

    // MARK: Natural voices

    @ViewBuilder
    private var naturalVoices: some View {
        switch model.state {
        case .ready:
            Section {
                voiceGroup(male: false, isOpen: $femaleOpen, british: $femaleBritish)
                voiceGroup(male: true, isOpen: $maleOpen, british: $maleBritish)
            } header: {
                Text("Natural Voices")
            } footer: {
                if let error = engine.naturalVoiceError {
                    Text("The natural voice couldn't play: \(error)")
                        .foregroundStyle(.red)
                }
            }

            Section {
                tuningSlider(
                    "Pace", value: engine.tuning.pace, steps: VoiceTuning.paces,
                    low: "Slower", high: "Faster", set: engine.setPace
                )
                tuningSlider(
                    "Expressiveness", value: engine.tuning.expressiveness, steps: VoiceTuning.expressions,
                    low: "Calmer", high: "More expressive", set: engine.setExpressiveness
                )
                if let id = engine.chosenNaturalVoiceID {
                    VoicePreviewButton(voiceID: ListenEngine.naturalPrefix + id, title: "Hear It")
                }
            } header: {
                Text("Voice Style")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Generated on your device by the Kokoro voice model. Nothing you read leaves your iPhone.")
                    Button("Remove Download (\(KokoroModel.approximateSize))", role: .destructive) { model.remove() }
                        .font(.footnote)
                }
            }
        case .downloading(let fraction):
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Downloading Natural Voices")
                        Spacer()
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: fraction)
                }
                .padding(.vertical, 4)
                Button("Cancel Download", role: .destructive) { model.cancelDownload() }
            } header: {
                Text("Natural Voices")
            } footer: {
                Text("You can keep listening with a system voice; Listen switches over when the download finishes.")
            }
        case .notDownloaded:
            Section {
                Button {
                    model.download()
                } label: {
                    Label("Download Natural Voices", systemImage: "arrow.down.circle")
                }
            } header: {
                Text("Natural Voices")
            } footer: {
                Text("Lifelike voices that run on your iPhone, like an audiobook narrator. One-time download of about \(KokoroModel.approximateSize).")
            }
        case .failed(let message):
            Section {
                Button("Try Again") { model.download() }
            } header: {
                Text("Natural Voices")
            } footer: {
                Text(message)
            }
        case .unavailable:
            Section {
                Text("You're running in the Simulator. Natural voices need a real iPhone or iPad: run Hearken on your iPhone to download them.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Natural Voices")
            }
        }
    }

    /// The natural voice picked (or the default).
    private var currentNatural: KokoroVoices.Voice {
        engine.chosenNaturalVoiceID.flatMap(KokoroVoices.voice) ?? KokoroVoices.voice(KokoroVoices.defaultID)!
    }

    /// One gender's voices: a row that opens to show American / British tabs and the voices.
    private func voiceGroup(male: Bool, isOpen: Binding<Bool>, british: Binding<Bool>) -> some View {
        let holdsCurrent = currentNatural.isMale == male && engine.chosenNaturalVoiceID != nil
        let voices = ordered.filter { $0.isMale == male && $0.isBritish == british.wrappedValue }
        return DisclosureGroup(isExpanded: isOpen.animation(.snappy)) {
            Picker("Accent", selection: british.animation(.snappy)) {
                Text("American").tag(false)
                Text("British").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.vertical, 4)
            ForEach(voices) { voice in
                naturalRow(voice)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: male ? "person.fill" : "person")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(male ? "Male Voices" : "Female Voices")
                    if holdsCurrent {
                        Text("\(currentNatural.name) · \(currentNatural.isBritish ? "British" : "American")")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Featured voices first, then the rest.
    private var ordered: [KokoroVoices.Voice] {
        let featured = KokoroVoices.featured.compactMap(KokoroVoices.voice)
        return featured + KokoroVoices.all.filter { !KokoroVoices.featured.contains($0.id) }
    }

    /// Opens the group holding the chosen voice, on its accent tab.
    private func openCurrentGroup() {
        let voice = currentNatural
        if voice.isMale {
            maleOpen = true
            maleBritish = voice.isBritish
        } else {
            femaleOpen = true
            femaleBritish = voice.isBritish
        }
    }

    /// A five-step slider with words at each end, like Siri's voice settings.
    private func tuningSlider(_ title: String, value: Double, steps: [Double], low: String, high: String, set: @escaping (Double) -> Void) -> some View {
        let position = Double(steps.firstIndex(of: value) ?? steps.count / 2)
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Slider(
                value: Binding(get: { position }, set: { set(steps[Int($0.rounded())]) }),
                in: 0...Double(steps.count - 1),
                step: 1
            ) {
                Text(title)
            } minimumValueLabel: {
                Text(low).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func naturalRow(_ voice: KokoroVoices.Voice) -> some View {
        let selected = engine.chosenNaturalVoiceID == voice.id
        return HStack(spacing: 12) {
            Button {
                engine.setVoice(ListenEngine.naturalPrefix + voice.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .opacity(selected ? 1 : 0)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(voice.name)
                        Text(voice.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if voice.id == KokoroVoices.defaultID {
                        Text("Recommended")
                            .font(.caption.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.tint.opacity(0.16), in: .rect(cornerRadius: 7))
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            VoicePreviewButton(voiceID: ListenEngine.naturalPrefix + voice.id)
        }
    }

    // MARK: System voices

    private func voiceRow(_ option: ListenVoices.Option) -> some View {
        let selected = engine.naturalVoiceID == nil && engine.chosenNaturalVoiceID == nil && (engine.voiceID ?? bestID) == option.id
        return HStack(spacing: 12) {
            Button {
                engine.setVoice(option.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .opacity(selected ? 1 : 0)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(option.name)
                        Text(option.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(option.tier.title)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(option.tier == .premium ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.quaternary), in: .rect(cornerRadius: 7))
                        .foregroundStyle(option.tier == .premium ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            VoicePreviewButton(voiceID: option.id)
        }
    }

    private func reload() {
        voices = ListenVoices.available()
        bestID = ListenVoices.best()?.identifier
    }
}

/// Play a voice sample: a spinner while a natural voice generates it, a moving waveform while
/// it plays (tap again to stop), and the play icon otherwise.
struct VoicePreviewButton: View {
    let voiceID: String
    var title: String?

    @State private var engine = ListenEngine.shared

    var body: some View {
        let preview = engine.preview?.voiceID == voiceID ? engine.preview : nil
        Button {
            engine.playSample(voiceID: voiceID)
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if let preview, !preview.isPlaying {
                        ProgressView()
                    } else if preview != nil {
                        Image(systemName: "waveform.circle.fill")
                            .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: true)
                            .foregroundStyle(.tint)
                    } else {
                        Image(systemName: "play.circle.fill")
                            .foregroundStyle(title == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    }
                }
                .font(.title2)
                .frame(width: 32, height: 32)
                if let title {
                    Text(preview == nil ? title : "Stop")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .animation(.snappy, value: preview)
        .accessibilityLabel(preview == nil ? "Play sample" : "Stop sample")
    }
}

#Preview {
    NavigationStack { ListenSettingsView() }
}
