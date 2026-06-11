import SwiftUI

// `GardenSnapshot.preview(...)` lives in GardenSnapshot+Preview.swift (plain Foundation) so both
// targets and headless tests can use it.

/// A labelled tile, used by the gallery.
private struct GardenTile: View {
    let title: String
    let snapshot: GardenSnapshot
    var animated: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            GardenSceneView(snapshot: snapshot, animated: animated)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// The full gallery — every state at a glance.
struct GardenGalleryView: View {
    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                GardenTile(title: "Thriving · Bloom", snapshot: .preview(growth: .blooming))
                GardenTile(title: "Thriving · Flourishing", snapshot: .preview(growth: .flourishing))
                GardenTile(title: "Thriving · Sprout", snapshot: .preview(growth: .sprout, totalEntries: 1))
                GardenTile(title: "Drooping · 1", snapshot: .preview(vitality: .drooping, wiltLevel: 1))
                GardenTile(title: "Drooping · 2", snapshot: .preview(vitality: .drooping, wiltLevel: 2))
                GardenTile(title: "Drooping · 3", snapshot: .preview(vitality: .drooping, wiltLevel: 3))
                GardenTile(title: "Dormant", snapshot: .preview(vitality: .dormant, wiltLevel: 4))
                GardenTile(title: "Reviving", snapshot: .preview(isReviving: true))
            }
            .padding()
        }
    }
}

// MARK: - Previews (Xcode canvas)

#Preview("Garden Gallery") {
    GardenGalleryView()
}

#Preview("Thriving") {
    GardenSceneView(snapshot: .preview(growth: .flourishing))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Drooping (level 2)") {
    GardenSceneView(snapshot: .preview(vitality: .drooping, wiltLevel: 2))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Dormant") {
    GardenSceneView(snapshot: .preview(vitality: .dormant, wiltLevel: 4))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Reviving (welcome back)") {
    GardenSceneView(snapshot: .preview(isReviving: true))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Growth stages") {
    HStack(spacing: 8) {
        ForEach(GrowthStage.allCases, id: \.rawValue) { stage in
            GardenSceneView(snapshot: .preview(growth: stage), animated: false)
                .aspectRatio(0.7, contentMode: .fit)
        }
    }
    .padding()
}
