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
                case .dead:
                    finishCard(won: false)
                        .padding(.bottom, 48)
                case .won:
                    finishCard(won: true)
                        .padding(.bottom, 48)
                case .playing:
                    EmptyView()
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
        switch skin {
        case .classic:
            Circle()
                .fill(Color(red: 0.92, green: 0.28, blue: 0.22))
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
        case .soccer:
            Image(uiImage: GameArt.soccerBallTexture())
                .resizable()
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 2))
        }
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
