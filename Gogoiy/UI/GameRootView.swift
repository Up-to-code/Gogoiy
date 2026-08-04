import SpriteKit
import SwiftUI

private let privacyPolicyText = """
Gogoiy stores your best score and sound, music, and haptic preferences on your device. \
The game does not require an account and does not send gameplay data to a Gogoiy server.

Gogoiy uses Unity Ads to show a small banner and optional rewarded \
ads. The integration uses restrictive, non-tracking privacy settings. Unity and its \
advertising partners may still process device, network, and ad-delivery data as described \
in the privacy information on the final App Store listing.

Deleting Gogoiy removes its locally stored game preferences. This prototype does not \
sell personal information or include analytics, accounts, or a custom tracking backend.
"""

private let termsOfUseText = """
Gogoiy is provided as an entertainment game. You may play it for personal, non-commercial \
use. Do not attempt to manipulate advertising rewards, disrupt the service, or redistribute \
the app or its artwork without permission.

Rewarded ads are optional. A reward is granted only after the advertising provider confirms \
completion. Ad availability is not guaranteed, and ordinary gameplay remains available \
without watching a rewarded ad.

The game is provided as-is while this device prototype is being developed. Scores, features, \
and availability may change in later versions. These terms are governed by the laws applicable \
to the publisher shown on the final App Store listing.
"""

struct GameRootView: View {
    @StateObject private var model = GameViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            background

            mainContent

            if model.overlay == .settings {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ModalScrollContainer {
                    SettingsPanel(model: model)
                }
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }

            if model.overlay == .howToPlay {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ModalScrollContainer {
                    HowToPlayPanel(close: { model.closeOverlay() })
                }
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }

            if model.overlay == .blockBuilder {
                Color.black.opacity(0.54)
                    .ignoresSafeArea()
                ModalScrollContainer {
                    BlockBuilderPanel(model: model)
                }
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }

            if model.overlay == .moreSettings {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ModalScrollContainer {
                    MoreSettingsPanel(model: model)
                }
                .transition(.scale(scale: 0.88).combined(with: .opacity))
            }

            if model.overlay == .privacyPolicy {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ModalScrollContainer {
                    LegalPanel(
                        title: "Privacy Policy",
                        systemImage: "hand.raised.fill",
                        text: privacyPolicyText,
                        url: URL(string: "https://gogoiy.qentrah.com/privacy"),
                        close: { model.showMoreSettings() }
                    )
                }
            }

            if model.overlay == .termsOfUse {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                ModalScrollContainer {
                    LegalPanel(
                        title: "Terms of Use",
                        systemImage: "doc.text.fill",
                        text: termsOfUseText,
                        url: URL(string: "https://gogoiy.qentrah.com/terms"),
                        close: { model.showMoreSettings() }
                    )
                }
            }

            if case let .gameOver(newBest) = model.overlay {
                Color.black.opacity(0.54)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ModalScrollContainer {
                    GameOverPanel(
                        score: model.state.score,
                        bestScore: model.state.bestScore,
                        newBest: newBest,
                        playAgain: { model.restart() },
                        goHome: { model.goHome() }
                    )
                }
                .transition(.scale(scale: 0.78).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.overlay)
        .alert("Start a new game?", isPresented: $model.showsRestartConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restart", role: .destructive) {
                model.restart()
            }
        } message: {
            Text("Your current board and score will be cleared.")
        }
        .onChange(of: scenePhase) { _, newPhase in
            model.handleScenePhase(newPhase)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch model.screen {
        case .splash:
            SplashScreen()
                .transition(.opacity)
        case .home:
            HomeScreen(model: model)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .game:
            ZStack {
                SpriteView(scene: model.scene, options: [.allowsTransparency])
                    .ignoresSafeArea()
                hud
                if model.canRequestAds {
                    VStack {
                        Spacer()
                        AdBannerSlot()
                    }
                    .padding(.bottom, 2)
                }
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.13, blue: 0.46),
                    Color(red: 0.08, green: 0.07, blue: 0.25),
                    Color(red: 0.04, green: 0.04, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.13), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 430
            )
        }
        .ignoresSafeArea()
    }

    private var hud: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height * 1.12

            VStack {
                HStack(alignment: .top, spacing: isLandscape ? 10 : 14) {
                    scoreBrand
                        .frame(maxWidth: .infinity, alignment: .leading)

                    scoreDisplay(compact: isLandscape)
                        .frame(maxWidth: .infinity)

                    if isLandscape {
                        HStack(spacing: 8) {
                            powerButtons(compact: true)
                            settingsButton
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
                        settingsButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, isLandscape ? 5 : 8)

                if !isLandscape {
                    powerButtons(compact: false)
                        .frame(maxWidth: .infinity)
                }

                Spacer()
            }
        }
    }

    private var scoreBrand: some View {
        Label("\(model.state.bestScore)", systemImage: "crown.fill")
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 1, green: 0.73, blue: 0.18))
    }

    private func scoreDisplay(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Text("GOGOIY")
                .font(.system(size: compact ? 9 : 11, weight: .black, design: .rounded))
                .tracking(compact ? 1.3 : 1.7)
                .foregroundStyle(.cyan.opacity(0.9))
            Text("\(model.state.score)")
                .font(.system(size: compact ? 32 : 42, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .shadow(color: .black.opacity(0.25), radius: 4, y: 3)
            Text("LEVEL \(model.state.level)")
                .font(.system(size: compact ? 8 : 9, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.58))
            if model.state.combo > 1 {
                Text("SWEET ×\(model.state.combo)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.cyan)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var settingsButton: some View {
        Button {
            model.openSettings()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .accessibilityLabel("Pause and settings")
    }

    private func powerButtons(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            Button {
                model.watchRewardedHint()
            } label: {
                Label("Hint", systemImage: "lightbulb.fill")
                    .font(.system(size: compact ? 10 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 9 : 12)
                    .padding(.vertical, compact ? 7 : 8)
                    .background(Color.cyan.opacity(0.28), in: Capsule())
                    .overlay(Capsule().stroke(Color.cyan.opacity(0.45), lineWidth: 1))
            }
            .accessibilityHint("Watch an optional rewarded ad to highlight a valid move")

            Button {
                model.openBlockBuilder()
            } label: {
                Label("Get Block", systemImage: "square.grid.2x2.fill")
                    .font(.system(size: compact ? 10 : 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, compact ? 9 : 12)
                    .padding(.vertical, compact ? 7 : 8)
                    .background(Color.purple.opacity(0.42), in: Capsule())
                    .overlay(Capsule().stroke(Color.purple.opacity(0.65), lineWidth: 1))
            }
            .accessibilityHint("Choose a block shape and color after an optional rewarded ad")
        }
    }
}

private struct SplashScreen: View {
    @State private var isVisible = false
    @State private var progress: CGFloat = 0.08

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            GogoiyMark(blockSize: 22)
                .frame(maxWidth: .infinity, alignment: .center)
                .scaleEffect(isVisible ? 1 : 0.55)
                .rotationEffect(.degrees(isVisible ? 0 : -12))
                .opacity(isVisible ? 1 : 0)

            VStack(spacing: 7) {
                Text("GOGOIY")
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .tracking(5)
                Text("COLOR MATCH PUZZLE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.cyan.opacity(0.78))
            }
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 12)
            .padding(.top, 8)

            Spacer()

            VStack(spacing: 9) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.09))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.cyan, .green, .yellow],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geometry.size.width * progress)
                    }
                }
                .frame(height: 8)

                Text("Mixing the colors…")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: 230)
            .padding(.bottom, 46)
        }
        .padding(24)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                isVisible = true
            }
            withAnimation(.easeInOut(duration: 1.4)) {
                progress = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Gogoiy is loading")
    }
}

private struct HomeScreen: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            VStack(spacing: isLandscape ? 8 : 17) {
                if isLandscape {
                    HStack(spacing: 34) {
                        brand(blockSize: 13, wordmarkSize: 31)
                            .frame(maxWidth: .infinity)
                        controls
                            .frame(maxWidth: 330)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 4)
                    brand(blockSize: 16, wordmarkSize: 38)
                    controls
                    Spacer(minLength: 4)
                }

                if model.canRequestAds {
                    AdBannerSlot()
                }
            }
            .padding(.horizontal, isLandscape ? 34 : 24)
            .padding(.top, isLandscape ? 4 : 12)
            .padding(.bottom, 4)
        }
    }

    private func brand(blockSize: CGFloat, wordmarkSize: CGFloat) -> some View {
        VStack(spacing: 8) {
            GogoiyMark(blockSize: blockSize)

            VStack(spacing: 4) {
                Text("GOGOIY")
                    .font(.system(size: wordmarkSize, weight: .black, design: .rounded))
                    .tracking(4)
                    .minimumScaleFactor(0.75)
                Text("MATCH THE COLOR. CLEAR THE LINE.")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.35)
                    .foregroundStyle(.cyan.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                model.playOrContinue()
            } label: {
                Label(
                    model.hasActiveGame ? "Continue" : "Play",
                    systemImage: "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                CandyButtonStyle(color: Color(red: 0.22, green: 0.86, blue: 0.45))
            )

            Button {
                model.showHowToPlay()
            } label: {
                Label("How to Play", systemImage: "lightbulb.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                CandyButtonStyle(color: Color(red: 0.2, green: 0.66, blue: 0.96))
            )

            Button {
                model.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                CandyButtonStyle(color: Color(red: 0.48, green: 0.31, blue: 0.95))
            )

            Label("Best  \(model.state.bestScore)", systemImage: "crown.fill")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow.opacity(0.85))
        }
        .frame(maxWidth: 330)
    }
}

private struct AdBannerSlot: View {
    @ViewBuilder
    var body: some View {
#if DEBUG
        HStack(spacing: 10) {
            Image(systemName: "rectangle.inset.filled")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text("ADVERTISEMENT")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(1.3)
                Text("Ad preview · Live in release")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 420, minHeight: 50, maxHeight: 50)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Advertisement preview")
#else
        GeometryReader { geometry in
            let width = min(420, max(320, geometry.size.width))

            UnityAdsBannerView(width: width)
                .frame(width: width, height: 50)
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Advertisement")
        }
        .frame(height: 50)
#endif
    }
}

private struct ModalScrollContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct MarkBlock: Identifiable {
    let id: Int
    let row: Int
    let column: Int
    let color: Color
}

private struct GogoiyMark: View {
    let blockSize: CGFloat

    private let blocks = [
        MarkBlock(id: 0, row: 0, column: 1, color: .cyan),
        MarkBlock(id: 1, row: 0, column: 2, color: .pink),
        MarkBlock(id: 2, row: 0, column: 3, color: .yellow),
        MarkBlock(id: 3, row: 1, column: 0, color: .green),
        MarkBlock(id: 4, row: 2, column: 0, color: .purple),
        MarkBlock(id: 5, row: 3, column: 0, color: .pink),
        MarkBlock(id: 6, row: 4, column: 1, color: .cyan),
        MarkBlock(id: 7, row: 4, column: 2, color: .green),
        MarkBlock(id: 8, row: 4, column: 3, color: .purple),
        MarkBlock(id: 9, row: 3, column: 3, color: .yellow),
        MarkBlock(id: 10, row: 2, column: 3, color: .purple),
        MarkBlock(id: 11, row: 2, column: 2, color: .cyan)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(blocks) { block in
                RoundedRectangle(cornerRadius: blockSize * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [block.color.opacity(1), block.color.opacity(0.68)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: blockSize * 0.24)
                            .stroke(Color.white.opacity(0.32), lineWidth: 1)
                    )
                    .shadow(color: block.color.opacity(0.34), radius: 6, y: 4)
                    .frame(width: blockSize, height: blockSize)
                    .offset(
                        x: CGFloat(block.column) * blockSize * 0.9,
                        y: CGFloat(block.row) * blockSize * 0.9
                    )
            }
        }
        .frame(
            width: blockSize * 3.7,
            height: blockSize * 4.6,
            alignment: .topLeading
        )
        .accessibilityHidden(true)
    }
}

private struct SettingsPanel: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 5) {
                Text(model.screen == .home ? "SETTINGS" : "PAUSED")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(.cyan)
                Text(model.screen == .home ? "Make it yours" : "Take a breather")
                    .font(.system(size: 27, weight: .black, design: .rounded))
            }

            VStack(spacing: 4) {
                SettingToggle(
                    title: "Sound",
                    systemImage: "speaker.wave.2.fill",
                    isOn: Binding(
                        get: { model.soundEnabled },
                        set: { model.setSoundEnabled($0) }
                    )
                )
                SettingToggle(
                    title: "Music",
                    systemImage: "music.note",
                    isOn: Binding(
                        get: { model.musicEnabled },
                        set: { model.setMusicEnabled($0) }
                    )
                )
                SettingToggle(
                    title: "Haptics",
                    systemImage: "waveform",
                    isOn: Binding(
                        get: { model.hapticsEnabled },
                        set: { model.setHapticsEnabled($0) }
                    )
                )
            }

            Button {
                model.showMoreSettings()
            } label: {
                Label("More Settings", systemImage: "ellipsis.circle.fill")
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))

            Button {
                if model.screen == .home {
                    model.closeOverlay()
                } else {
                    model.resume()
                }
            } label: {
                Label(
                    model.screen == .home ? "Back Home" : "Keep Playing",
                    systemImage: model.screen == .home ? "chevron.backward" : "play.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CandyButtonStyle(color: Color(red: 0.23, green: 0.86, blue: 0.45)))

            if model.screen == .game {
                HStack(spacing: 24) {
                    Button {
                        model.goHome()
                    } label: {
                        Label("Home", systemImage: "house.fill")
                    }

                    Button {
                        model.requestRestart()
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }
        }
        .padding(26)
        .frame(maxWidth: 370)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.27))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        )
        .padding(22)
    }
}

private struct MoreSettingsPanel: View {
    @ObservedObject var model: GameViewModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.cyan)

            Text("MORE SETTINGS")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .tracking(2.2)

            VStack(spacing: 10) {
                MoreSettingsButton(
                    title: "Ad Privacy Choices",
                    systemImage: "hand.raised.fill",
                    action: { model.showPrivacyOptions() }
                )
                MoreSettingsButton(
                    title: "Privacy Policy",
                    systemImage: "lock.shield.fill",
                    action: { model.showPrivacyPolicy() }
                )
                MoreSettingsButton(
                    title: "Terms of Use",
                    systemImage: "doc.text.fill",
                    action: { model.showTermsOfUse() }
                )
            }

            Button {
                model.returnToSettings()
            } label: {
                Label("Back", systemImage: "chevron.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CandyButtonStyle(color: Color(red: 0.25, green: 0.67, blue: 0.94)))
        }
        .padding(26)
        .frame(maxWidth: 370)
        .panelBackground()
        .padding(22)
    }
}

private struct MoreSettingsButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
        }
        .foregroundStyle(.white.opacity(0.86))
    }
}

private struct LegalPanel: View {
    let title: String
    let systemImage: String
    let text: String
    let url: URL?
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 21, weight: .black, design: .rounded))
                .foregroundStyle(.cyan)

            ScrollView {
                Text(text)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 360)

            if let url {
                Link("Open full \(title)", destination: url)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.cyan)
            }

            Button("Done", action: close)
                .buttonStyle(CandyButtonStyle(color: Color(red: 0.25, green: 0.67, blue: 0.94)))
                .frame(maxWidth: .infinity)
        }
        .padding(26)
        .frame(maxWidth: 390)
        .panelBackground()
        .padding(20)
    }
}

private struct BlockBuilderPanel: View {
    @ObservedObject var model: GameViewModel
    @State private var selectedShape = PieceCatalog.rewardedShapes[0]
    @State private var selectedColor = BlockColor.cyan

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("GET YOUR BLOCK")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.9)
                    .foregroundStyle(.cyan)
                Text("Choose your block")
                    .font(.system(size: 22, weight: .black, design: .rounded))
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 7) {
                ForEach(PieceCatalog.rewardedShapes, id: \.name) { shape in
                    Button {
                        selectedShape = shape
                    } label: {
                        BlockShapePreview(shape: shape, color: selectedColor)
                            .frame(height: 36)
                            .padding(4)
                            .background(
                                selectedShape == shape
                                    ? Color.cyan.opacity(0.28)
                                    : Color.white.opacity(0.055),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(
                                        selectedShape == shape ? Color.cyan : .clear,
                                        lineWidth: 1.5
                                    )
                            )
                    }
                    .disabled(!model.canUseRewardedShape(shape))
                    .opacity(model.canUseRewardedShape(shape) ? 1 : 0.3)
                }
            }

            HStack(spacing: 11) {
                ForEach(BlockColor.allCases, id: \.rawValue) { color in
                    Button {
                        selectedColor = color
                    } label: {
                        Circle()
                            .fill(color.swiftUIColor)
                            .frame(width: 29, height: 29)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: selectedColor == color ? 3 : 0)
                            )
                            .shadow(color: color.swiftUIColor.opacity(0.35), radius: 5, y: 3)
                    }
                    .accessibilityLabel(color.displayName)
                }
            }

            Text("Replaces your first remaining tray piece.")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)

            Button {
                model.watchRewardedBlock(shape: selectedShape, color: selectedColor)
            } label: {
                Label("Watch Ad · Get Block", systemImage: "play.rectangle.fill")
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            .buttonStyle(CandyButtonStyle(color: Color(red: 0.48, green: 0.31, blue: 0.95)))

            Button("Cancel") {
                model.cancelBlockBuilder()
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white.opacity(0.65))
        }
        .padding(20)
        .frame(maxWidth: 350)
        .panelBackground()
        .padding(20)
    }
}

private struct BlockShapePreview: View {
    let shape: PieceShape
    let color: BlockColor

    var body: some View {
        GeometryReader { geometry in
            let cellSize = min(
                geometry.size.width / CGFloat(max(shape.columns, 1)),
                geometry.size.height / CGFloat(max(shape.rows, 1))
            )
            let contentWidth = CGFloat(shape.columns) * cellSize
            let contentHeight = CGFloat(shape.rows) * cellSize

            ZStack(alignment: .topLeading) {
                ForEach(Array(shape.cells.enumerated()), id: \.offset) { _, cell in
                    RoundedRectangle(cornerRadius: cellSize * 0.2)
                        .fill(color.swiftUIColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: cellSize * 0.2)
                                .stroke(.white.opacity(0.35), lineWidth: 1)
                        )
                        .frame(width: cellSize * 0.86, height: cellSize * 0.86)
                        .offset(
                            x: CGFloat(cell.column) * cellSize,
                            y: CGFloat(cell.row) * cellSize
                        )
                }
            }
            .frame(width: contentWidth, height: contentHeight)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}

private struct HowToPlayPanel: View {
    let close: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 34, weight: .black))
                .foregroundStyle(.yellow)

            VStack(spacing: 5) {
                Text("HOW TO PLAY")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(2.2)
                    .foregroundStyle(.cyan)
                Text("Match one color")
                    .font(.system(size: 27, weight: .black, design: .rounded))
            }

            VStack(alignment: .leading, spacing: 14) {
                InstructionRow(
                    number: "1",
                    text: "Drag one of the three pieces onto open squares."
                )
                InstructionRow(
                    number: "2",
                    text: "Fill all eight squares in a row or column with the same color."
                )
                InstructionRow(
                    number: "3",
                    text: "Green light means the line will clear. Mixed colors stay on the board."
                )
            }

            Button {
                close()
            } label: {
                Label("Got It", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                CandyButtonStyle(color: Color(red: 0.22, green: 0.86, blue: 0.45))
            )
        }
        .padding(26)
        .frame(maxWidth: 390)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.27))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        )
        .padding(22)
    }
}

private struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.cyan.opacity(0.55), in: Circle())
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 16, weight: .bold, design: .rounded))
        }
        .tint(Color(red: 0.25, green: 0.88, blue: 0.49))
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct GameOverPanel: View {
    let score: Int
    let bestScore: Int
    let newBest: Bool
    let playAgain: () -> Void
    let goHome: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 74, height: 74)
                    .shadow(color: .orange.opacity(0.45), radius: 16, y: 8)
                Image(systemName: newBest ? "crown.fill" : "checkmark.circle.fill")
                    .font(.system(size: 32, weight: .black))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 5) {
                if newBest {
                    Text("NEW BEST!")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(.yellow)
                }
                Text(newBest ? "Sugar Rush!" : "Sweet Run!")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                Text("\(score)")
                    .font(.system(size: 58, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .purple, .pink],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .contentTransition(.numericText())
                Text("Best  \(bestScore)")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Button {
                playAgain()
            } label: {
                Label("Play Again", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CandyButtonStyle(color: Color(red: 0.43, green: 0.3, blue: 0.96)))

            Button {
                goHome()
            } label: {
                Label("Home Screen", systemImage: "house.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .padding(28)
        .frame(maxWidth: 370)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.27))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.5), radius: 34, y: 18)
        )
        .padding(22)
    }
}

private struct CandyButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .padding(.vertical, 15)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.72 : 1))
                    .shadow(color: color.opacity(0.35), radius: 12, y: 7)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private extension View {
    func panelBackground() -> some View {
        background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 0.09, green: 0.08, blue: 0.27))
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
        )
    }
}

private extension BlockColor {
    var swiftUIColor: Color {
        switch self {
        case .coral: Color(red: 0.98, green: 0.27, blue: 0.35)
        case .amber: Color(red: 1, green: 0.67, blue: 0.10)
        case .lime: Color(red: 0.20, green: 0.82, blue: 0.35)
        case .cyan: Color(red: 0.15, green: 0.72, blue: 0.94)
        case .violet: Color(red: 0.72, green: 0.20, blue: 0.88)
        case .blue: Color(red: 0.22, green: 0.45, blue: 0.96)
        }
    }

    var displayName: String {
        switch self {
        case .coral: "Coral"
        case .amber: "Amber"
        case .lime: "Green"
        case .cyan: "Cyan"
        case .violet: "Violet"
        case .blue: "Blue"
        }
    }
}
