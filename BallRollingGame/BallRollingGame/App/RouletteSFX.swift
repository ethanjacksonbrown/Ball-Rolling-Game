import AVFoundation
import Foundation

/// Decelerating click track for the biome roulette spin.
final class RouletteSFX {
    static let shared = RouletteSFX()

    private var pool: [AVAudioPlayer] = []
    private var poolIndex = 0
    private var workItems: [DispatchWorkItem] = []
    private var didConfigureSession = false

    private init() {
        prepare()
    }

    func prepare() {
        configureSessionIfNeeded()
        guard pool.isEmpty else { return }
        guard let url = Bundle.main.url(forResource: "roulette_tick", withExtension: "wav") else {
            assertionFailure("Missing roulette_tick.wav in app bundle")
            return
        }
        do {
            // Several players so fast early ticks can overlap cleanly.
            for _ in 0..<4 {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                player.volume = 0.7
                pool.append(player)
            }
        } catch {
            assertionFailure("Failed to load roulette tick: \(error)")
        }
    }

    /// Plays ticks that start fast and slow down over `duration` seconds.
    func playSpin(duration: TimeInterval = 5.0) {
        stop()
        prepare()
        guard !pool.isEmpty else { return }

        var t: TimeInterval = 0.02
        while t < duration - 0.04 {
            let progress = min(1, t / duration)
            // Match the visual ease-out: dense early, sparse near the end.
            let interval = 0.05 + pow(progress, 1.75) * 0.32
            scheduleTick(after: t, volume: 0.55 + Float(progress) * 0.25)
            t += interval
        }
        // Final confirmatory click when the reel lands.
        scheduleTick(after: duration, volume: 1.0)
    }

    func stop() {
        workItems.forEach { $0.cancel() }
        workItems.removeAll()
        for player in pool {
            player.stop()
            player.currentTime = 0
        }
    }

    private func scheduleTick(after delay: TimeInterval, volume: Float) {
        let item = DispatchWorkItem { [weak self] in
            self?.playTick(volume: volume)
        }
        workItems.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func playTick(volume: Float) {
        guard !pool.isEmpty else { return }
        let player = pool[poolIndex]
        poolIndex = (poolIndex + 1) % pool.count
        player.volume = volume
        player.currentTime = 0
        player.play()
    }

    private func configureSessionIfNeeded() {
        guard !didConfigureSession else { return }
        didConfigureSession = true
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal — ticks simply won't play if audio session fails.
        }
    }
}
