import MapKit
import SwiftData
import SwiftUI

/// Map Quest: a place is named, the player drops a pin on the map (satellite or standard
/// style), and the real spot is revealed with the distance and points. Eight places a round.
/// Each pin is recorded like an answered question, so far-off places come back in review.
struct MapQuestView: View {
    let category: MapQuestCategory

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var places: [MapQuestPlace]
    @State private var index = 0
    @State private var guess: CLLocationCoordinate2D?
    @State private var revealed = false
    @State private var scores: [Int] = []
    @State private var finished = false
    @State private var camera: MapCameraPosition
    @State private var drops = 0
    /// A touch-and-hold is in progress and has already dropped its pin.
    @State private var holding = false
    /// VoiceOver: name choices instead of a pin, since a map can't be tapped by place.
    @State private var choices: [MapQuestPlace] = []
    @AppStorage("mapquest.style") private var style: MapQuestMapStyle = .satellite

    private let mastery = MasteryService()

    init(category: MapQuestCategory) {
        self.category = category
        let round = category.round()
        _places = State(initialValue: round)
        _camera = State(initialValue: .rect(Self.rect(for: round.first?.area ?? .holyLand)))
    }

    private var current: MapQuestPlace? { places.indices.contains(index) ? places[index] : nil }
    private var lastPoints: Int { scores.last ?? 0 }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                if let guess {
                    Annotation("Your pin", coordinate: guess, anchor: .bottom) {
                        QuestPin(color: .red)
                    }
                    .annotationTitles(.hidden)
                }
                if revealed, let current {
                    Annotation(current.name, coordinate: current.coordinate, anchor: .bottom) {
                        QuestPin(color: .green)
                    }
                    if let guess {
                        MapPolyline(coordinates: [guess, current.coordinate])
                            .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 6]))
                    }
                }
            }
            .mapStyle(style.mapStyle)
            // Touch and hold to drop the pin, so panning and zooming never drop one by accident.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                    .onChanged { value in
                        guard !holding, case .second(true, let drag?) = value,
                              let coordinate = proxy.convert(drag.startLocation, from: .local) else { return }
                        holding = true
                        drop(at: coordinate)
                    }
                    .onEnded { _ in holding = false }
            )
            .accessibilityLabel("Map")
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) {
            VStack { bottomPanel }
                .animation(reduceMotion ? nil : .snappy, value: revealed)
                .animation(reduceMotion ? nil : .snappy, value: finished)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: drops)
        .sensoryFeedback(trigger: scores.count) { old, new in
            guard new > old else { return nil }
            return lastPoints >= MapQuestCategory.closeEnough ? .success : .warning
        }
        .onAppear { prepareChoices() }
    }

    // MARK: Top

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(finished ? category.title : "\(min(index + 1, places.count)) of \(places.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(scores.reduce(0, +))", systemImage: "scope")
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(scores.reduce(0, +)) points")
            }
            .overlay {
                // How to play, centered between the progress and the score, until the pin is checked.
                if !finished, !revealed, !voiceOver {
                    Text("Touch and Hold to Drop a Pin")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 64)
                        .transition(.opacity)
                }
            }
            if !finished, let current {
                Text(current.prompt)
                    .font(.title3.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    // MARK: Bottom

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            if finished {
                card { summary }
            } else {
                if revealed, let current {
                    card { result(current) }
                } else if voiceOver {
                    card { nameChoices }
                }
                controls
            }
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    /// A frosted card for the answer, the VoiceOver choices and the summary.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedGlass(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 16, y: 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Back, the main action (Check, then Next Place), and the map style.
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .accessibilityLabel("Back")

            Group {
                if revealed {
                    Button {
                        next()
                    } label: {
                        Text(index + 1 < places.count ? "Next Place" : "See Results")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                } else {
                    Button {
                        check()
                    } label: {
                        Text("Check")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .disabled(guess == nil)
                    .accessibilityHint(guess == nil ? "Touch and hold the map to drop a pin first." : "")
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            styleMenu
        }
    }

    /// Satellite or Map, with the checkmark on the right like every Hearken menu.
    private var styleMenu: some View {
        CheckMenu(MapQuestMapStyle.allCases.map { option in
            CheckMenuItem.choice(option.title, systemImage: option.symbol, isSelected: option == style) { style = option }
        }) {
            Image(systemName: "map")
                .font(.title3.weight(.semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel("Map Style")
        .accessibilityValue(style.title)
    }

    /// VoiceOver: pick the place by name from four.
    private var nameChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose the place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(choices) { choice in
                Button {
                    guess = choice.coordinate
                    check()
                } label: {
                    Text(choice.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private func result(_ place: MapQuestPlace) -> some View {
        let points = lastPoints
        let km = guess.map { place.distanceKm(from: $0) } ?? 0
        let color: Color = points >= MapQuestCategory.closeEnough ? .green : (points >= 30 ? .orange : .red)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("\(points)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color, in: Circle())
                    .accessibilityLabel("\(points) points")
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).font(.headline)
                    Text(distanceLabel(km))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text(place.detail)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            if let reference = place.reference {
                Label(reference, systemImage: "book")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var summary: some View {
        let total = scores.reduce(0, +)
        let close = scores.filter { $0 >= MapQuestCategory.closeEnough }.count

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(total) of \(places.count * 100) points")
                    .font(.title2.bold())
                Text("\(close) of \(places.count) pins close · +\(close * MasteryConfig.standard.xpPerCorrect) XP")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(scores.indices, id: \.self) { i in
                    let place = places[i]
                    let points = scores[i]
                    HStack {
                        Text(place.name).font(.subheadline)
                        Spacer()
                        Text("\(points)")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(points >= MapQuestCategory.closeEnough ? Color.green : .secondary)
                    }
                }
            }
            HStack(spacing: 10) {
                Button("Done") { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Button {
                    playAgain()
                } label: {
                    Text("Play Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: Play

    private func drop(at coordinate: CLLocationCoordinate2D) {
        guard !revealed, !finished, current != nil else { return }
        guess = coordinate
        drops += 1
    }

    private func check() {
        guard let current, let guess, !revealed else { return }
        let points = current.area.points(forKm: current.distanceKm(from: guess))
        scores.append(points)
        // Recorded like an answered question: close pins count as remembered, and far ones
        // come back sooner in review.
        mastery.record(
            questionID: "\(category.id).\(current.id)",
            correct: points >= MapQuestCategory.closeEnough,
            in: modelContext
        )
        revealed = true
        move(to: .rect(Self.rect(around: [guess, current.coordinate])))
    }

    private func next() {
        guard index + 1 < places.count else {
            finish()
            return
        }
        index += 1
        guess = nil
        revealed = false
        prepareChoices()
        if let current { move(to: .rect(Self.rect(for: current.area))) }
    }

    private func finish() {
        finished = true
        let close = scores.filter { $0 >= MapQuestCategory.closeEnough }.count
        modelContext.insert(GameSession(
            gameType: "mapQuest",
            subjectID: category.id,
            correct: close,
            total: places.count,
            xpEarned: close * MasteryConfig.standard.xpPerCorrect
        ))
    }

    private func playAgain() {
        places = category.round()
        index = 0
        guess = nil
        revealed = false
        scores = []
        finished = false
        prepareChoices()
        if let current { move(to: .rect(Self.rect(for: current.area))) }
    }

    private func prepareChoices() {
        guard let current else { return }
        let others = category.places.filter { $0.id != current.id }.shuffled().prefix(3)
        choices = ([current] + others).shuffled()
    }

    private func move(to position: MapCameraPosition) {
        if reduceMotion {
            camera = position
        } else {
            withAnimation(.easeInOut(duration: 0.9)) { camera = position }
        }
    }

    private func distanceLabel(_ km: Double) -> String {
        if km < 1 { return "Right on it" }
        // Miles or kilometers, following the person's region.
        let distance = Measurement(value: km, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        return "\(distance) away"
    }

    /// The whole area, fitted to the screen: a map rect is always shown in full, so every
    /// answer in the area starts on screen whatever the device's shape.
    private static func rect(for area: MapQuestArea) -> MKMapRect {
        let region = area.region
        let corner1 = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude + region.span.latitudeDelta / 2,
            longitude: region.center.longitude - region.span.longitudeDelta / 2))
        let corner2 = MKMapPoint(CLLocationCoordinate2D(
            latitude: region.center.latitude - region.span.latitudeDelta / 2,
            longitude: region.center.longitude + region.span.longitudeDelta / 2))
        return MKMapRect(
            x: min(corner1.x, corner2.x), y: min(corner1.y, corner2.y),
            width: abs(corner2.x - corner1.x), height: abs(corner2.y - corner1.y)
        )
    }

    /// A map rect showing every coordinate, with room around them for the top and bottom panels.
    private static func rect(around coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let points = coordinates.map(MKMapPoint.init)
        let minX = points.map(\.x).min() ?? 0, maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0, maxY = points.map(\.y).max() ?? 0
        // At least ~6 km across, so a near-perfect pin doesn't zoom in to street level.
        let latitude = coordinates.first?.latitude ?? 0
        let minimum = MKMapPointsPerMeterAtLatitude(latitude) * 6000
        let width = max(maxX - minX, minimum), height = max(maxY - minY, minimum)
        let midX = (minX + maxX) / 2, midY = (minY + maxY) / 2
        let rect = MKMapRect(x: midX - width / 2, y: midY - height / 2, width: width, height: height)
        return rect.insetBy(dx: -width * 0.6, dy: -height * 1.1)
    }
}

/// How the Map Quest map looks. Both show place names; modern names can give an answer away,
/// so the questions lean on events rather than the names themselves.
enum MapQuestMapStyle: String, CaseIterable, Identifiable {
    case standard, satellite

    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Map"
        case .satellite: "Satellite"
        }
    }
    var symbol: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        }
    }
    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        case .satellite: .hybrid(elevation: .flat, pointsOfInterest: .excludingAll)
        }
    }
}

/// A map pin: a colored ball on a short white stem.
private struct QuestPin: View {
    let color: Color

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(color)
                .frame(width: 22, height: 22)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            Rectangle()
                .fill(.white)
                .frame(width: 3, height: 12)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    MapQuestView(category: MapQuestCatalog.bible)
}
