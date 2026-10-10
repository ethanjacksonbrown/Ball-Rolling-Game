import AVFoundation
import Foundation

/// Loops the Song Maker theme.
/// Menu / non-race states play at 90 BPM; active racing plays at 150 BPM.
final class GameMusic {
    static let shared = GameMusic()

    private let baseBPM: Double = 90
    private let menuBPM: Double = 90
    private let raceBPM: Double = 150

    private var player: AVAudioPlayer?
    private var wantsPlaying = false
    private var isRacing = false
    private var didConfigureSession = false

    private init() {
        prepare()
    }

    func prepare() {
        configureSessionIfNeeded()
        guard player == nil else { return }
        guard let url = Bundle.main.url(forResource: "biome_theme", withExtension: "wav") else {
            assertionFailure("Missing biome_theme.wav in app bundle")
            return
        }
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.numberOfLoops = -1 // seamless native loop — no end gap
            audio.enableRate = true
            audio.prepareToPlay()
            player = audio
            applyRate()
            applyVolume()
        } catch {
            assertionFailure("Failed to load theme audio: \(error)")
        }
    }

    /// Start looping (menu on launch, return from mute, etc.).
    func start() {
        wantsPlaying = true
        ensurePlaying()
    }

    func stop() {
        wantsPlaying = false
        player?.stop()
    }

    /// `true` only while a race is actively running (not pause / finish / menus).
    func setRacing(_ racing: Bool) {
        isRacing = racing
        applyRate()
    }

    /// Re-check music volume after Settings changes.
    func refreshFromSettings() {
        applyVolume()
        if SoundSettings.musicVolume <= 0.001 {
            player?.pause()
        } else if wantsPlaying {
            ensurePlaying()
        }
    }

    private func applyRate() {
        let bpm = isRacing ? raceBPM : menuBPM
        // WAV was rendered at baseBPM; rate scales wall-clock tempo.
        player?.rate = Float(bpm / baseBPM)
    }

    private func applyVolume() {
        player?.volume = max(0, min(1, SoundSettings.musicVolume))
    }

    private func ensurePlaying() {
        prepare()
        guard wantsPlaying else { return }
        guard SoundSettings.musicVolume > 0.001 else { return }
        guard let player else { return }
        applyRate()
        applyVolume()
        if !player.isPlaying {
            player.play()
        }
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal — theme simply won't play if audio session fails.
        }
    }
}
