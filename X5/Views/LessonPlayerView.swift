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

    private var displayedTranslation: CGSize {
        guard displayedScale > CGFloat(VideoViewportState.minimumScale) else { return .zero }
        return CGSize(
            width: CGFloat(viewport.translationX) + gestureTranslation.width,
            height: CGFloat(viewport.translationY) + gestureTranslation.height
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.black

                    VideoPlayer(player: player)
                        .scaleEffect(displayedScale)
                        .offset(displayedTranslation)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .clipped()
                .simultaneousGesture(magnificationGesture)
                .simultaneousGesture(translationGesture)
                .simultaneousGesture(resetGesture)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewport.reset()
                    } label: {
                        Label("Reset zoom", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(viewport == VideoViewportState())
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            player.play()
        }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .updating($gestureMagnification) { value, state, _ in
                state = value
            }
            .onEnded { value in
                viewport.applyMagnification(viewport.scale * Double(value))
            }
    }

    private var translationGesture: some Gesture {
        DragGesture()
            .updating($gestureTranslation) { value, state, _ in
                guard viewport.scale > VideoViewportState.minimumScale else { return }
                state = value.translation
            }
            .onEnded { value in
                guard viewport.scale > VideoViewportState.minimumScale else { return }
                viewport.applyTranslation(
                    x: viewport.translationX + Double(value.translation.width),
                    y: viewport.translationY + Double(value.translation.height)
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
