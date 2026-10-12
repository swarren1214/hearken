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
    /// Each question's pin and, once checked, its points. Players can move between
    /// questions, so each keeps its own.
    @State private var guesses: [CLLocationCoordinate2D?]
    @State private var results: [Int?]
    @State private var finished = false
    @State private var camera: MapCameraPosition
    @State private var drops = 0
    /// A touch-and-hold is in progress and has already dropped its pin.
    @State private var holding = false
    /// VoiceOver: name choices instead of a pin, since a map can't be tapped by place.
    @State private var choices: [MapQuestPlace] = []
    @AppStorage("mapquest.style") private var style: MapQuestMapStyle = .satellite
    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue

    private let mastery = MasteryService()

    init(category: MapQuestCategory) {
        self.category = category
        let round = category.round()
        _places = State(initialValue: round)
        _guesses = State(initialValue: Array(repeating: nil, count: round.count))
        _results = State(initialValue: Array(repeating: nil, count: round.count))
        _camera = State(initialValue: .rect(Self.rect(for: round.first?.area ?? .holyLand)))
    }

    private var current: MapQuestPlace? { places.indices.contains(index) ? places[index] : nil }
    private var guess: CLLocationCoordinate2D? { guesses.indices.contains(index) ? guesses[index] : nil }
    private var currentPoints: Int? { results.indices.contains(index) ? results[index] : nil }
    private var revealed: Bool { currentPoints != nil }
    private var scores: [Int] { results.compactMap { $0 } }
    private var allAnswered: Bool { !results.contains { $0 == nil } }

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: [.pan, .zoom]) {
                // The system's own map markers: red for the guess, green for the answer.
                if let guess {
                    Marker("Your Pin", systemImage: "mappin", coordinate: guess)
                        .tint(.red)
                        .annotationTitles(.hidden)
                }
                if revealed, let current {
                    Marker(current.name, systemImage: "flag.fill", coordinate: current.coordinate)
                        .tint(.green)
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
            return (currentPoints ?? 0) >= MapQuestCategory.closeEnough ? .success : .warning
        }
        .sensoryFeedback(.selection, trigger: index)
        .onAppear { prepareChoices() }
        // The Check button follows the app's accent; the chevrons, back and map style icons use the text color.
        .tint(accent.color)
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
                // The question, with chevrons to move between questions.
                HStack(spacing: 6) {
                    questionChevron("chevron.left", label: "Previous Question", enabled: index > 0) { go(to: index - 1) }
                    Text(current.prompt)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .id(index)
                        .transition(.opacity)
                    questionChevron("chevron.right", label: "Next Question", enabled: index + 1 < places.count) { go(to: index + 1) }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: index)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .frame(maxWidth: 560)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
    }

    /// A bare chevron: no button shape, just the icon, dimmed at the first and last question.
    private func questionChevron(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(enabled ? AnyShapeStyle(Color.primary) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                .frame(width: 32, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
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
                    .foregroundStyle(Color.primary)
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
                        Text(allAnswered ? "See Results" : "Next Place")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                } else if guess != nil {
                    // Appears once a pin is down.
                    Button {
                        check()
                    } label: {
                        Text("Check")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                } else {
                    // Keeps back and map style at the edges until then.
                    Spacer()
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            styleMenu
        }
        .animation(reduceMotion ? nil : .snappy, value: guess != nil)
    }

    /// Satellite or Map, with the checkmark on the right like every Hearken menu.
    private var styleMenu: some View {
        CheckMenu(MapQuestMapStyle.allCases.map { option in
            CheckMenuItem.choice(option.title, systemImage: option.symbol, isSelected: option == style) { style = option }
        }) {
            Image(systemName: "map")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.primary)
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
                    guesses[index] = choice.coordinate
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
        let points = currentPoints ?? 0
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
                ForEach(places.indices, id: \.self) { i in
                    let place = places[i]
                    let points = results[i] ?? 0
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
        guard !revealed, !finished, guesses.indices.contains(index) else { return }
        guesses[index] = coordinate
        drops += 1
    }

    private func check() {
        guard let current, let guess, !revealed else { return }
        let points = current.area.points(forKm: current.distanceKm(from: guess))
        results[index] = points
        // Recorded like an answered question: close pins count as remembered, and far ones
        // come back sooner in review.
        mastery.record(
            questionID: "\(category.id).\(current.id)",
            correct: points >= MapQuestCategory.closeEnough,
            in: modelContext
        )
        move(to: .rect(Self.rect(around: [guess, current.coordinate])))
    }

    /// After a reveal: on to the next question still unanswered, or the results once all are.
    private func next() {
        guard !allAnswered else {
            finish()
            return
        }
        let order = Array(index + 1 ..< places.count) + Array(0 ..< index)
        if let open = order.first(where: { results[$0] == nil }) { go(to: open) }
    }

    /// Shows another question as it was left: its whole area, or its pin and answer if checked.
    private func go(to newIndex: Int) {
        guard places.indices.contains(newIndex), newIndex != index else { return }
        index = newIndex
        prepareChoices()
        guard let current else { return }
        if let guess, revealed {
            move(to: .rect(Self.rect(around: [guess, current.coordinate])))
        } else {
            move(to: .rect(Self.rect(for: current.area)))
        }
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
        guesses = Array(repeating: nil, count: places.count)
        results = Array(repeating: nil, count: places.count)
        index = 0
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

#Preview {
    MapQuestView(category: MapQuestCatalog.bible)
}
