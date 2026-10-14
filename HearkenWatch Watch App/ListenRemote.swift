import SwiftUI

/// A remote for Listen mode on the iPhone: play/pause (double tap works too), verse and
/// chapter skipping, speed, and Mark Verse, which bookmarks the verse being heard.
struct ListenRemote: View {
    @Environment(WatchStore.self) private var store
    @State private var showsMarked = false

    var body: some View {
        let listen = store.listen
        Group {
            if listen.active {
                player(listen)
            } else {
                idle
            }
        }
        .onChange(of: store.marked) { _, marked in
            guard marked != nil else { return }
            showsMarked = true
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                showsMarked = false
                store.marked = nil
            }
        }
        .sensoryFeedback(.success, trigger: store.marked) { _, new in new != nil }
    }

    private var idle: some View {
        VStack(spacing: 10) {
            Image(systemName: "headphones")
                .font(.title)
                .foregroundStyle(.tint)
            Text("Nothing playing")
                .font(.headline)
            Button("Listen to Today's Reading") { store.send(.listenToday) }
                .buttonStyle(.borderedProminent)
            if let problem = store.problem {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func player(_ listen: ListenState) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 1) {
                Text(listen.book)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(listen.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(showsMarked ? "Saved \(store.marked ?? "")" : "Verse \(listen.verse) of \(listen.verseCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(showsMarked ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .contentTransition(.opacity)
            }

            ProgressView(value: Double(listen.verse), total: Double(listen.verseCount))
                .tint(.accentColor)

            HStack {
                Button { store.send(.previousVerse) } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("Previous Verse")

                Button { store.send(.toggle) } label: {
                    Image(systemName: listen.playing ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .accessibilityLabel(listen.playing ? "Pause" : "Play")
                .handGestureShortcut(.primaryAction)

                Button { store.send(.nextVerse) } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("Next Verse")
            }
            .buttonStyle(.bordered)

            HStack {
                Button { store.send(.markVerse) } label: {
                    Image(systemName: "bookmark.fill")
                }
                .accessibilityLabel("Mark This Verse")

                Button { store.send(.setSpeed, value: listen.nextSpeed) } label: {
                    Text(listen.speedLabel).font(.footnote.weight(.semibold).monospacedDigit())
                }
                .accessibilityLabel("Speed \(listen.speedLabel)")

                Button { store.send(.nextChapter) } label: {
                    Image(systemName: "forward.end.fill")
                }
                .accessibilityLabel("Next Chapter")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

#Preview {
    ListenRemote()
        .environment(WatchStore.shared)
}
