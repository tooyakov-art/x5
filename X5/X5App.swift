import SwiftUI
import GoogleSignIn

@main
struct X5App: App {
    @UIApplicationDelegateAdaptor(X5AppDelegate.self) private var appDelegate

    // Build 67: explicitly bind to the .shared singletons (build 56/61 baseline
    // was using `Auth()` etc which creates a SECOND instance — different from
    // the `.shared` that ContentView/HomeView etc. read. Two parallel object
    // graphs on iOS 26 SwiftUI looked correlated with the every-button-tap
    // crash report. Aligning everyone on `.shared` eliminates that.
    @StateObject private var auth = Auth.shared
    @StateObject private var history = CaptionHistory.shared
    @StateObject private var brand = BrandProfile.shared
    @StateObject private var subscription = Subscription.shared
    @StateObject private var currentUser = CurrentUser.shared
    @StateObject private var localization = LocalizationService.shared

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Build 67: install crash + lifecycle reporter BEFORE any other init.
        // Sends device info + uncaught exception traces to Supabase
        // `app_diagnostics`. We need this because TestFlight's automatic
        // crash channel is empty for our recent builds (Apple's
        // diagnosticSignatures endpoint returns 404), so we can't tell what
        // is crashing. Self-collected traces fill the gap.
        DiagnosticLogger.bootstrap()
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
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    // Forward custom-scheme callbacks to the Google Sign-In SDK.
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task(id: auth.isAuthenticated) {
                    DiagnosticLogger.log(event: "auth_state",
                                         extra: ["authenticated": auth.isAuthenticated ? "true" : "false"])
                    // Build 67: defensively skip PushNotifications bootstrap on
                    // launch. The async permission request and APNs registration
                    // both have known iOS 26 regressions with strict concurrency;
                    // we re-enable them once we know they are not implicated.
                    if !auth.isAuthenticated {
                        PushNotifications.shared.cancelPromoLoop()
                    }
                }
        }
    }
}
