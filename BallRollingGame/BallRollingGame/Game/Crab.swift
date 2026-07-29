import Foundation
import SceneKit
import UIKit

enum CrabColor: CaseIterable {
    case red
    case orange
    case sand

    var shell: UIColor {
        switch self {
        case .red: return UIColor(red: 0.78, green: 0.22, blue: 0.18, alpha: 1)
        case .orange: return UIColor(red: 0.88, green: 0.48, blue: 0.18, alpha: 1)
        case .sand: return UIColor(red: 0.72, green: 0.55, blue: 0.36, alpha: 1)
        }
    }

    var claw: UIColor {
        switch self {
        case .red: return UIColor(red: 0.88, green: 0.32, blue: 0.22, alpha: 1)
        case .orange: return UIColor(red: 0.95, green: 0.58, blue: 0.22, alpha: 1)
        case .sand: return UIColor(red: 0.82, green: 0.64, blue: 0.42, alpha: 1)
        }
    }
}

final class CrabActor {
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
    private let bodyNode: SCNNode
    private let bodyBaseY: Float
    private let leftClaw: SCNNode
    private let rightClaw: SCNNode

    init(
        node: SCNNode,
        radius: Float,
        height: Float,
        startX: Float,
        startZ: Float,
        body: SCNNode,
        bodyBaseY: Float,
        leftClaw: SCNNode,
        rightClaw: SCNNode
    ) {
        self.node = node
        self.radius = radius
        self.height = height
        self.targetX = startX + 3
        self.targetZ = startZ
        self.retargetTimer = Float.random(in: 0.3...1.0)
        self.walkPhase = Float.random(in: 0...(Float.pi * 2))
        self.lastX = startX
        self.lastZ = startZ
        self.bodyNode = body
        self.bodyBaseY = bodyBaseY
        self.leftClaw = leftClaw
        self.rightClaw = rightClaw
    }

    func update(
        deltaTime: Float,
        heightField: HeightField,
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator
    ) {
        let dt = min(deltaTime, 1.0 / 20.0)
        retargetTimer -= dt
        if retargetTimer <= 0 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng)
        }

        let pos = node.position
        let dx = targetX - pos.x
        let dz = targetZ - pos.z
        let dist = hypot(dx, dz)
        if dist < 0.8 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng)
        }

        let moveDist = hypot(pos.x - lastX, pos.z - lastZ)
        stuckTimer = moveDist < 0.02 ? stuckTimer + dt : 0
        lastX = pos.x
        lastZ = pos.z
        if stuckTimer > 0.7 {
            stuckTimer = 0
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng, forceEscape: true)
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let speed: Float = 3.6
        let step = min(max(dist, 0.001), speed * dt)
        let maxX = trackHalfWidth - radius - 0.4
        let newX = max(-maxX, min(maxX, pos.x + dirX * step))
        let newZ = pos.z + dirZ * step
        let groundY = heightField.height(atX: newX, z: newZ)
        node.position = SCNVector3(newX, groundY, newZ)

        // Face sideways to the motion — crabs scuttle sideways.
        if hypot(newX - pos.x, newZ - pos.z) > 0.01 {
            node.eulerAngles.y = atan2(dirX, dirZ) + Float.pi / 2
        }

        walkPhase += dt * 12
        let bob = abs(sin(walkPhase)) * 0.04
        bodyNode.position.y = bodyBaseY + bob
        leftClaw.eulerAngles.z = 0.25 + sin(walkPhase) * 0.2
        rightClaw.eulerAngles.z = -0.25 - sin(walkPhase + 0.6) * 0.2
    }

    private func pickNewTarget(
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.4
        for _ in 0..<14 {
            // Prefer sideways sidesteps along the beach.
            let x: Float
            let z: Float
            if forceEscape || Bool.random(using: &rng) {
                x = max(-maxX, min(maxX, pos.x + Float.random(in: -10...10, using: &rng)))
                z = pos.z + Float.random(in: -4...8, using: &rng)
            } else {
                let side: Float = Bool.random(using: &rng) ? -1 : 1
                x = max(-maxX, min(maxX, pos.x + side * Float.random(in: 3...9, using: &rng)))
                z = pos.z + Float.random(in: -3...6, using: &rng)
            }
            if hypot(x - pos.x, z - pos.z) < 2.5 { continue }
            targetX = x
            targetZ = z
            retargetTimer = Float.random(in: 1.4...3.2, using: &rng)
            return
        }
        targetX = max(-maxX, min(maxX, pos.x + Float.random(in: -6...6, using: &rng)))
        targetZ = pos.z + Float.random(in: 4...10, using: &rng)
        retargetTimer = Float.random(in: 1.0...2.0, using: &rng)
    }
}

final class CrabIndex {
    private var crabs: [CrabActor] = []
    private var lastSpawnZ: Float = -100
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        crabs.forEach { $0.node.removeFromParentNode() }
        crabs.removeAll()
        lastSpawnZ = -100
        rng = SystemRandomNumberGenerator()
    }

    func cull(beforeZ z: Float) {
        crabs.removeAll { crab in
            if crab.node.position.z < z {
                crab.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    /// Beach crabs every ~220–320m.
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        let spacing = Float.random(in: 220...320, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        let maxX = trackHalfWidth * 0.42
        // Bias toward the water edges of the beach path.
        let side: Float = Bool.random(using: &rng) ? -1 : 1
        let x = side * Float.random(in: (maxX * 0.45)...maxX, using: &rng)
        let sz = z + Float.random(in: -5...12, using: &rng)
        let groundY = heightField.height(atX: x, z: sz)
        let color = CrabColor.allCases.randomElement(using: &rng) ?? .red
        let built = CrabFactory.make(at: SCNVector3(x, groundY, sz), color: color)
        parent.addChildNode(built.node)
        crabs.append(
            CrabActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                startX: x,
                startZ: sz,
                body: built.body,
                bodyBaseY: built.bodyBaseY,
                leftClaw: built.leftClaw,
                rightClaw: built.rightClaw
            )
        )
        lastSpawnZ = z
    }

    func update(deltaTime: Float, heightField: HeightField, trackHalfWidth: Float) {
        for crab in crabs {
            crab.update(
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

        for crab in crabs {
            let pos = crab.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = crab.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + crab.height && ballTop > pos.y else { continue }

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

enum CrabFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let body: SCNNode
        let bodyBaseY: Float
        let leftClaw: SCNNode
        let rightClaw: SCNNode
    }

    static func make(at position: SCNVector3, color: CrabColor) -> Built {
        let root = SCNNode()
        root.name = "crab"
        root.position = position
        root.castsShadow = false

        let shellMat = SCNMaterial()
        shellMat.diffuse.contents = color.shell
        shellMat.lightingModel = .blinn
        shellMat.shininess = 0.35

        let clawMat = SCNMaterial()
        clawMat.diffuse.contents = color.claw
        clawMat.lightingModel = .blinn

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.1, alpha: 1)
        dark.lightingModel = .lambert

        let bodyBaseY: Float = 0.32
        let body = SCNNode()
        body.position = SCNVector3(0, bodyBaseY, 0)
        root.addChildNode(body)

        let shell = SCNSphere(radius: 0.40)
        shell.segmentCount = 12
        shell.firstMaterial = shellMat
        let shellNode = SCNNode(geometry: shell)
        shellNode.scale = SCNVector3(1.35, 0.55, 1.05)
        body.addChildNode(shellNode)

        for side: Float in [-1, 1] {
            let eyeStalk = SCNCylinder(radius: 0.035, height: 0.22)
            eyeStalk.radialSegmentCount = 5
            eyeStalk.firstMaterial = shellMat
            let stalkNode = SCNNode(geometry: eyeStalk)
            stalkNode.position = SCNVector3(side * 0.17, 0.26, 0.22)
            body.addChildNode(stalkNode)

            let eye = SCNSphere(radius: 0.06)
            eye.segmentCount = 6
            eye.firstMaterial = dark
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(0, 0.14, 0)
            stalkNode.addChildNode(eyeNode)
        }

        func makeClaw(side: Float) -> SCNNode {
            let pivot = SCNNode()
            pivot.position = SCNVector3(side * 0.45, 0.03, 0.26)

            let arm = SCNCapsule(capRadius: 0.07, height: 0.40)
            arm.radialSegmentCount = 6
            arm.firstMaterial = clawMat
            let armNode = SCNNode(geometry: arm)
            armNode.eulerAngles.z = side * 1.1
            armNode.position = SCNVector3(side * 0.11, 0.03, 0)
            pivot.addChildNode(armNode)

            let pincer = SCNSphere(radius: 0.14)
            pincer.segmentCount = 8
            pincer.firstMaterial = clawMat
            let pincerNode = SCNNode(geometry: pincer)
            pincerNode.scale = SCNVector3(0.9, 0.55, 1.15)
            pincerNode.position = SCNVector3(side * 0.30, 0.03, 0.11)
            pivot.addChildNode(pincerNode)

            return pivot
        }

        let leftClaw = makeClaw(side: -1)
        let rightClaw = makeClaw(side: 1)
        // One bigger "fiddler" claw for character.
        rightClaw.scale = SCNVector3(1.25, 1.25, 1.25)
        body.addChildNode(leftClaw)
        body.addChildNode(rightClaw)

        // Little walking legs.
        for i in 0..<3 {
            for side: Float in [-1, 1] {
                let leg = SCNCapsule(capRadius: 0.035, height: 0.30)
                leg.radialSegmentCount = 5
                leg.firstMaterial = shellMat
                let legNode = SCNNode(geometry: leg)
                legNode.position = SCNVector3(side * 0.30, -0.11, -0.07 + Float(i) * 0.16)
                legNode.eulerAngles.z = side * 0.9
                legNode.eulerAngles.x = 0.35
                body.addChildNode(legNode)
            }
        }

        let hitRadius: Float = 0.78
        let hitHeight: Float = 0.78
        return Built(
            node: root,
            radius: hitRadius,
            height: hitHeight,
            body: body,
            bodyBaseY: bodyBaseY,
            leftClaw: leftClaw,
            rightClaw: rightClaw
        )
    }
}
