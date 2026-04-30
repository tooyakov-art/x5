import SwiftUI

@main
struct X5App: App {
    @UIApplicationDelegateAdaptor(X5AppDelegate.self) private var appDelegate

    @StateObject private var auth = Auth()
    @StateObject private var history = CaptionHistory()
    @StateObject private var brand = BrandProfile()
    @StateObject private var subscription = Subscription()
    @StateObject private var currentUser = CurrentUser()
    @StateObject private var localization = LocalizationService.shared

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
                .task(id: auth.isAuthenticated) {
                    if auth.isAuthenticated {
                        PushNotifications.shared.bootstrap()
                        PushNotifications.shared.currentUserDidChange(
                            userId: auth.userId,
                            accessToken: auth.accessToken
                        )
                    }
                }
        }
    }
}
