import Foundation
import SceneKit
import UIKit

final class MooseActor {
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
    private let bodyBaseY: Float = 1.45

    init(node: SCNNode, radius: Float, height: Float, startX: Float, startZ: Float, legs: [SCNNode], body: SCNNode) {
        self.node = node
        self.radius = radius
        self.height = height
        self.targetX = startX
        self.targetZ = startZ + 10
        self.retargetTimer = Float.random(in: 0.3...1.0)
        self.walkPhase = Float.random(in: 0...(Float.pi * 2))
        self.lastX = startX
        self.lastZ = startZ
        self.legNodes = legs
        self.bodyNode = body
    }

    func update(
        deltaTime: Float,
        ice: IcePatchIndex,
        heightField: HeightField,
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator
    ) {
        retargetTimer -= deltaTime
        if retargetTimer <= 0 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng)
        }

        let pos = node.position
        let dx = targetX - pos.x
        let dz = targetZ - pos.z
        let dist = hypot(dx, dz)

        if dist < 1.2 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng)
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
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng, forceEscape: true)
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let speed: Float = 4.4
        let step = min(max(dist, 0.001), speed * deltaTime)

        let maxX = trackHalfWidth - radius - 0.5
        let newX = max(-maxX, min(maxX, pos.x + dirX * step))
        let newZ = pos.z + dirZ * step

        let groundY = heightField.height(atX: newX, z: newZ)
        node.position = SCNVector3(newX, groundY, newZ)

        let movedX = newX - pos.x
        let movedZ = newZ - pos.z
        if hypot(movedX, movedZ) > 0.01 {
            node.eulerAngles.y = atan2(movedX, movedZ)
        } else if dist > 0.5 {
            node.eulerAngles.y = atan2(dirX, dirZ)
        }

        walkPhase += deltaTime * 6.8
        let swing = sin(walkPhase) * 0.4
        if legNodes.count >= 4 {
            legNodes[0].eulerAngles.x = swing
            legNodes[1].eulerAngles.x = -swing
            legNodes[2].eulerAngles.x = -swing
            legNodes[3].eulerAngles.x = swing
        }
        bodyNode.position.y = bodyBaseY + abs(sin(walkPhase)) * 0.05
        bodyNode.eulerAngles.z = sin(walkPhase * 0.5) * 0.03
        _ = ice
    }

    private func pickNewTarget(
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.5

        for _ in 0..<16 {
            let x = Float.random(in: (-maxX)...maxX, using: &rng)
            let zOffset: Float
            if forceEscape {
                zOffset = Float.random(in: 8...24, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
            } else {
                zOffset = Float.random(in: -18...26, using: &rng)
            }
            let z = pos.z + zOffset
            if hypot(x - pos.x, z - pos.z) < 5 { continue }
            targetX = x
            targetZ = z
            retargetTimer = Float.random(in: 2.0...4.5, using: &rng)
            return
        }

        targetX = max(-maxX, min(maxX, pos.x + Float.random(in: -12...12, using: &rng)))
        targetZ = pos.z + Float.random(in: 10...22, using: &rng)
        retargetTimer = Float.random(in: 1.5...3.0, using: &rng)
    }
}

final class MooseIndex {
    private var moose: [MooseActor] = []
    private var lastSpawnZ: Float = -180
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        moose.forEach { $0.node.removeFromParentNode() }
        moose.removeAll()
        lastSpawnZ = -180
        rng = SystemRandomNumberGenerator()
    }

    func cull(beforeZ z: Float) {
        moose.removeAll { animal in
            if animal.node.position.z < z {
                animal.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    /// Roughly one moose every ~500m on open snow (not on ice).
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        ice: IcePatchIndex,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        let spacing = Float.random(in: 440...580, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        let maxX = trackHalfWidth * 0.4
        var spot: (x: Float, z: Float)?
        for _ in 0..<24 {
            let x = Float.random(in: (-maxX)...maxX, using: &rng)
            let sz = z + Float.random(in: -6...14, using: &rng)
            let cleared = ice.pushOffIce(x: x, z: sz, clearance: 1.5)
            let finalX = max(-maxX, min(maxX, cleared.x))
            if ice.isOnIce(x: finalX, z: cleared.z, margin: 1.0) { continue }
            spot = (finalX, cleared.z)
            break
        }
        guard let spot else { return }

        let groundY = heightField.height(atX: spot.x, z: spot.z)
        let built = MooseFactory.make(at: SCNVector3(spot.x, groundY, spot.z))
        parent.addChildNode(built.node)
        moose.append(
            MooseActor(
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
        ice: IcePatchIndex,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        for animal in moose {
            animal.update(
                deltaTime: deltaTime,
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

        for animal in moose {
            let pos = animal.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = animal.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + animal.height && ballTop > pos.y else { continue }

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

enum MooseFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let legs: [SCNNode]
        let body: SCNNode
    }

    /// Tall moose with oversized palmated antlers.
    static func make(at position: SCNVector3) -> Built {
        let root = SCNNode()
        root.name = "moose"
        root.position = position
        root.castsShadow = false

        let fur = SCNMaterial()
        fur.diffuse.contents = UIColor(red: 0.42, green: 0.28, blue: 0.18, alpha: 1)
        fur.lightingModel = .blinn
        fur.shininess = 0.1

        let darkFur = SCNMaterial()
        darkFur.diffuse.contents = UIColor(red: 0.28, green: 0.18, blue: 0.12, alpha: 1)
        darkFur.lightingModel = .blinn

        let antlerMat = SCNMaterial()
        antlerMat.diffuse.contents = UIColor(red: 0.78, green: 0.68, blue: 0.48, alpha: 1)
        antlerMat.lightingModel = .blinn
        antlerMat.shininess = 0.25

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        dark.lightingModel = .lambert

        let body = SCNNode()
        body.position = SCNVector3(0, 1.45, 0)
        root.addChildNode(body)

        let torso = SCNSphere(radius: 0.78)
        torso.segmentCount = 14
        torso.firstMaterial = fur
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.scale = SCNVector3(0.95, 0.9, 1.7)
        body.addChildNode(torsoNode)

        let hump = SCNSphere(radius: 0.42)
        hump.segmentCount = 10
        hump.firstMaterial = darkFur
        let humpNode = SCNNode(geometry: hump)
        humpNode.scale = SCNVector3(0.9, 0.7, 1.1)
        humpNode.position = SCNVector3(0, 0.45, 0.55)
        body.addChildNode(humpNode)

        let neck = SCNCylinder(radius: 0.28, height: 0.7)
        neck.radialSegmentCount = 10
        neck.firstMaterial = fur
        let neckNode = SCNNode(geometry: neck)
        neckNode.eulerAngles.x = 0.55
        neckNode.position = SCNVector3(0, 0.35, 1.05)
        body.addChildNode(neckNode)

        // Unscaled head group so antlers are not warped by sphere stretch.
        let headGroup = SCNNode()
        headGroup.position = SCNVector3(0, 0.55, 1.45)
        body.addChildNode(headGroup)

        let head = SCNSphere(radius: 0.36)
        head.segmentCount = 12
        head.firstMaterial = fur
        let headNode = SCNNode(geometry: head)
        headNode.scale = SCNVector3(0.9, 0.85, 1.2)
        headGroup.addChildNode(headNode)

        let snout = SCNSphere(radius: 0.2)
        snout.segmentCount = 10
        snout.firstMaterial = darkFur
        let snoutNode = SCNNode(geometry: snout)
        snoutNode.scale = SCNVector3(0.85, 0.7, 1.35)
        snoutNode.position = SCNVector3(0, -0.04, 0.38)
        headGroup.addChildNode(snoutNode)

        for side: Float in [-1, 1] {
            let ear = SCNSphere(radius: 0.1)
            ear.segmentCount = 8
            ear.firstMaterial = fur
            let earNode = SCNNode(geometry: ear)
            earNode.scale = SCNVector3(0.7, 1.2, 0.5)
            earNode.position = SCNVector3(side * 0.26, 0.26, -0.05)
            headGroup.addChildNode(earNode)

            let eye = SCNSphere(radius: 0.05)
            eye.segmentCount = 6
            eye.firstMaterial = dark
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.18, 0.08, 0.2)
            headGroup.addChildNode(eyeNode)
        }

        // Antlers parented to unscaled head group.
        addAntler(to: headGroup, side: -1, material: antlerMat)
        addAntler(to: headGroup, side: 1, material: antlerMat)

        var legs: [SCNNode] = []
        let legOffsets: [(Float, Float)] = [
            (-0.38, 0.65),
            (0.38, 0.65),
            (-0.42, -0.85),
            (0.42, -0.85)
        ]
        for (lx, lz) in legOffsets {
            let pivot = SCNNode()
            pivot.position = SCNVector3(lx, 1.2, lz)
            root.addChildNode(pivot)

            let leg = SCNCylinder(radius: 0.14, height: 1.25)
            leg.radialSegmentCount = 8
            leg.firstMaterial = fur
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(0, -0.55, 0)
            pivot.addChildNode(legNode)

            let hoof = SCNSphere(radius: 0.16)
            hoof.segmentCount = 8
            hoof.firstMaterial = darkFur
            let hoofNode = SCNNode(geometry: hoof)
            hoofNode.scale = SCNVector3(1.0, 0.55, 1.15)
            hoofNode.position = SCNVector3(0, -1.2, 0.02)
            pivot.addChildNode(hoofNode)

            legs.append(pivot)
        }

        // One-third smaller than the base mesh.
        let size: Float = 2.0 / 3.0
        root.scale = SCNVector3(size, size, size)
        let hitRadius: Float = 2.0 * size
        let hitHeight: Float = 3.2 * size
        return Built(node: root, radius: hitRadius, height: hitHeight, legs: legs, body: body)
    }

    /// Classic moose antler: beam out from skull, flat palm, upright tines.
    private static func addAntler(to head: SCNNode, side: Float, material: SCNMaterial) {
        let root = SCNNode()
        root.position = SCNVector3(side * 0.18, 0.28, -0.02)
        head.addChildNode(root)

        // Main beam: out to the side and slightly up/back.
        let beam = SCNCylinder(radius: 0.055, height: 0.7)
        beam.radialSegmentCount = 8
        beam.firstMaterial = material
        let beamNode = SCNNode(geometry: beam)
        beamNode.eulerAngles.z = side * (.pi / 2 - 0.35)
        beamNode.eulerAngles.x = -0.35
        beamNode.position = SCNVector3(side * 0.28, 0.22, -0.08)
        root.addChildNode(beamNode)

        // Palm sits at the end of the beam (thin plate in the Y/Z plane).
        let palm = SCNBox(width: 0.1, height: 0.62, length: 0.85, chamferRadius: 0.04)
        palm.firstMaterial = material
        let palmNode = SCNNode(geometry: palm)
        palmNode.position = SCNVector3(side * 0.58, 0.48, -0.05)
        palmNode.eulerAngles.z = side * 0.15
        root.addChildNode(palmNode)

        // Upright tines along the top of the palm.
        let tineZs: [Float] = [-0.3, -0.1, 0.1, 0.3]
        for (i, tz) in tineZs.enumerated() {
            let h = CGFloat(0.22 + Float(i % 2) * 0.1)
            let tine = SCNCylinder(radius: 0.035, height: h)
            tine.radialSegmentCount = 6
            tine.firstMaterial = material
            let tineNode = SCNNode(geometry: tine)
            tineNode.position = SCNVector3(side * 0.58, 0.78 + Float(h) * 0.35, tz)
            root.addChildNode(tineNode)
        }

        // Brow tine toward the snout.
        let brow = SCNCylinder(radius: 0.032, height: 0.32)
        brow.radialSegmentCount = 6
        brow.firstMaterial = material
        let browNode = SCNNode(geometry: brow)
        browNode.eulerAngles.x = 1.05
        browNode.eulerAngles.z = side * 0.2
        browNode.position = SCNVector3(side * 0.28, 0.3, 0.28)
        root.addChildNode(browNode)
    }
}
