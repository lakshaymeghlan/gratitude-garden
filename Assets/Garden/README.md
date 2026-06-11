# Garden art assets

The app ships with **procedural pixel art** drawn in code (`Shared/Rendering/GardenSprites.swift`).
These folders are where **commissioned bitmap art** goes when you're ready, and this file documents
exactly how to swap it in **without changing any rendering code**.

## Folder layout

```
Assets/Garden/
  Seed/         ← GrowthStage.seed
  Sprout/       ← GrowthStage.sprout
  Bud/          ← GrowthStage.budding   (and seedling, if you split it)
  Bloom/        ← GrowthStage.blooming
  Flourishing/  ← GrowthStage.flourishing
```

There are **6** `GrowthStage` cases (`seed, sprout, seedling, budding, blooming, flourishing`); the
folders above cover the visually distinct ones. Add a `Seedling/` folder if you want it to differ
from `Bud`.

## Sprite specs

| Property        | Value |
|-----------------|-------|
| Grid / canvas   | **15 × 20 px** logical (matches the procedural sprites; the plant is anchored bottom-center). |
| Color depth     | PNG, sRGB, transparent background. |
| Palette         | Stick to `Shared/Rendering/GardenPalette.swift` (warm greens, soft yellows, creams, muted browns, gentle floral accents). No neon. |
| Export scale    | Provide **1× (15×20)**. The app integer-scales it at runtime, so 1× stays crisp. Optionally also export @2×/@3× for an asset catalog. |
| Frames          | 1 frame per stage = procedural motion (sway is applied by the renderer). For hand-animated sway, export **N frames** named `…_0`, `…_1`, … and the renderer will cycle them. |
| Naming          | `plant_<stage>_<frame>.png`, e.g. `plant_bloom_0.png`, `plant_bloom_1.png`. |

## Scale factor & crispness

The renderer computes an **integer** scale (`floor`) from the available size and draws pixels as
solid rectangles — never a resampled bitmap — so there is **no blur** at any size. When you supply
real PNGs, draw them with nearest-neighbor (`.interpolation(.none)`) at an integer scale to preserve
the same crispness (see the image-provider skeleton below).

## How to swap in commissioned art (no rendering changes)

1. Add the PNGs to an asset catalog (or these folders) following the naming above.
2. Implement a new `GardenArtProvider` that returns image-backed `GardenDrawable`s:

```swift
struct ImageGardenArtProvider: GardenArtProvider {
    func plantFrames(for stage: GrowthStage) -> [PixelSprite] {
        // If you keep using PixelSprite, you can also generate sprites from indexed PNGs.
        // For true bitmap art, add an `ImageDrawable: GardenDrawable` that draws an Image with
        // .interpolation(.none) at an integer scale, and change the protocol to return [GardenDrawable].
    }
}
```

3. Inject it once at the call sites:
   - App: `GardenSceneView(snapshot:)` → `GardenSceneView(snapshot:, artProvider: ImageGardenArtProvider())`
   - Widget: same.

Because `GardenSceneView` depends only on the `GardenArtProvider` protocol, **nothing else changes** —
animation, layout, vitality/wilt/dormancy/revival, particles, and the widget all keep working.
