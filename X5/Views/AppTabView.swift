import SwiftUI

/// Bottom tab layout — matches x5 web order: Generate / Courses / Chat / Hub / Profile.
struct AppTabView: View {
    var body: some View {
        TabView {
            GenerateView()
                .tabItem { Label("Generate", systemImage: "wand.and.stars") }

            CoursesView()
                .tabItem { Label("Courses", systemImage: "graduationcap") }

            ChatView()
                .tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }

            HireView()
                .tabItem { Label("Hub", systemImage: "briefcase") }

            ProfileView(showsDoneButton: false)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(.accentColor)
    }
}
