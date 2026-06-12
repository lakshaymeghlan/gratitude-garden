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

/// The full gallery — the world growing, plus each vitality state.
struct GardenGalleryView: View {
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    // Representative entry counts for each world stage 0...6.
    private let stageEntries = [1, 5, 12, 24, 45, 80, 140]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Array(stageEntries.enumerated()), id: \.offset) { index, entries in
                    GardenTile(title: "Stage \(index) · \(entries) entries",
                               snapshot: .preview(totalEntries: entries))
                }
                GardenTile(title: "Drooping", snapshot: .preview(vitality: .drooping, wiltLevel: 2, totalEntries: 80))
                GardenTile(title: "Dormant", snapshot: .preview(vitality: .dormant, wiltLevel: 4, totalEntries: 80))
                GardenTile(title: "Reviving", snapshot: .preview(isReviving: true, totalEntries: 80))
            }
            .padding()
        }
    }
}

// MARK: - Previews (Xcode canvas)

#Preview("World Gallery") {
    GardenGalleryView()
}

#Preview("Stage 0 · bare meadow") {
    GardenSceneView(snapshot: .preview(totalEntries: 1))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Stage 6 · magical") {
    GardenSceneView(snapshot: .preview(totalEntries: 140))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Drooping") {
    GardenSceneView(snapshot: .preview(vitality: .drooping, wiltLevel: 2, totalEntries: 80))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Dormant (still beautiful)") {
    GardenSceneView(snapshot: .preview(vitality: .dormant, wiltLevel: 4, totalEntries: 80))
        .aspectRatio(0.9, contentMode: .fit).padding()
}

#Preview("Reviving (welcome back)") {
    GardenSceneView(snapshot: .preview(isReviving: true, totalEntries: 80))
        .aspectRatio(0.9, contentMode: .fit).padding()
}
