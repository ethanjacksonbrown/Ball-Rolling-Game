import Foundation
import SceneKit
import UIKit

final class BrownBearActor {
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
        stuckTimer = moveDist < 0.03 ? stuckTimer + deltaTime : 0
        lastX = pos.x
        lastZ = pos.z
        if stuckTimer > 0.7 {
            stuckTimer = 0
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng, forceEscape: true)
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let step = min(max(dist, 0.001), 3.9 * deltaTime)
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

        walkPhase += deltaTime * 7.2
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
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.5
        for _ in 0..<16 {
            let x = Float.random(in: (-maxX)...maxX, using: &rng)
            let zOffset = forceEscape
                ? Float.random(in: 8...22, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
                : Float.random(in: -18...24, using: &rng)
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
    }
}

final class BrownBearIndex {
    private var bears: [BrownBearActor] = []
    private var lastSpawnZ: Float = -250
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        bears.forEach { $0.node.removeFromParentNode() }
        bears.removeAll()
        lastSpawnZ = -250
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

    /// Roughly one brown bear every ~500m in the forest.
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        let spacing = Float.random(in: 430...560, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        let maxX = trackHalfWidth * 0.4
        let x = Float.random(in: (-maxX)...maxX, using: &rng)
        let sz = z + Float.random(in: -6...14, using: &rng)
        let groundY = heightField.height(atX: x, z: sz)
        let built = BrownBearFactory.make(at: SCNVector3(x, groundY, sz))
        parent.addChildNode(built.node)
        bears.append(
            BrownBearActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                startX: x,
                startZ: sz,
                legs: built.legs,
                body: built.body
            )
        )
        lastSpawnZ = z
    }

    func update(deltaTime: Float, heightField: HeightField, trackHalfWidth: Float) {
        for bear in bears {
            bear.update(
                deltaTime: deltaTime,
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

enum BrownBearFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let legs: [SCNNode]
        let body: SCNNode
    }

    static func make(at position: SCNVector3) -> Built {
        let root = SCNNode()
        root.name = "brownBear"
        root.position = position
        root.castsShadow = false

        let fur = SCNMaterial()
        fur.diffuse.contents = UIColor(red: 0.45, green: 0.28, blue: 0.14, alpha: 1)
        fur.lightingModel = .blinn
        fur.shininess = 0.1

        let muzzle = SCNMaterial()
        muzzle.diffuse.contents = UIColor(red: 0.55, green: 0.40, blue: 0.28, alpha: 1)
        muzzle.lightingModel = .blinn

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        dark.lightingModel = .lambert

        let noseMat = SCNMaterial()
        noseMat.diffuse.contents = UIColor(white: 0.05, alpha: 1)
        noseMat.lightingModel = .lambert

        let body = SCNNode()
        body.position = SCNVector3(0, 1.0, 0)
        root.addChildNode(body)

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
        snout.firstMaterial = muzzle
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
            paw.firstMaterial = dark
            let pawNode = SCNNode(geometry: paw)
            pawNode.scale = SCNVector3(1.1, 0.55, 1.2)
            pawNode.position = SCNVector3(0, -0.85, 0.04)
            pivot.addChildNode(pawNode)

            legs.append(pivot)
        }

        let hitRadius: Float = 1.85
        let hitHeight: Float = 2.2
        return Built(node: root, radius: hitRadius, height: hitHeight, legs: legs, body: body)
    }
}
