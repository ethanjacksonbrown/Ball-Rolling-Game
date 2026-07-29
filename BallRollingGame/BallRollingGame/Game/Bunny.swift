import Foundation
import SceneKit
import UIKit

enum BunnyColor: CaseIterable {
    case gray
    case white
    case beige

    var fur: UIColor {
        switch self {
        case .gray: return UIColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 1)
        case .white: return UIColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)
        case .beige: return UIColor(red: 0.82, green: 0.72, blue: 0.55, alpha: 1)
        }
    }
}

final class BunnyActor {
    let node: SCNNode
    let radius: Float
    let height: Float
    private var targetX: Float
    private var targetZ: Float
    private var retargetTimer: Float
    private var hopPhase: Float
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
        self.targetZ = startZ + 6
        self.retargetTimer = Float.random(in: 0.2...0.8)
        self.hopPhase = Float.random(in: 0...(Float.pi * 2))
        self.lastX = startX
        self.lastZ = startZ
        self.bodyNode = body
        self.bodyBaseY = bodyBaseY
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
        if dist < 0.9 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng)
        }

        let moveDist = hypot(pos.x - lastX, pos.z - lastZ)
        stuckTimer = moveDist < 0.02 ? stuckTimer + deltaTime : 0
        lastX = pos.x
        lastZ = pos.z
        if stuckTimer > 0.6 {
            stuckTimer = 0
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng, forceEscape: true)
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let speed: Float = 5.2
        let step = min(max(dist, 0.001), speed * deltaTime)
        let maxX = trackHalfWidth - radius - 0.4
        let newX = max(-maxX, min(maxX, pos.x + dirX * step))
        let newZ = pos.z + dirZ * step
        let groundY = heightField.height(atX: newX, z: newZ)
        node.position = SCNVector3(newX, groundY, newZ)

        if hypot(newX - pos.x, newZ - pos.z) > 0.01 {
            node.eulerAngles.y = atan2(dirX, dirZ)
        }

        hopPhase += deltaTime * 14
        let hop = abs(sin(hopPhase))
        bodyNode.position.y = bodyBaseY + hop * 0.12
        bodyNode.eulerAngles.x = -hop * 0.15
    }

    private func pickNewTarget(
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.4
        for _ in 0..<14 {
            let x = Float.random(in: (-maxX)...maxX, using: &rng)
            let zOffset = forceEscape
                ? Float.random(in: 6...16, using: &rng) * (Bool.random(using: &rng) ? 1 : -1)
                : Float.random(in: -12...18, using: &rng)
            let z = pos.z + zOffset
            if hypot(x - pos.x, z - pos.z) < 3.5 { continue }
            targetX = x
            targetZ = z
            retargetTimer = Float.random(in: 1.2...2.8, using: &rng)
            return
        }
        targetX = max(-maxX, min(maxX, pos.x + Float.random(in: -8...8, using: &rng)))
        targetZ = pos.z + Float.random(in: 6...14, using: &rng)
        retargetTimer = Float.random(in: 1.0...2.2, using: &rng)
    }
}

final class BunnyIndex {
    private var bunnies: [BunnyActor] = []
    private var lastSpawnZ: Float = -120
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        bunnies.forEach { $0.node.removeFromParentNode() }
        bunnies.removeAll()
        lastSpawnZ = -120
        rng = SystemRandomNumberGenerator()
    }

    func cull(beforeZ z: Float) {
        bunnies.removeAll { bunny in
            if bunny.node.position.z < z {
                bunny.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    /// Slightly more frequent than brown bears (~500m) — about every 320–420m.
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        let spacing = Float.random(in: 320...420, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        let maxX = trackHalfWidth * 0.42
        let x = Float.random(in: (-maxX)...maxX, using: &rng)
        let sz = z + Float.random(in: -5...12, using: &rng)
        let groundY = heightField.height(atX: x, z: sz)
        let color = BunnyColor.allCases.randomElement(using: &rng) ?? .gray
        let built = BunnyFactory.make(at: SCNVector3(x, groundY, sz), color: color)
        parent.addChildNode(built.node)
        bunnies.append(
            BunnyActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                startX: x,
                startZ: sz,
                body: built.body,
                bodyBaseY: built.bodyBaseY
            )
        )
        lastSpawnZ = z
    }

    func update(deltaTime: Float, heightField: HeightField, trackHalfWidth: Float) {
        for bunny in bunnies {
            bunny.update(
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

        for bunny in bunnies {
            let pos = bunny.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = bunny.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + bunny.height && ballTop > pos.y else { continue }

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

enum BunnyFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let body: SCNNode
        let bodyBaseY: Float
    }

    /// Small hopping rabbit — clearly smaller than forest brown bears.
    static func make(at position: SCNVector3, color: BunnyColor) -> Built {
        let root = SCNNode()
        root.name = "bunny"
        root.position = position
        root.castsShadow = false

        let fur = SCNMaterial()
        fur.diffuse.contents = color.fur
        fur.lightingModel = .blinn
        fur.shininess = 0.15

        let pink = SCNMaterial()
        pink.diffuse.contents = UIColor(red: 0.92, green: 0.62, blue: 0.68, alpha: 1)
        pink.lightingModel = .lambert

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.1, alpha: 1)
        dark.lightingModel = .lambert

        let bodyBaseY: Float = 0.38
        let body = SCNNode()
        body.position = SCNVector3(0, bodyBaseY, 0)
        root.addChildNode(body)

        let torso = SCNSphere(radius: 0.28)
        torso.segmentCount = 12
        torso.firstMaterial = fur
        let torsoNode = SCNNode(geometry: torso)
        torsoNode.scale = SCNVector3(0.9, 0.85, 1.25)
        body.addChildNode(torsoNode)

        let head = SCNSphere(radius: 0.2)
        head.segmentCount = 12
        head.firstMaterial = fur
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, 0.18, 0.28)
        body.addChildNode(headNode)

        for side: Float in [-1, 1] {
            let ear = SCNCapsule(capRadius: 0.045, height: 0.32)
            ear.radialSegmentCount = 6
            ear.firstMaterial = fur
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(side * 0.08, 0.28, 0.02)
            earNode.eulerAngles.z = side * 0.12
            headNode.addChildNode(earNode)

            let inner = SCNCapsule(capRadius: 0.025, height: 0.2)
            inner.radialSegmentCount = 5
            inner.firstMaterial = pink
            let innerNode = SCNNode(geometry: inner)
            innerNode.position = SCNVector3(0, 0.02, 0.02)
            earNode.addChildNode(innerNode)

            let eye = SCNSphere(radius: 0.03)
            eye.segmentCount = 6
            eye.firstMaterial = dark
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.09, 0.04, 0.16)
            headNode.addChildNode(eyeNode)
        }

        let nose = SCNSphere(radius: 0.035)
        nose.segmentCount = 6
        nose.firstMaterial = pink
        let noseNode = SCNNode(geometry: nose)
        noseNode.position = SCNVector3(0, -0.02, 0.2)
        headNode.addChildNode(noseNode)

        // Tiny back feet.
        for side: Float in [-1, 1] {
            let foot = SCNSphere(radius: 0.08)
            foot.segmentCount = 8
            foot.firstMaterial = fur
            let footNode = SCNNode(geometry: foot)
            footNode.scale = SCNVector3(0.7, 0.45, 1.1)
            footNode.position = SCNVector3(side * 0.12, -0.28, -0.12)
            body.addChildNode(footNode)
        }

        // Fluffy tail.
        let tail = SCNSphere(radius: 0.09)
        tail.segmentCount = 8
        tail.firstMaterial = fur
        let tailNode = SCNNode(geometry: tail)
        tailNode.position = SCNVector3(0, 0.05, -0.32)
        body.addChildNode(tailNode)

        // Smaller than brown bears (radius ~1.85).
        let hitRadius: Float = 0.55
        let hitHeight: Float = 0.85
        return Built(
            node: root,
            radius: hitRadius,
            height: hitHeight,
            body: body,
            bodyBaseY: bodyBaseY
        )
    }
}
