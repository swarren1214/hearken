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
                Picker("Pause Between Verses", selection: Binding(get: { engine.versePause }, set: { engine.setVersePause($0) })) {
                    ForEach(VersePause.allCases) { pause in
                        Text(pause.title).tag(pause)
                    }
                }
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
            if model.isReady { KokoroSynth.shared.prewarm() }
        }
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
                Picker("Voice", selection: genderBinding) {
                    Text("Female").tag(false)
                    Text("Male").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Accent", selection: accentBinding) {
                    Text("American").tag(false)
                    Text("British").tag(true)
                }
                .pickerStyle(.segmented)
                ForEach(filteredNatural) { voice in
                    naturalRow(voice)
                }
            } header: {
                Text("Natural Voices")
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
                Button("Hear It", systemImage: "play.circle") {
                    if let id = engine.naturalVoiceID { engine.playSample(voiceID: ListenEngine.naturalPrefix + id) }
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

    /// The chosen gender and accent's voices, featured ones first.
    private var filteredNatural: [KokoroVoices.Voice] {
        let featured = KokoroVoices.featured.compactMap(KokoroVoices.voice)
        let ordered = featured + KokoroVoices.all.filter { !KokoroVoices.featured.contains($0.id) }
        return ordered.filter { $0.isMale == currentNatural.isMale && $0.isBritish == currentNatural.isBritish }
    }

    private var currentNatural: KokoroVoices.Voice {
        engine.naturalVoiceID.flatMap(KokoroVoices.voice) ?? KokoroVoices.voice(KokoroVoices.defaultID)!
    }

    /// Switching gender picks that gender's recommended voice in the same accent.
    private var genderBinding: Binding<Bool> {
        Binding(get: { currentNatural.isMale }, set: { male in
            engine.setVoice(ListenEngine.naturalPrefix + KokoroVoices.recommended(male: male, british: currentNatural.isBritish))
        })
    }

    private var accentBinding: Binding<Bool> {
        Binding(get: { currentNatural.isBritish }, set: { british in
            engine.setVoice(ListenEngine.naturalPrefix + KokoroVoices.recommended(male: currentNatural.isMale, british: british))
        })
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
        let selected = engine.naturalVoiceID == voice.id
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

            Button("Play Sample", systemImage: "play.circle.fill") {
                engine.playSample(voiceID: ListenEngine.naturalPrefix + voice.id)
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
        }
    }

    // MARK: System voices

    private func voiceRow(_ option: ListenVoices.Option) -> some View {
        let selected = engine.naturalVoiceID == nil && (engine.voiceID ?? bestID) == option.id
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

            Button("Play Sample", systemImage: "play.circle.fill") {
                engine.playSample(voiceID: option.id)
            }
            .labelStyle(.iconOnly)
            .font(.title2)
            .foregroundStyle(.secondary)
            .buttonStyle(.borderless)
        }
    }

    private func reload() {
        voices = ListenVoices.available()
        bestID = ListenVoices.best()?.identifier
    }
}

#Preview {
    NavigationStack { ListenSettingsView() }
}
