import SceneKit
import UIKit

struct PlacedObstacle {
    let node: SCNNode
    /// Horizontal collision radius (matches solid trunk / rock body, not canopy).
    let radius: Float
    let height: Float
}

enum ObstacleFactory {
    /// Angular rock planted into the ground — returns matching collision size.
    static func makeRock(
        at position: SCNVector3,
        sizeRange: ClosedRange<CGFloat> = 0.7...1.4,
        color: UIColor? = nil
    ) -> PlacedObstacle {
        let size = CGFloat.random(in: sizeRange)
        let root = SCNNode()
        root.name = "obstacle"
        // Sink slightly so the rock sits in the grass instead of hovering on slopes.
        root.position = SCNVector3(position.x, position.y - 0.12, position.z)
        root.castsShadow = false

        let tint = color ?? UIColor(
            red: CGFloat.random(in: 0.42...0.55),
            green: CGFloat.random(in: 0.40...0.52),
            blue: CGFloat.random(in: 0.38...0.48),
            alpha: 1
        )
        let material = GameArt.rockMaterial(tint: tint)

        // Slightly uneven proportions so rocks don't look like identical boxes.
        let width = size * CGFloat.random(in: 0.75...1.35)
        let height = size * CGFloat.random(in: 0.48...0.95)
        let depth = size * CGFloat.random(in: 0.65...1.25)
        let rock = SCNBox(
            width: width,
            height: height,
            length: depth,
            chamferRadius: min(width, height, depth) * CGFloat.random(in: 0.18...0.38)
        )
        rock.firstMaterial = material
        let rockNode = SCNNode(geometry: rock)
        rockNode.position = SCNVector3(0, Float(height) * 0.5, 0)
        rockNode.scale = SCNVector3(
            Float.random(in: 0.88...1.12),
            Float.random(in: 0.82...1.15),
            Float.random(in: 0.88...1.12)
        )
        rockNode.eulerAngles = SCNVector3(
            Float.random(in: -0.22...0.22),
            Float.random(in: 0...(Float.pi * 2)),
            Float.random(in: -0.18...0.18)
        )
        root.addChildNode(rockNode)

        // Extra chunks / rounded nubs for an irregular silhouette.
        let nubCount = Int.random(in: 1...3)
        for _ in 0..<nubCount {
            let s = size * CGFloat.random(in: 0.28...0.62)
            let nubNode: SCNNode
            if Bool.random() {
                let nub = SCNBox(
                    width: s * CGFloat.random(in: 0.8...1.2),
                    height: s * CGFloat.random(in: 0.55...0.9),
                    length: s * CGFloat.random(in: 0.8...1.2),
                    chamferRadius: s * 0.28
                )
                nub.firstMaterial = material
                nubNode = SCNNode(geometry: nub)
            } else {
                let nub = SCNSphere(radius: s * 0.45)
                nub.segmentCount = 8
                nub.firstMaterial = material
                nubNode = SCNNode(geometry: nub)
                nubNode.scale = SCNVector3(
                    Float.random(in: 0.9...1.3),
                    Float.random(in: 0.55...0.85),
                    Float.random(in: 0.9...1.3)
                )
            }
            nubNode.position = SCNVector3(
                Float.random(in: -0.35...0.35) * Float(size),
                Float(s) * Float.random(in: 0.25...0.55),
                Float.random(in: -0.35...0.35) * Float(size)
            )
            nubNode.eulerAngles = SCNVector3(
                Float.random(in: -0.3...0.3),
                Float.random(in: 0...(Float.pi * 2)),
                Float.random(in: -0.3...0.3)
            )
            root.addChildNode(nubNode)
        }

        let hitRadius = Float(max(width, depth)) * 0.42
        let hitHeight = Float(height) * 0.95
        return PlacedObstacle(node: root, radius: hitRadius, height: hitHeight)
    }

    static func makeTree(at position: SCNVector3, scorched: Bool = false) -> PlacedObstacle {
        let root = SCNNode()
        root.name = "obstacle"
        root.position = SCNVector3(position.x, position.y - 0.04, position.z)
        root.castsShadow = false

        let trunkHeight = CGFloat.random(in: 2.0...3.0)
        let trunkBottom = CGFloat.random(in: 0.28...0.40)
        let trunkTop = trunkBottom * CGFloat.random(in: 0.55...0.7)

        let trunk = SCNCone(topRadius: trunkTop, bottomRadius: trunkBottom, height: trunkHeight)
        trunk.radialSegmentCount = 10
        trunk.firstMaterial = GameArt.barkMaterial(scorched: scorched)
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, Float(trunkHeight) * 0.5, 0)
        root.addChildNode(trunkNode)

        let flare = SCNCylinder(radius: trunkBottom * 1.35, height: 0.18)
        flare.radialSegmentCount = 8
        flare.firstMaterial = GameArt.barkMaterial(scorched: scorched)
        let flareNode = SCNNode(geometry: flare)
        flareNode.position = SCNVector3(0, 0.08, 0)
        root.addChildNode(flareNode)

        if scorched {
            let char = GameArt.barkMaterial(scorched: true)
            let stump = SCNSphere(radius: trunkTop * 1.6)
            stump.segmentCount = 10
            stump.firstMaterial = GameArt.rockMaterial(tint: UIColor(white: 0.12, alpha: 1))
            let stumpNode = SCNNode(geometry: stump)
            stumpNode.position = SCNVector3(0, Float(trunkHeight) + 0.1, 0)
            stumpNode.scale = SCNVector3(1, 0.55, 1)
            root.addChildNode(stumpNode)

            // A couple of short, broken limbs — dead wood, nothing green left.
            let branchCount = Int.random(in: 2...3)
            for i in 0..<branchCount {
                let branchLen = CGFloat.random(in: 0.35...0.65)
                let branch = SCNCylinder(
                    radius: trunkTop * CGFloat.random(in: 0.35...0.55),
                    height: branchLen
                )
                branch.radialSegmentCount = 6
                branch.firstMaterial = char
                let branchNode = SCNNode(geometry: branch)
                let side: Float = (i % 2 == 0) ? -1 : 1
                let attachY = Float(trunkHeight) * Float.random(in: 0.45...0.82)
                branchNode.position = SCNVector3(
                    side * Float(trunkBottom) * 0.35,
                    attachY,
                    Float.random(in: -0.08...0.08)
                )
                // Stick mostly sideways with a slight upward / downward break.
                branchNode.eulerAngles.z = side * Float.random(in: 1.05...1.35)
                branchNode.eulerAngles.x = Float.random(in: -0.35...0.35)
                branchNode.eulerAngles.y = Float.random(in: -0.4...0.4)
                // Cylinder is Y-up; nudge so half the limb extends outward from the trunk.
                branchNode.pivot = SCNMatrix4MakeTranslation(0, -Float(branchLen) * 0.45, 0)
                root.addChildNode(branchNode)
            }

            return PlacedObstacle(
                node: root,
                radius: Float(trunkBottom) * 1.05,
                height: Float(trunkHeight) + 0.3
            )
        }

        let canopyBase = Float(trunkHeight) * 0.72
        let greens: [UIColor] = [
            UIColor(red: 0.18, green: 0.48, blue: 0.20, alpha: 1),
            UIColor(red: 0.12, green: 0.40, blue: 0.16, alpha: 1),
            UIColor(red: 0.24, green: 0.55, blue: 0.24, alpha: 1),
            UIColor(red: 0.15, green: 0.36, blue: 0.14, alpha: 1)
        ]

        let clusterCount = Int.random(in: 5...7)
        for i in 0..<clusterCount {
            let radius = CGFloat.random(in: 0.55...0.95)
            let foliage = SCNSphere(radius: radius)
            foliage.segmentCount = 12
            let color = greens.randomElement()!
            foliage.firstMaterial = GameArt.foliageMaterial(base: color)
            let node = SCNNode(geometry: foliage)
            let angle = Float(i) / Float(clusterCount) * Float.pi * 2 + Float.random(in: -0.3...0.3)
            let spread = Float.random(in: 0.15...0.55)
            node.position = SCNVector3(
                cos(angle) * spread,
                canopyBase + Float.random(in: 0.2...1.3),
                sin(angle) * spread
            )
            node.scale = SCNVector3(
                Float.random(in: 0.9...1.15),
                Float.random(in: 0.75...1.0),
                Float.random(in: 0.9...1.15)
            )
            root.addChildNode(node)
        }

        let crown = SCNSphere(radius: CGFloat.random(in: 0.65...0.9))
        crown.segmentCount = 12
        crown.firstMaterial = GameArt.foliageMaterial(base: greens[0])
        let crownNode = SCNNode(geometry: crown)
        crownNode.position = SCNVector3(0, canopyBase + 1.35, 0)
        crownNode.scale = SCNVector3(1.05, 0.85, 1.05)
        root.addChildNode(crownNode)

        // Collide with the trunk only — canopy is visual.
        return PlacedObstacle(
            node: root,
            radius: Float(trunkBottom) * 1.15,
            height: Float(trunkHeight) * 0.85
        )
    }

    /// Swamp willow: mossy crown, dangling strands, and spreading roots (sometimes in water).
    static func makeWillowTree(at position: SCNVector3, inWater: Bool = false) -> PlacedObstacle {
        makeWillowTree(at: position, inWater: inWater, detail: .standard)
    }

    /// Lightweight willow for dense edge scenery (far fewer nodes / polygons).
    static func makeSimpleWillow(at position: SCNVector3, inWater: Bool = false) -> PlacedObstacle {
        makeWillowTree(at: position, inWater: inWater, detail: .simple)
    }

    private enum WillowDetail {
        case standard
        case simple
    }

    private static func makeWillowTree(
        at position: SCNVector3,
        inWater: Bool,
        detail: WillowDetail
    ) -> PlacedObstacle {
        let root = SCNNode()
        root.name = "obstacle"
        let sink: Float = inWater ? 0.18 : 0.04
        root.position = SCNVector3(position.x, position.y - sink, position.z)
        root.castsShadow = false

        let trunkHeight = CGFloat.random(in: detail == .simple ? 2.0...2.8 : 2.4...3.4)
        let trunkBottom = CGFloat.random(in: 0.26...0.36)
        let bark = GameArt.barkMaterial()
        bark.diffuse.contents = UIColor(red: 0.28, green: 0.22, blue: 0.14, alpha: 1)

        let trunk = SCNCone(
            topRadius: trunkBottom * 0.45,
            bottomRadius: trunkBottom,
            height: trunkHeight
        )
        trunk.radialSegmentCount = detail == .simple ? 5 : 6
        trunk.firstMaterial = bark
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, Float(trunkHeight) * 0.5, 0)
        trunkNode.eulerAngles.z = Float.random(in: -0.1...0.1)
        root.addChildNode(trunkNode)

        let rootCount = detail == .simple ? 3 : 4
        for i in 0..<rootCount {
            let angle = Float(i) / Float(rootCount) * Float.pi * 2
            let len = CGFloat.random(in: 0.7...1.2)
            let thick = CGFloat.random(in: 0.07...0.12)
            let rootGeom = SCNCone(topRadius: 0.015, bottomRadius: thick, height: len)
            rootGeom.radialSegmentCount = 4
            rootGeom.firstMaterial = bark
            let rootNode = SCNNode(geometry: rootGeom)
            let reach = Float(len) * 0.45
            let drop: Float = inWater ? 0.28 : 0.12
            rootNode.position = SCNVector3(cos(angle) * reach, Float(len) * 0.12 - drop, sin(angle) * reach)
            rootNode.eulerAngles = SCNVector3(Float.pi * 0.68, angle, 0)
            root.addChildNode(rootNode)
        }

        let mossGreens: [UIColor] = [
            UIColor(red: 0.22, green: 0.38, blue: 0.18, alpha: 1),
            UIColor(red: 0.18, green: 0.32, blue: 0.16, alpha: 1),
            UIColor(red: 0.30, green: 0.42, blue: 0.20, alpha: 1)
        ]

        let crownY = Float(trunkHeight) * 0.9
        let blobCount = detail == .simple ? 2 : 3
        for i in 0..<blobCount {
            let r = CGFloat.random(in: 0.75...1.1)
            let blob = SCNSphere(radius: r)
            blob.segmentCount = detail == .simple ? 6 : 8
            blob.firstMaterial = GameArt.foliageMaterial(base: mossGreens[i % mossGreens.count])
            let node = SCNNode(geometry: blob)
            let angle = Float(i) / Float(blobCount) * Float.pi * 2
            node.position = SCNVector3(cos(angle) * 0.3, crownY, sin(angle) * 0.3)
            node.scale = SCNVector3(1.25, 0.6, 1.25)
            root.addChildNode(node)
        }

        let strandCount = detail == .simple ? 4 : 6
        for i in 0..<strandCount {
            let angle = Float(i) / Float(strandCount) * Float.pi * 2
            let strandLen = CGFloat.random(in: 1.2...1.9)
            let strand = SCNBox(width: 0.09, height: strandLen, length: 0.09, chamferRadius: 0)
            strand.firstMaterial = GameArt.foliageMaterial(base: mossGreens[i % mossGreens.count])
            let strandNode = SCNNode(geometry: strand)
            strandNode.position = SCNVector3(
                cos(angle) * 0.85,
                crownY - Float(strandLen) * 0.4,
                sin(angle) * 0.85
            )
            strandNode.eulerAngles = SCNVector3(0.22, angle, 0)
            root.addChildNode(strandNode)
        }

        return PlacedObstacle(
            node: root,
            radius: Float(trunkBottom) * 1.2,
            height: Float(trunkHeight) * 0.85
        )
    }

    /// Layered pine with bark trunk and slightly irregular cones.
    static func makePineTree(
        at position: SCNVector3,
        snowCapped: Bool = true,
        heightScale: Float = 1
    ) -> PlacedObstacle {
        let root = SCNNode()
        root.name = "obstacle"
        root.position = SCNVector3(position.x, position.y - 0.04, position.z)
        root.castsShadow = false

        let scale = CGFloat(max(0.5, heightScale))
        let trunkHeight = CGFloat.random(in: 0.7...1.1) * scale
        let trunkRadius = CGFloat.random(in: 0.16...0.24)
        let trunk = SCNCylinder(radius: trunkRadius, height: trunkHeight)
        trunk.radialSegmentCount = 8
        trunk.firstMaterial = GameArt.barkMaterial()
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, Float(trunkHeight) * 0.5, 0)
        root.addChildNode(trunkNode)

        let needleBase = UIColor(
            red: CGFloat.random(in: 0.08...0.16),
            green: CGFloat.random(in: 0.30...0.42),
            blue: CGFloat.random(in: 0.16...0.24),
            alpha: 1
        )
        let needleDark = UIColor(
            red: CGFloat.random(in: 0.05...0.12),
            green: CGFloat.random(in: 0.22...0.32),
            blue: CGFloat.random(in: 0.12...0.18),
            alpha: 1
        )

        let layers = Int.random(in: 4...6)
        var y = Float(trunkHeight) * 0.55
        for i in 0..<layers {
            let t = CGFloat(i) / CGFloat(max(layers - 1, 1))
            let bottomR = CGFloat.random(in: 1.05...1.45) * (1.0 - t * 0.55)
            let height = CGFloat.random(in: 0.9...1.25) * (1.0 - t * 0.08) * scale
            let cone = SCNCone(topRadius: 0.04, bottomRadius: bottomR, height: height)
            cone.radialSegmentCount = 10
            let color = (i % 2 == 0) ? needleBase : needleDark
            cone.firstMaterial = GameArt.foliageMaterial(base: color)
            let coneNode = SCNNode(geometry: cone)
            coneNode.position = SCNVector3(
                Float.random(in: -0.05...0.05),
                y + Float(height) * 0.38,
                Float.random(in: -0.05...0.05)
            )
            coneNode.eulerAngles = SCNVector3(
                Float.random(in: -0.04...0.04),
                Float.random(in: 0...(Float.pi * 2)),
                Float.random(in: -0.04...0.04)
            )
            root.addChildNode(coneNode)

            if snowCapped && i >= layers - 2 {
                let snow = SCNCone(
                    topRadius: 0.02,
                    bottomRadius: bottomR * 0.72,
                    height: height * 0.35
                )
                snow.radialSegmentCount = 8
                let snowMat = SCNMaterial()
                snowMat.diffuse.contents = UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1)
                snowMat.lightingModel = .lambert
                snow.firstMaterial = snowMat
                let snowNode = SCNNode(geometry: snow)
                snowNode.position = SCNVector3(0, Float(height) * 0.28, 0)
                coneNode.addChildNode(snowNode)
            }

            y += Float(height) * 0.52
        }

        // Trunk-sized hitbox — wide pine needles were making a huge invisible cylinder.
        return PlacedObstacle(
            node: root,
            radius: Float(trunkRadius) * 1.35,
            height: Float(trunkHeight) + 1.2 * Float(scale)
        )
    }

    /// Tall palm with radiating fronds.
    static func makePalmTree(at position: SCNVector3, crownCoconuts: Bool? = nil) -> PlacedObstacle {
        let root = SCNNode()
        root.name = "obstacle"
        root.position = SCNVector3(position.x, position.y - 0.04, position.z)
        root.castsShadow = false

        let trunkHeight = CGFloat.random(in: 3.2...4.4)
        let trunkBottom = CGFloat.random(in: 0.20...0.28)
        let trunk = SCNCone(topRadius: trunkBottom * 0.55, bottomRadius: trunkBottom, height: trunkHeight)
        trunk.radialSegmentCount = 8
        let bark = SCNMaterial()
        bark.diffuse.contents = UIColor(red: 0.55, green: 0.40, blue: 0.22, alpha: 1)
        bark.lightingModel = .blinn
        bark.locksAmbientWithDiffuse = true
        trunk.firstMaterial = bark
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position = SCNVector3(0, Float(trunkHeight) * 0.5, 0)
        root.addChildNode(trunkNode)

        let frondGreen = UIColor(
            red: CGFloat.random(in: 0.12...0.22),
            green: CGFloat.random(in: 0.48...0.62),
            blue: CGFloat.random(in: 0.18...0.28),
            alpha: 1
        )
        let frondCount = Int.random(in: 6...8)
        let crownY = Float(trunkHeight) - 0.1
        for i in 0..<frondCount {
            let angle = Float(i) / Float(frondCount) * Float.pi * 2
            let frondLen = CGFloat.random(in: 1.6...2.2)
            let frond = SCNCone(topRadius: 0.02, bottomRadius: 0.28, height: frondLen)
            frond.radialSegmentCount = 6
            frond.firstMaterial = GameArt.foliageMaterial(base: frondGreen)
            let frondNode = SCNNode(geometry: frond)
            // Hang outward and slightly down from the crown.
            frondNode.position = SCNVector3(
                cos(angle) * 0.15,
                crownY,
                sin(angle) * 0.15
            )
            frondNode.eulerAngles = SCNVector3(
                Float.pi * 0.55 + Float.random(in: -0.08...0.08),
                angle,
                Float.random(in: -0.1...0.1)
            )
            root.addChildNode(frondNode)
        }

        // Small crown nub
        let nub = SCNSphere(radius: 0.22)
        nub.segmentCount = 8
        nub.firstMaterial = bark
        let nubNode = SCNNode(geometry: nub)
        nubNode.position = SCNVector3(0, crownY, 0)
        root.addChildNode(nubNode)

        // Sometimes a small cluster of coconuts tucked under the fronds.
        let wantCrown = crownCoconuts ?? (Float.random(in: 0...1) < 0.45)
        if wantCrown {
            attachCrownCoconuts(to: root, crownY: crownY)
        }

        return PlacedObstacle(
            node: root,
            radius: Float(trunkBottom) * 1.25,
            height: Float(trunkHeight) * 0.75
        )
    }

    /// Visual husks hanging in the palm crown (no separate collision).
    private static func attachCrownCoconuts(to palm: SCNNode, crownY: Float) {
        let count = Int.random(in: 2...4)
        for i in 0..<count {
            let angle = Float(i) / Float(count) * Float.pi * 2 + Float.random(in: -0.25...0.25)
            let radius = CGFloat.random(in: 0.16...0.24)
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 8
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(
                red: CGFloat.random(in: 0.42...0.52),
                green: CGFloat.random(in: 0.24...0.32),
                blue: CGFloat.random(in: 0.10...0.16),
                alpha: 1
            )
            mat.lightingModel = .blinn
            mat.locksAmbientWithDiffuse = true
            sphere.firstMaterial = mat
            let node = SCNNode(geometry: sphere)
            node.name = "crownCoconut"
            let dist = Float.random(in: 0.18...0.38)
            node.position = SCNVector3(
                cos(angle) * dist,
                crownY - Float.random(in: 0.15...0.45),
                sin(angle) * dist
            )
            node.eulerAngles = SCNVector3(
                Float.random(in: -0.5...0.5),
                Float.random(in: 0...(Float.pi * 2)),
                Float.random(in: -0.4...0.4)
            )
            palm.addChildNode(node)
        }
    }

    /// Ground coconut (decorative on dunes; solid only when registered as an obstacle).
    static func makeCoconut(at position: SCNVector3) -> PlacedObstacle {
        let radius = CGFloat.random(in: 0.28...0.40)
        let root = SCNNode()
        root.name = "obstacle"
        root.position = SCNVector3(position.x, position.y, position.z)
        root.castsShadow = false

        let sphere = SCNSphere(radius: radius)
        sphere.segmentCount = 10
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(
            red: CGFloat.random(in: 0.42...0.52),
            green: CGFloat.random(in: 0.24...0.32),
            blue: CGFloat.random(in: 0.10...0.16),
            alpha: 1
        )
        mat.lightingModel = .blinn
        mat.locksAmbientWithDiffuse = true
        sphere.firstMaterial = mat
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(0, Float(radius) * 0.85, 0)
        node.scale = SCNVector3(1.0, 0.88, 1.05)
        node.eulerAngles = SCNVector3(
            Float.random(in: -0.4...0.4),
            Float.random(in: 0...(Float.pi * 2)),
            Float.random(in: -0.3...0.3)
        )
        root.addChildNode(node)

        return PlacedObstacle(
            node: root,
            radius: Float(radius) * 0.95,
            height: Float(radius) * 1.7
        )
    }

    struct LavaGeyserVisual {
        let node: SCNNode
        let jetNode: SCNNode
        let sprayNode: SCNNode
        let glowNode: SCNNode
        let jetHeight: Float
        let radius: Float
    }

    /// Rock vent with a straight orange lava pillar and bubbly molten crown.
    static func makeLavaGeyser(at position: SCNVector3) -> LavaGeyserVisual {
        let root = SCNNode()
        root.name = "geyser"
        root.position = SCNVector3(position.x, position.y - 0.06, position.z)
        root.castsShadow = false

        let rockTint = UIColor(red: 0.20, green: 0.11, blue: 0.09, alpha: 1)
        let rockMat = GameArt.rockMaterial(tint: rockTint)
        let darkRock = GameArt.rockMaterial(tint: UIColor(red: 0.12, green: 0.07, blue: 0.06, alpha: 1))

        for i in 0..<6 {
            let angle = Float(i) / 6 * Float.pi * 2
            let size = CGFloat.random(in: 0.35...0.55)
            let chunk = SCNBox(
                width: size,
                height: size * CGFloat.random(in: 0.45...0.7),
                length: size * CGFloat.random(in: 0.7...1.1),
                chamferRadius: size * 0.22
            )
            chunk.chamferSegmentCount = 4
            chunk.firstMaterial = (i % 2 == 0) ? rockMat : darkRock
            let node = SCNNode(geometry: chunk)
            node.position = SCNVector3(
                cos(angle) * 0.62,
                Float(size) * 0.22,
                sin(angle) * 0.62
            )
            node.eulerAngles = SCNVector3(
                Float.random(in: -0.25...0.25),
                angle,
                Float.random(in: -0.2...0.2)
            )
            root.addChildNode(node)
        }

        let rim = SCNTorus(ringRadius: 0.58, pipeRadius: 0.16)
        rim.ringSegmentCount = 28
        rim.pipeSegmentCount = 12
        rim.firstMaterial = rockMat
        let rimNode = SCNNode(geometry: rim)
        rimNode.position = SCNVector3(0, 0.14, 0)
        root.addChildNode(rimNode)

        let lavaMat = SCNMaterial()
        lavaMat.diffuse.contents = UIColor(red: 1.0, green: 0.45, blue: 0.12, alpha: 1)
        lavaMat.emission.contents = UIColor(red: 0.95, green: 0.32, blue: 0.05, alpha: 1)
        lavaMat.lightingModel = .physicallyBased
        lavaMat.metalness.contents = 0.08
        lavaMat.roughness.contents = 0.4

        let bowl = SCNCylinder(radius: 0.40, height: 0.16)
        bowl.radialSegmentCount = 24
        bowl.firstMaterial = lavaMat
        let glowNode = SCNNode(geometry: bowl)
        glowNode.name = "geyserGlow"
        glowNode.position = SCNVector3(0, 0.07, 0)
        root.addChildNode(glowNode)

        let jetHeight = CGFloat.random(in: 3.4...4.8)
        let pillarRadius: CGFloat = 0.32

        // Straight orange pillar (scales up from the vent when erupting).
        let pillar = SCNCylinder(radius: pillarRadius, height: jetHeight)
        pillar.radialSegmentCount = 16
        pillar.heightSegmentCount = 1
        let pillarMat = SCNMaterial()
        pillarMat.diffuse.contents = UIColor(red: 1.0, green: 0.40, blue: 0.08, alpha: 1)
        pillarMat.emission.contents = UIColor(red: 0.90, green: 0.28, blue: 0.04, alpha: 1)
        pillarMat.lightingModel = .constant
        pillar.firstMaterial = pillarMat
        let jetNode = SCNNode(geometry: pillar)
        jetNode.name = "geyserJet"
        jetNode.position = SCNVector3(0, Float(jetHeight) * 0.5, 0)
        root.addChildNode(jetNode)

        let core = SCNCylinder(radius: pillarRadius * 0.55, height: jetHeight * 0.98)
        core.radialSegmentCount = 12
        let coreMat = SCNMaterial()
        coreMat.diffuse.contents = UIColor(red: 1.0, green: 0.62, blue: 0.18, alpha: 1)
        coreMat.emission.contents = UIColor(red: 1.0, green: 0.45, blue: 0.08, alpha: 1)
        coreMat.lightingModel = .constant
        core.firstMaterial = coreMat
        let coreNode = SCNNode(geometry: core)
        jetNode.addChildNode(coreNode)

        // Bubbly molten crown at the top of the pillar.
        let sprayNode = SCNNode()
        sprayNode.name = "geyserSpray"
        sprayNode.position = SCNVector3(0, Float(jetHeight), 0)
        root.addChildNode(sprayNode)

        let bubbleSizes: [CGFloat] = [0.72, 0.58, 0.48, 0.42, 0.55, 0.38, 0.46, 0.34]
        for (i, size) in bubbleSizes.enumerated() {
            let bubble = SCNSphere(radius: size)
            bubble.segmentCount = 12
            bubble.firstMaterial = lavaMat
            let bubbleNode = SCNNode(geometry: bubble)
            let angle = Float(i) / Float(bubbleSizes.count) * Float.pi * 2
            let radial = Float.random(in: 0.15...0.55)
            bubbleNode.position = SCNVector3(
                cos(angle) * radial,
                Float.random(in: -0.08...0.45),
                sin(angle) * radial
            )
            bubbleNode.name = "geyserBubble"
            sprayNode.addChildNode(bubbleNode)
        }

        // Slightly larger center blob so the top reads as molten foam.
        let crown = SCNSphere(radius: 0.75)
        crown.segmentCount = 14
        crown.firstMaterial = lavaMat
        let crownNode = SCNNode(geometry: crown)
        crownNode.position = SCNVector3(0, 0.2, 0)
        crownNode.scale = SCNVector3(1.35, 0.85, 1.35)
        sprayNode.addChildNode(crownNode)

        jetNode.scale = SCNVector3(1, 0.04, 1)
        jetNode.opacity = 0.15
        sprayNode.opacity = 0.05
        sprayNode.scale = SCNVector3(0.2, 0.2, 0.2)

        return LavaGeyserVisual(
            node: root,
            jetNode: jetNode,
            sprayNode: sprayNode,
            glowNode: glowNode,
            jetHeight: Float(jetHeight),
            radius: 0.85
        )
    }

    /// Decorative snow peak for biome edge ridges (no gameplay collision).
    static func makeSnowMountain(at position: SCNVector3, peakHeight: CGFloat) -> SCNNode {
        let root = SCNNode()
        root.name = "edgeDecor"
        root.position = position
        root.castsShadow = false

        let rock = GameArt.rockMaterial(tint: UIColor(red: 0.48, green: 0.52, blue: 0.58, alpha: 1))
        let snow = GameArt.rockMaterial(tint: UIColor(red: 0.93, green: 0.96, blue: 1.0, alpha: 1))

        let baseRadius = peakHeight * CGFloat.random(in: 0.72...0.98)
        let base = SCNCone(topRadius: baseRadius * 0.08, bottomRadius: baseRadius, height: peakHeight)
        base.radialSegmentCount = 8
        base.firstMaterial = rock
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, Float(peakHeight) * 0.5, 0)
        root.addChildNode(baseNode)

        let midHeight = peakHeight * CGFloat.random(in: 0.35...0.5)
        let mid = SCNCone(
            topRadius: baseRadius * 0.04,
            bottomRadius: baseRadius * 0.55,
            height: midHeight
        )
        mid.radialSegmentCount = 7
        mid.firstMaterial = rock
        let midNode = SCNNode(geometry: mid)
        midNode.position = SCNVector3(
            Float.random(in: -0.4...0.4),
            Float(peakHeight) * 0.55,
            Float.random(in: -0.4...0.4)
        )
        root.addChildNode(midNode)

        let capHeight = peakHeight * CGFloat.random(in: 0.22...0.34)
        let cap = SCNCone(
            topRadius: 0.05,
            bottomRadius: baseRadius * 0.42,
            height: capHeight
        )
        cap.radialSegmentCount = 7
        cap.firstMaterial = snow
        let capNode = SCNNode(geometry: cap)
        capNode.position = SCNVector3(0, Float(peakHeight) * 0.78, 0)
        root.addChildNode(capNode)

        root.eulerAngles.y = Float.random(in: 0...(Float.pi * 2))
        return root
    }

    /// Decorative forest bush — foliage only, no collision volume.
    static func makeBush(
        at position: SCNVector3,
        scaleRange: ClosedRange<Float> = 0.86...1.39,
        withBerries: Bool = false
    ) -> SCNNode {
        let root = SCNNode()
        root.name = "decor"
        root.position = position
        root.castsShadow = false

        let greens: [UIColor] = [
            UIColor(red: 0.22, green: 0.48, blue: 0.18, alpha: 1),
            UIColor(red: 0.30, green: 0.55, blue: 0.22, alpha: 1),
            UIColor(red: 0.18, green: 0.40, blue: 0.16, alpha: 1),
            UIColor(red: 0.26, green: 0.50, blue: 0.20, alpha: 1)
        ]

        var canopyBlobs: [(pos: SCNVector3, radiusX: Float, radiusY: Float, radiusZ: Float)] = []
        let blobCount = Int.random(in: 3...6)
        for i in 0..<blobCount {
            let radius = CGFloat.random(in: 0.38...0.72)
            let sphere = SCNSphere(radius: radius)
            sphere.segmentCount = 10
            sphere.firstMaterial = GameArt.foliageMaterial(base: greens[i % greens.count])
            let node = SCNNode(geometry: sphere)
            let pos = SCNVector3(
                Float.random(in: -0.42...0.42),
                Float(radius) * 0.85 + Float.random(in: -0.05...0.12),
                Float.random(in: -0.42...0.42)
            )
            let sx = Float.random(in: 0.9...1.2)
            let sy = Float.random(in: 0.65...0.95)
            let sz = Float.random(in: 0.9...1.2)
            node.position = pos
            node.scale = SCNVector3(sx, sy, sz)
            root.addChildNode(node)
            canopyBlobs.append((pos, Float(radius) * sx, Float(radius) * sy, Float(radius) * sz))
        }

        // Twigs under the canopy.
        let stem = SCNCylinder(radius: 0.05, height: 0.28)
        stem.radialSegmentCount = 5
        stem.firstMaterial = GameArt.barkMaterial()
        let stemNode = SCNNode(geometry: stem)
        stemNode.position = SCNVector3(0, 0.12, 0)
        root.addChildNode(stemNode)

        if withBerries {
            let berryMat = SCNMaterial()
            // Muted cranberry red — readable without neon saturation.
            berryMat.diffuse.contents = UIColor(red: 0.62, green: 0.22, blue: 0.24, alpha: 1)
            berryMat.lightingModel = .blinn
            berryMat.shininess = 0.2
            berryMat.locksAmbientWithDiffuse = true

            let berryCount = Int.random(in: 8...16)
            for _ in 0..<berryCount {
                guard let blob = canopyBlobs.randomElement() else { continue }
                // Sit on the outer surface so berries aren't buried in the foliage.
                var dx = Float.random(in: -1...1)
                var dy = Float.random(in: 0.15...1) // bias upward / outward
                var dz = Float.random(in: -1...1)
                let len = max(0.0001, sqrt(dx * dx + dy * dy + dz * dz))
                dx /= len
                dy /= len
                dz /= len
                let berry = SCNSphere(radius: CGFloat.random(in: 0.07...0.11))
                berry.segmentCount = 8
                berry.firstMaterial = berryMat
                let berryNode = SCNNode(geometry: berry)
                berryNode.position = SCNVector3(
                    blob.pos.x + dx * blob.radiusX * 1.05,
                    blob.pos.y + dy * blob.radiusY * 1.05,
                    blob.pos.z + dz * blob.radiusZ * 1.05
                )
                root.addChildNode(berryNode)
            }
        }

        root.eulerAngles.y = Float.random(in: 0...(Float.pi * 2))
        let grow = Float.random(in: scaleRange)
        root.scale = SCNVector3(grow, grow, grow)
        return root
    }

    /// Side volcano with a glowing crater (lava pockets spawn separately on the path).
    static func makeVolcano(
        at position: SCNVector3,
        peakHeight: CGFloat,
        side: Float
    ) -> SCNNode {
        _ = side
        let root = SCNNode()
        root.name = "edgeDecor"
        root.position = position
        root.castsShadow = false

        let rock = GameArt.rockMaterial(tint: UIColor(red: 0.22, green: 0.14, blue: 0.12, alpha: 1))
        let darkRock = GameArt.rockMaterial(tint: UIColor(red: 0.14, green: 0.09, blue: 0.08, alpha: 1))
        let lava = GameArt.lavaGlowMaterial()
        let hotLava = GameArt.lavaGlowMaterial(intensity: 1.25)

        let baseRadius = peakHeight * CGFloat.random(in: 0.70...0.95)
        let base = SCNCone(topRadius: baseRadius * 0.12, bottomRadius: baseRadius, height: peakHeight)
        base.radialSegmentCount = 9
        base.firstMaterial = rock
        let baseNode = SCNNode(geometry: base)
        baseNode.position = SCNVector3(0, Float(peakHeight) * 0.5, 0)
        root.addChildNode(baseNode)

        let shoulder = SCNCone(
            topRadius: baseRadius * 0.08,
            bottomRadius: baseRadius * 0.55,
            height: peakHeight * 0.42
        )
        shoulder.radialSegmentCount = 8
        shoulder.firstMaterial = darkRock
        let shoulderNode = SCNNode(geometry: shoulder)
        shoulderNode.position = SCNVector3(
            Float.random(in: -0.5...0.5),
            Float(peakHeight) * 0.52,
            Float.random(in: -0.5...0.5)
        )
        root.addChildNode(shoulderNode)

        // Glowing crater bowl.
        let crater = SCNCylinder(radius: baseRadius * 0.22, height: peakHeight * 0.08)
        crater.radialSegmentCount = 10
        crater.firstMaterial = hotLava
        let craterNode = SCNNode(geometry: crater)
        craterNode.position = SCNVector3(0, Float(peakHeight) * 0.92, 0)
        root.addChildNode(craterNode)

        let glow = SCNSphere(radius: baseRadius * 0.18)
        glow.segmentCount = 8
        glow.firstMaterial = lava
        let glowNode = SCNNode(geometry: glow)
        glowNode.position = SCNVector3(0, Float(peakHeight) * 0.96, 0)
        glowNode.opacity = 0.85
        root.addChildNode(glowNode)
        glowNode.runAction(
            .repeatForever(
                .sequence([
                    .fadeOpacity(to: 1.0, duration: 0.55),
                    .fadeOpacity(to: 0.55, duration: 0.7)
                ])
            )
        )

        root.eulerAngles.y = Float.random(in: -0.25...0.25)
        return root
    }

    static func makeHazardVolume(
        width: CGFloat,
        height: CGFloat,
        length: CGFloat,
        color: UIColor,
        at position: SCNVector3
    ) -> SCNNode {
        let box = SCNBox(width: width, height: height, length: length, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .blinn
        material.locksAmbientWithDiffuse = true
        box.firstMaterial = material
        let node = SCNNode(geometry: box)
        node.name = "hazard"
        node.position = position
        node.castsShadow = false
        return node
    }
}
