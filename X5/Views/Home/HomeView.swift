import SwiftUI

/// AI generation hub — banner carousel + tool cards.
///
/// Apple Review build 50 was rejected (Guideline 2.1a) because the Home
/// tab "fetched no contents" on iPad — that was the showsTools/showsBanners
/// gate hiding everything from non-developer accounts and leaving an empty
/// screen.
///
/// Build 53 fix: ALWAYS show a populated Home. Non-developer accounts
/// (incl. Apple's appreview tester) see only the live tools (Captions
/// templates, Academy). Developer accounts still see the full grid with
/// in-development tools for QA.
struct HomeView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var loc: LocalizationService

    @State private var bannerIndex: Int = 0
    @State private var openTool: HomeTool?
    @State private var openCaptions: Bool = false
    @State private var openImageCategory: ImageGenerationCategory?
    @State private var selectedGenerationProvider: ImageGenerationProvider = .gptImageMini
    @State private var showingNotifications: Bool = false
    @State private var showingGeneratedGallery: Bool = false

    private var isDeveloper: Bool { Roles.isDeveloper(auth.userEmail) }
    /// Apple-safe live tool IDs — these have working functionality.
    private static let liveToolIDs: Set<String> = ["photo", "captions", "academy"]
    private var visibleTools: [HomeTool] {
        if isDeveloper { return HomeContent.tools }
        return HomeContent.tools.filter { Self.liveToolIDs.contains($0.id) }
    }
    private var visibleBanners: [HomeBanner] {
        // Banners hidden for everyone — Apple flagged the AI-generated
        // face imagery as objectionable content (Guideline 1.1.1) and
        // banners deep-link to in-development tools anyway. Developer
        // accounts can still QA the tool grid below.
        []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if !visibleBanners.isEmpty {
                        bannerCarousel
                    }
                    sectionHeader(isDeveloper ? loc.t("home_ai_tools") : loc.t("home_live_now"))
                    toolGrid
                    generationHeader
                    generationProviderPicker
                    generationCategoryStrip
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle("X5")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingGeneratedGallery = true } label: {
                        Image(systemName: "photo.stack")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .accessibilityLabel(loc.t("gen_gallery"))

                    Button { showingNotifications = true } label: {
                        Image(systemName: "bell")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .accessibilityLabel(loc.t("notif_title"))
                }
            }
            .sheet(item: $openTool) { tool in
                ToolDetailView(tool: tool)
            }
            .sheet(isPresented: $openCaptions) {
                NavigationStack { MainView() }
                    .preferredColorScheme(.dark)
            }
            .navigationDestination(isPresented: imageCategoryNavigationBinding) {
                if let category = openImageCategory {
                    ImageGeneratorView(category: category, provider: selectedGenerationProvider)
                        .preferredColorScheme(.dark)
                }
            }
            .sheet(isPresented: $showingNotifications) {
                NotificationsView()
            }
            .sheet(isPresented: $showingGeneratedGallery) {
                GeneratedGalleryView()
            }
        }
    }

    private var bannerCarousel: some View {
        VStack(spacing: 8) {
            TabView(selection: $bannerIndex) {
                ForEach(Array(visibleBanners.enumerated()), id: \.element.id) { idx, banner in
                    HomeBannerCard(banner: banner) {
                        if let tool = HomeContent.tools.first(where: { $0.id == banner.toolID }) {
                            openTool = tool
                        }
                    }
                    .tag(idx)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 180)

            HStack(spacing: 6) {
                ForEach(0..<visibleBanners.count, id: \.self) { i in
                    Capsule()
                        .fill(i == bannerIndex ? Color.accentColor : Color.white.opacity(0.18))
                        .frame(width: i == bannerIndex ? 18 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: bannerIndex)
                }
            }
        }
    }

    private var toolGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(visibleTools) { tool in
                Button {
                    DiagnosticLogger.log(event: "home_tool_tap",
                                         extra: ["tool_id": tool.id])
                    if tool.id == "captions" {
                        openCaptions = true
                    } else if tool.id == "photo" {
                        openImageCategory = ImageGenerationCatalog.custom
                    } else if tool.id == "academy" {
                        // Live: deep-link to Courses tab via NotificationCenter.
                        NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "courses"])
                    } else {
                        openTool = tool
                    }
                } label: {
                    HomeToolCard(
                        tool: tool,
                        title: localized("home_tool_\(tool.id)_title", fallback: tool.title),
                        subtitle: localized("home_tool_\(tool.id)_subtitle", fallback: tool.subtitle)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var generationCategoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ImageGenerationCatalog.categories) { category in
                    Button {
                        DiagnosticLogger.log(event: "home_generation_category_tap",
                                             extra: ["category": category.id])
                        openImageCategory = category
                    } label: {
                        GenerationCategoryCard(
                            category: category,
                            title: categoryTitle(category),
                            subtitle: categorySubtitle(category),
                            provider: selectedGenerationProvider
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var generationHeader: some View {
        HStack {
            sectionHeader(loc.t("home_generate"))
            Spacer()
            Button {
                showingGeneratedGallery = true
            } label: {
                Label(loc.t("gen_gallery"), systemImage: "photo.stack")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.18))
        }
        .padding(.trailing, 2)
    }

    private var generationProviderPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(loc.t("gen_model"))

            Menu {
                ForEach(ImageGenerationProvider.allCases) { model in
                    Button {
                        selectedGenerationProvider = model
                    } label: {
                        Label(model.title, systemImage: model == selectedGenerationProvider ? "checkmark" : "cpu")
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "cpu")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedGenerationProvider.title)
                            .font(.system(size: 14, weight: .heavy))
                        Text(selectedGenerationProvider.subtitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.56))
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.52))
                }
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(12)
        .x5ClearGlass(cornerRadius: 16, highlight: 0.10)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundColor(.white.opacity(0.45))
            .padding(.leading, 4)
    }

    private func localized(_ key: String, fallback: String) -> String {
        let value = loc.t(key)
        return value == key ? fallback : value
    }

    private func categoryTitle(_ category: ImageGenerationCategory) -> String {
        localized("gen_category_\(category.id)_title", fallback: category.title)
    }

    private func categorySubtitle(_ category: ImageGenerationCategory) -> String {
        localized("gen_category_\(category.id)_subtitle", fallback: category.subtitle)
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

                // Build 66: LoopingVideo disabled — AVPlayer crash on iOS 26 stable.

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
