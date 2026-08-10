import Foundation
import StoreKit

@MainActor
final class IAPService: ObservableObject {
    static let monthlyProductID = "com.x5studio.app.pro.monthly"
    static let verifiedCostCredits: Int = 500

    @Published private(set) var product: Product?
    @Published private(set) var isPurchasing: Bool = false
    @Published var lastError: String?

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
            let products = try await Product.products(for: [Self.monthlyProductID])
            product = products.first { $0.id == Self.monthlyProductID }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func activateVerifiedWithCredits(currentUser: CurrentUser, accessToken: String) async -> Bool {
        guard let profile = currentUser.profile else { return false }
        let credits = profile.credits ?? 0
        guard credits >= Self.verifiedCostCredits else {
            lastError = "Недостаточно кредитов: нужно \(Self.verifiedCostCredits), доступно \(credits)."
            return false
        }
        let endIso = ISO8601DateFormatter().string(
            from: Calendar.current.date(byAdding: .day, value: 30, to: Date())
                ?? Date().addingTimeInterval(30 * 24 * 3600)
        )
        await currentUser.patchMany([
            "is_verified": AnyEncodable(true),
            "verified_until": AnyEncodable(endIso),
            "credits": AnyEncodable(credits - Self.verifiedCostCredits)
        ], accessToken: accessToken)
        return true
    }

    func purchaseMonthly() async -> Bool {
        guard let product else { return false }
        guard let appUserToken = currentUserToken() else {
            lastError = LocalizationService.shared.t("iap_signin_first")
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase(options: [.appAccountToken(appUserToken)])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Purchase failed verification"
                    return false
                }
                let applied = await applyEntitlement(transaction: transaction)
                if applied { await transaction.finish() }
                return applied
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
                if case .verified(let transaction) = result,
                   transaction.productID == Self.monthlyProductID,
                   await applyEntitlement(transaction: transaction) {
                    await transaction.finish()
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startTransactionListener() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update,
                   await self?.applyEntitlement(transaction: transaction) == true {
                    await transaction.finish()
                }
            }
        }
    }

    private func currentUserToken() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: "x5.session.user_id") else { return nil }
        return UUID(uuidString: raw)
    }

    /// The app never grants Pro or credits directly. It sends only the StoreKit
    /// transaction id to the protected backend. The backend fetches and verifies
    /// Apple's signed transaction, then applies the period idempotently.
    private func applyEntitlement(transaction: StoreKit.Transaction) async -> Bool {
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = Keychain.string(for: "x5.session.access_token")
        else { return false }

        if let token = transaction.appAccountToken,
           let buyerId = UUID(uuidString: userId),
           token != buyerId {
            lastError = "This purchase belongs to another X Five account."
            return false
        }

        let url = baseURL.appendingPathComponent("functions/v1/verify-apple-purchase")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "transaction_id": String(transaction.id)
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                lastError = payload?["error"] as? String ?? "Apple purchase verification failed."
                return false
            }
            NotificationCenter.default.post(name: .x5DidActivatePro, object: nil)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }
}

extension Notification.Name {
    static let x5DidActivatePro = Notification.Name("x5.iap.did_activate_pro")
}
