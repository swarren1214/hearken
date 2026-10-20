import SwiftUI

// Reporting and blocking in study groups. "Report…" opens `GroupReportSheet` (POST /v1/reports);
// "Block <name>" asks with a native alert, then hides that person's posts, replies and answers
// (GroupStore filters them here; the server leaves them out too). Settings › Blocked People
// (`BlockedPeopleView`) unblocks. Neither is offered on your own content.

/// Something in a group to report.
struct GroupReportTarget: Identifiable, Hashable {
    let kind: GroupStore.ReportKind
    let targetID: String
    let groupID: String
    var id: String { "\(kind.rawValue)|\(targetID)" }

    var noun: String {
        switch kind {
        case .post: "post"
        case .comment: "reply"
        case .answer: "answer"
        case .question: "question"
        case .member: "person"
        }
    }
}

/// Someone to block.
struct GroupBlockTarget: Identifiable, Hashable {
    let userID: String
    let name: String
    var id: String { userID }
    var firstName: String { groupFirstName(name) }
}

extension View {
    /// The Report sheet and the Block confirmation for a view that offers "Report…" and
    /// "Block <name>". Set `reporting` or `blocking` to show them.
    func groupSafety(reporting: Binding<GroupReportTarget?>, blocking: Binding<GroupBlockTarget?>) -> some View {
        modifier(GroupSafetyModifier(reporting: reporting, blocking: blocking))
    }
}

private struct GroupSafetyModifier: ViewModifier {
    @Binding var reporting: GroupReportTarget?
    @Binding var blocking: GroupBlockTarget?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: $reporting) { target in
                GroupReportSheet(target: target)
            }
            .alert(
                "Block \(blocking?.name ?? "")?",
                isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }),
                presenting: blocking
            ) { person in
                Button("Block", role: .destructive) {
                    Task { await block(person) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { person in
                Text("You won't see \(person.firstName)'s posts, replies or answers in your study groups. They aren't told. You can unblock them in Settings › Blocked People.")
            }
            .alert("Couldn't Block", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func block(_ person: GroupBlockTarget) async {
        do {
            try await GroupStore.shared.block(userID: person.userID, name: person.name)
        } catch {
            errorMessage = GroupStore.describe(error, action: "block them")
        }
    }
}

// MARK: - Report

/// Why something is being reported, with optional details, sent to Hearth for review.
struct GroupReportSheet: View {
    let target: GroupReportTarget

    @Environment(\.dismiss) private var dismiss
    @State private var reason: GroupStore.ReportReason?
    @State private var details = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private static let limit = 1000

    var body: some View {
        NavigationStack {
            Form {
                if sent {
                    Section {
                        Label {
                            Text("Thanks. We review every report within 24 hours.")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                } else {
                    Section {
                        ForEach(GroupStore.ReportReason.allCases) { option in
                            Button {
                                reason = option
                            } label: {
                                HStack {
                                    Text(option.title).foregroundStyle(.primary)
                                    Spacer(minLength: 8)
                                    if reason == option {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(reason == option ? .isSelected : [])
                        }
                    } header: {
                        Text("What's wrong with this \(target.noun)?")
                    } footer: {
                        Text("Reports go to the Hearth team, not to the person or the group.")
                    }
                    Section("Details (Optional)") {
                        TextField("Anything else we should know", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                            .onChange(of: details) { _, value in
                                if value.count > Self.limit { details = String(value.prefix(Self.limit)) }
                            }
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle(sent ? "Report Sent" : "Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sent {
                    ToolbarItem(placement: .confirmationAction) { SheetDoneButton { dismiss() } }
                } else {
                    ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        SheetDoneButton("Send") { Task { await send() } }
                            .disabled(reason == nil || sending)
                    }
                }
            }
        }
        .tint(Accent.color)
    }

    private func send() async {
        guard let reason else { return }
        sending = true
        defer { sending = false }
        do {
            try await GroupStore.shared.report(target.kind, targetID: target.targetID, groupID: target.groupID,
                                               reason: reason, details: details)
            errorMessage = nil
            withAnimation(.snappy) { sent = true }
        } catch {
            errorMessage = GroupStore.describe(error, action: "send the report")
        }
    }
}

// MARK: - Blocked people

/// Settings › Blocked People: everyone I've blocked in study groups, with Unblock.
struct BlockedPeopleView: View {
    @State private var working: String?
    @State private var errorMessage: String?

    var body: some View {
        let store = GroupStore.shared
        let people = store.blockedUserIDs
            .map { GroupBlockTarget(userID: $0, name: store.blockedName($0)) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        List {
            if !people.isEmpty {
                Section {
                    ForEach(people) { person in
                        HStack(spacing: 12) {
                            MemberAvatar(name: person.name, initials: groupInitials(person.name), size: 36)
                            Text(person.name)
                            Spacer(minLength: 8)
                            if working == person.userID {
                                ProgressView()
                            } else {
                                Button("Unblock") { Task { await unblock(person) } }
                                    .buttonStyle(.borderless)
                                    .disabled(working != nil)
                            }
                        }
                    }
                } footer: {
                    Text("You don't see posts, replies or answers from people you block in your study groups. They aren't told.")
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .overlay {
            if people.isEmpty {
                ContentUnavailableView("No Blocked People", systemImage: "hand.raised",
                                       description: Text("People you block in study groups show here, so you can unblock them."))
            }
        }
        .navigationTitle("Blocked People")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.loadBlocks() }
        .refreshable { await store.loadBlocks() }
    }

    private func unblock(_ person: GroupBlockTarget) async {
        working = person.userID
        defer { working = nil }
        do {
            try await GroupStore.shared.unblock(userID: person.userID)
            errorMessage = nil
        } catch {
            errorMessage = GroupStore.describe(error, action: "unblock them")
        }
    }
}
