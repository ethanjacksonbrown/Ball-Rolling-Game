import Foundation
import SceneKit
import UIKit

enum SeaTurtleColor: CaseIterable {
    case olive
    case green
    case brown

    var shell: UIColor {
        switch self {
        case .olive: return UIColor(red: 0.38, green: 0.48, blue: 0.28, alpha: 1)
        case .green: return UIColor(red: 0.28, green: 0.52, blue: 0.34, alpha: 1)
        case .brown: return UIColor(red: 0.48, green: 0.38, blue: 0.24, alpha: 1)
        }
    }

    var skin: UIColor {
        switch self {
        case .olive: return UIColor(red: 0.55, green: 0.62, blue: 0.40, alpha: 1)
        case .green: return UIColor(red: 0.45, green: 0.68, blue: 0.48, alpha: 1)
        case .brown: return UIColor(red: 0.62, green: 0.52, blue: 0.36, alpha: 1)
        }
    }
}

final class SeaTurtleActor {
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
    private let flippers: [SCNNode]

    init(
        node: SCNNode,
        radius: Float,
        height: Float,
        startX: Float,
        startZ: Float,
        body: SCNNode,
        bodyBaseY: Float,
        flippers: [SCNNode]
    ) {
        self.node = node
        self.radius = radius
        self.height = height
        self.targetX = startX
        self.targetZ = startZ + 5
        self.retargetTimer = Float.random(in: 0.4...1.2)
        self.walkPhase = Float.random(in: 0...(Float.pi * 2))
        self.lastX = startX
        self.lastZ = startZ
        self.bodyNode = body
        self.bodyBaseY = bodyBaseY
        self.flippers = flippers
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
        if dist < 1.0 {
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng)
        }

        let moveDist = hypot(pos.x - lastX, pos.z - lastZ)
        stuckTimer = moveDist < 0.015 ? stuckTimer + dt : 0
        lastX = pos.x
        lastZ = pos.z
        if stuckTimer > 0.9 {
            stuckTimer = 0
            pickNewTarget(trackHalfWidth: trackHalfWidth, rng: &rng, forceEscape: true)
        }

        let dirX = dx / max(dist, 0.001)
        let dirZ = dz / max(dist, 0.001)
        let speed: Float = 2.1
        let step = min(max(dist, 0.001), speed * dt)
        let maxX = trackHalfWidth - radius - 0.4
        let newX = max(-maxX, min(maxX, pos.x + dirX * step))
        let newZ = pos.z + dirZ * step
        let groundY = heightField.height(atX: newX, z: newZ)
        node.position = SCNVector3(newX, groundY, newZ)

        if hypot(newX - pos.x, newZ - pos.z) > 0.01 {
            node.eulerAngles.y = atan2(dirX, dirZ)
        }

        walkPhase += dt * 11
        let bob = abs(sin(walkPhase)) * 0.05
        bodyNode.position.y = bodyBaseY + bob
        bodyNode.eulerAngles.z = sin(walkPhase * 0.5) * 0.06
        for (i, flipper) in flippers.enumerated() {
            let phase = walkPhase + Float(i) * 0.85
            let side: Float = (i % 2 == 0) ? -1 : 1
            flipper.eulerAngles.x = sin(phase) * 0.75
            flipper.eulerAngles.z = side * (0.2 + cos(phase) * 0.45)
            flipper.eulerAngles.y = sin(phase * 1.3) * 0.25
        }
    }

    private func pickNewTarget(
        trackHalfWidth: Float,
        rng: inout some RandomNumberGenerator,
        forceEscape: Bool = false
    ) {
        let pos = node.position
        let maxX = trackHalfWidth - radius - 0.4
        for _ in 0..<12 {
            let x = max(-maxX, min(maxX, pos.x + Float.random(in: -8...8, using: &rng)))
            let zSpan: ClosedRange<Float> = forceEscape ? 4...12 : -3...9
            let z = pos.z + Float.random(in: zSpan, using: &rng)
            if hypot(x - pos.x, z - pos.z) < 2.2 { continue }
            targetX = x
            targetZ = z
            retargetTimer = Float.random(in: 2.0...4.0, using: &rng)
            return
        }
        targetX = max(-maxX, min(maxX, pos.x + Float.random(in: -5...5, using: &rng)))
        targetZ = pos.z + Float.random(in: 3...8, using: &rng)
        retargetTimer = Float.random(in: 1.5...2.5, using: &rng)
    }
}

final class SeaTurtleIndex {
    private var turtles: [SeaTurtleActor] = []
    private var lastSpawnZ: Float = -100
    private var rng = SystemRandomNumberGenerator()

    func reset() {
        turtles.forEach { $0.node.removeFromParentNode() }
        turtles.removeAll()
        lastSpawnZ = -100
        rng = SystemRandomNumberGenerator()
    }

    func cull(beforeZ z: Float) {
        turtles.removeAll { turtle in
            if turtle.node.position.z < z {
                turtle.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    /// Beach turtles every ~280–400m.
    func maybeSpawn(
        aroundZ z: Float,
        parent: SCNNode,
        heightField: HeightField,
        trackHalfWidth: Float
    ) {
        let spacing = Float.random(in: 280...400, using: &rng)
        guard z - lastSpawnZ >= spacing else { return }

        let maxX = trackHalfWidth * 0.4
        let x = Float.random(in: (-maxX)...maxX, using: &rng)
        let sz = z + Float.random(in: -5...12, using: &rng)
        let groundY = heightField.height(atX: x, z: sz)
        let color = SeaTurtleColor.allCases.randomElement(using: &rng) ?? .olive
        let built = SeaTurtleFactory.make(at: SCNVector3(x, groundY, sz), color: color)
        parent.addChildNode(built.node)
        turtles.append(
            SeaTurtleActor(
                node: built.node,
                radius: built.radius,
                height: built.height,
                startX: x,
                startZ: sz,
                body: built.body,
                bodyBaseY: built.bodyBaseY,
                flippers: built.flippers
            )
        )
        lastSpawnZ = z
    }

    func update(deltaTime: Float, heightField: HeightField, trackHalfWidth: Float) {
        for turtle in turtles {
            turtle.update(
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

        for turtle in turtles {
            let pos = turtle.node.position
            let dx = x - pos.x
            let dz = z - pos.z
            let minDist = turtle.radius + ballRadius
            let distSq = dx * dx + dz * dz
            guard distSq <= minDist * minDist else { continue }
            guard ballBottom < pos.y + turtle.height && ballTop > pos.y else { continue }

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

enum SeaTurtleFactory {
    struct Built {
        let node: SCNNode
        let radius: Float
        let height: Float
        let body: SCNNode
        let bodyBaseY: Float
        let flippers: [SCNNode]
    }

    static func make(at position: SCNVector3, color: SeaTurtleColor) -> Built {
        let root = SCNNode()
        root.name = "seaTurtle"
        root.position = position
        root.castsShadow = false

        let shellMat = SCNMaterial()
        shellMat.diffuse.contents = color.shell
        shellMat.lightingModel = .blinn
        shellMat.shininess = 0.4

        let skinMat = SCNMaterial()
        skinMat.diffuse.contents = color.skin
        skinMat.lightingModel = .blinn

        let dark = SCNMaterial()
        dark.diffuse.contents = UIColor(white: 0.12, alpha: 1)
        dark.lightingModel = .lambert

        let bodyBaseY: Float = 0.42
        let body = SCNNode()
        body.position = SCNVector3(0, bodyBaseY, 0)
        root.addChildNode(body)

        let shell = SCNSphere(radius: 0.72)
        shell.segmentCount = 12
        shell.firstMaterial = shellMat
        let shellNode = SCNNode(geometry: shell)
        shellNode.scale = SCNVector3(1.25, 0.55, 1.45)
        body.addChildNode(shellNode)

        // Shell plate accents.
        for i in 0..<3 {
            let plate = SCNBox(width: 0.34, height: 0.09, length: 0.42, chamferRadius: 0.05)
            plate.firstMaterial = shellMat
            let plateNode = SCNNode(geometry: plate)
            plateNode.position = SCNVector3(0, 0.34, -0.18 + Float(i) * 0.24)
            plateNode.eulerAngles.x = -0.15
            body.addChildNode(plateNode)
        }

        let head = SCNSphere(radius: 0.24)
        head.segmentCount = 8
        head.firstMaterial = skinMat
        let headNode = SCNNode(geometry: head)
        headNode.scale = SCNVector3(0.9, 0.75, 1.2)
        headNode.position = SCNVector3(0, 0.08, 0.95)
        body.addChildNode(headNode)

        for side: Float in [-1, 1] {
            let eye = SCNSphere(radius: 0.055)
            eye.segmentCount = 6
            eye.firstMaterial = dark
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.position = SCNVector3(side * 0.11, 0.07, 0.14)
            headNode.addChildNode(eyeNode)
        }

        var flipperNodes: [SCNNode] = []
        func makeFlipper(side: Float, z: Float, scale: Float) -> SCNNode {
            let pivot = SCNNode()
            pivot.position = SCNVector3(side * 0.55 * scale, -0.1, z)
            body.addChildNode(pivot)

            let flipper = SCNSphere(radius: 0.24)
            flipper.segmentCount = 8
            flipper.firstMaterial = skinMat
            let node = SCNNode(geometry: flipper)
            node.scale = SCNVector3(1.45 * scale, 0.3 * scale, 0.75 * scale)
            node.position = SCNVector3(side * 0.2 * scale, 0, 0)
            node.eulerAngles.z = side * 0.25
            pivot.addChildNode(node)
            return pivot
        }

        flipperNodes.append(makeFlipper(side: -1, z: 0.28, scale: 1.15))
        flipperNodes.append(makeFlipper(side: 1, z: 0.28, scale: 1.15))
        flipperNodes.append(makeFlipper(side: -1, z: -0.48, scale: 0.9))
        flipperNodes.append(makeFlipper(side: 1, z: -0.48, scale: 0.9))

        let hitRadius: Float = 1.2
        let hitHeight: Float = 1.0
        return Built(
            node: root,
            radius: hitRadius,
            height: hitHeight,
            body: body,
            bodyBaseY: bodyBaseY,
            flippers: flipperNodes
        )
    }
}
