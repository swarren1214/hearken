import AuthenticationServices
import SwiftUI

/// First-launch screen. Sign in with Apple is the only sign-in option; "Not now" lets people
/// read and practice without an account (App Review guideline 5.1.1).
struct SignInView: View {
    var onFinish: () -> Void

    @Environment(AccountService.self) private var account
    @State private var signedIn = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    AppIconBadge(size: 92)
                    Text("Hearken")
                        .font(.largeTitle.bold())
                        .padding(.top, 6)
                    Text("Study the scriptures and remember what you learn.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 290)

                    if signedIn {
                        signedInConfirmation
                    } else {
                        features
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 64)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.basedOnSize)

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
        }
        .alert("Couldn't sign in", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(symbol: "book.fill", title: "Read and mark", detail: "Highlight, underline and take notes in the scriptures.")
            FeatureRow(symbol: "gamecontroller.fill", title: "Learn by playing", detail: "Games and mastery meters across seven subjects.")
            FeatureRow(symbol: "icloud.fill", title: "Private by design", detail: "Your notes and progress live in your own iCloud. No ads, no tracking.")
        }
        .padding(.top, 32)
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
        .padding(.top, 40)
    }

    private var signInControls: some View {
        VStack(spacing: 6) {
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

            Button("Not now", action: onFinish)
                .frame(minHeight: 44)

            Text("Sign in to sync notes, highlights and progress. You can read and practice without an account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LegalFooter()
                .padding(.top, 4)
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
