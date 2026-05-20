import SwiftUI

/// Home shows clear generation scenarios as compact video-backed cards.
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
                    mediaGrid
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
                .foregroundColor(X5Style.blue)
            Text("Маркетинг")
                .font(.system(size: 36, weight: .black))
                .foregroundColor(.white)
                .kerning(-0.6)
        }
        .padding(.top, -10)
        .padding(.leading, 2)
    }

    private var mediaGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            ForEach(homeMediaItems) { item in
                Button {
                    switch item.action {
                    case .image(let category):
                        DiagnosticLogger.log(event: "home_media_\(category.id)_tap")
                        openImageCategory = category
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
        let categories = Dictionary(uniqueKeysWithValues: ImageGenerationCatalog.categories.map { ($0.id, $0) })
        let klingVideos = [
            "https://v1-kling.kechuangai.com/kcdn/cdn-kcdn112452/kling-website/dev-home/demo-1-global.308958a99ecaeaf6.mp4",
            "https://v1-kling.kechuangai.com/kcdn/cdn-kcdn112452/kling-website/dev-home/demo-2-global.3d9f73e4e7668b72.mp4",
            "https://v1-kling.kechuangai.com/kcdn/cdn-kcdn112452/kling-website/dev-home/demo-3-global.038434fdc4f93199.mp4",
            "https://v1-kling.kechuangai.com/kcdn/cdn-kcdn112452/kling-website/dev-home/page3-video-en.37caf59c5ac36bc6.mp4",
            "https://v16-kling.klingai.com/kos/s101/nlav112918/kling-website/page1-v3-1.mp4",
            "https://v16-kling.klingai.com/kos/s101/nlav112918/kling-website/page1-v3-2.mp4",
            "https://v16-kling.klingai.com/kos/s101/nlav112918/kling-website/page1-v3-3.mp4"
        ]

        return [
            HomeMediaItem(
                id: "logo",
                title: localized("home_media_logo_title", fallback: "Генерация лого"),
                subtitle: localized("home_media_logo_subtitle", fallback: "Логотип для бренда"),
                kicker: "LOGO",
                systemImage: "seal.fill",
                videoURL: URL(string: klingVideos[0]),
                gradientStart: X5Style.blue.opacity(0.40),
                gradientEnd: .black,
                action: categories["logo"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "story",
                title: localized("home_media_story_title", fallback: "Генерация сторис"),
                subtitle: localized("home_media_story_subtitle", fallback: "Вертикальный креатив 9:16"),
                kicker: "STORY",
                systemImage: "rectangle.portrait.fill",
                videoURL: URL(string: klingVideos[1]),
                gradientStart: X5Style.backgroundCyan.opacity(0.42),
                gradientEnd: .black,
                action: categories["story"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "post",
                title: localized("home_media_post_title", fallback: "Генерация поста"),
                subtitle: localized("home_media_post_subtitle", fallback: "Пост для ленты"),
                kicker: "POST",
                systemImage: "square.grid.2x2.fill",
                videoURL: URL(string: klingVideos[2]),
                gradientStart: Color(red: 0.20, green: 0.42, blue: 0.95).opacity(0.42),
                gradientEnd: .black,
                action: categories["post"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "insta_pack",
                title: localized("home_media_instapack_title", fallback: "Упаковка Instagram"),
                subtitle: localized("home_media_instapack_subtitle", fallback: "Посты и сторис в одном стиле"),
                kicker: "INSTA",
                systemImage: "square.stack.3d.up.fill",
                videoURL: URL(string: klingVideos[3]),
                gradientStart: Color(red: 0.42, green: 0.55, blue: 1.0).opacity(0.40),
                gradientEnd: .black,
                action: categories["insta_pack"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "product",
                title: localized("home_media_product_title", fallback: "Фото товара"),
                subtitle: localized("home_media_product_subtitle", fallback: "Кадр для рекламы"),
                kicker: "PRODUCT",
                systemImage: "shippingbox.fill",
                videoURL: URL(string: klingVideos[4]),
                gradientStart: X5Style.blue.opacity(0.34),
                gradientEnd: .black,
                action: categories["product"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "packaging",
                title: localized("home_media_packaging_title", fallback: "Дизайн упаковки"),
                subtitle: localized("home_media_packaging_subtitle", fallback: "Коробка, этикетка, мокап"),
                kicker: "PACK",
                systemImage: "cube.box.fill",
                videoURL: URL(string: klingVideos[5]),
                gradientStart: Color(red: 0.72, green: 0.82, blue: 0.92).opacity(0.30),
                gradientEnd: .black,
                action: categories["packaging"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "custom",
                title: localized("home_media_custom_title", fallback: "Своя идея"),
                subtitle: localized("home_media_custom_subtitle", fallback: "Загрузи фото или напиши промпт"),
                kicker: "AI",
                systemImage: "photo",
                videoURL: URL(string: klingVideos[6]),
                gradientStart: X5Style.backgroundBlue.opacity(0.48),
                gradientEnd: .black,
                action: .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "video",
                title: localized("home_media_video_title", fallback: "Генерация видео"),
                subtitle: localized("home_media_video_subtitle", fallback: "Kling: текст или фото в видео"),
                kicker: "KLING",
                systemImage: "video.fill",
                videoURL: URL(string: klingVideos[1]),
                gradientStart: X5Style.blue.opacity(0.38),
                gradientEnd: .black,
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
    case image(ImageGenerationCategory)
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
                    .overlay(Color.black.opacity(0.20))
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.10),
                    Color.black.opacity(0.18),
                    Color.black.opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.kicker)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.3)
                        .foregroundColor(.white.opacity(0.62))
                    Spacer()
                    Image(systemName: item.systemImage)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white.opacity(0.92))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.13))
                        .clipShape(Circle())
                }

                Spacer(minLength: 18)

                Text(item.title)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.80)

                Text(item.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.74))
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 168)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
