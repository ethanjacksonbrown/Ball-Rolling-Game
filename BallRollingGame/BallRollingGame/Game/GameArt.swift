import SceneKit
import UIKit

/// Shared procedural textures and materials for a more coherent look.
enum GameArt {
    private static var textureCache: [String: UIImage] = [:]
    private static var materialCache: [String: SCNMaterial] = [:]

    /// Warm common textures/materials so the first race doesn't hitch on UIGraphics work.
    static func warmCaches() {
        _ = skyGradient()
        _ = soccerBallTexture()
        _ = basketballTexture()
        _ = tennisBallTexture()
        _ = beachBallTexture()
        _ = marbleBallTexture()
        for biome in Biome.allCases {
            _ = groundTexture(for: biome)
        }
        _ = barkMaterial(scorched: false)
        _ = barkMaterial(scorched: true)
        _ = foliageMaterial(base: UIColor(red: 0.18, green: 0.48, blue: 0.20, alpha: 1))
        _ = foliageMaterial(base: UIColor(red: 0.12, green: 0.40, blue: 0.16, alpha: 1))
        _ = foliageMaterial(base: UIColor(red: 0.24, green: 0.55, blue: 0.24, alpha: 1))
        _ = foliageMaterial(base: UIColor(red: 0.22, green: 0.48, blue: 0.18, alpha: 1))
        _ = rockMaterial()
        _ = rockMaterial(tint: UIColor(white: 0.12, alpha: 1))
    }

    static func skyGradient() -> UIImage {
        cached("sky") {
            makeVerticalGradient(
                size: CGSize(width: 8, height: 256),
                top: UIColor(red: 0.35, green: 0.62, blue: 0.92, alpha: 1),
                bottom: UIColor(red: 0.72, green: 0.86, blue: 0.98, alpha: 1)
            )
        }
    }

    static func groundMaterial(for biome: Biome) -> SCNMaterial {
        groundMaterial(from: biome, to: biome)
    }

    /// When `from != to`, builds a soft along-track color blend (seamless biome change).
    static func groundMaterial(from: Biome, to: Biome) -> SCNMaterial {
        let material = SCNMaterial()
        if from == to {
            material.diffuse.contents = groundTexture(for: from)
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .repeat
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 10, 1)
        } else {
            material.diffuse.contents = blendedGroundTexture(from: from, to: to)
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .clamp
            material.diffuse.contentsTransform = SCNMatrix4MakeScale(6, 1, 1)
        }
        material.lightingModel = .lambert
        material.locksAmbientWithDiffuse = true
        material.shininess = 0.02
        return material
    }

    static func waterMaterial(for biome: Biome) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .constant
        material.locksAmbientWithDiffuse = true
        material.isDoubleSided = true
        return material
    }

    /// Flat water strip with vertex colors lerped along +Z (no UV/texture orientation bugs).
    static func makeWaterStrip(
        width: Float,
        length: Float,
        fromColor: UIColor,
        toColor: UIColor,
        segments: Int = 16
    ) -> SCNNode {
        var vertices: [SCNVector3] = []
        var normals: [SCNVector3] = []
        var colors: [Float] = []
        var indices: [UInt32] = []

        let halfW = width * 0.5
        let segs = max(2, segments)

        func appendColor(_ color: UIColor) {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            colors.append(contentsOf: [Float(r), Float(g), Float(b), Float(a)])
        }

        for i in 0...segs {
            let t = Float(i) / Float(segs)
            let eased = t * t * (3 - 2 * t)
            let z = length * t
            let color = lerpColor(fromColor, toColor, t: CGFloat(eased))
            vertices.append(SCNVector3(-halfW, 0, z))
            vertices.append(SCNVector3(halfW, 0, z))
            normals.append(SCNVector3(0, 1, 0))
            normals.append(SCNVector3(0, 1, 0))
            appendColor(color)
            appendColor(color)
        }

        for i in 0..<segs {
            let base = UInt32(i * 2)
            indices.append(contentsOf: [base, base + 1, base + 2, base + 1, base + 3, base + 2])
        }

        let vertexSource = SCNGeometrySource(vertices: vertices)
        let normalSource = SCNGeometrySource(normals: normals)
        let colorData = Data(bytes: colors, count: colors.count * MemoryLayout<Float>.size)
        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource, colorSource], elements: [element])
        geometry.materials = [waterMaterial(for: .forest)]

        let node = SCNNode(geometry: geometry)
        node.name = "hazard"
        node.castsShadow = false
        return node
    }

    static func pondMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.18, green: 0.42, blue: 0.40, alpha: 1)
        material.lightingModel = .constant
        material.transparency = 1
        material.locksAmbientWithDiffuse = true
        return material
    }

    static func iceMaterial() -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(red: 0.72, green: 0.88, blue: 0.98, alpha: 1)
        material.transparent.contents = UIColor(white: 1, alpha: 0.65)
        material.transparency = 0.62
        material.specular.contents = UIColor.white
        material.shininess = 1.0
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.25
        material.roughness.contents = 0.08
        return material
    }

    static func barkMaterial(scorched: Bool = false) -> SCNMaterial {
        let key = scorched ? "bark-scorched" : "bark"
        if let hit = materialCache[key] { return hit }
        let material = SCNMaterial()
        material.diffuse.contents = scorched
            ? barkTexture(
                base: UIColor(red: 0.18, green: 0.10, blue: 0.08, alpha: 1),
                streak: UIColor(red: 0.08, green: 0.05, blue: 0.04, alpha: 1)
            )
            : barkTexture(
                base: UIColor(red: 0.42, green: 0.27, blue: 0.15, alpha: 1),
                streak: UIColor(red: 0.28, green: 0.17, blue: 0.10, alpha: 1)
            )
        material.diffuse.wrapS = .repeat
        material.diffuse.wrapT = .repeat
        material.lightingModel = .blinn
        material.locksAmbientWithDiffuse = true
        materialCache[key] = material
        return material
    }

    static func foliageMaterial(base: UIColor) -> SCNMaterial {
        // Quantize color so nearby greens share one material.
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = String(format: "foliage-%.2f-%.2f-%.2f", r, g, b)
        if let hit = materialCache[key] { return hit }
        let material = SCNMaterial()
        material.diffuse.contents = foliageTexture(base: base)
        material.lightingModel = .lambert
        material.locksAmbientWithDiffuse = true
        materialCache[key] = material
        return material
    }

    static func rockMaterial(tint: UIColor = UIColor(white: 0.48, alpha: 1)) -> SCNMaterial {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = String(format: "rock-%.2f-%.2f-%.2f", r, g, b)
        if let hit = materialCache[key] { return hit }
        let material = SCNMaterial()
        material.diffuse.contents = rockTexture(base: tint)
        material.lightingModel = .blinn
        material.locksAmbientWithDiffuse = true
        material.shininess = 0.08
        materialCache[key] = material
        return material
    }

    static func ballMaterial() -> SCNMaterial {
        ballMaterial(for: .classic)
    }

    /// Emission reserved for lava accents (geysers / molten edge bubbles).
    static func lavaGlowMaterial(intensity: CGFloat = 1) -> SCNMaterial {
        let material = SCNMaterial()
        let hot = UIColor(red: 1.0, green: 0.42, blue: 0.10, alpha: 1)
        material.diffuse.contents = hot
        material.emission.contents = UIColor(
            red: 0.95 * intensity,
            green: 0.28 * intensity,
            blue: 0.04 * intensity,
            alpha: 1
        )
        material.lightingModel = .lambert
        material.locksAmbientWithDiffuse = true
        return material
    }

    static func ballMaterial(for skin: BallSkin) -> SCNMaterial {
        switch skin {
        case .classic:
            return glossyBall(color: skin.previewColor)
        case .soccer:
            return texturedBall(soccerBallTexture())
        case .basketball:
            return texturedBall(basketballTexture())
        case .tennis:
            return texturedBall(tennisBallTexture())
        case .beachBall:
            return texturedBall(beachBallTexture())
        case .gold:
            let material = glossyBall(color: skin.previewColor)
            material.metalness.contents = 0.85
            material.roughness.contents = 0.18
            material.emission.contents = UIColor(red: 0.95, green: 0.78, blue: 0.22, alpha: 0.12)
            return material
        case .neon:
            let material = glossyBall(color: skin.previewColor)
            material.emission.contents = UIColor(red: 0.15, green: 0.95, blue: 0.85, alpha: 0.55)
            material.roughness.contents = 0.22
            return material
        case .marble:
            return texturedBall(marbleBallTexture())
        }
    }

    static func botMaterial(color: UIColor) -> SCNMaterial {
        glossyBall(color: color)
    }

    private static func glossyBall(color: UIColor) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.specular.contents = UIColor(white: 0.9, alpha: 1)
        material.shininess = 0.65
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.05
        material.roughness.contents = 0.35
        return material
    }

    private static func texturedBall(_ image: UIImage) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.specular.contents = UIColor.white
        material.shininess = 0.7
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.02
        material.roughness.contents = 0.4
        return material
    }

    /// Classic black-and-white soccer panel look for sphere UVs.
    static func soccerBallTexture() -> UIImage {
        cached("soccer-ball") {
            let size = 256
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }

            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            // Soft panel seams.
            UIColor(white: 0.78, alpha: 1).setStroke()
            ctx.setLineWidth(2)
            for y in stride(from: 0, through: size, by: size / 4) {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size, y: y))
            }
            for x in stride(from: 0, through: size, by: size / 4) {
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x, y: size))
            }
            ctx.strokePath()

            let black = UIColor(white: 0.08, alpha: 1)
            black.setFill()

            func fillPentagon(center: CGPoint, radius: CGFloat, rotation: CGFloat) {
                let path = CGMutablePath()
                for i in 0..<5 {
                    let angle = rotation + CGFloat(i) * (.pi * 2 / 5) - .pi / 2
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                    if i == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
            }

            let s = CGFloat(size)
            let patches: [(CGPoint, CGFloat, CGFloat)] = [
                (CGPoint(x: s * 0.22, y: s * 0.28), s * 0.11, 0.15),
                (CGPoint(x: s * 0.55, y: s * 0.22), s * 0.12, -0.1),
                (CGPoint(x: s * 0.82, y: s * 0.35), s * 0.10, 0.35),
                (CGPoint(x: s * 0.30, y: s * 0.62), s * 0.11, 0.05),
                (CGPoint(x: s * 0.62, y: s * 0.58), s * 0.12, -0.25),
                (CGPoint(x: s * 0.18, y: s * 0.82), s * 0.10, 0.4),
                (CGPoint(x: s * 0.78, y: s * 0.78), s * 0.11, -0.05),
                (CGPoint(x: s * 0.48, y: s * 0.88), s * 0.09, 0.2)
            ]
            for (center, radius, rotation) in patches {
                fillPentagon(center: center, radius: radius, rotation: rotation)
            }

            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    static func basketballTexture() -> UIImage {
        cached("basketball") {
            let size = CGFloat(256)
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            UIColor(red: 0.92, green: 0.45, blue: 0.12, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor(white: 0.08, alpha: 1).setStroke()
            ctx.setLineWidth(6)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: size / 2, y: 8))
            ctx.addLine(to: CGPoint(x: size / 2, y: size - 8))
            ctx.move(to: CGPoint(x: 8, y: size / 2))
            ctx.addLine(to: CGPoint(x: size - 8, y: size / 2))
            let leftOval = CGRect(x: -size * 0.35, y: 16, width: size * 0.9, height: size - 32)
            let rightOval = CGRect(x: size * 0.45, y: 16, width: size * 0.9, height: size - 32)
            ctx.addEllipse(in: leftOval)
            ctx.addEllipse(in: rightOval)
            ctx.strokePath()
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    static func tennisBallTexture() -> UIImage {
        cached("tennis-ball") {
            let size = CGFloat(256)
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            UIColor(red: 0.82, green: 0.92, blue: 0.18, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.white.setStroke()
            ctx.setLineWidth(10)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 20, y: size * 0.28))
            ctx.addCurve(
                to: CGPoint(x: size - 20, y: size * 0.72),
                control1: CGPoint(x: size * 0.35, y: size * 0.05),
                control2: CGPoint(x: size * 0.65, y: size * 0.95)
            )
            ctx.move(to: CGPoint(x: 20, y: size * 0.72))
            ctx.addCurve(
                to: CGPoint(x: size - 20, y: size * 0.28),
                control1: CGPoint(x: size * 0.35, y: size * 0.95),
                control2: CGPoint(x: size * 0.65, y: size * 0.05)
            )
            ctx.strokePath()
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    static func beachBallTexture() -> UIImage {
        cached("beach-ball") {
            let size = CGFloat(256)
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            let colors: [UIColor] = [
                UIColor(red: 0.95, green: 0.28, blue: 0.32, alpha: 1),
                UIColor(red: 1.0, green: 0.92, blue: 0.25, alpha: 1),
                UIColor(red: 0.20, green: 0.62, blue: 0.95, alpha: 1),
                UIColor.white,
                UIColor(red: 0.25, green: 0.78, blue: 0.42, alpha: 1),
                UIColor(red: 0.95, green: 0.45, blue: 0.15, alpha: 1)
            ]
            let stripe = size / CGFloat(colors.count)
            for (i, color) in colors.enumerated() {
                color.setFill()
                ctx.fill(CGRect(x: CGFloat(i) * stripe, y: 0, width: stripe + 1, height: size))
            }
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    static func marbleBallTexture() -> UIImage {
        cached("marble-ball") {
            let size = CGFloat(256)
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            UIColor(red: 0.90, green: 0.92, blue: 0.95, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            let veins: [(UIColor, CGFloat)] = [
                (UIColor(red: 0.55, green: 0.60, blue: 0.70, alpha: 0.55), 4),
                (UIColor(red: 0.35, green: 0.40, blue: 0.50, alpha: 0.4), 3),
                (UIColor(red: 0.70, green: 0.55, blue: 0.55, alpha: 0.35), 2.5)
            ]
            for (i, vein) in veins.enumerated() {
                vein.0.setStroke()
                ctx.setLineWidth(vein.1)
                ctx.setLineCap(.round)
                let y0 = CGFloat(40 + i * 55)
                ctx.move(to: CGPoint(x: 0, y: y0))
                ctx.addCurve(
                    to: CGPoint(x: size, y: y0 + 30),
                    control1: CGPoint(x: size * 0.3, y: y0 - 40),
                    control2: CGPoint(x: size * 0.7, y: y0 + 55)
                )
                ctx.strokePath()
            }
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    // MARK: - Textures

    private static func groundTexture(for biome: Biome) -> UIImage {
        switch biome {
        case .swamp:
            return grassTexture(
                key: "grass-swamp",
                c1: UIColor(red: 0.27, green: 0.46, blue: 0.24, alpha: 1),
                c2: UIColor(red: 0.34, green: 0.52, blue: 0.28, alpha: 1),
                c3: UIColor(red: 0.22, green: 0.38, blue: 0.20, alpha: 1)
            )
        case .forest:
            return grassTexture(
                key: "grass-forest",
                c1: UIColor(red: 0.24, green: 0.44, blue: 0.18, alpha: 1),
                c2: UIColor(red: 0.32, green: 0.52, blue: 0.22, alpha: 1),
                c3: UIColor(red: 0.18, green: 0.34, blue: 0.14, alpha: 1)
            )
        case .lava:
            return grassTexture(
                key: "ground-lava",
                c1: UIColor(red: 0.20, green: 0.11, blue: 0.09, alpha: 1),
                c2: UIColor(red: 0.28, green: 0.14, blue: 0.10, alpha: 1),
                c3: UIColor(red: 0.14, green: 0.08, blue: 0.07, alpha: 1)
            )
        case .snow:
            return grassTexture(
                key: "ground-snow",
                c1: UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1),
                c2: UIColor(red: 0.82, green: 0.88, blue: 0.94, alpha: 1),
                c3: UIColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1)
            )
        case .tropical:
            return grassTexture(
                key: "ground-tropical",
                c1: UIColor(red: 0.78, green: 0.72, blue: 0.42, alpha: 1),
                c2: UIColor(red: 0.68, green: 0.62, blue: 0.34, alpha: 1),
                c3: UIColor(red: 0.55, green: 0.58, blue: 0.28, alpha: 1)
            )
        }
    }

    private static func grassTexture(key: String, c1: UIColor, c2: UIColor, c3: UIColor) -> UIImage {
        cached(key) {
            let size = 128
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            c1.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

            for _ in 0..<1400 {
                let x = CGFloat.random(in: 0..<CGFloat(size))
                let y = CGFloat.random(in: 0..<CGFloat(size))
                let h = CGFloat.random(in: 2...7)
                let w = CGFloat.random(in: 0.6...1.4)
                let color = [c1, c2, c3].randomElement()!
                color.setStroke()
                ctx.setLineWidth(w)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -1.2...1.2), y: y - h))
                ctx.strokePath()
            }

            // Soft blotches for larger-scale variation
            for _ in 0..<40 {
                let r = CGFloat.random(in: 6...18)
                let rect = CGRect(
                    x: CGFloat.random(in: -r...(CGFloat(size))),
                    y: CGFloat.random(in: -r...(CGFloat(size))),
                    width: r * 2,
                    height: r * 2
                )
                c2.withAlphaComponent(0.18).setFill()
                ctx.fillEllipse(in: rect)
            }

            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    private static func barkTexture(base: UIColor, streak: UIColor) -> UIImage {
        let key = "bark-\(base.description)"
        return cached(key) {
            let size = 64
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<50 {
                streak.withAlphaComponent(CGFloat.random(in: 0.25...0.55)).setStroke()
                ctx.setLineWidth(CGFloat.random(in: 0.8...2.2))
                let x = CGFloat.random(in: 0..<CGFloat(size))
                ctx.move(to: CGPoint(x: x, y: 0))
                ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -3...3), y: CGFloat(size)))
                ctx.strokePath()
            }
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    private static func foliageTexture(base: UIColor) -> UIImage {
        let key = "leaf-\(base.description)"
        return cached(key) {
            let size = 64
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            base.getRed(&r, green: &g, blue: &b, alpha: &a)
            let light = UIColor(red: min(1, r + 0.12), green: min(1, g + 0.14), blue: min(1, b + 0.08), alpha: 1)
            let dark = UIColor(red: max(0, r - 0.1), green: max(0, g - 0.12), blue: max(0, b - 0.06), alpha: 1)
            for _ in 0..<120 {
                let color = Bool.random() ? light : dark
                color.withAlphaComponent(0.45).setFill()
                let s = CGFloat.random(in: 3...9)
                ctx.fillEllipse(
                    in: CGRect(
                        x: CGFloat.random(in: 0..<CGFloat(size)),
                        y: CGFloat.random(in: 0..<CGFloat(size)),
                        width: s,
                        height: s * CGFloat.random(in: 0.6...1.1)
                    )
                )
            }
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    private static func rockTexture(base: UIColor) -> UIImage {
        let key = "rock-\(base.description)"
        return cached(key) {
            let size = 64
            UIGraphicsBeginImageContextWithOptions(CGSize(width: size, height: size), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            base.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            for _ in 0..<80 {
                UIColor(white: CGFloat.random(in: 0.2...0.7), alpha: 0.2).setFill()
                let s = CGFloat.random(in: 2...10)
                ctx.fillEllipse(
                    in: CGRect(
                        x: CGFloat.random(in: 0..<CGFloat(size)),
                        y: CGFloat.random(in: 0..<CGFloat(size)),
                        width: s,
                        height: s
                    )
                )
            }
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    private static func blendedGroundTexture(from: Biome, to: Biome) -> UIImage {
        let key = "blend-\(from.displayName)-\(to.displayName)"
        return cached(key) {
            let width = 128
            let height = 256
            UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), true, 1)
            guard let ctx = UIGraphicsGetCurrentContext() else {
                UIGraphicsEndImageContext()
                return UIImage()
            }
            for y in 0..<height {
                let raw = CGFloat(y) / CGFloat(max(height - 1, 1))
                // Ease in/out so the middle of the chunk carries most of the change.
                let t = raw * raw * (3 - 2 * raw)
                let color = lerpColor(from.groundColor, to.groundColor, t: t)
                color.setFill()
                ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
            }
            // Soft flecks so it still reads as ground, not a flat gradient.
            for _ in 0..<900 {
                let y = Int.random(in: 0..<height)
                let raw = CGFloat(y) / CGFloat(max(height - 1, 1))
                let t = raw * raw * (3 - 2 * raw)
                let base = lerpColor(from.groundColor, to.groundColor, t: t)
                let fleck = Bool.random() ? lighten(base, 0.08) : darken(base, 0.08)
                fleck.withAlphaComponent(0.35).setFill()
                let s = CGFloat.random(in: 1.2...3.5)
                ctx.fill(
                    CGRect(
                        x: CGFloat.random(in: 0..<CGFloat(width)),
                        y: CGFloat(y),
                        width: s,
                        height: CGFloat.random(in: 2...6)
                    )
                )
            }
            let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
            UIGraphicsEndImageContext()
            return image
        }
    }

    static func lerpColor(_ a: UIColor, _ b: UIColor, t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let u = max(0, min(1, t))
        return UIColor(
            red: ar + (br - ar) * u,
            green: ag + (bg - ag) * u,
            blue: ab + (bb - ab) * u,
            alpha: aa + (ba - aa) * u
        )
    }

    private static func lighten(_ color: UIColor, _ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: min(1, r + amount),
            green: min(1, g + amount),
            blue: min(1, b + amount),
            alpha: a
        )
    }

    private static func darken(_ color: UIColor, _ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(
            red: max(0, r - amount),
            green: max(0, g - amount),
            blue: max(0, b - amount),
            alpha: a
        )
    }

    private static func makeVerticalGradient(size: CGSize, top: UIColor, bottom: UIColor) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, true, 1)
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return UIImage()
        }
        let colors = [top.cgColor, bottom.cgColor] as CFArray
        let space = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) else {
            UIGraphicsEndImageContext()
            return UIImage()
        }
        ctx.drawLinearGradient(
            gradient,
            start: .zero,
            end: CGPoint(x: 0, y: size.height),
            options: []
        )
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }

    private static func cached(_ key: String, build: () -> UIImage) -> UIImage {
        if let hit = textureCache[key] { return hit }
        let image = build()
        textureCache[key] = image
        return image
    }
}
