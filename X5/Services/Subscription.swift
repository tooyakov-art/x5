import Foundation

extension Notification.Name {
    static let x5UserDidSignOut = Notification.Name("x5.user.did_sign_out")
}

@MainActor
final class Subscription: ObservableObject {
    @Published private(set) var isPro: Bool = false

    private let key = "x5.subscription.is_pro"
    private let migrationKey = "x5.subscription.migrated_v14"
    private var observer: NSObjectProtocol?

    private var proObserver: NSObjectProtocol?

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
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let proObserver { NotificationCenter.default.removeObserver(proObserver) }
    }

    /// Reactively syncs from a fresh profile load (e.g. on app launch / refresh).
    func sync(from profile: UserProfile?) {
        guard let plan = profile?.plan else { return }
        let pro = plan == "pro" || plan == "black"
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
