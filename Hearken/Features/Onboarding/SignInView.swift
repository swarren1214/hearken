import AuthenticationServices
import SwiftUI

/// First-launch screen. Sign in with Apple is the only sign-in option; "Not now" lets people
/// read and practice without an account (App Review guideline 5.1.1). When another Hearth app
/// on this device already signed in with Apple, it offers "Continue as <name>" instead.
struct SignInView: View {
    var onFinish: () -> Void

    @Environment(AccountService.self) private var account
    @State private var signedIn = false
    @State private var errorMessage: String?
    /// The sign-in another Hearth app shared, once Apple says it's still good.
    @State private var sharedSignIn: HearthSharedAppleID?
    /// The screen's height, to fit short screens (iPhone Duo's outer display, iPhone SE).
    @State private var height: CGFloat = 900

    /// Short screens: a smaller icon, less padding, and the fine print scrolls with the
    /// content so the pinned buttons don't cover the features.
    private var isShort: Bool { height < 760 }
    /// Wide screens (iPhone Duo's inner display, iPad) keep a readable column.
    private static let columnWidth: CGFloat = 460

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: isShort ? 10 : 14) {
                    AppIconBadge(size: isShort ? 64 : 92)
                    Text("Hearken")
                        .font(.largeTitle.bold())
                        .padding(.top, isShort ? 2 : 6)
                    Text("Study the scriptures and remember what you learn.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 290)

                    if signedIn {
                        signedInConfirmation
                    } else {
                        features
                        if isShort {
                            finePrint
                                .padding(.top, 20)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, isShort ? 24 : 64)
                .padding(.bottom, isShort ? 16 : 32)
                .frame(maxWidth: Self.columnWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollEdgeEffectStyle(.soft, for: .bottom)

            Group {
                if signedIn {
                    Button(action: onFinish) {
                        Text("Continue").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                } else {
                    signInControls
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
            .frame(maxWidth: Self.columnWidth)
        }
        .frame(maxWidth: .infinity)
        // Centered on the screen even where one side's inset is larger (iPhone Duo).
        .symmetricSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .alert("Couldn't sign in", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task { sharedSignIn = await account.sharedSignInToOffer() }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(symbol: "book.fill", title: "Read and mark", detail: "Highlight, underline and take notes in the scriptures.")
            FeatureRow(symbol: "gamecontroller.fill", title: "Learn by playing", detail: "Games and mastery meters across seven subjects.")
            FeatureRow(symbol: "icloud.fill", title: "Private by design", detail: "Your notes and progress live in your own iCloud. No ads, no tracking.")
        }
        .padding(.top, isShort ? 20 : 32)
    }

    private var signedInConfirmation: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: signedIn)
            Text("You're signed in")
                .font(.title2.bold())
            Text("Notes, highlights and progress will sync through iCloud to every device signed in to your Apple Account.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, isShort ? 20 : 40)
    }

    private var signInControls: some View {
        VStack(spacing: 6) {
            if let shared = sharedSignIn {
                SharedSignInButton(shared: shared) {
                    withAnimation { signedIn = true }
                } onFailed: { message in
                    sharedSignIn = nil
                    errorMessage = message
                }
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    do {
                        try account.completeSignIn(result)
                        withAnimation { signedIn = true }
                    } catch let error as ASAuthorizationError where error.code == .canceled {
                        // The person closed the sheet; nothing to report.
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .modifier(AdaptiveSignInStyle())
                .frame(height: 52)
                .clipShape(Capsule())
            }

            Button("Not now", action: onFinish)
                .frame(minHeight: 44)

            if !isShort { finePrint }
        }
    }

    private var finePrint: some View {
        VStack(spacing: 6) {
            Text("Optional. Signing in adds your name and photo. Everything else works, and syncs with iCloud, without it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LegalFooter()
                .padding(.top, 4)
        }
    }
}

/// "Continue as Steve": signs in with the Apple sign-in another Hearth app on this device shared
/// (`HearthAccounts.appleID()`), so nobody signs in to each app separately. Apple is still asked
/// whether the sign-in is valid. Shown in place of Sign in with Apple.
struct SharedSignInButton: View {
    let shared: HearthSharedAppleID
    var onSignedIn: () -> Void
    var onFailed: (String) -> Void

    @Environment(AccountService.self) private var account
    @State private var photo: Data?
    @State private var working = false

    private var firstName: String {
        shared.fullName?.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? "You"
    }

    var body: some View {
        Button {
            guard !working else { return }
            working = true
            Task {
                do {
                    try await account.continueWithSharedSignIn(shared)
                    onSignedIn()
                } catch {
                    onFailed(error.localizedDescription)
                }
                working = false
            }
        } label: {
            HStack(spacing: 10) {
                AccountAvatar(initials: firstName.first.map { String($0).uppercased() }, imageData: photo, size: 30)
                Text("Continue as \(firstName)")
                    .font(.headline)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(working)
        .accessibilityHint("Uses the Apple sign-in from your other Hearth apps")
        .task(id: shared.userID) {
            photo = shared.fullName.flatMap { Hearth.sharedPhoto(forName: $0, excluding: .hearken) }
        }
    }
}

/// The adaptive Sign in with Apple button style: black in light mode, white in dark mode.
private struct AdaptiveSignInStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The no-affiliation disclaimer with Terms and Privacy links.
struct LegalFooter: View {
    var body: some View {
        Text(footer)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var footer: AttributedString {
        let markdown = "\(AppConfig.disclaimer) By continuing you agree to the [Terms](\(AppConfig.termsURL.absoluteString)) and [Privacy Policy](\(AppConfig.privacyURL.absoluteString))."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }
}

#Preview {
    SignInView(onFinish: {})
        .environment(AccountService())
}
