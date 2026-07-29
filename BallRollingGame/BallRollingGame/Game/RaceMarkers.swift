import SceneKit
import UIKit

enum RaceMarkers {
    /// Start / finish stripe spanning the track. Parent under trackRoot (not a chunk).
    static func makeLine(
        atZ z: Float,
        y: Float,
        width: Float,
        checkered: Bool
    ) -> SCNNode {
        let root = SCNNode()
        root.name = checkered ? "finishLine" : "startLine"
        root.position = SCNVector3(0, y, z)

        let length: Float = checkered ? 2.2 : 1.8
        let stripe = SCNBox(
            width: CGFloat(width),
            height: 0.12,
            length: CGFloat(length),
            chamferRadius: 0
        )
        let mat = SCNMaterial()
        // Tile so squares stay square across the wide track (not one stretched blotch).
        let cellsAcross = max(8, Int(width / 1.6))
        let cellsAlong = checkered ? 3 : 2
        // Classic race checkerboard for both start and finish.
        mat.diffuse.contents = checkeredTexture(light: .white, dark: .black)
        mat.diffuse.wrapS = .repeat
        mat.diffuse.wrapT = .repeat
        mat.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(cellsAcross), Float(cellsAlong), 1)
        mat.lightingModel = .lambert
        mat.locksAmbientWithDiffuse = true
        stripe.firstMaterial = mat

        let stripeNode = SCNNode(geometry: stripe)
        stripeNode.position = SCNVector3(0, 0.06, 0)
        root.addChildNode(stripeNode)

        // Side posts so the line reads from a distance.
        let postOffset = width * 0.5 - 0.4
        for side: Float in [-1, 1] {
            let post = SCNCylinder(radius: 0.28, height: 3.2)
            post.firstMaterial = GameArt.barkMaterial()
            let postNode = SCNNode(geometry: post)
            postNode.position = SCNVector3(side * postOffset, 1.6, 0)
            root.addChildNode(postNode)

            let flag = SCNBox(width: 1.2, height: 0.8, length: 0.08, chamferRadius: 0)
            let flagMat = SCNMaterial()
            flagMat.diffuse.contents = checkeredTexture(light: .white, dark: .black)
            flagMat.diffuse.wrapS = .repeat
            flagMat.diffuse.wrapT = .repeat
            flagMat.diffuse.contentsTransform = SCNMatrix4MakeScale(4, 3, 1)
            flagMat.lightingModel = .lambert
            flag.firstMaterial = flagMat
            let flagNode = SCNNode(geometry: flag)
            flagNode.position = SCNVector3(side * (postOffset - side * 0.7), 2.7, 0)
            root.addChildNode(flagNode)
        }

        return root
    }

    private static func checkeredTexture(light: UIColor, dark: UIColor) -> UIImage {
        let cells = 8
        let cell = 16
        let size = cells * cell
        UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return UIImage()
        }
        for row in 0..<cells {
            for col in 0..<cells {
                let isLight = (row + col) % 2 == 0
                ctx.setFillColor((isLight ? light : dark).cgColor)
                ctx.fill(CGRect(x: col * cell, y: row * cell, width: cell, height: cell))
            }
        }
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}
