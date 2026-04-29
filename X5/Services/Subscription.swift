import Foundation

@MainActor
final class Subscription: ObservableObject {
    @Published private(set) var isPro: Bool = false

    private let key = "x5.subscription.is_pro"

    init() {
        isPro = UserDefaults.standard.bool(forKey: key)
    }

    /// Stub: real StoreKit purchase wiring will set this via transaction listener.
    /// For now this just persists a local flag so dev can preview Pro UI.
    func setPro(_ value: Bool) {
        isPro = value
        UserDefaults.standard.set(value, forKey: key)
    }

    static let monthlyPrice = "$9.99"
    static let monthlyProductID = "com.x5studio.app.pro.monthly"
}
