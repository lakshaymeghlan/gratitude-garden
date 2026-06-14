import SwiftUI

/// A short, warm welcome (well under 60 seconds). It sets the forgiving expectation up front and
/// ends by leading straight into the first entry. No productivity or streak language anywhere.
struct OnboardingView: View {
    /// Called when the user finishes — the caller marks onboarding complete and opens the composer.
    let onFinish: () -> Void

    @State private var page = 0

    private struct Slide: Identifiable {
        let id = UUID()
        let snapshot: GardenSnapshot
        let title: String
        let body: String
    }

    private let slides: [Slide] = [
        Slide(snapshot: .preview(growth: .blooming, vitality: .thriving),
              title: "Welcome to your garden",
              body: "Your garden grows when you tend it — one small moment at a time."),
        Slide(snapshot: .preview(growth: .seedling, vitality: .drooping, wiltLevel: 2),
              title: "Missing a few days is okay",
              body: "Life happens. Your garden waits patiently — it never judges, and it never rushes you."),
        Slide(snapshot: .preview(growth: .budding, vitality: .dormant, wiltLevel: 4),
              title: "The garden never dies",
              body: "If you're away a while it simply rests. The moment you return, it begins to bloom again."),
        Slide(snapshot: .preview(growth: .flourishing, vitality: .thriving, isReviving: true),
              title: "A small moment is enough",
              body: "Gratitude on good days, or anything you got through on hard ones. There's no wrong entry."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    slideView(slide).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: advance) {
                Text(page == slides.count - 1 ? "Plant your first seed" : "Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: 20) {
            GardenSceneView(snapshot: slide.snapshot, interactive: false)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 280)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)   // the title/body below carry the meaning
            VStack(spacing: 10) {
                Text(slide.title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(slide.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 32)
    }

    private func advance() {
        if page < slides.count - 1 {
            withAnimation { page += 1 }
        } else {
            onFinish()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
