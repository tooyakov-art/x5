import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: Auth
    @EnvironmentObject private var currentUser: CurrentUser
    @EnvironmentObject private var subscription: Subscription
    @AppStorage("x5.face_id_enabled") private var faceIDEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = false
    /// Timestamp when the app last went to background — used to re-lock only after a long absence.
    @State private var backgroundedAt: Date?
    /// Lock again only after this many seconds in background. Anything shorter = quick task switch.
    private let relockAfter: TimeInterval = 300 // 5 min
    /// True after first successful Face ID unlock in this app session.
    @State private var hasUnlockedThisSession = false

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
        .onChange(of: isLocked) { locked in
            // Mark unlocked once so we don't re-prompt on every onAppear within this session.
            if !locked { hasUnlockedThisSession = true }
        }
        .onAppear {
            // Cold launch: lock once. After successful unlock the user won't see Face ID
            // again unless the app stays in background for `relockAfter` seconds.
            if faceIDEnabled && auth.isAuthenticated && !hasUnlockedThisSession {
                isLocked = true
            }
        }
        .onChange(of: scenePhase) { phase in
            guard faceIDEnabled, auth.isAuthenticated else { return }
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                // Re-lock only if the app was in background long enough.
                if let t = backgroundedAt, Date().timeIntervalSince(t) >= relockAfter {
                    isLocked = true
                }
                backgroundedAt = nil
            default: break
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
