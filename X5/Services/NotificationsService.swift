import Foundation

struct AppNotification: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let actorId: String?
    let type: String
    let title: String
    let body: String?
    let objectType: String?
    let objectId: String?
    let isRead: Bool
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, body
        case userId = "user_id"
        case actorId = "actor_id"
        case objectType = "object_type"
        case objectId = "object_id"
        case isRead = "is_read"
        case createdAt = "created_at"
    }
}

@MainActor
final class NotificationsService: ObservableObject {
    @Published private(set) var items: [AppNotification] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

    func load(userId: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/notifications"), resolvingAgainstBaseURL: false) else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.desc"),
            URLQueryItem(name: "limit", value: "80")
        ]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                items = []
                return
            }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw NSError(domain: "Notifications", code: http.statusCode)
            }
            items = try JSONDecoder().decode([AppNotification].self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func markRead(_ notification: AppNotification, accessToken: String) async {
        guard !notification.isRead else { return }
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/notifications"), resolvingAgainstBaseURL: false) else {
            return
        }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(notification.id)")]
        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["is_read": true])
        _ = try? await URLSession.shared.data(for: request)
        if let index = items.firstIndex(where: { $0.id == notification.id }) {
            items[index] = AppNotification(
                id: notification.id,
                userId: notification.userId,
                actorId: notification.actorId,
                type: notification.type,
                title: notification.title,
                body: notification.body,
                objectType: notification.objectType,
                objectId: notification.objectId,
                isRead: true,
                createdAt: notification.createdAt
            )
        }
    }
}
