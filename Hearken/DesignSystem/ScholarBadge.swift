import SwiftUI

/// A Scholar Path medal: reeded edge, bevel ring, rank-colored face, emblem and rank dots,
/// with an optional progress ring around it. Geometry matches the design canvas exactly
/// (a 256-unit square, scaled to `size`).
///
/// At 40 pt and below it draws a simplified mark: the emblem on a plain bevel and face.
struct ScholarBadge: View {
    enum Status { case earned, next, locked }

    let rank: ScholarRank
    var size: CGFloat = 72
    var status: Status = .earned
    /// Progress toward the next badge, 0…1, drawn as a ring around the medal.
    var progress: Double? = nil
    /// The ring's color; the rank's light color by default.
    var tint: Color? = nil
    /// Animation hooks used by the unlock celebration.
    var emblemScale: CGFloat = 1
    var emblemTurn: Double = 0
    var dotsShown: Int? = nil
    var raysTurn: Double = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var palette: MedalPalette { rank.palette }
    private var isSmall: Bool { size <= 40 }

    var body: some View {
        ZStack {
            if status == .next {
                Circle()
                    .fill(RadialGradient(colors: [palette.light.opacity(0.55), palette.light.opacity(0)], center: .center, startRadius: size * 0.22, endRadius: size * 0.5))
                    .scaleEffect(breathing ? 1.04 : 0.92)
                    .opacity(breathing ? 0.75 : 0.25)
            }
            if let progress {
                ring(progress)
            }
            medal
                .scaleEffect(progress == nil ? 1 : 0.82)
                .saturation(status == .locked ? 0 : 1)
                .opacity(status == .locked ? 0.45 : 1)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if status == .locked { lockBadge }
        }
        .onAppear {
            guard status == .next, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathing = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rank.name) badge")
        .accessibilityValue(status == .locked ? "Locked" : status == .next ? "Next" : "Earned")
    }

    // MARK: Ring

    private func ring(_ value: Double) -> some View {
        let width = size * 10 / 256
        return ZStack {
            Circle().stroke(colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(tint ?? palette.light, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(size * 6 / 256)
        .animation(.smooth, value: value)
    }

    // MARK: Medal

    private var medal: some View {
        let s = size / 256
        return ZStack {
            if isSmall {
                Circle().fill(rimGradient).frame(width: 236 * s, height: 236 * s)
                Circle().fill(faceGradient(diameter: 200 * s)).frame(width: 200 * s, height: 200 * s)
            } else {
                Circle().fill(palette.rimDark).frame(width: 240 * s, height: 240 * s)
                Circle()
                    .stroke(palette.rim.opacity(0.9), style: StrokeStyle(lineWidth: 7 * s, dash: [5.06 * s, 5.06 * s]))
                    .frame(width: 232 * s, height: 232 * s)
                Circle().fill(rimGradient).frame(width: 218 * s, height: 218 * s)
                Circle()
                    .fill(faceGradient(diameter: 194 * s))
                    .overlay(Circle().stroke(palette.rimDark, lineWidth: 2 * s))
                    .frame(width: 194 * s, height: 194 * s)
                Circle().stroke(palette.rim.opacity(0.4), lineWidth: 1.5 * s).frame(width: 176 * s, height: 176 * s)
                Circle()
                    .trim(from: 0.6, to: 0.9)
                    .stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 10 * s, lineCap: .round))
                    .frame(width: 152 * s, height: 152 * s)
                Circle()
                    .fill(RadialGradient(colors: [palette.mid.opacity(0.35), palette.mid.opacity(0)], center: .center, startRadius: 0, endRadius: 54 * s))
                    .frame(width: 108 * s, height: 108 * s)
                    .offset(y: -4 * s)
            }
            emblem
                .scaleEffect(emblemScale)
                .rotationEffect(.degrees(emblemTurn))
            if !isSmall { dots }
        }
        .frame(width: size, height: size)
    }

    private var rimGradient: LinearGradient {
        LinearGradient(colors: [palette.light, palette.rim, palette.rimDark], startPoint: UnitPoint(x: 0.2, y: 0), endPoint: UnitPoint(x: 0.8, y: 1))
    }

    private func faceGradient(diameter: CGFloat) -> RadialGradient {
        RadialGradient(colors: [palette.top, palette.bottom], center: UnitPoint(x: 0.5, y: 0.32), startRadius: 0, endRadius: diameter * 0.75)
    }

    private var emblemGradient: LinearGradient {
        LinearGradient(stops: [.init(color: .white, location: 0), .init(color: palette.light, location: 0.35), .init(color: palette.mid, location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var dots: some View {
        let s = size / 256
        let count = rank.rawValue
        let shown = dotsShown ?? count
        return HStack(spacing: 4.2 * s) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(palette.light)
                    .frame(width: 6.8 * s, height: 6.8 * s)
                    .scaleEffect(index < shown ? 1 : 0)
                    .opacity(index < shown ? 1 : 0)
            }
        }
        .position(x: size / 2, y: 200 * s)
    }

    // MARK: Emblems

    /// Emblem geometry is drawn in the canvas's 256-unit space around (128, 132), then placed
    /// at (128, 124) at 90% (or larger in the small mark).
    private var emblemTransform: CGAffineTransform {
        let s = size / 256
        let scale: CGFloat = isSmall ? 1.08 : 0.9
        let center = CGPoint(x: 128, y: isSmall ? 126 : 124)
        return CGAffineTransform(translationX: -128, y: -132)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
            .concatenating(CGAffineTransform(scaleX: s, y: s))
    }

    private func shape(_ d: String) -> Path { SVGPath.parse(d).applying(emblemTransform) }

    private var lineScale: CGFloat { size / 256 * (isSmall ? 1.08 : 0.9) }

    @ViewBuilder
    private var emblem: some View {
        let w = lineScale
        switch rank {
        case .novice:
            ZStack {
                shape("M128 70 C132 112 138 124 178 132 C138 140 132 152 128 194 C124 152 118 140 78 132 C118 124 124 112 128 70 Z").fill(emblemGradient)
                shape("M128 104 C130 124 132 128 146 132 C132 136 130 140 128 160 C126 140 124 136 110 132 C124 128 126 124 128 104 Z").fill(Color.white.opacity(0.75))
            }
        case .apprentice:
            let pages = "M126 108 C110 96 92 96 76 102 L76 164 C92 158 110 158 126 170 Z M130 108 C146 96 164 96 180 102 L180 164 C164 158 146 158 130 170 Z"
            ZStack {
                shape(pages).fill(palette.mid.opacity(0.22))
                shape(pages).stroke(emblemGradient, style: StrokeStyle(lineWidth: 7 * w, lineCap: .round, lineJoin: .round))
                shape("M90 118 C100 115 108 115 114 119 M90 132 C100 129 108 129 114 133 M142 119 C148 115 156 115 166 118 M142 133 C148 129 156 129 166 132")
                    .stroke(palette.light, style: StrokeStyle(lineWidth: 4.5 * w, lineCap: .round))
            }
        case .investigator:
            ZStack {
                shape("M144 150 L172 178").stroke(emblemGradient, style: StrokeStyle(lineWidth: 13 * w, lineCap: .round))
                shape("M152 124 C152 141.7 137.7 156 120 156 C102.3 156 88 141.7 88 124 C88 106.3 102.3 92 120 92 C137.7 92 152 106.3 152 124 Z").fill(palette.mid.opacity(0.18))
                shape("M152 124 C152 141.7 137.7 156 120 156 C102.3 156 88 141.7 88 124 C88 106.3 102.3 92 120 92 C137.7 92 152 106.3 152 124 Z")
                    .stroke(emblemGradient, lineWidth: 9 * w)
                shape("M120 104 V116 M120 132 V144 M100 124 H112 M128 124 H140").stroke(palette.light, style: StrokeStyle(lineWidth: 4 * w, lineCap: .round))
                shape("M124.5 124 C124.5 126.5 122.5 128.5 120 128.5 C117.5 128.5 115.5 126.5 115.5 124 C115.5 121.5 117.5 119.5 120 119.5 C122.5 119.5 124.5 121.5 124.5 124 Z").fill(palette.light)
            }
        case .scholar:
            ZStack {
                shape("M170 80 C126 86 96 124 98 178 C140 170 168 132 170 80 Z").fill(emblemGradient)
                shape("M100 176 L158 98 M118 146 L142 150 M128 132 L152 136").stroke(palette.top, style: StrokeStyle(lineWidth: 4 * w, lineCap: .round))
            }
        case .sage:
            ZStack {
                if !isSmall {
                    shape(SageGeometry.rays)
                        .stroke(palette.light.opacity(0.9), style: StrokeStyle(lineWidth: 5 * w, lineCap: .round))
                        .rotationEffect(.degrees(raysTurn))
                }
                shape(SageGeometry.star).fill(emblemGradient)
                shape(SageGeometry.star).stroke(palette.light, style: StrokeStyle(lineWidth: 2 * w, lineJoin: .round))
                shape("M135 134 C135 137.9 131.9 141 128 141 C124.1 141 121 137.9 121 134 C121 130.1 124.1 127 128 127 C131.9 127 135 130.1 135 134 Z").fill(Color.white.opacity(0.85))
            }
        }
    }

    // MARK: Lock

    private var lockBadge: some View {
        let lock = max(14, size * 0.3)
        return Image(systemName: "lock.fill")
            .font(.system(size: lock * 0.5, weight: .semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white : Color(uiColor: .darkGray))
            .frame(width: lock, height: lock)
            .background(colorScheme == .dark ? Color(uiColor: .systemGray4) : Color.white, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .offset(x: size * 0.02, y: size * 0.02)
            .accessibilityHidden(true)
    }
}

/// The Sage star and its rays, computed once in the 256-unit space.
private enum SageGeometry {
    static let star: String = {
        var parts: [String] = []
        for i in 0..<10 {
            let angle = (-90.0 + Double(i) * 36) * .pi / 180
            let radius = i.isMultiple(of: 2) ? 44.0 : 19.0
            let x = 128 + radius * cos(angle), y = 134 + radius * sin(angle)
            parts.append("\(i == 0 ? "M" : "L")\(x) \(y)")
        }
        return parts.joined(separator: " ") + " Z"
    }()

    /// Seven rays: every 45°, skipping the bottom one (it would cross the rank dots).
    static let rays: String = {
        var parts: [String] = []
        for i in 0..<8 where i != 4 {
            let angle = (-90.0 + Double(i) * 45) * .pi / 180
            let (inner, outer) = i.isMultiple(of: 2) ? (64.0, 78.0) : (66.0, 76.0)
            parts.append("M\(128 + inner * cos(angle)) \(132 + inner * sin(angle)) L\(128 + outer * cos(angle)) \(132 + outer * sin(angle))")
        }
        return parts.joined(separator: " ")
    }()
}

/// A minimal SVG path parser: absolute M, L, H, V, C and Z, which is all the emblems use.
enum SVGPath {
    /// Parsed paths by source string. Emblems are redrawn every frame by the 3D coin.
    private static var cache: [String: Path] = [:]

    static func parse(_ d: String) -> Path {
        if let cached = cache[d] { return cached }
        let path = build(d)
        cache[d] = path
        return path
    }

    private static func build(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var number = ""
        for character in d {
            if character.isLetter {
                if !number.isEmpty { tokens.append(number); number = "" }
                tokens.append(String(character))
            } else if character == " " || character == "," {
                if !number.isEmpty { tokens.append(number); number = "" }
            } else if character == "-" && !number.isEmpty && number.last != "e" {
                tokens.append(number); number = "-"
            } else {
                number.append(character)
            }
        }
        if !number.isEmpty { tokens.append(number) }

        var index = 0
        var command = "M"
        var current = CGPoint.zero
        func next() -> CGFloat {
            defer { index += 1 }
            return index < tokens.count ? CGFloat(Double(tokens[index]) ?? 0) : 0
        }
        while index < tokens.count {
            if let first = tokens[index].first, first.isLetter {
                command = tokens[index]
                index += 1
                if command == "Z" { path.closeSubpath(); continue }
            }
            switch command {
            case "M":
                current = CGPoint(x: next(), y: next())
                path.move(to: current)
                command = "L"
            case "L":
                current = CGPoint(x: next(), y: next())
                path.addLine(to: current)
            case "H":
                current = CGPoint(x: next(), y: current.y)
                path.addLine(to: current)
            case "V":
                current = CGPoint(x: current.x, y: next())
                path.addLine(to: current)
            case "C":
                let c1 = CGPoint(x: next(), y: next())
                let c2 = CGPoint(x: next(), y: next())
                current = CGPoint(x: next(), y: next())
                path.addCurve(to: current, control1: c1, control2: c2)
            default:
                index += 1
            }
        }
        return path
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack { ForEach(ScholarRank.allCases) { ScholarBadge(rank: $0, size: 64) } }
        HStack { ForEach(ScholarRank.allCases) { ScholarBadge(rank: $0, size: 64, status: .locked) } }
        HStack { ForEach(ScholarRank.allCases) { ScholarBadge(rank: $0, size: 72, progress: 0.62) } }
        HStack { ForEach(ScholarRank.allCases) { ScholarBadge(rank: $0, size: 32) } }
    }
    .padding()
    .background(Color(hex: 0x101722))
}
