import SwiftData
import SwiftUI

/// A subject: its Scholar Path, or Coming Soon for subjects whose path isn't built yet.
struct SubjectDetailView: View {
    let subject: Subject

    var body: some View {
        if let path = PathCatalog.shared.path(for: subject.id) {
            SubjectPathView(subject: subject, path: path)
        } else {
            // Links elsewhere (notifications, search history) can still land here.
            ContentUnavailableView {
                Label(subject.name, systemImage: subject.symbol)
            } description: {
                Text("Coming Soon. \(subject.summary)")
            }
            .navigationTitle(subject.name)
        }
    }
}

#Preview {
    NavigationStack { PlayView() }
        .previewEnvironment()
}
