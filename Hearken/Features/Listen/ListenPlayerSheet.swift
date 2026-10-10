import SwiftUI

/// The full Listen player: verses scrolling like lyrics with the one being spoken large,
/// a scrubber that moves by verse, transport, and speed, voice and sleep timer.
struct ListenPlayerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContentService.self) private var content
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @State private var engine = ListenEngine.shared
    /// The verse under the scrubber's thumb while it's being dragged.
    @State private var scrubbing: Double?
    @State private var showsVoiceHelp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if engine.naturalVoiceID == nil { voiceBanner }
                lyrics
                scrubber
                transport
                chips
                continueRow
            }
            .background {
                LinearGradient(
                    colors: [accent.color.opacity(0.16), Color(.systemGroupedBackground)],
                    startPoint: .top, endPoint: .center
                )
                .ignoresSafeArea()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ListenSettingsRoute.self) { _ in
                ListenSettingsView()
            }
        }
        .presentationDragIndicator(.visible)
        .alert("Get Better Voices", isPresented: $showsVoiceHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open the Settings app, then go to Accessibility › Spoken Content › Voices › English and download a Premium voice such as Ava or Zoe. It will appear in Hearken right away.")
        }
        .onChange(of: engine.isActive) { _, active in
            if !active { dismiss() }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 12) {
            ListenCover(chapterID: engine.chapterID, width: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(engine.title)
                    .font(.scripture(size: 22, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu {
                if let chapterID = engine.chapterID {
                    Button("Show in Reader", systemImage: "book") {
                        dismiss()
                        AppNavigator.shared.open(chapterID: chapterID)
                    }
                }
                Button("Stop Listening", systemImage: "xmark", role: .destructive) { engine.stop() }
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(.quaternary, in: Circle())
            }
            .tint(Color.primary)
            Button("Close", systemImage: "chevron.down") { dismiss() }
                .labelStyle(.iconOnly)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(.quaternary, in: Circle())
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private var subtitle: String {
        engine.source == .plan ? "Today's reading" : engine.bookTitle
    }

    /// While a system voice is reading: natural voices are downloading, or a way to get them.
    @ViewBuilder
    private var voiceBanner: some View {
        let model = KokoroModel.shared
        switch model.state {
        case .downloading(let fraction):
            Label("Getting natural voices… \(fraction.formatted(.percent.precision(.fractionLength(0))))", systemImage: "arrow.down.circle")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(.tint.opacity(0.14), in: Capsule())
                .foregroundStyle(.tint)
                .padding(.top, 6)
        case .notDownloaded, .failed:
            NavigationLink(value: ListenSettingsRoute()) {
                Label("Sounds robotic? Get natural voices", systemImage: "waveform.badge.plus")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(.tint.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.top, 6)
        default:
            EmptyView()
        }
    }

    private var lyrics: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(engine.verses.enumerated()), id: \.element.id) { position, verse in
                        let isNow = position == engine.index
                        Button {
                            engine.seek(toIndex: position)
                            if !engine.isPlaying { engine.play() }
                        } label: {
                            let number = Text("\(verse.number)  ")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(isNow ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                            let words = Text(verse.text)
                                .font(.scripture(size: isNow ? 23 : 19, weight: isNow ? .semibold : .regular))
                                .foregroundStyle(isNow ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            Text("\(number)\(words)")
                                .multilineTextAlignment(.leading)
                                .lineSpacing(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .id(position)
                        .accessibilityLabel("Verse \(verse.number). \(verse.text)")
                        .accessibilityHint(isNow ? "" : "Plays from this verse.")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 60)
                .animation(.snappy, value: engine.index)
            }
            .scrollIndicators(.hidden)
            .mask {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
            .onAppear { proxy.scrollTo(engine.index, anchor: UnitPoint(x: 0.5, y: 0.3)) }
            .onChange(of: engine.index) { _, index in
                withAnimation(.snappy) { proxy.scrollTo(index, anchor: UnitPoint(x: 0.5, y: 0.3)) }
            }
            .onChange(of: engine.chapterID) { _, _ in
                proxy.scrollTo(0, anchor: .top)
            }
        }
    }

    private var scrubber: some View {
        let last = Double(max(engine.verseCount - 1, 1))
        let shown = Int(scrubbing ?? Double(engine.index))
        let verseNumber = engine.verses.indices.contains(shown) ? engine.verses[shown].number : shown + 1
        return VStack(spacing: 6) {
            Slider(
                value: Binding(get: { scrubbing ?? Double(engine.index) }, set: { scrubbing = $0 }),
                in: 0...last,
                step: 1
            ) {
                Text("Verse")
            } onEditingChanged: { editing in
                guard !editing, let scrubbing else { return }
                engine.seek(toIndex: Int(scrubbing))
                self.scrubbing = nil
            }
            .tint(Color.primary)
            .accessibilityValue("Verse \(verseNumber) of \(engine.verseCount)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: engine.nextVerse()
                case .decrement: engine.previousVerse()
                @unknown default: break
                }
            }
            HStack {
                Text("Verse \(verseNumber) of \(engine.verseCount)")
                Spacer()
                Text(ListenFormat.minutesLeft(engine.secondsLeft))
            }
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var transport: some View {
        HStack(spacing: 26) {
            transportButton("Previous Chapter", "backward.fill", size: 22) { engine.previousChapter() }
            transportButton("Previous Verse", "backward.end.fill", size: 26) { engine.previousVerse() }
            Button {
                engine.toggle()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 76, height: 76)
                    .background(Color.primary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            .sensoryFeedback(.impact(weight: .medium), trigger: engine.isPlaying)
            transportButton("Next Verse", "forward.end.fill", size: 26) { engine.nextVerse() }
            transportButton("Next Chapter", "forward.fill", size: 22) { engine.nextChapter() }
        }
        .padding(.vertical, 14)
    }

    private func transportButton(_ label: String, _ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var chips: some View {
        HStack(spacing: 8) {
            Menu {
                Picker("Speed", selection: Binding(get: { engine.speed }, set: { engine.setSpeed($0) })) {
                    ForEach(ListenFormat.speeds, id: \.self) { speed in
                        Text(ListenFormat.speed(speed)).tag(speed)
                    }
                }
            } label: {
                chip(caption: "Speed") {
                    Text(ListenFormat.speed(engine.speed)).font(.body.weight(.bold)).monospacedDigit()
                }
            }

            NavigationLink(value: ListenSettingsRoute()) {
                chip(caption: engine.voiceName) {
                    Image(systemName: "waveform").font(.body.weight(.semibold))
                }
            }

            Menu {
                Picker("Sleep Timer", selection: Binding(get: { engine.sleep }, set: { engine.setSleep($0) })) {
                    ForEach(ListenSleep.options) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                chip(caption: sleepCaption) {
                    Image(systemName: engine.sleep == .off ? "moon" : "moon.fill").font(.body.weight(.semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .tint(Color.primary)
        .padding(.horizontal, 18)
    }

    private var sleepCaption: String {
        switch engine.sleep {
        case .off:
            return "Sleep"
        case .endOfChapter:
            return "End of chapter"
        case .minutes(let minutes):
            guard let deadline = engine.sleepDeadline else { return "\(minutes) min" }
            return "\(max(1, Int(deadline.timeIntervalSinceNow / 60) + 1)) min"
        }
    }

    private func chip(caption: String, @ViewBuilder icon: () -> some View) -> some View {
        VStack(spacing: 3) {
            icon()
            Text(caption)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var continueRow: some View {
        if let next = engine.followingChapterID {
            Toggle(isOn: Binding(get: { engine.autoContinue }, set: { engine.setAutoContinue($0) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Continue to \(content.title(forChapter: next))")
                        .font(.subheadline.weight(.semibold))
                    Text(engine.source == .plan ? "Next in today's plan" : "Next in the book")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, 16)
        } else {
            Color.clear.frame(height: 24)
        }
    }
}

/// Opens Settings › Listening from the player's voice chip.
struct ListenSettingsRoute: Hashable {}
