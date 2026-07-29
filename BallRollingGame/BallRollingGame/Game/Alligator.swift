import Foundation
import SceneKit
import UIKit

final class AlligatorActor {
    let node: SCNNode
    let radius: Float
    let height: Float
    private var targetX: Float
    private var targetZ: Float
    private var retargetTimer: Float
    private var swimPhase: Float
    private var stuckTimer: Float = 0
    private var lastX: Float
    private var lastZ: Float
    private let bodyNode: SCNNode
    private let bodyBaseY: Float
    private let jawNode: SCNNode

    init(
        node: SCNNode,
        radius: Float,
        height: Float,
        startX: Float,
        startZ: Float,
        body: SCNNode,
        bodyBaseY: Float,
        jaw: SCNNode
    ) {
        self.node = node
        self.radius = radius
        self.height = height
        self.targetX = startX
        self.targetZ = startZ + 6
        self.retargetTimer = Float.random(in: 0.4...1.2)
        self.swimPhase = Float.random(in: 0...(Float.pi * 2))
        self.lastX = startX
        self.lastZ = startZ
        self.bodyNode = body
        self.bodyBaseY = bodyBaseY
        self.jawNode = jaw
    }

    func update(
        deltaTime: Float,
        heightField: HeightField,
        trackHalfWidth: Float,
        waterSpots: [(x: Float, z: Float, radius: Float)],
        rng: inout some RandomNumberGenerator
    ) {
        retargetTimer -= deltaTime
        if retargetTimer <= 0 {
            pickNewTarget(
                trackHalfWidth: trackHalfWidth,
                waterSpots: waterSpots,
                rng: &rng
            )
        }

        let pos = node.position
        let dx = targetX - pos.x
        let dz = targetZ - pos.z
        let dist = hypot(dx, dz)
        if dist < 1.1 {
            pickNewTarget(
                trackHalfWidth: trackHalfWidth,
                waterSpots: waterSpots,
                rng: &rng
            )
        }

        let moveDist = hypot(pos.x - lastX, pos.z - lastZ)
        stuckTimer = moveDist < 0.02 ? stuckTimer + deltaTime : 0
        lastX = pos.x
        lastZ = pos.z
        if stuckTimer > 0.8 {
            stuckTimer = 0
            pickNewTarget(
                trackHalfWidth: trackHalfWidth,
                waterSpots: waterSpots,
                rng: &rng,
                forceEscape: true
            )
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let speed: Float = 3.4
        let step = min(max(dist, 0.001), speed * deltaTime)
        let maxX = trackHalfWidth - radius - 0.35
        let newX = max(-maxX, min(maxX, pos.x + dirX * step))
        let newZ = pos.z + dirZ * step
        let groundY = heightField.height(atX: newX, z: newZ)
        // Sit a touch into soft ground / pond edges.
        node.position = SCNVector3(newX, groundY - 0.04, newZ)

        if hypot(newX - pos.x, newZ - pos.z) > 0.01 {
            node.eulerAngles.y = atan2(dirX, dirZ)
        }

        swimPhase += deltaTime * 5.5
        bodyNode.position.y = bodyBaseY + sin(swimPhase) * 0.03
        bodyNode.eulerAngles.y = sin(swimPhase * 0.7) * 0.08
        jawNode.eulerAngles.x = 0.05 + abs(sin(swimPhase * 0.35)) * 0.12
    }

    private func pickNewTarget(
        trackHalfWidth: Float,
        waterSpots: [(x: Float, z: Float, radius: Float)],
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.35

        // Prefer shores: pond rims or the path edge where water begins.
        for _ in 0..<18 {
            let x: Float
            let z: Float
            if !forceEscape, let spot = nearbyWater(from: pos, waterSpots: waterSpots, rng: &rng) {
                let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
                let rim = spot.radius * Float.random(in: 0.75...1.15, using: &rng)
                x = max(-maxX, min(maxX, spot.x + cos(angle) * rim))
                z = spot.z + sin(angle) * rim + Float.random(in: -4...8, using: &rng)
            } else if !forceEscape, Float.random(in: 0...1, using: &rng) < 0.65 {
                // Hang along the left/right waterline.
                let side: Float = Bool.random(using: &rng) ? -1 : 1
                x = side * maxX * Float.random(in: 0.72...0.98, using: &rng)
                z = pos.z + Float.random(in: -14...20, using: &rng)
            } else {
                x = Float.random(in: (-maxX)...maxX, using: &rng)
                z = pos.z + Float.random(in: -10...16, using: &rng) * (forceEscape ? 1.4 : 1)
            }
            if hypot(x - pos.x, z - pos.z) < 3.5 { continue }
            targetX = x
            targetZ = z
            retargetTimer = Float.random(in: 2.2...4.8, using: &rng)
            return
        }

        let side: Float = Bool.random(using: &rng) ? -1 : 1
        targetX = side * maxX * 0.9
        targetZ = pos.z + Float.random(in: 8...16, using: &rng)
        retargetTimer = Float.random(in: 1.8...3.2, using: &rng)
    }

    private func nearbyWater(
        from pos: SCNVector3,
        waterSpots: [(x: Float, z: Float, radius: Float)],
        rng: inout some RandomNumberGenerator
    ) -> (x: Float, z: Float, radius: Float)? {
        let nearby = waterSpots.filter { hypot(pos.x - $0.x, pos.z - $0.z) < 55 }
        if let pick = nearby.randomElement(using: &rng) { return pick }
        return waterSpots.randomElement(using: &rng)
    }
}

final class AlligatorIndex {
    private var gators: [AlligatorActor] = []
    private var waterSpots: [(x: Float, z: Float, radius: Float, endZ: Float)] = []
    private var lastSpawnZ: Float = -180
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        gators.forEach { $0.node.removeFromParentNode() }
        gators.removeAll()
        waterSpots.removeAll()
        lastSpawnZ = -180
        rng = SystemRandomNumberGenerator()
    }

    func registerPonds(_ ponds: [(x: Float, z: Float, radius: Float)], chunkEndZ: Float) {
        for pond in ponds {
            waterSpots.append((pond.x, pond.z, pond.radius, chunkEndZ))
        }
    }

    func cull(beforeZ z: Float) {
        waterSpots.removeAll { $0.endZ < z }
        gators.removeAll { gator in
            if gator.node.position.z < z {
                gator.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    /// Roughly one alligator every ~380–500m, biased onto pond shores / water edges.
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float,
        ponds: [(x: Float, z: Float, radius: Float)]
    ) {
        let spacing = Float.random(in: 380...500, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        let maxX = trackHalfWidth - 1.6
        let x: Float
        let sz: Float
        if let pond = ponds.randomElement(using: &rng) {
            let angle = Float.random(in: 0...(Float.pi * 2), using: &rng)
            let rim = pond.radius * Float.random(in: 0.85...1.2, using: &rng)
            x = max(-maxX, min(maxX, pond.x + cos(angle) * rim))
            sz = pond.z + sin(angle) * rim * 0.35
        } else {
            let side: Float = Bool.random(using: &rng) ? -1 : 1
            x = side * maxX * Float.random(in: 0.78...0.96, using: &rng)
            sz = z + Float.random(in: -4...10, using: &rng)
        }

        let groundY = heightField.height(atX: x, z: sz)
        let built = AlligatorFactory.make(at: SCNVector3(x, groundY - 0.04, sz))
        parent.addChildNode(built.node)
        gators.append(
            AlligatorActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                startX: x,
                startZ: sz,
                body: built.body,
                bodyBaseY: built.bodyBaseY,
                jaw: built.jaw
            )
        )
        lastSpawnZ = z
    }

    func update(deltaTime: Float, heightField: HeightField, trackHalfWidth: Float) {
        let spots = waterSpots.map { (x: $0.x, z: $0.z, radius: $0.radius) }
        for gator in gators {
            gator.update(
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

        for gator in gators {
            let pos = gator.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = gator.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + gator.height && ballTop > pos.y else { continue }

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

enum AlligatorFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let body: SCNNode
        let bodyBaseY: Float
        let jaw: SCNNode
    }

    static func make(at position: SCNVector3) -> Built {
        let root = SCNNode()
        root.name = "alligator"
        root.position = position
        root.castsShadow = false

        let hide = SCNMaterial()
        hide.diffuse.contents = UIColor(red: 0.22, green: 0.38, blue: 0.20, alpha: 1)
        hide.lightingModel = .blinn
        hide.shininess = 0.2

        let belly = SCNMaterial()
        belly.diffuse.contents = UIColor(red: 0.55, green: 0.52, blue: 0.32, alpha: 1)
        belly.lightingModel = .lambert

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.08, alpha: 1)
        dark.lightingModel = .lambert

        let tooth = SCNMaterial()
        tooth.diffuse.contents = UIColor(red: 0.92, green: 0.90, blue: 0.82, alpha: 1)
        tooth.lightingModel = .lambert

        let bodyBaseY: Float = 0.28
        let body = SCNNode()
        body.position = SCNVector3(0, bodyBaseY, 0)
        root.addChildNode(body)

        let torso = SCNCapsule(capRadius: 0.28, height: 1.55)
        torso.radialSegmentCount = 10
        torso.firstMaterial = hide
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.eulerAngles.x = Float.pi / 2
        torsoNode.scale = SCNVector3(1.15, 0.75, 1.0)
        body.addChildNode(torsoNode)

        let bellyGeo = SCNCapsule(capRadius: 0.2, height: 1.2)
        bellyGeo.radialSegmentCount = 8
        bellyGeo.firstMaterial = belly
        let bellyNode = SCNNode(geometry: bellyGeo)
        bellyNode.eulerAngles.x = Float.pi / 2
        bellyNode.scale = SCNVector3(0.85, 0.55, 1)
        bellyNode.position = SCNVector3(0, -0.12, 0.05)
        body.addChildNode(bellyNode)

        let head = SCNNode()
        head.position = SCNVector3(0, 0.06, 0.95)
        body.addChildNode(head)

        let skull = SCNSphere(radius: 0.26)
        skull.segmentCount = 12
        skull.firstMaterial = hide
        let skullNode = SCNNode(geometry: skull)
        skullNode.scale = SCNVector3(0.95, 0.7, 1.35)
        head.addChildNode(skullNode)

        let jaw = SCNNode()
        jaw.position = SCNVector3(0, -0.06, 0.08)
        head.addChildNode(jaw)

        let snout = SCNBox(width: 0.34, height: 0.14, length: 0.7, chamferRadius: 0.04)
        snout.firstMaterial = hide
        let snoutNode = SCNNode(geometry: snout)
        snoutNode.position = SCNVector3(0, 0.02, 0.38)
        jaw.addChildNode(snoutNode)

        for side: Float in [-1, 1] {
            let eye = SCNSphere(radius: 0.045)
            eye.segmentCount = 6
            eye.firstMaterial = dark
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.14, 0.12, 0.18)
            head.addChildNode(eyeNode)

            // Ridge bumps along the back.
            for i in 0..<4 {
                let bump = SCNSphere(radius: 0.06)
                bump.segmentCount = 6
                bump.firstMaterial = hide
                let bumpNode = SCNNode(geometry: bump)
                bumpNode.position = SCNVector3(side * 0.1, 0.22, -0.15 + Float(i) * 0.28)
                body.addChildNode(bumpNode)
            }

            let toothGeo = SCNCone(topRadius: 0.01, bottomRadius: 0.025, height: 0.07)
            toothGeo.radialSegmentCount = 5
            toothGeo.firstMaterial = tooth
            let toothNode = SCNNode(geometry: toothGeo)
            toothNode.position = SCNVector3(side * 0.1, -0.02, 0.55)
            toothNode.eulerAngles.x = Float.pi
            jaw.addChildNode(toothNode)
        }

        let tail = SCNCone(topRadius: 0.02, bottomRadius: 0.2, height: 0.95)
        tail.radialSegmentCount = 8
        tail.firstMaterial = hide
        let tailNode = SCNNode(geometry: tail)
        tailNode.position = SCNVector3(0, 0.02, -1.15)
        tailNode.eulerAngles.x = Float.pi / 2 + 0.15
        body.addChildNode(tailNode)

        // Short stubby legs.
        let legOffsets: [(Float, Float)] = [
            (-0.32, 0.45),
            (0.32, 0.45),
            (-0.28, -0.35),
            (0.28, -0.35)
        ]
        for (lx, lz) in legOffsets {
            let leg = SCNCylinder(radius: 0.07, height: 0.22)
            leg.radialSegmentCount = 6
            leg.firstMaterial = hide
            let legNode = SCNNode(geometry: leg)
            legNode.position = SCNVector3(lx, -0.18, lz)
            body.addChildNode(legNode)
        }

        // 1.5× larger swamp gators.
        let scale: Float = 1.5
        root.scale = SCNVector3(scale, scale, scale)
        let hitRadius: Float = 1.15 * scale
        let hitHeight: Float = 0.85 * scale
        return Built(
            node: root,
            radius: hitRadius,
            height: hitHeight,
            body: body,
            bodyBaseY: bodyBaseY,
            jaw: jaw
        )
    }
}
