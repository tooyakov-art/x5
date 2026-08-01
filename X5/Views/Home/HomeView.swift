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
        }
    }
}

/// The approved 740 x 1600 client mockup is the visual source of truth.
/// Cards reuse its exact artwork while navigation, playback and accessibility stay native.
struct HomeView: View {
    @EnvironmentObject private var loc: LocalizationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeRoute: HomeRoute?
    @State private var openImageCategory: ImageGenerationCategory?
    @State private var showingGeneratedGallery = false
    @State private var showingSearch = false
    @State private var pendingSearchRoute: HomeRoute?
    @State private var activeTrendVideoID: String?
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    compactHeader
                    heroBanner
                        .padding(.top, 0)
                        .offset(y: 0.6)
                    promoCards
                        .padding(.top, 7)
                        .offset(x: 1.2)
                    trendsSection
                        .padding(.top, 0)
                    businessSection
                        .padding(.top, 3.4)
                }
                .padding(.horizontal, 16.65)
                .padding(.top, 42)
                .padding(.bottom, 10)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(.container, edges: .top)
            .scrollIndicators(.hidden)
            .background { HomeApprovedBackground() }
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(
                isPresented: $showingSearch,
                onDismiss: completePendingSearchRoute
            ) {
                HomeSearchSheet { route in
                    pendingSearchRoute = route
                    showingSearch = false
                }
            }
        }
        .onDisappear {
            activeTrendVideoID = nil
        }
        .onChange(of: motionPreviewAllowed) { isAllowed in
            if !isAllowed { activeTrendVideoID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            Text("X five marketing")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .padding(.leading, 2)

            Spacer(minLength: 10)

            HStack(spacing: 0) {
                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 21, weight: .medium))
                        .foregroundColor(X5Style.blue)
                        .frame(width: 52, height: 44)
                }
                .accessibilityLabel("Поиск инструментов")

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 25)
                    .padding(.horizontal, 0.8)
                    .accessibilityHidden(true)

                Button {
                    showingGeneratedGallery = true
                } label: {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(X5Style.blue)
                        .frame(width: 52, height: 44)
                }
                .accessibilityLabel(loc.t("gen_gallery"))
            }
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.075, green: 0.078, blue: 0.10))
                    .frame(height: 40)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    .frame(height: 40)
            )
        }
        .frame(height: 44)
    }

    private var heroBanner: some View {
        Button {
            handle(.imageGeneration(ImageGenerationCatalog.custom))
        } label: {
            ApprovedHomeCrop(rect: HomeApprovedLayout.hero)
                .aspectRatio(HomeApprovedLayout.hero.width / HomeApprovedLayout.hero.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Генерация изображений. Создать")
        .accessibilityHint("Открывает генератор изображений")
    }

    private var promoCards: some View {
        HStack(spacing: 5) {
            ApprovedArtworkButton(
                rect: HomeApprovedLayout.startupPromo,
                cornerRadius: 16,
                accessibilityLabel: "Стартап чат. AI-наставник",
                action: { handle(.startupChat) }
            )
            ApprovedArtworkButton(
                rect: HomeApprovedLayout.hubPromo,
                cornerRadius: 16,
                accessibilityLabel: "Hub. Специалисты и задачи",
                action: { handle(.hub) }
            )
        }
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("Тренды")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Button {
                    handle(.videoGeneration)
                } label: {
                    HStack(spacing: 3) {
                        Text("Еще")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.56))
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Еще")
                .accessibilityHint("Открывает генератор видео")
            }
            .frame(height: 24)

            GeometryReader { proxy in
                let scale = proxy.size.width / HomeApprovedLayout.trendRailWidth

                HStack(spacing: 0) {
                    ForEach(Array(trendItems.enumerated()), id: \.element.id) { index, item in
                        Button {
                            if motionPreviewAllowed {
                                activeTrendVideoID = activeTrendVideoID == item.id ? nil : item.id
                            } else {
                                handle(.videoGeneration)
                            }
                            X5Feedback.selection()
                        } label: {
                            TrendArtworkCard(
                                item: item,
                                isActive: motionPreviewAllowed && activeTrendVideoID == item.id
                            )
                            .frame(
                                width: item.crop.width * scale,
                                height: HomeApprovedLayout.trendRailHeight * scale
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.title). Видео")
                        .accessibilityHint(
                            !motionPreviewAllowed
                                ? "Открывает генератор видео"
                                : activeTrendVideoID == item.id
                                ? "Остановить воспроизведение"
                                : "Воспроизвести без звука"
                        )

                        if index < HomeApprovedLayout.trendGaps.count {
                            Color.clear
                                .frame(width: HomeApprovedLayout.trendGaps[index] * scale)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
            .aspectRatio(
                HomeApprovedLayout.trendRailWidth / HomeApprovedLayout.trendRailHeight,
                contentMode: .fit
            )
        }
    }

    private var businessSection: some View {
        VStack(alignment: .leading, spacing: 5.2) {
            Text("Дизайн для бизнеса")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.leading, 2)

            BusinessArtworkButton(
                rect: HomeApprovedLayout.instagramBanner,
                title: "Оформление Instagram",
                action: { handle(imageAction("insta_pack")) }
            )

            HStack(spacing: 5) {
                BusinessArtworkButton(
                    rect: HomeApprovedLayout.youtube,
                    title: "Обложки YouTube",
                    action: { handle(imageAction("youtube_cover")) }
                )
                BusinessArtworkButton(
                    rect: HomeApprovedLayout.logo,
                    title: "Логотипы",
                    action: { handle(imageAction("logo")) }
                )
            }

            HStack(spacing: 5) {
                BusinessArtworkButton(
                    rect: HomeApprovedLayout.brandbook,
                    title: "Брендбук",
                    action: { handle(.imageGeneration(ImageGenerationCatalog.custom)) }
                )
                BusinessArtworkButton(
                    rect: HomeApprovedLayout.influencer,
                    title: "AI-инфлюенсер",
                    action: { handle(.videoGeneration) }
                )
            }

            BusinessArtworkButton(
                rect: HomeApprovedLayout.productCards,
                title: "Карточки товара",
                action: { handle(imageAction("product_cards")) }
            )
        }
    }

    private var trendItems: [HomeTrendItem] {
        [
            HomeTrendItem(
                id: "strawberry",
                title: "Измена клубнички",
                crop: HomeApprovedLayout.trendStrawberry,
                videoURL: HomeApprovedLayout.videoURL("transitions.mp4")
            ),
            HomeTrendItem(
                id: "tokayev",
                title: "С Токаевым",
                crop: HomeApprovedLayout.trendTokayev,
                videoURL: HomeApprovedLayout.videoURL("lipsync.mp4")
            ),
            HomeTrendItem(
                id: "wildberries",
                title: "Карточки WB",
                crop: HomeApprovedLayout.trendWildberries,
                videoURL: HomeApprovedLayout.videoURL("ai-stylist.mp4")
            ),
            HomeTrendItem(
                id: "celebrity",
                title: "Со знаменитостью",
                crop: HomeApprovedLayout.trendCelebrity,
                videoURL: HomeApprovedLayout.videoURL("face-swap.mp4")
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
        case .videoGeneration:
            VideoGeneratorView()
        case .voiceGeneration:
            VoiceGeneratorView()
        case .startupChat:
            StartupChatView()
        case .liveFruits:
            LiveFruitsView()
        case .imageGeneration, .hub:
            EmptyView()
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

private enum HomeApprovedLayout {
    static let referenceSize = CGSize(width: 740, height: 1600)

    static let hero = CGRect(x: 28, y: 145, width: 684, height: 354)
    static let startupPromo = CGRect(x: 29, y: 510, width: 339, height: 90)
    static let hubPromo = CGRect(x: 376, y: 510, width: 337, height: 90)

    static let trendStrawberry = CGRect(x: 28, y: 649, width: 176, height: 265)
    static let trendTokayev = CGRect(x: 213, y: 649, width: 188, height: 265)
    static let trendWildberries = CGRect(x: 412, y: 649, width: 160, height: 265)
    static let trendCelebrity = CGRect(x: 579, y: 649, width: 133, height: 265)
    static let trendRailWidth: CGFloat = 684
    static let trendRailHeight: CGFloat = 265
    static let trendGaps: [CGFloat] = [9, 11, 7]

    static let instagramBanner = CGRect(x: 28, y: 969, width: 684, height: 204)
    static let youtube = CGRect(x: 28, y: 1181, width: 338, height: 129)
    static let logo = CGRect(x: 374, y: 1181, width: 338, height: 129)
    static let brandbook = CGRect(x: 28, y: 1319, width: 338, height: 120)
    static let influencer = CGRect(x: 374, y: 1319, width: 338, height: 120)
    static let productCards = CGRect(x: 28, y: 1448, width: 684, height: 96)

    private static let videoBase =
        "https://afwznqjpshybmqhlewmy.supabase.co/storage/v1/object/public/videos/home"

    static func videoURL(_ filename: String) -> URL {
        URL(string: "\(videoBase)/\(filename)")!
    }
}

/// Home-only backdrop from the approved black/violet composition.
/// Global X5 screens keep their existing blue theme.
private struct HomeApprovedBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.004, green: 0.006, blue: 0.014)

            RadialGradient(
                colors: [
                    Color(red: 0.28, green: 0.035, blue: 0.58).opacity(0.34),
                    .clear
                ],
                center: .init(x: -0.08, y: 0.66),
                startRadius: 6,
                endRadius: 360
            )

            RadialGradient(
                colors: [
                    Color(red: 0.035, green: 0.16, blue: 0.28).opacity(0.24),
                    .clear
                ],
                center: .init(x: 0.48, y: -0.05),
                startRadius: 8,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

private struct HomeTrendItem: Identifiable {
    let id: String
    let title: String
    let crop: CGRect
    let videoURL: URL
}

private struct ApprovedHomeCrop: View {
    let rect: CGRect

    var body: some View {
        GeometryReader { proxy in
            let widthScale = proxy.size.width / rect.width
            let heightScale = proxy.size.height / rect.height
            let scale = max(widthScale, heightScale)
            let renderedSize = CGSize(
                width: HomeApprovedLayout.referenceSize.width * scale,
                height: HomeApprovedLayout.referenceSize.height * scale
            )
            let visibleSize = CGSize(
                width: rect.width * scale,
                height: rect.height * scale
            )

            Image("HomeApprovedReference")
                .resizable()
                .frame(width: renderedSize.width, height: renderedSize.height)
                .position(
                    x: renderedSize.width / 2
                        - rect.minX * scale
                        + (proxy.size.width - visibleSize.width) / 2,
                    y: renderedSize.height / 2
                        - rect.minY * scale
                        + (proxy.size.height - visibleSize.height) / 2
                )
        }
        .clipped()
        .background(Color.black)
    }
}

private struct ApprovedArtworkButton: View {
    let rect: CGRect
    let cornerRadius: CGFloat
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ApprovedHomeCrop(rect: rect)
                .aspectRatio(rect.width / rect.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct TrendArtworkCard: View {
    let item: HomeTrendItem
    let isActive: Bool

    var body: some View {
        ZStack {
            ApprovedHomeCrop(rect: item.crop)

            if isActive {
                LoopingVideo(
                    source: .remote(url: item.videoURL),
                    posterAssetName: nil,
                    isActive: true
                )
                .transition(.opacity)

                Image(systemName: "pause.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.black.opacity(0.52))
                    .clipShape(Circle())
                    .padding(5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.7)
        )
    }
}

private struct BusinessArtworkButton: View {
    let rect: CGRect
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ApprovedHomeCrop(rect: rect)
                .aspectRatio(rect.width / rect.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.13), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint("Открывает соответствующий инструмент")
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
            HomeSearchItem(title: "Живые фрукты", subtitle: "Сценарий и ролик для Reels", icon: "play.tv.fill", route: .liveFruits),
            HomeSearchItem(title: "Hub", subtitle: "Специалисты и задачи", icon: "briefcase.fill", route: .hub)
        ]
        items.append(
            contentsOf: ImageGenerationCatalog.categories.map { category in
                HomeSearchItem(
                    title: category.title,
                    subtitle: category.subtitle,
                    icon: category.icon,
                    route: .imageGeneration(category)
                )
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
                Button {
                    onSelect(item.route)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(X5Style.blue)
                            .frame(width: 38, height: 38)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                            Text(item.subtitle)
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.58))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
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
                    Button("Готово") { dismiss() }
                        .foregroundColor(X5Style.blue)
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
