import SwiftUI

enum HomeRoute: Hashable, Identifiable {
    case imageGeneration(ImageGenerationCategory)
    case startupChat
    case hub
    case videoGeneration
    case voiceGeneration
    case liveFruits

    var id: String {
        switch self {
        case .imageGeneration(let category): return "image_generation:\(category.id)"
        case .startupChat: return "startup_chat"
        case .hub: return "hub"
        case .videoGeneration: return "video_generation"
        case .voiceGeneration: return "voice_generation"
        case .liveFruits: return "live_fruits"
        }
    }
}

private enum HomeLayout {
    static let heroHeight: CGFloat = 198
    static let promoHeight: CGFloat = 78
    static let trendCardSize = CGSize(width: 96, height: 148)
    static let businessFeatureHeight: CGFloat = 198
    static let businessFeatureOverflow: CGFloat = 38
    static let businessTileHeight: CGFloat = 112
    static let businessWideHeight: CGFloat = 104
    static let sectionSpacing: CGFloat = 14
    static let cardSpacing: CGFloat = 8
}

/// Native Home composition. Photography and video posters are content-only assets;
/// labels, controls, card chrome, navigation and layout are SwiftUI views.
struct HomeView: View {
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeRoute: HomeRoute?
    @State private var openImageCategory: ImageGenerationCategory?
    @State private var showingGeneratedGallery = false
    @State private var showingSearch = false
    @State private var pendingSearchRoute: HomeRoute?
    @State private var activeHeroPage = 0
    @State private var activeTrendVideoID: String?
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
                    heroBanner
                    promoCards
                    trendsSection
                    businessSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 18)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background { NativeHomeBackground() }
            .navigationTitle("X five marketing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityIdentifier("x5.home.search")
                    .accessibilityLabel("Поиск инструментов")

                    Button {
                        showingGeneratedGallery = true
                    } label: {
                        Image(systemName: "photo.stack")
                    }
                    .accessibilityIdentifier("x5.home.gallery")
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
            .sheet(isPresented: $showingSearch, onDismiss: completePendingSearchRoute) {
                HomeSearchSheet { route in
                    pendingSearchRoute = route
                    showingSearch = false
                }
            }
        }
        .onDisappear { activeTrendVideoID = nil }
        .onChange(of: motionPreviewAllowed) { isAllowed in
            if !isAllowed { activeTrendVideoID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var heroBanner: some View {
        TabView(selection: $activeHeroPage) {
            ForEach(Array(heroSlides.enumerated()), id: \.element.id) { index, slide in
                NativeHomeHeroCard(
                    slide: slide,
                    pageIndex: index,
                    pageCount: heroSlides.count,
                    action: { handle(slide.action) }
                )
                .accessibilityIdentifier("x5.home.hero.\(slide.id)")
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: HomeLayout.heroHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var heroSlides: [NativeHomeHero] {
        [
            NativeHomeHero(
                id: "image",
                eyebrow: "X FIVE • AI STUDIO",
                title: "Генерация\nизображений",
                subtitle: "Креативы, товары и посты за минуту",
                assetName: "HomeCoverTargetAds",
                action: .imageGeneration(ImageGenerationCatalog.custom)
            ),
            NativeHomeHero(
                id: "video",
                eyebrow: "X FIVE • AI VIDEO",
                title: "Генерация\nвидео",
                subtitle: "Текст или фото в готовый ролик",
                assetName: "HomeUtilityVideo",
                action: .videoGeneration
            ),
            NativeHomeHero(
                id: "live_products",
                eyebrow: "X FIVE • VIDEO TREND",
                title: "Живые\nпродукты",
                subtitle: "Видео для Reels и коротких форматов",
                assetName: "HomeTrendFruitVideo",
                action: .liveFruits
            )
        ]
    }

    private var promoCards: some View {
        HStack(spacing: HomeLayout.cardSpacing) {
            NativeHomePromoCard(
                title: "Стартап чат",
                subtitle: "AI-наставник",
                icon: "message.badge",
                action: { handle(.startupChat) }
            )
            .accessibilityIdentifier("x5.home.promo.startup")

            NativeHomePromoCard(
                title: "Hub",
                subtitle: "Специалисты и задачи",
                icon: "briefcase.fill",
                action: { handle(.hub) }
            )
            .accessibilityIdentifier("x5.home.promo.hub")
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Тренды")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    handle(.videoGeneration)
                } label: {
                    Label("Еще", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.white.opacity(0.68))
                .accessibilityIdentifier("x5.home.trends.more")
                .accessibilityHint("Открывает генератор видео")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: HomeLayout.cardSpacing) {
                    ForEach(trendItems) { item in
                        NativeHomeTrendCard(
                            item: item,
                            isPlaying: motionPreviewAllowed && activeTrendVideoID == item.id,
                            onOpen: { handle(item.action) },
                            onPreview: { togglePreview(for: item) }
                        )
                        .accessibilityIdentifier("x5.home.trend.\(item.id)")
                    }
                }
                .padding(.horizontal, 1)
            }
            .accessibilityLabel("Тренды")
        }
    }

    private var businessSection: some View {
        VStack(alignment: .leading, spacing: HomeLayout.cardSpacing) {
            Text("Дизайн для бизнеса")
                .font(.title2.weight(.bold))
                .foregroundColor(.white)

            NativeHomeInstagramFeatureCard(
                action: { handle(imageAction("insta_pack")) }
            )
            .accessibilityIdentifier("x5.home.business.instagram")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: HomeLayout.cardSpacing),
                    GridItem(.flexible(), spacing: HomeLayout.cardSpacing)
                ],
                spacing: HomeLayout.cardSpacing
            ) {
                ForEach(businessItems) { item in
                    NativeHomeBusinessCard(
                        title: item.title,
                        subtitle: item.subtitle,
                        assetName: item.assetName,
                        accent: item.accent,
                        actionTitle: nil,
                        action: { handle(item.action) }
                    )
                    .accessibilityIdentifier("x5.home.business.\(item.id)")
                }
            }

            NativeHomeBusinessCard(
                title: "Карточки товара",
                subtitle: "Готовые визуалы для маркетплейсов",
                assetName: "HomeCoverProductCards",
                accent: X5Style.blue,
                actionTitle: nil,
                compact: true,
                action: { handle(imageAction("product_cards")) }
            )
            .accessibilityIdentifier("x5.home.business.product_cards")
        }
    }

    private var trendItems: [NativeHomeTrend] {
        [
            NativeHomeTrend(
                id: "strawberry",
                title: "Измена клубнички",
                subtitle: "С бананом • мультсериал",
                assetName: "HomeTrendLiveVideo",
                videoURL: HomeMotionURLs.video("transitions.mp4"),
                action: .liveFruits
            ),
            NativeHomeTrend(
                id: "tokayev",
                title: "С Токаевым",
                subtitle: "AI-пародия • VIP на матче",
                assetName: "HomeTrendPost",
                videoURL: HomeMotionURLs.video("lipsync.mp4"),
                action: .videoGeneration
            ),
            NativeHomeTrend(
                id: "wildberries",
                title: "Карточки WB",
                subtitle: "Добавь свои товары",
                assetName: "HomeTrendNanoBanana",
                videoURL: HomeMotionURLs.video("ai-stylist.mp4"),
                action: imageAction("product_cards")
            ),
            NativeHomeTrend(
                id: "celebrity",
                title: "Со знаменитостью",
                subtitle: "Добавь себя в сцену",
                assetName: "HomeTrendInfluencer",
                videoURL: HomeMotionURLs.video("face-swap.mp4"),
                action: .videoGeneration
            )
        ]
    }

    private var businessItems: [NativeHomeBusiness] {
        [
            NativeHomeBusiness(
                id: "youtube",
                title: "Обложки YouTube",
                subtitle: "Больше кликов",
                assetName: "HomeCoverYoutube",
                accent: .red,
                action: imageAction("youtube_cover")
            ),
            NativeHomeBusiness(
                id: "logo",
                title: "Логотипы",
                subtitle: "Знак для бренда",
                assetName: "HomeUtilityLogo",
                accent: X5Style.blue,
                action: imageAction("logo")
            ),
            NativeHomeBusiness(
                id: "brandbook",
                title: "Брендбук",
                subtitle: "Единый стиль",
                assetName: "HomeUtilityPackaging",
                accent: Color(red: 0.68, green: 0.44, blue: 0.95),
                action: .imageGeneration(ImageGenerationCatalog.custom)
            ),
            NativeHomeBusiness(
                id: "influencer",
                title: "AI-инфлюенсер",
                subtitle: "Персонаж для бренда",
                assetName: "HomeUtilityCustom",
                accent: Color(red: 0.68, green: 0.44, blue: 0.95),
                action: .videoGeneration
            )
        ]
    }

    private func imageAction(_ categoryID: String) -> HomeRoute {
        let categories = Dictionary(
            uniqueKeysWithValues: ImageGenerationCatalog.categories.map { ($0.id, $0) }
        )
        return categories[categoryID].map(HomeRoute.imageGeneration)
            ?? .imageGeneration(ImageGenerationCatalog.custom)
    }

    private func togglePreview(for item: NativeHomeTrend) {
        guard motionPreviewAllowed else {
            handle(item.action)
            return
        }
        activeTrendVideoID = activeTrendVideoID == item.id ? nil : item.id
        X5Feedback.selection()
    }

    private func handle(_ route: HomeRoute) {
        activeTrendVideoID = nil
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
        }
    }

    private var motionPreviewAllowed: Bool {
        !reduceMotion && !lowPowerMode
    }

    private func completePendingSearchRoute() {
        guard let route = pendingSearchRoute else { return }
        pendingSearchRoute = nil
        handle(route)
    }

    @ViewBuilder
    private func sheetDestination(for route: HomeRoute) -> some View {
        switch route {
        case .videoGeneration: VideoGeneratorView()
        case .voiceGeneration: VoiceGeneratorView()
        case .startupChat: StartupChatView()
        case .liveFruits: LiveFruitsView()
        case .imageGeneration, .hub: EmptyView()
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

private struct NativeHomeHero: Identifiable {
    let id: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let assetName: String
    let action: HomeRoute
}

private struct NativeHomeTrend: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let assetName: String
    let videoURL: URL
    let action: HomeRoute
}

private struct NativeHomeBusiness: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let assetName: String
    let accent: Color
    let action: HomeRoute
}

private enum HomeMotionURLs {
    private static let base = "https://afwznqjpshybmqhlewmy.supabase.co/storage/v1/object/public/videos/home"

    static func video(_ filename: String) -> URL {
        URL(string: "\(base)/\(filename)")!
    }
}

private struct NativeHomeBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.016, green: 0.020, blue: 0.045)
            RadialGradient(
                colors: [Color(red: 0.40, green: 0.10, blue: 0.72).opacity(0.42), .clear],
                center: .init(x: -0.10, y: 0.62),
                startRadius: 8,
                endRadius: 340
            )
            RadialGradient(
                colors: [Color(red: 0.04, green: 0.22, blue: 0.38).opacity(0.34), .clear],
                center: .init(x: 0.62, y: 0.04),
                startRadius: 8,
                endRadius: 390
            )
        }
        .ignoresSafeArea()
    }
}

private struct NativeHomeHeroCard: View {
    let slide: NativeHomeHero
    let pageIndex: Int
    let pageCount: Int
    let action: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                Image(slide.assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0.04), Color.black.opacity(0.30), Color.black.opacity(0.88)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text(slide.eyebrow)
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundColor(X5Style.blue)

                    Text(slide.title)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    Text(slide.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)

                    Button(action: action) {
                        Text("Создать")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 38)
                            .background(X5Style.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("x5.home.hero.\(slide.id).create")
                    .accessibilityLabel("\(slide.title.replacingOccurrences(of: "\n", with: " ")). Создать")
                }
                .padding(16)
                .padding(.trailing, 48)

                NativeHomePageDots(active: pageIndex, count: pageCount)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .background(.black)
        .accessibilityElement(children: .contain)
    }
}

private struct NativeHomePromoCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black)
                    .frame(width: 34, height: 34)
                    .background(
                        Color.black.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)

                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.black.opacity(0.56))
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundColor(X5Style.blue)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity)
            .frame(height: HomeLayout.promoHeight)
            .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

private struct NativeHomeTrendCard: View {
    let item: NativeHomeTrend
    let isPlaying: Bool
    let onOpen: () -> Void
    let onPreview: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Button(action: onOpen) {
                ZStack(alignment: .bottomLeading) {
                    Image(item.assetName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: HomeLayout.trendCardSize.width,
                            height: HomeLayout.trendCardSize.height
                        )
                        .clipped()

                    if isPlaying {
                        LoopingVideo(source: .remote(url: item.videoURL), posterAssetName: item.assetName, isActive: true)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }

                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.82)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.65)
                            .allowsTightening(true)
                        Text(item.subtitle)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.74))
                            .lineLimit(2)
                        Text("VIDEO")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(X5Style.blue)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.52), in: Capsule())
                    }
                    .padding(8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Открывает соответствующий инструмент")

            Button(action: onPreview) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("x5.home.trend.\(item.id).preview")
            .accessibilityLabel("Видео: \(item.title)")
            .accessibilityHint(isPlaying ? "Остановить воспроизведение" : "Воспроизвести без звука")
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .frame(width: HomeLayout.trendCardSize.width, height: HomeLayout.trendCardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
        .accessibilityLabel(item.title)
    }
}

private struct NativeHomeInstagramFeatureCard: View {
    let action: () -> Void

    private let cornerRadius: CGFloat = 20

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                cardSurface
                    .frame(height: HomeLayout.businessFeatureHeight)

                Image("HomeInstagramModelCutout")
                    .resizable()
                    .scaledToFit()
                    .frame(
                        width: 205,
                        height: HomeLayout.businessFeatureHeight
                            + HomeLayout.businessFeatureOverflow + 8
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(x: 18, y: 2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(
                height: HomeLayout.businessFeatureHeight
                    + HomeLayout.businessFeatureOverflow
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Оформление Instagram. Стильные посты и сторис для твоего бренда")
        .accessibilityHint("Открывает генератор оформления Instagram")
    }

    private var cardSurface: some View {
        ZStack(alignment: .leading) {
            NativeHomeInstagramBackdrop()

            VStack(alignment: .leading, spacing: 2) {
                Text("Оформление")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.black)

                Text("Instagram")
                    .font(.system(size: 30, weight: .bold))
                    .italic()
                    .foregroundColor(Color(red: 0.48, green: 0.26, blue: 0.80))

                Text("Стильные посты и сторис\nдля твоего бренда")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.black.opacity(0.58))
                    .lineSpacing(1)
                    .padding(.top, 5)

                Text("X5")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 17)
                    .frame(minHeight: 30)
                    .background(X5Style.blue, in: Capsule())
                    .padding(.top, 9)
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 172, maxHeight: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        }
        .shadow(color: Color(red: 0.49, green: 0.23, blue: 0.82).opacity(0.30), radius: 16, y: 8)
    }
}

private struct NativeHomeInstagramBackdrop: View {
    private let lightPanelFraction: CGFloat = 0.42

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [
                        Color(red: 0.29, green: 0.12, blue: 0.47),
                        Color(red: 0.16, green: 0.06, blue: 0.29),
                        Color(red: 0.07, green: 0.03, blue: 0.13)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.76, green: 0.54, blue: 1.00).opacity(0.72),
                                .clear
                            ],
                            center: .center,
                            startRadius: 2,
                            endRadius: 104
                        )
                    )
                    .frame(width: 208, height: 208)
                    .offset(x: proxy.size.width * 0.49, y: -28)

                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [
                            Color(red: 0.99, green: 0.98, blue: 1.00),
                            Color(red: 0.91, green: 0.84, blue: 0.99)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Capsule()
                        .fill(Color(red: 0.57, green: 0.35, blue: 0.86).opacity(0.18))
                        .frame(width: 210, height: 54)
                        .rotationEffect(.degrees(-13))
                        .offset(x: 16, y: 34)
                }
                .frame(width: proxy.size.width * lightPanelFraction)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.13))
                    .frame(width: 82, height: 136)
                    .rotationEffect(.degrees(7))
                    .offset(x: proxy.size.width * 0.66, y: 22)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NativeHomeBusinessCard: View {
    let title: String
    let subtitle: String
    let assetName: String
    let accent: Color
    let actionTitle: String?
    var compact = false
    let action: () -> Void

    private var cardHeight: CGFloat {
        if compact { return HomeLayout.businessWideHeight }
        if actionTitle != nil { return HomeLayout.businessFeatureHeight }
        return HomeLayout.businessTileHeight
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: cardHeight)
                    .clipped()

                LinearGradient(
                    colors: [Color.black.opacity(0.03), Color.black.opacity(0.83)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(compact ? .subheadline.weight(.bold) : .headline.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(subtitle)
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.white.opacity(0.76))
                        .lineLimit(2)
                    if let actionTitle {
                        Text(actionTitle)
                            .font(.caption.weight(.bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 28)
                            .background(accent, in: Capsule())
                            .padding(.top, 4)
                    }
                }
                .padding(11)

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.black)
                    .frame(width: 30, height: 30)
                    .background(accent, in: Circle())
                    .padding(9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
            .frame(maxWidth: .infinity)
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
        .accessibilityHint("Открывает соответствующий инструмент")
    }
}

private struct NativeHomePageDots: View {
    let active: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == active ? .white : .white.opacity(0.42))
                    .frame(width: index == active ? 22 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct HomeSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    let onSelect: (HomeRoute) -> Void

    private var allItems: [HomeSearchItem] {
        var items = [
            HomeSearchItem(title: "Генерация изображений", subtitle: "Креативы, товары и посты", icon: "photo.badge.plus", route: .imageGeneration(ImageGenerationCatalog.custom)),
            HomeSearchItem(title: "Стартап чат", subtitle: "AI-наставник для бизнеса", icon: "sparkles.rectangle.stack", route: .startupChat),
            HomeSearchItem(title: "Генерация видео", subtitle: "AI-ролики для соцсетей", icon: "video.fill", route: .videoGeneration),
            HomeSearchItem(title: "Озвучка", subtitle: "Текст в естественный голос", icon: "waveform", route: .voiceGeneration),
            HomeSearchItem(title: "Живые фрукты", subtitle: "Сценарий и ролик для Reels", icon: "play.tv.fill", route: .liveFruits),
            HomeSearchItem(title: "Hub", subtitle: "Специалисты и задачи", icon: "briefcase.fill", route: .hub)
        ]
        items.append(
            contentsOf: ImageGenerationCatalog.categories.map { category in
                HomeSearchItem(title: category.title, subtitle: category.subtitle, icon: category.icon, route: .imageGeneration(category))
            }
        )
        return items
    }

    private var filteredItems: [HomeSearchItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return allItems }
        return allItems.filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.subtitle.localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredItems) { item in
                Button { onSelect(item.route) } label: {
                    HStack(spacing: 13) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(X5Style.blue)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.body.weight(.semibold)).foregroundColor(.white)
                            Text(item.subtitle).font(.caption).foregroundColor(.white.opacity(0.58))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white.opacity(0.28))
                    }
                    .frame(minHeight: 48)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background { X5Background() }
            .searchable(text: $query, prompt: "Инструмент или формат")
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }.foregroundColor(X5Style.blue)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct HomeSearchItem: Identifiable {
    let title: String
    let subtitle: String
    let icon: String
    let route: HomeRoute

    var id: String { "\(route.id):\(title)" }
}
