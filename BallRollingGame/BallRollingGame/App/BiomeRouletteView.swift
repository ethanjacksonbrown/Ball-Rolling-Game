import SwiftUI
import UIKit

/// Brawl Stars–style biome picker: cards scroll left→right and ease to a stop (~5s).
struct BiomeRouletteView: View {
    var onComplete: (Biome) -> Void
    var onCancel: () -> Void

    private let cardWidth: CGFloat = 132
    private let cardHeight: CGFloat = 168
    private let spacing: CGFloat = 14
    private let spinDuration: Double = 5.0
    private let cyclesBeforeLanding = 8

    private struct ReelCard: Identifiable {
        let id: Int
        let biome: Biome
        let preview: UIImage
    }

    @State private var offsetX: CGFloat = 0
    @State private var reel: [ReelCard] = []
    @State private var winner: Biome = .forest
    @State private var winnerIndex: Int = 0
    @State private var phase: Phase = .ready
    @State private var highlightPulse = false

    private enum Phase {
        case ready
        case spinning
        case landed
    }

    private var cellWidth: CGFloat { cardWidth + spacing }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Finding Biome")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if phase != .spinning && phase != .landed {
                    Button("Back") { onCancel() }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.18), in: Capsule())
                }
            }

            Text(statusText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.35))

                GeometryReader { geo in
                    let centerX = geo.size.width * 0.5
                    HStack(spacing: spacing) {
                        ForEach(reel) { card in
                            biomeCard(card, emphasized: phase != .spinning && card.id == winnerIndex)
                                .frame(width: cardWidth, height: cardHeight)
                        }
                    }
                    .offset(x: offsetX + centerX - cardWidth * 0.5)
                }
                .frame(height: cardHeight + 28)
                .clipped()

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Color.orange.opacity(phase == .landed ? 1 : 0.9),
                        lineWidth: phase == .landed ? 4 : 3
                    )
                    .frame(width: cardWidth + 10, height: cardHeight + 10)
                    .scaleEffect(highlightPulse ? 1.04 : 1.0)
                    .shadow(color: .orange.opacity(phase == .landed ? 0.55 : 0.25), radius: 10, y: 0)
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.75), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 48)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 48)
                }
                .frame(height: cardHeight + 28)
                .allowsHitTesting(false)
            }
            .frame(height: cardHeight + 36)

            if phase == .landed {
                Text(winner.displayName.uppercased())
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Color(winner.rouletteAccent))
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(20)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 22)
        .onAppear(perform: beginSpin)
        .onDisappear {
            RouletteSFX.shared.stop()
        }
    }

    private var statusText: String {
        switch phase {
        case .ready, .spinning:
            return "Scrolling biomes… hang tight!"
        case .landed:
            return "Race starts in \(winner.displayName)!"
        }
    }

    private func biomeCard(_ card: ReelCard, emphasized: Bool) -> some View {
        ZStack(alignment: .bottom) {
            Image(uiImage: card.preview)
                .resizable()
                .scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(card.biome.displayName)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .padding(.bottom, 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(emphasized ? 0.55 : 0.18), lineWidth: emphasized ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        .scaleEffect(emphasized ? 1.03 : 1.0)
    }

    private func beginSpin() {
        let biomes = Array(Biome.allCases)

        var strip: [Biome] = []
        for _ in 0..<cyclesBeforeLanding {
            strip.append(contentsOf: biomes.shuffled())
        }
        strip.append(contentsOf: biomes.shuffled())
        strip.append(contentsOf: biomes.shuffled())

        // Lock preview art per card so Beach randomly picks one of its screenshots
        // once (50/50) and doesn't flicker on redraws.
        let cards: [ReelCard] = strip.enumerated().map { index, biome in
            ReelCard(id: index, biome: biome, preview: BiomeMapPreview.randomImage(for: biome))
        }

        let landingStart = biomes.count * cyclesBeforeLanding
        let landIndex = Int.random(in: landingStart...(cards.count - 1))
        let chosen = cards[landIndex].biome

        reel = cards
        winner = chosen
        winnerIndex = landIndex
        phase = .spinning
        offsetX = 0

        let target = -CGFloat(landIndex) * cellWidth
        RouletteSFX.shared.playSpin(duration: spinDuration)

        withAnimation(.timingCurve(0.08, 0.72, 0.12, 1.0, duration: spinDuration)) {
            offsetX = target
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration + 0.05) {
            phase = .landed
            withAnimation(.easeInOut(duration: 0.22).repeatCount(3, autoreverses: true)) {
                highlightPulse = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration + 0.85) {
            RouletteSFX.shared.stop()
            onComplete(chosen)
        }
    }
}
