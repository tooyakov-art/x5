import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                LoginView()
            } else if needsOnboarding {
                OnboardingView()
            } else {
                AppTabView()
                    .task(id: auth.userId) { await loadProfileIfNeeded() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.2), value: needsOnboarding)
    }

    /// Onboarding required when we have a profile loaded but no user_role yet.
    /// While loading, fall through to AppTabView (avoids flicker).
    private var needsOnboarding: Bool {
        guard let profile = currentUser.profile else { return false }
        return (profile.userRole ?? "").isEmpty
    }

    private func loadProfileIfNeeded() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        if currentUser.profile?.id != uid {
            await currentUser.load(userId: uid, accessToken: token)
        }
    }
}
