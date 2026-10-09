import SwiftUI

/// A short burst of falling confetti for a perfect score.
/// Built from plain SwiftUI shapes animated with offsets, so it renders anywhere a view can.
/// Doesn't block touches or VoiceOver. Callers should skip it when Reduce Motion is on.
struct ConfettiView: View {
    var pieceCount = 120
    var colors: [Color] = [.blue, .cyan, .green, .yellow, .orange, .pink, .purple, .red]

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat          // 0...1 across the width
        let drift: CGFloat      // sideways travel while falling, in points
        let delay: Double
        let duration: Double
        let spin: Double        // total rotation in degrees
        let flips: Double       // total 3D flip in degrees
        let size: CGSize
        let isCircle: Bool
        let color: Color
    }

    @State private var pieces: [Piece] = []
    @State private var falling = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(pieces) { piece in
                    shape(for: piece)
                        .frame(width: piece.size.width, height: piece.size.height)
                        .rotation3DEffect(.degrees(falling ? piece.flips : 0), axis: (x: 1, y: 0.4, z: 0))
                        .rotationEffect(.degrees(falling ? piece.spin : 0))
                        .position(
                            x: piece.x * proxy.size.width + (falling ? piece.drift : 0),
                            y: falling ? proxy.size.height + 60 : -30
                        )
                        .animation(.easeIn(duration: piece.duration).delay(piece.delay), value: falling)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            pieces = Self.makePieces(count: pieceCount, colors: colors)
            // Let the pieces render at the top first, then start the fall.
            try? await Task.sleep(for: .milliseconds(30))
            falling = true
        }
    }

    @ViewBuilder
    private func shape(for piece: Piece) -> some View {
        if piece.isCircle {
            Circle().fill(piece.color)
        } else {
            RoundedRectangle(cornerRadius: 1.5).fill(piece.color)
        }
    }

    private static func makePieces(count: Int, colors: [Color]) -> [Piece] {
        (0..<count).map { index in
            let isCircle = Double.random(in: 0...1) < 0.25
            let width = CGFloat.random(in: 6...10)
            return Piece(
                id: index,
                x: .random(in: 0...1),
                drift: .random(in: -60...60),
                delay: .random(in: 0...0.7),
                duration: .random(in: 2.2...3.4),
                spin: .random(in: -540...540),
                flips: .random(in: 360...1080),
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
