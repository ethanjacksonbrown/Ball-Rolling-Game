import Foundation

/// Bot steering with a preferred corridor and calmer, closer-range dodges.
final class BotBrain {
    /// 0.65…0.995 — higher means cleaner lane picks and faster reactions.
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
    /// How urgently we need to leave the current line (nearby blockage).
    private var dodgeUrgency: Float = 0

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
        thinkTimer = Float.random(in: 0.08...0.2)
        heldLateral = 0
        targetX = startX
        dodgeUrgency = 0
    }

    func desiredLateral(
        positionX: Float,
        positionZ: Float,
        deltaTime: Float,
        trackHalfWidth: Float,
        ballRadius: Float,
        obstacles: ObstacleIndex,
        ignoreObstacles: Bool = false
    ) -> Float {
        let maxX = trackHalfWidth - ballRadius - 0.35
        let corridor = idealCorridorX(atZ: positionZ, maxX: maxX)

        thinkTimer -= deltaTime
        if thinkTimer <= 0 {
            if ignoreObstacles {
                // Ghost: commit to the natural racing line — no swerving for solids.
                targetX = corridor
                dodgeUrgency = 0
                thinkTimer = Float.random(in: 0.18...0.32)
            } else {
                let plan = chooseLane(
                    positionX: positionX,
                    positionZ: positionZ,
                    maxX: maxX,
                    corridor: corridor,
                    ballRadius: ballRadius,
                    obstacles: obstacles
                )
                targetX = plan.targetX
                dodgeUrgency = plan.urgency
                // Clear road → rethink slowly. Immediate threat → rethink sooner.
                let clearThink = Float.random(in: 0.16...0.28)
                let panicThink = Float.random(in: 0.07...0.12)
                thinkTimer = clearThink - (clearThink - panicThink) * dodgeUrgency
                thinkTimer *= 1.05 - skill * 0.15
            }
        } else if ignoreObstacles {
            // Keep tracking the weaving corridor between rethinks.
            targetX = corridor
            dodgeUrgency = 0
        }

        let error = targetX - positionX
        // Soft proportional steer; urgency only tightens response a little.
        let gain = 0.28 + skill * 0.18 + dodgeUrgency * 0.22
        let desired = max(-1, min(1, error * gain))

        // Gentle blend so lane changes don't look twitchy.
        let blend = min(1, deltaTime * (5.5 + skill * 3.5 + dodgeUrgency * 4))
        heldLateral += (desired - heldLateral) * blend
        // Soft deadzone — tiny corrections read as jitter.
        if abs(heldLateral) < 0.04, dodgeUrgency < 0.25 {
            heldLateral *= 0.85
        }
        return heldLateral
    }

    private func idealCorridorX(atZ z: Float, maxX: Float) -> Float {
        let weave = sin(z * weaveFrequency + weavePhase) * weaveAmplitude
        return max(-maxX, min(maxX, preferredX + weave))
    }

    private func chooseLane(
        positionX: Float,
        positionZ: Float,
        maxX: Float,
        corridor: Float,
        ballRadius: Float,
        obstacles: ObstacleIndex
    ) -> (targetX: Float, urgency: Float) {
        // Nearby threats drive dodging; far ones only bias the path lightly.
        let nearLooks: [Float] = [3, 6, 10, 14]
        let farLooks: [Float] = [20, 28]

        let blockedNear = nearestBlockDistance(
            x: positionX,
            z: positionZ,
            ballRadius: ballRadius,
            obstacles: obstacles,
            looks: nearLooks
        )
        let urgency: Float
        if let blockedNear {
            urgency = max(0, min(1, 1.15 - blockedNear / 14))
        } else {
            urgency = 0
        }

        // Mostly stay on the racing line unless something is actually close.
        if urgency < 0.2 {
            var stay = corridor
            // Mild far-ahead bias: ease a half-lane if the corridor itself is clogged later.
            if laneBlocked(
                x: corridor,
                z: positionZ,
                ballRadius: ballRadius,
                obstacles: obstacles,
                looks: farLooks,
                pad: 0.35
            ) {
                let left = min(maxX, corridor + 3.5)
                let right = max(-maxX, corridor - 3.5)
                let leftClear = !laneBlocked(
                    x: left, z: positionZ, ballRadius: ballRadius, obstacles: obstacles, looks: farLooks, pad: 0.25
                )
                let rightClear = !laneBlocked(
                    x: right, z: positionZ, ballRadius: ballRadius, obstacles: obstacles, looks: farLooks, pad: 0.25
                )
                if leftClear && (!rightClear || abs(left - positionX) <= abs(right - positionX)) {
                    stay = corridor + (left - corridor) * 0.45
                } else if rightClear {
                    stay = corridor + (right - corridor) * 0.45
                }
            }
            return (stay, 0)
        }

        // Evaluate a few nearby offsets instead of the whole track grid.
        var candidates: [Float] = [corridor, positionX]
        for delta in [-7, -4.5, -2.5, 2.5, 4.5, 7] as [Float] {
            candidates.append(max(-maxX, min(maxX, positionX + delta)))
            candidates.append(max(-maxX, min(maxX, corridor + delta)))
        }
        // Dedupe
        var unique: [Float] = []
        for c in candidates {
            if !unique.contains(where: { abs($0 - c) < 0.4 }) {
                unique.append(c)
            }
        }

        var bestX = corridor
        var bestScore: Float = -1_000

        for laneX in unique {
            var score: Float = 0
            // Prefer the racing line and small moves over big swerves.
            score -= abs(laneX - corridor) * (0.08 + corridorPull)
            score -= abs(laneX - positionX) * (0.12 + (1 - urgency) * 0.1)

            for ahead in nearLooks {
                let closeness = 1 - ahead / 16
                let weight = (10 + skill * 8) * closeness
                if obstacles.intersectsBall(
                    x: laneX,
                    y: 1.0,
                    z: positionZ + ahead,
                    ballRadius: ballRadius + 0.15
                ) {
                    score -= weight * 1.35
                } else if obstacles.intersectsBall(
                    x: laneX,
                    y: 1.0,
                    z: positionZ + ahead,
                    ballRadius: ballRadius + 0.55
                ) {
                    score -= weight * 0.35
                }
            }

            if score > bestScore {
                bestScore = score
                bestX = laneX
            }
        }

        // Occasional small mistakes so bots don't look perfect.
        let mistakeChance = max(0.01, 0.1 - skill * 0.08)
        if Float.random(in: 0...1) < mistakeChance {
            bestX = max(-maxX, min(maxX, bestX + Float.random(in: -1.0...1.0)))
        }

        return (bestX, urgency)
    }

    private func nearestBlockDistance(
        x: Float,
        z: Float,
        ballRadius: Float,
        obstacles: ObstacleIndex,
        looks: [Float]
    ) -> Float? {
        for ahead in looks {
            if obstacles.intersectsBall(
                x: x,
                y: 1.0,
                z: z + ahead,
                ballRadius: ballRadius + 0.25
            ) {
                return ahead
            }
        }
        return nil
    }

    private func laneBlocked(
        x: Float,
        z: Float,
        ballRadius: Float,
        obstacles: ObstacleIndex,
        looks: [Float],
        pad: Float
    ) -> Bool {
        for ahead in looks {
            if obstacles.intersectsBall(
                x: x,
                y: 1.0,
                z: z + ahead,
                ballRadius: ballRadius + pad
            ) {
                return true
            }
        }
        return false
    }
}
