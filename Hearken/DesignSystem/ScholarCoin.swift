import CoreMotion
import SwiftUI

/// A Scholar Path medal as a 3D coin: the medal art on the front, an engraved back, and a
/// reeded metal edge made of stacked discs. It idles with a slow sway and turns all the way over
/// every few seconds, light sweeping across its face. Drag or flick it to spin it by hand; it
/// tilts a little as the phone moves. Used where a medal is the hero (the unlock celebration and
/// the badge detail). Lists keep the flat `ScholarBadge`.
///
/// Reduce Motion: no idle motion, no intro spin; the coin rests at a slight angle.
struct ScholarCoin: View {
    let rank: ScholarRank
    var size: CGFloat = 200
    /// Sway and turn on its own.
    var idles: Bool = true
    /// Spin into place when it appears.
    var introSpin: Bool = false
    /// Face animation hooks, passed through to the medal art.
    var emblemScale: CGFloat = 1
    var emblemTurn: Double = 0
    var dotsShown: Int? = nil
    var raysTurn: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = Date()
    @State private var introCancelled = false
    @State private var drag: Drag?
    @State private var settle: Settle?
    @State private var motion = CoinMotion.shared

    private struct Drag { var start: Double; var translation: CGFloat }
    /// Settling after a drag, in "base" degrees (rest angle excluded).
    private struct Settle { var from: Double; var to: Double; var at: Date }

    private static let introDuration = 1.6
    private static let settleDuration = 0.9
    private static let dragGain = 0.8
    private static let period = 9.0

    var body: some View {
        TimelineView(.animation) { context in
            let current = pose(at: context.date)
            CoinRender(rank: rank, size: size, angle: current.y, tilt: current.x, bob: current.bob,
                       emblemScale: emblemScale, emblemTurn: emblemTurn, dotsShown: dotsShown, raysTurn: raysTurn)
        }
        .frame(width: size, height: size * 1.16, alignment: .top)
        .contentShape(.rect)
        .gesture(spin)
        .onAppear { if !reduceMotion { motion.start() } }
        .onDisappear { motion.stop() }
        .sensoryFeedback(.impact(weight: .light), trigger: settle?.to)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank.name) badge")
        .accessibilityHint("Drag to spin the medal")
    }

    // MARK: Gesture

    private var spin: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if drag == nil {
                    // Mostly vertical drags belong to the scroll view.
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    drag = Drag(start: pose(at: .now).y, translation: 0)
                    settle = nil
                    introCancelled = true
                }
                drag?.translation = value.translation.width
            }
            .onEnded { value in
                guard let drag else { return }
                let rest = restAngle
                let end = drag.start + Double(value.translation.width) * Self.dragGain - rest
                let flung = drag.start + Double(value.predictedEndTranslation.width) * Self.dragGain - rest
                // Land face up, a whole number of turns from where a flick would carry it.
                let target = (flung / 360).rounded() * 360
                settle = Settle(from: end, to: target, at: .now)
                self.drag = nil
            }
    }

    // MARK: Pose

    private var idling: Bool { idles && !reduceMotion }
    /// Where the coin rests when it isn't idling: turned a little so it still reads as an object.
    private var restAngle: Double { idling ? 0 : -16 }

    private struct Pose { var y: Double; var x: Double; var bob: Double }

    private func pose(at date: Date) -> Pose {
        let tiltY = reduceMotion ? 0 : max(-12, min(12, motion.roll * 40))
        let tiltX = reduceMotion ? 0 : max(-10, min(10, motion.pitch * 30))
        if let drag {
            return Pose(y: drag.start + Double(drag.translation) * Self.dragGain, x: 4 + tiltX, bob: 0)
        }

        var base = 0.0
        var idleFrom = appeared
        if introSpin && !introCancelled && !reduceMotion {
            let p = min(date.timeIntervalSince(appeared) / Self.introDuration, 1)
            base = -540 * (1 - Ease.outCubic(p))
            idleFrom = appeared.addingTimeInterval(Self.introDuration)
        }
        if let settle {
            let p = min(date.timeIntervalSince(settle.at) / Self.settleDuration, 1)
            base = settle.from + (settle.to - settle.from) * Ease.outBack(p)
            idleFrom = settle.at.addingTimeInterval(Self.settleDuration)
        }

        var y = base + restAngle
        var x = idling ? 0 : 6.0
        if idling {
            let since = date.timeIntervalSince(idleFrom)
            if since > 0 {
                let weight = Ease.inOut(min(since / 1.2, 1))
                let idle = Self.idle(since)
                y += weight * idle.y
                x += weight * idle.x
            }
        }
        let bob = reduceMotion ? 0 : sin(date.timeIntervalSinceReferenceDate * 2 * .pi / 4.5)
        return Pose(y: y + tiltY, x: x + tiltX, bob: bob)
    }

    /// Sway left and right twice, hold, then one full turn. Same timing as the design canvas.
    private static func idle(_ seconds: Double) -> (y: Double, x: Double) {
        let p = (seconds / period).truncatingRemainder(dividingBy: 1)
        let y: Double
        switch p {
        case ..<0.28: y = lerp(-24, 24, Ease.inOut(p / 0.28))
        case ..<0.56: y = lerp(24, -24, Ease.inOut((p - 0.28) / 0.28))
        case ..<0.70: y = -24
        case ..<0.90: y = lerp(-24, 336, Ease.inOut((p - 0.70) / 0.20))
        default: y = 336
        }
        return (y, 6 * cos(p * 4 * .pi))
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}

private enum Ease {
    static func inOut(_ t: Double) -> Double { t * t * (3 - 2 * t) }
    static func outCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }
    static func outBack(_ t: Double) -> Double {
        let c1 = 1.4, c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }
}

// MARK: - Rendering

/// Draws the coin at a turn of `angle` degrees about its vertical axis. The faces and each edge
/// disc are squeezed by cos(angle) and shifted by their depth times sin(angle), drawn back to
/// front, so the rim shows as a band when the coin turns edge-on.
private struct CoinRender: View {
    let rank: ScholarRank
    let size: CGFloat
    let angle: Double
    let tilt: Double
    let bob: Double
    let emblemScale: CGFloat
    let emblemTurn: Double
    let dotsShown: Int?
    let raysTurn: Double

    private let layers = 12

    var body: some View {
        let theta = angle * .pi / 180
        let c = cos(theta), s = sin(theta)
        let thickness = size * 0.075
        // Keep each disc a sliver wide edge-on, so the stack still reads as a solid band.
        let squeeze = max(abs(c), Double(thickness) / Double(layers) * 1.8 / Double(size))
        let order = c >= 0 ? Array(0..<layers) : Array((0..<layers).reversed())
        let palette = rank.palette

        ZStack(alignment: .top) {
            // Shadow on the "floor": narrows edge-on and as the coin floats up.
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: size * 0.4))
                .frame(width: size * 0.78 * max(abs(c), 0.25) + thickness, height: size * 0.11)
                .scaleEffect(1 - bob * 0.08)
                .opacity(0.8 - bob * 0.15)
                .offset(y: size * 1.04)

            ZStack {
                ForEach(order, id: \.self) { index in
                    let z = (Double(index) / Double(layers - 1) - 0.5) * Double(thickness)
                    Circle()
                        .fill(RadialGradient(colors: [palette.light, index.isMultiple(of: 2) ? palette.rim : palette.rimDark, palette.rimDark],
                                             center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.55))
                        .frame(width: size * 240 / 256, height: size * 240 / 256)
                        .scaleEffect(x: squeeze, y: 1)
                        .offset(x: z * s)
                }

                Group {
                    if c >= 0 {
                        front(sweep: s)
                    } else {
                        CoinBack(rank: rank, size: size)
                    }
                }
                .brightness(-0.2 * (1 - abs(c)))
                .scaleEffect(x: squeeze, y: 1)
                .offset(x: (c >= 0 ? 1 : -1) * Double(thickness) / 2 * s)
            }
            .frame(width: size, height: size)
            .rotation3DEffect(.degrees(tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
            .offset(y: -bob * size * 0.04)
        }
        .frame(width: size, height: size * 1.16, alignment: .top)
    }

    private func front(sweep s: Double) -> some View {
        ScholarBadge(rank: rank, size: size, emblemScale: emblemScale, emblemTurn: emblemTurn, dotsShown: dotsShown, raysTurn: raysTurn)
            .overlay {
                // Light that slides across the face as it turns.
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: size * 0.32)
                    .rotationEffect(.degrees(18))
                    .offset(x: -s * size * 0.95)
                    .opacity(0.2 + 0.8 * min(abs(s) * 1.6, 1))
                    .frame(width: size, height: size)
                    .mask(Circle().padding(size * 19 / 256))
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
    }
}

/// The engraved back: rim and bevel like the front, then HEARKEN, the rank numeral, the rank
/// name and its dots.
private struct CoinBack: View {
    let rank: ScholarRank
    let size: CGFloat

    var body: some View {
        let p = rank.palette
        let unit = size / 256
        ZStack {
            Circle().fill(p.rimDark).frame(width: 240 * unit, height: 240 * unit)
            Circle()
                .strokeBorder(p.rim.opacity(0.9), style: StrokeStyle(lineWidth: 7 * unit, dash: [5.06 * unit, 5.06 * unit]))
                .frame(width: 236 * unit, height: 236 * unit)
            Circle()
                .fill(LinearGradient(colors: [p.light, p.rim, p.rimDark], startPoint: UnitPoint(x: 0.8, y: 0), endPoint: UnitPoint(x: 0.2, y: 1)))
                .frame(width: 218 * unit, height: 218 * unit)
            Circle()
                .fill(RadialGradient(colors: [p.top, p.bottom], center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: 140 * unit))
                .overlay(Circle().strokeBorder(p.rimDark, lineWidth: 2 * unit))
                .frame(width: 194 * unit, height: 194 * unit)
            Circle()
                .strokeBorder(p.rim.opacity(0.4), lineWidth: 1.5 * unit)
                .frame(width: 176 * unit, height: 176 * unit)

            VStack(spacing: 8 * unit) {
                Text("HEARKEN")
                    .font(.system(size: 14 * unit, weight: .heavy))
                    .tracking(3 * unit)
                    .opacity(0.75)
                Text(numeral)
                    .font(.system(size: 50 * unit, weight: .heavy, design: .serif))
                    .shadow(color: .black.opacity(0.5), radius: 0, y: 1.5 * unit)
                Text(rank.name.uppercased())
                    .font(.system(size: 16 * unit, weight: .heavy))
                    .tracking(2.4 * unit)
                HStack(spacing: 6 * unit) {
                    ForEach(0..<rank.rawValue, id: \.self) { _ in
                        Circle().frame(width: 7 * unit, height: 7 * unit)
                    }
                }
                .padding(.top, 2 * unit)
            }
            .foregroundStyle(p.light)
        }
        .frame(width: size, height: size)
    }

    private var numeral: String { ["I", "II", "III", "IV", "V"][max(0, min(4, rank.rawValue - 1))] }
}

// MARK: - Device tilt

/// Shared device-motion reader so hero coins lean a little as the phone moves. The baseline
/// drifts toward how the phone is held, so only movement tilts the coin. Device motion needs
/// no permission prompt.
@Observable
@MainActor
final class CoinMotion {
    static let shared = CoinMotion()

    private(set) var roll = 0.0
    private(set) var pitch = 0.0

    @ObservationIgnored private let manager = CMMotionManager()
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var baseline: (roll: Double, pitch: Double)?

    func start() {
        users += 1
        guard users == 1, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 30
        manager.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let data else { return }
            let roll = data.attitude.roll, pitch = data.attitude.pitch
            MainActor.assumeIsolated { CoinMotion.shared.update(roll: roll, pitch: pitch) }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        manager.stopDeviceMotionUpdates()
        baseline = nil
        roll = 0
        pitch = 0
    }

    private func update(roll: Double, pitch: Double) {
        var base = baseline ?? (roll: roll, pitch: pitch)
        base.roll += (roll - base.roll) * 0.02
        base.pitch += (pitch - base.pitch) * 0.02
        baseline = base
        // Light smoothing so the coin doesn't jitter.
        self.roll += ((roll - base.roll) - self.roll) * 0.3
        self.pitch += ((pitch - base.pitch) - self.pitch) * 0.3
    }
}
