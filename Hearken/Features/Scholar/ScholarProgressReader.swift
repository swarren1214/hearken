import SwiftData
import SwiftUI

/// Queries a subject's Scholar Path evidence and hands its progress to `content`.
struct ScholarProgressReader<Content: View>: View {
    let path: ScholarPathFile
    @ViewBuilder let content: (ScholarProgress) -> Content

    @Query private var awards: [SubjectAward]
    @Query private var completions: [ItemCompletion]
    @Query private var attempts: [AssessmentAttempt]
    @Query private var grants: [RankGrant]
    @Query private var enrollments: [SubjectEnrollment]

    init(path: ScholarPathFile, @ViewBuilder content: @escaping (ScholarProgress) -> Content) {
        self.path = path
        self.content = content
        let id = path.subjectID
        _awards = Query(filter: #Predicate<SubjectAward> { $0.subjectID == id })
        _completions = Query(filter: #Predicate<ItemCompletion> { $0.subjectID == id })
        _attempts = Query(filter: #Predicate<AssessmentAttempt> { $0.subjectID == id })
        _grants = Query(filter: #Predicate<RankGrant> { $0.subjectID == id })
        _enrollments = Query(filter: #Predicate<SubjectEnrollment> { $0.subjectID == id })
    }

    var body: some View {
        content(ScholarProgress(path: path, awards: awards, completions: completions, attempts: attempts, grants: grants, enrollments: enrollments))
    }
}

/// Account XP: the existing XP history plus each Scholar Path award once. Subject awards are
/// never copied into XPEvent, so nothing counts twice.
enum AccountXP {
    static func total(events: [XPEvent], awards: [SubjectAward]) -> Int {
        var seen: Set<String> = []
        var subject = 0
        for award in awards where seen.insert(award.key).inserted {
            subject += award.amount
        }
        return events.reduce(0) { $0 + $1.amount } + subject
    }
}

/// A small progress ring with a label in the middle, for requirements and course progress.
struct RequirementRing: View {
    let progress: Double
    let label: String
    var color: Color = .accentColor
    var track: Color = Color(.tertiarySystemFill)
    var size: CGFloat = 50
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: size * 0.26, weight: .bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(.horizontal, lineWidth)
        }
        .frame(width: size, height: size)
        .animation(.smooth, value: progress)
        .accessibilityHidden(true)
    }
}
