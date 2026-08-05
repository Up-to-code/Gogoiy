import SwiftUI
import UIKit
import UnityAds

enum RewardedPowerUp: String, Sendable {
    case undo
    case hint
    case recolor
    case getBlock
}

enum UnityAdsConfiguration {
    static let gameID = value(for: "UnityAdsGameID")
    static let bannerPlacementID = value(for: "UnityAdsBannerPlacementID")
    static let rewardedPlacementID = value(for: "UnityAdsRewardedPlacementID")

    static var isConfigured: Bool {
        !gameID.isEmpty && !bannerPlacementID.isEmpty && !rewardedPlacementID.isEmpty
    }

    private static func value(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("$(") else { return "" }
        return trimmed
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
final class UnityAdsRuntime {
    static let shared = UnityAdsRuntime()

    private(set) var isInitialized = false
    private var isInitializing = false
    private var callbacks: [(Bool) -> Void] = []

    private init() {}

    func prepare(completion: @escaping (Bool) -> Void) {
        guard UnityAdsConfiguration.isConfigured else {
            completion(false)
            return
        }
        guard !isInitialized else {
            completion(true)
            return
        }

        callbacks.append(completion)
        guard !isInitializing else { return }
        isInitializing = true

        // Keep ads non-personalized and opt out of sale/sharing. Gogoiy does not
        // request App Tracking Transparency permission.
        UnityAds.setUserConsent(false)
        UnityAds.setUserOptOut(true)
        UnityAds.setNonBehavioral(true)

        let builder = UADSInitializationConfigurationBuilder(gameId: UnityAdsConfiguration.gameID)
#if DEBUG
        _ = builder.with(testMode: true).with(logLevel: .debug)
#else
        _ = builder.with(testMode: false).with(logLevel: .error)
#endif

        UnityAds.initialize(builder.build()) { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isInitialized = error == nil
                self.isInitializing = false
                let pending = self.callbacks
                self.callbacks.removeAll()
                pending.forEach { $0(self.isInitialized) }
            }
        }
    }
}

@MainActor
final class UnityAdsAdvertisingService: NSObject, AdvertisingServing {
    private var rewardedAd: UADSRewardedAd?
    private var isLoadingRewarded = false
    private var preparationCallbacks: [() -> Void] = []
    private var pendingRewardCompletion: ((Bool) -> Void)?
    private var rewardWasEarned = false

    var canRequestAds: Bool {
        UnityAdsRuntime.shared.isInitialized && UnityAdsConfiguration.isConfigured
    }

    var privacyOptionsRequired: Bool { false }

    func prepare(completion: @escaping () -> Void) {
        preparationCallbacks.append(completion)
        UnityAdsRuntime.shared.prepare { [weak self] initialized in
            guard let self else { return }
            if initialized {
                self.loadRewardedAd()
            }
            let callbacks = self.preparationCallbacks
            self.preparationCallbacks.removeAll()
            callbacks.forEach { $0() }
        }
    }

    func presentRewarded(
        for powerUp: RewardedPowerUp,
        completion: @escaping (Bool) -> Void
    ) {
#if targetEnvironment(simulator)
        presentSimulatedRewarded(completion: completion)
#else
        guard canRequestAds, let rewardedAd else {
            completion(false)
            loadRewardedAd()
            return
        }
        guard let viewController = activeViewController() else {
            completion(false)
            return
        }

        pendingRewardCompletion = completion
        rewardWasEarned = false
        self.rewardedAd = nil

        let configuration = UADSShowConfigurationBuilder()
            .with(viewController: viewController)
            .build()
        rewardedAd.show(configuration, delegate: self)
#endif
    }

#if targetEnvironment(simulator)
    private func presentSimulatedRewarded(completion: @escaping (Bool) -> Void) {
        guard let viewController = activeViewController() else {
            completion(false)
            return
        }
        let controller = SimulatedRewardedAdController { [weak self] earned in
            self?.loadRewardedAd()
            completion(earned)
        }
        controller.modalPresentationStyle = .fullScreen
        viewController.present(controller, animated: true)
    }
#endif

    func presentPrivacyOptions(completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func gameDidEnd() {
        // No forced interstitial. Monetization is limited to the home banner and
        // rewarded power-ups that the player explicitly requests.
    }

    private func loadRewardedAd() {
        guard canRequestAds, rewardedAd == nil, !isLoadingRewarded else { return }
        isLoadingRewarded = true

        let configuration = UADSLoadConfigurationBuilder(
            placementId: UnityAdsConfiguration.rewardedPlacementID
        ).build()

        UADSRewardedAd.load(configuration) { [weak self] ad, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoadingRewarded = false
                self.rewardedAd = ad
                self.rewardedAd?.onAdExpired = { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.rewardedAd = nil
                        self?.loadRewardedAd()
                    }
                }
            }
        }
    }

    private func finishReward(_ earned: Bool) {
        pendingRewardCompletion?(earned)
        pendingRewardCompletion = nil
    }
}

extension UnityAdsAdvertisingService: @preconcurrency UADSRewardedShowDelegate {
    func showDidStart(_ unityAd: UADSRewardedAd) {}

    func showDidClick(_ unityAd: UADSRewardedAd) {}

    func showDidReceiveReward(_ unityAd: UADSRewardedAd) {
        rewardWasEarned = true
        finishReward(true)
    }

    func showDidComplete(_ unityAd: UADSRewardedAd, with finishState: UADSShowFinishState) {
        if !rewardWasEarned {
            finishReward(false)
        }
        loadRewardedAd()
    }

    func showDidFail(_ unityAd: UADSRewardedAd, error: UnityAdsError) {
        finishReward(false)
        loadRewardedAd()
    }
}

struct UnityAdsBannerView: UIViewRepresentable {
    let width: CGFloat

    @MainActor
    final class Coordinator: NSObject, @preconcurrency UADSBannerAdDelegate {
        weak var container: UIView?
        var bannerAd: UADSBannerAd?
        var isLoading = false

        func loadBanner() {
            guard !isLoading, bannerAd == nil else { return }
            isLoading = true

            let configuration = UADSBannerLoadConfigurationBuilder(
                placementId: UnityAdsConfiguration.bannerPlacementID,
                bannerSize: CGSize(width: 320, height: 50),
                delegate: self
            ).build()

            UADSBannerAd.load(configuration) { [weak self] ad, _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.isLoading = false
                    guard let ad, let container = self.container else { return }

                    self.bannerAd = ad
                    ad.view.translatesAutoresizingMaskIntoConstraints = false
                    container.addSubview(ad.view)
                    NSLayoutConstraint.activate([
                        ad.view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                        ad.view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                        ad.view.widthAnchor.constraint(equalToConstant: 320),
                        ad.view.heightAnchor.constraint(equalToConstant: 50)
                    ])
                    ad.onAdExpired = { [weak self] _ in
                        Task { @MainActor [weak self] in
                            self?.bannerAd?.view.removeFromSuperview()
                            self?.bannerAd = nil
                            self?.loadBanner()
                        }
                    }
                }
            }
        }

        func bannerImpression(_ banner: UADSBannerAd) {}

        func bannerDidClick(_ banner: UADSBannerAd) {}

        func bannerDidFailShow(_ banner: UADSBannerAd, error: UnityAdsError) {
            bannerAd?.view.removeFromSuperview()
            bannerAd = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear
        container.clipsToBounds = true
        context.coordinator.container = container

        guard UnityAdsConfiguration.isConfigured else { return container }
        UnityAdsRuntime.shared.prepare { initialized in
            if initialized {
                context.coordinator.loadBanner()
            }
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.bannerAd?.view.removeFromSuperview()
        coordinator.bannerAd = nil
        coordinator.container = nil
    }
}

@MainActor
private func activeViewController() -> UIViewController? {
    let windowScene = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
    var controller = windowScene?.keyWindow?.rootViewController
    while let presented = controller?.presentedViewController {
        controller = presented
    }
    return controller
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

#if targetEnvironment(simulator)
@MainActor
final class SimulatedRewardedAdController: UIViewController {
    private let completion: (Bool) -> Void
    private var countdown = 5
    private var timer: Timer?
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let countdownLabel = UILabel()

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        let icon = UIImageView(image: UIImage(systemName: "play.rectangle.fill"))
        icon.tintColor = .systemCyan
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = UILabel()
        title.text = "Ad"
        title.font = UIFont.systemFont(ofSize: 30, weight: .bold)
        title.textColor = .white
        title.textAlignment = .center

        let subtitle = UILabel()
        subtitle.text = "Simulated reward ad (simulator only)"
        subtitle.font = .systemFont(ofSize: 14, weight: .medium)
        subtitle.textColor = .white.withAlphaComponent(0.6)
        subtitle.textAlignment = .center

        progressView.trackTintColor = .white.withAlphaComponent(0.2)
        progressView.progressTintColor = .systemCyan
        progressView.translatesAutoresizingMaskIntoConstraints = false

        countdownLabel.text = "Reward in \(countdown)s"
        countdownLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        countdownLabel.textColor = .white
        countdownLabel.textAlignment = .center

        container.addSubview(icon)
        container.addSubview(title)
        container.addSubview(subtitle)
        container.addSubview(progressView)
        container.addSubview(countdownLabel)
        for subview in [icon, title, subtitle, progressView, countdownLabel] {
            subview.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: 280),

            icon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            icon.topAnchor.constraint(equalTo: container.topAnchor),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),

            title.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            title.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),

            subtitle.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),

            progressView.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 28),
            progressView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            countdownLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            countdownLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            countdownLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startCountdown()
    }

    private func startCountdown() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        tick()
    }

    private func tick() {
        countdown = max(0, countdown - 1)
        countdownLabel.text = countdown > 0
            ? "Reward in \(countdown)s"
            : "Reward ready"
        progressView.progress = 1 - Float(countdown) / 5
        if countdown <= 0 {
            timer?.invalidate()
            timer = nil
            finish()
        }
    }

    private func finish() {
        completion(true)
        dismiss(animated: true)
    }
}
#endif
