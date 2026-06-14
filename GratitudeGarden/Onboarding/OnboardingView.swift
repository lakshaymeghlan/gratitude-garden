import SwiftUI

/// A short, warm welcome (well under 60 seconds): a few gentle slides that set the forgiving tone,
/// then a one-time choice of home — the permanent center of the garden — leading into the first entry.
struct OnboardingView: View {
    /// Called when the user finishes, with the home they chose. The caller persists it, marks
    /// onboarding complete, and opens the composer.
    let onFinish: (HomeStyle) -> Void

    @State private var page = 0
    @State private var selectedHome: HomeStyle?

    private struct Slide: Identifiable {
        let id = UUID()
        let snapshot: GardenSnapshot
        let title: String
        let body: String
    }

    private let slides: [Slide] = [
        Slide(snapshot: .preview(totalEntries: 30),
              title: "Welcome to your garden",
              body: "Your garden grows around your home, one small moment at a time."),
        Slide(snapshot: .preview(vitality: .drooping, wiltLevel: 2, totalEntries: 20),
              title: "Missing a few days is okay",
              body: "Life happens. Your garden waits patiently — it never judges, and it never rushes you."),
        Slide(snapshot: .preview(vitality: .dormant, wiltLevel: 4, totalEntries: 20),
              title: "The garden never dies",
              body: "If you're away a while it simply rests. The moment you return, it comes back to life."),
    ]

    /// The home-pick page lives at index `slides.count`.
    private var homePage: Int { slides.count }
    private var lastPage: Int { slides.count }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                    slideView(slide).tag(index)
                }
                homePicker.tag(homePage)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            Button(action: advance) {
                Text(page < homePage ? "Continue" : "Plant your first seed")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(page == homePage && selectedHome == nil)
            .padding()
        }
    }

    private func slideView(_ slide: Slide) -> some View {
        VStack(spacing: 20) {
            GardenSceneView(snapshot: slide.snapshot, homeStyle: .cottage, animated: false, interactive: false)
                .aspectRatio(0.85, contentMode: .fit)
                .frame(maxWidth: 280)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(slide.title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                Text(slide.body).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
        }
        .padding(.top, 32)
    }

    private var homePicker: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Choose your home").font(.title2.weight(.semibold))
                Text("Your garden will grow around it.").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(HomeStyle.allCases) { style in
                    homeTile(style)
                }
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
        }
    }

    private func homeTile(_ style: HomeStyle) -> some View {
        let selected = selectedHome == style
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { selectedHome = style }
        } label: {
            VStack(spacing: 6) {
                GardenSceneView(snapshot: .preview(totalEntries: 8), homeStyle: style, animated: false, interactive: false)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(selected ? Color.green : Color.black.opacity(0.08), lineWidth: selected ? 3 : 1))
                Text(style.displayName).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(style.blurb).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(style.displayName). \(style.blurb)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func advance() {
        if page < homePage {
            withAnimation { page += 1 }
        } else {
            onFinish(selectedHome ?? .cottage)
        }
    }
}

#Preview {
    OnboardingView { _ in }
}
