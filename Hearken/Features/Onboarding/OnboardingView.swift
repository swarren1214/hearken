import AuthenticationServices
import SwiftData
import SwiftUI

/// First run, from the Hearth Onboarding canvas (Hearken row): Welcome with an optional Sign in
/// with Apple, the household, a reading plan, a daily goal and reminder, text size, review
/// questions, All Set, then Better with Hearth, which starts the tour (Show Me Around) or opens
/// the reader (Start Reading). Built from the shared pieces in HearthOnboarding.swift; every
/// setting it asks for is the same one Profile changes later.
///
/// Shown once, for a new install (`SettingsKey.onboardingDone`); people who already finished
/// the old sign-in screen never see it.
struct OnboardingView: View {
    var onFinish: () -> Void

    private enum Screen: Int, CaseIterable {
        case welcome, household, plan, goal, text, review, ready, apps
    }

    @Environment(\.modelContext) private var modelContext
    @State private var screen: Screen = .welcome
    @State private var isForward = true

    // The plan: a catalog plan's id, or nil for "At my own pace".
    @State private var planID: String? = "bofm-180"
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 15
    @AppStorage(SettingsKey.studyReminder) private var studyReminder = false
    @AppStorage(SettingsKey.scriptureTextSize) private var textSize: Double = 20
    @AppStorage(SettingsKey.showVerseNumbers) private var showVerseNumbers = true
    @AppStorage(SettingsKey.readerLayout) private var readerLayout: ReaderLayout = .scroll
    @AppStorage(SettingsKey.reviewNotifications) private var reviewNotifications = false
    @AppStorage(SettingsKey.reviewNotificationMinutes) private var reviewMinutes = ReviewNotifications.defaultMinutes

    private static let steps = 5
    /// The plans offered here; the rest are in Library › Reading Plans.
    private static let planIDs = ["bofm-180", "bofm-90", "nt-180", "ot-365"]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            page
                .id(screen)
                .transition(.asymmetric(
                    insertion: .move(edge: isForward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: isForward ? .leading : .trailing).combined(with: .opacity)
                ))
        }
        .hearthOnboardingStyle(.hearken)
        .symmetricSafeArea()
    }

    @ViewBuilder
    private var page: some View {
        switch screen {
        case .welcome: OnboardingWelcome(next: next)
        case .household:
            HearthHouseholdOnboarding(accent: HearthOnboarding.ink(.hearken), onContinue: next)
        case .plan: planPage
        case .goal: goalPage
        case .text: textPage
        case .review: reviewPage
        case .ready: readyPage
        case .apps:
            HearthOnboardingAppsPage(app: .hearken, finish: finish, jumpInTitle: "Start Reading")
        }
    }

    private func next() {
        guard let following = Screen(rawValue: screen.rawValue + 1) else { return }
        isForward = true
        withAnimation(.smooth) { screen = following }
    }

    /// Show Me Around starts the tour; Start Reading opens where they'd start (TodayView acts on
    /// `finishRequested`). Hearken's tour keeps its own "seen" key.
    private func finish(_ tour: Bool) {
        HearthOnboarding.finish(.hearken, tour: tour)
        UserDefaults.standard.set(true, forKey: SettingsKey.tourDone)
        if !tour { HearthTour.shared.finishRequested = true }
        onFinish()
    }

    // MARK: Reading plan

    private var planPage: some View {
        HearthOnboardingPage(
            app: .hearken, step: (2, Self.steps), symbol: "book.closed",
            title: "Choose a reading plan",
            subtitle: "A little every day. Change plans anytime in Library › Reading Plans."
        ) {
            ForEach(Self.planIDs, id: \.self) { id in
                if let plan = ReadingPlanCatalog.plans.first(where: { $0.id == id }) {
                    HearthOnboardingOption(
                        plan.title,
                        detail: "\(PlanFormat.perDay(chapters: plan.chapterIDs.count, days: plan.days)) chapters a day · \(plan.subtitle)",
                        isSelected: planID == id
                    ) { planID = id }
                }
            }
            HearthOnboardingOption("At my own pace", detail: "No plan. Just pick up where you left off.", isSelected: planID == nil) {
                planID = nil
            }
        } controls: {
            HearthOnboardingButtons(app: .hearken, primary: "Continue", action: {
                startPlan()
                next()
            }, secondary: "Skip", secondaryAction: {
                planID = nil
                next()
            })
        }
    }

    private var chosenPlan: ReadingPlan? {
        planID.flatMap { id in ReadingPlanCatalog.plans.first { $0.id == id } }
    }

    /// Starts the chosen plan today, unless one is already going (another device, through iCloud).
    private func startPlan() {
        guard let plan = chosenPlan, !plan.chapterIDs.isEmpty else { return }
        let enrollments = (try? modelContext.fetch(FetchDescriptor<PlanEnrollment>())) ?? []
        guard !enrollments.contains(where: { $0.endedAt == nil }) else { return }
        modelContext.insert(PlanEnrollment(
            planID: plan.id,
            startDate: Calendar.current.startOfDay(for: .now),
            days: plan.days,
            readingDays: ReadingDays.everyDay.rawValue,
            reminderEnabled: false,
            reminderMinutes: 7 * 60
        ))
    }

    // MARK: Daily goal

    private static let goals = [5, 10, 15, 30]

    private var goalPage: some View {
        HearthOnboardingPage(
            app: .hearken, step: (3, Self.steps), symbol: "flame",
            title: "Set a daily goal",
            subtitle: "Reach it to keep your streak going."
        ) {
            HearthOnboardingChips(options: Self.goals.map { "\($0) min" }, selection: Binding(
                get: { ["\(dailyGoal) min"] },
                set: { picked in
                    if let first = picked.first, let minutes = Int(first.split(separator: " ").first ?? "") { dailyGoal = minutes }
                }
            ), single: true)
            HearthOnboardingCard {
                Toggle(isOn: reminderBinding) {
                    HearthOnboardingRowLabel("Study Reminder", detail: "8:00 PM, to keep your streak going")
                }
            }
        } controls: {
            HearthOnboardingButtons(app: .hearken, primary: "Continue", action: next, secondary: "Skip", secondaryAction: next)
        }
    }

    /// The same as Profile › Study Reminder: asks for notifications, and turns itself back off
    /// if they're denied.
    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { studyReminder },
            set: { on in
                studyReminder = on
                if on {
                    Task {
                        let granted = await ReminderScheduler.enable()
                        if !granted { studyReminder = false }
                    }
                } else {
                    ReminderScheduler.disable()
                }
            }
        )
    }

    // MARK: Text

    private var textPage: some View {
        HearthOnboardingPage(
            app: .hearken, step: (4, Self.steps), symbol: "textformat.size",
            title: "Make it easy to read",
            subtitle: "Pick a size you can read comfortably. It’s in the reader’s … menu too."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                VerseRow(
                    verse: Verse(id: "preview", number: 27, text: "But behold, if ye will awake and arouse your faculties, even to an experiment upon my words, and exercise a particle of faith."),
                    highlight: nil,
                    showNumber: showVerseNumbers,
                    fontSize: CGFloat(textSize),
                    isSelected: false
                )
                .animation(.snappy, value: textSize)
                .accessibilityLabel("Preview of scripture text")
                HStack(spacing: 12) {
                    Image(systemName: "textformat.size.smaller").accessibilityHidden(true)
                    Slider(value: $textSize, in: 15...28, step: 1) {
                        Text("Scripture Text Size")
                    }
                    .accessibilityValue("\(Int(textSize)) points")
                    Image(systemName: "textformat.size.larger").accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))

            HearthOnboardingChips(options: ReaderLayout.allCases.map(\.title), selection: Binding(
                get: { [readerLayout.title] },
                set: { picked in
                    if let layout = ReaderLayout.allCases.first(where: { picked.contains($0.title) }) { readerLayout = layout }
                }
            ), single: true)
        } controls: {
            HearthOnboardingButtons(app: .hearken, primary: "Continue", action: next, secondary: "Skip", secondaryAction: next)
        }
    }

    // MARK: Review

    private var reviewPage: some View {
        HearthOnboardingPage(
            app: .hearken, step: (5, Self.steps), symbol: "arrow.trianglehead.2.clockwise.rotate.90",
            title: "Remember what you read",
            subtitle: "One question a day from what you studied, answered right from the notification."
        ) {
            HearthOnboardingCard {
                Toggle(isOn: reviewBinding) {
                    HearthOnboardingRowLabel("Review Questions", detail: "On iPhone and Apple Watch")
                }
                if reviewNotifications {
                    DatePicker("Time", selection: reviewTimeBinding, displayedComponents: .hourAndMinute)
                }
            }
        } controls: {
            if reviewNotifications {
                HearthOnboardingButtons(app: .hearken, primary: "Continue", action: next)
            } else {
                HearthOnboardingButtons(app: .hearken, primary: "Turn On Review", action: turnOnReview, secondary: "Not Now", secondaryAction: next)
            }
        }
    }

    private func turnOnReview() {
        reviewBinding.wrappedValue = true
        next()
    }

    /// The same as Profile › Review Questions.
    private var reviewBinding: Binding<Bool> {
        Binding(
            get: { reviewNotifications },
            set: { on in
                reviewNotifications = on
                guard on else { return }
                Task {
                    let granted = await ReviewNotifications.requestPermission()
                    if !granted { reviewNotifications = false }
                }
            }
        )
    }

    private var reviewTimeBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: reviewMinutes / 60, minute: reviewMinutes % 60, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reviewMinutes = (parts.hour ?? 12) * 60 + (parts.minute ?? 30)
            }
        )
    }

    // MARK: All set

    private var readyPage: some View {
        let household = HearthHouseholdStore.shared
        let reviewTime = reviewTimeBinding.wrappedValue.formatted(date: .omitted, time: .shortened)
        return HearthOnboardingPage(
            app: .hearken, symbol: "checkmark",
            title: "You’re all set",
            subtitle: "Here’s your plan."
        ) {
            VStack(spacing: 14) {
                if let plan = chosenPlan {
                    HearthOnboardingSummaryRow(app: .hearken, title: plan.title, detail: "Starts today with \(plan.chapterIDs.first.map(PlanFormat.chapterName) ?? plan.subtitle)")
                } else {
                    HearthOnboardingSummaryRow(app: .hearken, title: "At your own pace", detail: "Start a plan anytime in Library › Reading Plans")
                }
                HearthOnboardingSummaryRow(app: .hearken, title: "\(dailyGoal) minutes a day", detail: studyReminder ? "Reminder at 8:00 PM" : "No reminder")
                HearthOnboardingSummaryRow(app: .hearken, title: reviewNotifications ? "A review question at \(reviewTime)" : "Spaced Review", detail: reviewNotifications ? "From what you read" : "In Play, whenever you like")
                HearthOnboardingSummaryRow(app: .hearken, title: household.info?.name ?? "Your household", detail: household.people.count > 1 ? "Readings on Caloma’s family calendar" : "Add your family anytime in Profile")
            }
            .padding(16)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 22, style: .continuous))
        } controls: {
            HearthOnboardingButtons(app: .hearken, primary: "Continue", action: next)
        }
    }
}

/// The welcome: what Hearken does, and an optional Sign in with Apple (or "Continue as" the
/// sign-in another Hearth app shared). Signing in also signs in to the Hearth API for study
/// groups, as in Profile.
private struct OnboardingWelcome: View {
    var next: () -> Void

    @Environment(AccountService.self) private var account
    @State private var errorMessage: String?
    @State private var appleNonce: String?
    @State private var sharedSignIn: HearthSharedAppleID?

    var body: some View {
        HearthOnboardingPage(
            app: .hearken,
            title: "Hearken",
            subtitle: "Study the scriptures and remember what you learn."
        ) {
            VStack(spacing: 20) {
                HearthOnboardingFeature(app: .hearken, symbol: "highlighter", title: "Read and mark", detail: "Highlight, underline and keep notes as you study.")
                HearthOnboardingFeature(app: .hearken, symbol: "headphones", title: "Listen", detail: "Hear any chapter read aloud, even with the screen locked.")
                HearthOnboardingFeature(app: .hearken, symbol: "star.fill", title: "Learn and play", detail: "Climb the Scholar Path with quick games and earn ranks.")
            }
        } controls: {
            if account.isSignedIn {
                HearthOnboardingButtons(app: .hearken, primary: "Continue", action: next)
            } else {
                if let shared = sharedSignIn {
                    SharedSignInButton(shared: shared) {
                        next()
                    } onFailed: { message in
                        sharedSignIn = nil
                        errorMessage = message
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        // The same sign-in also signs in to the Hearth account, as in Profile, so
                        // the other Hearth apps (and study groups) see it.
                        appleNonce = HearthAPI.prepareAppleRequest(request)
                    } onCompletion: { result in
                        do {
                            try account.completeSignIn(result)
                            if case .success(let authorization) = result,
                               let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                let nonce = appleNonce
                                Task { await HearthConnection.shared.connect(credential: credential, nonce: nonce) }
                            }
                            next()
                        } catch let error as ASAuthorizationError where error.code == .canceled {
                            // The person closed the sheet; nothing to report.
                        } catch {
                            errorMessage = FriendlyError.signIn(error)
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(Capsule())
                }
                HearthOnboardingButtons(
                    app: .hearken,
                    secondary: "Continue Without an Account", secondaryAction: next,
                    footnote: "Optional. Signing in adds your name and lets you join study groups. Everything else syncs with iCloud without it."
                )
                LegalFooter()
            }
        }
        .alert("Couldn't sign in", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { sharedSignIn = await account.sharedSignInToOffer() }
    }
}
