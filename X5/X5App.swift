import SwiftUI
import GoogleSignIn

@main
struct X5App: App {
    @UIApplicationDelegateAdaptor(X5AppDelegate.self) private var appDelegate

    @StateObject private var auth = Auth()
    @StateObject private var history = CaptionHistory()
    @StateObject private var brand = BrandProfile()
    @StateObject private var subscription = Subscription()
    @StateObject private var currentUser = CurrentUser()
    @StateObject private var localization = LocalizationService.shared

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
                .environmentObject(history)
                .environmentObject(brand)
                .environmentObject(subscription)
                .environmentObject(currentUser)
                .environmentObject(localization)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Forward custom-scheme callbacks to the Google Sign-In SDK.
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task(id: auth.isAuthenticated) {
                    if auth.isAuthenticated {
                        PushNotifications.shared.bootstrap()
                        PushNotifications.shared.currentUserDidChange(
                            userId: auth.userId,
                            accessToken: auth.accessToken
                        )
                        // Cold launch already starts in `.active`, so the
                        // scenePhase onChange below would not fire — seed
                        // the rolling promo queue here.
                        PushNotifications.shared.schedulePromoLoop()
                    } else {
                        // Wipe pending promo notifications when the user signs out
                        // so a new account on the same device starts clean.
                        PushNotifications.shared.cancelPromoLoop()
                    }
                }
                .onChange(of: scenePhase) { phase in
                    // Refresh the promo queue on warm foreground — keeps a
                    // rolling hour of 5-minute slots scheduled. Slots whose
                    // fire date already passed are dropped automatically by
                    // iOS when re-added (idempotent: cancel-then-schedule).
                    if phase == .active && auth.isAuthenticated {
                        PushNotifications.shared.schedulePromoLoop()
                    }
                }
        }
    }
}
