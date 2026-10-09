import AuthenticationServices
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AccountService.self) private var account
    @Environment(HighlightLegend.self) private var legend

    @AppStorage(SettingsKey.accent) private var accent: AccentOption = .blue
    @AppStorage(SettingsKey.appearance) private var appearance: AppearanceOption = .system
    @AppStorage(SettingsKey.scriptureTextSize) private var textSize: Double = 20
    @AppStorage(SettingsKey.showVerseNumbers) private var showVerseNumbers = true
    @AppStorage(SettingsKey.readerLayout) private var readerLayout: ReaderLayout = .scroll
    @AppStorage(SettingsKey.pencilHighlighting) private var pencilHighlighting = false
    @AppStorage(SettingsKey.dailyGoalMinutes) private var dailyGoal = 15
    @AppStorage(SettingsKey.studyReminder) private var studyReminder = false

    @State private var confirmDelete = false
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
                        Text("Pencil Highlighting")
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
            Text("This removes your notes, highlights and progress from this device and from iCloud. It can't be undone.")
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
                    AppIconBadge(size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName ?? "Signed in").font(.headline)
                        Text("Sign in with Apple").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("iCloud")
                    Spacer()
                    iCloudStatus
                }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
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

    @ViewBuilder
    private var iCloudStatus: some View {
        switch account.iCloudAvailable {
        case .some(true):
            Label(AppConfig.cloudSyncEnabled ? "Syncing" : "Available", systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
        case .some(false):
            Label("Off", systemImage: "xmark.icloud")
                .foregroundStyle(.secondary)
        case .none:
            ProgressView()
        }
    }

    private func deleteAccount() {
        do {
            try account.deleteAccount(context: modelContext)
        } catch {
            errorMessage = error.localizedDescription
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
