import SwiftUI

/// First-run introduction shown once. Explains the core loop
/// (scan a sign → read the parking signal → get an alarm) and sets
/// expectations before the app asks for camera / location / notification
/// permission in context.
struct OnboardingView: View {
    /// Called when the user finishes or skips onboarding.
    var onFinish: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(symbol: "camera.viewfinder",
             title: "Read and review parking signs",
             body: "Scan sign text on your device, then compare the suggested weekly rules with every sign on the curb. Complex exceptions need manual review."),
        Page(symbol: "circle.righthalf.filled",
             title: "Keep your parking rules together",
             body: "Signals summarize your saved rules. They cannot confirm parking legality or account for missing, temporary or unreadable signs."),
        Page(symbol: "alarm",
             title: "Set a parking reminder",
             body: "Save a spot, confirm its rules and enable reminders on this device. Check that notifications or alarms are allowed; delivery is not guaranteed.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .padding()
            }

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, item in
                    ScrollView {
                        VStack(spacing: 24) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 88, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            Text(item.title)
                                .font(.title.bold())
                                .multilineTextAlignment(.center)
                            Text(item.body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
