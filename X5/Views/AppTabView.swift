import SwiftUI

extension Notification.Name {
    /// Posted with `userInfo: ["tab": "profile"]` to programmatically switch tabs from anywhere.
    static let x5SwitchTab = Notification.Name("x5.tab.switch")
}

/// Compact custom navigation matching the approved X5 Home mockup.
/// It avoids the oversized floating system tab treatment on iOS 26.
struct AppTabView: View {
    @StateObject private var deepLinkRouter = AppDeepLinkRouter.shared
    @State private var selectedTab = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    HomeView()
                        .onAppear { DiagnosticLogger.log(event: "home_appeared") }
                        .toolbar(.hidden, for: .tabBar)
                        .tag(0)

                    CoursesView()
                        .toolbar(.hidden, for: .tabBar)
                        .tag(1)

                    ChatsListView()
                        .toolbar(.hidden, for: .tabBar)
                        .tag(2)

                    HubView()
                        .toolbar(.hidden, for: .tabBar)
                        .tag(3)

                    ProfileView(showsDoneButton: false)
                        .toolbar(.hidden, for: .tabBar)
                        .tag(4)
                }
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear
                        .frame(height: 44)
                        .accessibilityHidden(true)
                }

                X5BottomTabBar(selectedTab: $selectedTab)
                    .offset(y: proxy.safeAreaInsets.bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
            .onChange(of: selectedTab) { newValue in
                X5Feedback.selection()
                DiagnosticLogger.log(
                    event: "tab_switched",
                    extra: ["tab": String(newValue)]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .x5SwitchTab)) { note in
                guard let key = note.userInfo?["tab"] as? String else { return }
                switch key {
                case "home": selectedTab = 0
                case "courses": selectedTab = 1
                case "chats": selectedTab = 2
                case "hub": selectedTab = 3
                case "profile": selectedTab = 4
                default: break
                }
            }
            .onChange(of: deepLinkRouter.pendingHubTaskID) { taskID in
                if taskID != nil { selectedTab = 3 }
            }
            .onChange(of: deepLinkRouter.pendingChatID) { chatID in
                if chatID != nil { selectedTab = 2 }
            }
            .onAppear {
                if deepLinkRouter.pendingHubTaskID != nil {
                    selectedTab = 3
                } else if deepLinkRouter.pendingChatID != nil {
                    selectedTab = 2
                }
            }
    }
}

private struct X5BottomTabBar: View {
    @EnvironmentObject private var loc: LocalizationService
    @Binding var selectedTab: Int
    @ScaledMetric(relativeTo: .caption2) private var tabLabelSize: CGFloat = 7.5
    @ScaledMetric(relativeTo: .body) private var tabIconSize: CGFloat = 16

    /// Icon centers measured from the approved 740 pt reference.
    private let itemCenters: [CGFloat] = [138, 260, 372, 473, 576]

    private let items: [X5BottomTabItem] = [
        X5BottomTabItem(titleKey: "tab_home", icon: "house.fill"),
        X5BottomTabItem(titleKey: "tab_courses", icon: "graduationcap.fill"),
        X5BottomTabItem(titleKey: "tab_chats", icon: "bubble.left.and.bubble.right.fill"),
        X5BottomTabItem(titleKey: "tab_hub", icon: "briefcase.fill"),
        X5BottomTabItem(titleKey: "tab_profile", icon: "person.crop.circle.fill")
    ]

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

                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Button {
                        selectedTab = index
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon)
                                .font(.system(size: tabIconSize, weight: .semibold))
                                .frame(height: 17)

                            Text(loc.t(item.titleKey))
                                .font(.system(size: tabLabelSize, weight: index == selectedTab ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundColor(index == selectedTab ? X5Style.blue : .white.opacity(0.78))
                        .frame(width: 52, height: 34)
                        .frame(minHeight: 44, alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(loc.t(item.titleKey))
                    .accessibilityAddTraits(index == selectedTab ? .isSelected : [])
                    .position(
                        x: proxy.size.width * itemCenters[index] / 740,
                        y: 22
                    )
                }
            }
        }
        .frame(height: 44, alignment: .bottom)
        .shadow(color: .black.opacity(0.40), radius: 13, x: 0, y: 4)
        .contentShape(Rectangle())
        .ignoresSafeArea(.container, edges: .bottom)
    }
}

private struct X5BottomTabItem {
    let titleKey: String
    let icon: String
}
