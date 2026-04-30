import Foundation
import StoreKit

@MainActor
final class IAPService: ObservableObject {
    static let monthlyProductID = "com.x5studio.app.pro.monthly"

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
            product = products.first
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Initiates purchase flow. On verified transaction, upgrades the local profile and credits.
    func purchaseMonthly() async -> Bool {
        guard let product else { return false }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
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

    /// Marks the user as Pro on the server: profiles.plan='pro' + credits += 1000 + subscription_end_date.
    private func applyEntitlement(transaction: StoreKit.Transaction) async {
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = UserDefaults.standard.string(forKey: "x5.session.access_token")
        else { return }

        let endDate = transaction.expirationDate ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        let endIso = ISO8601DateFormatter().string(from: endDate)
        let startIso = ISO8601DateFormatter().string(from: transaction.purchaseDate)

        // First: read current credits
        var currentCredits = 0
        var getURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        getURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)"), URLQueryItem(name: "select", value: "credits")]
        var getReq = URLRequest(url: getURL.url!)
        getReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        getReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: getReq),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
           let row = arr.first,
           let c = row["credits"] as? Int {
            currentCredits = c
        }

        // Patch profile
        var patchURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        patchURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        var patch = URLRequest(url: patchURL.url!)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "plan": "pro",
            "subscription_type": "monthly",
            "subscription_date": startIso,
            "subscription_end_date": endIso,
            "credits": currentCredits + 1000
        ]
        patch.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: patch)
    }
}
