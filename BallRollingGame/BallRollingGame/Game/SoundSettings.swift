import Foundation

/// Persisted SFX and music levels (each 0…1), independent of each other.
enum SoundSettings {
    private static let sfxKey = "sfxVolume"
    private static let musicKey = "musicVolume"

    /// Coin pickups, roulette ticks, and other effects. Defaults to 100%.
    static var masterVolume: Float {
        get {
            guard UserDefaults.standard.object(forKey: sfxKey) != nil else { return 1 }
            return max(0, min(1, UserDefaults.standard.float(forKey: sfxKey)))
        }
        set {
            UserDefaults.standard.set(max(0, min(1, newValue)), forKey: sfxKey)
        }
    }

    /// Background theme music. Defaults to 100%. Independent of SFX.
    static var musicVolume: Float {
        get {
            guard UserDefaults.standard.object(forKey: musicKey) != nil else { return 1 }
            return max(0, min(1, UserDefaults.standard.float(forKey: musicKey)))
        }
        set {
            UserDefaults.standard.set(max(0, min(1, newValue)), forKey: musicKey)
        }
    }

    /// Scales a per-effect gain by the SFX slider.
    static func scaled(_ gain: Float) -> Float {
        max(0, min(1, gain * masterVolume))
    }
}
