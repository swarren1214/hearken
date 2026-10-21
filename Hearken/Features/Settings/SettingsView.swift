import AuthenticationServices
import CloudKit
import PhotosUI
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AccountService.self) private var account
    @Environment(HighlightLegend.self) private var legend
    @Environment(SyncService.self) private var sync

    @AppStorage(ScholarDebug.unlockAllKey) private var unlockAllCourses = false
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKey.scriptureTextSize) private var textSize: Double = 20
    @AppStorage(SettingsKey.showVerseNumbers) private var showVerseNumbers = true
    @AppStorage(SettingsKey.readerLayout) private var readerLayout: ReaderLayout = .scroll
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 15
    @AppStorage(SettingsKey.studyReminder) private var studyReminder = false
    @AppStorage(SettingsKey.reviewNotifications) private var reviewNotifications = false
    @AppStorage(SettingsKey.reviewNotificationMinutes) private var reviewMinutes = ReviewNotifications.defaultMinutes

    @State private var confirmDelete = false
    @State private var confirmSignOut = false
    /// The nonce for the Sign in with Apple request, which also signs in to the Hearth API.
    @State private var appleNonce: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var tipsReset = false
    /// The sign-in another Hearth app shared, offered as "Continue as <name>".
    @State private var sharedSignIn: HearthSharedAppleID?
    /// The tip being bought, for its button's spinner.
    @State private var tipping: String?
    @State private var tipThanks = false
    @State private var tipPending = false
    private var hearth: HearthLink { HearthLink.shared }

    var body: some View {
        // The shared Hearth Profile (HearthProfile.swift), with Hearken's own sections in the middle.
        HearthProfileView(
            app: .hearken,
            profile: accountProfile,
            sync: HearthProfileSync(summary: "Your highlights, notes and progress", sharing: syncSharing) {
                syncSnapshot
            } syncNow: {
                await sync.syncNow(context: modelContext)
                await CloudRefresh.refresh()
            },
            erase: HearthProfileErase(
                app: .hearken,
                message: "This removes your notes, highlights, plans and progress from this device and from iCloud. Your Hearth account, study groups and household aren't affected. It can't be undone."
            ) {
                do {
                    try Persistence.eraseAll(in: modelContext)
                } catch {
                    errorMessage = FriendlyError.message(error, action: "erase your data")
                }
            }
        ) {
            accountSection
        } settings: {
            hearkenSections
        } data: {
        } about: {
            // Kokoro's model and voices are Apache 2.0, which asks for attribution.
            Link("Natural voices: Kokoro · Apache 2.0", destination: URL(string: "https://huggingface.co/hexgrad/Kokoro-82M")!)
                .tint(Color.secondary)
            Text(AppConfig.disclaimer)
        }
        // Delete Account is only offered when signed in (Erase Hearken Data covers signed out).
        .alert("Delete your Hearth account?", isPresented: $confirmDelete) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your Hearth account, which your other Hearth apps use too, and everything it keeps on Hearth's servers. You leave your study groups and what you shared in them is deleted; groups you own pass to another member. Your notes, highlights, plans and progress are removed from this device and from iCloud, and you're signed out of your Hearth apps on this iPhone. A Hearken Plus or Hearth+ subscription isn't canceled; cancel it in Settings › Apple Account › Subscriptions. This can't be undone.")
        }
        .alert("Sign out of Hearken?", isPresented: $confirmSignOut) {
            // Also signs out of the other Hearth apps on this iPhone (one shared sign-in).
            Button("Sign Out", role: .destructive) { account.signOutEverywhere() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This also signs you out of your other Hearth apps on this iPhone. Your notes, highlights and progress stay on this device and in iCloud.")
        }
        .alert("Thank you!", isPresented: $tipThanks) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your tip helps keep Hearken free for everyone who studies with it, with no ads. It means a lot.")
        }
        .alert("Waiting for Approval", isPresented: $tipPending) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your tip will go through once it's approved. Thank you for thinking of Hearken.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Hearken's own settings: appearance, text, reading, study and tips.
    @ViewBuilder
    private var hearkenSections: some View {
        Section {
            AppearancePicker(selection: $appearance)
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your iPhone's Light and Dark setting, including scheduled switching.")
        }

        Section {
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
        } header: {
            HStack {
                Text("Text Size")
                Spacer()
                Text("\(Int(textSize)) pt").monospacedDigit()
            }
        } footer: {
            Text("Alma 32:27. Also adjustable from the … menu in the reader.")
        }

        Section("Reading") {
            NavigationLink {
                HighlightColorsView()
            } label: {
                HStack {
                    Text("Highlight Colors")
                    Spacer()
                    HStack(spacing: -4) {
                        ForEach(legend.entries.prefix(4)) { entry in
                            Circle()
                                .fill(entry.hue.color)
                                .frame(width: 14, height: 14)
                                .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        }
                    }
                    Text("\(legend.entries.count)").foregroundStyle(.secondary)
                }
            }
            NavigationLink {
                ListenSettingsView()
            } label: {
                LabeledContent("Listening", value: ListenEngine.shared.voiceName)
            }
            Toggle("Verse Numbers", isOn: $showVerseNumbers)
            CheckPicker("Layout", selection: $readerLayout, options: ReaderLayout.allCases.map {
                .init(value: $0, title: $0.title, systemImage: $0.symbol)
            })
        }

        Section("Study") {
            NavigationLink {
                BadgesView()
            } label: {
                Label("Badges", systemImage: "medal")
            }
            // The icon matches the title, not the accent (the Stepper and Toggle keep it).
            .tint(Color.primary)
            Stepper(value: $dailyGoal, in: 5...60, step: 5) {
                LabeledContent("Daily Goal", value: "\(dailyGoal) min")
            }
            Toggle("Study Reminder", isOn: reminderBinding)
        }

        Section {
            Toggle("Review Questions", isOn: reviewBinding)
            if reviewNotifications {
                DatePicker("Time", selection: reviewTimeBinding, displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text("A daily Spaced Review question you can answer right from the notification, on iPhone or Apple Watch.")
        }

        #if DEBUG
        Section {
            Toggle("Unlock All Courses", isOn: $unlockAllCourses)
        } header: {
            Text("Developer")
        } footer: {
            Text("Debug builds only. Opens every Scholar Path course and check so a path can be reviewed end to end. XP and rank rules are unchanged.")
        }
        #endif

        if account.isSignedIn, HearthConnection.shared.isConnected || !GroupStore.shared.blockedUserIDs.isEmpty {
            Section {
                NavigationLink {
                    BlockedPeopleView()
                } label: {
                    LabeledContent {
                        let count = GroupStore.shared.blockedUserIDs.count
                        if count > 0 { Text("\(count)") }
                    } label: {
                        Label("Blocked People", systemImage: "hand.raised")
                    }
                }
            } header: {
                Text("Study Groups")
            } footer: {
                Text("You don't see posts, replies or answers from people you block.")
            }
            .tint(Color.primary)
        }

        Section {
            Button(tipsReset ? "Tips Will Show Again" : "Show All Tips Again", systemImage: tipsReset ? "checkmark" : "lightbulb") {
                UserDefaults.standard.set(true, forKey: SettingsKey.tipsResetPending)
                withAnimation { tipsReset = true }
            }
            .disabled(tipsReset)
        } header: {
            Text("Tips")
        } footer: {
            Text(tipsReset
                 ? "Reader tips reappear after you next open Hearken, the next time you reach each feature."
                 : "Reader tips reappear the next time you reach each feature.")
        }
        .tint(Color.primary)

        supportSection
    }

    /// Who's signed in, for the account card at the top (nil shows Sign in with Apple).
    private var accountProfile: HearthAccountProfile? {
        guard account.isSignedIn else { return nil }
        return HearthAccountProfile(name: account.displayName, email: account.email, photo: account.avatarData ?? hearth.sharedAvatar)
    }

    // MARK: Account

    /// A photo is set: their household photo when they're in a household, else Hearken's own.
    private var hasProfilePhoto: Bool {
        if let me = HearthHouseholdStore.shared.me { return me.photo != nil }
        return account.avatarData != nil
    }

    @ViewBuilder
    private var accountSection: some View {
        Section {
            HearthAccountSection(
                app: .hearken,
                profile: account.isSignedIn
                    ? HearthAccountProfile(name: account.displayName, email: account.email, photo: account.avatarData ?? hearth.sharedAvatar)
                    : nil,
                pitch: "Optional: signing in adds your name to your profile and lets your other Hearth apps recognize you. Study groups need it (they show your name and initials, never your photo); everything else works without it."
            ) {
                if let shared = sharedSignIn {
                    SharedSignInButton(shared: shared) {
                        sharedSignIn = nil
                    } onFailed: { message in
                        sharedSignIn = nil
                        errorMessage = message
                    }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                        // The same sign-in also signs in to the Hearth API (study groups).
                        appleNonce = HearthAPI.prepareAppleRequest(request)
                    } onCompletion: { result in
                        do {
                            try account.completeSignIn(result)
                            if case .success(let authorization) = result,
                               let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                                let nonce = appleNonce
                                Task { await HearthConnection.shared.connect(credential: credential, nonce: nonce) }
                            }
                        } catch let error as ASAuthorizationError where error.code == .canceled {
                        } catch {
                            errorMessage = FriendlyError.signIn(error)
                        }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                }
            } rows: {
                PhotosPicker(selection: $avatarItem, matching: .images) {
                    HearthAccountRow(hasProfilePhoto ? "Change Profile Photo" : "Add Profile Photo", systemImage: "camera", showsChevron: false)
                }
                .buttonStyle(.plain)
                if hasProfilePhoto {
                    Button(role: .destructive) {
                        if let me = HearthHouseholdStore.shared.me { HearthHouseholdStore.shared.setPhoto(nil, for: me.id) }
                        account.setAvatar(nil)
                    } label: {
                        HearthAccountRow("Remove Photo", systemImage: "trash", showsChevron: false)
                    }
                    .buttonStyle(.plain)
                }
            } onSignOut: {
                confirmSignOut = true
            } onDeleteAccount: {
                confirmDelete = true
            }
            .hearthAccountSectionRow()
            .task(id: account.isSignedIn) {
                sharedSignIn = account.isSignedIn ? nil : await account.sharedSignInToOffer()
            }
            .task(id: HearthHouseholdStore.shared.me?.photo) {
                // Once the household has their photo (Hearken's older one was adopted, or they
                // chose one in another app), Hearken's own copy goes.
                if HearthHouseholdStore.shared.me?.photo != nil, account.avatarData != nil { account.setAvatar(nil) }
            }
            .onChange(of: avatarItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let jpeg = AccountAvatar.thumbnail(from: data) {
                        // Their household photo, the one every Hearth app shows; Hearken keeps
                        // its own copy only for someone not in a household.
                        if let me = HearthHouseholdStore.shared.me, HearthHouseholdStore.shared.setPhoto(jpeg, for: me.id) {
                            account.setAvatar(nil)
                        } else {
                            account.setAvatar(jpeg)
                        }
                    }
                    avatarItem = nil
                }
            }
        } header: {
            HStack {
                Text("Account")
                Spacer()
                // "HEARTH+" or "HEARKEN PLUS" beside the signed-in person.
                if account.isSignedIn { HearthMemberBadge() }
            }
        }

    }

    // MARK: Tips

    /// One-time tips, for people who'd like to give something. Hidden when there are none to offer.
    @ViewBuilder
    private var supportSection: some View {
        let tips = HearthPurchases.shared.tips
        if !tips.isEmpty {
            Section {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { tipButtons(tips) }
                    VStack(spacing: 10) { tipButtons(tips) }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Support Hearken")
            } footer: {
                Text("A one-time tip helps keep Hearken growing and free to read. It doesn't unlock anything, just our thanks.")
            }
        }
    }

    @ViewBuilder
    private func tipButtons(_ tips: [HearthPlan]) -> some View {
        ForEach(tips) { tip in
            Button {
                Task { await buy(tip) }
            } label: {
                Group {
                    if tipping == tip.id {
                        ProgressView()
                    } else {
                        Text(tip.price).monospacedDigit()
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.glass)
            .tint(Color.primary)
            .disabled(tipping != nil)
            .accessibilityLabel("Tip \(tip.price)")
        }
    }

    private func buy(_ tip: HearthPlan) async {
        tipping = tip.id
        defer { tipping = nil }
        switch await HearthPurchases.shared.purchase(tip) {
        case .purchased: tipThanks = true
        case .pending: tipPending = true
        case .cancelled: break
        case .failed(let message): errorMessage = message
        }
    }

    // MARK: iCloud

    /// What the iCloud Sync card shows, from the iCloud account and SyncService.
    private var syncSnapshot: HearthSyncSnapshot {
        let state: HearthSyncSnapshot.Account
        switch account.iCloudAvailable {
        case nil:
            state = .checking
        case false?:
            state = .unavailable("Sign in to iCloud in Settings to keep your highlights, notes and progress on all your devices.")
        case true? where !AppConfig.cloudSyncEnabled:
            state = .unavailable("iCloud sync is turned off in this build.")
        case true?:
            state = .available
        }
        return HearthSyncSnapshot(
            account: state,
            // Sync Now running, or CloudKit uploading or downloading on its own.
            isSyncing: sync.isActive,
            lastSynced: sync.lastSynced,
            pendingChanges: nil,
            errorMessage: syncErrorMessage
        )
    }

    /// The last sync error in words a person can act on. Network trouble isn't shown (the card
    /// says "Waiting to sync" when offline and CloudKit retries on its own), and neither is a
    /// signed-out account (the card shows iCloud as off).
    private var syncErrorMessage: String? {
        guard sync.lastError != nil else { return nil }
        switch sync.lastErrorCode {
        case .quotaExceeded?:
            return "iCloud storage is full, so new changes can’t be saved there. Free up space in Settings › [your name] › iCloud."
        case .networkUnavailable?, .networkFailure?, .notAuthenticated?:
            return nil
        default:
            return "iCloud couldn’t sync right now. Hearken will try again on its own."
        }
    }

    /// The study groups this person is in, with up to three of the other members.
    private var syncSharing: HearthSyncSharing? {
        let store = GroupStore.shared
        let groups = store.groups
        guard !groups.isEmpty else { return nil }
        var seen: Set<String> = []
        var people: [HearthSyncSharing.Person] = []
        for member in groups.flatMap(\.members) where member.userID != store.myUserID {
            guard people.count < 3, seen.insert(member.userID).inserted else { continue }
            let initial = String((member.initials.isEmpty ? member.name : member.initials).prefix(1)).uppercased()
            guard !initial.isEmpty else { continue }
            people.append(HearthSyncSharing.Person(id: member.userID, initial: initial, colorHex: Self.memberColor(member.name)))
        }
        return HearthSyncSharing(label: groups.count == 1 ? "1 study group" : "\(groups.count) study groups", people: people)
    }

    /// The same color MemberAvatar gives this name in Study Groups.
    private static func memberColor(_ name: String) -> UInt32 {
        let palette: [UInt32] = [0x5E5CE6, 0xE0244A, 0x24A148, 0xE68600, 0x0E8A8A, 0x8E44C9]
        let seed = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[seed % palette.count]
    }

    /// Signed in: deletes the Hearth account on the server (which also takes care of study
    /// groups), then the data here and in iCloud, and signs out everywhere. If the server call
    /// fails, nothing is deleted and the error shows. Signed out: local data only, no server call.
    private func deleteAccount() {
        Task {
            do {
                try await account.deleteAccount(context: modelContext)
            } catch {
                errorMessage = FriendlyError.message(error, action: "delete your account")
            }
        }
    }

    // MARK: Reminder

    private var reviewBinding: Binding<Bool> {
        Binding(
            get: { reviewNotifications },
            set: { newValue in
                reviewNotifications = newValue
                guard newValue else { return }
                Task {
                    let granted = await ReviewNotifications.requestPermission()
                    if !granted { reviewNotifications = false }
                }
            }
        )
    }

    private var reviewTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: reviewMinutes / 60, minute: reviewMinutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                reviewMinutes = (parts.hour ?? 12) * 60 + (parts.minute ?? 30)
            }
        )
    }

    private var reminderBinding: Binding<Bool> {
        Binding(
            get: { studyReminder },
            set: { newValue in
                studyReminder = newValue
                if newValue {
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
}

/// Three thumbnails (System, Light, Dark) with radio buttons, matching the design.
private struct AppearancePicker: View {
    @Binding var selection: AppearanceOption

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AppearanceOption.allCases) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 8) {
                        AppearanceThumbnail(option: option)
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.separator)),
                                                  lineWidth: isSelected ? 3 : 0.5)
                            }
                        Text(option.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiaryLabel)))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// A miniature screen: a title bar and two cards, in light, dark, or split for System.
private struct AppearanceThumbnail: View {
    let option: AppearanceOption

    private struct Palette {
        let background: Color
        let card: Color
        let bar: Color
    }

    private static let light = Palette(background: Color(white: 0.95), card: .white, bar: Color(white: 0.82))
    private static let dark = Palette(background: Color(white: 0.11), card: Color(white: 0.23), bar: Color(white: 0.4))

    var body: some View {
        Group {
            switch option {
            case .light:
                screen(Self.light)
            case .dark:
                screen(Self.dark)
            case .system:
                screen(Self.light)
                    .overlay(alignment: .trailing) {
                        GeometryReader { proxy in
                            screen(Self.dark)
                                .mask(alignment: .trailing) {
                                    Rectangle().frame(width: proxy.size.width / 2)
                                }
                        }
                    }
            }
        }
        .frame(height: 120)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }

    private func screen(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule().fill(palette.bar).frame(width: 46, height: 10)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.card).frame(height: 32)
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.card).frame(height: 32)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack { SettingsView() }
        .previewEnvironment(signedIn: true)
}

/// The person's profile photo, or their initials in the accent color when there's no photo.
struct AccountAvatar: View {
    let initials: String?
    let imageData: Data?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(.tint)
                    if let initials {
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// A square, 256-point JPEG of the chosen photo: small enough to sync through iCloud
    /// key-value storage (which allows 1 MB in total).
    static func thumbnail(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
        let target = CGSize(width: 256, height: 256)
        let renderer = UIGraphicsImageRenderer(size: target)
        let thumb = renderer.image { _ in
            let scale = target.width / side
            image.draw(in: CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
        return thumb.jpegData(compressionQuality: 0.8)
    }
}

private extension View {
    /// Starts the row's separator at the row's leading edge. By default a separator lines up
    /// with the first text it finds, so rows with an avatar or an icon label (like the iCloud
    /// status) got separators of different lengths.
    func fullWidthSeparator() -> some View {
        alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}
