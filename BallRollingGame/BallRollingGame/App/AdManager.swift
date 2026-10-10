import Foundation
import GoogleMobileAds
import UIKit

/// AdMob unit IDs. Currently Google's official test IDs — swap for real ones before release.
enum AdConfig {
    static let interstitialUnitID = "ca-app-pub-3940256099942544/4411468910"
    static let rewardedUnitID = "ca-app-pub-3940256099942544/1712485313"
    /// Coins granted when a rewarded ad is finished.
    static let rewardedCoinBonus = 50
    /// Show a full-screen interstitial after every N finished races.
    static let interstitialEveryNRaces = 2
}

@MainActor
final class AdManager: NSObject, ObservableObject {
    static let shared = AdManager()

    @Published private(set) var isRewardedReady = false

    private var interstitial: InterstitialAd?
    private var rewarded: RewardedAd?
    private var racesFinished = 0
    private var interstitialDismissHandler: (() -> Void)?
    private var rewardedCompletion: ((Bool) -> Void)?
    private var didEarnRewarded = false
    private var isStarting = false
    private var didStart = false

    private override init() {
        super.init()
    }

    func startIfNeeded() {
        guard !didStart, !isStarting else { return }
        isStarting = true
        MobileAds.shared.start { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.didStart = true
                self.isStarting = false
                self.preloadAll()
            }
        }
    }

    func preloadAll() {
        loadInterstitial()
        loadRewarded()
    }

    /// Call when a race ends (win or lose). May present an interstitial.
    func onRaceFinished() {
        racesFinished += 1
        guard racesFinished % AdConfig.interstitialEveryNRaces == 0 else { return }
        presentInterstitial()
    }

    func presentInterstitial() {
        guard let ad = interstitial else {
            loadInterstitial()
            return
        }
        interstitialDismissHandler = { [weak self] in
            GameMusic.shared.start()
            self?.loadInterstitial()
        }
        GameMusic.shared.stop()
        ad.present(from: nil)
    }

    /// Optional rewarded video — grants coins only if the user earns the reward.
    func presentRewarded(completion: @escaping (Bool) -> Void) {
        guard let ad = rewarded else {
            isRewardedReady = false
            loadRewarded()
            completion(false)
            return
        }
        didEarnRewarded = false
        rewardedCompletion = completion
        GameMusic.shared.stop()
        ad.present(from: nil) { [weak self] in
            Task { @MainActor in
                self?.didEarnRewarded = true
            }
        }
    }

    private func finishRewarded(earned: Bool) {
        GameMusic.shared.start()
        let completion = rewardedCompletion
        rewardedCompletion = nil
        rewarded = nil
        isRewardedReady = false
        completion?(earned)
        loadRewarded()
    }

    private func loadInterstitial() {
        Task { @MainActor in
            do {
                let ad = try await InterstitialAd.load(
                    with: AdConfig.interstitialUnitID,
                    request: Request()
                )
                ad.fullScreenContentDelegate = self
                interstitial = ad
            } catch {
                interstitial = nil
            }
        }
    }

    private func loadRewarded() {
        isRewardedReady = false
        Task { @MainActor in
            do {
                let ad = try await RewardedAd.load(
                    with: AdConfig.rewardedUnitID,
                    request: Request()
                )
                ad.fullScreenContentDelegate = self
                rewarded = ad
                isRewardedReady = true
            } catch {
                rewarded = nil
                isRewardedReady = false
            }
        }
    }
}

extension AdManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if ad === interstitial {
            interstitial = nil
            let handler = interstitialDismissHandler
            interstitialDismissHandler = nil
            handler?()
        } else if ad === rewarded {
            finishRewarded(earned: didEarnRewarded)
        }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        if ad === interstitial {
            interstitial = nil
            let handler = interstitialDismissHandler
            interstitialDismissHandler = nil
            handler?()
            loadInterstitial()
        } else if ad === rewarded {
            finishRewarded(earned: false)
        }
    }
}
