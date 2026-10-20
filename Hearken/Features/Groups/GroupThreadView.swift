import SwiftUI

/// Replies on a shared post or an answer to the weekly question. Replies go two levels deep: a
/// reply to a reply joins the same conversation, mentioning who it answers. `@` in the composer
/// offers the group's members to mention.
struct GroupThreadView: View {
    let route: ThreadRoute

    @State private var loadedComments: [GroupStore.Comment] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var text = ""
    @State private var replyingTo: GroupStore.Comment?
    @State private var mentions: [String: String] = [:]   // "@David" → user id
    @State private var mentionsEveryone = false
    @State private var sending = false
    @State private var deleting: GroupStore.Comment?
    @State private var reporting: GroupReportTarget?
    @State private var blocking: GroupBlockTarget?
    @FocusState private var focused: Bool

    var body: some View {
        let store = GroupStore.shared
        if let group = store.group(route.groupID) {
            page(group, me: store.myUserID)
        } else {
            ContentUnavailableView("Group Unavailable", systemImage: "person.3",
                                   description: Text("You may have left this group, or it was deleted."))
        }
    }

    /// The replies, without those of people I blocked (blocked since they loaded).
    private var comments: [GroupStore.Comment] {
        let blocked = GroupStore.shared.blockedUserIDs
        return blocked.isEmpty ? loadedComments : loadedComments.filter { !blocked.contains($0.authorID) }
    }

    private func page(_ group: GroupStore.StudyGroup, me: String?) -> some View {
        let item = route.target == .item ? group.items.first { $0.id == route.targetID } : nil
        let answer = route.target == .answer ? group.question?.answers.first { $0.id == route.targetID } : nil
        let topLevel = comments.filter { $0.parentID == nil }

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let item {
                    GroupItemCard(item: item, group: group, me: me, showsReplies: false)
                } else if let answer {
                    AnswerCard(answer: answer, group: group, me: me, showsReplies: false)
                }
                Text(comments.isEmpty ? "REPLIES" : "\(comments.count) \(comments.count == 1 ? "REPLY" : "REPLIES")")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
                } else if comments.isEmpty {
                    Text("No replies yet. Start the conversation below.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(topLevel) { comment in
                            thread(comment, group: group, me: me)
                            if comment.id != topLevel.last?.id { Divider() }
                        }
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await load() }
        .task { await load() }
        .safeAreaInset(edge: .bottom) { composer(group, me: me) }
        .navigationTitle(route.target == .answer ? "Answer" : (item?.kind == .highlight ? "Highlight" : "Reflection"))
        .navigationSubtitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this reply?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) {
                if let comment = deleting { Task { await delete(comment) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleting?.parentID == nil ? "Replies to it are deleted too." : "")
        }
        .groupSafety(reporting: $reporting, blocking: $blocking)
    }

    // MARK: Replies

    private func thread(_ comment: GroupStore.Comment, group: GroupStore.StudyGroup, me: String?) -> some View {
        let replies = comments.filter { $0.parentID == comment.id }
        return HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 6) {
                MemberAvatar(name: comment.authorName, initials: groupInitials(comment.authorName), size: 30)
                if !replies.isEmpty {
                    Capsule().fill(.quaternary).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                commentBody(comment, group: group, me: me)
                ForEach(replies) { reply in
                    HStack(alignment: .top, spacing: 10) {
                        MemberAvatar(name: reply.authorName, initials: groupInitials(reply.authorName), size: 24)
                        commentBody(reply, group: group, me: me)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private func commentBody(_ comment: GroupStore.Comment, group: GroupStore.StudyGroup, me: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            (Text(comment.authorID == me ? "You" : groupFirstName(comment.authorName)).font(.subheadline.weight(.semibold))
             + Text(" · \(comment.createdAt.formatted(.relative(presentation: .named)))").font(.footnote).foregroundStyle(.secondary))
            MentionText(text: comment.body)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                ReactionChip(kind: .heart, reactions: comment.reactions, me: me, compact: true) {
                    Task { await toggleHeart(on: comment, in: group, me: me) }
                }
                Button("Reply") { startReply(to: comment) }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .frame(minHeight: 28)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .contextMenu {
            Button("Reply", menuIcon: "arrowshape.turn.up.left") { startReply(to: comment) }
            if comment.authorID != me, me != nil {
                Button("Report…", menuIcon: "exclamationmark.bubble") {
                    reporting = GroupReportTarget(kind: .comment, targetID: comment.id, groupID: group.id)
                }
                Button("Block \(groupFirstName(comment.authorName))", menuIcon: "hand.raised", role: .destructive) {
                    blocking = GroupBlockTarget(userID: comment.authorID, name: comment.authorName)
                }
            }
            if comment.authorID == me || group.canModerate {
                Button(role: .destructive) { deleting = comment } label: {
                    Label { Text("Delete") } icon: { Image.redTrash }
                }
            }
        }
    }

    // MARK: Composer

    private func composer(_ group: GroupStore.StudyGroup, me: String?) -> some View {
        let suggestions = mentionSuggestions(group, me: me)
        return VStack(alignment: .leading, spacing: 8) {
            if !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions, id: \.id) { suggestion in
                        Button { pick(suggestion) } label: {
                            HStack(spacing: 10) {
                                if suggestion.isEveryone {
                                    Image(systemName: "person.3.fill")
                                        .font(.footnote)
                                        .foregroundStyle(.white)
                                        .frame(width: 28, height: 28)
                                        .background(Color.secondary, in: Circle())
                                } else {
                                    MemberAvatar(name: suggestion.name, initials: suggestion.initials, size: 28)
                                }
                                Text(suggestion.name)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .frame(maxWidth: 280)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Mention someone")
            }
            VStack(alignment: .leading, spacing: 2) {
                if let replyingTo {
                    HStack {
                        (Text("Replying to ") + Text(replyingTo.authorID == me ? "yourself" : groupFirstName(replyingTo.authorName)).fontWeight(.semibold))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel Reply", systemImage: "xmark") { self.replyingTo = nil }
                            .labelStyle(.iconOnly)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .padding(.top, 6)
                }
                HStack(spacing: 8) {
                    TextField(replyingTo == nil ? "Add a reply" : "Reply", text: $text, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    Button("Send", systemImage: "arrow.up") {
                        Task { await send(group) }
                    }
                    .labelStyle(.iconOnly)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.tint, in: Circle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sending)
                    .padding(.trailing, 6)
                }
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private struct MentionSuggestion {
        let id: String
        let name: String
        let initials: String
        let handle: String
        let isEveryone: Bool
    }

    /// The `@word` being typed at the end of the reply, if any.
    private var mentionQuery: String? {
        guard let last = text.split(separator: " ", omittingEmptySubsequences: false).last, last.hasPrefix("@") else { return nil }
        return String(last.dropFirst())
    }

    private func mentionSuggestions(_ group: GroupStore.StudyGroup, me: String?) -> [MentionSuggestion] {
        guard let query = mentionQuery?.lowercased() else { return [] }
        var result = group.members
            .filter { $0.userID != me && !$0.pending }
            .filter { query.isEmpty || $0.name.lowercased().hasPrefix(query) || $0.firstName.lowercased().hasPrefix(query) }
            .prefix(5)
            .map { MentionSuggestion(id: $0.userID, name: $0.name, initials: $0.initials, handle: "@" + $0.firstName, isEveryone: false) }
        if group.canModerate || group.members.count <= 12, query.isEmpty || "everyone".hasPrefix(query) {
            result.append(MentionSuggestion(id: "everyone", name: "Everyone in the group", initials: "", handle: "@everyone", isEveryone: true))
        }
        return result
    }

    private func pick(_ suggestion: MentionSuggestion) {
        var words = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if !words.isEmpty { words.removeLast() }
        words.append(suggestion.handle)
        text = words.joined(separator: " ") + " "
        if suggestion.isEveryone { mentionsEveryone = true } else { mentions[suggestion.handle] = suggestion.id }
    }

    private func startReply(to comment: GroupStore.Comment) {
        replyingTo = comment
        // Answering a reply in a conversation: say who it's for.
        if comment.parentID != nil, comment.authorID != GroupStore.shared.myUserID {
            let handle = "@" + groupFirstName(comment.authorName)
            if !text.contains(handle) { text = handle + " " + text }
            mentions[handle] = comment.authorID
        }
        focused = true
    }

    // MARK: Actions

    private func load() async {
        do {
            loadedComments = try await GroupStore.shared.comments(on: route.target, id: route.targetID, in: route.groupID)
            errorMessage = nil
        } catch {
            errorMessage = GroupStore.describe(error, action: "load the replies")
        }
        loaded = true
    }

    private func send(_ group: GroupStore.StudyGroup) async {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true
        defer { sending = false }
        // Only the mentions still in the text count.
        let mentioned = mentions.filter { body.contains($0.key) }.map(\.value)
        do {
            let comment = try await GroupStore.shared.reply(
                body, on: route.target, id: route.targetID, parentID: replyingTo.map { $0.parentID ?? $0.id },
                mentions: Array(Set(mentioned)), mentionsEveryone: mentionsEveryone && body.contains("@everyone"), in: group.id
            )
            withAnimation(.snappy) { loadedComments.append(comment) }
            text = ""
            replyingTo = nil
            mentions = [:]
            mentionsEveryone = false
            focused = false
            errorMessage = nil
        } catch {
            errorMessage = GroupStore.describe(error, action: "send that")
        }
    }

    private func delete(_ comment: GroupStore.Comment) async {
        do {
            try await GroupStore.shared.deleteComment(comment, in: route.groupID)
            withAnimation(.snappy) { loadedComments.removeAll { $0.id == comment.id || $0.parentID == comment.id } }
        } catch {
            errorMessage = GroupStore.describe(error, action: "delete that")
        }
        deleting = nil
    }

    private func toggleHeart(on comment: GroupStore.Comment, in group: GroupStore.StudyGroup, me: String?) async {
        guard let me, let index = loadedComments.firstIndex(where: { $0.id == comment.id }) else { return }
        let on = !loadedComments[index].reactions.contains { $0.userID == me && $0.kind == .heart }
        loadedComments[index].reactions.removeAll { $0.userID == me && $0.kind == .heart }
        if on { loadedComments[index].reactions.append(GroupStore.Reaction(kind: .heart, userID: me)) }
        await GroupStore.shared.setReaction(.heart, on: on, target: .comment, id: comment.id, in: group.id)
    }
}

/// Reply text with its @mentions in the app's color.
struct MentionText: View {
    let text: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        var rest = Substring(text)
        while let match = rest.firstMatch(of: #/@[\p{L}\p{N}_]+/#) {
            result += AttributedString(String(rest[rest.startIndex..<match.range.lowerBound]))
            var mention = AttributedString(String(match.output))
            mention.foregroundColor = Accent.color
            mention.font = .body.weight(.semibold)
            result += mention
            rest = rest[match.range.upperBound...]
        }
        result += AttributedString(String(rest))
        return result
    }
}
