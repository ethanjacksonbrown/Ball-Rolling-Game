import Foundation
import SceneKit

struct IcePatch {
    var x: Float
    var z: Float
    var radius: Float
    var chunkEndZ: Float
}

/// Tracks icy patches so polar bears can spawn near ice clusters without standing on them.
final class IcePatchIndex {
    private var patches: [IcePatch] = []

    func reset() {
        patches.removeAll(keepingCapacity: true)
    }

    func add(_ patch: IcePatch) {
        patches.append(patch)
    }

    func cull(beforeZ z: Float) {
        patches.removeAll { $0.chunkEndZ < z }
    }

    /// True if (x, z) sits on an ice disc (plus optional margin).
    func isOnIce(x: Float, z: Float, margin: Float = 0.6) -> Bool {
        for p in patches {
            if hypot(x - p.x, z - p.z) < p.radius + margin {
                return true
            }
        }
        return false
    }

    /// Push a point off the nearest ice disc if it overlaps one.
    func pushOffIce(x: Float, z: Float, clearance: Float = 1.2) -> (x: Float, z: Float) {
        var px = x
        var pz = z
        for _ in 0..<4 {
            var moved = false
            for p in patches {
                let dx = px - p.x
                let dz = pz - p.z
                let dist = max(0.0001, hypot(dx, dz))
                let minDist = p.radius + clearance
                if dist < minDist {
                    let push = (minDist - dist) / dist
                    px += dx * push
                    pz += dz * push
                    moved = true
                }
            }
            if !moved { break }
        }
        return (px, pz)
    }

    /// Keep as much of the intended step as possible while sliding around ice discs.
    func slideAroundIce(
        fromX: Float,
        fromZ: Float,
        toX: Float,
        toZ: Float,
        clearance: Float = 0.9
    ) -> (x: Float, z: Float) {
        if !isOnIce(x: toX, z: toZ, margin: clearance * 0.5) {
            return (toX, toZ)
        }

        // Try lateral slides first, then fall back to a push-off from the start point.
        let dx = toX - fromX
        let dz = toZ - fromZ
        let candidates: [(Float, Float)] = [
            (fromX + dx, fromZ),
            (fromX, fromZ + dz),
            (fromX - dz * 0.8, fromZ + dx * 0.8),
            (fromX + dz * 0.8, fromZ - dx * 0.8),
            pushOffIce(x: toX, z: toZ, clearance: clearance)
        ]
        for c in candidates {
            if !isOnIce(x: c.0, z: c.1, margin: clearance * 0.4) {
                return (c.0, c.1)
            }
        }
        return pushOffIce(x: fromX, z: fromZ, clearance: clearance + 0.4)
    }

    /// Higher when more ice overlaps the sense radius around (x, z).
    func coverageScore(atX x: Float, z: Float, senseRadius: Float) -> Float {
        var score: Float = 0
        for p in patches {
            let dx = x - p.x
            let dz = z - p.z
            let dist = sqrt(dx * dx + dz * dz)
            let reach = senseRadius + p.radius
            guard dist < reach else { continue }
            let closeness = 1 - dist / reach
            score += p.radius * p.radius * closeness * closeness
        }
        return score
    }

    /// Spot near dense ice, but never on the ice itself.
    func spawnSpotBesideIce(
        nearZ preferredZ: Float,
        zRange: ClosedRange<Float>,
        trackHalfWidth: Float,
        senseRadius: Float = 15,
        samples: Int = 40,
        rng: inout some RandomNumberGenerator
    ) -> (x: Float, z: Float)? {
        guard !patches.isEmpty else { return nil }

        var best: (x: Float, z: Float, score: Float)?
        for _ in 0..<samples {
            // Sample beside a random nearby patch (outside its disc).
            guard let patch = patches.randomElement(using: &rng) else { continue }
            guard zRange.contains(patch.z) || abs(patch.z - preferredZ) < 24 else { continue }

            let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
            let dist = patch.radius + Float.random(in: 1.5...5.5, using: &rng)
            var x = patch.x + cos(angle) * dist
            var z = patch.z + sin(angle) * dist
            if abs(x) > trackHalfWidth { continue }
            if !zRange.contains(z) { continue }

            let cleared = pushOffIce(x: x, z: z, clearance: 1.4)
            x = cleared.x
            z = cleared.z
            guard abs(x) <= trackHalfWidth else { continue }
            guard !isOnIce(x: x, z: z, margin: 0.8) else { continue }

            var score = coverageScore(atX: x, z: z, senseRadius: senseRadius)
            score -= abs(z - preferredZ) * 0.08
            // Prefer being close to ice without standing on it.
            if score > (best?.score ?? -1) {
                best = (x, z, score)
            }
        }

        guard let best, best.score > 4 else { return nil }
        return (best.x, best.z)
    }
}

final class PolarBearActor {
    let node: SCNNode
    let radius: Float
    let height: Float
    private var targetX: Float
    private var targetZ: Float
    private var retargetTimer: Float
    private var walkPhase: Float
    private var stuckTimer: Float = 0
    private var lastX: Float
    private var lastZ: Float
    private let legNodes: [SCNNode]
    private let bodyNode: SCNNode
    private let bodyBaseY: Float = 1.0

    init(node: SCNNode, radius: Float, height: Float, startX: Float, startZ: Float, legs: [SCNNode], body: SCNNode) {
        self.node = node
        self.radius = radius
        self.height = height
        self.targetX = startX
        self.targetZ = startZ + 8
        self.retargetTimer = Float.random(in: 0.3...1.0)
        self.walkPhase = Float.random(in: 0...(Float.pi * 2))
        self.lastX = startX
        self.lastZ = startZ
        self.legNodes = legs
        self.bodyNode = body
    }

    func update(
        deltaTime: Float,
        time: Float,
        ice: IcePatchIndex,
        heightField: HeightField,
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator
    ) {
        retargetTimer -= deltaTime
        if retargetTimer <= 0 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, ice: ice, rng: &rng)
        }

        let pos = node.position
        let dx = targetX - pos.x
        let dz = targetZ - pos.z
        let dist = hypot(dx, dz)

        if dist < 1.2 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, ice: ice, rng: &rng)
        }

        let moveDist = hypot(pos.x - lastX, pos.z - lastZ)
        if moveDist < 0.03 {
            stuckTimer += deltaTime
        } else {
            stuckTimer = 0
        }
        lastX = pos.x
        lastZ = pos.z
        if stuckTimer > 0.7 {
            stuckTimer = 0
            pickNewTarget(trackHalfWidth: trackHalfWidth, ice: ice, rng: &rng, forceEscape: true)
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let speed: Float = 4.0
        let step = min(max(dist, 0.001), speed * deltaTime)

        let maxX = trackHalfWidth - radius - 0.5
        let newX = max(-maxX, min(maxX, pos.x + dirX * step))
        let newZ = pos.z + dirZ * step

        let groundY = heightField.height(atX: newX, z: newZ)
        node.position = SCNVector3(newX, groundY, newZ)

        // Face the direction of travel (forward/back/sideways).
        let movedX = newX - pos.x
        let movedZ = newZ - pos.z
        if hypot(movedX, movedZ) > 0.01 {
            node.eulerAngles.y = atan2(movedX, movedZ)
        } else if dist > 0.5 {
            node.eulerAngles.y = atan2(dirX, dirZ)
        }

        walkPhase += deltaTime * 7.5
        let swing = sin(walkPhase) * 0.35
        if legNodes.count >= 4 {
            legNodes[0].eulerAngles.x = swing
            legNodes[1].eulerAngles.x = -swing
            legNodes[2].eulerAngles.x = -swing
            legNodes[3].eulerAngles.x = swing
        }
        bodyNode.position.y = bodyBaseY + abs(sin(walkPhase)) * 0.05
        bodyNode.eulerAngles.z = sin(walkPhase * 0.5) * 0.04
    }

    private func pickNewTarget(
        trackHalfWidth: Float,
        ice: IcePatchIndex,
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.5

        for _ in 0..<16 {
            // Roam freely: mix of forward, back, and across the track.
            let x = Float.random(in: (-maxX)...maxX, using: &rng)
            let zOffset: Float
            if forceEscape {
                zOffset = Float.random(in: 8...22, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            } else {
                zOffset = Float.random(in: -18...24, using: &rng)
            }
            let z = pos.z + zOffset
            if hypot(x - pos.x, z - pos.z) < 5 { continue }
            targetX = x
            targetZ = z
            retargetTimer = Float.random(in: 2.0...4.5, using: &rng)
            return
        }

        targetX = max(-maxX, min(maxX, pos.x + Float.random(in: -12...12, using: &rng)))
        targetZ = pos.z + Float.random(in: 10...20, using: &rng)
        retargetTimer = Float.random(in: 1.5...3.0, using: &rng)
        _ = ice
    }
}

final class PolarBearIndex {
    private var bears: [PolarBearActor] = []
    private var lastSpawnZ: Float = -400
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        bears.forEach { $0.node.removeFromParentNode() }
        bears.removeAll()
        lastSpawnZ = -400
        rng = SystemRandomNumberGenerator()
    }

    func cull(beforeZ z: Float) {
        bears.removeAll { bear in
            if bear.node.position.z < z {
                bear.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    var count: Int { bears.count }

    /// Roughly one bear every ~500m, near ice clusters but never on the ice.
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        ice: IcePatchIndex,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        let spacing = Float.random(in: 430...560, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        guard let spot = ice.spawnSpotBesideIce(
            nearZ: z,
            zRange: (z - 10)...(z + 18),
            trackHalfWidth: trackHalfWidth * 0.4,
            senseRadius: 15,
            samples: 40,
            rng: &rng
        ) else { return }

        guard !ice.isOnIce(x: spot.x, z: spot.z, margin: 0.8) else { return }

        let groundY = heightField.height(atX: spot.x, z: spot.z)
        let built = PolarBearFactory.make(at: SCNVector3(spot.x, groundY, spot.z))
        parent.addChildNode(built.node)
        bears.append(
            PolarBearActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                startX: spot.x,
                startZ: spot.z,
                legs: built.legs,
                body: built.body
            )
        )
        lastSpawnZ = z
    }

    func update(
        deltaTime: Float,
        time: Float,
        ice: IcePatchIndex,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        for bear in bears {
            bear.update(
                deltaTime: deltaTime,
                time: time,
                ice: ice,
                heightField: heightField,
                trackHalfWidth: trackHalfWidth,
                rng: &rng
            )
        }
    }

    func deepestContact(x: Float, y: Float, z: Float, ballRadius: Float) -> ObstacleContact? {
        let ballBottom = y - ballRadius
        let ballTop = y + ballRadius
        var best: ObstacleContact?

        for bear in bears {
            let pos = bear.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = bear.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + bear.height && ballTop > pos.y else { continue }

            let dist = max(0.0001, sqrt(distSq))
            let overlap = minDist - dist + 0.05
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

enum PolarBearFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let legs: [SCNNode]
        let body: SCNNode
    }

    /// Large stylized polar bear built from simple SceneKit primitives.
    static func make(at position: SCNVector3) -> Built {
        let root = SCNNode()
        root.name = "polarBear"
        root.position = position
        root.castsShadow = false

        // Warm dusty gray — reads clearly on white snow.
        let fur = SCNMaterial()
        fur.diffuse.contents = UIColor(red: 0.62, green: 0.60, blue: 0.58, alpha: 1)
        fur.lightingModel = .blinn
        fur.shininess = 0.12

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.1, alpha: 1)
        dark.lightingModel = .lambert

        let noseMat = SCNMaterial()
        noseMat.diffuse.contents = UIColor(white: 0.05, alpha: 1)
        noseMat.lightingModel = .lambert

        let body = SCNNode()
        body.position = SCNVector3(0, 1.0, 0)
        root.addChildNode(body)

        // Smaller torso so the head/legs read as a bear, not a giant snowball.
        let torso = SCNSphere(radius: 0.72)
        torso.segmentCount = 16
        torso.firstMaterial = fur
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.scale = SCNVector3(0.95, 0.85, 1.55)
        body.addChildNode(torsoNode)

        let head = SCNSphere(radius: 0.48)
        head.segmentCount = 14
        head.firstMaterial = fur
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.42, 1.05)
        body.addChildNode(headNode)

        let snout = SCNSphere(radius: 0.22)
        snout.segmentCount = 10
        snout.firstMaterial = fur
        let snoutNode = SCNNode(geometry: snout)
        snoutNode.scale = SCNVector3(0.9, 0.75, 1.25)
        snoutNode.position = SCNVector3(0, -0.04, 0.42)
        headNode.addChildNode(snoutNode)

        let nose = SCNSphere(radius: 0.08)
        nose.segmentCount = 8
        nose.firstMaterial = noseMat
        let noseNode = SCNNode(geometry: nose)
        noseNode.position = SCNVector3(0, 0.02, 0.24)
        snoutNode.addChildNode(noseNode)

        for side: Float in [-1, 1] {
            let ear = SCNSphere(radius: 0.13)
            ear.segmentCount = 8
            ear.firstMaterial = fur
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(side * 0.3, 0.38, 0.08)
            headNode.addChildNode(earNode)

            let eye = SCNSphere(radius: 0.055)
            eye.segmentCount = 6
            eye.firstMaterial = dark
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.18, 0.1, 0.4)
            headNode.addChildNode(eyeNode)
        }

        // Legs: front-left, front-right, back-left, back-right.
        var legs: [SCNNode] = []
        let legOffsets: [(Float, Float)] = [
            (-0.42, 0.55),
            (0.42, 0.55),
            (-0.48, -0.7),
            (0.48, -0.7)
        ]
        for (lx, lz) in legOffsets {
            let pivot = SCNNode()
            pivot.position = SCNVector3(lx, 0.85, lz)
            root.addChildNode(pivot)

            let leg = SCNCylinder(radius: 0.18, height: 0.85)
            leg.radialSegmentCount = 8
            leg.firstMaterial = fur
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, -0.4, 0)
            pivot.addChildNode(legNode)

            let paw = SCNSphere(radius: 0.2)
            paw.segmentCount = 8
            paw.firstMaterial = fur
            let pawNode = SCNNode(geometry: paw)
            pawNode.scale = SCNVector3(1.1, 0.55, 1.2)
            pawNode.position = SCNVector3(0, -0.85, 0.04)
            pivot.addChildNode(pawNode)

            legs.append(pivot)
        }

        // Match ball-scale wildlife size.
        let size: Float = 1
        root.scale = SCNVector3(size, size, size)
        let hitRadius: Float = 1.85 * size
        let hitHeight: Float = 2.2 * size
        return Built(node: root, radius: hitRadius, height: hitHeight, legs: legs, body: body)
    }
}
