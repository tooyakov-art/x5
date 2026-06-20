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
    private nonisolated static let legacyMonthlyProductIDs = [
        "x5_lite_monthly",
        "x5_pro_monthly",
        "x5_max_monthly"
    ]
    private nonisolated static let recognizedMonthlyProductIDs = monthlyProductIDs + legacyMonthlyProductIDs
    private nonisolated static let recognizedVerifiedProductIDs = [
        verifiedMonthlyProductID,
        "x5_verified_monthly"
    ]
    nonisolated static let allProductIDs = monthlyProductIDs + [verifiedMonthlyProductID]

    nonisolated static let verifiedDisplayPrice = "5000 ₸"

    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isPurchasing: Bool = false
    @Published var lastError: String?

    var product: Product? { products[Self.proMonthlyProductID] }

    private var updatesTask: Task<Void, Never>?

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

    private enum EntitlementApplyResult: Equatable {
        case applied
        case skipped
        case failed

        var shouldFinishTransaction: Bool {
            switch self {
            case .applied: return true
            case .skipped, .failed: return false
            }
        }

    }

    private enum EntitlementClaimResult: Equatable {
        case claimed
        case transferred
        case alreadyOwned
        case ownedByOther
        case failed

        var belongsToCurrentUser: Bool {
            switch self {
            case .claimed, .transferred, .alreadyOwned: return true
            case .ownedByOther, .failed: return false
            }
        }
    }

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
            DiagnosticLogger.log(event: "iap_products_loaded", extra: [
                "ids": loaded.map(\.id).sorted().joined(separator: ",")
            ])
            await syncCurrentEntitlements(source: "load")
        } catch {
            lastError = error.localizedDescription
            DiagnosticLogger.log(event: "iap_products_failed", extra: [
                "error": String(error.localizedDescription.prefix(120))
            ])
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
        DiagnosticLogger.log(event: "iap_purchase_start", extra: ["product": productID])
        guard let product = products[productID] else {
            lastError = "Тариф сейчас недоступен. Перезапусти приложение и попробуй снова."
            DiagnosticLogger.log(event: "iap_purchase_product_missing", extra: ["product": productID])
            return false
        }
        guard let appUserToken = currentUserToken() else {
            lastError = LocalizationService.shared.t("iap_signin_first")
            DiagnosticLogger.log(event: "iap_purchase_missing_user", extra: ["product": productID])
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
                    DiagnosticLogger.log(event: "iap_purchase_verified", extra: [
                        "requested_product": productID,
                        "transaction_product": transaction.productID
                    ])
                    let applyResult: EntitlementApplyResult
                    if Self.recognizedMonthlyProductIDs.contains(transaction.productID) {
                        applyResult = await applySubscriptionEntitlement(
                            transaction: transaction,
                            grantCredits: true,
                            source: "purchase"
                        )
                    } else if Self.recognizedVerifiedProductIDs.contains(transaction.productID) {
                        applyResult = await applyVerifiedEntitlement(transaction: transaction, source: "purchase")
                    } else {
                        handleUnknownProduct(transaction: transaction, requestedProductID: productID, source: "purchase")
                        applyResult = .failed
                    }
                    if applyResult.shouldFinishTransaction {
                        await transaction.finish()
                    }
                    return applyResult == .applied
                } else {
                    lastError = "Purchase failed verification"
                    DiagnosticLogger.log(event: "iap_purchase_unverified", extra: ["product": productID])
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                lastError = "Purchase pending"
                DiagnosticLogger.log(event: "iap_purchase_pending", extra: ["product": productID])
                return false
            @unknown default:
                DiagnosticLogger.log(event: "iap_purchase_unknown_result", extra: ["product": productID])
                return false
            }
        } catch {
            lastError = error.localizedDescription
            DiagnosticLogger.log(event: "iap_purchase_error", extra: [
                "product": productID,
                "error": String(error.localizedDescription.prefix(120))
            ])
            return false
        }
    }

    func restore() async {
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
                    let applyResult: EntitlementApplyResult
                    if Self.recognizedMonthlyProductIDs.contains(transaction.productID) {
                        applyResult = await self?.applySubscriptionEntitlement(
                            transaction: transaction,
                            grantCredits: true,
                            source: "update"
                        ) ?? .failed
                    } else if Self.recognizedVerifiedProductIDs.contains(transaction.productID) {
                        applyResult = await self?.applyVerifiedEntitlement(transaction: transaction, source: "update") ?? .failed
                    } else {
                        await self?.handleUnknownProduct(transaction: transaction, requestedProductID: nil, source: "update")
                        applyResult = .failed
                    }
                    if applyResult.shouldFinishTransaction {
                        await transaction.finish()
                    }
                }
            }
        }
    }

    private func syncCurrentEntitlements(source: String) async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.recognizedMonthlyProductIDs.contains(transaction.productID) {
                _ = await applySubscriptionEntitlement(
                    transaction: transaction,
                    grantCredits: true,
                    source: source
                )
            } else if Self.recognizedVerifiedProductIDs.contains(transaction.productID) {
                _ = await applyVerifiedEntitlement(transaction: transaction, source: source)
            } else {
                handleUnknownProduct(transaction: transaction, requestedProductID: nil, source: source)
            }
        }
    }

    private func handleUnknownProduct(
        transaction: StoreKit.Transaction,
        requestedProductID: String?,
        source: String
    ) {
        DiagnosticLogger.log(event: "iap_unknown_product", extra: [
            "source": source,
            "requested_product": requestedProductID ?? "",
            "transaction_product": transaction.productID,
            "original_id": String(transaction.originalID)
        ])
        if source == "purchase" {
            lastError = "Покупка прошла в Apple, но приложение не распознало тариф. Обнови приложение и нажми «Восстановить покупки»."
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

    /// Claims the StoreKit transaction on the server.
    ///
    /// The Supabase RPC grants credits atomically and marks the original
    /// transaction as credited, so restore/re-delivery can recover missed
    /// purchases without double-crediting the same Apple transaction.
    private func applySubscriptionEntitlement(
        transaction: StoreKit.Transaction,
        grantCredits: Bool,
        source: String
    ) async -> EntitlementApplyResult {
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = Keychain.string(for: "x5.session.access_token")
        else {
            DiagnosticLogger.log(event: "iap_subscription_missing_session", extra: [
                "source": source,
                "product": transaction.productID
            ])
            lastError = "Sign in again, then restore purchases."
            return .failed
        }

        // Apple keeps an active subscription on the Apple ID even when the
        // user deletes their X5 account. A stale appAccountToken is still a
        // useful signal, but the server must decide whether the purchase can
        // be transferred from a deleted account or is owned by a live one.
        if let token = transaction.appAccountToken,
           let buyerId = UUID(uuidString: userId) {
            if token != buyerId {
                DiagnosticLogger.log(event: "iap_subscription_token_mismatch", extra: [
                    "source": source,
                    "product": transaction.productID,
                    "user_id": userId
                ])
            }
        }

        let claimResult = await claimIAPEntitlement(
            transaction: transaction,
            accessToken: accessToken,
            source: source
        )
        let claimStatus: String
        switch claimResult {
        case .claimed:
            claimStatus = "claimed"
        case .transferred:
            claimStatus = "transferred"
        case .alreadyOwned:
            claimStatus = "already_owned"
        case .ownedByOther:
            return .skipped
        case .failed:
            return .failed
        }

        DiagnosticLogger.log(event: "iap_subscription_applied", extra: [
            "source": source,
            "product": transaction.productID,
            "claim": claimStatus,
            "grant_credits": grantCredits ? "true" : "false"
        ])

        // Notify Subscription so isPro flips immediately without waiting for profile reload
        lastError = nil
        NotificationCenter.default.post(name: .x5DidActivatePro, object: nil)
        return .applied
    }

    private func applyVerifiedEntitlement(transaction: StoreKit.Transaction, source: String) async -> EntitlementApplyResult {
        guard
            let userId = UserDefaults.standard.string(forKey: "x5.session.user_id"),
            let accessToken = Keychain.string(for: "x5.session.access_token")
        else {
            DiagnosticLogger.log(event: "iap_verified_missing_session", extra: ["source": source])
            lastError = "Sign in again, then restore purchases."
            return .failed
        }

        if let token = transaction.appAccountToken,
           let buyerId = UUID(uuidString: userId),
           token != buyerId {
            DiagnosticLogger.log(event: "iap_verified_token_mismatch", extra: ["source": source])
        }

        let claimResult = await claimIAPEntitlement(
            transaction: transaction,
            accessToken: accessToken,
            source: source
        )
        switch claimResult {
        case .claimed, .transferred, .alreadyOwned:
            break
        case .ownedByOther:
            return .skipped
        case .failed:
            return .failed
        }

        let endDate = transaction.expirationDate
            ?? Calendar.current.date(byAdding: .month, value: 1, to: Date())
            ?? Date().addingTimeInterval(30 * 24 * 3600)
        let endIso = ISO8601DateFormatter().string(from: endDate)

        guard var patchURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false) else {
            return .failed
        }
        patchURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(userId)")]
        guard let patchReqURL = patchURL.url else { return .failed }
        var patch = URLRequest(url: patchReqURL)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        patch.setValue("return=representation", forHTTPHeaderField: "Prefer")
        patch.httpBody = try? JSONSerialization.data(withJSONObject: [
            "is_verified": true,
            "verified_until": endIso
        ])
        do {
            let (data, response) = try await URLSession.shared.data(for: patch)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                DiagnosticLogger.log(event: "iap_verified_profile_patch_failed", extra: [
                    "source": source,
                    "status": "\(status)"
                ])
                lastError = "Purchase is active, but verified badge was not synced. Restore again when the server is online."
                return .failed
            }
            if let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.isEmpty {
                DiagnosticLogger.log(event: "iap_verified_profile_patch_empty", extra: ["source": source])
                lastError = "Purchase is active, but profile was not updated."
                return .failed
            }
        } catch {
            DiagnosticLogger.log(event: "iap_verified_profile_patch_error", extra: [
                "source": source,
                "error": String(error.localizedDescription.prefix(120))
            ])
            lastError = "Purchase is active, but verified badge was not synced. Restore again when the server is online."
            return .failed
        }

        DiagnosticLogger.log(event: "iap_verified_applied", extra: ["source": source])
        return .applied
    }

    private func claimIAPEntitlement(
        transaction: StoreKit.Transaction,
        accessToken: String,
        source: String
    ) async -> EntitlementClaimResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/rpc/claim_iap_entitlement"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "p_original_transaction_id": String(transaction.originalID),
            "p_product_id": transaction.productID,
            "p_platform": "ios"
        ]
        if let appAccountToken = transaction.appAccountToken?.uuidString {
            payload["p_app_account_token"] = appAccountToken
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                DiagnosticLogger.log(event: "iap_claim_failed", extra: [
                    "source": source,
                    "product": transaction.productID,
                    "status": "\(status)"
                ])
                lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
                return .failed
            }

            let raw = Self.claimStatus(from: data)
            switch raw {
            case "claimed":
                return .claimed
            case "transferred":
                return .transferred
            case "already_owned":
                return .alreadyOwned
            case "owned_by_other":
                DiagnosticLogger.log(event: "iap_claim_owned_by_other", extra: [
                    "source": source,
                    "product": transaction.productID
                ])
                lastError = "Эта покупка уже привязана к другому активному аккаунту X5."
                return .ownedByOther
            default:
                DiagnosticLogger.log(event: "iap_claim_unknown_response", extra: [
                    "source": source,
                    "product": transaction.productID,
                    "response": String(raw.prefix(80))
                ])
                lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
                return .failed
            }
        } catch {
            DiagnosticLogger.log(event: "iap_claim_error", extra: [
                "source": source,
                "product": transaction.productID,
                "error": String(error.localizedDescription.prefix(120))
            ])
            lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
            return .failed
        }
    }

    private nonisolated static func claimStatus(from data: Data) -> String {
        let trimmedText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard
            !data.isEmpty,
            let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else {
            return trimmedText.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }

        if let value = object as? String {
            return value
        }

        if let dict = object as? [String: Any] {
            return (dict["claim_iap_entitlement"] as? String)
                ?? (dict["status"] as? String)
                ?? trimmedText
        }

        if let rows = object as? [[String: Any]],
           let first = rows.first {
            return (first["claim_iap_entitlement"] as? String)
                ?? (first["status"] as? String)
                ?? trimmedText
        }

        if let values = object as? [String],
           let first = values.first {
            return first
        }

        return trimmedText.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

}

extension Notification.Name {
    static let x5DidActivatePro = Notification.Name("x5.iap.did_activate_pro")
}
