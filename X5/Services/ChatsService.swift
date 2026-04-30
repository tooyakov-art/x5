import Foundation

// MARK: - Models

struct ChatRoom: Codable, Identifiable, Hashable {
    let id: String
    let participants: [String]
    let taskId: String?
    let taskTitle: String?
    let lastMessage: String?
    let lastMessageAt: String?
    let unread: [String: Int]?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, participants, unread
        case taskId = "task_id"
        case taskTitle = "task_title"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
    }

    func otherParticipantId(currentUser: String) -> String? {
        participants.first { $0 != currentUser }
    }

    func unreadCount(for userId: String) -> Int {
        unread?[userId] ?? 0
    }
}

struct ChatMessageRow: Codable, Identifiable, Hashable {
    let id: String
    let chatId: String
    let senderId: String
    let type: String           // text | image | video | audio
    let content: String?
    let mediaUrl: String?
    let mediaMime: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, content
        case chatId = "chat_id"
        case senderId = "sender_id"
        case mediaUrl = "media_url"
        case mediaMime = "media_mime"
        case createdAt = "created_at"
    }
}

// MARK: - Service

@MainActor
final class ChatsService: ObservableObject {
    @Published private(set) var chats: [ChatRoom] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    static func chatId(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "_")
    }

    /// Load minimal public profile for any user by ID (used in chat header / row).
    func loadPublicProfile(userId: String, accessToken: String) async -> UserProfile? {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/profiles"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let rows = try? JSONDecoder().decode([UserProfile].self, from: data)
        else { return nil }
        return rows.first
    }

    func loadChats(currentUserId: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/chats"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "participants", value: "cs.{\(currentUserId)}"),
            URLQueryItem(name: "order", value: "last_message_at.desc.nullslast")
        ]
        do {
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            chats = (try? JSONDecoder().decode([ChatRoom].self, from: data)) ?? []
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMessages(chatId: String, accessToken: String) async -> [ChatMessageRow] {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "chat_id", value: "eq.\(chatId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        do {
            var request = URLRequest(url: components.url!)
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            return (try? JSONDecoder().decode([ChatMessageRow].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    /// Ensures a chat row exists for the (me, other) pair, optionally tagged with a task.
    func ensureChat(otherUserId: String, currentUserId: String, taskId: String? = nil, taskTitle: String? = nil, accessToken: String) async -> ChatRoom? {
        let chatId = Self.chatId(currentUserId, otherUserId)

        // Try fetching first
        var get = URLComponents(url: baseURL.appendingPathComponent("rest/v1/chats"), resolvingAgainstBaseURL: false)!
        get.queryItems = [URLQueryItem(name: "id", value: "eq.\(chatId)"), URLQueryItem(name: "select", value: "*")]
        var getReq = URLRequest(url: get.url!)
        getReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        getReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (data, _) = try? await URLSession.shared.data(for: getReq),
           let rows = try? JSONDecoder().decode([ChatRoom].self, from: data),
           let existing = rows.first {
            return existing
        }

        // Create
        var post = URLRequest(url: baseURL.appendingPathComponent("rest/v1/chats"))
        post.httpMethod = "POST"
        post.setValue(anonKey, forHTTPHeaderField: "apikey")
        post.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("return=representation", forHTTPHeaderField: "Prefer")

        var body: [String: AnyEncodable] = [
            "id": AnyEncodable(chatId),
            "participants": AnyEncodable([currentUserId, otherUserId])
        ]
        if let taskId { body["task_id"] = AnyEncodable(taskId) }
        if let taskTitle { body["task_title"] = AnyEncodable(taskTitle) }
        post.httpBody = try? JSONEncoder().encode(body)

        if let (data, _) = try? await URLSession.shared.data(for: post),
           let rows = try? JSONDecoder().decode([ChatRoom].self, from: data),
           let created = rows.first {
            return created
        }
        return nil
    }

    /// Sends a text message, then bumps chats.last_message / last_message_at.
    @discardableResult
    func sendText(chatId: String, currentUserId: String, text: String, accessToken: String) async -> ChatMessageRow? {
        var post = URLRequest(url: baseURL.appendingPathComponent("rest/v1/messages"))
        post.httpMethod = "POST"
        post.setValue(anonKey, forHTTPHeaderField: "apikey")
        post.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let body: [String: AnyEncodable] = [
            "chat_id": AnyEncodable(chatId),
            "sender_id": AnyEncodable(currentUserId),
            "type": AnyEncodable("text"),
            "content": AnyEncodable(text)
        ]
        post.httpBody = try? JSONEncoder().encode(body)

        guard let (data, _) = try? await URLSession.shared.data(for: post),
              let rows = try? JSONDecoder().decode([ChatMessageRow].self, from: data),
              let inserted = rows.first
        else { return nil }

        // Bump chat preview
        var patchURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/chats"), resolvingAgainstBaseURL: false)!
        patchURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(chatId)")]
        var patch = URLRequest(url: patchURL.url!)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bumpBody: [String: AnyEncodable] = [
            "last_message": AnyEncodable(text),
            "last_message_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
        ]
        patch.httpBody = try? JSONEncoder().encode(bumpBody)
        _ = try? await URLSession.shared.data(for: patch)

        return inserted
    }
}
