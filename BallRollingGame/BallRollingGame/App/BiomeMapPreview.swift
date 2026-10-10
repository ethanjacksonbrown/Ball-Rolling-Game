import UIKit

/// Roulette card art: real screenshots when available, procedural fallback otherwise.
enum BiomeMapPreview {
    private static var proceduralCache: [String: UIImage] = [:]

    /// Asset catalog names for a biome. Multiple names = even random pick per card.
    static func screenshotNames(for biome: Biome) -> [String] {
        switch biome {
        case .tropical:
            return ["BiomeBeach1"]
        case .swamp:
            return ["BiomeSwamp1", "BiomeSwamp2", "BiomeSwamp3"]
        case .lava:
            return ["BiomeLava1"]
        case .snow:
            return ["BiomeSnow1"]
        case .forest:
            return []
        }
    }

    /// Picks one screenshot evenly at random when the biome has any; else procedural art.
    static func randomImage(for biome: Biome) -> UIImage {
        let names = screenshotNames(for: biome)
        if let name = names.randomElement(), let image = UIImage(named: name) {
            return image
        }
        return proceduralImage(for: biome)
    }

    static func proceduralImage(for biome: Biome, size: CGSize = CGSize(width: 264, height: 336)) -> UIImage {
        let key = "side-\(biome.displayName)-\(Int(size.width))x\(Int(size.height))"
        if let hit = proceduralCache[key] { return hit }
        let image = renderSideView(biome: biome, size: size)
        proceduralCache[key] = image
        return image
    }

    // MARK: - Procedural side-view fallback (used until screenshots are provided)

    private static func renderSideView(biome: Biome, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            let w = size.width
            let h = size.height
            drawSky(biome: biome, in: CGRect(x: 0, y: 0, width: w, height: h * 0.52), cg: cg)
            drawDistantBackdrop(biome: biome, width: w, horizonY: h * 0.46, cg: cg)
            drawGroundAndTrack(biome: biome, width: w, height: h, cg: cg)
            drawNearProps(biome: biome, width: w, height: h, cg: cg)
            drawPlayerBall(at: CGPoint(x: w * 0.50, y: h * 0.72), cg: cg)
            UIColor.black.withAlphaComponent(0.28).setFill()
            cg.fill(CGRect(x: 0, y: h * 0.78, width: w, height: h * 0.22))
        }
    }

    private static func drawSky(biome: Biome, in rect: CGRect, cg: CGContext) {
        let colors: [UIColor]
        switch biome {
        case .lava:
            colors = [
                UIColor(red: 0.55, green: 0.22, blue: 0.12, alpha: 1),
                UIColor(red: 0.92, green: 0.48, blue: 0.22, alpha: 1),
                UIColor(red: 0.28, green: 0.12, blue: 0.10, alpha: 1)
            ]
        case .snow:
            colors = [
                UIColor(red: 0.55, green: 0.72, blue: 0.90, alpha: 1),
                UIColor(red: 0.78, green: 0.88, blue: 0.96, alpha: 1),
                UIColor(red: 0.90, green: 0.94, blue: 0.98, alpha: 1)
            ]
        case .tropical:
            colors = [
                UIColor(red: 0.28, green: 0.62, blue: 0.92, alpha: 1),
                UIColor(red: 0.55, green: 0.80, blue: 0.98, alpha: 1),
                UIColor(red: 0.78, green: 0.92, blue: 1.0, alpha: 1)
            ]
        case .swamp:
            colors = [
                UIColor(red: 0.42, green: 0.52, blue: 0.40, alpha: 1),
                UIColor(red: 0.58, green: 0.66, blue: 0.50, alpha: 1),
                UIColor(red: 0.70, green: 0.74, blue: 0.58, alpha: 1)
            ]
        case .forest:
            colors = [
                UIColor(red: 0.40, green: 0.64, blue: 0.90, alpha: 1),
                UIColor(red: 0.62, green: 0.80, blue: 0.95, alpha: 1),
                UIColor(red: 0.78, green: 0.90, blue: 0.98, alpha: 1)
            ]
        }
        drawLinearGradient(cg, in: rect, colors: colors)
    }

    private static func drawDistantBackdrop(biome: Biome, width w: CGFloat, horizonY: CGFloat, cg: CGContext) {
        switch biome {
        case .snow:
            drawSnowMountains(width: w, baseY: horizonY, cg: cg)
        case .lava:
            drawVolcanoSilhouettes(width: w, baseY: horizonY, cg: cg)
        case .tropical:
            UIColor(red: 0.12, green: 0.55, blue: 0.75, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: horizonY - 4, width: w, height: 18))
        case .forest:
            UIColor(red: 0.22, green: 0.40, blue: 0.22, alpha: 1).setFill()
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0, y: horizonY + 16))
            path.addQuadCurve(to: CGPoint(x: w * 0.4, y: horizonY - 10), controlPoint: CGPoint(x: w * 0.18, y: horizonY - 22))
            path.addQuadCurve(to: CGPoint(x: w, y: horizonY + 8), controlPoint: CGPoint(x: w * 0.72, y: horizonY + 18))
            path.addLine(to: CGPoint(x: w, y: horizonY + 28))
            path.addLine(to: CGPoint(x: 0, y: horizonY + 28))
            path.close()
            path.fill()
        case .swamp:
            UIColor(red: 0.32, green: 0.42, blue: 0.30, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: horizonY, width: w, height: 24))
        }
    }

    private static func drawSnowMountains(width w: CGFloat, baseY: CGFloat, cg: CGContext) {
        let rock = UIColor(red: 0.55, green: 0.62, blue: 0.70, alpha: 1)
        let snow = UIColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1)
        for (cx, height) in [(0.18, 78.0), (0.48, 96.0), (0.78, 88.0)] as [(CGFloat, CGFloat)] {
            let x = w * cx
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x - height * 0.55, y: baseY + 8))
            path.addLine(to: CGPoint(x: x, y: baseY - height))
            path.addLine(to: CGPoint(x: x + height * 0.55, y: baseY + 8))
            path.close()
            rock.setFill()
            path.fill()
            let cap = UIBezierPath()
            cap.move(to: CGPoint(x: x - height * 0.18, y: baseY - height + height * 0.32))
            cap.addLine(to: CGPoint(x: x, y: baseY - height))
            cap.addLine(to: CGPoint(x: x + height * 0.18, y: baseY - height + height * 0.32))
            cap.close()
            snow.setFill()
            cap.fill()
        }
    }

    private static func drawVolcanoSilhouettes(width w: CGFloat, baseY: CGFloat, cg: CGContext) {
        let rock = UIColor(red: 0.22, green: 0.10, blue: 0.09, alpha: 1)
        let glow = UIColor(red: 1.0, green: 0.40, blue: 0.10, alpha: 1)
        for (cx, height) in [(0.28, 80.0), (0.7, 70.0)] as [(CGFloat, CGFloat)] {
            let x = w * cx
            let path = UIBezierPath()
            path.move(to: CGPoint(x: x - height * 0.5, y: baseY + 10))
            path.addLine(to: CGPoint(x: x - 6, y: baseY - height))
            path.addLine(to: CGPoint(x: x + 6, y: baseY - height))
            path.addLine(to: CGPoint(x: x + height * 0.5, y: baseY + 10))
            path.close()
            rock.setFill()
            path.fill()
            glow.setFill()
            cg.fillEllipse(in: CGRect(x: x - 5, y: baseY - height - 4, width: 10, height: 8))
        }
    }

    private static func drawGroundAndTrack(biome: Biome, width w: CGFloat, height h: CGFloat, cg: CGContext) {
        let horizon = h * 0.48
        let nearY = h * 0.98
        biome.waterSurfaceColor.setFill()
        let left = UIBezierPath()
        left.move(to: CGPoint(x: 0, y: horizon))
        left.addLine(to: CGPoint(x: w * 0.38, y: horizon))
        left.addLine(to: CGPoint(x: w * 0.08, y: nearY))
        left.addLine(to: CGPoint(x: 0, y: nearY))
        left.close()
        left.fill()
        let right = UIBezierPath()
        right.move(to: CGPoint(x: w * 0.62, y: horizon))
        right.addLine(to: CGPoint(x: w, y: horizon))
        right.addLine(to: CGPoint(x: w, y: nearY))
        right.addLine(to: CGPoint(x: w * 0.92, y: nearY))
        right.close()
        right.fill()
        let track = UIBezierPath()
        track.move(to: CGPoint(x: w * 0.38, y: horizon))
        track.addLine(to: CGPoint(x: w * 0.62, y: horizon))
        track.addLine(to: CGPoint(x: w * 0.92, y: nearY))
        track.addLine(to: CGPoint(x: w * 0.08, y: nearY))
        track.close()
        biome.groundColor.setFill()
        track.fill()
    }

    private static func drawNearProps(biome: Biome, width w: CGFloat, height h: CGFloat, cg: CGContext) {
        let leaf = UIColor(red: 0.16, green: 0.48, blue: 0.20, alpha: 1)
        let trunk = UIColor(red: 0.40, green: 0.26, blue: 0.14, alpha: 1)
        switch biome {
        case .forest, .snow, .swamp, .tropical, .lava:
            for (x, y, s) in [(0.18, 0.64, 1.1), (0.82, 0.70, 1.2), (0.12, 0.82, 1.35)] as [(CGFloat, CGFloat, CGFloat)] {
                trunk.setFill()
                cg.fill(CGRect(x: w * x - 2.5 * s, y: h * y - 4 * s, width: 5 * s, height: 16 * s))
                leaf.setFill()
                cg.fillEllipse(in: CGRect(x: w * x - 14 * s, y: h * y - 28 * s, width: 28 * s, height: 26 * s))
            }
        }
    }

    private static func drawPlayerBall(at point: CGPoint, cg: CGContext) {
        UIColor(red: 0.92, green: 0.28, blue: 0.22, alpha: 1).setFill()
        cg.fillEllipse(in: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18))
    }

    private static func drawLinearGradient(_ cg: CGContext, in rect: CGRect, colors: [UIColor]) {
        let cgColors = colors.map(\.cgColor) as CFArray
        var locations: [CGFloat] = []
        for i in 0..<colors.count {
            locations.append(colors.count == 1 ? 0 : CGFloat(i) / CGFloat(colors.count - 1))
        }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: cgColors,
            locations: locations
        ) else { return }
        cg.saveGState()
        cg.addRect(rect)
        cg.clip()
        cg.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: []
        )
        cg.restoreGState()
    }
}
