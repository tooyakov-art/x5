import SwiftUI

extension Notification.Name {
    /// Posted with `userInfo: ["tab": "profile"]` to programmatically switch tabs from anywhere.
    static let x5SwitchTab = Notification.Name("x5.tab.switch")
}

enum X5AppTab: Int, CaseIterable, Identifiable {
    case home
    case courses
    case chats
    case hub
    case profile

    var id: Int { rawValue }

    var notificationKey: String {
        switch self {
        case .home: return "home"
        case .courses: return "courses"
        case .chats: return "chats"
        case .hub: return "hub"
        case .profile: return "profile"
        }
    }

    var titleKey: String {
        switch self {
        case .home: return "tab_home"
        case .courses: return "tab_courses"
        case .chats: return "tab_chats"
        case .hub: return "tab_hub"
        case .profile: return "tab_profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .courses: return "graduationcap.fill"
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .hub: return "briefcase.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    init?(notificationKey: String) {
        guard let tab = Self.allCases.first(where: { $0.notificationKey == notificationKey }) else {
            return nil
        }
        self = tab
    }
}

/// Five functional app tabs with the compact client-approved visual treatment.
struct AppTabView: View {
    @EnvironmentObject private var loc: LocalizationService
    @StateObject private var deepLinkRouter = AppDeepLinkRouter.shared
    @State private var selectedTab: X5AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label(loc.t(X5AppTab.home.titleKey), systemImage: X5AppTab.home.icon) }
                .tag(X5AppTab.home)
                .toolbar(.hidden, for: .tabBar)
                .onAppear { DiagnosticLogger.log(event: "home_appeared") }

            CoursesView()
                .tabItem { Label(loc.t(X5AppTab.courses.titleKey), systemImage: X5AppTab.courses.icon) }
                .tag(X5AppTab.courses)
                .toolbar(.hidden, for: .tabBar)

            ChatsListView()
                .tabItem { Label(loc.t(X5AppTab.chats.titleKey), systemImage: X5AppTab.chats.icon) }
                .tag(X5AppTab.chats)
                .toolbar(.hidden, for: .tabBar)

            HubView()
                .tabItem { Label(loc.t(X5AppTab.hub.titleKey), systemImage: X5AppTab.hub.icon) }
                .tag(X5AppTab.hub)
                .toolbar(.hidden, for: .tabBar)

            ProfileView(showsDoneButton: false)
                .tabItem { Label(loc.t(X5AppTab.profile.titleKey), systemImage: X5AppTab.profile.icon) }
                .tag(X5AppTab.profile)
                .toolbar(.hidden, for: .tabBar)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            X5BottomTabBar(selectedTab: $selectedTab)
        }
        .onChange(of: selectedTab) { newValue in
            X5Feedback.selection()
            DiagnosticLogger.log(
                event: "tab_switched",
                extra: ["tab": String(newValue.rawValue)]
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .x5SwitchTab)) { note in
            guard
                let key = note.userInfo?["tab"] as? String,
                let tab = X5AppTab(notificationKey: key)
            else { return }
            selectedTab = tab
        }
        .onChange(of: deepLinkRouter.pendingHubTaskID) { taskID in
            if taskID != nil { selectedTab = .hub }
        }
        .onChange(of: deepLinkRouter.pendingChatID) { chatID in
            if chatID != nil { selectedTab = .chats }
        }
        .onAppear {
            if deepLinkRouter.pendingHubTaskID != nil {
                selectedTab = .hub
            } else if deepLinkRouter.pendingChatID != nil {
                selectedTab = .chats
            }
        }
    }
}

private struct X5BottomTabBar: View {
    @EnvironmentObject private var loc: LocalizationService
    @Binding var selectedTab: X5AppTab
    @ScaledMetric(relativeTo: .caption2) private var tabLabelSize: CGFloat = 7.5
    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 16

    /// Icon centers measured from the approved 740 pt reference.
    private let itemCenters: [CGFloat] = [138, 260, 372, 473, 576]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(red: 0.045, green: 0.048, blue: 0.06).opacity(0.98))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.11), lineWidth: 1)
                    )
                    .frame(width: proxy.size.width - 34, height: 34)
                    .position(x: proxy.size.width / 2, y: 27)

                ForEach(X5AppTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: tab.icon)
                                .font(.system(size: tabIconSize, weight: .semibold))
                                .frame(height: 17)

                            Text(loc.t(tab.titleKey))
                                .font(
                                    .system(
                                        size: tabLabelSize,
                                        weight: tab == selectedTab ? .semibold : .medium
                                    )
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundColor(tab == selectedTab ? X5Style.blue : .white.opacity(0.78))
                        .frame(width: 52, height: 34)
                        .frame(minHeight: 44, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("x5.tab.\(tab.notificationKey)")
                    .accessibilityLabel(loc.t(tab.titleKey))
                    .accessibilityAddTraits(tab == selectedTab ? .isSelected : [])
                    .position(
                        x: proxy.size.width * itemCenters[tab.rawValue] / 740,
                        y: 22
                    )
                }
            }
        }
        .frame(height: 44, alignment: .bottom)
        .shadow(color: .black.opacity(0.40), radius: 13, x: 0, y: 4)
        .contentShape(Rectangle())
    }
}
