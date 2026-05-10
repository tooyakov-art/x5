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
    @ObservedObject private var auth = Auth.shared
    private let loc = LocalizationService.shared

    @State private var bannerIndex: Int = 0
    @State private var openTool: HomeTool?
    @State private var openCaptions: Bool = false
    @State private var showingNotifications: Bool = false

    private var isDeveloper: Bool { Roles.isDeveloper(auth.userEmail) }
    /// Apple-safe live tool IDs — these have working functionality.
    private static let liveToolIDs: Set<String> = ["captions", "academy"]
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
                    sectionHeader(isDeveloper ? "AI Tools" : "Live now")
                    toolGrid
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 40)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.04, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle("X5")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingNotifications = true } label: {
                        Image(systemName: "bell")
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .accessibilityLabel("Notifications")
                }
            }
            .sheet(item: $openTool) { tool in
                ToolDetailView(tool: tool)
            }
            .sheet(isPresented: $openCaptions) {
                NavigationStack { MainView() }
                    .preferredColorScheme(.dark)
            }
            .sheet(isPresented: $showingNotifications) {
                NotificationsView()
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
                    if tool.id == "captions" {
                        openCaptions = true
                    } else if tool.id == "academy" {
                        // Live: deep-link to Courses tab via NotificationCenter.
                        NotificationCenter.default.post(name: .x5SwitchTab, object: nil, userInfo: ["tab": "courses"])
                    } else {
                        openTool = tool
                    }
                } label: {
                    HomeToolCard(tool: tool)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.4)
            .foregroundColor(.white.opacity(0.45))
            .padding(.leading, 4)
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

                if let url = banner.videoURL {
                    LoopingVideo(url: url)
                        .opacity(0.85)
                }

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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [tool.gradientStart, tool.gradientEnd],
                               startPoint: .topLeading, endPoint: .bottomTrailing)

                if let url = tool.videoURL {
                    LoopingVideo(url: url)
                        .opacity(0.78)
                }

                LinearGradient(colors: [Color.black.opacity(0), Color.black.opacity(0.7)],
                               startPoint: .center, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tool.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text(tool.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(12)

                if tool.videoURL == nil {
                    Image(systemName: tool.icon)
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.bottom, 60)
                        .padding(.leading, 12)
                }
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
