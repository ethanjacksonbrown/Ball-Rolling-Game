import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameSceneController()

    private var showsGameWorld: Bool {
        switch game.state {
        case .playing, .dead, .won: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            SceneKitGameView(game: game)
                .ignoresSafeArea()

            // Separate menu screen — covers the 3D world until a biome is played.
            if !showsGameWorld {
                menuBackground
                    .ignoresSafeArea()
            }

            VStack {
                if game.state == .playing || game.state == .dead || game.state == .won {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(game.distance)m / \(game.raceLengthMeters)m")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.black.opacity(0.35), in: Capsule())

                            Text(game.selectedLevel.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.35), in: Capsule())

                            coinBadge(text: "\(game.runCoins)", subtitle: "this run")
                        }

                        Spacer()

                        leaderboard
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                }

                Spacer()

                switch game.state {
                case .menu:
                    mainMenu
                        .padding(.bottom, 48)
                case .levelSelect:
                    levelSelect
                        .padding(.bottom, 36)
                case .skinShop:
                    skinShop
                        .padding(.bottom, 36)
                case .powerUpShop:
                    powerUpShop
                        .padding(.bottom, 36)
                case .dead:
                    finishCard(won: false)
                        .padding(.bottom, 48)
                case .won:
                    finishCard(won: true)
                        .padding(.bottom, 48)
                case .playing:
                    powerUpHUD
                        .padding(.bottom, 36)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
    }

    private var menuBackground: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.16, blue: 0.28),
                Color(red: 0.16, green: 0.28, blue: 0.42),
                Color(red: 0.22, green: 0.38, blue: 0.48)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var mainMenu: some View {
        VStack(spacing: 18) {
            Text("Ball Roll")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            coinBadge(text: "\(game.totalCoins)", subtitle: "total coins")

            Text("Race four bots to the finish line.\nBounce off trees and rocks — first across wins!")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            menuButton(title: "Level Select", color: .orange) {
                game.openLevelSelect()
            }

            menuButton(title: "Skin Shop", color: Color(red: 0.22, green: 0.52, blue: 0.86)) {
                game.openSkinShop()
            }

            menuButton(title: "Power-ups", color: Color(red: 0.18, green: 0.62, blue: 0.48)) {
                game.openPowerUpShop()
            }
        }
        .padding(24)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 28)
    }

    private var levelSelect: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Level Select")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("Back") {
                    game.returnToMenu()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.18), in: Capsule())
            }

            Text("Tap a biome to start racing there.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(Biome.allCases, id: \.self) { biome in
                levelRow(biome)
            }
        }
        .padding(20)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 22)
    }

    private func levelRow(_ biome: Biome) -> some View {
        Button {
            game.playLevel(biome)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(biome.groundColor))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(biome.displayName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(biome.levelSubtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Text("Play")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.orange, in: Capsule())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Standings")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))

            ForEach(game.standings) { row in
                HStack(spacing: 8) {
                    Text("\(row.place)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 16, alignment: .trailing)

                    Text(row.name)
                        .font(.system(size: 14, weight: row.isPlayer ? .heavy : .semibold, design: .rounded))
                        .foregroundStyle(row.isPlayer ? Color.orange : .white)

                    Spacer(minLength: 4)

                    if row.hasFinished {
                        Text("FIN")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    } else if row.isOut {
                        Text("OUT")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.red.opacity(0.9))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 148, alignment: .leading)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func finishCard(won: Bool) -> some View {
        VStack(spacing: 16) {
            Text(won ? "You Win!" : "Race Over")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text(placeLabel(game.finishPlace))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(won ? Color.orange : .white.opacity(0.95))

            Text("\(game.distance)m of \(game.raceLengthMeters)m · \(game.selectedLevel.displayName)")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            coinBadge(text: "+\(game.runCoins)", subtitle: "coins this race")

            menuButton(title: "Play Again", color: .orange) {
                game.startPlay()
            }

            menuButton(title: "Return to Main Menu", color: Color(white: 0.28)) {
                game.returnToMenu()
            }
        }
        .padding(24)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 28)
    }

    private func placeLabel(_ place: Int) -> String {
        switch place {
        case 1: return "1st place — first to the finish!"
        case 2: return "2nd place"
        case 3: return "3rd place"
        default: return "\(place)th place"
        }
    }

    private var skinShop: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Skin Shop")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button("Back") {
                    game.returnToMenu()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.18), in: Capsule())
            }

            Text("Equip a ball for your next run.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(BallSkin.allCases) { skin in
                skinRow(skin)
            }
        }
        .padding(20)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 22)
    }

    private var powerUpShop: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("Power-ups")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                coinBadge(text: "\(game.totalCoins)", subtitle: "coins")

                Button("Back") {
                    game.returnToMenu()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.18), in: Capsule())
            }

            Text("Unlock once for every biome. Equip one, tap it during a race.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(PowerUpType.allCases) { type in
                        powerUpRow(type)
                    }
                }
            }
            .frame(maxHeight: 440)
        }
        .padding(20)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 22)
    }

    private func powerUpRow(_ type: PowerUpType) -> some View {
        let level = game.powerUpLevels[type] ?? 0
        let owned = level >= 1
        let equipped = game.equippedPowerUp == type
        let maxed = level >= PowerUpStats.maxLevel
        let unlockCost = type.unlockCost
        let upgradeCost = owned && !maxed ? type.upgradeCost(fromLevel: level) : 0
        let canAffordUnlock = game.totalCoins >= unlockCost
        let canAffordUpgrade = game.totalCoins >= upgradeCost

        return HStack(spacing: 12) {
            powerUpIcon(type, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text(type.displayName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(type.subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)

                if owned {
                    powerUpLevelDots(level: level)
                } else {
                    Text("Locked")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                if !owned {
                    powerUpActionChip(
                        title: "\(unlockCost)",
                        showsCoin: true,
                        tint: canAffordUnlock
                            ? Color(red: 0.18, green: 0.62, blue: 0.48)
                            : Color.white.opacity(0.16),
                        enabled: canAffordUnlock
                    ) {
                        game.purchasePowerUp(type)
                    }
                } else {
                    if maxed {
                        Text("MAX")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    } else {
                        powerUpActionChip(
                            title: "\(upgradeCost)",
                            showsCoin: true,
                            tint: canAffordUpgrade
                                ? Color(red: 0.22, green: 0.52, blue: 0.86)
                                : Color.white.opacity(0.16),
                            enabled: canAffordUpgrade
                        ) {
                            game.upgradePowerUp(type)
                        }
                    }

                    powerUpActionChip(
                        title: equipped ? "Equipped" : "Equip",
                        showsCoin: false,
                        tint: equipped ? Color.orange.opacity(0.28) : Color.white.opacity(0.12),
                        foreground: equipped ? Color.orange : .white,
                        enabled: true
                    ) {
                        game.equipPowerUp(type)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(equipped ? 0.16 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(equipped ? Color.orange : Color.white.opacity(0.06), lineWidth: equipped ? 2 : 1)
                )
        )
    }

    private func powerUpLevelDots(level: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(1...PowerUpStats.maxLevel, id: \.self) { i in
                Capsule()
                    .fill(i <= level ? Color.orange : Color.white.opacity(0.18))
                    .frame(width: i <= level ? 14 : 8, height: 4)
            }
        }
    }

    private func powerUpActionChip(
        title: String,
        showsCoin: Bool,
        tint: Color,
        foreground: Color = .white,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if showsCoin {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.78, blue: 0.18))
                        .frame(width: 10, height: 10)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(foreground.opacity(enabled ? 1 : 0.55))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func powerUpAccent(_ type: PowerUpType) -> Color {
        switch type {
        case .speedBoost: return Color(red: 0.98, green: 0.55, blue: 0.18)
        case .coinMagnet: return Color(red: 0.95, green: 0.78, blue: 0.18)
        case .ghost: return Color(red: 0.70, green: 0.80, blue: 0.95)
        case .shield: return Color(red: 0.30, green: 0.72, blue: 0.95)
        case .slowPulse: return Color(red: 0.72, green: 0.42, blue: 0.95)
        }
    }

    private func powerUpSymbol(_ type: PowerUpType) -> String {
        switch type {
        case .speedBoost: return "bolt.fill"
        case .coinMagnet: return "dollarsign.circle.fill"
        case .ghost: return "eye.slash.fill"
        case .shield: return "shield.fill"
        case .slowPulse: return "tortoise.fill"
        }
    }

    private func powerUpIcon(_ type: PowerUpType, size: CGFloat) -> some View {
        let color = powerUpAccent(type)
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: powerUpSymbol(type))
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var powerUpHUD: some View {
        if let type = game.equippedPowerUp {
            let accent = powerUpAccent(type)
            let ready = game.powerUpReady
            let active = game.powerUpEffectActive
            let cooldown = max(0, game.powerUpCooldownRemaining)
            let statusText: String = {
                if active { return "Active" }
                if cooldown > 0 { return String(format: "%.0fs", ceil(Double(cooldown))) }
                return "Tap"
            }()

            Button {
                game.activateEquippedPowerUp()
            } label: {
                VStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .frame(width: 72, height: 72)

                        Circle()
                            .strokeBorder(accent.opacity(ready || active ? 0.95 : 0.35), lineWidth: 3)
                            .frame(width: 72, height: 72)

                        powerUpIcon(type, size: 48)
                            .clipShape(Circle())
                            .opacity(ready || active ? 1 : 0.4)

                        if !ready && !active && cooldown > 0 {
                            Text(String(format: "%.0f", ceil(Double(cooldown))))
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        }
                    }

                    Text(statusText)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(active ? accent : .white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.4), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .disabled(!ready)
            .accessibilityLabel("\(type.displayName), \(statusText)")
        }
    }

    private func skinRow(_ skin: BallSkin) -> some View {
        let selected = game.selectedSkin == skin
        return Button {
            game.selectSkin(skin)
        } label: {
            HStack(spacing: 14) {
                skinPreview(skin)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(skin.displayName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(skin.subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Text(selected ? "Equipped" : "Select")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? Color.orange : .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        (selected ? Color.orange.opacity(0.2) : Color.white.opacity(0.12)),
                        in: Capsule()
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(selected ? 0.16 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Color.orange : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func skinPreview(_ skin: BallSkin) -> some View {
        let image: UIImage? = {
            switch skin {
            case .soccer: return GameArt.soccerBallTexture()
            case .basketball: return GameArt.basketballTexture()
            case .tennis: return GameArt.tennisBallTexture()
            case .beachBall: return GameArt.beachBallTexture()
            case .marble: return GameArt.marbleBallTexture()
            case .classic, .gold, .neon: return nil
            }
        }()

        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color(skin.previewColor))
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
        .shadow(
            color: skin == .neon ? Color(red: 0.15, green: 0.95, blue: 0.85).opacity(0.55) : .clear,
            radius: skin == .neon ? 6 : 0
        )
    }

    private func coinBadge(text: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0.95, green: 0.78, blue: 0.18))
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .strokeBorder(Color(red: 0.85, green: 0.62, blue: 0.12), lineWidth: 2)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.35), in: Capsule())
    }

    private func menuButton(title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: 260)
                .padding(.vertical, 14)
                .background(color, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
