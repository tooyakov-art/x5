import SwiftUI
import AVKit

/// Plays lesson video. Supports direct mp4/HLS via AVPlayer; YouTube falls back to system browser.
struct LessonPlayerView: View {
    let lesson: CourseLesson

    @State private var player: AVPlayer?
    @State private var isFullScreenPresented = false
    @State private var viewport = VideoViewportState()

    init(lesson: CourseLesson) {
        self.lesson = lesson

        if let url = lesson.playableURL, !Self.isYouTubeURL(url) {
            _player = State(initialValue: AVPlayer(url: url))
        } else {
            _player = State(initialValue: nil)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let url = lesson.playableURL {
                if Self.isYouTubeURL(url) {
                    YouTubeFallbackView(url: url, title: lesson.title)
                } else if let player {
                    directVideo(player)
                } else {
                    ContentUnavailable(
                        systemImage: "play.slash",
                        title: "Video is unavailable",
                        subtitle: "This video could not be opened. Please try again later."
                    )
                }
            } else {
                ContentUnavailable(systemImage: "play.slash", title: "Video not uploaded yet", subtitle: "This lesson does not have a video yet. Check back soon.")
            }
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder
    private func directVideo(_ player: AVPlayer) -> some View {
        ZStack(alignment: .topTrailing) {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                isFullScreenPresented = true
            } label: {
                Label("Enter full screen", systemImage: "arrow.up.left.and.arrow.down.right")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .padding()
            .accessibilityHint("Opens zoom and pan controls")
        }
        .background(Color.black)
        .onAppear {
            player.play()
        }
        .onDisappear {
            if !isFullScreenPresented {
                player.pause()
            }
        }
        .fullScreenCover(isPresented: $isFullScreenPresented, onDismiss: {
            viewport.reset()
        }) {
            FullScreenVideoPlayer(player: player, viewport: $viewport)
        }
    }

    private static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
    }
}

private struct FullScreenVideoPlayer: View {
    let player: AVPlayer
    @Binding var viewport: VideoViewportState

    @Environment(\.dismiss) private var dismiss
    @GestureState private var gestureMagnification: CGFloat = 1
    @GestureState private var gestureTranslation: CGSize = .zero

    private var displayedScale: CGFloat {
        let proposed = viewport.scale * Double(gestureMagnification)
        return CGFloat(min(max(proposed, VideoViewportState.minimumScale), VideoViewportState.maximumScale))
    }

    private func displayedTranslation(in viewportSize: CGSize) -> CGSize {
        guard displayedScale > CGFloat(VideoViewportState.minimumScale) else { return .zero }
        let clamped = viewport.clampedTranslation(
            x: Double(CGFloat(viewport.translationX) + gestureTranslation.width),
            y: Double(CGFloat(viewport.translationY) + gestureTranslation.height),
            scale: Double(displayedScale),
            viewportWidth: Double(viewportSize.width),
            viewportHeight: Double(viewportSize.height)
        )
        return CGSize(
            width: CGFloat(clamped.x),
            height: CGFloat(clamped.y)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black

                VideoPlayer(player: player)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(displayedScale)
                    .offset(displayedTranslation(in: proxy.size))

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.58), in: Circle())
                    }
                    .accessibilityLabel("Close")

                    Spacer()

                    Button {
                        viewport.reset()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.58), in: Circle())
                    }
                    .disabled(viewport == VideoViewportState())
                    .opacity(viewport == VideoViewportState() ? 0.45 : 1)
                    .accessibilityLabel("Reset zoom")
                }
                .padding(.leading, max(16, proxy.safeAreaInsets.leading))
                .padding(.trailing, max(16, proxy.safeAreaInsets.trailing))
                .padding(.top, max(12, proxy.safeAreaInsets.top))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .clipped()
            .simultaneousGesture(magnificationGesture(in: proxy.size))
            .simultaneousGesture(translationGesture(in: proxy.size))
            .simultaneousGesture(resetGesture)
            .onChange(of: proxy.size) { newSize in
                viewport.clampTranslation(
                    viewportWidth: Double(newSize.width),
                    viewportHeight: Double(newSize.height)
                )
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(true)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            AppOrientationCoordinator.enterVideoFullscreen()
            player.play()
        }
        .onDisappear {
            AppOrientationCoordinator.leaveVideoFullscreen()
        }
    }

    private func magnificationGesture(in viewportSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .updating($gestureMagnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                viewport.applyMagnification(
                    viewport.scale * Double(value),
                    viewportWidth: Double(viewportSize.width),
                    viewportHeight: Double(viewportSize.height)
                )
            }
    }

    private func translationGesture(in viewportSize: CGSize) -> some Gesture {
        DragGesture()
            .updating($gestureTranslation) { value, state, _ in
                guard viewport.scale > VideoViewportState.minimumScale else { return }
                state = value.translation
            }
            .onEnded { value in
                guard viewport.scale > VideoViewportState.minimumScale else { return }
                viewport.applyTranslation(
                    x: viewport.translationX + Double(value.translation.width),
                    y: viewport.translationY + Double(value.translation.height),
                    viewportWidth: Double(viewportSize.width),
                    viewportHeight: Double(viewportSize.height)
                )
            }
    }

    private var resetGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                viewport.reset()
            }
    }
}

private struct YouTubeFallbackView: View {
    let url: URL
    let title: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button {
                UIApplication.shared.open(url)
            } label: {
                Text("Open on YouTube")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

private struct ContentUnavailable: View {
    let systemImage: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.white.opacity(0.7))
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
