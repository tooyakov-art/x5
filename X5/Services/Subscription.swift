import Foundation

extension Notification.Name {
    static let x5UserDidSignOut = Notification.Name("x5.user.did_sign_out")
    /// Fired when CurrentUser.profile is loaded, created, or patched.
    /// `object` carries the new UserProfile? (nil after sign-out).
    static let x5ProfileDidUpdate = Notification.Name("x5.profile.did_update")
}

@MainActor
final class Subscription: ObservableObject {
    @Published private(set) var isPro: Bool = false

    private let key = "x5.subscription.is_pro"
    private let migrationKey = "x5.subscription.migrated_v14"
    private var observer: NSObjectProtocol?

    private var proObserver: NSObjectProtocol?

    private var profileObserver: NSObjectProtocol?

    init() {
        // Migration: build 12 had a paywall that locally activated Pro on tap.
        // From build 14 onward, Pro state must come from a real receipt.
        // Force a one-time reset for users carrying that stale flag.
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.standard.set(true, forKey: migrationKey)
        }
        isPro = UserDefaults.standard.bool(forKey: key)

        observer = NotificationCenter.default.addObserver(
            forName: .x5UserDidSignOut,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reset() }
        }

        // IAPService posts this after a successful Pro purchase so isPro flips immediately.
        proObserver = NotificationCenter.default.addObserver(
            forName: .x5DidActivatePro,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setPro(true) }
        }

        // CurrentUser posts this whenever profile loads / refreshes / patches.
        // Server `profiles.plan` is the single source of truth — the local
        // UserDefaults cache is reconciled here so SettingsView ("Pro активна")
        // and ProfileView (server `isPro`) never disagree.
        // Payload is only the plan string (narrowed for PII safety).
        profileObserver = NotificationCenter.default.addObserver(
            forName: .x5ProfileDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let plan = note.userInfo?["plan"] as? String
            Task { @MainActor in self?.syncPlan(plan) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let proObserver { NotificationCenter.default.removeObserver(proObserver) }
        if let profileObserver { NotificationCenter.default.removeObserver(profileObserver) }
    }

    /// Reactively syncs from a fresh profile load (e.g. on app launch / refresh).
    /// Treats a nil/missing `plan` as Free so a stale `isPro = true` from the
    /// build-12 paywall or an outdated IAP cache cannot survive a clean
    /// server-side state of "no plan column / null".
    func sync(from profile: UserProfile?) {
        syncPlan(profile?.plan)
    }

    /// String-level entry point used by the notification observer — keeps the
    /// observer payload narrow (no full UserProfile broadcast).
    func syncPlan(_ plan: String?) {
        let normalized = (plan?.isEmpty == false) ? plan : nil
        let pro = normalized == "pro" || normalized == "black"
        if pro != isPro { setPro(pro) }
    }

    func reset() {
        isPro = false
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Stub: real StoreKit purchase wiring will set this via transaction listener.
    /// Currently never called — paywall shows "Coming soon" until IAP is wired.
    func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: key)
    }

    static let monthlyPrice = "$9.99"
    static let monthlyProductID = "com.x5studio.app.pro.monthly"
}
