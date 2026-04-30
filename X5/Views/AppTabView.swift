import SwiftUI

/// Bottom tab layout — matches web x5 mobile MAIN_TAB_VIEWS:
/// Home / Courses / Chats / Hub / Profile.
struct AppTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            CoursesView()
                .tabItem { Label("CourseUP", systemImage: "graduationcap") }

            ChatsListView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }

            HubView()
                .tabItem { Label("Hub", systemImage: "briefcase") }

            ProfileView(showsDoneButton: false)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(.accentColor)
    }
}
