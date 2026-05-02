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
    @Published var error: String?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    static func chatId(_ a: String, _ b: String) -> String {
        [a, b].sorted().joined(separator: "_")
    }

    /// Sends `request` with the given Bearer token. If Supabase returns 401, refresh
    /// the session via the global SupabaseClient and retry once with the new token.
    /// Surfaces a human error to `self.error` on any non-2xx response.
    private func sendAuthed(_ request: URLRequest, accessToken: String) async -> (Data, HTTPURLResponse)? {
        do {
            let (data, resp) = try await URLSession.shared.data(for: request)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                // Try to refresh the session via the global SupabaseClient instance.
                if let newToken = await refreshGlobalToken() {
                    var retry = request
                    retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                    let (rdata, rresp) = try await URLSession.shared.data(for: retry)
                    guard let rhttp = rresp as? HTTPURLResponse else { return nil }
                    if !(200..<300).contains(rhttp.statusCode) {
                        let body = String(data: rdata, encoding: .utf8) ?? ""
                        self.error = "Сервер: \(rhttp.statusCode). \(body)"
                        return (rdata, rhttp)
                    }
                    return (rdata, rhttp)
                }
                self.error = "Сессия истекла. Выйди и войди снова."
                return nil
            }
            guard let http = resp as? HTTPURLResponse else { return nil }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                self.error = "Сервер: \(http.statusCode). \(body)"
            }
            return (data, http)
        } catch {
            self.error = "Сеть: \(error.localizedDescription)"
            return nil
        }
    }

    /// Pulls the current refresh token from UserDefaults, calls Supabase /token?grant_type=refresh_token,
    /// stores the new tokens back. Returns the new access token or nil.
    private func refreshGlobalToken() async -> String? {
        guard let refresh = Keychain.string(for: "x5.session.refresh_token") else { return nil }
        var c = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        var req = URLRequest(url: c.url!)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["refresh_token": refresh])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String
        else { return nil }
        Keychain.set(access, for: "x5.session.access_token")
        if let newRefresh = json["refresh_token"] as? String {
            Keychain.set(newRefresh, for: "x5.session.refresh_token")
        }
        return access
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
        guard let (data, http) = await sendAuthed(request, accessToken: accessToken),
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([UserProfile].self, from: data)
        else { return nil }
        return rows.first
    }

    func loadChats(currentUserId: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }
        error = nil
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/chats"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "participants", value: "cs.{\(currentUserId)}"),
            URLQueryItem(name: "order", value: "last_message_at.desc.nullslast")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, http) = await sendAuthed(request, accessToken: accessToken),
              (200..<300).contains(http.statusCode) else { return }
        chats = (try? JSONDecoder().decode([ChatRoom].self, from: data)) ?? []
    }

    func loadMessages(chatId: String, accessToken: String) async -> [ChatMessageRow] {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "chat_id", value: "eq.\(chatId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, http) = await sendAuthed(request, accessToken: accessToken),
              (200..<300).contains(http.statusCode) else { return [] }
        return (try? JSONDecoder().decode([ChatMessageRow].self, from: data)) ?? []
    }

    /// Ensures a chat row exists for the (me, other) pair, optionally tagged with a task.
    /// Returns nil and sets `self.error` on failure (RLS, network, expired token).
    func ensureChat(otherUserId: String, currentUserId: String, taskId: String? = nil, taskTitle: String? = nil, accessToken: String) async -> ChatRoom? {
        error = nil
        let chatId = Self.chatId(currentUserId, otherUserId)

        // Try fetching first
        var get = URLComponents(url: baseURL.appendingPathComponent("rest/v1/chats"), resolvingAgainstBaseURL: false)!
        get.queryItems = [URLQueryItem(name: "id", value: "eq.\(chatId)"), URLQueryItem(name: "select", value: "*")]
        var getReq = URLRequest(url: get.url!)
        getReq.setValue(anonKey, forHTTPHeaderField: "apikey")
        getReq.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (data, http) = await sendAuthed(getReq, accessToken: accessToken),
           (200..<300).contains(http.statusCode),
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

        guard let (data, http) = await sendAuthed(post, accessToken: accessToken),
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([ChatRoom].self, from: data),
              let created = rows.first
        else {
            if error == nil { error = "Не удалось создать чат. Попробуй ещё раз." }
            return nil
        }
        return created
    }

    /// Uploads a binary attachment (image / audio) to Supabase Storage `chat-media` bucket
    /// and returns the public URL. Caller then sends a message with `media_url`.
    /// Requires: bucket `chat-media` to exist (public read) in Supabase Storage.
    func uploadAttachment(chatId: String, data: Data, mime: String, ext: String, accessToken: String) async -> String? {
        let path = "\(chatId)/\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(6)).\(ext)"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/chat-media/\(path)")
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.setValue("3600", forHTTPHeaderField: "Cache-Control")
        req.httpBody = data
        guard let (_, http) = await sendAuthed(req, accessToken: accessToken),
              (200..<300).contains(http.statusCode) else {
            if error == nil { error = "Не удалось загрузить файл. Создай bucket chat-media в Supabase Storage." }
            return nil
        }
        return baseURL.appendingPathComponent("storage/v1/object/public/chat-media/\(path)").absoluteString
    }

    /// Inserts a message of `type` ("image" / "audio" / "file") with the given media URL.
    @discardableResult
    func sendMedia(chatId: String, currentUserId: String, type: String, mediaUrl: String, mime: String, accessToken: String) async -> ChatMessageRow? {
        error = nil
        var post = URLRequest(url: baseURL.appendingPathComponent("rest/v1/messages"))
        post.httpMethod = "POST"
        post.setValue(anonKey, forHTTPHeaderField: "apikey")
        post.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let body: [String: AnyEncodable] = [
            "chat_id": AnyEncodable(chatId),
            "sender_id": AnyEncodable(currentUserId),
            "type": AnyEncodable(type),
            "media_url": AnyEncodable(mediaUrl),
            "media_mime": AnyEncodable(mime)
        ]
        post.httpBody = try? JSONEncoder().encode(body)
        guard let (data, http) = await sendAuthed(post, accessToken: accessToken),
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([ChatMessageRow].self, from: data),
              let inserted = rows.first
        else {
            if error == nil { error = "Не удалось отправить файл." }
            return nil
        }
        // Bump chat preview
        let preview = type == "image" ? "📷 Фото" : type == "audio" ? "🎤 Голосовое" : "📎 Файл"
        var pURL = URLComponents(url: baseURL.appendingPathComponent("rest/v1/chats"), resolvingAgainstBaseURL: false)!
        pURL.queryItems = [URLQueryItem(name: "id", value: "eq.\(chatId)")]
        var patch = URLRequest(url: pURL.url!)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let bumpBody: [String: AnyEncodable] = [
            "last_message": AnyEncodable(preview),
            "last_message_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
        ]
        patch.httpBody = try? JSONEncoder().encode(bumpBody)
        _ = await sendAuthed(patch, accessToken: accessToken)
        return inserted
    }

    /// Sends a text message, then bumps chats.last_message / last_message_at.
    /// Sets `self.error` on failure so the UI can show a real reason instead of a dead spinner.
    @discardableResult
    func sendText(chatId: String, currentUserId: String, text: String, accessToken: String) async -> ChatMessageRow? {
        error = nil
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

        guard let (data, http) = await sendAuthed(post, accessToken: accessToken),
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([ChatMessageRow].self, from: data),
              let inserted = rows.first
        else {
            if error == nil { error = "Не удалось отправить сообщение." }
            return nil
        }

        // Bump chat preview (best effort — message already sent)
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
        _ = await sendAuthed(patch, accessToken: accessToken)

        return inserted
    }
}
