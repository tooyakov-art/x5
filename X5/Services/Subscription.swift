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
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
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
