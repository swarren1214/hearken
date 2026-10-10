import AVFoundation
import Combine
import SwiftUI

/// Settings › Listening: the voice (best first, with samples), speed, the pause between
/// verses, reading verse numbers, and continuing to the next chapter.
struct ListenSettingsView: View {
    @State private var engine = ListenEngine.shared
    @State private var voices: [ListenVoices.Option] = []
    @State private var bestID: String?
    @State private var personalStatus = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
    @State private var showsVoiceHelp = false

    var body: some View {
        Form {
            Section {
                ForEach(voices) { option in
                    voiceRow(option)
                }
                Button("Get Better Voices") { showsVoiceHelp = true }
            } header: {
                Text("Voice")
            } footer: {
                Text("Premium voices sound most natural. Download more in the Settings app under Accessibility › Spoken Content › Voices.")
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
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
            reload()
        }
        .alert("Get Better Voices", isPresented: $showsVoiceHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open the Settings app, then go to Accessibility › Spoken Content › Voices › English and download a Premium voice such as Ava or Zoe. It will appear here right away.")
        }
    }

    private func voiceRow(_ option: ListenVoices.Option) -> some View {
        let selected = (engine.voiceID ?? bestID) == option.id
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
