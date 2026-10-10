import AVFoundation
import Foundation

/// Short pickup blip when the player collects a coin.
final class CoinSFX {
    static let shared = CoinSFX()

    private var pool: [AVAudioPlayer] = []
    private var poolIndex = 0
    private var didConfigureSession = false

    private init() {
        prepare()
    }

    func prepare() {
        configureSessionIfNeeded()
        guard pool.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "coin_pickup", withExtension: "wav") else {
            assertionFailure("Missing coin_pickup.wav in app bundle")
            return
        }
        do {
            // Pool so rapid multi-coin pickups (magnet) can overlap.
            for _ in 0..<6 {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                player.volume = 0.75
                pool.append(player)
            }
        } catch {
            assertionFailure("Failed to load coin pickup: \(error)")
        }
    }

    /// Plays one pickup blip. Safe to call for each coin collected in a frame.
    func play(count: Int = 1) {
        prepare()
        guard !pool.isEmpty, count > 0 else { return }
        // Cap stacked plays so a magnet vacuum doesn't blast the speaker.
        let plays = min(count, 4)
        for i in 0..<plays {
            let player = pool[poolIndex]
            poolIndex = (poolIndex + 1) % pool.count
            player.volume = SoundSettings.scaled(0.55 + 0.08 * Float(i))
            player.currentTime = 0
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
            // Non-fatal — pickups simply won't play if audio session fails.
        }
    }
}
