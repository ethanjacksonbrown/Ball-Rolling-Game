import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameSceneController()
    @ObservedObject private var ads = AdManager.shared
    @State private var sfxVolumePercent: Double = Double(SoundSettings.masterVolume * 100)
    @State private var musicVolumePercent: Double = Double(SoundSettings.musicVolume * 100)
    @State private var rewardedClaimedThisRace = false

    private var showsGameWorld: Bool {
        switch game.state {
        case .playing, .paused, .dead, .won: return true
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
                if game.state == .playing || game.state == .paused || game.state == .dead || game.state == .won {
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

                if game.state != .menu && game.state != .biomeRoulette {
                    Spacer()
                }

                switch game.state {
                case .menu:
                    mainMenu
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .biomeRoulette:
                    biomeRoulette
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .skinShop:
                    skinShop
                        .padding(.bottom, 36)
                case .powerUpShop:
                    powerUpShop
                        .padding(.bottom, 36)
                case .settings:
                    settingsPanel
                        .padding(.bottom, 36)
                case .dead:
                    finishCard(won: false)
                        .padding(.bottom, 48)
                case .won:
                    finishCard(won: true)
                        .padding(.bottom, 48)
                case .playing:
                    HStack(alignment: .bottom) {
                        pauseButton
                            .padding(.leading, 16)
                        Spacer()
                        powerUpHUD
                            .padding(.trailing, 16)
                    }
                    .padding(.bottom, 36)
                case .paused:
                    pauseMenu
                        .padding(.bottom, 48)
                }
            }
        }
        .onAppear {
            GameMusic.shared.prepare()
            GameMusic.shared.setRacing(game.state == .playing)
            GameMusic.shared.start()
            AdManager.shared.startIfNeeded()
        }
        .onChange(of: game.state) { _, state in
            GameMusic.shared.setRacing(state == .playing)
            if state == .won || state == .dead {
                rewardedClaimedThisRace = false
                AdManager.shared.onRaceFinished()
            }
        }
    }

    private var menuBackground: some View {
        GeometryReader { geo in
            let useLandscape = geo.size.width > geo.size.height
            ZStack {
                Image(useLandscape ? "MenuHeroLandscape" : "MenuHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Keep the scenic art readable while CTA text stays sharp.
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.18),
                        Color.black.opacity(0.08),
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.82)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }

    private var mainMenu: some View {
        GeometryReader { geo in
            let isWide = geo.size.width > geo.size.height || geo.size.width >= 700
            let titleSize: CGFloat = isWide ? 72 : 42

            VStack(spacing: 0) {
                VStack(spacing: isWide ? 18 : 14) {
                    Text("BIOME RACING")
                        .font(.system(size: titleSize, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
                        .minimumScaleFactor(0.65)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)

                    coinBadge(text: "\(game.totalCoins)", subtitle: "total coins")
                }
                .padding(.top, isWide ? 28 : 16)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    menuButton(title: "Play", color: Color(red: 0.98, green: 0.52, blue: 0.16)) {
                        game.openBiomeRoulette()
                    }

                    menuButton(title: "Skins", color: Color(red: 0.18, green: 0.48, blue: 0.78)) {
                        game.openSkinShop()
                    }

                    menuButton(title: "Power-ups", color: Color(red: 0.14, green: 0.58, blue: 0.44)) {
                        game.openPowerUpShop()
                    }

                    menuButton(title: "Settings", color: Color(white: 0.28)) {
                        sfxVolumePercent = Double(SoundSettings.masterVolume * 100)
                        musicVolumePercent = Double(SoundSettings.musicVolume * 100)
                        game.openSettings()
                    }
                }
                .padding(.bottom, isWide ? 56 : 48)
            }
            .padding(.horizontal, isWide ? 48 : 28)
            .frame(maxWidth: isWide ? 560 : 420)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private var biomeRoulette: some View {
        BiomeRouletteView { biome in
            game.playLevel(biome)
        } onCancel: {
            game.returnToMenu()
        }
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

            if !rewardedClaimedThisRace {
                menuButton(
                    title: ads.isRewardedReady
                        ? "Watch Ad · +\(AdConfig.rewardedCoinBonus) Coins"
                        : "Bonus Ad Loading…",
                    color: Color(red: 0.55, green: 0.35, blue: 0.85)
                ) {
                    guard ads.isRewardedReady else { return }
                    AdManager.shared.presentRewarded { earned in
                        guard earned else { return }
                        game.grantBonusCoins(AdConfig.rewardedCoinBonus)
                        rewardedClaimedThisRace = true
                    }
                }
                .disabled(!ads.isRewardedReady)
                .opacity(ads.isRewardedReady ? 1 : 0.55)
            } else {
                Text("+\(AdConfig.rewardedCoinBonus) bonus coins claimed")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
            }

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
            HStack(alignment: .center, spacing: 12) {
                Text("Skin Shop")
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

            Text("Classic is free. Unlock the rest with coins, then equip one.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(BallSkin.allCases) { skin in
                        skinRow(skin)
                    }
                }
            }
            .frame(maxHeight: 440)
        }
        .padding(20)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 22)
    }

    private var settingsPanel: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text("Settings")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                Button("Back") {
                    game.returnToMenu()
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.18), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 18) {
                volumeRow(
                    title: "Music",
                    percent: $musicVolumePercent,
                    playsPreviewSound: false
                ) { value in
                    SoundSettings.musicVolume = Float(value / 100)
                    GameMusic.shared.refreshFromSettings()
                }

                volumeRow(
                    title: "Sound Effects",
                    percent: $sfxVolumePercent,
                    playsPreviewSound: true
                ) { value in
                    SoundSettings.masterVolume = Float(value / 100)
                }

                Text("Music and sound effects are separate — turn effects down and keep the song, or the other way around.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 22)
    }

    private func volumeRow(
        title: String,
        percent: Binding<Double>,
        playsPreviewSound: Bool,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        let binding = Binding<Double>(
            get: { percent.wrappedValue },
            set: { newValue in
                percent.wrappedValue = newValue
                onChange(newValue)
            }
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(percent.wrappedValue.rounded()))%")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.orange)
                    .monospacedDigit()
            }

            Slider(value: binding, in: 0...100, step: 1) { editing in
                if !editing && playsPreviewSound {
                    CoinSFX.shared.play(count: 1)
                }
            }
            .tint(.orange)
        }
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
        case .slowPulse: return Color(red: 0.72, green: 0.42, blue: 0.95)
        }
    }

    private func powerUpSymbol(_ type: PowerUpType) -> String {
        switch type {
        case .speedBoost: return "bolt.fill"
        case .coinMagnet: return "dollarsign.circle.fill"
        case .ghost: return "eye.slash.fill"
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
    private var pauseButton: some View {
        Button {
            game.pauseRun()
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pause")
    }

    private var pauseMenu: some View {
        VStack(spacing: 18) {
            Text("Paused")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("The race is frozen until you continue.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            menuButton(title: "Resume Run", color: .orange) {
                game.resumeRun()
            }

            menuButton(title: "Exit", color: Color(white: 0.28)) {
                game.exitRun()
            }
        }
        .padding(24)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 28)
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
        let owned = game.ownedSkins.contains(skin) || skin.isFree
        let selected = game.selectedSkin == skin
        let cost = skin.coinCost
        let canAfford = game.totalCoins >= cost

        return HStack(spacing: 14) {
            skinPreview(skin)
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 4) {
                Text(skin.displayName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(skin.subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                if !owned {
                    Text("\(cost) coins")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.95, green: 0.78, blue: 0.18))
                }
            }

            Spacer()

            if owned {
                Button {
                    game.selectSkin(skin)
                } label: {
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
                .buttonStyle(.plain)
                .disabled(selected)
            } else {
                Button {
                    game.purchaseSkin(skin)
                } label: {
                    Text(canAfford ? "Buy" : "Need coins")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(canAfford ? .white : .white.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            (canAfford ? Color.orange : Color.white.opacity(0.12)),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canAfford)
            }
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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(color)
                        .shadow(color: color.opacity(0.45), radius: 10, y: 4)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: 300)
    }
}

#Preview {
    ContentView()
}
