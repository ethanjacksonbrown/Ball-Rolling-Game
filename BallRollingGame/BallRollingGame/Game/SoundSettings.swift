import Foundation

/// Master volume for all in-game sound effects (0…1), persisted across launches.
enum SoundSettings {
    private static let key = "sfxVolume"

    /// 0 = muted, 1 = full. Defaults to 100% when never set.
    static var masterVolume: Float {
        get {
            guard UserDefaults.standard.object(forKey: key) != nil else { return 1 }
            return max(0, min(1, UserDefaults.standard.float(forKey: key)))
        }
        set {
            UserDefaults.standard.set(max(0, min(1, newValue)), forKey: key)
        }
    }

    /// Scales a per-effect gain by the master slider.
    static func scaled(_ gain: Float) -> Float {
        max(0, min(1, gain * masterVolume))
    }
}
