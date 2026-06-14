import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Optional, gentle sound. **Off by default**, fully user-controllable (see Settings). Plays only on
/// save and revival, and only if both the preference is on *and* a sound file is bundled — so it
/// degrades silently when no audio assets ship. Drop `entry.caf` / `revival.caf` into the app bundle
/// to enable real sound without touching this code.
enum GardenSoundEvent: String {
    case entry
    case revival
}

@MainActor
protocol SoundPlaying {
    func play(_ event: GardenSoundEvent)
    /// A soft, optional companion sound (purr / bark / baa…). No-op unless a matching asset ships.
    func playPet(_ type: PetType)
}

@MainActor
final class SystemSoundPlayer: SoundPlaying {
    #if canImport(AVFoundation)
    private var players: [String: AVAudioPlayer] = [:]
    #endif

    func play(_ event: GardenSoundEvent) { playNamed(event.rawValue, volume: 0.4) }

    /// Looks for `pet_cat.caf`/`pet_dog.caf`… in the bundle. Until those ship, it's silent — so the
    /// pet works with or without sound, always honoring the user's Sound toggle (checked by the caller).
    func playPet(_ type: PetType) { playNamed("pet_\(type.rawValue)", volume: 0.3) }

    private func playNamed(_ name: String, volume: Float) {
        #if canImport(AVFoundation)
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf")
            ?? Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.prepareToPlay()
            player.play()
            players[name] = player   // retain until it finishes
        } catch {
            // No audio session / missing asset → stay silent. Sound is a nicety, never required.
        }
        #endif
    }
}

@MainActor
struct NoSound: SoundPlaying {
    func play(_ event: GardenSoundEvent) {}
    func playPet(_ type: PetType) {}
}
