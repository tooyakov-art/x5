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
                    businessPanel
                    trendsPanel
                    moreGrid
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

    private var businessPanel: some View {
        HomeSectionPanel(title: "Креативы", subtitle: "Что чаще всего нужно бизнесу") {
            mediaGrid(items: businessMediaItems)
        }
    }

    private var trendsPanel: some View {
        HomeSectionPanel(title: "Тренды", subtitle: "Вирусные форматы для Reels, TikTok и Shorts") {
            mediaGrid(items: trendMediaItems)
        }
    }

    private var moreGrid: some View {
        mediaGrid(items: utilityMediaItems)
    }

    private func mediaGrid(items: [HomeMediaItem]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(items) { item in mediaButton(item) }
        }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private func mediaButton(_ item: HomeMediaItem) -> some View {
        Button {
            switch item.action {
            case .image(let category):
                DiagnosticLogger.log(event: "home_media_\(category.id)_tap")
                openImageCategory = category
            case .video:
                DiagnosticLogger.log(event: "home_media_video_tap")
                openTool = HomeContent.tools.first(where: { $0.id == "video_gen" })
            case .tool(let id):
                DiagnosticLogger.log(event: "home_media_\(id)_tap")
                openTool = HomeContent.tools.first(where: { $0.id == id })
            }
        } label: {
            HomeMediaCard(item: item)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
    }

    private var businessMediaItems: [HomeMediaItem] {
        let categories = Dictionary(uniqueKeysWithValues: ImageGenerationCatalog.categories.map { ($0.id, $0) })
        return [
            HomeMediaItem(
                id: "youtube_cover",
                title: localized("home_media_youtube_title", fallback: "Обложка YouTube"),
                subtitle: localized("home_media_youtube_subtitle", fallback: "Кликабельная превью-картинка"),
                kicker: "YOUTUBE",
                systemImage: "play.rectangle.fill",
                assetName: "HomeCoverYoutube",
                videoURL: nil,
                gradientStart: X5Style.blue.opacity(0.38),
                gradientEnd: .black,
                action: categories["youtube_cover"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "product_cards",
                title: localized("home_media_product_cards_title", fallback: "Карточки товара"),
                subtitle: localized("home_media_product_cards_subtitle", fallback: "Для маркетплейса и сайта"),
                kicker: "SHOP",
                systemImage: "rectangle.grid.2x2.fill",
                assetName: "HomeCoverProductCards",
                videoURL: nil,
                gradientStart: Color(red: 0.56, green: 0.72, blue: 0.92).opacity(0.36),
                gradientEnd: .black,
                action: categories["product_cards"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "target_ad",
                title: localized("home_media_target_title", fallback: "Для таргета"),
                subtitle: localized("home_media_target_subtitle", fallback: "Креатив для Instagram и TikTok"),
                kicker: "ADS",
                systemImage: "scope",
                assetName: "HomeCoverTargetAds",
                videoURL: nil,
                gradientStart: Color(red: 0.20, green: 0.42, blue: 0.95).opacity(0.42),
                gradientEnd: .black,
                action: categories["target_ad"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "story",
                title: localized("home_media_story_title", fallback: "Генерация сторис"),
                subtitle: localized("home_media_story_subtitle", fallback: "Вертикальный креатив 9:16"),
                kicker: "STORY",
                systemImage: "rectangle.portrait.fill",
                assetName: "HomeCoverStories",
                videoURL: nil,
                gradientStart: X5Style.backgroundCyan.opacity(0.42),
                gradientEnd: .black,
                action: categories["story"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            )
        ]
    }

    private var trendMediaItems: [HomeMediaItem] {
        let categories = Dictionary(uniqueKeysWithValues: ImageGenerationCatalog.categories.map { ($0.id, $0) })
        return [
            HomeMediaItem(
                id: "ai_influencer",
                title: localized("home_media_ai_influencer_title", fallback: "AI-инфлюенсер"),
                subtitle: localized("home_media_ai_influencer_subtitle", fallback: "Персонаж для роликов"),
                kicker: "TREND",
                systemImage: "person.crop.square.filled.and.at.rectangle",
                assetName: "HomeTrendInfluencer",
                videoURL: nil,
                gradientStart: Color(red: 0.30, green: 0.42, blue: 0.98).opacity(0.42),
                gradientEnd: .black,
                action: .tool("ai_influencer")
            ),
            HomeMediaItem(
                id: "fruit_video",
                title: localized("home_media_fruit_video_title", fallback: "Живые фрукты"),
                subtitle: localized("home_media_fruit_video_subtitle", fallback: "Фруктовый ролик за минуту"),
                kicker: "VIDEO",
                systemImage: "play.tv.fill",
                assetName: "HomeTrendFruitVideo",
                videoURL: nil,
                gradientStart: Color(red: 0.02, green: 0.58, blue: 0.72).opacity(0.38),
                gradientEnd: .black,
                action: .video
            ),
            HomeMediaItem(
                id: "trend_post",
                title: localized("home_media_trend_post_title", fallback: "Пост-тренд"),
                subtitle: localized("home_media_trend_post_subtitle", fallback: "Готовая идея для ленты"),
                kicker: "POST",
                systemImage: "sparkles",
                assetName: "HomeTrendPost",
                videoURL: nil,
                gradientStart: X5Style.blue.opacity(0.34),
                gradientEnd: .black,
                action: categories["post"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "trend_video",
                title: localized("home_media_video_trends_title", fallback: "Видео тренды"),
                subtitle: localized("home_media_video_trends_subtitle", fallback: "Reels и TikTok идеи"),
                kicker: "REELS",
                systemImage: "film.stack",
                assetName: "HomeTrendLiveVideo",
                videoURL: nil,
                gradientStart: Color(red: 0.50, green: 0.60, blue: 1.0).opacity(0.35),
                gradientEnd: .black,
                action: .video
            )
        ]
    }

    private var utilityMediaItems: [HomeMediaItem] {
        let categories = Dictionary(uniqueKeysWithValues: ImageGenerationCatalog.categories.map { ($0.id, $0) })
        return [
            HomeMediaItem(
                id: "custom",
                title: localized("home_media_custom_title", fallback: "Генерация изображения"),
                subtitle: localized("home_media_custom_subtitle", fallback: "Любой промпт, фото или идея"),
                kicker: "IMAGE",
                systemImage: "sparkles",
                assetName: nil,
                videoURL: HomeMediaVideos.custom,
                gradientStart: X5Style.backgroundBlue.opacity(0.48),
                gradientEnd: .black,
                action: .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "logo",
                title: localized("home_media_logo_title", fallback: "Генерация лого"),
                subtitle: localized("home_media_logo_subtitle", fallback: "Логотип для бренда"),
                kicker: "LOGO",
                systemImage: "seal.fill",
                assetName: nil,
                videoURL: HomeMediaVideos.logo,
                gradientStart: X5Style.blue.opacity(0.40),
                gradientEnd: .black,
                action: categories["logo"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "post",
                title: localized("home_media_post_title", fallback: "Генерация поста"),
                subtitle: localized("home_media_post_subtitle", fallback: "Пост для ленты"),
                kicker: "POST",
                systemImage: "square.grid.2x2.fill",
                assetName: nil,
                videoURL: HomeMediaVideos.post,
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
                assetName: nil,
                videoURL: HomeMediaVideos.instaPack,
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
                assetName: nil,
                videoURL: HomeMediaVideos.product,
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
                assetName: nil,
                videoURL: HomeMediaVideos.packaging,
                gradientStart: Color(red: 0.72, green: 0.82, blue: 0.92).opacity(0.30),
                gradientEnd: .black,
                action: categories["packaging"].map(HomeMediaAction.image) ?? .image(ImageGenerationCatalog.custom)
            ),
            HomeMediaItem(
                id: "video",
                title: localized("home_media_video_title", fallback: "Генерация видео"),
                subtitle: localized("home_media_video_subtitle", fallback: "Kling: текст или фото в видео"),
                kicker: "KLING",
                systemImage: "video.fill",
                assetName: nil,
                videoURL: HomeMediaVideos.video,
                gradientStart: X5Style.blue.opacity(0.38),
                gradientEnd: .black,
                action: .video
            ),
            HomeMediaItem(
                id: "startup_chat",
                title: localized("home_media_startup_chat_title", fallback: "Стартап чат"),
                subtitle: localized("home_media_startup_chat_subtitle", fallback: "ИИ-помощник для бизнеса"),
                kicker: "SOON",
                systemImage: "sparkles.rectangle.stack.fill",
                assetName: nil,
                videoURL: nil,
                gradientStart: X5Style.backgroundBlue.opacity(0.44),
                gradientEnd: .black,
                action: .tool("startup_chat")
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
    case tool(String)
}

private enum HomeMediaVideos {
    static let logo = URL(string: "https://cdn.higgsfield.ai/kling_motion/af9b47a1-6db9-4a68-bdc4-467a49fca07e.mp4")
    static let story = URL(string: "https://cdn.higgsfield.ai/card/9268ed82-5e18-439c-8758-12bb301fab63.mp4")
    static let post = URL(string: "https://cdn.higgsfield.ai/card/62f23c78-13bc-49e5-8149-3ef22fda7638.mp4")
    static let instaPack: URL? = nil
    static let product: URL? = nil
    static let packaging = URL(string: "https://static.higgsfield.ai/canvas/Advertising/result-mini.mp4")
    static let custom: URL? = nil
    static let video = URL(string: "https://static.higgsfield.ai/ai-video/ecommerce-1-mini.mp4")
}

private struct HomeMediaItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let kicker: String
    let systemImage: String
    let assetName: String?
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
            } else if let assetName = item.assetName {
                GeometryReader { proxy in
                    Image(assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                .overlay(Color.black.opacity(0.08))
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

private struct HomeSectionPanel<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .black))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.58))
                    .lineLimit(2)
            }
            .padding(.horizontal, 2)

            content
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}
