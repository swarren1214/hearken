import SwiftUI

// MARK: - On the group page

/// This week's question at the top of the group: answer it, or see everyone's answers.
struct QuestionCard: View {
    let group: GroupStore.StudyGroup
    let question: GroupStore.Question
    let onAnswer: () -> Void
    let onOpen: () -> Void

    @State private var reporting: GroupReportTarget?
    @State private var blocking: GroupBlockTarget?

    var body: some View {
        let me = GroupStore.shared.myUserID
        let answered = question.myAnswer != nil || (me.map(question.answeredUserIDs.contains) ?? false)
        let answeredMembers = question.answeredUserIDs.compactMap { id in group.members.first { $0.userID == id } }
        VStack(alignment: .leading, spacing: 12) {
            AdaptiveStack {
                Label("THIS WEEK'S QUESTION", systemImage: "questionmark.bubble")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tint)
                Spacer(minLength: 8)
                Text("from \(question.authorID == me ? "you" : groupFirstName(question.authorName)) · \(question.postAt.formatted(.dateTime.weekday(.abbreviated)))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(question.text)
                .font(.scripture(size: 20, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            AdaptiveStack(spacing: 10) {
                if !answeredMembers.isEmpty {
                    HStack(spacing: -8) {
                        ForEach(answeredMembers.prefix(5)) { member in
                            MemberAvatar(name: member.name, initials: member.initials, size: 28)
                                .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        }
                    }
                }
                Text(status(answered: answered))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if answered {
                Button(action: onOpen) {
                    Text("See Answers").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            } else {
                Button(action: onAnswer) {
                    Text("Answer").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .contextMenu {
            if question.authorID != me, me != nil {
                Button("Report…", menuIcon: "exclamationmark.bubble") {
                    reporting = GroupReportTarget(kind: .question, targetID: question.id, groupID: group.id)
                }
            }
        }
        .groupSafety(reporting: $reporting, blocking: $blocking)
    }

    private func status(answered: Bool) -> String {
        let count = question.answerCount
        let total = group.members.filter { !$0.pending }.count
        if answered {
            return count <= 1 ? "You're the first to answer." : "You and \(count - 1) \(count - 1 == 1 ? "other" : "others") answered."
        }
        if count == 0 { return "Be the first to answer." }
        let base = "\(count) of \(total) answered."
        return question.hideAnswers ? base + " Their answers show after you post yours." : base
    }
}

/// For owners and leaders when there's no question this week.
struct AskQuestionPrompt: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AdaptiveStack(spacing: 14) {
                SymbolTile(systemName: "questionmark.bubble.fill", size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ask this week's question").font(.headline)
                    Text("Give everyone something to talk about").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(.tint)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// A question waiting for its post time (owners and leaders see it).
struct ScheduledQuestionCard: View {
    let group: GroupStore.StudyGroup
    let question: GroupStore.Question
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AdaptiveStack {
                Label("Posts \(question.postAt.formatted(.dateTime.weekday(.wide).hour().minute()))", systemImage: "clock")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
            }
            Text(question.text)
                .font(.scripture(size: 17))
                .foregroundStyle(.secondary)
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .alert("Delete the scheduled question?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    do { try await GroupStore.shared.deleteQuestion(question, in: group) }
                    catch { errorMessage = GroupStore.describe(error, action: "delete it") }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Asking

/// Owners and leaders: pick a suggested question for the week's chapters or write one, and
/// post it now or Monday morning.
struct AskQuestionSheet: View {
    let groupID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(ContentService.self) private var content
    @State private var suggestions: [QuestionSuggester.Suggestion] = []
    @State private var loadingSuggestions = true
    @State private var picked: UUID?
    @State private var custom = ""
    @State private var timing: Timing = .now
    @State private var hideAnswers = true
    @State private var posting = false
    @State private var errorMessage: String?

    enum Timing: Hashable { case now, monday }

    var body: some View {
        let group = GroupStore.shared.group(groupID)
        let week = group.map { GroupSchedule.week(GroupSchedule.days(for: $0, content: content)) }
        let chapterIDs = (week?.days.flatMap(\.chapterIDs) ?? []).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let range = PlanFormat.range(chapterIDs)

        NavigationStack {
            Form {
                Section {
                    if loadingSuggestions {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(QuestionSuggester.canGenerate ? "Writing suggestions…" : "Loading…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(suggestions) { suggestion in
                        Button {
                            picked = suggestion.id
                            custom = ""
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: picked == suggestion.id && custom.isEmpty ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(picked == suggestion.id && custom.isEmpty ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(suggestion.text).font(.scripture(size: 17)).foregroundStyle(.primary)
                                    if !suggestion.reference.isEmpty {
                                        Text(suggestion.reference).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(picked == suggestion.id && custom.isEmpty ? .isSelected : [])
                    }
                } header: {
                    Text(range.isEmpty ? "Suggested" : "Suggested for \(range)")
                } footer: {
                    if QuestionSuggester.canGenerate {
                        Text("Written on this iPhone by Apple Intelligence from this week's chapters.")
                    }
                }
                Section("Or write your own") {
                    TextField("What would you like to ask?", text: $custom, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("Post", selection: $timing) {
                        Text("Now").tag(Timing.now)
                        Text("Monday Morning").tag(Timing.monday)
                    }
                    Toggle("Hide answers until you answer", isOn: $hideAnswers)
                } footer: {
                    Text("Everyone in \(group?.name ?? "the group") is notified when it posts. \(hideAnswers ? "Each person sees the others' answers once they've posted their own." : "")")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("This Week's Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton("Post") { Task { await post(range: range, chapterIDs: chapterIDs) } }
                        .disabled(questionText.isEmpty || posting)
                }
            }
            .task {
                let chapters = chapterIDs.map { (title: content.title(forChapter: $0), heading: content.chapter($0)?.heading) }
                suggestions = await QuestionSuggester.suggestions(range: range, chapters: chapters)
                picked = suggestions.first?.id
                loadingSuggestions = false
            }
        }
        .tint(Accent.color)
    }

    private var chosen: QuestionSuggester.Suggestion? { suggestions.first { $0.id == picked } }

    private var questionText: String {
        let own = custom.trimmingCharacters(in: .whitespacesAndNewlines)
        return own.isEmpty ? (chosen?.text ?? "") : String(own.prefix(300))
    }

    /// Next Monday at 7:00 (today, if it's Monday before 7).
    private var mondayMorning: Date {
        Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 7, minute: 0, weekday: 2), matchingPolicy: .nextTime) ?? .now
    }

    private func post(range: String, chapterIDs: [String]) async {
        guard let group = GroupStore.shared.group(groupID), !questionText.isEmpty else { return }
        posting = true
        defer { posting = false }
        let own = !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        do {
            try await GroupStore.shared.ask(
                questionText,
                reference: String((own ? range : (chosen?.reference ?? range)).prefix(80)),
                chapterID: chapterIDs.first ?? "",
                postAt: timing == .monday ? mondayMorning : nil,
                hideAnswers: hideAnswers,
                in: group
            )
            dismiss()
        } catch {
            errorMessage = GroupStore.describe(error, action: "post the question")
        }
    }
}

// MARK: - Answering

/// Writing (or editing) my answer. Others' answers wait behind it when the question hides them.
struct AnswerSheet: View {
    let groupID: String
    let question: GroupStore.Question
    var onPosted: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var posting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private static let limit = 1000

    var body: some View {
        let group = GroupStore.shared.group(groupID)
        let me = GroupStore.shared.myUserID
        let waiting = question.answeredUserIDs.filter { $0 != me }.compactMap { id in group?.members.first { $0.userID == id } }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            MemberAvatar(name: question.authorName, initials: groupInitials(question.authorName), size: 24)
                            (Text(question.authorID == me ? "You" : groupFirstName(question.authorName)).fontWeight(.semibold)
                             + Text(" asked · \(group?.name ?? "")").foregroundStyle(.secondary))
                                .font(.footnote)
                        }
                        Text(question.text)
                            .font(.scripture(size: 22, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        if !question.chapterID.isEmpty {
                            Button {
                                AppNavigator.shared.open(chapterID: question.chapterID)
                                dismiss()
                            } label: {
                                Label("Read \(question.reference.isEmpty ? "the chapter" : question.reference)", systemImage: "book")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal, 4)

                    VStack(alignment: .trailing, spacing: 6) {
                        TextField("Your answer", text: $text, axis: .vertical)
                            .lineLimit(5...12)
                            .focused($focused)
                            .onChange(of: text) { _, value in
                                if value.count > Self.limit { text = String(value.prefix(Self.limit)) }
                            }
                        Text("\(text.count) / \(Self.limit.formatted())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(16)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))

                    if question.hideAnswers, question.myAnswer == nil, !waiting.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label {
                                Text("\(waiting.count) \(waiting.count == 1 ? "answer is" : "answers are") waiting.").fontWeight(.semibold)
                                + Text(" They show after you post yours.").foregroundStyle(.secondary)
                            } icon: {
                                Image(systemName: "lock.fill").foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            ForEach(waiting) { member in
                                HStack(alignment: .top, spacing: 10) {
                                    MemberAvatar(name: member.name, initials: member.initials, size: 30)
                                    VStack(alignment: .leading, spacing: 7) {
                                        Capsule().fill(.quaternary).frame(height: 10)
                                        Capsule().fill(.quaternary).frame(height: 10).padding(.trailing, 60)
                                    }
                                    .padding(.top, 6)
                                }
                                .padding(14)
                                .background(Color(.secondarySystemGroupedBackground).opacity(0.7), in: .rect(cornerRadius: 20))
                                .accessibilityHidden(true)
                            }
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(question.myAnswer == nil ? "Your Answer" : "Edit Answer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetDoneButton("Post") { Task { await post() } }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || posting)
                }
            }
        }
        .tint(Accent.color)
        .onAppear {
            text = question.myAnswer?.body ?? ""
            focused = true
        }
    }

    private func post() async {
        guard let group = GroupStore.shared.group(groupID) else { return }
        posting = true
        defer { posting = false }
        do {
            try await GroupStore.shared.answer(text.trimmingCharacters(in: .whitespacesAndNewlines), to: question, in: group)
            dismiss()
            onPosted()
        } catch {
            errorMessage = GroupStore.describe(error, action: "post your answer")
        }
    }
}

// MARK: - Answers

/// This week's question with everyone's answers (once mine is in, or it has closed).
struct QuestionDetailView: View {
    let groupID: String

    @State private var answering: GroupStore.Question?
    @State private var reporting: GroupReportTarget?
    @State private var blocking: GroupBlockTarget?

    var body: some View {
        let store = GroupStore.shared
        let me = store.myUserID
        if let group = store.group(groupID), let question = group.question {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(question, group: group, me: me)
                    if question.answersVisible {
                        ForEach(sortedAnswers(question, me: me)) { answer in
                            AnswerCard(answer: answer, group: group, me: me)
                        }
                        if question.answers.isEmpty {
                            Text("No answers yet.").font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 4)
                        }
                    } else {
                        locked(question)
                    }
                    NavigationLink {
                        EarlierQuestionsView(groupID: groupID)
                    } label: {
                        HStack {
                            Text("Earlier Questions")
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { await store.reload(groupID) }
            .navigationTitle("This Week's Question")
            .navigationSubtitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if question.myAnswer != nil, !question.isClosed {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Edit Answer", systemImage: "pencil") { answering = question }
                            .tint(Color.primary)
                    }
                }
            }
            .sheet(item: $answering) { question in
                AnswerSheet(groupID: groupID, question: question)
            }
            .groupSafety(reporting: $reporting, blocking: $blocking)
        } else {
            ContentUnavailableView("No Question This Week", systemImage: "questionmark.bubble",
                                   description: Text("When the group's owner or a leader asks one, it shows here."))
        }
    }

    private func header(_ question: GroupStore.Question, group: GroupStore.StudyGroup, me: String?) -> some View {
        let total = max(group.members.filter { !$0.pending }.count, 1)
        let missing = group.members.filter { !$0.pending && !question.answeredUserIDs.contains($0.userID) && $0.userID != me }
        return VStack(alignment: .leading, spacing: 10) {
            Text(question.text)
                .font(.scripture(size: 19, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !question.reference.isEmpty {
                Text(question.reference).font(.footnote).foregroundStyle(.secondary)
            }
            AdaptiveStack(spacing: 8) {
                ProgressView(value: Double(question.answerCount), total: Double(total))
                    .tint(Accent.color)
                Text("\(question.answerCount) of \(total) answered")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .fixedSize()
            }
            Text(footnote(question, missing: missing))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .contextMenu {
            if question.authorID != me, me != nil {
                Button("Report…", menuIcon: "exclamationmark.bubble") {
                    reporting = GroupReportTarget(kind: .question, targetID: question.id, groupID: group.id)
                }
            }
        }
    }

    private func footnote(_ question: GroupStore.Question, missing: [GroupStore.Member]) -> String {
        let closes = question.isClosed ? "Answers closed." : "Answers close \(question.closesAt.formatted(.dateTime.weekday(.wide)))."
        guard !missing.isEmpty else { return closes }
        let names = ListFormatter.localizedString(byJoining: missing.prefix(3).map(\.firstName))
        let more = missing.count > 3 ? " and \(missing.count - 3) more" : ""
        return "\(names)\(more) \(missing.count == 1 ? "hasn't" : "haven't") answered yet. \(closes)"
    }

    private func locked(_ question: GroupStore.Question) -> some View {
        VStack(spacing: 12) {
            Label("Answers show after you post yours", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                answering = question
            } label: {
                Text("Answer").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func sortedAnswers(_ question: GroupStore.Question, me: String?) -> [GroupStore.Answer] {
        let mine = question.answers.filter { $0.userID == me }
        return mine + question.answers.filter { $0.userID != me }
    }
}

/// One answer to the weekly question, with hearts and replies.
struct AnswerCard: View {
    let answer: GroupStore.Answer
    let group: GroupStore.StudyGroup
    let me: String?
    var showsReplies = true
    /// Earlier questions show answers without reacting or replying.
    var interactive = true

    @State private var reporting: GroupReportTarget?
    @State private var blocking: GroupBlockTarget?

    var body: some View {
        let mine = answer.userID == me
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MemberAvatar(name: answer.authorName, initials: groupInitials(answer.authorName), size: 28)
                (Text(mine ? "You" : groupFirstName(answer.authorName)).fontWeight(.semibold)
                 + Text(" · \(answer.createdAt.formatted(.relative(presentation: .named)))").foregroundStyle(.secondary))
                    .font(.subheadline)
            }
            Text(answer.body)
                .fixedSize(horizontal: false, vertical: true)
            if interactive {
                HStack(spacing: 8) {
                    ReactionChip(kind: .heart, reactions: answer.reactions, me: me) {
                        let on = !answer.reactions.contains { $0.userID == me && $0.kind == .heart }
                        Task { await GroupStore.shared.setReaction(.heart, on: on, target: .answer, id: answer.id, in: group.id) }
                    }
                    if showsReplies {
                        NavigationLink(value: ThreadRoute(groupID: group.id, target: .answer, targetID: answer.id)) {
                            HStack(spacing: 5) {
                                Image(systemName: "bubble.left")
                                Text(answer.commentCount > 0 ? "\(answer.commentCount)" : "Reply").monospacedDigit()
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(answer.commentCount > 0 ? AnyShapeStyle(Accent.color) : AnyShapeStyle(.secondary))
                            .padding(.horizontal, 10)
                            .frame(minHeight: 30)
                            .background(answer.commentCount > 0 ? AnyShapeStyle(Accent.color.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.6)), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(answer.commentCount == 0 ? "Reply" : "\(answer.commentCount) replies")
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .overlay {
            if mine { RoundedRectangle(cornerRadius: 20).strokeBorder(Accent.color.opacity(0.35), lineWidth: 2) }
        }
        .contextMenu {
            if !mine, me != nil {
                Button("Report…", menuIcon: "exclamationmark.bubble") {
                    reporting = GroupReportTarget(kind: .answer, targetID: answer.id, groupID: group.id)
                }
                Button("Block \(groupFirstName(answer.authorName))", menuIcon: "hand.raised", role: .destructive) {
                    blocking = GroupBlockTarget(userID: answer.userID, name: answer.authorName)
                }
            }
        }
        .groupSafety(reporting: $reporting, blocking: $blocking)
    }
}

// MARK: - Earlier questions

struct EarlierQuestionsView: View {
    let groupID: String

    @State private var questions: [GroupStore.Question] = []
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var expanded: Set<String> = []

    var body: some View {
        let store = GroupStore.shared
        let group = store.group(groupID)
        let earlier = questions.filter { $0.isClosed || $0.id != group?.question?.id }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !loaded {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if earlier.isEmpty {
                    ContentUnavailableView("No Earlier Questions", systemImage: "clock.arrow.circlepath",
                                           description: Text(errorMessage ?? "Questions the group has finished show here."))
                }
                if let group {
                    ForEach(earlier) { question in
                        card(question, group: group, me: store.myUserID)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Earlier Questions")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func card(_ question: GroupStore.Question, group: GroupStore.StudyGroup, me: String?) -> some View {
        let open = expanded.contains(question.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy) {
                    if open { expanded.remove(question.id) } else { expanded.insert(question.id) }
                }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.postAt.formatted(date: .abbreviated, time: .omitted) + (question.reference.isEmpty ? "" : " · \(question.reference)"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(question.text)
                        .font(.scripture(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("\(question.answerCount) \(question.answerCount == 1 ? "answer" : "answers")")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the answers" : "Shows the answers")
            if open {
                if question.answersVisible {
                    ForEach(question.answers.filter { !GroupStore.shared.isBlocked($0.userID) }) { answer in
                        AnswerCard(answer: answer, group: group, me: me, interactive: false)
                    }
                } else {
                    Label("Answers show after you post yours", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func load() async {
        guard let group = GroupStore.shared.group(groupID) else { return }
        do {
            questions = try await GroupStore.shared.questions(in: group)
            errorMessage = nil
        } catch {
            errorMessage = GroupStore.describe(error, action: "load the questions")
        }
        loaded = true
    }
}
