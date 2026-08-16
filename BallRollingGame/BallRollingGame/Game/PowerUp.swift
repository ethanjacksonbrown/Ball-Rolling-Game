import Foundation

enum PowerUpType: String, CaseIterable, Identifiable, Equatable {
    case speedBoost
    case coinMagnet
    case ghost
    case shield
    case slowPulse

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speedBoost: return "Speed Boost"
        case .coinMagnet: return "Coin Magnet"
        case .ghost: return "Ghost"
        case .shield: return "Shield"
        case .slowPulse: return "Slow Pulse"
        }
    }

    var subtitle: String {
        switch self {
        case .speedBoost: return "Burst of forward speed"
        case .coinMagnet: return "Pull coins from farther away"
        case .ghost: return "Pass through obstacles briefly"
        case .shield: return "Absorb the next solid hit"
        case .slowPulse: return "Slow nearby rivals briefly"
        }
    }

    /// Types bots may be assigned (no Coin Magnet).
    static var botAssignable: [PowerUpType] {
        [.speedBoost, .ghost, .shield, .slowPulse]
    }

    /// Unlock cost for level 1.
    var unlockCost: Int {
        switch self {
        case .speedBoost: return 40
        case .coinMagnet: return 55
        case .ghost: return 70
        case .shield: return 60
        case .slowPulse: return 80
        }
    }

    /// Cost to go from `currentLevel` to `currentLevel + 1` (currentLevel must be 1...4).
    func upgradeCost(fromLevel currentLevel: Int) -> Int {
        guard currentLevel >= 1, currentLevel < PowerUpStats.maxLevel else { return 0 }
        return unlockCost * currentLevel
    }

    func stats(level: Int) -> PowerUpStats {
        PowerUpStats(type: self, level: level)
    }
}

struct PowerUpStats: Equatable {
    static let maxLevel = 5

    let type: PowerUpType
    let level: Int

    init(type: PowerUpType, level: Int) {
        self.type = type
        self.level = max(0, min(Self.maxLevel, level))
    }

    private var tier: Float {
        Float(max(0, level - 1))
    }

    var cooldown: Float {
        switch type {
        case .speedBoost: return max(8, 12 - tier * 0.5)
        case .coinMagnet: return max(10, 14 - tier * 0.5)
        case .ghost: return max(11, 16 - tier * 0.6)
        case .shield: return max(10, 14 - tier * 0.5)
        case .slowPulse: return max(11, 16 - tier * 0.6)
        }
    }

    var duration: Float {
        switch type {
        case .speedBoost: return 2.5 + tier * 0.3
        case .coinMagnet: return 4.0 + tier * 0.4
        case .ghost: return 2.5 + tier * 0.35
        case .shield: return 6.0 + tier * 0.8
        case .slowPulse: return 2.5 + tier * 0.35
        }
    }

    var speedMultiplier: Float {
        guard type == .speedBoost else { return 1 }
        return 1.45 + tier * 0.08
    }

    var magnetReach: Float {
        guard type == .coinMagnet else { return 0 }
        return 8 + tier * 1.5
    }

    var shieldCharges: Int {
        guard type == .shield else { return 0 }
        return level >= 5 ? 2 : 1
    }

    var slowMultiplier: Float {
        guard type == .slowPulse else { return 1 }
        // Milder slow: L1 ≈ 0.75×, L5 ≈ 0.63× (was 0.55→0.39).
        return max(0.60, 0.75 - tier * 0.03)
    }

    var slowRadius: Float {
        guard type == .slowPulse else { return 0 }
        return 10 + tier * 1.2
    }
}

enum PowerUpStore {
    private static let levelsKey = "powerUpLevels"
    private static let equippedKey = "equippedPowerUp"

    static func level(of type: PowerUpType) -> Int {
        levels()[type.rawValue] ?? 0
    }

    static func isOwned(_ type: PowerUpType) -> Bool {
        level(of: type) >= 1
    }

    static var equipped: PowerUpType? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: equippedKey) else { return nil }
            return PowerUpType(rawValue: raw)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: equippedKey)
            } else {
                UserDefaults.standard.removeObject(forKey: equippedKey)
            }
        }
    }

    /// Unlock at level 1 if locked. Returns false if already owned or can't afford.
    @discardableResult
    static func purchase(_ type: PowerUpType) -> Bool {
        guard level(of: type) == 0 else { return false }
        guard CoinStore.spend(type.unlockCost) else { return false }
        setLevel(1, for: type)
        if equipped == nil {
            equipped = type
        }
        return true
    }

    /// Upgrade one level if owned and below max. Returns false on failure.
    @discardableResult
    static func upgrade(_ type: PowerUpType) -> Bool {
        let current = level(of: type)
        guard current >= 1, current < PowerUpStats.maxLevel else { return false }
        let cost = type.upgradeCost(fromLevel: current)
        guard CoinStore.spend(cost) else { return false }
        setLevel(current + 1, for: type)
        return true
    }

    static func equip(_ type: PowerUpType) {
        guard isOwned(type) else { return }
        equipped = type
    }

    static func unequip() {
        equipped = nil
    }

    private static func levels() -> [String: Int] {
        (UserDefaults.standard.dictionary(forKey: levelsKey) as? [String: Int]) ?? [:]
    }

    private static func setLevel(_ level: Int, for type: PowerUpType) {
        var map = levels()
        map[type.rawValue] = level
        UserDefaults.standard.set(map, forKey: levelsKey)
    }
}
