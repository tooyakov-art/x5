import Foundation

enum KaspiCreditPaymentStatus: String, Codable, Sendable {
    case pending
    case confirmed
    case refunded
    case expired
    case cancelled
}

struct KaspiCreditPayment: Codable, Equatable, Sendable {
    let id: UUID
    let productId: String
    let credits: Int
    let amountKzt: Decimal
    let status: KaspiCreditPaymentStatus
    let paymentUrl: URL
    let expiresAt: String
    let confirmedAt: String?
}

enum KaspiCreditCatalog {
    static func serverProductID(for storeProductID: String) -> String? {
        switch storeProductID {
        case "com.x5studio.app.credits.1000": return "x5_credits_1000_v2"
        case "com.x5studio.app.credits.2000": return "x5_credits_2000_v2"
        case "com.x5studio.app.credits.5000": return "x5_credits_5000_v2"
        default: return nil
        }
    }

    static func priceKzt(for storeProductID: String) -> Int? {
        switch storeProductID {
        case "com.x5studio.app.credits.1000": return 1_000
        case "com.x5studio.app.credits.2000": return 2_000
        case "com.x5studio.app.credits.5000": return 5_000
        default: return nil
        }
    }
}

/// This build is for internal TestFlight validation only. Kaspi checkout is
/// intentionally limited to the two agreed X5 beta accounts and must not be
/// submitted to App Review as a replacement for StoreKit digital purchases.
enum KaspiInternalBetaAccess {
    private static let testerUserIDs: Set<String> = [
        "f3eea23f-0aeb-405b-ab35-2c53173b7a8f",
        "eee55a08-18d1-46e3-a303-1411d1bb9333"
    ]

    static func isAllowed(userID: String?) -> Bool {
        guard let userID else { return false }
        return testerUserIDs.contains(userID.lowercased())
    }
}

enum KaspiCreditPaymentError: LocalizedError, Equatable {
    case invalidProduct
    case notConfigured
    case authenticationRequired
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidProduct:
            return "Этот пакет Kaspi не поддерживается."
        case .notConfigured:
            return "Kaspi Business ещё не активирован для X Five."
        case .authenticationRequired:
            return "Войдите в аккаунт для оплаты."
        case .invalidResponse:
            return "Kaspi вернул некорректный ответ."
        case .server:
            return "Не удалось создать оплату Kaspi. Попробуйте позже."
        }
    }
}

struct KaspiCreditPaymentService: Sendable {
    private let session: URLSession
    private let baseURL: URL
    private let anonKey: String

    init(
        session: URLSession = .shared,
        baseURL: URL = X5Config.supabaseBaseURL,
        anonKey: String = X5Config.supabaseAnonKey
    ) {
        self.session = session
        self.baseURL = baseURL
        self.anonKey = anonKey
    }

    func create(
        storeProductID: String,
        accessToken: String
    ) async throws -> KaspiCreditPayment {
        guard let productID = KaspiCreditCatalog.serverProductID(
            for: storeProductID
        ) else {
            throw KaspiCreditPaymentError.invalidProduct
        }
        return try await call(
            rpc: "create_kaspi_credit_payment",
            body: ["p_product_id": productID],
            accessToken: accessToken
        )
    }

    func get(
        paymentID: UUID,
        accessToken: String
    ) async throws -> KaspiCreditPayment {
        try await call(
            rpc: "get_kaspi_credit_payment",
            body: ["p_payment_id": paymentID.uuidString.lowercased()],
            accessToken: accessToken
        )
    }

    private func call(
        rpc: String,
        body: [String: String],
        accessToken: String
    ) async throws -> KaspiCreditPayment {
        guard !accessToken.isEmpty else {
            throw KaspiCreditPaymentError.authenticationRequired
        }

        var request = URLRequest(
            url: baseURL.appendingPathComponent("rest/v1/rpc/\(rpc)")
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(
            "Bearer \(accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KaspiCreditPaymentError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = Self.serverMessage(from: data)
            if message.contains("kaspi_pay_not_configured") {
                throw KaspiCreditPaymentError.notConfigured
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                throw KaspiCreditPaymentError.authenticationRequired
            }
            throw KaspiCreditPaymentError.server(message)
        }

        do {
            return try JSONDecoder().decode(KaspiCreditPayment.self, from: data)
        } catch {
            throw KaspiCreditPaymentError.invalidResponse
        }
    }

    private static func serverMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else { return "unknown_error" }
        return (dictionary["message"] as? String)
            ?? (dictionary["error"] as? String)
            ?? "unknown_error"
    }
}
