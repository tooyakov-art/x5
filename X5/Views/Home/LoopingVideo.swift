import SwiftUI
import AVFoundation

/// Auto-playing, looping, muted video used as a card cover.
/// Falls back to gradient placeholder while loading.
struct LoopingVideo: View {
    let url: URL
    var fallback: Color = Color.white.opacity(0.05)

    var body: some View {
        ZStack {
            fallback
            LoopingVideoRepresentable(url: url)
        }
    }
}

private struct LoopingVideoRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.configure(url: url)
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        // No-op
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: ()) {
        uiView.tearDown()
    }
}

final class PlayerContainerView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(url: URL) {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(playerItem: item)
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        let looper = AVPlayerLooper(player: queue, templateItem: item)

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer.addSublayer(layer)

        self.player = queue
        self.looper = looper
        self.playerLayer = layer
        queue.play()
    }

    func tearDown() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        player = nil
        looper = nil
        playerLayer = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }
}
