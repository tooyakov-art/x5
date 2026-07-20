import Foundation

enum CoursePurchaseStatus: Equatable, Codable {
    case purchased
    case alreadyOwned
    case insufficientCredits
    case priceChanged
    case courseUnavailable
    case profileUnavailable
    case notAuthenticated
    case unknown(String)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "purchased": self = .purchased
        case "already_owned": self = .alreadyOwned
        case "insufficient_credits": self = .insufficientCredits
        case "price_changed": self = .priceChanged
        case "course_unavailable": self = .courseUnavailable
        case "profile_unavailable": self = .profileUnavailable
        case "not_authenticated": self = .notAuthenticated
        default: self = .unknown(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        let value: String
        switch self {
        case .purchased: value = "purchased"
        case .alreadyOwned: value = "already_owned"
        case .insufficientCredits: value = "insufficient_credits"
        case .priceChanged: value = "price_changed"
        case .courseUnavailable: value = "course_unavailable"
        case .profileUnavailable: value = "profile_unavailable"
        case .notAuthenticated: value = "not_authenticated"
        case .unknown(let rawValue): value = rawValue
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct CoursePurchaseResponse: Codable, Equatable {
    let status: CoursePurchaseStatus
    let courseId: String
    let creditsRemaining: Int?
    let coursePrice: Int?
    let chargedAmount: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case courseId = "course_id"
        case creditsRemaining = "credits_remaining"
        case coursePrice = "course_price"
        case chargedAmount = "charged_amount"
    }

    var grantsOwnership: Bool {
        status == .purchased || status == .alreadyOwned
    }

    /// Reconciles the price the user must explicitly confirm on the next
    /// attempt. A price-changed response never charges, so adopting the
    /// server-returned value is safe only after showing a fresh confirmation.
    func reconciledExpectedPrice(currentPrice: Int) -> Int {
        guard status == .priceChanged, let coursePrice else {
            return max(currentPrice, 0)
        }
        return max(coursePrice, 0)
    }
}

enum CoursePurchaseServiceError: LocalizedError, Equatable {
    case invalidCourseId
    case missingAccessToken
    case transport(String)
    case http(statusCode: Int, message: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCourseId:
            return "Некорректный идентификатор курса."
        case .missingAccessToken:
            return "Войдите в аккаунт, чтобы купить курс."
        case .transport:
            return "Не удалось связаться с сервером. Проверьте интернет и повторите попытку."
        case .http(let statusCode, let message):
            let suffix = message.isEmpty ? "" : " \(message)"
            return "Покупка не выполнена (\(statusCode)).\(suffix)"
        case .invalidResponse:
            return "Сервер вернул некорректный ответ. Повторите попытку."
        }
    }
}

@MainActor
final class CoursePurchaseService: ObservableObject {
    @Published private(set) var isPurchasing = false
    @Published private(set) var error: String?

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

    func purchase(
        courseId: String,
        expectedPrice: Int,
        accessToken: String,
        refreshAccessToken: (() async -> String?)? = nil
    ) async throws -> CoursePurchaseResponse {
        let trimmedCourseId = courseId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: trimmedCourseId) != nil else {
            throw record(.invalidCourseId)
        }
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw record(.missingAccessToken)
        }

        isPurchasing = true
        error = nil
        defer { isPurchasing = false }

        let url = baseURL.appendingPathComponent("rest/v1/rpc/purchase_course")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        struct PurchaseRequest: Encodable {
            let pCourseId: String
            let pExpectedPrice: Int

            enum CodingKeys: String, CodingKey {
                case pCourseId = "p_course_id"
                case pExpectedPrice = "p_expected_price"
            }
        }
        request.httpBody = try JSONEncoder().encode(
            PurchaseRequest(
                pCourseId: trimmedCourseId,
                pExpectedPrice: max(expectedPrice, 0)
            )
        )

        var didRetryUnauthorized = false

        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw record(.transport(error.localizedDescription))
            }

            guard let http = response as? HTTPURLResponse else {
                throw record(.invalidResponse)
            }

            if http.statusCode == 401,
               !didRetryUnauthorized,
               let refreshAccessToken {
                // Authentication is rejected before PostgREST invokes the RPC,
                // so this is the only POST failure that is safe to retry. Mark
                // the attempt before awaiting to guarantee a strict one-retry cap.
                didRetryUnauthorized = true
                guard let refreshedToken = await refreshAccessToken()?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !refreshedToken.isEmpty else {
                    throw record(.missingAccessToken)
                }
                request.setValue("Bearer \(refreshedToken)", forHTTPHeaderField: "Authorization")
                continue
            }

            guard (200..<300).contains(http.statusCode) else {
                let message = Self.serverMessage(from: data)
                throw record(.http(statusCode: http.statusCode, message: message))
            }

            do {
                return try JSONDecoder().decode(CoursePurchaseResponse.self, from: data)
            } catch {
                // Some PostgREST configurations wrap a scalar JSON result in a
                // single-element array. Accept both forms without weakening types.
                if let first = try? JSONDecoder().decode([CoursePurchaseResponse].self, from: data).first {
                    return first
                }
                throw record(.invalidResponse)
            }
        }
    }

    @discardableResult
    private func record(_ serviceError: CoursePurchaseServiceError) -> CoursePurchaseServiceError {
        error = serviceError.localizedDescription
        return serviceError
    }

    private static func serverMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable { let message: String? }

        guard let raw = try? JSONDecoder().decode(ErrorEnvelope.self, from: data).message else {
            return ""
        }
        let collapsed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(240))
    }
}
