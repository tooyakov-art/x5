import AVFoundation
import SwiftUI

enum HomeMotionSource: Equatable {
    case bundled(resourceName: String)
    case remote(url: URL)
}

struct HomeMotionAsset: Equatable {
    let source: HomeMotionSource
    let posterAssetName: String
}

enum HomeDemoConfiguration {
    static let imageGenerationVideoURL = URL(
        string: "https://cdn.higgsfield.ai/card/83522493-66ba-44b9-92f6-ae18cd8ba22b.mp4"
    )!
    static let videoGenerationVideoURL = URL(
        string: "https://static.higgsfield.ai/ai-video-v2/01-mini.mp4"
    )!
    static let voiceGenerationVideoURL = URL(
        string: "https://static.higgsfield.ai/flow-medias/create-audio-22-07-2026.mp4"
    )!

    static var isEnabled: Bool {
        #if DEBUG
        return isEnabled(
            isDebugBuild: true,
            environment: ProcessInfo.processInfo.environment
        )
        #else
        return isEnabled(
            isDebugBuild: false,
            environment: ProcessInfo.processInfo.environment
        )
        #endif
    }

    static func isEnabled(
        isDebugBuild: Bool,
        environment: [String: String]
    ) -> Bool {
        guard isDebugBuild else { return false }
        return environment["X5_HOME_DEMO_MODE"] != "0"
    }
}

enum HomeMotionCatalog {
    static func asset(
        for imageAssetName: String,
        demoMode: Bool = HomeDemoConfiguration.isEnabled
    ) -> HomeMotionAsset? {
        if demoMode, imageAssetName == "HomeCoverTargetAds" {
            return HomeMotionAsset(
                source: .remote(url: HomeDemoConfiguration.imageGenerationVideoURL),
                posterAssetName: "HomeCoverTargetAds"
            )
        }

        if demoMode,
           imageAssetName == "HomeTrendLiveVideo"
            || imageAssetName == "HomeUtilityVideo" {
            return HomeMotionAsset(
                source: .remote(url: HomeDemoConfiguration.videoGenerationVideoURL),
                posterAssetName: imageAssetName
            )
        }

        if demoMode, imageAssetName == "HomeMotionStudioPoster" {
            return HomeMotionAsset(
                source: .remote(url: HomeDemoConfiguration.voiceGenerationVideoURL),
                posterAssetName: "HomeMotionStudioPoster"
            )
        }

        switch imageAssetName {
        case "HomeCoverTargetAds",
             "HomeTrendLiveVideo",
             "HomeUtilityVideo",
             "HomeMotionStudioPoster":
            return HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionStudio"),
                posterAssetName: "HomeMotionStudioPoster"
            )
        case "HomeTrendFruitVideo":
            return HomeMotionAsset(
                source: .bundled(resourceName: "HomeMotionFruit"),
                posterAssetName: "HomeMotionFruitPoster"
            )
        default:
            return nil
        }
    }
}

enum HomeMotionPlaybackPolicy {
    static func shouldPlay(
        isActive: Bool,
        isVisible: Bool,
        appIsActive: Bool,
        reduceMotion: Bool
    ) -> Bool {
        isActive && isVisible && appIsActive && !reduceMotion
    }
}

/// Muted card motion backed by one ordinary AVPlayer.
/// The poster always remains underneath, so a missing or failed video is harmless.
struct LoopingVideo: View {
    let source: HomeMotionSource
    let posterAssetName: String
    let isActive: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var controller: HomeLoopingVideoController
    @State private var isVisible = false

    init(source: HomeMotionSource, posterAssetName: String, isActive: Bool) {
        self.source = source
        self.posterAssetName = posterAssetName
        self.isActive = isActive
        _controller = StateObject(
            wrappedValue: HomeLoopingVideoController(source: source)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Image(posterAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                if controller.isReady, let player = controller.player {
                    HomePlayerLayerView(player: player)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .background(
                Color.clear.preference(
                    key: HomeMotionFramePreferenceKey.self,
                    value: proxy.frame(in: .global)
                )
            )
        }
        .background(Color.white.opacity(0.06))
        .onPreferenceChange(HomeMotionFramePreferenceKey.self) { frame in
            let screen = UIScreen.main.bounds.insetBy(dx: 0, dy: -32)
            isVisible = frame.width > 0
                && frame.height > 0
                && frame.intersects(screen)
        }
        .onAppear {
            controller.setShouldPlay(playbackShouldRun)
        }
        .onDisappear {
            isVisible = false
            controller.setShouldPlay(false)
        }
        .onChange(of: playbackShouldRun) { shouldPlay in
            controller.setShouldPlay(shouldPlay)
        }
    }

    private var playbackShouldRun: Bool {
        HomeMotionPlaybackPolicy.shouldPlay(
            isActive: isActive,
            isVisible: isVisible,
            appIsActive: scenePhase == .active,
            reduceMotion: reduceMotion
        )
    }
}

private struct HomeMotionFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private final class HomeLoopingVideoController: ObservableObject {
    @Published private(set) var isReady = false
    private(set) var player: AVPlayer?

    private var shouldPlay = false
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    init(source: HomeMotionSource, bundle: Bundle = .main) {
        guard let url = Self.mediaURL(for: source, bundle: bundle) else {
            return
        }

        let asset = AVURLAsset(
            url: url,
            options: [AVURLAssetPreferPreciseDurationAndTimingKey: false]
        )
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 1

        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReady = item.status == .readyToPlay
                self.applyPlaybackState()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.player?.seek(to: .zero)
            self.applyPlaybackState()
        }
    }

    deinit {
        statusObservation?.invalidate()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }

    func setShouldPlay(_ shouldPlay: Bool) {
        self.shouldPlay = shouldPlay
        applyPlaybackState()
    }

    private func applyPlaybackState() {
        guard shouldPlay, isReady else {
            player?.pause()
            return
        }
        player?.play()
    }

    private static func mediaURL(
        for source: HomeMotionSource,
        bundle: Bundle
    ) -> URL? {
        switch source {
        case .bundled(let resourceName):
            return bundle.url(
                forResource: resourceName,
                withExtension: "mp4",
                subdirectory: "HomeMotion"
            ) ?? bundle.url(forResource: resourceName, withExtension: "mp4")
        case .remote(let url):
            return url
        }
    }
}

private struct HomePlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> HomePlayerContainerView {
        let view = HomePlayerContainerView()
        view.player = player
        return view
    }

    func updateUIView(_ uiView: HomePlayerContainerView, context: Context) {
        uiView.player = player
    }

    static func dismantleUIView(_ uiView: HomePlayerContainerView, coordinator: ()) {
        uiView.player = nil
    }
}

private final class HomePlayerContainerView: UIView {
    override class var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.player = newValue
        }
    }
}
