import SwiftUI

enum HomeRoute: Hashable, Identifiable {
    case imageGeneration(ImageGenerationCategory)
    case startupChat
    case hub
    case videoGeneration
    case voiceGeneration
    case liveFruits
    case tool(String)

    var id: String {
        switch self {
        case .imageGeneration(let category):
            return "image_generation:\(category.id)"
        case .startupChat:
            return "startup_chat"
        case .hub:
            return "hub"
        case .videoGeneration:
            return "video_generation"
        case .voiceGeneration:
            return "voice_generation"
        case .liveFruits:
            return "live_fruits"
        case .tool(let id):
            return "tool:\(id)"
        }
    }
}

/// Client-approved Home layout. Every visible card opens a working route.
struct HomeView: View {
    @EnvironmentObject private var loc: LocalizationService

    @State private var activeRoute: HomeRoute?
    @State private var openImageCategory: ImageGenerationCategory?
    @State private var showingGeneratedGallery = false
    @State private var activeHeroPage = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroBanner
                    promoCards
                    trendsSection
                    businessSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 34)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background { X5Background() }
            .navigationTitle("X five marketing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingGeneratedGallery = true
                    } label: {
                        Image(systemName: "photo.stack")
                    }
                    .accessibilityLabel(loc.t("gen_gallery"))
                }
            }
            .sheet(item: $activeRoute) { route in
                sheetDestination(for: route)
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

    private var heroBanner: some View {
        TabView(selection: $activeHeroPage) {
            ForEach(Array(heroSlides.enumerated()), id: \.offset) { index, slide in
                Button {
                    handle(slide.action)
                } label: {
                    HeroSlideCard(
                        slide: slide,
                        pageIndex: index,
                        activePage: activeHeroPage,
                        pageCount: heroSlides.count
                    )
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 244)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var heroSlides: [HeroSlide] {
        [
            HeroSlide(
                id: "studio",
                eyebrow: "X five marketing",
                title: "Генерация изображений",
                subtitle: "Создай рекламный креатив, фото товара или пост",
                assetName: "HomeCoverTargetAds",
                systemImage: "photo.badge.plus",
                action: .imageGeneration(ImageGenerationCatalog.custom)
            ),
            HeroSlide(
                id: "video_generation",
                eyebrow: "AI Video",
                title: "Генерация видео",
                subtitle: "Преврати текст или фотографию в готовый ролик",
                assetName: "HomeUtilityVideo",
                systemImage: "video.fill",
                action: .videoGeneration
            ),
            HeroSlide(
                id: "commerce",
                eyebrow: "Business Pack",
                title: "Карточки и фото товара",
                subtitle: "Маркетплейс, сайт и таргет в одном стиле",
                assetName: "HomeCoverProductCards",
                systemImage: "rectangle.grid.2x2",
                action: imageAction("product_cards")
            ),
            HeroSlide(
                id: "fruit",
                eyebrow: "Video Trend",
                title: "Живые продукты в видео",
                subtitle: "Фрукты, напитки и товарные ролики для ленты",
                assetName: "HomeTrendFruitVideo",
                systemImage: "play.tv",
                action: .liveFruits
            )
        ]
    }

    private var promos: [HomePromo] {
        [
            HomePromo(
                id: "startup_chat",
                title: "Стартап чат",
                subtitle: "AI-наставник для бизнеса",
                systemImage: "sparkles.rectangle.stack",
                accent: Color(red: 0.11, green: 0.80, blue: 0.58),
                action: .startupChat
            ),
            HomePromo(
                id: "hub",
                title: "Hub",
                subtitle: "Специалисты и задачи",
                systemImage: "briefcase",
                accent: Color(red: 0.96, green: 0.29, blue: 0.56),
                action: .hub
            )
        ]
    }

    private var promoCards: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 12),
                count: 2
            ),
            spacing: 12
        ) {
            ForEach(promos) { promo in
                Button {
                    handle(promo.action)
                } label: {
                    HomePromoCard(promo: promo)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Тренды")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(trendCards) { item in
                        Button {
                            handle(item.action)
                        } label: {
                            TrendCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var businessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Дизайн для бизнеса")

            Button { handle(imageAction("insta_pack")) } label: {
                InstagramFeatureCard()
            }
            .buttonStyle(.plain)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(feedCards) { item in
                    Button {
                        handle(item.action)
                    } label: {
                        FeedCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 27, weight: .black))
                .foregroundColor(.white)
            Spacer()
        }
    }

    private var trendCards: [VisualCardItem] {
        [
            VisualCardItem(id: "fruit_video", title: "Живые фрукты", subtitle: "Видео для Reels", assetName: "HomeTrendFruitVideo", systemImage: "play.tv", action: .liveFruits, showsPlay: true),
            VisualCardItem(id: "nano_banana", title: "Nano Banana + GPT Image", subtitle: "AI-креативы", assetName: "HomeTrendNanoBanana", systemImage: "sparkles", action: .imageGeneration(ImageGenerationCatalog.custom), showsPlay: false),
            VisualCardItem(id: "live_video", title: "Видео тренды", subtitle: "Shorts и TikTok", assetName: "HomeTrendLiveVideo", systemImage: "film.stack", action: .videoGeneration, showsPlay: true),
            VisualCardItem(id: "target", title: "Таргет", subtitle: "Креативы теста", assetName: "HomeCoverTargetAds", systemImage: "scope", action: imageAction("target_ad"), showsPlay: false)
        ]
    }

    private var feedCards: [VisualCardItem] {
        [
            VisualCardItem(id: "youtube", title: "Обложка YouTube", subtitle: "Превью с высоким CTR", assetName: "HomeCoverYoutube", systemImage: "play.rectangle", action: imageAction("youtube_cover"), showsPlay: false),
            VisualCardItem(id: "product_cards", title: "Карточки товара", subtitle: "Маркетплейс и сайт", assetName: "HomeCoverProductCards", systemImage: "rectangle.grid.2x2", action: imageAction("product_cards"), showsPlay: false),
            VisualCardItem(id: "product", title: "Фото товара", subtitle: "Кадр для рекламы", assetName: "HomeUtilityProduct", systemImage: "shippingbox", action: imageAction("product"), showsPlay: false),
            VisualCardItem(id: "logo", title: "Лого", subtitle: "Знак для бренда", assetName: "HomeUtilityLogo", systemImage: "seal", action: imageAction("logo"), showsPlay: false),
            VisualCardItem(id: "packaging", title: "Упаковка", subtitle: "Единый стиль бренда", assetName: "HomeUtilityPackaging", systemImage: "cube.box", action: imageAction("packaging"), showsPlay: false),
            VisualCardItem(id: "target", title: "Креативы для рекламы", subtitle: "Статика для тестов", assetName: "HomeCoverTargetAds", systemImage: "scope", action: imageAction("target_ad"), showsPlay: false)
        ]
    }

    private func imageAction(_ categoryId: String) -> HomeRoute {
        let categories = Dictionary(uniqueKeysWithValues: ImageGenerationCatalog.categories.map { ($0.id, $0) })
        return categories[categoryId].map(HomeRoute.imageGeneration)
            ?? .imageGeneration(ImageGenerationCatalog.custom)
    }

    private func handle(_ route: HomeRoute) {
        switch route {
        case .imageGeneration(let category):
            DiagnosticLogger.log(event: "home_studio_\(category.id)_tap")
            openImageCategory = category
        case .hub:
            DiagnosticLogger.log(event: "home_hub_promo_tap")
            NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "hub"])
        case .videoGeneration:
            DiagnosticLogger.log(event: "home_studio_video_tap")
            activeRoute = route
        case .voiceGeneration:
            DiagnosticLogger.log(event: "home_studio_voice_tap")
            activeRoute = route
        case .liveFruits:
            DiagnosticLogger.log(event: "home_live_fruits_tap")
            activeRoute = route
        case .startupChat:
            DiagnosticLogger.log(event: "home_startup_chat_tap")
            activeRoute = route
        case .tool(let id):
            DiagnosticLogger.log(event: "home_studio_\(id)_tap")
            activeRoute = route
        }
    }

    @ViewBuilder
    private func sheetDestination(for route: HomeRoute) -> some View {
        switch route {
        case .videoGeneration:
            VideoGeneratorView()
        case .voiceGeneration:
            VoiceGeneratorView()
        case .startupChat:
            StartupChatView()
        case .liveFruits:
            LiveFruitsView()
        case .tool:
            ToolDetailView(tool: placeholderTool(for: route))
        case .imageGeneration, .hub:
            EmptyView()
        }
    }

    private func placeholderTool(for route: HomeRoute) -> HomeTool {
        switch route {
        case .startupChat:
            return developmentTool(id: "startup_assistant", title: "Стартап чат", icon: "sparkles.rectangle.stack")
        case .videoGeneration:
            return developmentTool(id: "video_generation", title: "Генерация видео", icon: "video")
        case .voiceGeneration:
            return developmentTool(id: "voice_generation", title: "Озвучка", icon: "waveform")
        case .liveFruits:
            return developmentTool(id: "live_fruits", title: "Живые фрукты", icon: "play.tv")
        case .tool(let id):
            return HomeContent.tools.first(where: { $0.id == id })
                ?? developmentTool(id: id, title: developmentTitle(for: id))
        case .imageGeneration:
            return developmentTool(id: "image", title: "Генерация изображений", icon: "photo.badge.plus")
        case .hub:
            return developmentTool(id: "hub", title: "Hub", icon: "briefcase")
        }
    }

    private func developmentTool(id: String, title: String, icon: String = "hammer.fill") -> HomeTool {
        HomeTool(
            id: id,
            title: title,
            subtitle: "Скоро добавим полный запуск внутри X five marketing.",
            icon: icon,
            videoFile: nil,
            gradientStart: Color.accentColor.opacity(0.34),
            gradientEnd: Color(red: 0.03, green: 0.04, blue: 0.08),
            tag: "SOON",
            tagColor: Color.accentColor
        )
    }

    private func developmentTitle(for id: String) -> String {
        switch id {
        case "ai_influencer": return "AI-инфлюенсер"
        case "video_creative": return "Видео-креатив"
        case "voice_tts": return "Sound"
        case "startup_chat": return "Startup Chat"
        default:
            return id
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
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

private struct HeroSlide: Identifiable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let assetName: String
    let systemImage: String
    let action: HomeRoute
}

private struct HomePromo: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let accent: Color
    let action: HomeRoute
}

private struct VisualCardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let assetName: String
    let systemImage: String
    let action: HomeRoute
    let showsPlay: Bool
}

private struct HeroSlideCard: View {
    let slide: HeroSlide
    let pageIndex: Int
    let activePage: Int
    let pageCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardMedia(assetName: slide.assetName, isMotionActive: false)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.05),
                    Color.black.opacity(0.30),
                    Color.black.opacity(0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: slide.systemImage)
                        .font(.system(size: 14, weight: .heavy))
                    Text(slide.eyebrow)
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundColor(.white.opacity(0.82))

                Text(slide.title)
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(slide.subtitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.74))
                    .lineLimit(2)
                    .minimumScaleFactor(0.84)
            }
            .padding(18)
            .padding(.trailing, 52)

            PageDots(active: activePage, count: pageCount)
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct HomePromoCard: View {
    let promo: HomePromo

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.white
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: promo.systemImage)
                        .font(.system(size: 21, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 42, height: 42)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .black))
                        .foregroundColor(X5Style.blue)
                }

                Text(promo.title)
                    .font(.system(size: 17, weight: .black))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(promo.subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black.opacity(0.55))
                    .lineLimit(2)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.85), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 13, x: 0, y: 8)
    }
}

private struct PageDots: View {
    let active: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(count, 1), id: \.self) { index in
                Capsule()
                    .fill(index == active ? Color.white : Color.white.opacity(0.32))
                    .frame(width: index == active ? 24 : 7, height: 7)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: active)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct TrendCard: View {
    let item: VisualCardItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardMedia(assetName: item.assetName, isMotionActive: item.showsPlay)

            LinearGradient(
                colors: [Color.black.opacity(0.05), Color.black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text(item.title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(item.subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.76))
                    .lineLimit(1)
            }
            .padding(12)

            if item.showsPlay {
                PlayBadge()
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        // The client-supplied Nano Banana artwork is landscape and contains
        // important center-aligned labels. Give it enough width to keep those
        // labels readable instead of applying a destructive portrait crop.
        .frame(width: item.id == "nano_banana" ? 236 : 148, height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct InstagramFeatureCard: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [.white, Color(red: 0.94, green: 0.91, blue: 1.0)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Image("HomeUtilityInstaPack")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width * 0.57, height: proxy.size.height)
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .mask(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.88), .black],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Оформление")
                        .font(.system(size: 26, weight: .black))
                        .foregroundColor(.black.opacity(0.86))
                    Text("Instagram")
                        .font(.system(size: 34, weight: .black))
                        .italic()
                        .foregroundColor(Color(red: 0.48, green: 0.30, blue: 0.78))
                    Text("Посты и сторис\nв едином стиле")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black.opacity(0.60))
                    Text("СОЗДАТЬ")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.black)
                        .frame(width: 82, height: 28)
                        .background(X5Style.blue)
                        .clipShape(Capsule())
                        .padding(.top, 6)
                }
                .padding(20)
            }
        }
        .frame(height: 218)
        .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .stroke(Color.white.opacity(0.64), lineWidth: 1)
        )
    }
}

private struct FeedCard: View {
    let item: VisualCardItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardMedia(assetName: item.assetName, isMotionActive: item.showsPlay)

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(item.subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
                    .lineLimit(2)
            }
            .padding(12)

            if item.showsPlay {
                PlayBadge()
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .frame(height: 196)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct CardImage: View {
    let assetName: String

    var body: some View {
        GeometryReader { proxy in
            Image(assetName)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
        }
        .background(Color.white.opacity(0.06))
    }
}

private struct CardMedia: View {
    let assetName: String
    let isMotionActive: Bool

    @ViewBuilder
    var body: some View {
        if isMotionActive, let motion = HomeMotionCatalog.asset(for: assetName) {
            LoopingVideo(
                source: motion.source,
                posterAssetName: motion.posterAssetName,
                isActive: true
            )
        } else {
            CardImage(assetName: assetName)
        }
    }
}

private struct PlayBadge: View {
    var body: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 32, height: 32)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
}
