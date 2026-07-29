import Foundation
import SceneKit
import UIKit

enum FrogColor: CaseIterable {
    case green
    case orange
    case brown

    var skin: UIColor {
        switch self {
        case .green: return UIColor(red: 0.28, green: 0.62, blue: 0.24, alpha: 1)
        case .orange: return UIColor(red: 0.92, green: 0.48, blue: 0.18, alpha: 1)
        case .brown: return UIColor(red: 0.48, green: 0.32, blue: 0.18, alpha: 1)
        }
    }

    var belly: UIColor {
        switch self {
        case .green: return UIColor(red: 0.78, green: 0.82, blue: 0.42, alpha: 1)
        case .orange: return UIColor(red: 0.96, green: 0.78, blue: 0.42, alpha: 1)
        case .brown: return UIColor(red: 0.78, green: 0.68, blue: 0.48, alpha: 1)
        }
    }
}

final class FrogActor {
    let node: SCNNode
    let radius: Float
    let height: Float
    private let bodyNode: SCNNode
    private let bodyBaseY: Float
    private var phase: Phase
    private var facingY: Float

    private enum Phase {
        case idle(remaining: Float)
        case jumping(elapsed: Float, duration: Float, start: SIMD3<Float>, end: SIMD3<Float>, peak: Float)
        case landing(remaining: Float)
        case fidget(remaining: Float, startX: Float, startZ: Float, endX: Float, endZ: Float, duration: Float)
    }

    init(
        node: SCNNode,
        radius: Float,
        height: Float,
        body: SCNNode,
        bodyBaseY: Float
    ) {
        self.node = node
        self.radius = radius
        self.height = height
        self.bodyNode = body
        self.bodyBaseY = bodyBaseY
        self.facingY = node.eulerAngles.y
        self.phase = .idle(remaining: Float.random(in: 0.35...1.1))
    }

    func update(
        deltaTime: Float,
        heightField: HeightField,
        trackHalfWidth: Float,
        waterSpots: [(x: Float, z: Float, radius: Float)],
        rng: inout some RandomNumberGenerator
    ) {
        // Cap spikes so a hitch can't finish a hop in one frame (looks like a teleport).
        let dt = min(deltaTime, 1.0 / 20.0)

        switch phase {
        case .idle(var remaining):
            remaining -= dt
            bodyNode.position.y = bodyBaseY
            bodyNode.eulerAngles.x = 0
            if remaining <= 0 {
                startJump(
                    heightField: heightField,
                    trackHalfWidth: trackHalfWidth,
                    waterSpots: waterSpots,
                    rng: &rng
                )
            } else {
                phase = .idle(remaining: remaining)
            }

        case .jumping(var elapsed, let duration, let start, let end, let peak):
            elapsed += dt
            let t = min(1, elapsed / max(duration, 0.001))
            let x = start.x + (end.x - start.x) * t
            let z = start.z + (end.z - start.z) * t
            let groundY = heightField.height(atX: x, z: z)
            let arc = 4 * peak * t * (1 - t)
            node.position = SCNVector3(x, groundY + arc, z)

            let stretch = sin(t * Float.pi)
            bodyNode.position.y = bodyBaseY + stretch * 0.04
            bodyNode.eulerAngles.x = -stretch * 0.35

            if t >= 1 {
                node.position = SCNVector3(end.x, heightField.height(atX: end.x, z: end.z), end.z)
                bodyNode.position.y = bodyBaseY
                bodyNode.eulerAngles.x = 0.08
                phase = .landing(remaining: Float.random(in: 0.18...0.4, using: &rng))
            } else {
                phase = .jumping(
                    elapsed: elapsed,
                    duration: duration,
                    start: start,
                    end: end,
                    peak: peak
                )
            }

        case .landing(var remaining):
            remaining -= dt
            let squash = max(0, remaining / 0.35)
            bodyNode.eulerAngles.x = 0.08 * squash
            bodyNode.position.y = bodyBaseY - 0.03 * squash
            if remaining <= 0 {
                bodyNode.eulerAngles.x = 0
                bodyNode.position.y = bodyBaseY
                if Bool.random(using: &rng) {
                    startFidget(trackHalfWidth: trackHalfWidth, rng: &rng)
                } else {
                    phase = .idle(remaining: Float.random(in: 0.45...1.4, using: &rng))
                }
            } else {
                phase = .landing(remaining: remaining)
            }

        case .fidget(var remaining, let startX, let startZ, let endX, let endZ, let duration):
            remaining -= dt
            let t = 1 - max(0, remaining / max(duration, 0.001))
            let x = startX + (endX - startX) * t
            let z = startZ + (endZ - startZ) * t
            let groundY = heightField.height(atX: x, z: z)
            node.position = SCNVector3(x, groundY, z)
            if remaining <= 0 {
                let yaw = atan2(endX - startX, endZ - startZ)
                if hypot(endX - startX, endZ - startZ) > 0.02 {
                    facingY = yaw
                    node.eulerAngles.y = facingY
                }
                phase = .idle(remaining: Float.random(in: 0.25...0.8, using: &rng))
            } else {
                phase = .fidget(
                    remaining: remaining,
                    startX: startX,
                    startZ: startZ,
                    endX: endX,
                    endZ: endZ,
                    duration: duration
                )
            }
        }
    }

    private func startJump(
        heightField: HeightField,
        trackHalfWidth: Float,
        waterSpots: [(x: Float, z: Float, radius: Float)],
        rng: inout some RandomNumberGenerator
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.35
        let minJump: Float = 1.8
        let maxJump: Float = 5.0

        // Only consider ponds close enough for a real hop — distant ones caused teleports.
        let nearbyWater = waterSpots.filter {
            hypot(pos.x - $0.x, pos.z - $0.z) <= maxJump + $0.radius + 1.5
        }

        var endX = pos.x
        var endZ = pos.z
        var found = false

        for _ in 0..<16 {
            let candidateX: Float
            let candidateZ: Float

            if let spot = nearbyWater.randomElement(using: &rng),
               Float.random(in: 0...1, using: &rng) < 0.55 {
                let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
                let rim = spot.radius * Float.random(in: 0.7...1.15, using: &rng)
                candidateX = max(-maxX, min(maxX, spot.x + cos(angle) * rim))
                candidateZ = spot.z + sin(angle) * rim
            } else {
                let dist = Float.random(in: minJump...maxJump, using: &rng)
                let angle = facingY + Float.random(in: -0.7...0.7, using: &rng)
                candidateX = max(-maxX, min(maxX, pos.x + sin(angle) * dist))
                candidateZ = pos.z + cos(angle) * dist
            }

            let dist = hypot(candidateX - pos.x, candidateZ - pos.z)
            guard dist >= minJump, dist <= maxJump else { continue }
            endX = candidateX
            endZ = candidateZ
            found = true
            break
        }

        if !found {
            // Guaranteed short local hop — never snap to a far pond.
            let dist = Float.random(in: minJump...3.2, using: &rng)
            let angle = facingY + Float.random(in: -0.5...0.5, using: &rng)
            endX = max(-maxX, min(maxX, pos.x + sin(angle) * dist))
            endZ = pos.z + cos(angle) * dist
        }

        facingY = atan2(endX - pos.x, endZ - pos.z)
        node.eulerAngles.y = facingY

        let start = SIMD3<Float>(pos.x, 0, pos.z)
        let end = SIMD3<Float>(endX, 0, endZ)
        let hopDist = hypot(endX - pos.x, endZ - pos.z)
        let peak = Float.random(in: 0.45...0.85, using: &rng)
        // Duration scales a bit with distance so long hops don't look rushed.
        let duration = Float.random(in: 0.40...0.52, using: &rng) + hopDist * 0.03
        phase = .jumping(
            elapsed: 0,
            duration: duration,
            start: start,
            end: end,
            peak: peak
        )
        _ = heightField
    }

    private func startFidget(
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.35
        let endX = max(-maxX, min(maxX, pos.x + Float.random(in: -0.28...0.28, using: &rng)))
        let endZ = pos.z + Float.random(in: -0.28...0.28, using: &rng)
        let duration: Float = 0.35
        phase = .fidget(
            remaining: duration,
            startX: pos.x,
            startZ: pos.z,
            endX: endX,
            endZ: endZ,
            duration: duration
        )
    }
}

final class FrogIndex {
    private var frogs: [FrogActor] = []
    private var waterSpots: [(x: Float, z: Float, radius: Float, endZ: Float)] = []
    private var lastSpawnZ: Float = -60
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        frogs.forEach { $0.node.removeFromParentNode() }
        frogs.removeAll()
        waterSpots.removeAll()
        lastSpawnZ = -60
        rng = SystemRandomNumberGenerator()
    }

    func registerPonds(_ ponds: [(x: Float, z: Float, radius: Float)], chunkEndZ: Float) {
        for pond in ponds {
            waterSpots.append((pond.x, pond.z, pond.radius, chunkEndZ))
        }
    }

    func cull(beforeZ z: Float) {
        waterSpots.removeAll { $0.endZ < z }
        frogs.removeAll { frog in
            if frog.node.position.z < z {
                frog.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    /// About twice as often as before (~120–170m).
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float,
        ponds: [(x: Float, z: Float, radius: Float)]
    ) {
        let spacing = Float.random(in: 120...170, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        let maxX = trackHalfWidth - 1.2
        let x: Float
        let sz: Float
        if let pond = ponds.randomElement(using: &rng) {
            let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
            let rim = pond.radius * Float.random(in: 0.9...1.35, using: &rng)
            x = max(-maxX, min(maxX, pond.x + cos(angle) * rim))
            sz = pond.z + sin(angle) * rim * 0.4
        } else {
            x = Float.random(in: (-maxX * 0.7)...(maxX * 0.7), using: &rng)
            sz = z + Float.random(in: -4...10, using: &rng)
        }

        let groundY = heightField.height(atX: x, z: sz)
        let color = FrogColor.allCases.randomElement(using: &rng) ?? .green
        let built = FrogFactory.make(at: SCNVector3(x, groundY, sz), color: color)
        parent.addChildNode(built.node)
        frogs.append(
            FrogActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                body: built.body,
                bodyBaseY: built.bodyBaseY
            )
        )
        lastSpawnZ = z
    }

    func update(deltaTime: Float, heightField: HeightField, trackHalfWidth: Float) {
        let spots = waterSpots.map { (x: $0.x, z: $0.z, radius: $0.radius) }
        for frog in frogs {
            frog.update(
                deltaTime: deltaTime,
                heightField: heightField,
                trackHalfWidth: trackHalfWidth,
                waterSpots: spots,
                rng: &rng
            )
        }
    }

    func deepestContact(x: Float, y: Float, z: Float, ballRadius: Float) -> ObstacleContact? {
        let ballBottom = y - ballRadius
        let ballTop = y + ballRadius
        var best: ObstacleContact?

        for frog in frogs {
            let pos = frog.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = frog.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + frog.height && ballTop > pos.y else { continue }

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

enum FrogFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let body: SCNNode
        let bodyBaseY: Float
    }

    static func make(at position: SCNVector3, color: FrogColor) -> Built {
        let root = SCNNode()
        root.name = "frog"
        root.position = position
        root.castsShadow = false

        let skin = SCNMaterial()
        skin.diffuse.contents = color.skin
        skin.lightingModel = .blinn
        skin.shininess = 0.35

        let belly = SCNMaterial()
        belly.diffuse.contents = color.belly
        belly.lightingModel = .lambert

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        dark.lightingModel = .lambert

        let bodyBaseY: Float = 0.22
        let body = SCNNode()
        body.position = SCNVector3(0, bodyBaseY, 0)
        root.addChildNode(body)

        let torso = SCNSphere(radius: 0.22)
        torso.segmentCount = 12
        torso.firstMaterial = skin
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.scale = SCNVector3(1.05, 0.75, 1.25)
        body.addChildNode(torsoNode)

        let bellyGeo = SCNSphere(radius: 0.14)
        bellyGeo.segmentCount = 10
        bellyGeo.firstMaterial = belly
        let bellyNode = SCNNode(geometry: bellyGeo)
        bellyNode.scale = SCNVector3(0.95, 0.55, 1.05)
        bellyNode.position = SCNVector3(0, -0.06, 0.04)
        body.addChildNode(bellyNode)

        let head = SCNSphere(radius: 0.15)
        head.segmentCount = 10
        head.firstMaterial = skin
        let headNode = SCNNode(geometry: head)
        headNode.scale = SCNVector3(1.05, 0.85, 1.0)
        headNode.position = SCNVector3(0, 0.1, 0.2)
        body.addChildNode(headNode)

        for side: Float in [-1, 1] {
            let eyeWhite = SCNSphere(radius: 0.055)
            eyeWhite.segmentCount = 8
            eyeWhite.firstMaterial = belly
            let eyeNode = SCNNode(geometry: eyeWhite)
            eyeNode.position = SCNVector3(side * 0.1, 0.1, 0.1)
            headNode.addChildNode(eyeNode)

            let pupil = SCNSphere(radius: 0.025)
            pupil.segmentCount = 6
            pupil.firstMaterial = dark
            let pupilNode = SCNNode(geometry: pupil)
            pupilNode.position = SCNVector3(0, 0.01, 0.04)
            eyeNode.addChildNode(pupilNode)

            let thigh = SCNCapsule(capRadius: 0.045, height: 0.22)
            thigh.radialSegmentCount = 6
            thigh.firstMaterial = skin
            let thighNode = SCNNode(geometry: thigh)
            thighNode.position = SCNVector3(side * 0.16, -0.08, -0.1)
            thighNode.eulerAngles.z = side * 0.7
            thighNode.eulerAngles.x = 0.5
            body.addChildNode(thighNode)

            let foot = SCNSphere(radius: 0.06)
            foot.segmentCount = 6
            foot.firstMaterial = skin
            let footNode = SCNNode(geometry: foot)
            footNode.scale = SCNVector3(0.7, 0.4, 1.2)
            footNode.position = SCNVector3(side * 0.22, -0.18, -0.02)
            body.addChildNode(footNode)

            let arm = SCNCapsule(capRadius: 0.03, height: 0.14)
            arm.radialSegmentCount = 5
            arm.firstMaterial = skin
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(side * 0.14, -0.1, 0.14)
            armNode.eulerAngles.z = side * 0.45
            body.addChildNode(armNode)
        }

        let hitRadius: Float = 0.42
        let hitHeight: Float = 0.55
        return Built(
            node: root,
            radius: hitRadius,
            height: hitHeight,
            body: body,
            bodyBaseY: bodyBaseY
        )
    }
}
