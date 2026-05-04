import SwiftUI

/// AI generation hub — banner carousel + 14 tool cards.
/// Mirrors the web HomeView. All tools open ToolDetailView (Coming soon),
/// except 'captions' which navigates to the live caption templates feature.
///
/// The tool grid is hidden for non-developer accounts so Apple Review
/// doesn't see "In development — coming soon" placeholders (Guideline 2.1
/// rejects previews of unfinished features). Developer accounts in
/// `Roles.swift` keep the grid for in-app QA.
struct HomeView: View {
    @EnvironmentObject private var auth: Auth

    @State private var bannerIndex: Int = 0
    @State private var openTool: HomeTool?
    @State private var openCaptions: Bool = false
    @State private var showingNotifications: Bool = false

    private var showsTools: Bool { Roles.isDeveloper(auth.userEmail) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    bannerCarousel
                    if showsTools {
                        sectionHeader("AI Tools")
                        toolGrid
                    }
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
                ForEach(Array(HomeContent.banners.enumerated()), id: \.element.id) { idx, banner in
                    HomeBannerCard(banner: banner) {
                        // Same gate as toolGrid — non-developer taps on a
                        // banner are no-ops so Apple Review never lands on
                        // a "Coming soon" page.
                        guard showsTools else { return }
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
                ForEach(0..<HomeContent.banners.count, id: \.self) { i in
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
            ForEach(HomeContent.tools) { tool in
                Button {
                    if tool.id == "captions" {
                        openCaptions = true
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
