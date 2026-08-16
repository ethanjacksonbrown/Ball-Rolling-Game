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

struct CoinPickup {
    let node: SCNNode
    let x: Float
    let z: Float
    let y: Float
    let radius: Float
    let chunkEndZ: Float
}

final class CoinIndex {
    private var coins: [CoinPickup] = []

    func reset() {
        coins.forEach { $0.node.removeFromParentNode() }
        coins.removeAll()
    }

    func cull(beforeZ z: Float) {
        coins.removeAll { coin in
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

    /// Collect overlapping coins. Returns how many were picked up.
    /// `extraReach` extends horizontal pickup distance (Coin Magnet).
    @discardableResult
    func collect(atX x: Float, y: Float, z: Float, ballRadius: Float, extraReach: Float = 0) -> Int {
        var collected = 0
        coins.removeAll { coin in
            let dx = x - coin.x
            let dz = z - coin.z
            let reach = coin.radius + ballRadius + max(0, extraReach)
            guard dx * dx + dz * dz <= reach * reach else { return false }
            let ballBottom = y - ballRadius
            let ballTop = y + ballRadius
            let verticalSlack: Float = extraReach > 0.5 ? 2.5 : 0.4
            guard ballBottom < coin.y + 0.7 && ballTop > coin.y - verticalSlack else { return false }
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
