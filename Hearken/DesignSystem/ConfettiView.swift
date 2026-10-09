import SwiftUI

/// A short burst of falling confetti, drawn with Canvas. Doesn't block touches or VoiceOver.
/// Callers should skip it when Reduce Motion is on.
struct ConfettiView: View {
    var pieceCount = 140
    var duration: Double = 3.5
    var colors: [Color] = [.blue, .cyan, .green, .yellow, .orange, .pink, .purple, .red]

    private struct Piece {
        let x: Double          // 0...1 across the width
        let delay: Double      // seconds before it appears
        let speed: Double      // initial fall speed, points per second
        let sway: Double       // phase of the side-to-side drift
        let spin: Double       // radians per second
        let flip: Double       // how fast it flips, for a 3D feel
        let size: CGSize
        let isCircle: Bool
        let color: Color
    }

    @State private var start = Date.now
    @State private var pieces: [Piece] = []
    @State private var done = false

    var body: some View {
        TimelineView(.animation(paused: done)) { timeline in
            Canvas { context, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                let fadeStart = duration - 0.8
                let opacity = elapsed < fadeStart ? 1 : max(0, 1 - (elapsed - fadeStart) / 0.8)

                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -24 + piece.speed * t + 70 * t * t
                    guard y < size.height + 40 else { continue }
                    let x = piece.x * size.width + sin(t * 2.6 + piece.sway) * 26

                    var ctx = context
                    ctx.opacity = opacity
                    ctx.translateBy(x: x, y: y)
                    ctx.rotate(by: .radians(piece.spin * t))
                    ctx.scaleBy(x: cos(piece.flip * t), y: 1)
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                      width: piece.size.width, height: piece.size.height)
                    let path = piece.isCircle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                    ctx.fill(path, with: .color(piece.color))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: launch)
        .task {
            try? await Task.sleep(for: .seconds(duration + 0.2))
            done = true
        }
    }

    private func launch() {
        start = .now
        pieces = (0..<pieceCount).map { _ in
            let isCircle = Double.random(in: 0...1) < 0.25
            let width = Double.random(in: 6...10)
            return Piece(
                x: .random(in: 0...1),
                delay: .random(in: 0...0.6),
                speed: .random(in: 90...240),
                sway: .random(in: 0...(2 * .pi)),
                spin: .random(in: -6...6),
                flip: .random(in: 3...9),
                size: isCircle ? CGSize(width: width * 0.8, height: width * 0.8) : CGSize(width: width, height: width * 1.6),
                isCircle: isCircle,
                color: colors.randomElement() ?? .blue
            )
        }
    }
}

#Preview {
    ConfettiView()
}
