import SceneKit
import UIKit

enum Biome: CaseIterable {
    case swamp
    case forest
    case lava
    case snow
    case tropical

    var groundColor: UIColor {
        switch self {
        case .swamp: return UIColor(red: 0.30, green: 0.48, blue: 0.28, alpha: 1)
        case .forest: return UIColor(red: 0.28, green: 0.45, blue: 0.22, alpha: 1)
        case .lava: return UIColor(red: 0.22, green: 0.12, blue: 0.10, alpha: 1)
        case .snow: return UIColor(red: 0.88, green: 0.93, blue: 0.97, alpha: 1)
        case .tropical: return UIColor(red: 0.72, green: 0.68, blue: 0.38, alpha: 1)
        }
    }

    var hazardColor: UIColor {
        switch self {
        case .swamp: return UIColor(red: 0.18, green: 0.42, blue: 0.55, alpha: 1)
        case .forest: return UIColor(red: 0.12, green: 0.35, blue: 0.70, alpha: 1)
        case .lava: return UIColor(red: 0.95, green: 0.30, blue: 0.08, alpha: 1)
        case .snow: return UIColor(red: 0.35, green: 0.55, blue: 0.78, alpha: 1)
        case .tropical: return UIColor(red: 0.10, green: 0.55, blue: 0.72, alpha: 1)
        }
    }

    /// Shared water surface color so swamp/forest/snow/tropical don't seam.
    /// Lava uses dark ash water — molten look comes from volcanoes / rivers, not side oceans.
    var waterSurfaceColor: UIColor {
        switch self {
        case .lava:
            return UIColor(red: 0.10, green: 0.07, blue: 0.07, alpha: 1)
        case .tropical:
            return UIColor(red: 0.12, green: 0.58, blue: 0.78, alpha: 1)
        default:
            return UIColor(red: 0.16, green: 0.48, blue: 0.72, alpha: 1)
        }
    }

    var wallColor: UIColor {
        switch self {
        case .swamp: return UIColor(red: 0.40, green: 0.35, blue: 0.22, alpha: 1)
        case .forest: return UIColor(red: 0.40, green: 0.28, blue: 0.18, alpha: 1)
        case .lava: return UIColor(red: 0.35, green: 0.18, blue: 0.14, alpha: 1)
        case .snow: return UIColor(red: 0.70, green: 0.78, blue: 0.86, alpha: 1)
        case .tropical: return UIColor(red: 0.78, green: 0.70, blue: 0.42, alpha: 1)
        }
    }

    var pondColor: UIColor {
        UIColor(red: 0.20, green: 0.45, blue: 0.42, alpha: 0.92)
    }

    var iceColor: UIColor {
        UIColor(red: 0.62, green: 0.84, blue: 0.95, alpha: 0.88)
    }

    var displayName: String {
        switch self {
        case .swamp: return "Swamp"
        case .forest: return "Forest"
        case .lava: return "Lava"
        case .snow: return "Snow"
        case .tropical: return "Beach"
        }
    }

    var levelSubtitle: String {
        switch self {
        case .swamp: return "Murky ponds, willows, alligators, and frogs"
        case .forest: return "Woods, bushes, bears, and bunnies"
        case .lava: return "Volcanoes, geysers, and lava lizards"
        case .snow: return "Ice, pines, polar bears, and moose"
        case .tropical: return "Sand dunes, crabs, and sea turtles"
        }
    }

    var rouletteSymbol: String {
        switch self {
        case .swamp: return "leaf.fill"
        case .forest: return "tree.fill"
        case .lava: return "flame.fill"
        case .snow: return "snowflake"
        case .tropical: return "sun.max.fill"
        }
    }

    var rouletteAccent: UIColor {
        switch self {
        case .swamp: return UIColor(red: 0.35, green: 0.72, blue: 0.42, alpha: 1)
        case .forest: return UIColor(red: 0.28, green: 0.62, blue: 0.32, alpha: 1)
        case .lava: return UIColor(red: 0.98, green: 0.42, blue: 0.16, alpha: 1)
        case .snow: return UIColor(red: 0.72, green: 0.88, blue: 1.0, alpha: 1)
        case .tropical: return UIColor(red: 0.98, green: 0.78, blue: 0.28, alpha: 1)
        }
    }
}

enum TerrainProfiles {
    /// Soft elliptical mound that tapers in both X and Z (localX in [-halfW, halfW], t in 0...1).
    static func localMound(peak: Float, halfWidth: Float) -> (Float, Float) -> Float {
        { localX, t in
            let u = max(0, min(1, (localX + halfWidth) / max(halfWidth * 2, 0.0001)))
            let across = sin(Float.pi * u)
            let along = sin(Float.pi * t)
            return peak * across * along
        }
    }

    /// Localized natural hill — rounded dome, not a full-width shelf.
    static func naturalHill(peak: Float, halfWidth: Float) -> (Float, Float) -> Float {
        { localX, t in
            let nx = localX / max(halfWidth, 0.0001) // -1...1
            // Stretch slightly along Z so hills feel organic, not circular blobs.
            let nz = (t - 0.48) * 2.15
            let r2 = nx * nx * 1.05 + nz * nz * 0.92
            guard r2 < 1.02 else { return 0 }
            let dome = pow(max(0, 1 - r2), 1.05)
            // Gentle crown so the top isn't perfectly flat.
            let crown = 0.88 + 0.12 * sin(Float.pi * max(0, min(1, t)))
            return peak * dome * crown
        }
    }

    static func sineHill(peak: Float) -> (Float, Float) -> Float {
        { _, t in peak * sin(Float.pi * t) }
    }

    static func jumpRamp(peak: Float) -> (Float, Float) -> Float {
        { _, t in
            let s = t * t * (3 - 2 * t)
            return peak * s
        }
    }

    static func divot(depth: Float) -> (Float, Float) -> Float {
        { localX, t in
            // Bowl that also softens toward the X edges of the divot mesh.
            // localX unused meaningfully without width — callers pass world-relative via mesh local space.
            _ = localX
            return -depth * sin(Float.pi * t)
        }
    }

    static func divotBowl(depth: Float, halfWidth: Float) -> (Float, Float) -> Float {
        { localX, t in
            let u = max(0, min(1, (localX + halfWidth) / max(halfWidth * 2, 0.0001)))
            let across = sin(Float.pi * u)
            let along = sin(Float.pi * t)
            return -depth * across * along
        }
    }
}
