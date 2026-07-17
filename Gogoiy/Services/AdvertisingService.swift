import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

enum RewardedPowerUp: String, Sendable {
    case undo
    case hint
    case recolor
    case getBlock
}

enum AdMobConfiguration {
    static var bannerAdUnitID: String {
#if DEBUG
        // Google's official iOS banner test unit. Never exercise a live unit during development.
        "ca-app-pub-3940256099942544/2435281174"
#else
        "ca-app-pub-6292495011747622/8411559201"
#endif
    }

    static var rewardedAdUnitID: String {
#if DEBUG
        // Google's official iOS rewarded test unit.
        "ca-app-pub-3940256099942544/1712485313"
#else
        "ca-app-pub-6292495011747622/2772219715"
#endif
    }
}

@MainActor
protocol AdvertisingServing: AnyObject {
    var canRequestAds: Bool { get }
    var privacyOptionsRequired: Bool { get }

    func prepare(completion: @escaping () -> Void)
    func presentRewarded(
        for powerUp: RewardedPowerUp,
        completion: @escaping (_ rewardEarned: Bool) -> Void
    )
    func presentPrivacyOptions(completion: @escaping (_ succeeded: Bool) -> Void)
    func gameDidEnd()
}

@MainActor
final class AdMobAdvertisingService: NSObject, AdvertisingServing {
    private var rewardedAd: RewardedAd?
    private var isPreparing = false
    private var preparationCallbacks: [() -> Void] = []
    private var pendingRewardCompletion: ((Bool) -> Void)?
    private var rewardWasEarned = false

    var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    func prepare(completion: @escaping () -> Void) {
        preparationCallbacks.append(completion)
        guard !isPreparing else { return }
        isPreparing = true

        let parameters = RequestParameters()
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await ConsentForm.loadAndPresentIfRequired(from: nil)
                } catch {
                    // A previous valid consent status can still allow requests after a form error.
                }
                self.finishPreparation()
            }
        }
    }

    func presentRewarded(
        for powerUp: RewardedPowerUp,
        completion: @escaping (Bool) -> Void
    ) {
        guard canRequestAds, let rewardedAd else {
            completion(false)
            Task { await loadRewardedAd() }
            return
        }

        do {
            try rewardedAd.canPresent(from: nil)
        } catch {
            completion(false)
            self.rewardedAd = nil
            Task { await loadRewardedAd() }
            return
        }

        pendingRewardCompletion = completion
        rewardWasEarned = false
        self.rewardedAd = nil
        rewardedAd.present(from: nil) { [weak self] in
            guard let self else { return }
            self.rewardWasEarned = true
            self.pendingRewardCompletion?(true)
            self.pendingRewardCompletion = nil
        }
    }

    func presentPrivacyOptions(completion: @escaping (Bool) -> Void) {
        Task { @MainActor in
            do {
                try await ConsentForm.presentPrivacyOptionsForm(from: nil)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    func gameDidEnd() {
        // Intentionally no forced interstitial. Gogoiy monetizes with an unobtrusive
        // home banner and explicitly user-initiated rewarded power-ups.
    }

    private func finishPreparation() {
        isPreparing = false
        if canRequestAds {
            MobileAds.shared.start()
            Task { await loadRewardedAd() }
        }
        let callbacks = preparationCallbacks
        preparationCallbacks.removeAll()
        callbacks.forEach { $0() }
    }

    private func loadRewardedAd() async {
        guard canRequestAds, rewardedAd == nil else { return }
        do {
            let ad = try await RewardedAd.load(
                with: AdMobConfiguration.rewardedAdUnitID,
                request: Request()
            )
            ad.fullScreenContentDelegate = self
            rewardedAd = ad
        } catch {
            rewardedAd = nil
        }
    }
}

extension AdMobAdvertisingService: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        if !rewardWasEarned {
            pendingRewardCompletion?(false)
            pendingRewardCompletion = nil
        }
        Task { await loadRewardedAd() }
    }

    func ad(
        _ ad: FullScreenPresentingAd,
        didFailToPresentFullScreenContentWithError error: Error
    ) {
        pendingRewardCompletion?(false)
        pendingRewardCompletion = nil
        Task { await loadRewardedAd() }
    }
}

struct AdMobBannerView: UIViewRepresentable {
    let width: CGFloat

    final class Coordinator {
        var banner: BannerView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true

        let adSize = inlineAdaptiveBanner(width: width, maxHeight: 50)
        let banner = BannerView(adSize: adSize)
        banner.adUnitID = AdMobConfiguration.bannerAdUnitID
        banner.rootViewController = topViewController()
        banner.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            banner.widthAnchor.constraint(equalToConstant: width),
            banner.heightAnchor.constraint(equalToConstant: 50)
        ])
        context.coordinator.banner = banner
        banner.load(Request())
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        guard let banner = context.coordinator.banner else { return }
        if banner.rootViewController == nil {
            banner.rootViewController = topViewController()
        }
    }

    private func topViewController() -> UIViewController? {
        let windowScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = windowScene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

@MainActor
final class NoOpAdvertisingService: AdvertisingServing {
    var canRequestAds: Bool { false }
    var privacyOptionsRequired: Bool { false }

    func prepare(completion: @escaping () -> Void) {
        completion()
    }

    func presentRewarded(
        for powerUp: RewardedPowerUp,
        completion: @escaping (Bool) -> Void
    ) {
        completion(false)
    }

    func presentPrivacyOptions(completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func gameDidEnd() {}
}
