import Foundation
import StoreKit

@MainActor
final class IAPService: ObservableObject {
    nonisolated static let liteMonthlyProductID = "com.x5studio.app.lite.monthly"
    nonisolated static let proMonthlyProductID = "com.x5studio.app.pro.monthly"
    nonisolated static let maxMonthlyProductID = "com.x5studio.app.max.monthly"
    nonisolated static let verifiedMonthlyProductID = "com.x5studio.app.verified.monthly"
    nonisolated static let monthlyProductID = proMonthlyProductID
    nonisolated static let monthlyProductIDs = [liteMonthlyProductID, proMonthlyProductID, maxMonthlyProductID]
    nonisolated static let allProductIDs = monthlyProductIDs + [verifiedMonthlyProductID]

    nonisolated static let verifiedDisplayPrice = "5000 ₸"

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isPurchasing: Bool = false
    @Published var lastError: String?

    var product: Product? { products[Self.proMonthlyProductID] }

    private var updatesTask: Task<Void, Never>?

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

    init() {
        startTransactionListener()
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            lastError = error.localizedDescription
        }
    }

    func product(id: String) -> Product? {
        products[id]
    }

    /// Initiates purchase flow. On verified transaction, upgrades the local profile and credits.
    /// The current X5 user id is bound to the StoreKit transaction via
    /// `appAccountToken` so subsequent restore / Transaction.updates events
    /// can verify the entitlement belongs to *this* user — preventing the
    /// "log in to a second X5 account on the same Apple ID and inherit Pro
    /// for free" exploit Diaz hit in build 43.
    func purchaseMonthly() async -> Bool {
        await purchase(productID: Self.proMonthlyProductID)
    }

    func purchase(productID: String) async -> Bool {
        guard let product = products[productID] else { return false }
        guard let appUserToken = currentUserToken() else {
            lastError = LocalizationService.shared.t("iap_signin_first")
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase(options: [
                .appAccountToken(appUserToken)
            ])
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    if Self.monthlyProductIDs.contains(transaction.productID) {
                        await applySubscriptionEntitlement(transaction: transaction, grantCredits: true)
                    } else if transaction.productID == Self.verifiedMonthlyProductID {
                        await applyVerifiedEntitlement(transaction: transaction)
                    }
                    await transaction.finish()
                    return true
                } else {
                    lastError = "Purchase failed verification"
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                lastError = "Purchase pending"
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if case .verified(let t) = result, Self.monthlyProductIDs.contains(t.productID) {
                    await applySubscriptionEntitlement(transaction: t, grantCredits: false)
                } else if case .verified(let t) = result, t.productID == Self.verifiedMonthlyProductID {
                    await applyVerifiedEntitlement(transaction: t)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startTransactionListener() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    if Self.monthlyProductIDs.contains(transaction.productID) {
                        await self?.applySubscriptionEntitlement(transaction: transaction, grantCredits: false)
                    } else if transaction.productID == Self.verifiedMonthlyProductID {
                        await self?.applyVerifiedEntitlement(transaction: transaction)
                    }
                    await transaction.finish()
                }
            }
        }
    }

    /// Maps the signed-in X5 user id (Supabase UUID string) into the UUID
    /// type StoreKit's `appAccountToken` requires. Returns nil if no user is
    /// signed in OR the stored id can't be parsed as a UUID — in either case
    /// purchase is blocked rather than silently binding the entitlement to
    /// a wrong account.
    private func currentUserToken() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: "x5.session.user_id") else { return nil }
        return UUID(uuidString: raw)
    }

    /// Marks the user as Pro on the server.
    ///
    /// Credits are granted only from the direct purchase success path. Restore,
    /// relaunch, and StoreKit re-delivery only refresh Pro state.
    ///
    /// Guard: only credit when the incoming `expirationDate` is later than the
    /// `subscription_end_date` already stored. A renewal that doesn't extend
    /// the period (re-delivery of a known transaction) is treated as a no-op
    /// for credits. Plan/end-date are still refreshed so isPro stays true.
    private func applySubscriptionEntitlement(transaction: StoreKit.Transaction, grantCredits: Bool) async {
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = Keychain.string(for: "x5.session.access_token")
        else { return }

        // Cross-account guard: an Apple ID can be shared between several X5
        // accounts on the same device. StoreKit returns the active
        // subscription regardless of which X5 user is currently signed in,
        // so without this gate signing into a second X5 account would
        // silently mark it Pro and credit paid credits for free (build 43 bug).
        //
        // We bind appAccountToken at purchase time to the buyer's user id;
        // here we ignore any transaction whose token doesn't match. Old
        // pre-fix transactions have a nil token — those we let through so
        // legit existing subscribers don't lose their Pro on upgrade.
        if let token = transaction.appAccountToken,
           let buyerId = UUID(uuidString: userId),
           token != buyerId {
            return
        }

        let endDate = transaction.expirationDate
            ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())
            ?? Date().addingTimeInterval(30 * 24 * 3600)
        let endIso = ISO8601DateFormatter().string(from: endDate)
        let startIso = ISO8601DateFormatter().string(from: transaction.purchaseDate)

        // Read current credits + last-known subscription_end_date so we can
        // decide whether this transaction is a NEW period (grant credits) or
        // a re-delivery of an already-known one (skip credits).
        var currentCredits = 0
        var storedEndDate: Date? = nil
        guard var getURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false) else {
            return
        }
        getURL.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "credits,subscription_end_date")
        ]
        guard let getReqURL = getURL.url else { return }
        var getReq = URLRequest(url: getReqURL)
        getReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        getReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: getReq),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let row = arr.first {
            if let c = row["credits"] as? Int { currentCredits = c }
            if let s = row["subscription_end_date"] as? String {
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                storedEndDate = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
            }
        }

        // Treat the transaction as "already credited" if our stored end-date
        // is at or beyond what this transaction reports. A 60-second slack
        // absorbs floating-point rounding from the ISO round-trip.
        let alreadyCredited: Bool = {
            guard let stored = storedEndDate else { return false }
            return stored.timeIntervalSince(endDate) >= -60
        }()

        let monthlyCredits = Self.creditsGranted(for: transaction.productID)
        let subscriptionType = Self.subscriptionType(for: transaction.productID)

        var body: [String: Any] = [
            "plan": "pro",
            "subscription_type": subscriptionType,
            "subscription_date": startIso,
            "subscription_end_date": endIso
        ]
        if grantCredits && !alreadyCredited {
            body["credits"] = currentCredits + monthlyCredits
        }

        guard var patchURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false) else {
            return
        }
        patchURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        guard let patchReqURL = patchURL.url else { return }
        var patch = URLRequest(url: patchReqURL)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        patch.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: patch)

        // Notify Subscription so isPro flips immediately without waiting for profile reload
        NotificationCenter.default.post(name: .x5DidActivatePro, object: nil)
    }

    private func applyVerifiedEntitlement(transaction: StoreKit.Transaction) async {
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = Keychain.string(for: "x5.session.access_token")
        else { return }

        if let token = transaction.appAccountToken,
           let buyerId = UUID(uuidString: userId),
           token != buyerId {
            return
        }

        let endDate = transaction.expirationDate
            ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())
            ?? Date().addingTimeInterval(30 * 24 * 3600)
        let endIso = ISO8601DateFormatter().string(from: endDate)

        guard var patchURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false) else {
            return
        }
        patchURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        guard let patchReqURL = patchURL.url else { return }
        var patch = URLRequest(url: patchReqURL)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        patch.httpBody = try? JSONSerialization.data(withJSONObject: [
            "is_verified": true,
            "verified_until": endIso
        ])
        _ = try? await URLSession.shared.data(for: patch)
    }

    private static func creditsGranted(for productID: String) -> Int {
        switch productID {
        case liteMonthlyProductID: return 1000
        case proMonthlyProductID: return 2000
        case maxMonthlyProductID: return 5000
        default: return 1000
        }
    }

    private static func subscriptionType(for productID: String) -> String {
        switch productID {
        case liteMonthlyProductID: return "lite_monthly"
        case proMonthlyProductID: return "pro_monthly"
        case maxMonthlyProductID: return "max_monthly"
        default: return "lite_monthly"
        }
    }
}

extension Notification.Name {
    static let x5DidActivatePro = Notification.Name("x5.iap.did_activate_pro")
}
