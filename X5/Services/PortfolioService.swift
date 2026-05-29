import Foundation

struct PortfolioItem: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    var type: String           // image | video | project
    var title: String?
    var description: String?
    var mediaUrl: String?
    var thumbnailUrl: String?
    var link: String?
    var sortOrder: Int?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, type, title, description, link
        case userId = "user_id"
        case mediaUrl = "media_url"
        case thumbnailUrl = "thumbnail_url"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

struct PortfolioLikeState: Equatable {
    let isLiked: Bool
    let count: Int
}

struct PortfolioComment: Codable, Identifiable, Equatable {
    let id: String
    let itemId: String
    let userId: String
    let userName: String?
    let userAvatar: String?
    let text: String
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, text
        case itemId = "item_id"
        case userId = "user_id"
        case userName = "user_name"
        case userAvatar = "user_avatar"
        case createdAt = "created_at"
    }
}

@MainActor
final class PortfolioService: ObservableObject {
    @Published private(set) var items: [PortfolioItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

    func load(userId: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "sort_order.asc,created_at.desc")
        ]
        guard let reqURL = components.url else { return }
        var request = URLRequest(url: reqURL)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
        items = (try? JSONDecoder().decode([PortfolioItem].self, from: data)) ?? []
    }

    /// Uploads JPEG to Storage, then inserts a portfolio_items row pointing at the public URL.
    func addImage(jpegData: Data, userId: String, title: String?, description: String?, accessToken: String) async -> Bool {
        await addMedia(data: jpegData, type: "image", mime: "image/jpeg", ext: "jpg", userId: userId, title: title, description: description, accessToken: accessToken)
    }

    /// Uploads image/video to Storage, then inserts a portfolio_items row pointing at the public URL.
    func addMedia(data: Data, type: String, mime: String, ext: String, userId: String, title: String?, description: String?, accessToken: String) async -> Bool {
        let cleanType = type == "video" ? "video" : "image"
        let safeExt = ext.isEmpty ? (cleanType == "video" ? "mov" : "jpg") : ext
        let path = "\(userId)/\(Int(Date().timeIntervalSince1970)).\(safeExt)"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/portfolio/\(path)")

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "POST"
        upload.setValue(anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        upload.setValue(mime, forHTTPHeaderField: "Content-Type")
        upload.setValue("3600", forHTTPHeaderField: "Cache-Control")
        upload.setValue("true", forHTTPHeaderField: "x-upsert")
        upload.httpBody = data

        guard let (_, response) = try? await URLSession.shared.data(for: upload),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else {
            self.error = "Upload failed"
            return false
        }

        let publicURL = baseURL.appendingPathComponent("storage/v1/object/public/portfolio/\(path)").absoluteString

        var insert = URLRequest(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"))
        insert.httpMethod = "POST"
        insert.setValue(anonKey, forHTTPHeaderField: "apikey")
        insert.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        insert.setValue("application/json", forHTTPHeaderField: "Content-Type")
        insert.setValue("return=representation", forHTTPHeaderField: "Prefer")

        let body: [String: AnyEncodable] = [
            "user_id": AnyEncodable(userId),
            "type": AnyEncodable(cleanType),
            "title": AnyEncodable(title ?? ""),
            "description": AnyEncodable(description ?? ""),
            "media_url": AnyEncodable(publicURL),
            "thumbnail_url": AnyEncodable(cleanType == "image" ? publicURL : "")
        ]
        insert.httpBody = try? JSONEncoder().encode(body)

        guard let (data, _) = try? await URLSession.shared.data(for: insert),
              let rows = try? JSONDecoder().decode([PortfolioItem].self, from: data),
              let inserted = rows.first
        else {
            self.error = "Insert failed"
            return false
        }
        items.insert(inserted, at: 0)
        return true
    }

    func loadComments(itemId: String, accessToken: String) async -> [PortfolioComment] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_item_comments"), resolvingAgainstBaseURL: false) else { return [] }
        components.queryItems = [
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "created_at.asc")
        ]
        guard let reqURL = components.url else { return [] }
        var request = URLRequest(url: reqURL)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return [] }
        return (try? JSONDecoder().decode([PortfolioComment].self, from: data)) ?? []
    }

    func addComment(itemId: String, userId: String, userName: String?, userAvatar: String?, text: String, accessToken: String) async -> PortfolioComment? {
        var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/portfolio_item_comments"))
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let body: [String: AnyEncodable] = [
            "item_id": AnyEncodable(itemId),
            "user_id": AnyEncodable(userId),
            "user_name": AnyEncodable(userName ?? ""),
            "user_avatar": AnyEncodable(userAvatar ?? ""),
            "text": AnyEncodable(text)
        ]
        request.httpBody = try? JSONEncoder().encode(body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([PortfolioComment].self, from: data)
        else { return nil }
        return rows.first
    }

    func delete(itemId: String, accessToken: String) async {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"), resolvingAgainstBaseURL: false) else { return }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        guard let reqURL = components.url else { return }
        var request = URLRequest(url: reqURL)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            items.removeAll { $0.id == itemId }
        }
    }

    func updateDetails(itemId: String, title: String?, description: String?, accessToken: String) async -> PortfolioItem? {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"), resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        guard let reqURL = components.url else { return nil }

        var request = URLRequest(url: reqURL)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder().encode([
            "title": AnyEncodable(title ?? ""),
            "description": AnyEncodable(description ?? "")
        ])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([PortfolioItem].self, from: data),
              let updated = rows.first
        else { return nil }

        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index] = updated
        }
        return updated
    }

    func replaceMedia(data: Data, type: String, mime: String, ext: String, itemId: String, userId: String, accessToken: String) async -> PortfolioItem? {
        let cleanType = type == "video" ? "video" : "image"
        let safeExt = ext.isEmpty ? (cleanType == "video" ? "mov" : "jpg") : ext
        let path = "\(userId)/\(itemId)-replacement-\(Int(Date().timeIntervalSince1970)).\(safeExt)"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/portfolio/\(path)")

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "POST"
        upload.setValue(anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        upload.setValue(mime, forHTTPHeaderField: "Content-Type")
        upload.setValue("3600", forHTTPHeaderField: "Cache-Control")
        upload.setValue("true", forHTTPHeaderField: "x-upsert")
        upload.httpBody = data

        guard let (_, response) = try? await URLSession.shared.data(for: upload),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else {
            self.error = "Upload failed"
            return nil
        }

        let publicURL = baseURL.appendingPathComponent("storage/v1/object/public/portfolio/\(path)").absoluteString
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"), resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        guard let reqURL = components.url else { return nil }

        var request = URLRequest(url: reqURL)
        request.httpMethod = "PATCH"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try? JSONEncoder().encode([
            "type": AnyEncodable(cleanType),
            "media_url": AnyEncodable(publicURL),
            "thumbnail_url": AnyEncodable(cleanType == "image" ? publicURL : "")
        ])

        guard let (responseData, patchResponse) = try? await URLSession.shared.data(for: request),
              let patchHTTP = patchResponse as? HTTPURLResponse,
              (200..<300).contains(patchHTTP.statusCode),
              let rows = try? JSONDecoder().decode([PortfolioItem].self, from: responseData),
              let updated = rows.first
        else {
            self.error = "Update failed"
            return nil
        }

        if let index = items.firstIndex(where: { $0.id == itemId }) {
            items[index] = updated
        }
        return updated
    }

    func likeState(itemId: String, currentUserId: String, accessToken: String) async -> PortfolioLikeState {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_item_likes"), resolvingAgainstBaseURL: false) else {
            return PortfolioLikeState(isLiked: false, count: 0)
        }
        components.queryItems = [
            URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
            URLQueryItem(name: "select", value: "user_id")
        ]
        guard let reqURL = components.url else {
            return PortfolioLikeState(isLiked: false, count: 0)
        }
        var request = URLRequest(url: reqURL)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([PortfolioLikeRow].self, from: data)
        else {
            return PortfolioLikeState(isLiked: false, count: 0)
        }
        return PortfolioLikeState(
            isLiked: rows.contains { $0.userId == currentUserId },
            count: rows.count
        )
    }

    func setLiked(itemId: String, liked: Bool, currentUserId: String, accessToken: String) async -> Bool {
        if liked {
            var request = URLRequest(url: baseURL.appendingPathComponent("rest/v1/portfolio_item_likes"))
            request.httpMethod = "POST"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
            let body: [String: AnyEncodable] = [
                "item_id": AnyEncodable(itemId),
                "user_id": AnyEncodable(currentUserId)
            ]
            request.httpBody = try? JSONEncoder().encode(body)
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { return false }
            return (200..<300).contains(http.statusCode)
        } else {
            guard var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_item_likes"), resolvingAgainstBaseURL: false) else {
                return false
            }
            components.queryItems = [
                URLQueryItem(name: "item_id", value: "eq.\(itemId)"),
                URLQueryItem(name: "user_id", value: "eq.\(currentUserId)")
            ]
            guard let reqURL = components.url else { return false }
            var request = URLRequest(url: reqURL)
            request.httpMethod = "DELETE"
            request.setValue(anonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            guard let (_, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { return false }
            return (200..<300).contains(http.statusCode)
        }
    }
}

private struct PortfolioLikeRow: Codable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}
