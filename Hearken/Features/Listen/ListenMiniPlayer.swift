import SwiftUI

enum ListenFormat {
    /// "1×", "1.25×"
    static func speed(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    static let speeds: [Double] = [0.75, 1, 1.25, 1.5, 2]

    /// "About 6 min left"
    static func minutesLeft(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        return "About \(minutes) min left"
    }
}

/// The small cloth cover used by the players.
struct ListenCover: View {
    let chapterID: String?
    var width: CGFloat = 32

    var body: some View {
        if let work = chapterID.flatMap({ LibraryCatalog.location(ofChapter: $0)?.work }) {
            BookCover(work: work, size: CGSize(width: width, height: width * 1.5))
                .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.tint)
                .frame(width: width, height: width * 1.5)
                .accessibilityHidden(true)
        }
    }
}

/// Listen mode's mini player: in the tab bar's accessory (iOS 26.2 and later), or floating
/// above the tab bar. Tap it for the full player; touch and hold to stop listening.
struct ListenMiniPlayer: View {
    var compact = false

    @State private var engine = ListenEngine.shared

    var body: some View {
        HStack(spacing: 12) {
            Button {
                engine.showsPlayer = true
            } label: {
                HStack(spacing: 10) {
                    ListenCover(chapterID: engine.chapterID, width: compact ? 18 : 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if !compact {
                            HStack(spacing: 5) {
                                Image(systemName: "waveform")
                                    .symbolEffect(.variableColor.iterative, isActive: engine.isPlaying)
                                    .foregroundStyle(.tint)
                                Text("\(engine.voiceName) · \(ListenFormat.speed(engine.speed))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(heading). Opens the player.")

            Button(engine.isPlaying ? "Pause" : "Play", systemImage: engine.isPlaying ? "pause.fill" : "play.fill") {
                engine.toggle()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 36, height: 36)
            .contentShape(.rect)

            if !compact {
                Button("Next Verse", systemImage: "forward.end.fill") { engine.nextVerse() }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .contextMenu {
            Button("Open Player", systemImage: "headphones") { engine.showsPlayer = true }
            if let chapterID = engine.chapterID {
                Button("Show in Reader", systemImage: "book") { AppNavigator.shared.open(chapterID: chapterID) }
            }
            Button("Stop Listening", systemImage: "xmark", role: .destructive) { engine.stop() }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: engine.isPlaying)
    }

    private var heading: String {
        guard let verse = engine.currentVerse else { return engine.title }
        return "\(engine.title) · Verse \(verse)"
    }
}

/// Picks compact or full layout from where the tab bar puts the accessory.
private struct AccessoryMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        ListenMiniPlayer(compact: placement == .inline)
    }
}

extension View {
    /// The mini player while Listen mode is on, and the full player sheet.
    func listenPlayer() -> some View {
        modifier(ListenPlayerChrome())
    }
}

private struct ListenPlayerChrome: ViewModifier {
    @State private var engine = ListenEngine.shared

    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.2, *) {
                content
                    .tabViewBottomAccessory(isEnabled: engine.isActive) { AccessoryMiniPlayer() }
            } else {
                // Earlier releases can't hide an empty accessory, so float the player instead.
                content
                    .overlay(alignment: .bottom) {
                        if engine.isActive {
                            ListenMiniPlayer()
                                .frame(height: 56)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 66)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy, value: engine.isActive)
            }
        }
        .sheet(isPresented: $engine.showsPlayer) {
            ListenPlayerSheet()
        }
    }
}

/// Connects Listen mode to the app's shared content, and offers a session from before a relaunch.
/// (Chapters heard to the end are marked read by the engine itself, so that works for Siri too.)
struct ListenSideEffects: ViewModifier {
    @Environment(ContentService.self) private var scripture

    func body(content: Content) -> some View {
        content
            .task {
                ListenEngine.shared.attach(content: scripture)
                ListenEngine.shared.restoreIfRecent()
            }
    }
}
