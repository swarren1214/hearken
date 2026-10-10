import AuthenticationServices
import PhotosUI
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AccountService.self) private var account
    @Environment(HighlightLegend.self) private var legend
    @Environment(SyncService.self) private var sync

    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKey.scriptureTextSize) private var textSize: Double = 20
    @AppStorage(SettingsKey.showVerseNumbers) private var showVerseNumbers = true
    @AppStorage(SettingsKey.readerLayout) private var readerLayout: ReaderLayout = .scroll
    @AppStorage(SettingsKey.pencilHighlighting) private var pencilHighlighting = false
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 15
    @AppStorage(SettingsKey.studyReminder) private var studyReminder = false

    @State private var confirmDelete = false
    @State private var avatarItem: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            accountSection

            Section {
                AppearancePicker(selection: $appearance)
            } header: {
                Text("Appearance")
            } footer: {
                Text("System follows your iPhone's Light and Dark setting, including scheduled switching.")
            }

            Section {
                accentPicker
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Used for buttons, progress rings and mastery meters. Highlight colors are set separately.")
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
                Toggle("Verse Numbers", isOn: $showVerseNumbers)
                Picker("Layout", selection: $readerLayout) {
                    ForEach(ReaderLayout.allCases) { layout in
                        Label(layout.title, systemImage: layout.symbol).tag(layout)
                    }
                }
                if UIDevice.isPad {
                    Toggle(isOn: $pencilHighlighting) {
                        Text("Pencil Mode")
                        Text("Draw over text with Apple Pencil to highlight it.")
                    }
                }
            }

            Section("Study") {
                Stepper(value: $dailyGoal, in: 5...60, step: 5) {
                    LabeledContent("Daily Goal", value: "\(dailyGoal) min")
                }
                Toggle("Study Reminder", isOn: reminderBinding)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersion)
                Link("Terms of Use", destination: AppConfig.termsURL)
                Link("Privacy Policy", destination: AppConfig.privacyURL)
                Link("Support", destination: AppConfig.supportURL)
                Text(AppConfig.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", systemImage: "checkmark") { dismiss() }
            }
        }
        .confirmationDialog("Delete your Hearken account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Account and Data", role: .destructive) { deleteAccount() }
        } message: {
            Text("This removes your notes, highlights, plans and progress from this device and from iCloud, deletes the study groups you created and leaves the ones you joined. It can't be undone.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Account

    @ViewBuilder
    private var accountSection: some View {
        Section {
            if account.isSignedIn {
                HStack(spacing: 14) {
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        AccountAvatar(initials: account.initials, imageData: account.avatarData, size: 56)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(.tint, in: Circle())
                                    .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                                    .offset(x: 2, y: 2)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(account.avatarData == nil ? "Add profile photo" : "Change profile photo")
                    .contextMenu {
                        if account.avatarData != nil {
                            Button("Remove Photo", systemImage: "trash", role: .destructive) { account.setAvatar(nil) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName ?? "Signed in").font(.headline)
                        Text(account.email ?? "Signed in with Apple")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .fullWidthSeparator()
                .onChange(of: avatarItem) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let jpeg = AccountAvatar.thumbnail(from: data) {
                            account.setAvatar(jpeg)
                        }
                        avatarItem = nil
                    }
                }
                HStack {
                    Text("iCloud")
                    Spacer()
                    iCloudStatus
                }
                .fullWidthSeparator()
                syncRow
                    .fullWidthSeparator()
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    do {
                        try account.completeSignIn(result)
                    } catch let error as ASAuthorizationError where error.code == .canceled {
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)
                .clipShape(Capsule())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } header: {
            Text("Account")
        } footer: {
            if !account.isSignedIn {
                Text("Sign in to save highlights, notes and progress to your own iCloud.")
            } else if account.iCloudAvailable == false {
                Text("Your work stays on this iPhone until iCloud is turned on in Settings.")
            } else if let error = sync.lastError {
                Text("Couldn't sync: \(error)")
                    .foregroundStyle(.red)
            }
        }

        if account.isSignedIn {
            Section {
                VStack(spacing: 10) {
                    // Primary: filled with the accent color, white text and icon.
                    Button {
                        account.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            // Inside a Form the icon would pick up the accent; keep it white like the text.
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    // Destructive: filled red, white text and icon.
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                            // Inside a Form the icon would pick up the accent; keep it white like the text.
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                }
                .controlSize(.large)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    /// Last synced time and a Sync Now button. The time refreshes every 30 seconds.
    private var syncRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Last Synced")
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(lastSyncedText(now: context.date))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            Spacer()
            Button {
                Task { await sync.syncNow(context: modelContext) }
            } label: {
                Label(sync.isSyncing ? "Syncing" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: sync.isSyncing)
                    .contentTransition(.interpolate)
            }
            .buttonStyle(.glass)
            .tint(Color.primary)
            .disabled(sync.isSyncing || account.iCloudAvailable != true)
            .accessibilityHint("Saves your highlights, notes and progress to iCloud now.")
        }
        .animation(.snappy, value: sync.isSyncing)
        .sensoryFeedback(.success, trigger: sync.lastSynced)
        .sensoryFeedback(.error, trigger: sync.lastError) { _, error in error != nil }
    }

    private func lastSyncedText(now: Date) -> String {
        if sync.isActive { return "Syncing…" }
        guard let date = sync.lastSynced else { return "Not yet synced" }
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return "Just now" }
        if elapsed < 60 * 60 { return date.formatted(.relative(presentation: .named)) }
        if Calendar.current.isDateInToday(date) { return "Today at \(date.formatted(date: .omitted, time: .shortened))" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday at \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    @ViewBuilder
    private var iCloudStatus: some View {
        switch account.iCloudAvailable {
        case .some(true) where !AppConfig.cloudSyncEnabled:
            Label("Available", systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
        case .some(true) where sync.isActive:
            Label("Syncing", systemImage: "arrow.triangle.2.circlepath.icloud")
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeat(.continuous))
        case .some(true) where sync.lastError != nil:
            Label("Not Synced", systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
        case .some(true):
            Label("Synced", systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
        case .some(false):
            Label("Off", systemImage: "xmark.icloud")
                .foregroundStyle(.secondary)
        case .none:
            ProgressView()
        }
    }

    private func deleteAccount() {
        Task {
            // First the shared groups (they live in iCloud, not on this device), then everything else.
            await GroupStore.shared.leaveAll()
            do {
                try account.deleteAccount(context: modelContext)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: Accent

    private var accentPicker: some View {
        HStack {
            ForEach(AccentOption.allCases) { option in
                Button {
                    accent = option
                } label: {
                    Circle()
                        .fill(option.color)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if option == accent {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .padding(3)
                        .overlay {
                            if option == accent {
                                Circle().strokeBorder(option.color, lineWidth: 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.name)
                .accessibilityAddTraits(option == accent ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: accent)
    }

    // MARK: Reminder

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
