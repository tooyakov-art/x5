import Foundation
import StoreKit

enum IAPEntitlementDisposition: Equatable {
    case applied
    case skipped
    case failed

    var shouldFinishTransaction: Bool {
        switch self {
        case .applied, .skipped: return true
        case .failed: return false
        }
    }

    var isPurchaseSuccess: Bool {
        self == .applied
    }
}

enum IAPVerificationRetryPolicy {
    static func shouldRetry(statusCode: Int, retryCount: Int) -> Bool {
        statusCode == 401 && retryCount == 0
    }
}

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
    private let auth: Auth

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

    private enum ServerVerificationResult: Equatable {
        case applied
        case alreadyApplied
        case ownedByOther
        case failed
    }

    private struct ServerVerificationRequest: Encodable {
        let signedTransaction: String

        enum CodingKeys: String, CodingKey {
            case signedTransaction = "signed_transaction"
        }
    }

    private struct ServerVerificationResponse: Decodable {
        let status: String
    }

    init(auth: Auth) {
        self.auth = auth
        startTransactionListener()
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        lastError = nil
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            products = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
            await syncCurrentEntitlements(source: "load")
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
        lastError = nil
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
                    let applyResult: IAPEntitlementDisposition
                    if Self.monthlyProductIDs.contains(transaction.productID) {
                        applyResult = await applySubscriptionEntitlement(
                            transaction: transaction,
                            signedTransaction: verification.jwsRepresentation,
                            source: "purchase"
                        )
                    } else if transaction.productID == Self.verifiedMonthlyProductID {
                        applyResult = await applyVerifiedEntitlement(
                            transaction: transaction,
                            signedTransaction: verification.jwsRepresentation,
                            source: "purchase"
                        )
                    } else {
                        applyResult = .skipped
                    }
                    if applyResult.shouldFinishTransaction {
                        await transaction.finish()
                    }
                    return applyResult.isPurchaseSuccess
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
        lastError = nil
        do {
            try await AppStore.sync()
            await syncCurrentEntitlements(source: "restore")
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func startTransactionListener() {
        updatesTask = Task.detached { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    let applyResult: IAPEntitlementDisposition
                    if Self.monthlyProductIDs.contains(transaction.productID) {
                        applyResult = await self?.applySubscriptionEntitlement(
                            transaction: transaction,
                            signedTransaction: update.jwsRepresentation,
                            source: "update"
                        ) ?? .failed
                    } else if transaction.productID == Self.verifiedMonthlyProductID {
                        applyResult = await self?.applyVerifiedEntitlement(
                            transaction: transaction,
                            signedTransaction: update.jwsRepresentation,
                            source: "update"
                        ) ?? .failed
                    } else {
                        applyResult = .skipped
                    }
                    if applyResult.shouldFinishTransaction {
                        await transaction.finish()
                    }
                }
            }
        }
    }

    func syncCurrentEntitlements(source: String) async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            let applyResult: IAPEntitlementDisposition
            if Self.monthlyProductIDs.contains(transaction.productID) {
                applyResult = await applySubscriptionEntitlement(
                    transaction: transaction,
                    signedTransaction: result.jwsRepresentation,
                    source: source
                )
            } else if transaction.productID == Self.verifiedMonthlyProductID {
                applyResult = await applyVerifiedEntitlement(
                    transaction: transaction,
                    signedTransaction: result.jwsRepresentation,
                    source: source
                )
            } else {
                applyResult = .skipped
            }
            if applyResult.shouldFinishTransaction {
                await transaction.finish()
            }
        }
    }

    /// Maps the signed-in X5 user id (Supabase UUID string) into the UUID
    /// type StoreKit's `appAccountToken` requires. Returns nil if no user is
    /// signed in OR the stored id can't be parsed as a UUID — in either case
    /// purchase is blocked rather than silently binding the entitlement to
    /// a wrong account.
    private func currentUserToken() -> UUID? {
        guard let raw = auth.userId else { return nil }
        return UUID(uuidString: raw)
    }

    /// Applies the verified subscription through the server-side, idempotent
    /// App Store transaction verifier. The client never writes protected
    /// profile fields or sends decoded transaction claims to the server.
    private func applySubscriptionEntitlement(
        transaction: StoreKit.Transaction,
        signedTransaction: String,
        source: String
    ) async -> IAPEntitlementDisposition {
        guard let userId = auth.userId else {
            DiagnosticLogger.log(event: "iap_subscription_missing_session", extra: [
                "source": source,
                "product": transaction.productID
            ])
            lastError = "Sign in again, then restore purchases."
            return .failed
        }

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
        if let token = transaction.appAccountToken {
            guard let buyerId = UUID(uuidString: userId), token == buyerId else {
                DiagnosticLogger.log(event: "iap_subscription_token_mismatch", extra: [
                    "source": source,
                    "product": transaction.productID
                ])
                lastError = accountMismatchError
                return .skipped
            }
        }

        let verificationResult = await verifyAppStoreTransaction(
            signedTransaction: signedTransaction,
            source: source,
            productID: transaction.productID
        )
        switch verificationResult {
        case .applied, .alreadyApplied:
            break
        case .ownedByOther:
            return .skipped
        case .failed:
            return .failed
        }

        // The Edge Function verifies Apple's JWS and is the only writer of
        // plan, balance and subscription dates.
        DiagnosticLogger.log(event: "iap_subscription_applied", extra: [
            "source": source,
            "product": transaction.productID,
            "server_verification": verificationResult == .applied ? "applied" : "already_applied"
        ])
        NotificationCenter.default.post(name: .x5DidActivatePro, object: nil)
        return .applied
    }

    private func applyVerifiedEntitlement(
        transaction: StoreKit.Transaction,
        signedTransaction: String,
        source: String
    ) async -> IAPEntitlementDisposition {
        guard let userId = auth.userId else {
            DiagnosticLogger.log(event: "iap_verified_missing_session", extra: ["source": source])
            lastError = "Sign in again, then restore purchases."
            return .failed
        }

        if let token = transaction.appAccountToken {
            guard let buyerId = UUID(uuidString: userId), token == buyerId else {
                DiagnosticLogger.log(event: "iap_verified_token_mismatch", extra: ["source": source])
                lastError = accountMismatchError
                return .skipped
            }
        }

        let verificationResult = await verifyAppStoreTransaction(
            signedTransaction: signedTransaction,
            source: source,
            productID: transaction.productID
        )
        switch verificationResult {
        case .applied, .alreadyApplied:
            break
        case .ownedByOther:
            return .skipped
        case .failed:
            return .failed
        }

        // Verified state is written by the same idempotent server claim.
        // Do not PATCH protected profile entitlement columns from the client.
        DiagnosticLogger.log(event: "iap_verified_applied", extra: [
            "source": source,
            "server_verification": verificationResult == .applied ? "applied" : "already_applied"
        ])
        return .applied
    }

    private func verifyAppStoreTransaction(
        signedTransaction: String,
        source: String,
        productID: String
    ) async -> ServerVerificationResult {
        let requestBody: Data
        do {
            requestBody = try JSONEncoder().encode(
                ServerVerificationRequest(signedTransaction: signedTransaction)
            )
        } catch {
            DiagnosticLogger.log(event: "iap_verification_request_encoding_failed", extra: [
                "source": source,
                "product": productID
            ])
            lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
            return .failed
        }

        var accessToken = auth.accessToken
        if accessToken == nil {
            accessToken = await auth.freshAccessToken()
        }
        guard var accessToken else {
            lastError = "Sign in again, then restore purchases."
            return .failed
        }

        var retryCount = 0
        while true {
            var request = URLRequest(url: baseURL.appendingPathComponent("functions/v1/verify-app-store-transaction"))
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = requestBody

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = try? JSONDecoder().decode(ServerVerificationResponse.self, from: data).status
                let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? -1

                if IAPVerificationRetryPolicy.shouldRetry(statusCode: httpStatus, retryCount: retryCount) {
                    retryCount += 1
                    guard let refreshedToken = await auth.freshAccessToken() else {
                        lastError = "Sign in again, then restore purchases."
                        return .failed
                    }
                    accessToken = refreshedToken
                    continue
                }

                if status == "owned_by_other" {
                    DiagnosticLogger.log(event: "iap_verification_owned_by_other", extra: [
                        "source": source,
                        "product": productID
                    ])
                    lastError = accountMismatchError
                    return .ownedByOther
                }

                guard (200..<300).contains(httpStatus) else {
                    DiagnosticLogger.log(event: "iap_verification_failed", extra: [
                        "source": source,
                        "product": productID,
                        "status": "\(httpStatus)"
                    ])
                    lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
                    return .failed
                }

                switch status {
                case "applied":
                    return .applied
                case "already_applied":
                    return .alreadyApplied
                default:
                    DiagnosticLogger.log(event: "iap_verification_unknown_response", extra: [
                        "source": source,
                        "product": productID,
                        "response": String((status ?? "").prefix(80))
                    ])
                    lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
                    return .failed
                }
            } catch {
                DiagnosticLogger.log(event: "iap_verification_error", extra: [
                    "source": source,
                    "product": productID,
                    "error": String(error.localizedDescription.prefix(120))
                ])
                lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
                return .failed
            }
        }
    }

    private var accountMismatchError: String {
        "This purchase belongs to another Xfive marketing account. Sign in to that account, then restore purchases."
    }

}

extension Notification.Name {
    static let x5DidActivatePro = Notification.Name("x5.iap.did_activate_pro")
}
