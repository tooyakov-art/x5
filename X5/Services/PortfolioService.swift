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

@MainActor
final class PortfolioService: ObservableObject {
    @Published private(set) var items: [PortfolioItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    func load(userId: String, accessToken: String) async {
        isLoading = true
        defer { isLoading = false }
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "user_id", value: "eq.\(userId)"),
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "order", value: "sort_order.asc,created_at.desc")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return }
        items = (try? JSONDecoder().decode([PortfolioItem].self, from: data)) ?? []
    }

    /// Uploads JPEG to Storage, then inserts a portfolio_items row pointing at the public URL.
    func addImage(jpegData: Data, userId: String, title: String?, description: String?, accessToken: String) async -> Bool {
        let path = "\(userId)/\(Int(Date().timeIntervalSince1970)).jpg"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/portfolio/\(path)")

        var upload = URLRequest(url: uploadURL)
        upload.httpMethod = "POST"
        upload.setValue(anonKey, forHTTPHeaderField: "apikey")
        upload.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        upload.setValue("3600", forHTTPHeaderField: "Cache-Control")
        upload.setValue("true", forHTTPHeaderField: "x-upsert")
        upload.httpBody = jpegData

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
            "type": AnyEncodable("image"),
            "title": AnyEncodable(title ?? ""),
            "description": AnyEncodable(description ?? ""),
            "media_url": AnyEncodable(publicURL),
            "thumbnail_url": AnyEncodable(publicURL)
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

    func delete(itemId: String, accessToken: String) async {
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/portfolio_items"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(itemId)")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "DELETE"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let (_, response) = try? await URLSession.shared.data(for: request),
           let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            items.removeAll { $0.id == itemId }
        }
    }
}
