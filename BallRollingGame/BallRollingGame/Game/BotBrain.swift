import Foundation

/// Strong bot steering with a preferred corridor so racers spread across the track.
final class BotBrain {
    /// 0.92…0.995 — higher means cleaner lane picks and faster reactions.
    let skill: Float
    /// Preferred lane center across the track (−maxX…maxX).
    private var preferredX: Float = 0
    /// Soft weave so paths stay distinct without hugging one X forever.
    private let weaveAmplitude: Float
    private let weaveFrequency: Float
    private let weavePhase: Float
    /// How strongly the bot sticks to its corridor (higher = less clumping).
    private let corridorPull: Float

    private var thinkTimer: Float = 0
    private var heldLateral: Float = 0
    private var targetX: Float = 0

    init(
        skill: Float,
        weaveAmplitude: Float = 2.0,
        weaveFrequency: Float = 0.03,
        weavePhase: Float = 0,
        corridorPull: Float = 0.1
    ) {
        self.skill = min(0.995, max(0.65, skill))
        self.weaveAmplitude = weaveAmplitude
        self.weaveFrequency = weaveFrequency
        self.weavePhase = weavePhase
        self.corridorPull = corridorPull
    }

    func reset(startX: Float, preferredX: Float) {
        self.preferredX = preferredX
        thinkTimer = Float.random(in: 0.01...0.05)
        heldLateral = 0
        targetX = startX
    }

    func desiredLateral(
        positionX: Float,
        positionZ: Float,
        deltaTime: Float,
        trackHalfWidth: Float,
        ballRadius: Float,
        obstacles: ObstacleIndex
    ) -> Float {
        thinkTimer -= deltaTime
        if thinkTimer <= 0 {
            // Very frequent rethinks so bots dodge early.
            thinkTimer = Float.random(in: 0.03...0.07) * (1.05 - skill * 0.2)
            targetX = chooseLane(
                positionX: positionX,
                positionZ: positionZ,
                trackHalfWidth: trackHalfWidth,
                ballRadius: ballRadius,
                obstacles: obstacles
            )
        }

        let error = targetX - positionX
        let desired = max(-1, min(1, error * (0.55 + skill * 0.35)))
        heldLateral += (desired - heldLateral) * min(1, deltaTime * (16 + skill * 10))
        return heldLateral
    }

    private func idealCorridorX(atZ z: Float, maxX: Float) -> Float {
        let weave = sin(z * weaveFrequency + weavePhase) * weaveAmplitude
        return max(-maxX, min(maxX, preferredX + weave))
    }

    private func chooseLane(
        positionX: Float,
        positionZ: Float,
        trackHalfWidth: Float,
        ballRadius: Float,
        obstacles: ObstacleIndex
    ) -> Float {
        let maxX = trackHalfWidth - ballRadius - 0.35
        let corridor = idealCorridorX(atZ: positionZ, maxX: maxX)
        var bestX = positionX
        var bestScore: Float = -1_000

        var lanes: [Float] = []
        var x = -maxX
        while x <= maxX + 0.01 {
            lanes.append(x)
            x += 1.25
        }
        for extra in [positionX, corridor] {
            if !lanes.contains(where: { abs($0 - extra) < 0.05 }) {
                lanes.append(extra)
            }
        }
        if lanes.isEmpty { lanes = [0] }

        let lookAheads: [Float] = [2.5, 5, 8, 12, 16, 21, 27, 34]
        for laneX in lanes {
            var score: Float = 0
            score -= abs(laneX - positionX) * 0.025
            // Light corridor preference — dodging obstacles wins over path style.
            score -= abs(laneX - corridor) * corridorPull

            for ahead in lookAheads {
                let weight = (38 - ahead) * (1.05 + skill * 0.55)
                if obstacles.intersectsBall(
                    x: laneX,
                    y: 1.0,
                    z: positionZ + ahead,
                    ballRadius: ballRadius + 0.2
                ) {
                    score -= weight
                }
                if obstacles.intersectsBall(
                    x: laneX,
                    y: 1.0,
                    z: positionZ + ahead,
                    ballRadius: ballRadius + 0.7
                ) {
                    score -= weight * 0.28
                }
            }

            if score > bestScore {
                bestScore = score
                bestX = laneX
            }
        }

        // Rare, tiny mistakes — still beatable, but much cleaner.
        let mistakeChance = max(0.008, 0.12 - skill * 0.1)
        if Float.random(in: 0...1) < mistakeChance {
            let jitter = Float.random(in: -1.2...1.2)
            bestX = max(-maxX, min(maxX, bestX + jitter))
        }

        return bestX
    }
}
