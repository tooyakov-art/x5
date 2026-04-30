import Foundation

struct SocialLinks: Codable, Equatable, Hashable {
    var instagram: String?
    var telegram: String?
    var whatsapp: String?
    var tiktok: String?
    var youtube: String?
    var linkedin: String?
    var facebook: String?
}

struct UserProfile: Codable, Equatable, Identifiable {
    let id: String
    var name: String?
    var nickname: String?
    var email: String?
    var avatar: String?
    var bio: String?
    var services: [String]?
    var plan: String?               // free | pro | black
    var credits: Int?
    var purchasedCourseIds: [String]?
    var purchasedLessonIds: [String]?
    var subscriptionType: String?
    var subscriptionDate: String?
    var subscriptionEndDate: String?
    var socialLinks: SocialLinks?
    var userRole: String?           // specialist | entrepreneur
    var specialistCategory: [String]?
    var showInHub: Bool?
    var isPublic: Bool?
    var signupNumber: Int?
    var language: String?
    var lastSeen: String?

    enum CodingKeys: String, CodingKey {
        case id, name, nickname, email, avatar, bio, services, plan, credits, language
        case purchasedCourseIds = "purchased_course_ids"
        case purchasedLessonIds = "purchased_lesson_ids"
        case subscriptionType = "subscription_type"
        case subscriptionDate = "subscription_date"
        case subscriptionEndDate = "subscription_end_date"
        case socialLinks = "social_links"
        case userRole = "user_role"
        case specialistCategory = "specialist_category"
        case showInHub = "show_in_hub"
        case isPublic = "is_public"
        case signupNumber = "signup_number"
        case lastSeen = "last_seen"
    }

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let n = nickname, !n.isEmpty { return n }
        if let e = email, !e.isEmpty { return e }
        return "User"
    }

    var planLabel: String {
        switch plan ?? "free" {
        case "pro": return "Pro"
        case "black": return "Black"
        default: return "Free"
        }
    }

    var isPro: Bool { plan == "pro" || plan == "black" }
}

@MainActor
final class CurrentUser: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .x5UserDidSignOut, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.profile = nil }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Loads (or refreshes) the current user's profile row using the access token.
    func load(userId: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        do {
            var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "id", value: "eq.\(userId)"),
                URLQueryItem(name: "select", value: "*")
            ]
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "CurrentUser", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
            }
            let rows = try JSONDecoder().decode([UserProfile].self, from: data)
            self.profile = rows.first
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Patches a single field on the profile row.
    func patch<T: Encodable>(_ field: String, value: T, accessToken: String) async {
        guard let id = profile?.id else { return }
        do {
            var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "PATCH"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            let body: [String: AnyEncodable] = [field: AnyEncodable(value)]
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                if let rows = try? JSONDecoder().decode([UserProfile].self, from: data), let row = rows.first {
                    self.profile = row
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Type-erased Encodable wrapper for heterogeneous JSON dicts.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        self._encode = value.encode
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
