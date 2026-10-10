import Foundation

/// Result of a successful power-up activation (for one-shot side effects like Slow Pulse).
struct PowerUpActivation: Equatable {
    let type: PowerUpType
    let stats: PowerUpStats
}

/// Per-racer power-up cooldown / active buff state for one race.
final class PowerUpRuntime {
    private(set) var type: PowerUpType?
    private(set) var level: Int = 0
    private(set) var cooldownRemaining: Float = 0
    private(set) var effectRemaining: Float = 0

    /// Slow Pulse sources applied to this racer: (remaining, multiplier).
    private var incomingSlows: [(remaining: Float, multiplier: Float)] = []

    var hasPowerUp: Bool { type != nil && level >= 1 }

    /// Ready to fire: owned, cooled down, and not mid-effect.
    var isReady: Bool {
        hasPowerUp && cooldownRemaining <= 0 && effectRemaining <= 0
    }

    var isEffectActive: Bool {
        effectRemaining > 0
    }

    var isGhost: Bool {
        type == .ghost && effectRemaining > 0
    }

    var isMagnetActive: Bool {
        type == .coinMagnet && effectRemaining > 0
    }

    var isSpeedBoostActive: Bool {
        type == .speedBoost && effectRemaining > 0
    }

    var stats: PowerUpStats? {
        guard let type, level >= 1 else { return nil }
        return type.stats(level: level)
    }

    func configure(type: PowerUpType?, level: Int) {
        self.type = type
        self.level = type == nil ? 0 : max(0, min(PowerUpStats.maxLevel, level))
        reset()
    }

    func reset() {
        cooldownRemaining = 0
        effectRemaining = 0
        incomingSlows.removeAll()
    }

    @discardableResult
    func tryActivate() -> PowerUpActivation? {
        guard isReady, let type, let stats else { return nil }
        effectRemaining = stats.duration
        cooldownRemaining = stats.cooldown
        return PowerUpActivation(type: type, stats: stats)
    }

    /// - Parameter isAirborne: Incoming slows pause in the air so jumps keep momentum.
    func tick(_ deltaTime: Float, isAirborne: Bool = false) {
        if cooldownRemaining > 0 {
            cooldownRemaining = max(0, cooldownRemaining - deltaTime)
        }
        if effectRemaining > 0 {
            effectRemaining = max(0, effectRemaining - deltaTime)
        }
        // Hold Slow Pulse time while airborne — duration spends on the ground.
        guard !isAirborne else { return }
        for i in incomingSlows.indices.reversed() {
            incomingSlows[i].remaining -= deltaTime
            if incomingSlows[i].remaining <= 0 {
                incomingSlows.remove(at: i)
            }
        }
    }

    /// Speed scale contribution from own Speed Boost and incoming Slow Pulses.
    /// Slow Pulse does not affect forward speed while airborne.
    func movementSpeedMultiplier(isAirborne: Bool = false) -> Float {
        var scale: Float = 1
        if isSpeedBoostActive, let stats {
            scale *= stats.speedMultiplier
        }
        if !isAirborne {
            for slow in incomingSlows {
                scale *= slow.multiplier
            }
        }
        return scale
    }

    func magnetReach() -> Float {
        guard isMagnetActive, let stats else { return 0 }
        return stats.magnetReach
    }

    func applyIncomingSlow(multiplier: Float, duration: Float) {
        incomingSlows.append((remaining: duration, multiplier: multiplier))
    }
}
