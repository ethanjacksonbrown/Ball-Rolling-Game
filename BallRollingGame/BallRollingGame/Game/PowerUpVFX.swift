import SceneKit
import UIKit

/// Visible SceneKit feedback for power-ups (player and bots).
final class PowerUpVFX {
    private weak var ballNode: SCNNode?
    private weak var worldRoot: SCNNode?
    private var ballRadius: Float = 0.55

    private var ghostShell: SCNNode?
    private var magnetHalo: SCNNode?
    private var speedAura: SCNNode?

    private var trailSpawnTimer: Float = 0
    private var activeTrailNodes: [SCNNode] = []
    private static let maxLiveTrails = 6
    private static let trailSpawnInterval: Float = 0.12
    private static let sharedTrailMaterial: SCNMaterial = {
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 0.85)
        mat.emission.contents = UIColor(red: 1.0, green: 0.4, blue: 0.05, alpha: 0.9)
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = false
        return mat
    }()

    private var savedEmission: Any?
    private var savedTransparency: CGFloat = 0
    private var materialTintActive = false

    func attach(to ballNode: SCNNode, worldRoot: SCNNode, radius: Float) {
        self.ballNode = ballNode
        self.worldRoot = worldRoot
        self.ballRadius = radius
    }

    func reset() {
        clearSustainedEffects()
        clearTrails()
        restoreBallMaterial()
        trailSpawnTimer = 0
    }

    /// One-shot burst when a power-up is activated.
    func playActivation(_ type: PowerUpType, pulseRadius: Float = 10) {
        switch type {
        case .slowPulse:
            spawnElectricPulse(radius: pulseRadius)
        case .speedBoost:
            spawnSpeedBurst()
        case .ghost:
            spawnGhostPoof()
        case .coinMagnet:
            spawnMagnetPing()
        }
    }

    /// Brief purple flash on a racer hit by Slow Pulse (readable even mid-air).
    func playSlowPulseHitFlash() {
        guard let ballNode else { return }
        let flash = makeShell(
            scale: 1.55,
            color: UIColor(red: 0.65, green: 0.4, blue: 1.0, alpha: 0.75),
            name: "slowPulseHit"
        )
        ballNode.addChildNode(flash)
        flash.runAction(
            .sequence([
                .group([
                    .scale(to: 2.1, duration: 0.35),
                    .fadeOut(duration: 0.35)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    /// Keep sustained visuals in sync with runtime state each frame.
    func update(
        deltaTime: Float,
        isSpeedBoost: Bool,
        isGhost: Bool,
        isMagnet: Bool
    ) {
        syncGhost(isGhost)
        syncMagnet(isMagnet)
        syncSpeedAura(isSpeedBoost)

        if isSpeedBoost {
            trailSpawnTimer -= deltaTime
            if trailSpawnTimer <= 0 {
                trailSpawnTimer = Self.trailSpawnInterval
                spawnSpeedTrailSegment()
            }
        } else {
            trailSpawnTimer = 0
        }

        // Cull finished trail nodes.
        activeTrailNodes.removeAll { node in
            if node.parent == nil {
                return true
            }
            return false
        }
    }

    // MARK: - Sustained

    private func syncGhost(_ active: Bool) {
        guard let ballNode else { return }
        if active {
            if ghostShell == nil {
                let shell = makeShell(
                    scale: 1.22,
                    color: UIColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 0.35),
                    name: "ghostShell"
                )
                ballNode.addChildNode(shell)
                ghostShell = shell
                shell.runAction(
                    .repeatForever(
                        .sequence([
                            .fadeOpacity(to: 0.25, duration: 0.35),
                            .fadeOpacity(to: 0.55, duration: 0.35)
                        ])
                    )
                )
            }
            applyGhostTint()
            ballNode.opacity = 0.55
        } else if ghostShell != nil {
            ghostShell?.removeAllActions()
            ghostShell?.removeFromParentNode()
            ghostShell = nil
            restoreBallMaterial()
            if ballNode.opacity > 0.3 {
                ballNode.opacity = 1
            }
        }
    }

    private func syncMagnet(_ active: Bool) {
        guard let ballNode else { return }
        if active {
            if magnetHalo == nil {
                let torus = SCNTorus(ringRadius: CGFloat(ballRadius * 1.7), pipeRadius: 0.06)
                torus.ringSegmentCount = 36
                torus.pipeSegmentCount = 10
                let mat = unlitMaterial(
                    color: UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 0.85),
                    emission: UIColor(red: 1.0, green: 0.8, blue: 0.15, alpha: 0.7)
                )
                torus.firstMaterial = mat
                let halo = SCNNode(geometry: torus)
                halo.name = "magnetHalo"
                halo.eulerAngles.x = .pi / 2
                ballNode.addChildNode(halo)
                magnetHalo = halo
                halo.runAction(
                    .repeatForever(.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 0.7))
                )
            }
        } else if magnetHalo != nil {
            magnetHalo?.removeAllActions()
            magnetHalo?.removeFromParentNode()
            magnetHalo = nil
        }
    }

    private func syncSpeedAura(_ active: Bool) {
        guard let ballNode else { return }
        if active {
            if speedAura == nil {
                let shell = makeShell(
                    scale: 1.1,
                    color: UIColor(red: 1.0, green: 0.55, blue: 0.12, alpha: 0.45),
                    name: "speedAura"
                )
                ballNode.addChildNode(shell)
                speedAura = shell
            }
            ballNode.geometry?.firstMaterial?.emission.contents = UIColor(
                red: 1.0, green: 0.45, blue: 0.1, alpha: 0.55
            )
        } else if speedAura != nil {
            speedAura?.removeAllActions()
            speedAura?.removeFromParentNode()
            speedAura = nil
            if ghostShell == nil {
                restoreBallMaterial()
            }
        }
    }

    // MARK: - One-shots

    private func spawnElectricPulse(radius: Float) {
        guard let worldRoot else { return }
        let origin = ballWorldPosition()
        // Keep geometry sized to the pulse — avoid huge SCNAction scales (can blow scene bounds).
        let pulseRadius = max(4, min(radius, 16))

        for i in 0..<2 {
            let delay = Double(i) * 0.09
            let ringRadius = CGFloat(pulseRadius) * (1.0 - CGFloat(i) * 0.1)
            let color: UIColor = i % 2 == 0
                ? UIColor(red: 0.55, green: 0.35, blue: 1.0, alpha: 0.95)
                : UIColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 0.9)
            // Two heights — readable from air without spawning a torus forest.
            for heightBoost: Float in [0.1, 1.1] {
                let ring = makePulseRing(ringRadius: ringRadius, color: color)
                ring.position = SCNVector3(origin.x, origin.y + heightBoost, origin.z)
                ring.scale = SCNVector3(0.12, 0.12, 0.12)
                ring.opacity = heightBoost < 0.5 ? 0.95 : 0.65
                worldRoot.addChildNode(ring)

                ring.runAction(
                    .sequence([
                        .wait(duration: delay),
                        .group([
                            .scale(to: 1.0, duration: 0.5),
                            .fadeOut(duration: 0.5)
                        ]),
                        .removeFromParentNode()
                    ])
                )
            }
        }

        spawnLightningSpokes(at: origin, radius: pulseRadius * 0.45, parent: worldRoot)
    }

    private func spawnLightningSpokes(at origin: SCNVector3, radius: Float, parent: SCNNode) {
        let spokeLength = max(2.5, min(radius, 7))
        let spokeCount = 4
        for s in 0..<spokeCount {
            let angle = Float(s) / Float(spokeCount) * Float.pi * 2
            let box = SCNBox(width: 0.07, height: 0.07, length: CGFloat(spokeLength), chamferRadius: 0)
            let mat = unlitMaterial(
                color: UIColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 0.9),
                emission: UIColor(red: 0.5, green: 0.75, blue: 1.0, alpha: 0.85)
            )
            box.firstMaterial = mat
            let spoke = SCNNode(geometry: box)
            spoke.position = origin
            spoke.eulerAngles.y = -angle
            // Grow outward from center without oversized pivots.
            spoke.pivot = SCNMatrix4MakeTranslation(0, 0, -spokeLength * 0.5)
            spoke.scale = SCNVector3(1, 1, 0.15)
            spoke.opacity = 0.9
            parent.addChildNode(spoke)
            spoke.runAction(
                .sequence([
                    .group([
                        .scale(to: 1.0, duration: 0.28),
                        .fadeOut(duration: 0.32)
                    ]),
                    .removeFromParentNode()
                ])
            )
        }
    }

    private func ballWorldPosition() -> SCNVector3 {
        guard let ballNode else { return SCNVector3Zero }
        // Prefer model position; presentation can be stale mid-air / mid-simulation.
        let world = ballNode.worldPosition
        if world.x.isFinite, world.y.isFinite, world.z.isFinite {
            return world
        }
        return ballNode.position
    }

    private func spawnSpeedBurst() {
        guard let ballNode else { return }
        let flash = makeShell(
            scale: 1.5,
            color: UIColor(red: 1.0, green: 0.6, blue: 0.15, alpha: 0.7),
            name: "speedBurst"
        )
        ballNode.addChildNode(flash)
        flash.runAction(
            .sequence([
                .group([
                    .scale(to: 2.2, duration: 0.28),
                    .fadeOut(duration: 0.28)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func spawnGhostPoof() {
        guard let ballNode else { return }
        let flash = makeShell(
            scale: 1.4,
            color: UIColor(red: 0.65, green: 0.9, blue: 1.0, alpha: 0.55),
            name: "ghostPoof"
        )
        ballNode.addChildNode(flash)
        flash.runAction(
            .sequence([
                .group([
                    .scale(to: 2.0, duration: 0.32),
                    .fadeOut(duration: 0.32)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func spawnMagnetPing() {
        guard let ballNode else { return }
        let torus = SCNTorus(ringRadius: CGFloat(ballRadius * 1.2), pipeRadius: 0.05)
        let mat = unlitMaterial(
            color: UIColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 0.9),
            emission: UIColor(red: 1.0, green: 0.8, blue: 0.1, alpha: 0.8)
        )
        torus.firstMaterial = mat
        let ping = SCNNode(geometry: torus)
        ping.eulerAngles.x = .pi / 2
        ballNode.addChildNode(ping)
        ping.runAction(
            .sequence([
                .group([
                    .scale(to: 2.4, duration: 0.4),
                    .fadeOut(duration: 0.4)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    private func spawnSpeedTrailSegment() {
        guard let worldRoot else { return }
        // Hard cap live trails so boosts can't flood the scene graph.
        if activeTrailNodes.count >= Self.maxLiveTrails {
            if let oldest = activeTrailNodes.first {
                oldest.removeAllActions()
                oldest.removeFromParentNode()
                activeTrailNodes.removeFirst()
            }
        }

        let pos = ballWorldPosition()
        let capsule = SCNCapsule(capRadius: 0.16, height: 0.85)
        capsule.firstMaterial = Self.sharedTrailMaterial

        let streak = SCNNode(geometry: capsule)
        streak.name = "speedTrail"
        streak.eulerAngles.x = .pi / 2
        streak.position = SCNVector3(pos.x, pos.y, pos.z - 0.35)
        streak.opacity = 0.85
        worldRoot.addChildNode(streak)
        activeTrailNodes.append(streak)

        streak.runAction(
            .sequence([
                .group([
                    .fadeOut(duration: 0.32),
                    .scale(to: 0.25, duration: 0.32),
                    .moveBy(x: 0, y: 0.04, z: -0.35, duration: 0.32)
                ]),
                .removeFromParentNode()
            ])
        )
    }

    // MARK: - Helpers

    private func makePulseRing(ringRadius: CGFloat, color: UIColor) -> SCNNode {
        let torus = SCNTorus(ringRadius: max(0.8, ringRadius), pipeRadius: 0.08)
        torus.ringSegmentCount = 24
        torus.pipeSegmentCount = 6
        torus.firstMaterial = unlitMaterial(color: color, emission: color)
        let node = SCNNode(geometry: torus)
        node.name = "slowPulseRing"
        node.eulerAngles.x = .pi / 2
        node.renderingOrder = 20
        return node
    }

    private func makeShell(scale: Float, color: UIColor, name: String) -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(ballRadius * scale))
        sphere.segmentCount = 20
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = color.withAlphaComponent(0.55)
        mat.transparent.contents = color
        mat.transparency = 0.55
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = false
        sphere.firstMaterial = mat
        let node = SCNNode(geometry: sphere)
        node.name = name
        node.renderingOrder = 10
        return node
    }

    private func unlitMaterial(color: UIColor, emission: UIColor) -> SCNMaterial {
        let mat = SCNMaterial()
        mat.diffuse.contents = color
        mat.emission.contents = emission
        mat.lightingModel = .constant
        mat.writesToDepthBuffer = false
        return mat
    }

    private func applyGhostTint() {
        guard let material = ballNode?.geometry?.firstMaterial else { return }
        if !materialTintActive {
            savedEmission = material.emission.contents
            savedTransparency = material.transparency
            materialTintActive = true
        }
        material.emission.contents = UIColor(red: 0.45, green: 0.85, blue: 1.0, alpha: 0.75)
        material.transparency = 0.35
        material.transparent.contents = UIColor(red: 0.7, green: 0.9, blue: 1.0, alpha: 0.5)
        material.blendMode = .alpha
    }

    private func restoreBallMaterial() {
        guard materialTintActive, let material = ballNode?.geometry?.firstMaterial else {
            ballNode?.geometry?.firstMaterial?.emission.contents = UIColor.black
            return
        }
        material.emission.contents = savedEmission ?? UIColor.black
        material.transparency = savedTransparency
        material.transparent.contents = UIColor.white
        material.blendMode = .alpha
        materialTintActive = false
        savedEmission = nil
    }

    private func clearSustainedEffects() {
        ghostShell?.removeAllActions()
        ghostShell?.removeFromParentNode()
        ghostShell = nil
        magnetHalo?.removeAllActions()
        magnetHalo?.removeFromParentNode()
        magnetHalo = nil
        speedAura?.removeAllActions()
        speedAura?.removeFromParentNode()
        speedAura = nil
    }

    private func clearTrails() {
        for node in activeTrailNodes {
            node.removeAllActions()
            node.removeFromParentNode()
        }
        activeTrailNodes.removeAll()
    }
}
