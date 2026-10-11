import SwiftData
import SwiftUI

/// The full-screen moment when a rank is earned: a glow blooms, the medal rises with a spring,
/// a light band sweeps across its face, the emblem pops in, the rank dots appear one by one,
/// and motes drift up. Then the details and buttons fade in. Reduce Motion: a simple fade.
struct BadgeUnlockView: View {
    let grant: RankGrant
    let subjectName: String
    let onSeePath: () -> Void
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloom = false
    @State private var risen = false
    @State private var sweep: CGFloat = -1
    @State private var emblemIn = false
    @State private var dots = 0
    @State private var detailsIn = false
    @State private var raysTurn: Double = 0

    private var rank: ScholarRank { grant.rank }
    private let medalSize: CGFloat = 220

    var body: some View {
        ZStack {
            background
            if !reduceMotion { MoteField(color: rank.palette.light).opacity(detailsIn ? 1 : 0.6) }

            VStack(spacing: 0) {
                Spacer(minLength: 40)
                medal
                    .padding(.bottom, 28)
                details
                    .opacity(detailsIn ? 1 : 0)
                    .offset(y: detailsIn ? 0 : 10)
                Spacer(minLength: 24)
                buttons
                    .opacity(detailsIn ? 1 : 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .preferredColorScheme(.dark)
        .sensoryFeedback(.success, trigger: risen)
        .sensoryFeedback(.impact(weight: .light), trigger: dots)
        .task { await play() }
        .accessibilityElement(children: .contain)
    }

    private var background: some View {
        ZStack {
            Color(hex: 0x05080F).ignoresSafeArea()
            RadialGradient(colors: [rank.palette.top.opacity(0.95), rank.palette.bottom, Color(hex: 0x05080F)], center: UnitPoint(x: 0.5, y: 0.34), startRadius: 0, endRadius: 520)
                .ignoresSafeArea()
            Circle()
                .fill(RadialGradient(colors: [rank.palette.light.opacity(0.38), rank.palette.mid.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 170))
                .frame(width: 340, height: 340)
                .scaleEffect(bloom ? 1 : 0.6)
                .opacity(bloom ? 0.85 : 0)
                .offset(y: -150)
        }
    }

    private var medal: some View {
        ScholarBadge(rank: rank, size: medalSize, emblemScale: emblemIn ? 1 : 0.35, emblemTurn: emblemIn ? 0 : -25, dotsShown: dots, raysTurn: raysTurn)
            .overlay {
                // The light band sweeping across the face.
                LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 70)
                    .rotationEffect(.degrees(18))
                    .offset(x: sweep * medalSize)
                    .mask(Circle().padding(medalSize * 19 / 256))
                    .allowsHitTesting(false)
            }
            .scaleEffect(risen ? 1 : 0.68)
            .offset(y: risen ? 0 : 22)
            .opacity(risen ? 1 : 0)
            .accessibilityLabel("\(rank.name) badge earned")
    }

    private var details: some View {
        VStack(spacing: 6) {
            Text("NEW RANK")
                .font(.footnote.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(rank.palette.light)
            Text(rank.name)
                .font(.system(size: 36, weight: .bold))
            Text("\(subjectName) · \(grant.earnedAt.formatted(date: .long, time: .omitted))")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)

            VStack(spacing: 9) {
                detailRow("XP at award", grant.xpAtAward.formatted())
                if rank.requiredStages > 0 {
                    detailRow("Stages complete", rank.requiredStages == 1 ? "Stage 1" : "Stages 1–\(rank.requiredStages)")
                } else {
                    detailRow("Earned for", "Your first learning item")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .padding(.top, 18)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.white.opacity(0.7))
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: onSeePath) {
                Text("See Your Path").font(.headline).frame(maxWidth: .infinity).frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .tint(.white)
            .foregroundStyle(Color(hex: 0x0E1A30))
            .controlSize(.large)

            HStack(spacing: 10) {
                ShareLink(item: "I earned the \(rank.name) badge in \(subjectName) on Hearken.") {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).frame(height: 30)
                }
                Button(action: onDone) {
                    Text("Done").frame(maxWidth: .infinity).frame(height: 30)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .tint(.white)
        }
    }

    // MARK: Animation

    private func play() async {
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.6)) {
                bloom = true
                risen = true
                emblemIn = true
                dots = rank.rawValue
                detailsIn = true
            }
            sweep = 2
            return
        }
        withAnimation(.easeOut(duration: 1.4)) { bloom = true }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.spring(response: 0.75, dampingFraction: 0.62)) { risen = true }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.easeInOut(duration: 1.0)) { sweep = 1.2 }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.55)) { emblemIn = true }
        try? await Task.sleep(for: .milliseconds(450))
        for index in 1...rank.rawValue {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { dots = index }
            try? await Task.sleep(for: .milliseconds(160))
        }
        withAnimation(.easeOut(duration: 0.6)) { detailsIn = true }
        if rank == .sage {
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) { raysTurn = 360 }
        }
    }
}

/// Soft motes drifting up in the rank's color.
private struct MoteField: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<18 {
                    let seed = Double(index)
                    let duration = 3.4 + seed.truncatingRemainder(dividingBy: 5) * 0.5
                    let phase = ((time + seed * 0.27) / duration).truncatingRemainder(dividingBy: 1)
                    let x = size.width * (0.15 + (seed * 0.137).truncatingRemainder(dividingBy: 0.7))
                    let startY = size.height * (0.42 + (seed * 0.071).truncatingRemainder(dividingBy: 0.16))
                    let y = startY - phase * 320
                    let alpha = phase < 0.15 ? phase / 0.15 : 1 - phase
                    let radius = 1.5 + (seed.truncatingRemainder(dividingBy: 4)) * 0.75
                    let shade = index.isMultiple(of: 3) ? Color.white : color
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(shade.opacity(alpha * 0.85)))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Shows the unlock celebration once for each newly granted rank, in order, over whatever
/// screen is open. Attach once, at the root.
struct ScholarCelebrations: ViewModifier {
    @Environment(ContentService.self) private var content
    @Query(filter: #Predicate<RankGrant> { !$0.celebrated }, sort: \RankGrant.rankRaw) private var pending: [RankGrant]
    @State private var navigator = AppNavigator.shared

    func body(content view: Content) -> some View {
        view.fullScreenCover(item: Binding(get: { pending.first }, set: { if $0 == nil { pending.first?.celebrated = true } })) { grant in
            BadgeUnlockView(
                grant: grant,
                subjectName: subjectName(grant.subjectID),
                onSeePath: {
                    let subjectID = grant.subjectID
                    grant.celebrated = true
                    navigator.pendingSubjectID = subjectID
                },
                onDone: { grant.celebrated = true }
            )
        }
    }

    private func subjectName(_ id: String) -> String {
        content.subject(id)?.name ?? PathCatalog.shared.path(for: id)?.title ?? "Your subject"
    }
}

extension View {
    func scholarCelebrations() -> some View { modifier(ScholarCelebrations()) }
}
