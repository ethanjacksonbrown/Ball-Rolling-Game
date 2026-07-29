import Foundation

/// Adaptive bot difficulty aimed slightly below the player so top-3 finishes feel normal.
enum BotDifficultyStore {
    private static let ratingKey = "botDifficultyRating"
    private static let placesKey = "botDifficultyRecentPlaces"
    private static let leadsKey = "botDifficultyRecentLeads"
    private static let historyLimit = 5
    /// Never let bots climb to true "match or beat you" strength.
    private static let maxRating: Float = 0.62

    /// 0 = easier bots, `maxRating` = still a notch under a strong player.
    static var rating: Float {
        get {
            if UserDefaults.standard.object(forKey: ratingKey) == nil {
                return 0.38
            }
            return min(maxRating, max(0, UserDefaults.standard.float(forKey: ratingKey)))
        }
        set {
            UserDefaults.standard.set(min(maxRating, max(0, newValue)), forKey: ratingKey)
        }
    }

    /// Call when a race ends. `leadMeters` is player Z minus the best rival Z
    /// (positive = ahead of the pack, negative = behind the leader).
    static func recordResult(place: Int, leadMeters: Float) {
        var places = recentPlaces()
        var leads = recentLeads()
        places.append(place)
        leads.append(leadMeters)
        if places.count > historyLimit {
            places.removeFirst(places.count - historyLimit)
            leads.removeFirst(leads.count - historyLimit)
        }
        savePlaces(places)
        saveLeads(leads)

        let avgPlace = Float(places.reduce(0, +)) / Float(places.count)
        let avgLead = leads.reduce(0, +) / Float(leads.count)

        // Aim for ~2nd place — top three should feel like the usual outcome.
        let desiredPlace: Float = 2.0
        let placeError = avgPlace - desiredPlace
        // Positive placeError (finishing 4th/5th) → drop bots hard.
        // Negative placeError (always 1st) → raise bots gently, and stay capped.
        var target = rating
        if placeError > 0 {
            target -= placeError * 0.22
        } else {
            target -= placeError * 0.08
        }

        // Big leads only nudge difficulty up a little; falling behind eases more.
        if avgLead > 100 {
            target += min(0.05, (avgLead - 100) / 800)
        } else if avgLead < -30 {
            target += max(-0.12, avgLead / 280)
        }

        // This race: leave top 3 → ease up; win by a lot → tiny bump only.
        if place >= 4 {
            target -= 0.08 + Float(place - 3) * 0.03
        } else if place == 1, leadMeters > 120 {
            target += 0.025
        } else if place == 1 {
            target += 0.012
        } else if place == 3 {
            target -= 0.01
        }

        // Stay a step under the player — never full equalizer strength.
        target = min(maxRating, max(0, target - 0.04))

        var next = rating
        next += (target - next) * 0.45
        rating = next
    }

    /// Per-bot tuning for the upcoming race — always a bit softer than a matched rival.
    static func profile(botIndex: Int) -> BotDifficultyProfile {
        let t = rating
        let skillBases: [Float] = [0.7, 0.74, 0.68, 0.76]
        let speedBases: [Float] = [0.92, 0.94, 0.91, 0.95]
        let i = min(max(botIndex, 0), 3)

        // Cap skill/speed under what a "fair mirror" of the player would be.
        let skill = min(0.93, max(0.62, skillBases[i] + t * 0.18))
        let speed = min(1.04, speedBases[i] + t * 0.12)
        // Comfortable catch-up so the pack stays near enough for a top-3 fight.
        let catchUp = 0.1 + (1 - t) * 0.18
        return BotDifficultyProfile(skill: skill, speedMultiplier: speed, catchUpStrength: catchUp)
    }

    private static func recentPlaces() -> [Int] {
        UserDefaults.standard.array(forKey: placesKey) as? [Int] ?? []
    }

    private static func recentLeads() -> [Float] {
        (UserDefaults.standard.array(forKey: leadsKey) as? [Double])?.map(Float.init) ?? []
    }

    private static func savePlaces(_ places: [Int]) {
        UserDefaults.standard.set(places, forKey: placesKey)
    }

    private static func saveLeads(_ leads: [Float]) {
        UserDefaults.standard.set(leads.map(Double.init), forKey: leadsKey)
    }
}

struct BotDifficultyProfile {
    let skill: Float
    let speedMultiplier: Float
    let catchUpStrength: Float
}
