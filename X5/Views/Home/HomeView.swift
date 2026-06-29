import SwiftUI

/// Home uses an AI-studio layout: hero, tool grid, trend rail, and creator feed.
struct HomeView: View {
    @EnvironmentObject private var loc: LocalizationService

    @State private var openTool: HomeTool?
    @State private var openImageCategory: ImageGenerationCategory?
    @State private var showingGeneratedGallery = false
    @State private var selectedFeed = "Для тебя"
    @State private var activeHeroPage = 0
    @State private var activeToolsPage = 0

    private let feedTabs = ["Для тебя", "Shorts", "Реклама", "UGC", "4K"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroBanner
                    quickToolsGrid
                    trendsSection
                    feedSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 34)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background { X5Background() }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        openTool = developmentTool(id: "search", title: "Поиск", icon: "magnifyingglass")
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("Поиск")

                    Button {
                        showingGeneratedGallery = true
                    } label: {
                        Text("Мои креативы")
                            .font(.system(size: 13, weight: .bold))
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

    private var heroBanner: some View {
        TabView(selection: $activeHeroPage) {
            ForEach(Array(heroSlides.enumerated()), id: \.offset) { index, slide in
                Button {
                    handle(slide.action)
                } label: {
                    HeroSlideCard(slide: slide, activePage: activeHeroPage, pageCount: heroSlides.count)
                }
                .buttonStyle(.plain)
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 136)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var heroSlides: [HeroSlide] {
        [
            HeroSlide(
                id: "studio",
                eyebrow: "X Five AI Studio",
                title: "Генерируй креативы для бизнеса",
                subtitle: "Картинки, видео, сторис, карточки товара и трендовые форматы",
                assetName: "HomeUtilityVideo",
                systemImage: "sparkles",
                action: .video
            ),
            HeroSlide(
                id: "influencer",
                eyebrow: "Trend Studio",
                title: "AI-инфлюенсер для Reels",
                subtitle: "Собери персонажа и запускай ролики без съемки",
                assetName: "HomeTrendInfluencer",
                systemImage: "person.crop.square",
                action: .tool("ai_influencer")
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
                action: .video
            )
        ]
    }

    private var quickToolsGrid: some View {
        VStack(spacing: 8) {
            TabView(selection: $activeToolsPage) {
                ForEach(Array(quickToolPages.enumerated()), id: \.offset) { pageIndex, page in
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(minimum: 52), spacing: 10), count: 4),
                        spacing: 10
                    ) {
                        ForEach(page) { tool in
                            Button {
                                handle(tool.action)
                            } label: {
                                StudioToolButton(tool: tool)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .tag(pageIndex)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 160)

            PageDots(active: activeToolsPage, count: quickToolPages.count)
            .frame(maxWidth: .infinity)
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Тренды", trailing: "Еще")

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

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 22) {
                    ForEach(feedTabs, id: \.self) { tab in
                        Button {
                            selectedFeed = tab
                            X5Feedback.selection()
                        } label: {
                            Text(tab)
                                .font(.system(size: 20, weight: selectedFeed == tab ? .heavy : .semibold))
                                .foregroundColor(selectedFeed == tab ? .white : .white.opacity(0.38))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }

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

    private func sectionHeader(title: String, trailing: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(.white)
            Spacer()
            Button {
                openTool = developmentTool(id: "more_\(title)", title: title, icon: "ellipsis")
            } label: {
                HStack(spacing: 5) {
                    Text(trailing)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.48))
            }
            .buttonStyle(.plain)
        }
    }

    private var quickTools: [StudioTool] {
        [
            StudioTool(id: "image_to_video", title: "Image to Video", icon: "photo", badge: nil, action: .video),
            StudioTool(id: "text_to_video", title: "Text to Video", icon: "text.bubble", badge: nil, action: .video),
            StudioTool(id: "avatar", title: "Avatar 2.0", icon: "person.crop.circle", badge: nil, action: .tool("ai_influencer")),
            StudioTool(id: "motion", title: "Motion Control", icon: "scope", badge: nil, action: .tool("video_creative")),
            StudioTool(id: "text_to_image", title: "AI Image", icon: "photo.badge.plus", badge: nil, action: .image(ImageGenerationCatalog.custom)),
            StudioTool(id: "ai_video", title: "AI Video", icon: "video", badge: "Motion", action: .video),
            StudioTool(id: "elements", title: "Карточки", icon: "rectangle.grid.2x2", badge: nil, action: imageAction("product_cards")),
            StudioTool(id: "restyle", title: "Restyle", icon: "paintpalette", badge: nil, action: imageAction("insta_pack")),
            StudioTool(id: "effects", title: "Effects", icon: "wand.and.sparkles", badge: nil, action: imageAction("story")),
            StudioTool(id: "sound", title: "Sound", icon: "waveform", badge: nil, action: .tool("voice_tts")),
            StudioTool(id: "logo", title: "Лого", icon: "seal", badge: nil, action: imageAction("logo")),
            StudioTool(id: "post", title: "Пост", icon: "square.grid.2x2", badge: nil, action: imageAction("post")),
            StudioTool(id: "product", title: "Фото товара", icon: "shippingbox", badge: nil, action: imageAction("product")),
            StudioTool(id: "packaging", title: "Упаковка", icon: "cube.box", badge: nil, action: imageAction("packaging")),
            StudioTool(id: "startup", title: "Startup Chat", icon: "sparkles.rectangle.stack", badge: nil, action: .tool("startup_chat"))
        ]
    }

    private var quickToolPages: [[StudioTool]] {
        quickTools.chunked(into: 8)
    }

    private var trendCards: [VisualCardItem] {
        [
            VisualCardItem(id: "ai_influencer", title: "AI-инфлюенсер", subtitle: "Персонаж для роликов", assetName: "HomeTrendInfluencer", systemImage: "person.crop.square", action: .tool("ai_influencer"), showsPlay: false),
            VisualCardItem(id: "fruit_video", title: "Живые фрукты", subtitle: "Видео для Reels", assetName: "HomeTrendFruitVideo", systemImage: "play.tv", action: .video, showsPlay: true),
            VisualCardItem(id: "trend_post", title: "Пост-тренд", subtitle: "Идея для ленты", assetName: "HomeTrendPost", systemImage: "sparkles", action: imageAction("post"), showsPlay: false),
            VisualCardItem(id: "live_video", title: "Видео тренды", subtitle: "Shorts и TikTok", assetName: "HomeTrendLiveVideo", systemImage: "film.stack", action: .video, showsPlay: true),
            VisualCardItem(id: "target", title: "Таргет", subtitle: "Креативы теста", assetName: "HomeCoverTargetAds", systemImage: "scope", action: imageAction("target_ad"), showsPlay: false)
        ]
    }

    private var feedCards: [VisualCardItem] {
        [
            VisualCardItem(id: "youtube", title: "Обложка YouTube", subtitle: "Превью с высоким CTR", assetName: "HomeCoverYoutube", systemImage: "play.rectangle", action: imageAction("youtube_cover"), showsPlay: false),
            VisualCardItem(id: "product_cards", title: "Карточки товара", subtitle: "Маркетплейс и сайт", assetName: "HomeCoverProductCards", systemImage: "rectangle.grid.2x2", action: imageAction("product_cards"), showsPlay: false),
            VisualCardItem(id: "video", title: "AI Video", subtitle: "Фото или текст в ролик", assetName: "HomeUtilityVideo", systemImage: "video", action: .video, showsPlay: true),
            VisualCardItem(id: "insta", title: "Упаковка Instagram", subtitle: "Посты и сторис", assetName: "HomeUtilityInstaPack", systemImage: "square.stack.3d.up", action: imageAction("insta_pack"), showsPlay: false),
            VisualCardItem(id: "product", title: "Фото товара", subtitle: "Кадр для рекламы", assetName: "HomeUtilityProduct", systemImage: "shippingbox", action: imageAction("product"), showsPlay: false),
            VisualCardItem(id: "logo", title: "Лого", subtitle: "Знак для бренда", assetName: "HomeUtilityLogo", systemImage: "seal", action: imageAction("logo"), showsPlay: false)
        ]
    }

    private func imageAction(_ categoryId: String) -> StudioAction {
        let categories = Dictionary(uniqueKeysWithValues: ImageGenerationCatalog.categories.map { ($0.id, $0) })
        return categories[categoryId].map(StudioAction.image) ?? .image(ImageGenerationCatalog.custom)
    }

    private func handle(_ action: StudioAction) {
        switch action {
        case .image(let category):
            DiagnosticLogger.log(event: "home_studio_\(category.id)_tap")
            openImageCategory = category
        case .video:
            DiagnosticLogger.log(event: "home_studio_video_tap")
            openVideoTool()
        case .tool(let id):
            DiagnosticLogger.log(event: "home_studio_\(id)_tap")
            openTool = HomeContent.tools.first(where: { $0.id == id })
                ?? developmentTool(id: id, title: developmentTitle(for: id))
        }
    }

    private func openVideoTool() {
        openTool = HomeContent.tools.first(where: { $0.id == "video_gen" })
            ?? developmentTool(id: "video_gen", title: "AI Video", icon: "video")
    }

    private func developmentTool(id: String, title: String, icon: String = "hammer.fill") -> HomeTool {
        HomeTool(
            id: id,
            title: title,
            subtitle: "Скоро добавим полный запуск внутри X Five Marketing.",
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

private enum StudioAction {
    case image(ImageGenerationCategory)
    case video
    case tool(String)
}

private struct HeroSlide: Identifiable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let assetName: String
    let systemImage: String
    let action: StudioAction
}

private struct StudioTool: Identifiable {
    let id: String
    let title: String
    let icon: String
    let badge: String?
    let action: StudioAction
}

private struct VisualCardItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let assetName: String
    let systemImage: String
    let action: StudioAction
    let showsPlay: Bool
}

private struct HeroSlideCard: View {
    let slide: HeroSlide
    let activePage: Int
    let pageCount: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardImage(assetName: slide.assetName)

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

private struct StudioToolButton: View {
    let tool: StudioTool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                Image(systemName: tool.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
                    .frame(width: 48, height: 48)

                if let badge = tool.badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .offset(x: 9, y: -7)
                }
            }

            Text(tool.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .frame(height: 24, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TrendCard: View {
    let item: VisualCardItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardImage(assetName: item.assetName)

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
        .frame(width: 148, height: 178)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct FeedCard: View {
    let item: VisualCardItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CardImage(assetName: item.assetName)

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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
