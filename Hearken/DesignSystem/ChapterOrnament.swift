import SwiftUI

/// The flourish under each chapter heading: sweeping lines that curl into scrolls, a leaf on
/// each side, and an open teardrop with a seed at the center. Drawn from paths (in a 240 × 50
/// design box, the left half mirrored to the right), so it's sharp at any size and takes any color.
struct ChapterOrnament: View {
    var color: Color = .primary

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 240, size.height / 50)
            context.translateBy(x: (size.width - 240 * scale) / 2, y: (size.height - 50 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let shading = GraphicsContext.Shading.color(color)

            var left = context
            Self.drawHalf(in: &left, shading)
            var right = context
            right.translateBy(x: 240, y: 0)
            right.scaleBy(x: -1, y: 1)
            Self.drawHalf(in: &right, shading)

            // The center: an open teardrop with a seed inside, and a drop below.
            context.stroke(Self.path { p in
                p.move(to: CGPoint(x: 120, y: 4))
                p.addCurve(to: CGPoint(x: 120, y: 29), control1: CGPoint(x: 113, y: 12), control2: CGPoint(x: 113, y: 22))
                p.addCurve(to: CGPoint(x: 120, y: 4), control1: CGPoint(x: 127, y: 22), control2: CGPoint(x: 127, y: 12))
                p.closeSubpath()
            }, with: shading, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            context.fill(Path(ellipseIn: CGRect(x: 118.2, y: 11, width: 3.6, height: 10)), with: shading)
            context.fill(Path(ellipseIn: CGRect(x: 118.3, y: 35.2, width: 3.4, height: 5.6)), with: shading)
        }
        .accessibilityHidden(true)
    }

    private static func drawHalf(in context: inout GraphicsContext, _ shading: GraphicsContext.Shading) {
        func stroke(_ width: CGFloat, _ build: (inout Path) -> Void) {
            context.stroke(path(build), with: shading, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

        // The long line, swelling from the tip into the center.
        stroke(1.5) { p in
            p.move(to: pt(6, 32))
            p.addCurve(to: pt(114, 29), control1: pt(40, 37), control2: pt(82, 36))
        }
        // The scroll, rising off the line and curling in on itself.
        stroke(1.6) { p in
            p.move(to: pt(72, 35))
            p.addCurve(to: pt(42, 17), control1: pt(52, 34), control2: pt(40, 26))
            p.addCurve(to: pt(61, 13), control1: pt(44, 9), control2: pt(56, 7))
            p.addCurve(to: pt(55, 22), control1: pt(65, 18), control2: pt(61, 24))
            p.addCurve(to: pt(56, 15), control1: pt(51, 20), control2: pt(52, 15))
        }
        // A sliver of a leaf inside the scroll.
        context.fill(path { p in
            p.move(to: pt(46, 18))
            p.addCurve(to: pt(56, 12), control1: pt(47, 13), control2: pt(52, 11))
            p.addCurve(to: pt(48, 19), control1: pt(52, 13), control2: pt(49, 15))
            p.closeSubpath()
        }, with: shading)
        // The leaf sweeping toward the center.
        context.fill(path { p in
            p.move(to: pt(76, 31))
            p.addCurve(to: pt(107, 27), control1: pt(86, 24), control2: pt(98, 23))
            p.addCurve(to: pt(76, 31), control1: pt(97, 26), control2: pt(87, 28))
            p.closeSubpath()
        }, with: shading)
        // The small curl beside the center.
        stroke(1.3) { p in
            p.move(to: pt(112, 29))
            p.addCurve(to: pt(104, 14), control1: pt(105, 26), control2: pt(101, 19))
            p.addCurve(to: pt(111, 16), control1: pt(107, 10), control2: pt(112, 12))
            p.addCurve(to: pt(108, 15), control1: pt(110, 18), control2: pt(107, 17))
        }
        // Fine strokes at the tip.
        stroke(1) { p in
            p.move(to: pt(10, 27))
            p.addCurve(to: pt(24, 33), control1: pt(16, 28), control2: pt(21, 30))
        }
        stroke(0.9) { p in
            p.move(to: pt(19, 24))
            p.addCurve(to: pt(34, 32), control1: pt(26, 25), control2: pt(31, 28))
        }
    }

    private static func path(_ build: (inout Path) -> Void) -> Path {
        var path = Path()
        build(&path)
        return path
    }
}

#Preview {
    ChapterOrnament(color: .blue)
        .frame(width: 240, height: 50)
        .padding()
}
