import SwiftUI
import AVKit

/// Plays lesson video. Supports direct mp4/HLS via AVPlayer; YouTube falls back to system browser.
struct LessonPlayerView: View {
    let lesson: CourseLesson

    @StateObject private var playback: CourseVideoPlaybackController
    @State private var isFullScreenPresented = false
    @State private var viewport = VideoViewportState()

    init(lesson: CourseLesson) {
        self.lesson = lesson

        let directURL = lesson.playableURL.flatMap {
            Self.isYouTubeURL($0) ? nil : $0
        }
        _playback = StateObject(
            wrappedValue: CourseVideoPlaybackController(url: directURL)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let url = lesson.playableURL {
                if Self.isYouTubeURL(url) {
                    YouTubeFallbackView(url: url, title: lesson.title)
                } else {
                    directVideo(playback)
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
    private func directVideo(_ playback: CourseVideoPlaybackController) -> some View {
        ZStack {
            VideoPlayer(player: playback.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    CourseQualityMenu(playback: playback)
                    Spacer()
                    Button {
                        isFullScreenPresented = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 42, height: 42)
                            .background(Color.black.opacity(0.66), in: Circle())
                    }
                    .accessibilityLabel("На весь экран")
                }

                Spacer()

                CoursePlaybackStatus(playback: playback)
            }
            .padding()
        }
        .background(Color.black)
        .onAppear {
            playback.play()
        }
        .onDisappear {
            if !isFullScreenPresented {
                playback.pause()
            }
        }
        .fullScreenCover(isPresented: $isFullScreenPresented, onDismiss: {
            viewport.reset()
        }) {
            FullScreenVideoPlayer(playback: playback, viewport: $viewport)
        }
    }

    private static func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
    }
}

private struct CourseQualityMenu: View {
    @ObservedObject var playback: CourseVideoPlaybackController

    var body: some View {
        Menu {
            ForEach(playback.availableQualities) { quality in
                Button {
                    playback.selectQuality(quality)
                } label: {
                    if playback.selectedQuality == quality {
                        Label(quality.title, systemImage: "checkmark")
                    } else {
                        Text(quality.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text(playback.selectedQualityTitle)
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 13)
            .frame(height: 42)
            .background(Color.black.opacity(0.66), in: Capsule())
            .overlay {
                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
        }
        .accessibilityLabel("Качество видео")
        .accessibilityValue(playback.selectedQualityTitle)
    }
}

private struct CoursePlaybackStatus: View {
    @ObservedObject var playback: CourseVideoPlaybackController

    var body: some View {
        VStack(spacing: 10) {
            if playback.isBuffering && !playback.isOffline && playback.playbackError == nil {
                HStack(spacing: 9) {
                    ProgressView()
                        .tint(Color.accentColor)
                    Text("Загружаем видео")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Color.black.opacity(0.76), in: Capsule())
            }

            if let message = playback.connectionMessage {
                HStack(spacing: 10) {
                    Image(
                        systemName: playback.isOffline
                            ? "wifi.slash"
                            : playback.playbackError == nil
                                ? "exclamationmark.triangle.fill"
                                : "play.slash.fill"
                    )
                    .foregroundColor(
                        playback.isOffline || playback.playbackError != nil
                            ? .red
                            : Color.accentColor
                    )

                    Text(message)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 4)

                    if playback.isOffline || playback.playbackError != nil {
                        Button("Повторить") {
                            playback.retry()
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.accentColor)
                        .disabled(playback.isOffline)
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
            }

            if let qualityMessage = playback.sourceQualityMessage,
               playback.connectionMessage == nil,
               !playback.isBuffering {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color.accentColor)
                    Text(qualityMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 11)
                .background(
                    Color.black.opacity(0.88),
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                }
            }
        }
    }
}

private struct FullScreenVideoPlayer: View {
    @ObservedObject var playback: CourseVideoPlaybackController
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

                VideoPlayer(player: playback.player)
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

                    CourseQualityMenu(playback: playback)

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

                VStack {
                    Spacer()
                    CoursePlaybackStatus(playback: playback)
                        .padding(.horizontal, 16)
                        .padding(.bottom, max(52, proxy.safeAreaInsets.bottom + 40))
                }
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
            playback.play()
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
