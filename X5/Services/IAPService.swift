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

    private enum EntitlementApplyResult: Equatable {
        case applied
        case skipped
        case failed

        var shouldFinishTransaction: Bool {
            switch self {
            case .applied, .skipped: return true
            case .failed: return false
            }
        }

        var isSuccessOrSkipped: Bool {
            switch self {
            case .applied, .skipped: return true
            case .failed: return false
            }
        }
    }

    private enum EntitlementClaimResult: Equatable {
        case claimed
        case alreadyOwned
        case ownedByOther
        case failed

        var belongsToCurrentUser: Bool {
            switch self {
            case .claimed, .alreadyOwned: return true
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
                    let applyResult: EntitlementApplyResult
                    if Self.monthlyProductIDs.contains(transaction.productID) {
                        applyResult = await applySubscriptionEntitlement(
                            transaction: transaction,
                            grantCredits: true,
                            source: "purchase"
                        )
                    } else if transaction.productID == Self.verifiedMonthlyProductID {
                        applyResult = await applyVerifiedEntitlement(transaction: transaction, source: "purchase")
                    } else {
                        applyResult = .skipped
                    }
                    if applyResult.shouldFinishTransaction {
                        await transaction.finish()
                    }
                    return applyResult.isSuccessOrSkipped
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
                    if Self.monthlyProductIDs.contains(transaction.productID) {
                        applyResult = await self?.applySubscriptionEntitlement(
                            transaction: transaction,
                            grantCredits: true,
                            source: "update"
                        ) ?? .failed
                    } else if transaction.productID == Self.verifiedMonthlyProductID {
                        applyResult = await self?.applyVerifiedEntitlement(transaction: transaction, source: "update") ?? .failed
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

    private func syncCurrentEntitlements(source: String) async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.monthlyProductIDs.contains(transaction.productID) {
                _ = await applySubscriptionEntitlement(
                    transaction: transaction,
                    grantCredits: true,
                    source: source
                )
            } else if transaction.productID == Self.verifiedMonthlyProductID {
                _ = await applyVerifiedEntitlement(transaction: transaction, source: source)
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
    /// Credits are granted whenever StoreKit has an active entitlement that is
    /// bound to the current X5 account and Supabase does not already have the
    /// same subscription period recorded. This lets Restore recover a purchase
    /// made while Supabase was paused/offline without double-crediting the same
    /// period on relaunch.
    ///
    /// Guard: only credit when the incoming `expirationDate` is later than the
    /// `subscription_end_date` already stored. A renewal that doesn't extend
    /// the period (re-delivery of a known transaction) is treated as a no-op
    /// for credits. Plan/end-date are still refreshed so isPro stays true.
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
        let tokenIsBoundToCurrentUser: Bool
        if let token = transaction.appAccountToken,
           let buyerId = UUID(uuidString: userId) {
            if token != buyerId {
                DiagnosticLogger.log(event: "iap_subscription_token_mismatch", extra: [
                    "source": source,
                    "product": transaction.productID
                ])
                return .skipped
            }
            tokenIsBoundToCurrentUser = true
        } else {
            tokenIsBoundToCurrentUser = false
        }

        let claimResult = await claimIAPEntitlement(
            transaction: transaction,
            accessToken: accessToken,
            source: source
        )
        switch claimResult {
        case .claimed, .alreadyOwned:
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
        let startIso = ISO8601DateFormatter().string(from: transaction.purchaseDate)

        // Read current credits + last-known subscription_end_date so we can
        // decide whether this transaction is a NEW period (grant credits) or
        // a re-delivery of an already-known one (skip credits).
        var currentCredits = 0
        var storedEndDate: Date? = nil
        guard var getURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false) else {
            return .failed
        }
        getURL.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "credits,subscription_end_date")
        ]
        guard let getReqURL = getURL.url else { return .failed }
        var getReq = URLRequest(url: getReqURL)
        getReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        getReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let profileRow: [String: Any]
        do {
            let (data, response) = try await URLSession.shared.data(for: getReq)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                DiagnosticLogger.log(event: "iap_subscription_profile_fetch_failed", extra: [
                    "source": source,
                    "product": transaction.productID,
                    "status": "\(status)"
                ])
                lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
                return .failed
            }
            guard
                let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                let row = arr.first
            else {
                DiagnosticLogger.log(event: "iap_subscription_profile_missing", extra: [
                    "source": source,
                    "product": transaction.productID
                ])
                lastError = "Profile was not found. Reopen the app and restore purchases."
                return .failed
            }
            profileRow = row
        } catch {
            DiagnosticLogger.log(event: "iap_subscription_profile_fetch_error", extra: [
                "source": source,
                "product": transaction.productID,
                "error": String(error.localizedDescription.prefix(120))
            ])
            lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
            return .failed
        }

        if let c = profileRow["credits"] as? Int { currentCredits = c }
        if let s = profileRow["subscription_end_date"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            storedEndDate = f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
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
        let shouldGrantCredits = grantCredits
            && !alreadyCredited
            && (source == "purchase" || tokenIsBoundToCurrentUser || claimResult.belongsToCurrentUser)
        if shouldGrantCredits {
            body["credits"] = currentCredits + monthlyCredits
        }

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
        patch.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let (data, response) = try await URLSession.shared.data(for: patch)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                DiagnosticLogger.log(event: "iap_subscription_profile_patch_failed", extra: [
                    "source": source,
                    "product": transaction.productID,
                    "status": "\(status)"
                ])
                lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
                return .failed
            }
            if let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], rows.isEmpty {
                DiagnosticLogger.log(event: "iap_subscription_profile_patch_empty", extra: [
                    "source": source,
                    "product": transaction.productID
                ])
                lastError = "Purchase is active, but profile was not updated."
                return .failed
            }
        } catch {
            DiagnosticLogger.log(event: "iap_subscription_profile_patch_error", extra: [
                "source": source,
                "product": transaction.productID,
                "error": String(error.localizedDescription.prefix(120))
            ])
            lastError = "Purchase is active, but credits were not synced. Restore again when the server is online."
            return .failed
        }

        DiagnosticLogger.log(event: "iap_subscription_applied", extra: [
            "source": source,
            "product": transaction.productID,
            "credited": shouldGrantCredits ? "true" : "false",
            "already_credited": alreadyCredited ? "true" : "false"
        ])

        // Notify Subscription so isPro flips immediately without waiting for profile reload
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
            return .skipped
        }

        let claimResult = await claimIAPEntitlement(
            transaction: transaction,
            accessToken: accessToken,
            source: source
        )
        switch claimResult {
        case .claimed, .alreadyOwned:
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
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "p_original_transaction_id": String(transaction.originalID),
            "p_product_id": transaction.productID,
            "p_platform": "ios"
        ])

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

            let raw = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String)
                ?? String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
                ?? ""
            switch raw {
            case "claimed":
                return .claimed
            case "already_owned":
                return .alreadyOwned
            case "owned_by_other":
                DiagnosticLogger.log(event: "iap_claim_owned_by_other", extra: [
                    "source": source,
                    "product": transaction.productID
                ])
                lastError = "This purchase is already linked to another Xfive marketing account."
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
