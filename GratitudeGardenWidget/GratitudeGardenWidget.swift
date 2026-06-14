import WidgetKit
import SwiftUI

/// One point on the widget's timeline.
struct GardenEntry: TimelineEntry {
    let date: Date
    let snapshot: GardenSnapshot
    var homeStyle: HomeStyle = .cottage
}

/// Reads the shared `GardenState` and projects a timeline that **ages the garden over time** via the
/// pure `GardenTimelinePlanner`. The app still calls `WidgetCenter.reload…` after a save (which
/// regenerates this with fresh growth/revival); between those, this timeline carries the natural
/// thriving→drooping→dormant decay on its own.
struct GardenProvider: TimelineProvider {
    private let store: GardenStore
    private let preferences: AppPreferencesStore

    init(store: GardenStore = FileGardenStore(), preferences: AppPreferencesStore = FileAppPreferencesStore()) {
        self.store = store
        self.preferences = preferences
    }

    private var homeStyle: HomeStyle { preferences.load().homeStyle }

    func placeholder(in context: Context) -> GardenEntry {
        GardenEntry(date: Date(), snapshot: GardenRules.snapshot(state: .empty, now: Date()), homeStyle: homeStyle)
    }

    func getSnapshot(in context: Context, completion: @escaping (GardenEntry) -> Void) {
        completion(GardenEntry(date: Date(),
                               snapshot: GardenRules.snapshot(state: store.loadGarden(), now: Date()),
                               homeStyle: homeStyle))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GardenEntry>) -> Void) {
        let plan = GardenTimelinePlanner.plan(state: store.loadGarden(), now: Date())
        let home = homeStyle
        let entries = plan.moments.map { GardenEntry(date: $0.date, snapshot: $0.snapshot, homeStyle: home) }
        // `.atEnd`: once the projected arc (which already covers the full decay to dormancy) is done,
        // ask the system to rebuild. Day-boundary entries mean we never wake more than ~once a day.
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

/// Renders the widget. The garden scene is the full-bleed **container background** (the hero); text
/// is a minimal overlay. Tapping anywhere deep-links to the composer.
struct GratitudeGardenWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: GardenEntry

    private var snapshot: GardenSnapshot { entry.snapshot }

    var body: some View {
        overlay
            .containerBackground(for: .widget) {
                // Same world renderer; static + fixed camera (widgets don't animate or accept gestures).
                GardenSceneView(snapshot: snapshot, homeStyle: entry.homeStyle, animated: false, interactive: false)
            }
            .widgetURL(GardenDeepLink.composeURL)
    }

    @ViewBuilder
    private var overlay: some View {
        switch family {
        case .systemMedium: medium
        default:            small
        }
    }

    // Small: garden + growth stage + short supportive copy.
    private var small: some View {
        VStack(alignment: .leading, spacing: 1) {
            Spacer()
            Text(GardenCopy.growthTitle(snapshot.growthStage))
                .font(.subheadline.weight(.semibold))
            Text(GardenCopy.widgetShort(snapshot.vitality, isReviving: snapshot.isReviving))
                .font(.caption2)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
        .padding(.horizontal, 2)
        .background(bottomScrim)
    }

    // Medium: larger garden (hero) + growth stage, supportive message, and last tended date.
    private var medium: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(GardenCopy.growthTitle(snapshot.growthStage))
                    .font(.headline)
                Text(GardenCopy.vitalityTitle(snapshot.vitality, isReviving: snapshot.isReviving))
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Last tended")
                    .font(.caption2).opacity(0.8)
                Text(lastTendedText)
                    .font(.caption.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
        .background(bottomScrim)
    }

    // A soft gradient so light text stays legible over the art (the lower band sits over dark soil).
    private var bottomScrim: some View {
        LinearGradient(colors: [.clear, .black.opacity(0.30)],
                       startPoint: .center, endPoint: .bottom)
    }

    private var lastTendedText: String {
        guard let date = snapshot.lastEntryDate else { return "Not yet" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct GratitudeGardenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GardenWidget.kind, provider: GardenProvider()) { entry in
            GratitudeGardenWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Gratitude Garden")
        .description("A glance at how your garden is doing.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Thriving — small", as: .systemSmall) {
    GratitudeGardenWidget()
} timeline: {
    GardenEntry(date: .now, snapshot: .preview(growth: .flourishing, vitality: .thriving))
}

#Preview("Drooping — small", as: .systemSmall) {
    GratitudeGardenWidget()
} timeline: {
    GardenEntry(date: .now, snapshot: .preview(growth: .blooming, vitality: .drooping, wiltLevel: 2))
}

#Preview("Dormant — small", as: .systemSmall) {
    GratitudeGardenWidget()
} timeline: {
    GardenEntry(date: .now, snapshot: .preview(growth: .blooming, vitality: .dormant, wiltLevel: 4))
}

#Preview("Thriving — medium", as: .systemMedium) {
    GratitudeGardenWidget()
} timeline: {
    GardenEntry(date: .now, snapshot: .preview(growth: .flourishing, vitality: .thriving))
}

#Preview("Dormant — medium", as: .systemMedium) {
    GratitudeGardenWidget()
} timeline: {
    GardenEntry(date: .now, snapshot: .preview(growth: .blooming, vitality: .dormant, wiltLevel: 4))
}
