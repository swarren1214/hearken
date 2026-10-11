import CoreLocation
import MapKit

// Map Quest: name a place, drop a pin, see how close you got.
//
// Each place belongs to an area that sets the starting view and how strict the scoring is:
// a pin 5 km off is excellent across the Mediterranean but poor around Jerusalem.
// Coordinates are the generally accepted modern sites; traditional or debated sites say so
// in their detail line.

/// Where a question opens the map, and how distance turns into points.
nonisolated struct MapQuestArea: Sendable {
    let center: CLLocationCoordinate2D
    let latitudeSpan: Double
    let longitudeSpan: Double
    /// Within this distance: full marks.
    let perfectKm: Double
    /// At or past this distance: no points.
    let zeroKm: Double

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: longitudeSpan))
    }

    /// 0–100, falling off evenly between the perfect and zero distances.
    func points(forKm km: Double) -> Int {
        guard km > perfectKm else { return 100 }
        let fraction = 1 - (km - perfectKm) / (zeroKm - perfectKm)
        return Int((max(0, min(1, fraction)) * 100).rounded())
    }

    // Bible
    static let holyLand = MapQuestArea(center: .init(latitude: 32.0, longitude: 35.3), latitudeSpan: 2.6, longitudeSpan: 1.9, perfectKm: 3, zeroKm: 60)
    static let nearEast = MapQuestArea(center: .init(latitude: 31.5, longitude: 39.0), latitudeSpan: 17, longitudeSpan: 16, perfectKm: 30, zeroKm: 700)
    static let mediterranean = MapQuestArea(center: .init(latitude: 38.0, longitude: 24.5), latitudeSpan: 14, longitudeSpan: 28, perfectKm: 40, zeroKm: 900)
    // Church history
    static let northeast = MapQuestArea(center: .init(latitude: 42.4, longitude: -77.0), latitudeSpan: 5.5, longitudeSpan: 11, perfectKm: 8, zeroKm: 250)
    static let midwest = MapQuestArea(center: .init(latitude: 40.2, longitude: -93.5), latitudeSpan: 4.6, longitudeSpan: 7, perfectKm: 8, zeroKm: 250)
    static let unitedStates = MapQuestArea(center: .init(latitude: 39.5, longitude: -98.0), latitudeSpan: 26, longitudeSpan: 58, perfectKm: 30, zeroKm: 800)
}

nonisolated struct MapQuestPlace: Identifiable, Sendable {
    let id: String
    /// The answer's name, shown on the map after the reveal.
    let name: String
    /// The question.
    let prompt: String
    /// One line shown after the reveal.
    let detail: String
    /// A scripture reference for reading more, if there is one.
    let reference: String?
    let latitude: Double
    let longitude: Double
    let area: MapQuestArea

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    /// Kilometers from a guess to this place.
    func distanceKm(from guess: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: guess.latitude, longitude: guess.longitude)) / 1000
    }
}

nonisolated struct MapQuestCategory: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let places: [MapQuestPlace]

    /// Places in one round.
    static let roundLength = 8
    /// A pin earning at least this many points counts as "close" (and as remembered, for review).
    static let closeEnough = 70

    func round() -> [MapQuestPlace] {
        Array(places.shuffled().prefix(Self.roundLength))
    }
}

nonisolated enum MapQuestCatalog {
    static let all: [MapQuestCategory] = [bible, churchHistory]

    static func category(_ id: String) -> MapQuestCategory? { all.first { $0.id == id } }

    static let bible = MapQuestCategory(
        id: "mapquest.bible",
        title: "Bible Geography",
        subtitle: "The Holy Land, the Near East and Paul's journeys",
        symbol: "globe.europe.africa.fill",
        places: [
            // The Holy Land
            .init(id: "bethlehem", name: "Bethlehem", prompt: "Where was Jesus born?",
                  detail: "About 9 km south of Jerusalem, the city of David.", reference: "Luke 2:4–7",
                  latitude: 31.7054, longitude: 35.2024, area: .holyLand),
            .init(id: "nazareth", name: "Nazareth", prompt: "In which town did Jesus grow up?",
                  detail: "A small village in the hills of Galilee.", reference: "Luke 2:39–40",
                  latitude: 32.7019, longitude: 35.2978, area: .holyLand),
            .init(id: "capernaum", name: "Capernaum", prompt: "Which town on the Sea of Galilee became the center of Jesus's ministry?",
                  detail: "On the north shore of the Sea of Galilee; Peter's home was here.", reference: "Matthew 4:13",
                  latitude: 32.8803, longitude: 35.5753, area: .holyLand),
            .init(id: "cana", name: "Cana", prompt: "Where did Jesus turn water into wine?",
                  detail: "Traditionally Kafr Kanna, a few kilometers northeast of Nazareth.", reference: "John 2:1–11",
                  latitude: 32.7466, longitude: 35.3388, area: .holyLand),
            .init(id: "jericho", name: "Jericho", prompt: "Whose walls fell when Joshua's army shouted?",
                  detail: "Jericho, near the Jordan River just north of the Dead Sea.", reference: "Joshua 6",
                  latitude: 31.8710, longitude: 35.4440, area: .holyLand),
            .init(id: "jerusalem", name: "Jerusalem", prompt: "Where did Solomon build the temple?",
                  detail: "On Mount Moriah in Jerusalem.", reference: "1 Kings 6; 2 Chronicles 3:1",
                  latitude: 31.7780, longitude: 35.2354, area: .holyLand),
            .init(id: "joppa", name: "Joppa", prompt: "From which port did Jonah sail to flee from the Lord?",
                  detail: "Joppa, today Jaffa in Tel Aviv. Peter also saw his vision of the sheet here.", reference: "Jonah 1:3",
                  latitude: 32.0543, longitude: 34.7522, area: .holyLand),
            .init(id: "carmel", name: "Mount Carmel", prompt: "Where did Elijah challenge the prophets of Baal?",
                  detail: "Traditionally El-Muhraka, on the Carmel ridge above the Jezreel Valley.", reference: "1 Kings 18:19–39",
                  latitude: 32.6684, longitude: 35.0918, area: .holyLand),
            .init(id: "hebron", name: "Hebron", prompt: "Where were Abraham and Sarah buried?",
                  detail: "The cave of Machpelah, in Hebron.", reference: "Genesis 23:19; 25:9–10",
                  latitude: 31.5245, longitude: 35.1107, area: .holyLand),
            .init(id: "caesarea-philippi", name: "Caesarea Philippi", prompt: "Near which city did Peter testify, \u{201C}Thou art the Christ\u{201D}?",
                  detail: "At the foot of Mount Hermon, by a source of the Jordan.", reference: "Matthew 16:13–16",
                  latitude: 33.2482, longitude: 35.6943, area: .holyLand),
            .init(id: "bethabara", name: "Bethabara", prompt: "Where did John baptize, \u{201C}beyond Jordan\u{201D}?",
                  detail: "Traditionally the baptism site on the Jordan's east bank, near Jericho.", reference: "John 1:28",
                  latitude: 31.8370, longitude: 35.5500, area: .holyLand),
            .init(id: "bethel", name: "Bethel", prompt: "Where did Jacob dream of a ladder reaching to heaven?",
                  detail: "Bethel, about 17 km north of Jerusalem.", reference: "Genesis 28:10–19",
                  latitude: 31.9300, longitude: 35.2400, area: .holyLand),
            .init(id: "jacobs-well", name: "Jacob's Well", prompt: "Where did Jesus meet the Samaritan woman at a well?",
                  detail: "Jacob's Well, near Sychar and ancient Shechem.", reference: "John 4:5–7",
                  latitude: 32.2094, longitude: 35.2853, area: .holyLand),
            // The Near East
            .init(id: "sinai", name: "Mount Sinai", prompt: "Where did Moses receive the Ten Commandments?",
                  detail: "Traditionally Jebel Musa in the southern Sinai; the exact mountain is debated.", reference: "Exodus 19–20",
                  latitude: 28.5394, longitude: 33.9750, area: .nearEast),
            .init(id: "babylon", name: "Babylon", prompt: "Where was Judah carried captive by Nebuchadnezzar?",
                  detail: "On the Euphrates, south of modern Baghdad.", reference: "2 Kings 24–25",
                  latitude: 32.5364, longitude: 44.4209, area: .nearEast),
            .init(id: "nineveh", name: "Nineveh", prompt: "Which city did Jonah warn to repent?",
                  detail: "The Assyrian capital on the Tigris, across from modern Mosul.", reference: "Jonah 3",
                  latitude: 36.3594, longitude: 43.1528, area: .nearEast),
            .init(id: "ur", name: "Ur", prompt: "Abraham's family set out from which city?",
                  detail: "Ur of the Chaldees, near the Euphrates in southern Iraq.", reference: "Genesis 11:31",
                  latitude: 30.9625, longitude: 46.1031, area: .nearEast),
            .init(id: "damascus", name: "Damascus", prompt: "Saul was on his way to which city when he saw the risen Lord?",
                  detail: "Damascus, one of the oldest continuously inhabited cities.", reference: "Acts 9:1–9",
                  latitude: 33.5138, longitude: 36.2765, area: .nearEast),
            // Paul's journeys
            .init(id: "tarsus", name: "Tarsus", prompt: "What was Paul's hometown?",
                  detail: "Tarsus in Cilicia, on the southern coast of modern Turkey.", reference: "Acts 22:3",
                  latitude: 36.9177, longitude: 34.8928, area: .mediterranean),
            .init(id: "antioch", name: "Antioch", prompt: "Where were the disciples first called Christians?",
                  detail: "Antioch in Syria, today Antakya, Turkey.", reference: "Acts 11:26",
                  latitude: 36.2021, longitude: 36.1600, area: .mediterranean),
            .init(id: "athens", name: "Athens", prompt: "Where did Paul preach about the \u{201C}unknown god\u{201D} on Mars' Hill?",
                  detail: "The Areopagus, below the Acropolis in Athens.", reference: "Acts 17:22–23",
                  latitude: 37.9721, longitude: 23.7236, area: .mediterranean),
            .init(id: "corinth", name: "Corinth", prompt: "Paul spent eighteen months building up the church in which Greek city?",
                  detail: "Corinth, on the narrow isthmus west of Athens.", reference: "Acts 18:1–11",
                  latitude: 37.9061, longitude: 22.8792, area: .mediterranean),
            .init(id: "ephesus", name: "Ephesus", prompt: "Where did a riot break out over the goddess Diana?",
                  detail: "Ephesus, on the western coast of modern Turkey.", reference: "Acts 19:23–41",
                  latitude: 37.9411, longitude: 27.3419, area: .mediterranean),
            .init(id: "patmos", name: "Patmos", prompt: "On which island did John receive the Revelation?",
                  detail: "A small Greek island in the Aegean Sea.", reference: "Revelation 1:9",
                  latitude: 37.3100, longitude: 26.5470, area: .mediterranean),
            .init(id: "rome", name: "Rome", prompt: "Where was Paul taken as a prisoner at the end of the book of Acts?",
                  detail: "Rome, where he lived two years in his own hired house.", reference: "Acts 28:16, 30",
                  latitude: 41.9028, longitude: 12.4964, area: .mediterranean),
        ]
    )

    static let churchHistory = MapQuestCategory(
        id: "mapquest.churchhistory",
        title: "Church History Geography",
        subtitle: "From Vermont to the Salt Lake Valley",
        symbol: "mappin.and.ellipse",
        places: [
            // New York, Pennsylvania, Ohio, Vermont
            .init(id: "sharon", name: "Sharon, Vermont", prompt: "Where was Joseph Smith born?",
                  detail: "December 23, 1805. A memorial marks the farm today.", reference: nil,
                  latitude: 43.7920, longitude: -72.4900, area: .northeast),
            .init(id: "sacred-grove", name: "The Sacred Grove", prompt: "Where did the First Vision take place?",
                  detail: "Woods near the Smith farm outside Palmyra, New York, spring 1820.", reference: "Joseph Smith—History 1:14–20",
                  latitude: 43.0400, longitude: -77.2370, area: .northeast),
            .init(id: "cumorah", name: "Hill Cumorah", prompt: "Where did Joseph receive the gold plates?",
                  detail: "A hill a few kilometers south of the Smith farm, in Manchester, New York.", reference: "Joseph Smith—History 1:51–52, 59",
                  latitude: 42.9930, longitude: -77.2260, area: .northeast),
            .init(id: "harmony", name: "Harmony, Pennsylvania", prompt: "Near the Susquehanna River, where was the Aaronic Priesthood restored?",
                  detail: "Harmony (today Oakland), Pennsylvania, May 1829.", reference: "Joseph Smith—History 1:68–72",
                  latitude: 41.9600, longitude: -75.6100, area: .northeast),
            .init(id: "fayette", name: "Fayette, New York", prompt: "Where was the Church organized on April 6, 1830?",
                  detail: "The Peter Whitmer Sr. farm in Fayette, New York.", reference: "D&C 20:1",
                  latitude: 42.8630, longitude: -76.8890, area: .northeast),
            .init(id: "kirtland", name: "Kirtland, Ohio", prompt: "Where was the first temple of this dispensation dedicated?",
                  detail: "The Kirtland Temple, dedicated March 27, 1836.", reference: "D&C 109",
                  latitude: 41.6253, longitude: -81.3620, area: .northeast),
            // Missouri, Illinois, Nebraska
            .init(id: "independence", name: "Independence, Missouri", prompt: "Which town was named the center place of Zion?",
                  detail: "Independence, in Jackson County, Missouri, 1831.", reference: "D&C 57:1–3",
                  latitude: 39.0911, longitude: -94.4155, area: .midwest),
            .init(id: "liberty", name: "Liberty Jail", prompt: "Where was Joseph imprisoned through the winter of 1838–39?",
                  detail: "Liberty, Missouri, where he wrote the letters in D&C 121–123.", reference: "D&C 121–123",
                  latitude: 39.2461, longitude: -94.4191, area: .midwest),
            .init(id: "far-west", name: "Far West, Missouri", prompt: "Where were temple cornerstones laid in Caldwell County in 1838?",
                  detail: "Far West, Missouri; the temple was never built.", reference: "D&C 115:7–11",
                  latitude: 39.7612, longitude: -94.0782, area: .midwest),
            .init(id: "adam-ondi-ahman", name: "Adam-ondi-Ahman", prompt: "Where, the Lord revealed, did Adam bless his posterity?",
                  detail: "In Daviess County, Missouri, above the Grand River.", reference: "D&C 116; 107:53",
                  latitude: 39.9800, longitude: -93.9800, area: .midwest),
            .init(id: "nauvoo", name: "Nauvoo, Illinois", prompt: "Which city did the Saints build on a bend of the Mississippi River?",
                  detail: "Nauvoo, Illinois, settled from 1839.", reference: "D&C 124",
                  latitude: 40.5500, longitude: -91.3850, area: .midwest),
            .init(id: "carthage", name: "Carthage Jail", prompt: "Where were Joseph and Hyrum Smith martyred?",
                  detail: "Carthage, Illinois, June 27, 1844.", reference: "D&C 135",
                  latitude: 40.4120, longitude: -91.1360, area: .midwest),
            .init(id: "winter-quarters", name: "Winter Quarters", prompt: "Where did the Saints spend the winter of 1846–47 before heading west?",
                  detail: "On the Missouri River, in today's Omaha, Nebraska.", reference: "D&C 136",
                  latitude: 41.3380, longitude: -95.9620, area: .midwest),
            // The West
            .init(id: "salt-lake", name: "Salt Lake Valley", prompt: "Where did Brigham Young say, \u{201C}This is the right place\u{201D}?",
                  detail: "At the mouth of Emigration Canyon, July 24, 1847.", reference: nil,
                  latitude: 40.7520, longitude: -111.8150, area: .unitedStates),
            .init(id: "martins-cove", name: "Martin's Cove", prompt: "Where did the Martin handcart company shelter from the snow in 1856?",
                  detail: "Near the Sweetwater River in central Wyoming.", reference: nil,
                  latitude: 42.4300, longitude: -107.1900, area: .unitedStates),
            .init(id: "st-george", name: "St. George Temple", prompt: "Where was the first temple completed in Utah?",
                  detail: "St. George, in southern Utah, dedicated in 1877.", reference: nil,
                  latitude: 37.1035, longitude: -113.5788, area: .unitedStates),
        ]
    )
}
