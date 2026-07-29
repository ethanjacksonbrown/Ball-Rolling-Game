import Foundation

enum BallSkin: String, CaseIterable, Identifiable, Equatable {
    case classic
    case soccer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .soccer: return "Soccer Ball"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "The original red roller"
        case .soccer: return "Black & white match ball"
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
