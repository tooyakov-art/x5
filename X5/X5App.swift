import SwiftUI
import GoogleSignIn

@main
struct X5App: App {
    @UIApplicationDelegateAdaptor(X5AppDelegate.self) private var appDelegate

    // Build 67: baseline kept — these services don't have `static let shared`
    // in 56/61 codebase (that was a build 63 nuclear refactor we rolled back).
    // The `@StateObject = NewInstance()` pattern is fine since ContentView /
    // HomeView read these via @EnvironmentObject, not via `.shared`.
    @StateObject private var auth: Auth
    @StateObject private var history = CaptionHistory()
    @StateObject private var brand = BrandProfile()
    @StateObject private var subscription = Subscription()
    @StateObject private var currentUser = CurrentUser()
    @StateObject private var localization = LocalizationService.shared
    @StateObject private var iap: IAPService

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Build 67: install crash + lifecycle reporter BEFORE any other init.
        // Sends device info + uncaught exception traces to Supabase
        // `app_diagnostics`. We need this because TestFlight's automatic
        // crash channel is empty for our recent builds (Apple's
        // diagnosticSignatures endpoint returns 404), so we can't tell what
        // is crashing. Self-collected traces fill the gap.
        DiagnosticLogger.bootstrap()

        let auth = Auth()
        _auth = StateObject(wrappedValue: auth)
        _iap = StateObject(wrappedValue: IAPService(auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(history)
                .environmentObject(brand)
                .environmentObject(subscription)
                .environmentObject(currentUser)
                .environmentObject(localization)
                .environmentObject(iap)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Forward custom-scheme callbacks to the Google Sign-In SDK.
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task(id: auth.isAuthenticated) {
                    DiagnosticLogger.log(event: "auth_state",
                                         extra: ["authenticated": auth.isAuthenticated ? "true" : "false"])
                    syncPushRegistrationIfNeeded()
                    await syncStoreKitAndProfile(source: "auth")
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    syncPushRegistrationIfNeeded()
                    // `UserProfile.isPro` evaluates the server expiration against
                    // the current time. Re-evaluate the cached profile every time
                    // the app becomes active so an expired plan cannot remain Pro.
                    subscription.sync(from: currentUser.profile)
                    Task { await syncStoreKitAndProfile(source: "active") }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: .x5DidReconcileStoreRefund
                    )
                ) { _ in
                    Task { await syncStoreKitAndProfile(source: "store_refund") }
                }
        }
    }

    private func syncPushRegistrationIfNeeded() {
        if auth.isAuthenticated {
            PushNotifications.shared.bootstrap()
            PushNotifications.shared.currentUserDidChange(
                userId: auth.userId,
                accessToken: auth.accessToken
            )
        } else {
            PushNotifications.shared.cancelPromoLoop()
        }
    }

    private func syncStoreKitAndProfile(source: String) async {
        guard auth.isAuthenticated else { return }
        await iap.syncRevokedStoreTransactions(source: "\(source)_revoked")
        await iap.retryUnfinishedConsumables(source: "\(source)_unfinished")
        await iap.syncCurrentEntitlements(source: source)

        if let userId = auth.userId,
           let accessToken = await auth.freshAccessToken() {
            await currentUser.load(userId: userId, accessToken: accessToken)
        }
        subscription.sync(from: currentUser.profile)
    }
}
