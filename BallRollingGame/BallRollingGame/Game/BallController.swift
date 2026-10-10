import SceneKit
import UIKit

final class BallController {
    let node: SCNNode
    let radius: Float = 0.55
    let displayName: String
    let isPlayer: Bool

    static let surfaceY: Float = 0

    private(set) var isAlive = true
    private(set) var hasFinished = false
    private var verticalVelocity: Float = 0
    private var bounceVX: Float = 0
    private var bounceVZ: Float = 0
    private(set) var isAirborne = false
    private var previousGroundY: Float = 0
    private var geyserCooldown: Float = 0
    private let powerUpVFX = PowerUpVFX()

    var position: SCNVector3 {
        node.position
    }

    init(name: String, isPlayer: Bool, material: SCNMaterial) {
        self.displayName = name
        self.isPlayer = isPlayer

        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = 24
        sphere.firstMaterial = material

        node = SCNNode(geometry: sphere)
        node.name = isPlayer ? "ball" : "bot"
        node.position = SCNVector3(0, Self.surfaceY + radius, 0)
    }

    func attachPowerUpVFX(worldRoot: SCNNode) {
        powerUpVFX.attach(to: node, worldRoot: worldRoot, radius: radius)
    }

    func applySkin(_ skin: BallSkin) {
        guard isPlayer else { return }
        node.geometry?.firstMaterial = GameArt.ballMaterial(for: skin)
        node.geometry?.firstMaterial?.emission.contents = UIColor.black
    }

    func applyMaterial(_ material: SCNMaterial) {
        node.geometry?.firstMaterial = material
        node.geometry?.firstMaterial?.emission.contents = UIColor.black
    }

    func prepareForReady(atX x: Float = 0) {
        node.isHidden = false
        node.opacity = 1
        node.position = SCNVector3(x, Self.surfaceY + radius, 0)
        node.eulerAngles = SCNVector3Zero
        resetMotionState()
        isAlive = true
        hasFinished = false
    }

    func beginPlaying(atX x: Float, startZ: Float = 0) {
        node.isHidden = false
        node.opacity = 1
        node.position = SCNVector3(x, Self.surfaceY + radius, startZ)
        resetMotionState()
        powerUpVFX.reset()
        isAlive = true
        hasFinished = false
    }

    func freeze() {
        verticalVelocity = 0
        bounceVX = 0
        bounceVZ = 0
        isAirborne = false
    }

    func eliminate() {
        guard isAlive else { return }
        isAlive = false
        freeze()
        powerUpVFX.reset()
        node.opacity = 0.35
    }

    func markFinished() {
        guard !hasFinished else { return }
        hasFinished = true
        node.opacity = 1
    }

    func parkAtFinish(z: Float) {
        node.position.z = z
    }

    func hide() {
        powerUpVFX.reset()
        node.isHidden = true
        isAlive = false
        hasFinished = false
        freeze()
    }

    /// Fling upward from an erupting lava geyser.
    func launchFromGeyser(impulse: Float) {
        guard isAlive else { return }
        isAirborne = true
        verticalVelocity = max(verticalVelocity, impulse)
        geyserCooldown = 0.75
    }

    /// Solid bounce off trees/rocks/bears — push out and rebound so you must go around.
    func resolveSolidContact(
        _ hit: ObstacleContact,
        trackHalfWidth: Float
    ) {
        guard isAlive else { return }

        node.position.x += hit.normalX * hit.overlap
        node.position.z += hit.normalZ * hit.overlap

        let bounce: Float = 13
        bounceVX = hit.normalX * bounce
        bounceVZ = hit.normalZ * bounce

        let maxX = trackHalfWidth - radius - 0.08
        node.position.x = max(-maxX, min(maxX, node.position.x))
    }

    /// Resolve overlaps against solid props (trees, rocks, polar bears).
    func resolveSolidObstacles(
        obstacles: ObstacleIndex,
        polarBears: PolarBearIndex,
        moose: MooseIndex,
        brownBears: BrownBearIndex,
        bunnies: BunnyIndex,
        alligators: AlligatorIndex,
        frogs: FrogIndex,
        lavaLizards: LavaLizardIndex,
        crabs: CrabIndex,
        seaTurtles: SeaTurtleIndex,
        trackHalfWidth: Float
    ) {
        guard isAlive else { return }

        for _ in 0..<4 {
            let pos = node.position
            let hit =
                obstacles.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? polarBears.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? moose.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? brownBears.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? bunnies.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? alligators.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? frogs.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? lavaLizards.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? crabs.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
                ?? seaTurtles.deepestContact(x: pos.x, y: pos.y, z: pos.z, ballRadius: radius)
            guard let hit else { break }
            resolveSolidContact(hit, trackHalfWidth: trackHalfWidth)
        }
    }

    func playPowerUpActivation(_ type: PowerUpType, pulseRadius: Float = 10) {
        powerUpVFX.playActivation(type, pulseRadius: pulseRadius)
    }

    func playSlowPulseHitFlash() {
        powerUpVFX.playSlowPulseHitFlash()
    }

    func updatePowerUpVFX(
        deltaTime: Float,
        isSpeedBoost: Bool,
        isGhost: Bool,
        isMagnet: Bool
    ) {
        guard isAlive else { return }
        powerUpVFX.update(
            deltaTime: deltaTime,
            isSpeedBoost: isSpeedBoost,
            isGhost: isGhost,
            isMagnet: isMagnet
        )
    }

    func applyMovement(
        lateral: Float,
        forwardSpeed: Float,
        deltaTime: Float,
        trackHalfWidth: Float,
        heightField: HeightField,
        speedScale: Float = 1
    ) {
        guard isAlive else { return }

        if geyserCooldown > 0 {
            geyserCooldown = max(0, geyserCooldown - deltaTime)
        }

        // Bounce impulse fades so steering recovers quickly after a hit.
        bounceVX *= max(0, 1 - deltaTime * 5.5)
        bounceVZ *= max(0, 1 - deltaTime * 5.5)

        let steerSpeed: Float = 20
        let gravity: Float = 28
        let current = node.position
        let scaledForward = forwardSpeed * speedScale

        var newX = current.x + lateral * steerSpeed * deltaTime + bounceVX * deltaTime
        let newZ = current.z + scaledForward * deltaTime + bounceVZ * deltaTime

        let maxX = trackHalfWidth - radius - 0.08
        if newX > maxX {
            newX = maxX
            bounceVX = min(0, bounceVX)
        } else if newX < -maxX {
            newX = -maxX
            bounceVX = max(0, bounceVX)
        }

        let heightAtNew = heightField.height(atX: newX, z: newZ)
        let heightAtOldX = heightField.height(atX: current.x, z: newZ)
        let maxStepUp = max(0.45, max(scaledForward, 4) * deltaTime * 0.85)

        if !isAirborne {
            if heightAtNew > previousGroundY + maxStepUp && heightAtNew > heightAtOldX + 0.35 {
                newX = current.x
            }

            let groundY = heightField.height(atX: newX, z: newZ)
            let groundAhead = heightField.height(atX: newX, z: newZ + 1.5)

            if groundY < previousGroundY - 0.55 {
                isAirborne = true
                verticalVelocity = min(verticalVelocity, -1.5)
                let newY = current.y + verticalVelocity * deltaTime
                previousGroundY = groundY
                node.position = SCNVector3(newX, newY, newZ)
                node.eulerAngles.x -= scaledForward * deltaTime / radius
                node.eulerAngles.z = -lateral * 0.35
                return
            }

            let targetY = groundY + radius
            let dropAhead = groundY - groundAhead
            let lipLaunch =
                previousGroundY > 1.0
                && groundY > 1.0
                && dropAhead > 0.55
                && groundAhead < groundY - 0.5
                && scaledForward > 12

            if lipLaunch {
                isAirborne = true
                verticalVelocity = min(14, 4.5 + scaledForward * 0.22)
                previousGroundY = groundY
                node.position = SCNVector3(newX, targetY + 0.02, newZ)
            } else {
                verticalVelocity = 0
                previousGroundY = groundY
                node.position = SCNVector3(newX, targetY, newZ)
            }
        } else {
            verticalVelocity -= gravity * deltaTime
            var newY = current.y + verticalVelocity * deltaTime

            let groundY = heightField.height(atX: newX, z: newZ)
            let targetY = groundY + radius

            if groundY > current.y + 0.4 && groundY > heightAtOldX + 0.4 {
                newX = current.x
                let groundRetry = heightField.height(atX: newX, z: newZ)
                let targetRetry = groundRetry + radius
                if newY <= targetRetry && verticalVelocity <= 0 {
                    newY = targetRetry
                    isAirborne = false
                    verticalVelocity = 0
                    previousGroundY = groundRetry
                }
            } else if newY <= targetY && verticalVelocity <= 0 {
                newY = targetY
                isAirborne = false
                verticalVelocity = 0
                previousGroundY = groundY
            }

            node.position = SCNVector3(newX, newY, newZ)
        }

        node.eulerAngles.x -= scaledForward * deltaTime / radius
        node.eulerAngles.z = -lateral * 0.35
    }

    var canLaunchFromGeyser: Bool { isAlive && geyserCooldown <= 0 }

    private func resetMotionState() {
        verticalVelocity = 0
        bounceVX = 0
        bounceVZ = 0
        isAirborne = false
        previousGroundY = Self.surfaceY
        geyserCooldown = 0
    }
}
