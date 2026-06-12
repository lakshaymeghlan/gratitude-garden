import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Supplies the handcrafted background artwork for a world stage. The renderer depends only on this
/// protocol, so an artist's assets — or a future remote/bundled set — slot in without touching the
/// scene/animation code. Returning `nil` lets the renderer fall back to the procedural landscape, so
/// the app keeps working before any art exists.
protocol GardenWorldArt {
    func image(for stage: WorldStage) -> Image?
}

/// Loads `world_0`…`world_6` from an asset catalog (`WorldArt.xcassets`). Until those imagesets
/// contain real images it returns `nil` (the size guard treats an empty slot as absent), so the
/// scene shows the procedural fallback. Drop art into the matching imageset and it appears — no code
/// change. The catalog is a member of both the app and widget targets, so both render the same art.
struct AssetWorldArt: GardenWorldArt {
    func image(for stage: WorldStage) -> Image? {
        let name = "world_\(stage.rawValue)"
        #if canImport(UIKit)
        if let ui = UIImage(named: name), ui.size.width > 0 { return Image(uiImage: ui) }
        #elseif canImport(AppKit)
        if let ns = NSImage(named: name), ns.size.width > 0 { return Image(nsImage: ns) }
        #endif
        return nil
    }
}
