import SwiftUI

/// Standard SwiftUI TabView shell — same dark theme as build 10.
/// 5 tabs: Captions / Chat / Courses / Hire / Profile.
struct AppTabView: View {
    var body: some View {
        TabView {
            MainView()
                .tabItem { Label("Captions", systemImage: "text.alignleft") }

            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

            CoursesView()
                .tabItem { Label("Courses", systemImage: "graduationcap") }

            HireView()
                .tabItem { Label("Hire", systemImage: "person.2") }

            ProfileView(showsDoneButton: false)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(.accentColor)
    }
}
