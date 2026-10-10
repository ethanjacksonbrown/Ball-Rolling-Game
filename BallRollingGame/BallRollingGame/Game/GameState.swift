import Foundation

enum GameState: Equatable {
    case menu
    case biomeRoulette
    case skinShop
    case powerUpShop
    case settings
    case playing
    case paused
    case dead
    case won
}

struct RaceStanding: Identifiable, Equatable {
    let id: String
    let name: String
    let place: Int
    let isPlayer: Bool
    let hasFinished: Bool
    let isOut: Bool
}

enum PhysicsCategory {
    static let ball: Int = 1 << 0
    static let ground: Int = 1 << 1
    static let obstacle: Int = 1 << 2
    static let hazard: Int = 1 << 3
}
