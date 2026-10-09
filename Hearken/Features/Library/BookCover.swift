import SwiftUI

/// A cloth-bound front cover with a gold-tooled frame. Scales from a shelf thumbnail
/// up to full screen (the opening animation draws it at the size of the display).
struct BookCover: View {
    let work: LibraryWork
    var size = CGSize(width: 120, height: 180)
    var showsRibbon = false

    private static let gold = Color(hex: 0xE9CF90)
    private var scale: CGFloat { size.width / 120 }
    private var showsText: Bool { size.width >= 80 }

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 3 * scale, bottomLeadingRadius: 3 * scale,
            bottomTrailingRadius: 8 * scale, topTrailingRadius: 8 * scale
        )

        ZStack {
            shape.fill(work.coverColor)
            // Spine crease and a soft sheen, like light across cloth.
            shape.fill(LinearGradient(stops: [
                .init(color: .black.opacity(0.32), location: 0),
                .init(color: .black.opacity(0.08), location: 0.07),
                .init(color: .white.opacity(0.08), location: 0.09),
                .init(color: .clear, location: 0.3),
            ], startPoint: .leading, endPoint: .trailing))
            shape.fill(RadialGradient(
                colors: [.white.opacity(0.14), .clear],
                center: UnitPoint(x: 0.75, y: 0.18), startRadius: 0, endRadius: size.width * 0.7
            ))

            RoundedRectangle(cornerRadius: 3 * scale)
                .strokeBorder(Self.gold.opacity(0.45), lineWidth: max(1, scale * 0.8))
                .padding(EdgeInsets(top: 8 * scale, leading: 15 * scale, bottom: 8 * scale, trailing: 8 * scale))

            VStack(spacing: 6 * scale) {
                rule
                if showsText {
                    Text(work.title)
                        .font(.system(size: 15 * scale, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.gold)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 10 * scale)
                    rule
                }
            }
            .padding(.leading, 6 * scale)

            if showsText && !work.subtitle.isEmpty {
                Text(work.subtitle.uppercased())
                    .font(.system(size: 8.5 * scale))
                    .tracking(0.5 * scale)
                    .foregroundStyle(Self.gold.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(EdgeInsets(top: 0, leading: 14 * scale, bottom: 16 * scale, trailing: 8 * scale))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topTrailing) {
            if showsRibbon {
                Ribbon()
                    .fill(.tint)
                    .frame(width: 10 * scale, height: 40 * scale)
                    .offset(x: -14 * scale, y: -2)
                    .accessibilityHidden(true)
            }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 8 * min(scale, 2), y: 8 * min(scale, 2))
    }

    private var rule: some View {
        Rectangle()
            .fill(Self.gold.opacity(0.8))
            .frame(width: 26 * scale, height: max(1, scale * 0.8))
    }
}

/// A bookmark ribbon with a notched tail.
private struct Ribbon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.2))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// Lifts a cover off the shelf while it's pressed.
struct CoverLiftStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let lifted = configuration.isPressed && !reduceMotion
        configuration.label
            .scaleEffect(lifted ? 1.06 : 1, anchor: .bottom)
            .offset(y: lifted ? -12 : 0)
            .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 18, y: 20)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// The wooden ledge under each row of covers.
struct ShelfBoard: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        RoundedRectangle(cornerRadius: 3)
            .fill(LinearGradient(
                colors: dark ? [Color(hex: 0x3A3A3E), Color(hex: 0x242427)] : [Color(hex: 0xE6E0D7), Color(hex: 0xD6CEC2)],
                startPoint: .top, endPoint: .bottom
            ))
            .frame(height: 12)
            .shadow(color: dark ? .black.opacity(0.6) : Color(hex: 0x503C1E).opacity(0.16), radius: 7, y: 8)
            .accessibilityHidden(true)
    }
}
