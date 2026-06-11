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
}

@MainActor
final class SystemSoundPlayer: SoundPlaying {
    #if canImport(AVFoundation)
    private var players: [String: AVAudioPlayer] = [:]
    #endif

    func play(_ event: GardenSoundEvent) {
        #if canImport(AVFoundation)
        guard let url = Bundle.main.url(forResource: event.rawValue, withExtension: "caf")
            ?? Bundle.main.url(forResource: event.rawValue, withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.4
            player.prepareToPlay()
            player.play()
            players[event.rawValue] = player   // retain until it finishes
        } catch {
            // No audio session / missing asset → stay silent. Sound is a nicety, never required.
        }
        #endif
    }
}

@MainActor
struct NoSound: SoundPlaying {
    func play(_ event: GardenSoundEvent) {}
}
