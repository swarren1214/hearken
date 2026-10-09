import SwiftUI

/// A ring that fills with progress, like the Activity rings. Draws in the current tint.
struct ProgressRing<Label: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 10
    @ViewBuilder var label: () -> Label

    var body: some View {
        ZStack {
            Circle()
                .stroke(.tint.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            label()
        }
        .animation(.smooth, value: progress)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text("\(Int((progress * 100).rounded())) percent"))
    }
}

extension ProgressRing where Label == EmptyView {
    init(progress: Double, lineWidth: CGFloat = 10) {
        self.init(progress: progress, lineWidth: lineWidth, label: { EmptyView() })
    }
}

/// The four-segment Seeker → Master bar shown on a subject.
struct TierBar: View {
    var mastery: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tier.allCases) { tier in
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule()
                                .fill(.tint)
                                .frame(width: proxy.size.width * fill(for: tier))
                        }
                    }
                    .frame(height: 6)
                    Text(tier.name)
                        .font(.caption2)
                        .fontWeight(tier == Tier(mastery: mastery) ? .semibold : .regular)
                        .foregroundStyle(tier == Tier(mastery: mastery) ? .primary : .secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tier")
        .accessibilityValue(Tier(mastery: mastery).name)
    }

    private func fill(for tier: Tier) -> CGFloat {
        let span = tier.upperBound - tier.lowerBound
        return CGFloat(min(max((mastery - tier.lowerBound) / span, 0), 1))
    }
}

/// A thin horizontal progress bar in the tint color.
struct MasteryBar: View {
    var value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.tint).frame(width: proxy.size.width * CGFloat(min(max(value, 0), 1)))
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// A rounded tinted square holding an SF Symbol, used in lists.
struct SymbolTile: View {
    var systemName: String
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .frame(width: size, height: size)
            .background(.tint.opacity(0.15), in: .rect(cornerRadius: size * 0.26))
            .accessibilityHidden(true)
    }
}

/// The app icon artwork, for onboarding and About.
struct AppIconBadge: View {
    var size: CGFloat = 92

    var body: some View {
        Image("HearkenMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: size * 0.2237, style: .continuous))
            .shadow(color: .blue.opacity(0.3), radius: 15, y: 10)
            .accessibilityHidden(true)
    }
}

/// A card container used on Today and subject screens.
struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
}
