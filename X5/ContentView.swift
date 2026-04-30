import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser

    var body: some View {
        Group {
            if auth.isAuthenticated {
                AppTabView()
                    .task(id: auth.userId) { await loadProfileIfNeeded() }
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isAuthenticated)
    }

    private func loadProfileIfNeeded() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        if currentUser.profile?.id != uid {
            await currentUser.load(userId: uid, accessToken: token)
        }
    }
}
