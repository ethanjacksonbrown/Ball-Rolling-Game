import Foundation
import SceneKit
import UIKit

enum CoinStore {
    private static let key = "totalCoins"

    static var total: Int {
        get { UserDefaults.standard.integer(forKey: key) }
        set { UserDefaults.standard.set(max(0, newValue), forKey: key) }
    }

    static func add(_ amount: Int) {
        guard amount > 0 else { return }
        total += amount
    }

    /// Spend coins if the wallet has enough. Returns false when insufficient.
    @discardableResult
    static func spend(_ amount: Int) -> Bool {
        guard amount > 0 else { return true }
        guard total >= amount else { return false }
        total -= amount
        return true
    }
}

final class CoinPickup {
    let node: SCNNode
    var x: Float
    var z: Float
    var y: Float
    let radius: Float
    let chunkEndZ: Float
    /// True once Coin Magnet locks onto this coin (keeps chasing until collected).
    var isAttracting = false
    var attractElapsed: Float = 0

    init(node: SCNNode, x: Float, z: Float, y: Float, radius: Float, chunkEndZ: Float) {
        self.node = node
        self.x = x
        self.z = z
        self.y = y
        self.radius = radius
        self.chunkEndZ = chunkEndZ
    }
}

final class CoinIndex {
    private var coins: [CoinPickup] = []

    /// Exponential chase rate (1/sec). Higher = snaps to the ball faster even at high speed.
    private let magnetCatchRate: Float = 14
    /// After this long locked on, guarantee the collect so coins never trail off-screen.
    private let magnetGuaranteeCollect: Float = 0.28

    func reset() {
        coins.forEach { $0.node.removeFromParentNode() }
        coins.removeAll()
    }

    func cull(beforeZ z: Float) {
        coins.removeAll { coin in
            // Don't cull coins the magnet already locked — they must finish collecting.
            if coin.isAttracting { return false }
            if coin.chunkEndZ < z {
                coin.node.removeFromParentNode()
                return true
            }
            return false
        }
    }

    func add(
        atX x: Float,
        z: Float,
        y: Float,
        chunkEndZ: Float,
        parent: SCNNode
    ) {
        let node = CoinFactory.make(at: SCNVector3(x, y + 0.55, z))
        parent.addChildNode(node)
        coins.append(
            CoinPickup(
                node: node,
                x: x,
                z: z,
                y: y + 0.55,
                radius: 0.55,
                chunkEndZ: chunkEndZ
            )
        )
    }

    /// Pulls coins in range when magnet is active; locked coins keep chasing until they hit.
    @discardableResult
    func collect(
        atX x: Float,
        y: Float,
        z: Float,
        ballRadius: Float,
        magnetReach: Float = 0,
        deltaTime: Float = 1.0 / 60.0
    ) -> Int {
        var collected = 0
        let contactReach = ballRadius + 0.55
        let contactReachSq = contactReach * contactReach
        let magnetReachSq = magnetReach > 0 ? magnetReach * magnetReach : Float(0)
        let dt = max(0, min(deltaTime, 0.05))

        coins.removeAll { coin in
            let dx0 = x - coin.x
            let dy0 = y - coin.y
            let dz0 = z - coin.z
            let horizSq0 = dx0 * dx0 + dz0 * dz0

            let inMagnetRange = magnetReach > 0 && horizSq0 <= magnetReachSq && abs(dy0) < 3.2
            if inMagnetRange || coin.isAttracting {
                if !coin.isAttracting {
                    coin.isAttracting = true
                    coin.attractElapsed = 0
                    coin.node.removeAllActions()
                }
                coin.attractElapsed += dt

                // Track the *current* ball position each frame so fast movement can't outrun coins.
                let blend = 1 - exp(-magnetCatchRate * dt)
                coin.x += (x - coin.x) * blend
                coin.y += (y - coin.y) * blend
                coin.z += (z - coin.z) * blend
                coin.node.position = SCNVector3(coin.x, coin.y, coin.z)

                // Guaranteed pickup after a short chase — never leave coins stranded behind.
                if coin.attractElapsed >= magnetGuaranteeCollect {
                    coin.node.removeFromParentNode()
                    collected += 1
                    return true
                }
            }

            let dx = x - coin.x
            let dy = y - coin.y
            let dz = z - coin.z
            let magnetContact = coin.isAttracting
            let reachSq = magnetContact ? (contactReach * 1.35) * (contactReach * 1.35) : contactReachSq
            guard dx * dx + dz * dz <= reachSq else { return false }
            let verticalSlack: Float = magnetContact ? 1.35 : 0.45
            guard abs(dy) <= ballRadius + verticalSlack else { return false }
            coin.node.removeFromParentNode()
            collected += 1
            return true
        }
        return collected
    }
}

enum CoinFactory {
    static func make(at position: SCNVector3) -> SCNNode {
        let root = SCNNode()
        root.name = "coin"
        root.position = position
        root.castsShadow = false

        let coin = SCNCylinder(radius: 0.32, height: 0.08)
        coin.radialSegmentCount = 16
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(red: 0.95, green: 0.78, blue: 0.18, alpha: 1)
        mat.emission.contents = UIColor(red: 0.95, green: 0.78, blue: 0.18, alpha: 0.35)
        mat.lightingModel = .blinn
        mat.shininess = 0.9
        mat.locksAmbientWithDiffuse = true
        coin.firstMaterial = mat

        let coinNode = SCNNode(geometry: coin)
        // Stand the coin upright like a collectible token.
        coinNode.eulerAngles.x = Float.pi / 2
        root.addChildNode(coinNode)

        let rim = SCNTorus(ringRadius: 0.32, pipeRadius: 0.035)
        rim.ringSegmentCount = 16
        rim.pipeSegmentCount = 8
        let rimMat = SCNMaterial()
        rimMat.diffuse.contents = UIColor(red: 0.85, green: 0.62, blue: 0.12, alpha: 1)
        rimMat.lightingModel = .blinn
        rim.firstMaterial = rimMat
        let rimNode = SCNNode(geometry: rim)
        rimNode.eulerAngles.x = Float.pi / 2
        root.addChildNode(rimNode)

        root.runAction(
            .repeatForever(
                .rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 2.2)
            )
        )
        root.runAction(
            .repeatForever(
                .sequence([
                    .moveBy(x: 0, y: 0.12, z: 0, duration: 0.7),
                    .moveBy(x: 0, y: -0.12, z: 0, duration: 0.7)
                ])
            )
        )

        return root
    }
}
