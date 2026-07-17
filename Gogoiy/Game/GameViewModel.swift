import Foundation
import SwiftUI

@MainActor
final class GameViewModel: ObservableObject {
    enum Screen: Equatable {
        case splash
        case home
        case game
    }

    enum Overlay: Equatable {
        case none
        case settings
        case howToPlay
        case blockBuilder
        case moreSettings
        case privacyPolicy
        case termsOfUse
        case gameOver(newBest: Bool)
    }

    @Published private(set) var screen: Screen = .splash
    @Published private(set) var state: GameState
    @Published private(set) var overlay: Overlay = .none
    @Published private(set) var soundEnabled: Bool
    @Published private(set) var musicEnabled: Bool
    @Published private(set) var hapticsEnabled: Bool
    @Published private(set) var canRequestAds = false
    @Published private(set) var privacyOptionsRequired = false
    @Published private(set) var hintText = "Match one-color lines"
    @Published var showsRestartConfirmation = false

    let scene: GameScene

    private var engine: GameEngine
    private let preferences: Preferences
    private let feedback: FeedbackController
    private let advertising: AdvertisingServing
    private var scoreAtRunStart: Int

    init(
        seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
        preferences: Preferences = Preferences(),
        advertising: AdvertisingServing = AdMobAdvertisingService()
    ) {
        self.preferences = preferences
        self.advertising = advertising
        engine = GameEngine(seed: seed, bestScore: preferences.bestScore)
        state = engine.state
        soundEnabled = preferences.soundEnabled
        musicEnabled = preferences.musicEnabled
        hapticsEnabled = preferences.hapticsEnabled
        scoreAtRunStart = preferences.bestScore
        feedback = FeedbackController()
        scene = GameScene(size: CGSize(width: 390, height: 844))
        scene.gameDelegate = self
        feedback.soundEnabled = soundEnabled
        feedback.hapticsEnabled = hapticsEnabled
        feedback.setMusicEnabled(musicEnabled)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1_650))
            guard self?.screen == .splash else { return }
            self?.screen = .home
            self?.scene.setGamePaused(true)
            self?.feedback.pauseMusic()
            self?.advertising.prepare { [weak self] in
                guard let self else { return }
                self.canRequestAds = self.advertising.canRequestAds
                self.privacyOptionsRequired = self.advertising.privacyOptionsRequired
            }
        }
    }

    func openSettings() {
        guard overlay == .none else { return }
        scene.setGamePaused(true)
        overlay = .settings
    }

    func resume() {
        guard overlay == .settings else { return }
        overlay = .none
        if screen == .game {
            scene.setGamePaused(false)
        }
        if musicEnabled, screen == .game {
            feedback.setMusicEnabled(true)
        }
    }

    func playOrContinue() {
        if state.isGameOver {
            restart()
            return
        }

        overlay = .none
        screen = .game
        scene.setGamePaused(false)
        scene.renderCurrentState(animatedTray: false)
        if musicEnabled {
            feedback.setMusicEnabled(true)
        }
    }

    func showHowToPlay() {
        guard overlay == .none else { return }
        overlay = .howToPlay
    }

    func watchRewardedHint() {
        guard screen == .game, overlay == .none, !state.isGameOver else { return }
        scene.setGamePaused(true)
        hintText = "Preparing your hint…"
        advertising.presentRewarded(for: .hint) { [weak self] rewardEarned in
            guard let self else { return }
            if rewardEarned, let hint = self.engine.bestPlacementHint() {
                self.hintText = hint.clearedCells.isEmpty
                    ? "Try the glowing piece on the highlighted squares"
                    : "This move can complete a same-color line"
                self.scene.showHint(hint)
            } else {
                self.hintText = "The rewarded ad is still loading—try again shortly"
            }
            if self.screen == .game, self.overlay == .none {
                self.scene.setGamePaused(false)
            }
        }
    }

    func openBlockBuilder() {
        guard screen == .game, overlay == .none, !state.isGameOver else { return }
        scene.setGamePaused(true)
        overlay = .blockBuilder
    }

    func canUseRewardedShape(_ shape: PieceShape) -> Bool {
        engine.canUseRewardedShape(shape)
    }

    func watchRewardedBlock(shape: PieceShape, color: BlockColor) {
        guard overlay == .blockBuilder else { return }
        hintText = "Preparing your custom block…"
        advertising.presentRewarded(for: .getBlock) { [weak self] rewardEarned in
            guard let self else { return }
            if rewardEarned,
               let piece = self.engine.replaceFirstAvailablePiece(with: shape, color: color) {
                self.state = self.engine.state
                self.hintText = "Your \(piece.shape.name) block is ready"
                self.overlay = .none
                self.scene.renderCurrentState(animatedTray: true)
                self.scene.setGamePaused(false)
            } else {
                self.hintText = "The rewarded ad is still loading—try again shortly"
                self.overlay = .none
                self.scene.setGamePaused(false)
            }
        }
    }

    func showMoreSettings() {
        overlay = .moreSettings
    }

    func showPrivacyPolicy() {
        overlay = .privacyPolicy
    }

    func showTermsOfUse() {
        overlay = .termsOfUse
    }

    func returnToSettings() {
        overlay = .settings
    }

    func showPrivacyOptions() {
        advertising.presentPrivacyOptions { [weak self] succeeded in
            guard let self else { return }
            self.canRequestAds = self.advertising.canRequestAds
            self.privacyOptionsRequired = self.advertising.privacyOptionsRequired
            if !succeeded {
                self.hintText = "Privacy choices are not available right now"
            }
        }
    }

    func closeOverlay() {
        overlay = .none
    }

    func cancelBlockBuilder() {
        guard overlay == .blockBuilder else { return }
        overlay = .none
        scene.setGamePaused(false)
    }

    func goHome() {
        scene.setGamePaused(true)
        overlay = .none
        screen = .home
        feedback.pauseMusic()
    }

    var hasActiveGame: Bool {
        state.score > 0 && !state.isGameOver
    }

    func requestRestart() {
        showsRestartConfirmation = true
    }

    func restart() {
        showsRestartConfirmation = false
        engine.restart()
        state = engine.state
        scoreAtRunStart = state.bestScore
        hintText = "Match one-color lines"
        overlay = .none
        screen = .game
        scene.prepareForRestart()
        if musicEnabled {
            feedback.setMusicEnabled(true)
        }
    }

    func setSoundEnabled(_ enabled: Bool) {
        soundEnabled = enabled
        preferences.soundEnabled = enabled
        feedback.soundEnabled = enabled
        if enabled {
            feedback.play(.pickup)
        }
    }

    func setMusicEnabled(_ enabled: Bool) {
        musicEnabled = enabled
        preferences.musicEnabled = enabled
        feedback.setMusicEnabled(enabled)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        hapticsEnabled = enabled
        preferences.hapticsEnabled = enabled
        feedback.hapticsEnabled = enabled
        if enabled {
            feedback.play(.pickup)
        }
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            if musicEnabled && overlay == .none && screen == .game {
                feedback.setMusicEnabled(true)
            }
        case .inactive, .background:
            feedback.pauseMusic()
            if overlay == .none, !state.isGameOver, screen == .game {
                scene.setGamePaused(true)
                overlay = .settings
            }
        @unknown default:
            break
        }
    }
}

extension GameViewModel: GameSceneDelegate {
    var currentGameState: GameState {
        state
    }

    func gameSceneCanPlace(pieceID: UUID, at origin: GridCell) -> Bool {
        engine.canPlace(pieceID: pieceID, at: origin)
    }

    func gameScenePreviewClearedCells(pieceID: UUID, at origin: GridCell) -> Set<GridCell> {
        engine.previewClearedCells(pieceID: pieceID, at: origin)
    }

    func gameScenePlace(pieceID: UUID, at origin: GridCell) -> MoveResult? {
        do {
            let result = try engine.place(pieceID: pieceID, at: origin)
            state = engine.state
            preferences.bestScore = state.bestScore
            hintText = result.clearedLineCount > 0
                ? "Color match! +\(result.scoreDelta) points"
                : "Keep every block in a line the same color"
            return result
        } catch {
            return nil
        }
    }

    func gameSceneDidFinishResolution(_ result: MoveResult) {
        guard result.isGameOver else { return }
        feedback.pauseMusic()
        feedback.play(.gameOver)
        advertising.gameDidEnd()
        if screen == .game {
            overlay = .gameOver(newBest: state.score > scoreAtRunStart)
        }
    }

    func gameScenePlayFeedback(_ cue: FeedbackController.Cue) {
        if case .invalid = cue {
            hintText = "Place the piece on open squares"
        }
        feedback.play(cue)
    }
}
