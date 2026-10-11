import SwiftUI

/// The first screen of the tour, right after sign-in: three things Hearken does, then a choice.
/// A sheet on iPhone; a centered form-sized card on iPad.
struct WelcomeView: View {
    var tour = TourController.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                AppIconBadge(size: 84)
                    .padding(.top, 40)

                Text("Welcome to Hearken")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .padding(.top, 22)
                    .accessibilityAddTraits(.isHeader)

                Text("Read, listen and learn the scriptures, a little every day.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 22) {
                    feature(
                        "Read and mark", "Highlight, underline and keep notes as you study.",
                        symbol: "highlighter", color: .yellow
                    )
                    feature(
                        "Listen", "Hear any chapter read aloud, even with the screen locked.",
                        symbol: "headphones", color: .blue
                    )
                    feature(
                        "Learn and play", "Climb the Scholar Path with quick games and earn ranks.",
                        symbol: "star.fill", color: .green
                    )
                }
                .padding(.top, 32)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    tour.begin()
                } label: {
                    Text("Show Me Around")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Skip for Now") { tour.skip() }
                    .font(.body.weight(.medium))
                    .padding(.vertical, 6)
                    .keyboardShortcut(.cancelAction)
            }
            .frame(maxWidth: 440)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
        }
        .interactiveDismissDisabled()
        .presentationSizing(.form)
    }

    private func feature(_ title: String, _ detail: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) { WelcomeView() }
}
