import Foundation
import SceneKit
import UIKit

/// Real Galapagos lava lizards range from black/grey to brown and green,
/// with warmer rusty morphs (females often show red/orange head tones).
enum LavaLizardColor: CaseIterable {
    case charcoal
    case grey
    case brown
    case olive
    case rusty

    var body: UIColor {
        switch self {
        // Lifted off pure black so they read on scorched ground.
        case .charcoal: return UIColor(red: 0.28, green: 0.24, blue: 0.22, alpha: 1)
        case .grey: return UIColor(red: 0.58, green: 0.54, blue: 0.50, alpha: 1)
        case .brown: return UIColor(red: 0.62, green: 0.40, blue: 0.24, alpha: 1)
        case .olive: return UIColor(red: 0.46, green: 0.52, blue: 0.28, alpha: 1)
        case .rusty: return UIColor(red: 0.72, green: 0.38, blue: 0.22, alpha: 1)
        }
    }

    var belly: UIColor {
        switch self {
        case .charcoal: return UIColor(red: 0.48, green: 0.40, blue: 0.32, alpha: 1)
        case .grey: return UIColor(red: 0.78, green: 0.72, blue: 0.62, alpha: 1)
        case .brown: return UIColor(red: 0.82, green: 0.64, blue: 0.42, alpha: 1)
        case .olive: return UIColor(red: 0.68, green: 0.70, blue: 0.42, alpha: 1)
        case .rusty: return UIColor(red: 0.90, green: 0.58, blue: 0.36, alpha: 1)
        }
    }

    var accent: UIColor {
        switch self {
        case .charcoal: return UIColor(red: 0.85, green: 0.72, blue: 0.28, alpha: 1)
        case .grey: return UIColor(red: 0.90, green: 0.78, blue: 0.32, alpha: 1)
        case .brown: return UIColor(red: 0.92, green: 0.70, blue: 0.28, alpha: 1)
        case .olive: return UIColor(red: 0.88, green: 0.82, blue: 0.35, alpha: 1)
        case .rusty: return UIColor(red: 0.95, green: 0.42, blue: 0.22, alpha: 1)
        }
    }
}

final class LavaLizardActor {
    let node: SCNNode
    let radius: Float
    let height: Float
    private var targetX: Float
    private var targetZ: Float
    private var retargetTimer: Float
    private var walkPhase: Float
    private var pushUpTimer: Float
    private var pushUpAmount: Float = 0
    private var stuckTimer: Float = 0
    private var lastX: Float
    private var lastZ: Float
    private let bodyNode: SCNNode
    private let bodyBaseY: Float

    init(
        node: SCNNode,
        radius: Float,
        height: Float,
        startX: Float,
        startZ: Float,
        body: SCNNode,
        bodyBaseY: Float
    ) {
        self.node = node
        self.radius = radius
        self.height = height
        self.targetX = startX
        self.targetZ = startZ + 4
        self.retargetTimer = Float.random(in: 0.2...0.8)
        self.walkPhase = Float.random(in: 0...(Float.pi * 2))
        self.pushUpTimer = Float.random(in: 1.5...4.0)
        self.lastX = startX
        self.lastZ = startZ
        self.bodyNode = body
        self.bodyBaseY = bodyBaseY
    }

    func update(
        deltaTime: Float,
        heightField: HeightField,
        trackHalfWidth: Float,
        hotSpots: [(x: Float, z: Float, radius: Float)],
        rng: inout some RandomNumberGenerator
    ) {
        let dt = min(deltaTime, 1.0 / 20.0)

        // Signature lava-lizard territorial push-ups.
        pushUpTimer -= dt
        if pushUpTimer <= 0 {
            pushUpAmount = 1
            pushUpTimer = Float.random(in: 2.5...5.5, using: &rng)
            retargetTimer = max(retargetTimer, 0.55)
        }
        if pushUpAmount > 0 {
            pushUpAmount = max(0, pushUpAmount - dt * 2.2)
            let bob = abs(sin((1 - pushUpAmount) * Float.pi * 3)) * 0.1 * pushUpAmount
            bodyNode.position.y = bodyBaseY + bob
            // Hold still while displaying.
            return
        }

        retargetTimer -= dt
        if retargetTimer <= 0 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, hotSpots: hotSpots, rng: &rng)
        }

        let pos = node.position
        let dx = targetX - pos.x
        let dz = targetZ - pos.z
        let dist = hypot(dx, dz)
        if dist < 0.7 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, hotSpots: hotSpots, rng: &rng)
        }

        let moveDist = hypot(pos.x - lastX, pos.z - lastZ)
        stuckTimer = moveDist < 0.015 ? stuckTimer + dt : 0
        lastX = pos.x
        lastZ = pos.z
        if stuckTimer > 0.7 {
            stuckTimer = 0
            pickNewTarget(
                trackHalfWidth: trackHalfWidth,
                hotSpots: hotSpots,
                rng: &rng,
                forceEscape: true
            )
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let speed: Float = 4.4
        let step = min(max(dist, 0.001), speed * dt)
        let maxX = trackHalfWidth - radius - 0.35
        let newX = max(-maxX, min(maxX, pos.x + dirX * step))
        let newZ = pos.z + dirZ * step
        let groundY = heightField.height(atX: newX, z: newZ)
        node.position = SCNVector3(newX, groundY, newZ)

        if hypot(newX - pos.x, newZ - pos.z) > 0.01 {
            node.eulerAngles.y = atan2(dirX, dirZ)
        }

        walkPhase += dt * 16
        bodyNode.position.y = bodyBaseY + abs(sin(walkPhase)) * 0.03
        bodyNode.eulerAngles.z = sin(walkPhase) * 0.08
    }

    private func pickNewTarget(
        trackHalfWidth: Float,
        hotSpots: [(x: Float, z: Float, radius: Float)],
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.35
        let nearbyHot = hotSpots.filter { hypot(pos.x - $0.x, pos.z - $0.z) < 28 }

        for _ in 0..<16 {
            let x: Float
            let z: Float
            if !forceEscape, let spot = nearbyHot.randomElement(using: &rng),
               Float.random(in: 0...1, using: &rng) < 0.6 {
                let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
                let rim = spot.radius * Float.random(in: 0.9...1.4, using: &rng)
                x = max(-maxX, min(maxX, spot.x + cos(angle) * rim))
                z = spot.z + sin(angle) * rim
            } else {
                let dist = Float.random(in: 2.5...7.0, using: &rng)
                let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
                x = max(-maxX, min(maxX, pos.x + cos(angle) * dist))
                z = pos.z + sin(angle) * dist
            }
            if hypot(x - pos.x, z - pos.z) < 1.6 { continue }
            targetX = x
            targetZ = z
            retargetTimer = Float.random(in: 1.0...2.6, using: &rng)
            return
        }

        targetX = max(-maxX, min(maxX, pos.x + Float.random(in: -5...5, using: &rng)))
        targetZ = pos.z + Float.random(in: 4...10, using: &rng)
        retargetTimer = Float.random(in: 0.8...1.8, using: &rng)
    }
}

final class LavaLizardIndex {
    private var lizards: [LavaLizardActor] = []
    private var hotSpots: [(x: Float, z: Float, radius: Float, endZ: Float)] = []
    private var lastSpawnZ: Float = -40
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        lizards.forEach { $0.node.removeFromParentNode() }
        lizards.removeAll()
        hotSpots.removeAll()
        lastSpawnZ = -40
        rng = SystemRandomNumberGenerator()
    }

    func registerPockets(_ pockets: [(x: Float, z: Float, radius: Float)], chunkEndZ: Float) {
        for pocket in pockets {
            hotSpots.append((pocket.x, pocket.z, pocket.radius, chunkEndZ))
        }
    }

    func cull(beforeZ z: Float) {
        hotSpots.removeAll { $0.endZ < z }
        lizards.removeAll { lizard in
            if lizard.node.position.z < z {
                lizard.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    /// Skittering lizards near lava pockets — often enough to notice (~90–140m).
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float,
        pockets: [(x: Float, z: Float, radius: Float)]
    ) {
        let spacing = Float.random(in: 90...140, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        // Sometimes drop a pair so they're easier to spot.
        let count = Float.random(in: 0...1, using: &rng) < 0.35 ? 2 : 1
        for _ in 0..<count {
            spawnOne(
                aroundZ: z,
                parent: parent,
                heightField: heightField,
                trackHalfWidth: trackHalfWidth,
                pockets: pockets
            )
        }
        lastSpawnZ = z
    }

    private func spawnOne(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float,
        pockets: [(x: Float, z: Float, radius: Float)]
    ) {
        let maxX = trackHalfWidth - 1.4
        let x: Float
        let sz: Float
        if let pocket = pockets.randomElement(using: &rng) {
            let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
            let rim = pocket.radius * Float.random(in: 1.15...1.7, using: &rng)
            x = max(-maxX, min(maxX, pocket.x + cos(angle) * rim))
            sz = pocket.z + sin(angle) * rim * 0.55
        } else {
            x = Float.random(in: (-maxX * 0.8)...(maxX * 0.8), using: &rng)
            sz = z + Float.random(in: -4...10, using: &rng)
        }

        let groundY = heightField.height(atX: x, z: sz)
        let color = LavaLizardColor.allCases.randomElement(using: &rng) ?? .rusty
        let built = LavaLizardFactory.make(at: SCNVector3(x, groundY, sz), color: color)
        parent.addChildNode(built.node)
        lizards.append(
            LavaLizardActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                startX: x,
                startZ: sz,
                body: built.body,
                bodyBaseY: built.bodyBaseY
            )
        )
    }

    func update(deltaTime: Float, heightField: HeightField, trackHalfWidth: Float) {
        let spots = hotSpots.map { (x: $0.x, z: $0.z, radius: $0.radius) }
        for lizard in lizards {
            lizard.update(
                deltaTime: deltaTime,
                heightField: heightField,
                trackHalfWidth: trackHalfWidth,
                hotSpots: spots,
                rng: &rng
            )
        }
    }

    func deepestContact(x: Float, y: Float, z: Float, ballRadius: Float) -> ObstacleContact? {
        let ballBottom = y - ballRadius
        let ballTop = y + ballRadius
        var best: ObstacleContact?

        for lizard in lizards {
            let pos = lizard.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = lizard.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + lizard.height && ballTop > pos.y else { continue }

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

enum LavaLizardFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let body: SCNNode
        let bodyBaseY: Float
    }

    static func make(at position: SCNVector3, color: LavaLizardColor) -> Built {
        let root = SCNNode()
        root.name = "lavaLizard"
        root.position = position
        root.castsShadow = false

        let skin = SCNMaterial()
        skin.diffuse.contents = color.body
        skin.lightingModel = .blinn
        skin.shininess = 0.25

        let bellyMat = SCNMaterial()
        bellyMat.diffuse.contents = color.belly
        bellyMat.lightingModel = .lambert

        let accentMat = SCNMaterial()
        accentMat.diffuse.contents = color.accent
        accentMat.emission.contents = color.accent.withAlphaComponent(0.25)
        accentMat.lightingModel = .blinn

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        dark.lightingModel = .lambert

        let bodyBaseY: Float = 0.14
        let body = SCNNode()
        body.position = SCNVector3(0, bodyBaseY, 0)
        root.addChildNode(body)

        let torso = SCNCapsule(capRadius: 0.12, height: 0.55)
        torso.radialSegmentCount = 8
        torso.firstMaterial = skin
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.eulerAngles.x = Float.pi / 2
        torsoNode.scale = SCNVector3(1.05, 0.7, 1)
        body.addChildNode(torsoNode)

        let belly = SCNCapsule(capRadius: 0.08, height: 0.4)
        belly.radialSegmentCount = 6
        belly.firstMaterial = bellyMat
        let bellyNode = SCNNode(geometry: belly)
        bellyNode.eulerAngles.x = Float.pi / 2
        bellyNode.scale = SCNVector3(0.85, 0.5, 1)
        bellyNode.position = SCNVector3(0, -0.05, 0.02)
        body.addChildNode(bellyNode)

        let head = SCNSphere(radius: 0.11)
        head.segmentCount = 10
        head.firstMaterial = skin
        let headNode = SCNNode(geometry: head)
        headNode.scale = SCNVector3(0.95, 0.75, 1.15)
        headNode.position = SCNVector3(0, 0.04, 0.38)
        body.addChildNode(headNode)

        // Rusty morphs get a warmer throat/cheek patch.
        if color == .rusty {
            let cheek = SCNSphere(radius: 0.05)
            cheek.segmentCount = 6
            cheek.firstMaterial = accentMat
            let cheekNode = SCNNode(geometry: cheek)
            cheekNode.scale = SCNVector3(1.2, 0.7, 0.9)
            cheekNode.position = SCNVector3(0, -0.02, 0.08)
            headNode.addChildNode(cheekNode)
        }

        for side: Float in [-1, 1] {
            let eye = SCNSphere(radius: 0.025)
            eye.segmentCount = 6
            eye.firstMaterial = dark
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.06, 0.04, 0.08)
            headNode.addChildNode(eyeNode)
        }

        // Short crest along the back.
        for i in 0..<4 {
            let spike = SCNCone(topRadius: 0.005, bottomRadius: 0.02, height: 0.06)
            spike.radialSegmentCount = 4
            spike.firstMaterial = skin
            let spikeNode = SCNNode(geometry: spike)
            spikeNode.position = SCNVector3(0, 0.12, -0.15 + Float(i) * 0.12)
            body.addChildNode(spikeNode)
        }

        let tail = SCNCone(topRadius: 0.01, bottomRadius: 0.08, height: 0.55)
        tail.radialSegmentCount = 6
        tail.firstMaterial = skin
        let tailNode = SCNNode(geometry: tail)
        tailNode.position = SCNVector3(0, 0.02, -0.48)
        tailNode.eulerAngles.x = Float.pi / 2 + 0.2
        body.addChildNode(tailNode)

        let legOffsets: [(Float, Float)] = [
            (-0.12, 0.18),
            (0.12, 0.18),
            (-0.11, -0.16),
            (0.11, -0.16)
        ]
        for (lx, lz) in legOffsets {
            let leg = SCNCylinder(radius: 0.03, height: 0.12)
            leg.radialSegmentCount = 5
            leg.firstMaterial = skin
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(lx, -0.08, lz)
            body.addChildNode(legNode)
        }

        // Larger than real life so they read clearly while rolling.
        let scale: Float = 2.2
        root.scale = SCNVector3(scale, scale, scale)
        let hitRadius: Float = 0.48 * scale
        let hitHeight: Float = 0.4 * scale
        return Built(
            node: root,
            radius: hitRadius,
            height: hitHeight,
            body: body,
            bodyBaseY: bodyBaseY
        )
    }
}
