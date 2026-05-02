import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var subscription: Subscription
    @AppStorage("x5.face_id_enabled") private var faceIDEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = false

    var body: some View {
        ZStack {
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

            // Face ID gate — covers everything when locked
            if isLocked {
                AppLockView(isLocked: $isLocked)
                    .transition(.opacity)
            }
        }
        .onAppear {
            if faceIDEnabled && auth.isAuthenticated { isLocked = true }
        }
        .onChange(of: scenePhase) { phase in
            // Re-lock when app goes to background and biometric protection is on.
            if phase == .background && faceIDEnabled && auth.isAuthenticated {
                isLocked = true
            }
        }
    }

    /// Onboarding required when we have a profile loaded but no user_role yet.
    /// While loading, fall through to AppTabView (avoids flicker).
    private var needsOnboarding: Bool {
        guard let profile = currentUser.profile else { return false }
        return (profile.userRole ?? "").isEmpty
    }

    private func loadProfileIfNeeded() async {
        guard let uid = auth.userId, let token = auth.accessToken else { return }
        // Always reload — fixes "paid Pro but stayed Free" if the profile was cached before purchase.
        await currentUser.load(userId: uid, accessToken: token)
        subscription.sync(from: currentUser.profile)
    }
}
