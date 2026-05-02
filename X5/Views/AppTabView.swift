import SwiftUI

extension Notification.Name {
    /// Posted with `userInfo: ["tab": "profile"]` to programmatically switch tabs from anywhere.
    static let x5SwitchTab = Notification.Name("x5.tab.switch")
}

/// Bottom tab layout — matches web x5 mobile MAIN_TAB_VIEWS:
/// Home / Courses / Chats / Hub / Profile.
struct AppTabView: View {
    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            CoursesView()
                .tabItem { Label("CourseUP", systemImage: "graduationcap") }
                .tag(1)

            ChatsListView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(2)

            HubView()
                .tabItem { Label("Hub", systemImage: "briefcase") }
                .tag(3)

            ProfileView(showsDoneButton: false)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(4)
        }
        .tint(.accentColor)
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
    }
}
