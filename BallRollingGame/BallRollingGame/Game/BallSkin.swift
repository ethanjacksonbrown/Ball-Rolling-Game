import Foundation
import UIKit

enum BallSkin: String, CaseIterable, Identifiable, Equatable {
    case classic
    case soccer
    case basketball
    case tennis
    case beachBall
    case gold
    case neon
    case marble

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .soccer: return "Soccer Ball"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis Ball"
        case .beachBall: return "Beach Ball"
        case .gold: return "Gold"
        case .neon: return "Neon"
        case .marble: return "Marble"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "The original red roller"
        case .soccer: return "Black & white match ball"
        case .basketball: return "Orange court classic"
        case .tennis: return "Fuzzy neon yellow"
        case .beachBall: return "Sunny striped floater"
        case .gold: return "Shiny treasure finish"
        case .neon: return "Glow-in-the-fast-lane"
        case .marble: return "Swirled stone polish"
        }
    }

    /// Simple shop preview tint when no custom texture is used.
    var previewColor: UIColor {
        switch self {
        case .classic: return UIColor(red: 0.92, green: 0.28, blue: 0.22, alpha: 1)
        case .soccer: return UIColor.white
        case .basketball: return UIColor(red: 0.92, green: 0.45, blue: 0.12, alpha: 1)
        case .tennis: return UIColor(red: 0.82, green: 0.92, blue: 0.18, alpha: 1)
        case .beachBall: return UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1)
        case .gold: return UIColor(red: 0.95, green: 0.78, blue: 0.22, alpha: 1)
        case .neon: return UIColor(red: 0.15, green: 0.95, blue: 0.85, alpha: 1)
        case .marble: return UIColor(red: 0.88, green: 0.90, blue: 0.94, alpha: 1)
        }
    }
}

enum SkinStore {
    private static let key = "selectedBallSkin"

    static var selected: BallSkin {
        get {
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let skin = BallSkin(rawValue: raw) else {
                return .classic
            }
            return skin
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
        }
    }
}
