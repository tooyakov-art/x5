import SwiftUI

/// Home is intentionally reduced to two creation surfaces: photo and video.
struct HomeView: View {
    @EnvironmentObject private var loc: LocalizationService

    @State private var openTool: HomeTool?
    @State private var openImageCategory: ImageGenerationCategory?
    @State private var showingGeneratedGallery: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    homeTitle
                    mediaStack
                }
                .padding(.horizontal, 16)
                .padding(.top, -18)
                .padding(.bottom, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background { X5Background() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingGeneratedGallery = true } label: {
                        Image(systemName: "photo.stack")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .accessibilityLabel(loc.t("gen_gallery"))
                }
            }
            .sheet(item: $openTool) { tool in
                ToolDetailView(tool: tool)
            }
            .navigationDestination(isPresented: imageCategoryNavigationBinding) {
                if let category = openImageCategory {
                    ImageGeneratorView(category: category, provider: .gptImage2)
                        .preferredColorScheme(.dark)
                }
            }
            .sheet(isPresented: $showingGeneratedGallery) {
                GeneratedGalleryView()
            }
        }
    }

    private var homeTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("X5")
                .font(.system(size: 18, weight: .black))
                .foregroundColor(.accentColor)
            Text("Маркетинг")
                .font(.system(size: 36, weight: .black))
                .foregroundColor(.white)
                .kerning(-0.6)
        }
        .padding(.top, -10)
        .padding(.leading, 2)
    }

    private var mediaStack: some View {
        VStack(spacing: 14) {
            ForEach(homeMediaItems) { item in
                Button {
                    switch item.action {
                    case .photo:
                        DiagnosticLogger.log(event: "home_media_photo_tap")
                        openImageCategory = ImageGenerationCatalog.custom
                    case .video:
                        DiagnosticLogger.log(event: "home_media_video_tap")
                        openTool = HomeContent.tools.first(where: { $0.id == "video_gen" })
                    }
                } label: {
                    HomeMediaCard(item: item)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
    }

    private var homeMediaItems: [HomeMediaItem] {
        [
            HomeMediaItem(
                id: "photo",
                title: localized("home_media_photo_title", fallback: "Фото"),
                subtitle: localized("home_media_photo_subtitle", fallback: "Генерация и редактирование изображений"),
                kicker: "IMAGE",
                systemImage: "photo",
                videoURL: URL(string: "https://v1-kling.kechuangai.com/kcdn/cdn-kcdn112452/kling-homepage-aio-prod_aio/assets/videos/model-video-1.6900686236fd8a15.mp4"),
                gradientStart: X5Style.blue.opacity(0.48),
                gradientEnd: .black,
                action: .photo
            ),
            HomeMediaItem(
                id: "video",
                title: localized("home_media_video_title", fallback: "Видео"),
                subtitle: localized("home_media_video_subtitle", fallback: "Kling AI: text/image to video"),
                kicker: "KLING",
                systemImage: "video.fill",
                videoURL: URL(string: "https://v16-kling.klingai.com/kos/s101/nlav112918/kling-website/page1-v3-0-en.mp4"),
                gradientStart: Color(red: 0.62, green: 1.0, blue: 0.0).opacity(0.36),
                gradientEnd: Color.black,
                action: .video
            )
        ]
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = loc.t(key)
        return value == key ? fallback : value
    }

    private var imageCategoryNavigationBinding: Binding<Bool> {
        Binding(
            get: { openImageCategory != nil },
            set: { isPresented in
                if !isPresented { openImageCategory = nil }
            }
        )
    }
}

private enum HomeMediaAction {
    case photo
    case video
}

private struct HomeMediaItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let kicker: String
    let systemImage: String
    let videoURL: URL?
    let gradientStart: Color
    let gradientEnd: Color
    let action: HomeMediaAction
}

private struct HomeMediaCard: View {
    let item: HomeMediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [item.gradientStart, item.gradientEnd],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)

            if let url = item.videoURL {
                LoopingVideo(url: url, fallback: item.gradientStart.opacity(0.18))
                    .overlay(Color.black.opacity(0.24))
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.78)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.kicker)
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(1.6)
                        .foregroundColor(.white.opacity(0.62))

                    Text(item.title)
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(.white)

                    Text(item.subtitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(2)
                }
                Spacer()

                Image(systemName: item.systemImage)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.14))
                    .clipShape(Circle())
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 236)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct HomeBannerCard: View {
    let banner: HomeBanner
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [banner.gradientStart, banner.gradientEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                // Build 66: LoopingVideo disabled — AVPlayer crash on iOS 26 stable.

                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.65)],
                    startPoint: .top, endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(banner.title)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.white)
                    Text(banner.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HomeToolCard: View {
    let tool: HomeTool
    let title: String
    let subtitle: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [tool.gradientStart, tool.gradientEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                if let url = tool.videoURL {
                    LoopingVideo(url: url, fallback: tool.gradientStart.opacity(0.28))
                        .overlay(Color.black.opacity(0.18))
                }

                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(12)

                Image(systemName: tool.icon)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.bottom, 60)
                    .padding(.leading, 12)
            }
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )

            if let tag = tool.tag, let tc = tool.tagColor {
                Text(tag)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundColor(.black)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(tc)
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
    }
}

private struct GenerationCategoryCard: View {
    let category: ImageGenerationCategory
    let title: String
    let subtitle: String
    let provider: ImageGenerationProvider

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: category.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(1)
                Text("\(provider.title) / \(ImageGenerationCatalog.creditCost)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }
        }
        .padding(13)
        .frame(width: 142, height: 146)
        .background(
            RadialGradient(
                colors: [category.gradientStart.opacity(0.24), Color.clear],
                center: .topLeading,
                startRadius: 4,
                endRadius: 150
            )
        )
        .x5ClearGlass(cornerRadius: 16, highlight: 0.11)
    }
}
