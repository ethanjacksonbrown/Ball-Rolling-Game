import Foundation
import SceneKit

/// Lightweight height profiles for hills/ramps/divots — no physics raycasts needed.
final class HeightField {
    struct Band {
        let startZ: Float
        let length: Float
        let minX: Float
        let maxX: Float
        let isDip: Bool
        /// (worldX, t along band 0...1) -> height
        let heightAt: (Float, Float) -> Float
    }

    private var bands: [Band] = []

    func reset() {
        bands.removeAll(keepingCapacity: true)
    }

    func addBand(
        startZ: Float,
        length: Float,
        minX: Float = -1_000,
        maxX: Float = 1_000,
        isDip: Bool = false,
        heightAt: @escaping (Float, Float) -> Float
    ) {
        bands.append(
            Band(
                startZ: startZ,
                length: length,
                minX: minX,
                maxX: maxX,
                isDip: isDip,
                heightAt: heightAt
            )
        )
    }

    /// Convenience for profiles that only vary along Z.
    func addBand(
        startZ: Float,
        length: Float,
        minX: Float = -1_000,
        maxX: Float = 1_000,
        isDip: Bool = false,
        heightAlong: @escaping (Float) -> Float
    ) {
        addBand(startZ: startZ, length: length, minX: minX, maxX: maxX, isDip: isDip) { _, t in
            heightAlong(t)
        }
    }

    func cull(beforeZ z: Float) {
        bands.removeAll { $0.startZ + $0.length < z }
    }

    func height(atX x: Float, z: Float) -> Float {
        var raised: Float = 0
        var dip: Float = 0
        for band in bands {
            guard z >= band.startZ, z <= band.startZ + band.length else { continue }
            guard x >= band.minX, x <= band.maxX else { continue }
            let t = (z - band.startZ) / max(band.length, 0.0001)
            let h = band.heightAt(x, t)
            if band.isDip {
                dip = min(dip, h)
            } else {
                raised = max(raised, h)
            }
        }
        return raised + dip
    }
}

struct ObstacleVolume {
    var x: Float
    var z: Float
    var radius: Float
    var baseY: Float
    var height: Float
    var chunkEndZ: Float
}

final class ObstacleIndex {
    private var obstacles: [ObstacleVolume] = []

    func reset() {
        obstacles.removeAll(keepingCapacity: true)
    }

    func add(_ obstacle: ObstacleVolume) {
        obstacles.append(obstacle)
    }

    func cull(beforeZ z: Float) {
        obstacles.removeAll { $0.chunkEndZ < z }
    }

    /// True if a new prop at (x, z) would sit inside / too close to an existing obstacle.
    func isNear(x: Float, z: Float, minSeparation: Float = 2.0) -> Bool {
        for o in obstacles {
            let needed = max(minSeparation, o.radius + 1.0)
            let dx = x - o.x
            let dz = z - o.z
            if dx * dx + dz * dz < needed * needed {
                return true
            }
        }
        return false
    }

    func intersectsBall(x: Float, y: Float, z: Float, ballRadius: Float) -> Bool {
        deepestContact(x: x, y: y, z: z, ballRadius: ballRadius) != nil
    }

    /// Deepest horizontal overlap with a solid prop (tree/rock). Used to bounce racers out.
    func deepestContact(x: Float, y: Float, z: Float, ballRadius: Float) -> ObstacleContact? {
        let ballBottom = y - ballRadius
        let ballTop = y + ballRadius
        var best: ObstacleContact?

        for o in obstacles {
            let dx = x - o.x
            let dz = z - o.z
            let minDist = o.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < o.baseY + o.height && ballTop > o.baseY else { continue }

            let dist = max(0.0001, sqrt(distSq))
            let overlap = minDist - dist + 0.04
            if overlap > (best?.overlap ?? 0) {
                best = ObstacleContact(
                    normalX: dx / dist,
                    normalZ: dz / dist,
                    overlap: overlap
                )
            }
        }
        return best
    }
}

struct ObstacleContact {
    var normalX: Float
    var normalZ: Float
    var overlap: Float
}

struct GeyserVolume {
    var x: Float
    var z: Float
    var baseY: Float
    var radius: Float
    var jetHeight: Float
    var chunkEndZ: Float
    var cycleDuration: Float
    var eruptDuration: Float
    var phaseOffset: Float
    weak var jetNode: SCNNode?
    weak var sprayNode: SCNNode?
    weak var glowNode: SCNNode?
}

final class GeyserIndex {
    private var geysers: [GeyserVolume] = []

    func reset() {
        geysers.removeAll(keepingCapacity: true)
    }

    func add(_ geyser: GeyserVolume) {
        geysers.append(geyser)
    }

    func cull(beforeZ z: Float) {
        geysers.removeAll { $0.chunkEndZ < z }
    }

    func updateVisuals(atTime time: Float) {
        for g in geysers {
            let intensity = eruptIntensity(g, time: time)
            // Grow a straight pillar upward from the vent (XZ stays full width).
            let yScale = max(0.04, intensity)
            g.jetNode?.scale = SCNVector3(1, yScale, 1)
            g.jetNode?.opacity = CGFloat(0.15 + 0.85 * intensity)
            // Keep the jet anchored at the vent while height scales.
            if let jet = g.jetNode {
                jet.position.y = g.jetHeight * 0.5 * yScale
            }

            let bubblePulse = 0.9 + 0.18 * sin(time * 9.0 + g.phaseOffset)
            let sprayScale = (0.35 + 0.95 * intensity) * bubblePulse
            g.sprayNode?.scale = SCNVector3(sprayScale, sprayScale * 0.95, sprayScale)
            g.sprayNode?.opacity = CGFloat(0.05 + 0.95 * intensity)
            g.sprayNode?.position.y = g.jetHeight * yScale
            g.glowNode?.opacity = CGFloat(0.4 + 0.6 * intensity)

            // Individual bubbles jiggle while erupting.
            if intensity > 0.2, let spray = g.sprayNode {
                var i = 0
                for child in spray.childNodes where child.name == "geyserBubble" {
                    let wobble = 0.85 + 0.2 * sin(time * (7.0 + Float(i) * 1.3) + g.phaseOffset + Float(i))
                    child.scale = SCNVector3(wobble, wobble, wobble)
                    i += 1
                }
            }
        }
    }

    /// Returns launch impulse if the ball is on an erupting geyser vent.
    func launchImpulse(
        atX x: Float,
        y: Float,
        z: Float,
        ballRadius: Float,
        time: Float
    ) -> Float? {
        for g in geysers {
            guard isErupting(g, time: time) else { continue }
            let dx = x - g.x
            let dz = z - g.z
            let hitR = g.radius + ballRadius
            guard dx * dx + dz * dz <= hitR * hitR else { continue }
            // Must be near the vent / low in the column (not already sky-high).
            let ballBottom = y - ballRadius
            guard ballBottom < g.baseY + g.jetHeight * 0.55 else { continue }
            guard ballBottom > g.baseY - 0.4 else { continue }
            return 18 + g.jetHeight * 2.2
        }
        return nil
    }

    private func isErupting(_ g: GeyserVolume, time: Float) -> Bool {
        eruptIntensity(g, time: time) > 0.35
    }

    private func eruptIntensity(_ g: GeyserVolume, time: Float) -> Float {
        let cycle = max(g.cycleDuration, 0.1)
        var t = (time + g.phaseOffset).truncatingRemainder(dividingBy: cycle)
        if t < 0 { t += cycle }
        let erupt = g.eruptDuration
        guard t < erupt else { return 0 }
        let rise: Float = 0.45
        let fall: Float = 0.55
        if t < rise {
            return t / rise
        }
        if t > erupt - fall {
            return max(0, (erupt - t) / fall)
        }
        return 1
    }
}

struct SlowZone {
    var minX: Float
    var maxX: Float
    var startZ: Float
    var endZ: Float
    var speedScale: Float
    var chunkEndZ: Float
}

final class SlowZoneIndex {
    private var zones: [SlowZone] = []

    func reset() {
        zones.removeAll(keepingCapacity: true)
    }

    func add(_ zone: SlowZone) {
        zones.append(zone)
    }

    func cull(beforeZ z: Float) {
        zones.removeAll { $0.chunkEndZ < z }
    }

    func speedScale(atX x: Float, z: Float) -> Float {
        var slowest: Float = 1
        var fastest: Float = 1
        for zone in zones {
            guard z >= zone.startZ, z <= zone.endZ else { continue }
            guard x >= zone.minX, x <= zone.maxX else { continue }
            // Don't multiply overlapping ponds (that could stall the ball).
            if zone.speedScale < 1 {
                slowest = min(slowest, zone.speedScale)
            } else if zone.speedScale > 1 {
                fastest = max(fastest, zone.speedScale)
            }
        }
        if fastest > 1 { return fastest }
        return slowest
    }

    func contains(x: Float, z: Float) -> Bool {
        for zone in zones {
            guard z >= zone.startZ, z <= zone.endZ else { continue }
            guard x >= zone.minX, x <= zone.maxX else { continue }
            return true
        }
        return false
    }
}
