import SwiftUI
import AVKit

/// Plays lesson video. Supports direct mp4/HLS via AVPlayer; YouTube falls back to system browser.
struct LessonPlayerView: View {
    let lesson: CourseLesson
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?

    var body: some View {
        VStack(spacing: 0) {
            if let url = lesson.playableURL {
                if (lesson.videoUrl?.contains("youtube") ?? false) || (lesson.youtubeUrl != nil && !(lesson.youtubeUrl ?? "").isEmpty) {
                    YouTubeFallbackView(url: url, title: lesson.title)
                } else {
                    VideoPlayer(player: player ?? AVPlayer(url: url))
                        .onAppear {
                            if player == nil {
                                let p = AVPlayer(url: url)
                                player = p
                                p.play()
                            }
                        }
                        .onDisappear { player?.pause() }
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
