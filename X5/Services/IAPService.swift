import Foundation
import StoreKit

@MainActor
final class IAPService: ObservableObject {
    static let monthlyProductID = "com.x5studio.app.pro.monthly"

    /// Cost in credits to activate the verified badge for 30 days.
    /// Credits are earned via Pro subscription (1000 credits/month).
    static let verifiedCostCredits: Int = 500

    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing: Bool = false
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    init() {
        startTransactionListener()
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [Self.monthlyProductID])
            product = products.first { $0.id == Self.monthlyProductID }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Spends `verifiedCostCredits` from the user's balance and activates the verified badge
    /// for 30 days. Returns false if the user has insufficient credits.
    func activateVerifiedWithCredits(currentUser: CurrentUser, accessToken: String) async -> Bool {
        guard let profile = currentUser.profile else { return false }
        let credits = profile.credits ?? 0
        guard credits >= Self.verifiedCostCredits else {
            lastError = "Не хватает кредитов: нужно \(Self.verifiedCostCredits), у тебя \(credits). Купи Pro — получишь 1000 кредитов."
            return false
        }
        let endIso = ISO8601DateFormatter().string(
            from: Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        )
        await currentUser.patchMany([
            "is_verified": AnyEncodable(true),
            "verified_until": AnyEncodable(endIso),
            "credits": AnyEncodable(credits - Self.verifiedCostCredits)
        ], accessToken: accessToken)
        return true
    }

    /// Initiates purchase flow. On verified transaction, upgrades the local profile and credits.
    /// The current X5 user id is bound to the StoreKit transaction via
    /// `appAccountToken` so subsequent restore / Transaction.updates events
    /// can verify the entitlement belongs to *this* user — preventing the
    /// "log in to a second X5 account on the same Apple ID and inherit Pro
    /// for free" exploit Diaz hit in build 43.
    func purchaseMonthly() async -> Bool {
        guard let product else { return false }
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
                    await applyEntitlement(transaction: transaction)
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
                if case .verified(let t) = result, t.productID == Self.monthlyProductID {
                    await applyEntitlement(transaction: t)
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
                    await self?.applyEntitlement(transaction: transaction)
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

    /// Marks the user as Pro on the server, granting +1000 credits per renewal period.
    ///
    /// Idempotent: this method runs from THREE entry points (purchase success,
    /// `Transaction.updates` listener, manual `restore()`), and StoreKit
    /// sandbox renews monthly subscriptions every ~5 minutes. Without a guard
    /// each restore/relaunch/renewal would credit another +1000 — that's the
    /// bug behind the 6500-credit balance Diaz hit in build 41.
    ///
    /// Guard: only credit when the incoming `expirationDate` is later than the
    /// `subscription_end_date` already stored. A renewal that doesn't extend
    /// the period (re-delivery of a known transaction) is treated as a no-op
    /// for credits. Plan/end-date are still refreshed so isPro stays true.
    private func applyEntitlement(transaction: StoreKit.Transaction) async {
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = Keychain.string(for: "x5.session.access_token")
        else { return }

        // Cross-account guard: an Apple ID can be shared between several X5
        // accounts on the same device. StoreKit returns the active
        // subscription regardless of which X5 user is currently signed in,
        // so without this gate signing into a second X5 account would
        // silently mark it Pro and credit +1000 for free (build 43 bug).
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

        let endDate = transaction.expirationDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        let endIso = ISO8601DateFormatter().string(from: endDate)
        let startIso = ISO8601DateFormatter().string(from: transaction.purchaseDate)

        // Read current credits + last-known subscription_end_date so we can
        // decide whether this transaction is a NEW period (grant credits) or
        // a re-delivery of an already-known one (skip credits).
        var currentCredits = 0
        var storedEndDate: Date? = nil
        var getURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        getURL.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "credits,subscription_end_date")
        ]
        var getReq = URLRequest(url: getURL.url!)
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

        var body: [String: Any] = [
            "plan": "pro",
            "subscription_type": "monthly",
            "subscription_date": startIso,
            "subscription_end_date": endIso
        ]
        if !alreadyCredited {
            body["credits"] = currentCredits + 1000
        }

        var patchURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        patchURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var patch = URLRequest(url: patchURL.url!)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        patch.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: patch)

        // Notify Subscription so isPro flips immediately without waiting for profile reload
        NotificationCenter.default.post(name: .x5DidActivatePro, object: nil)
    }
}

extension Notification.Name {
    static let x5DidActivatePro = Notification.Name("x5.iap.did_activate_pro")
}
