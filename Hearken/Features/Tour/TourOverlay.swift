import SwiftUI

/// The tour's spotlight and card, over the whole tab view. Nothing is placed at fixed
/// coordinates: the spotlight follows the target's live frame, and the card goes above or below
/// it, wherever there's room, never over the tab bar (bottom in compact width, top in regular).
/// If neither side has room, or the text is at an accessibility size, the card docks at the
/// edge away from the tab bar.
struct TourOverlay: View {
    var tour = TourController.shared

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @State private var cardHeight: CGFloat = 0
    @State private var pulse = false
    @AccessibilityFocusState private var titleFocused: Bool

    /// Side margin for the card, and its gap from the spotlight.
    private static let margin: CGFloat = 14
    private static let gap: CGFloat = 14
    /// How far the spotlight reaches past the target.
    private static let holePadding: CGFloat = 8
    private static let holeRadius: CGFloat = 26
    /// Room left for the floating tab bar (and the space around it).
    private static let tabBarClearance: CGFloat = 72
    private static let regularCardWidth: CGFloat = 380

    var body: some View {
        if let step = tour.step {
            GeometryReader { outer in
                let safe = outer.safeAreaInsets
                GeometryReader { full in
                    let placement = place(
                        size: full.size,
                        origin: full.frame(in: .global).origin,
                        safe: safe
                    )
                    stage(step, placement: placement, screenHeight: full.size.height)
                }
                .ignoresSafeArea()
            }
            .transition(.opacity)
        }
    }

    // MARK: Drawing

    private func stage(_ step: TourController.Step, placement: Placement, screenHeight: CGFloat) -> some View {
        let motion: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.45, bounce: 0.15)
        let increased = contrast == .increased

        return ZStack(alignment: .topLeading) {
            // The dim, with a hole over the target. It takes every tap, so nothing behind it
            // opens mid-tour.
            Spotlight(hole: placement.hole ?? .zero, radius: Self.holeRadius)
                .fill(Color.black.opacity(increased ? 0.65 : 0.52), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture {}
                .accessibilityHidden(true)

            if let hole = placement.hole {
                // Tapping the lit target moves the tour along.
                RoundedRectangle(cornerRadius: Self.holeRadius, style: .continuous)
                    .fill(Color.white.opacity(0.001))
                    .frame(width: hole.width, height: hole.height)
                    .offset(x: hole.minX, y: hole.minY)
                    .onTapGesture { tour.next() }
                    .accessibilityHidden(true)

                RoundedRectangle(cornerRadius: Self.holeRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.9), lineWidth: increased ? 3 : 2)
                    .frame(width: hole.width, height: hole.height)
                    .scaleEffect(reduceMotion ? 1 : (pulse ? 1.06 : 1))
                    .opacity(reduceMotion ? 0.9 : (pulse ? 0 : 0.9))
                    .offset(x: hole.minX, y: hole.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            card(step, screenHeight: screenHeight)
                .frame(width: placement.card.width)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                .offset(x: placement.card.minX, y: placement.card.minY)
        }
        .animation(motion, value: step)
        .animation(motion, value: placement)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
        .onChange(of: step, initial: true) {
            // VoiceOver starts each step at the card's title.
            Task { titleFocused = true }
        }
    }

    private func card(_ step: TourController.Step, screenHeight: CGFloat) -> some View {
        let large = typeSize.isAccessibilitySize
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: step.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(step.color)
                    .frame(width: 34, height: 34)
                    .background(step.color.opacity(0.15), in: .rect(cornerRadius: 10))
                    .accessibilityHidden(true)
                Text(step.title)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }

            Group {
                if large {
                    // Very large text: the words scroll inside a card that never outgrows the screen.
                    ScrollView {
                        message(step)
                    }
                    .frame(maxHeight: screenHeight * 0.4)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    message(step)
                }
            }
            .padding(.top, 8)

            HStack(spacing: 14) {
                if !large { dots(step) }
                Spacer(minLength: 0)
                Button("Skip") { tour.skip() }
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button(step.isLast ? "Start Reading" : "Next") { tour.next() }
                    .fontWeight(.semibold)
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 16)
        }
        .padding(18)
        .modifier(CardSurface(shape: shape, solid: reduceTransparency))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(named: "Skip Tour") { tour.skip() }
    }

    private func message(_ step: TourController.Step) -> some View {
        Text(step.message)
            .font(.body)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dots(_ step: TourController.Step) -> some View {
        HStack(spacing: 6) {
            ForEach(TourController.Step.allCases) { each in
                Capsule()
                    .fill(each == step ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.35)))
                    .frame(width: each == step ? 18 : 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(TourController.Step.allCases.count)")
    }

    // MARK: Placement

    struct Placement: Equatable {
        /// The spotlight, in the overlay's coordinates; nil when there's nothing on screen to point at.
        var hole: CGRect?
        var card: CGRect
    }

    private func place(size: CGSize, origin: CGPoint, safe: EdgeInsets) -> Placement {
        let compact = sizeClass != .regular
        let large = typeSize.isAccessibilitySize
        // The space the card may use: inside the safe area, clear of the tab bar.
        let topReserve = compact ? 8 : Self.tabBarClearance
        let bottomReserve = compact ? Self.tabBarClearance : 8
        let area = CGRect(
            x: safe.leading + Self.margin,
            y: safe.top + topReserve,
            width: max(0, size.width - safe.leading - safe.trailing - Self.margin * 2),
            height: max(0, size.height - safe.top - safe.bottom - topReserve - bottomReserve)
        )
        let width = (compact || large) ? area.width : min(Self.regularCardWidth, area.width)
        let height = cardHeight
        // Docked: at the edge away from the tab bar, which is the bottom of `area` either way.
        let docked = CGRect(x: area.midX - width / 2, y: area.maxY - height, width: width, height: height)

        guard let global = tour.targetFrame else { return Placement(hole: nil, card: docked) }
        let target = global.offsetBy(dx: -origin.x, dy: -origin.y)
        // Point at it only if most of it is on screen.
        let shown = target.intersection(CGRect(origin: .zero, size: size))
        guard !shown.isNull, shown.height >= target.height * 0.6, shown.width >= target.width * 0.6 else {
            return Placement(hole: nil, card: docked)
        }
        let hole = target.insetBy(dx: -Self.holePadding, dy: -Self.holePadding)
        guard !large else { return Placement(hole: hole, card: docked) }

        let above = hole.minY - Self.gap - area.minY
        let below = area.maxY - (hole.maxY + Self.gap)
        guard height > 0, above >= height || below >= height else { return Placement(hole: hole, card: docked) }
        let goBelow = below >= above || above < height
        let y = goBelow ? hole.maxY + Self.gap : hole.minY - Self.gap - height
        // Compact: full width. Regular: centered on the target, kept inside the safe area.
        let x = compact ? area.midX - width / 2 : min(max(hole.midX - width / 2, area.minX), area.maxX - width)
        return Placement(hole: hole, card: CGRect(x: x, y: y, width: width, height: height))
    }
}

/// The dim layer: the whole screen minus a rounded hole. Animates the hole between steps.
private struct Spotlight: Shape {
    var hole: CGRect
    var radius: CGFloat

    var animatableData: CGRect.AnimatableData {
        get { hole.animatableData }
        set { hole.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}

/// Frosted glass, or a solid card when Reduce Transparency is on.
private struct CardSurface<S: Shape>: ViewModifier {
    let shape: S
    let solid: Bool

    func body(content: Content) -> some View {
        if solid {
            content.background(Color(.secondarySystemGroupedBackground), in: shape)
        } else {
            content.frostedGlass(in: shape)
        }
    }
}
