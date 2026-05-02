import Foundation

// MARK: - Models

struct CourseLesson: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let duration: String?
    let order: Int?
    let videoUrl: String?
    let youtubeUrl: String?
    let thumbnailUrl: String?
    let isFreePreview: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, duration, order
        case videoUrl
        case youtubeUrl
        case thumbnailUrl
        case isFreePreview
    }

    var freePreview: Bool { isFreePreview ?? false }

    /// Best playable URL (mp4 / HLS) — falls back to youtube if available.
    var playableURL: URL? {
        if let v = videoUrl, !v.isEmpty, let url = URL(string: v) { return url }
        if let y = youtubeUrl, !y.isEmpty, let url = URL(string: y) { return url }
        return nil
    }
}

struct CourseDay: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let order: Int?
    let lessons: [CourseLesson]
}

struct CourseCategory: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let order: Int?
    let icon: String?
    let days: [CourseDay]
}

struct Course: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let marketingHook: String?
    let coverUrl: String?
    let authorName: String?
    let price: Int?
    let isFree: Bool?
    let isPublic: Bool?
    let courseLanguage: String?
    let averageRating: Double?
    let studentsCount: Int?
    let sortOrder: Int?
    let categoriesRaw: [CourseCategory]?

    var categories: [CourseCategory] { categoriesRaw ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, title, description, price
        case categoriesRaw = "categories"
        case marketingHook = "marketing_hook"
        case coverUrl = "cover_url"
        case authorName = "author_name"
        case isFree = "is_free"
        case isPublic = "is_public"
        case courseLanguage = "course_language"
        case averageRating = "average_rating"
        case studentsCount = "students_count"
        case sortOrder = "sort_order"
    }

    var totalLessons: Int {
        categories.reduce(0) { acc, cat in
            acc + cat.days.reduce(0) { $0 + $1.lessons.count }
        }
    }

    var totalDurationLabel: String {
        let secs = categories
            .flatMap { $0.days }
            .flatMap { $0.lessons }
            .map { Self.parseDurationSeconds($0.duration) }
            .reduce(0, +)
        guard secs > 0 else { return "" }
        let m = secs / 60
        if m >= 60 { return "\(m / 60)h \(m % 60)min" }
        return "\(m) min"
    }

    private static func parseDurationSeconds(_ s: String?) -> Int {
        guard let s, !s.isEmpty else { return 0 }
        let parts = s.split(separator: ":").map { Int($0) ?? 0 }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts.first ?? 0
    }
}

// MARK: - Service

@MainActor
final class CoursesService: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?

    private let baseURL = URL(string: "https://afwznqjpshybmqhlewmy.supabase.co")!
    private let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFmd3pucWpwc2h5Ym1xaGxld215Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAzNTUxMTcsImV4cCI6MjA4NTkzMTExN30.p51iPiMEUSETS9Ot_qkmtA3IcqA23kadgoBLLQDXuL0"

    func loadCourses(includeHidden: Bool = false) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let select = "id,title,description,marketing_hook,cover_url,author_name,price,is_free,is_public,course_language,average_rating,students_count,sort_order,categories"
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/courses"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]
        if !includeHidden {
            items.append(URLQueryItem(name: "is_public", value: "eq.true"))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "CoursesService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to load courses: \(body)"])
            }
            let decoded = try JSONDecoder().decode([Course].self, from: data)
            courses = decoded
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Editor (developer-only)
    // Mutations require an authenticated developer (RLS enforces on the server).

    /// Creates a draft course owned by the caller. Returns the new course on success.
    func createCourse(title: String, accessToken: String) async -> Course? {
        let id = UUID().uuidString
        var post = URLRequest(url: baseURL.appendingPathComponent("rest/v1/courses"))
        post.httpMethod = "POST"
        post.setValue(anonKey, forHTTPHeaderField: "apikey")
        post.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("return=representation", forHTTPHeaderField: "Prefer")
        let body: [String: Any] = [
            "id": id,
            "title": title,
            "is_public": false,
            "is_free": true,
            "price": 0,
            "course_language": "ru",
            "categories": []
        ]
        post.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: post),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONDecoder().decode([Course].self, from: data),
              let row = rows.first else {
            self.error = "Не удалось создать курс. Проверь права в Supabase RLS."
            return nil
        }
        return row
    }

    /// PATCH selected fields on a course row. Pass only the fields you want to change.
    func updateCourse(id: String, fields: [String: Any], accessToken: String) async -> Bool {
        var c = URLComponents(url: baseURL.appendingPathComponent("rest/v1/courses"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var patch = URLRequest(url: c.url!)
        patch.httpMethod = "PATCH"
        patch.setValue(anonKey, forHTTPHeaderField: "apikey")
        patch.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        patch.setValue("application/json", forHTTPHeaderField: "Content-Type")
        patch.httpBody = try? JSONSerialization.data(withJSONObject: fields)
        guard let (_, resp) = try? await URLSession.shared.data(for: patch),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            self.error = "Не удалось сохранить курс."
            return false
        }
        return true
    }

    func deleteCourse(id: String, accessToken: String) async -> Bool {
        var c = URLComponents(url: baseURL.appendingPathComponent("rest/v1/courses"), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "id", value: "eq.\(id)")]
        var del = URLRequest(url: c.url!)
        del.httpMethod = "DELETE"
        del.setValue(anonKey, forHTTPHeaderField: "apikey")
        del.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await URLSession.shared.data(for: del),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            self.error = "Не удалось удалить курс."
            return false
        }
        return true
    }

    /// Uploads `jpegData` to Storage `course-covers` bucket and PATCHes courses.cover_url.
    @discardableResult
    func uploadCover(courseId: String, jpegData: Data, accessToken: String) async -> String? {
        let path = "\(courseId)/\(Int(Date().timeIntervalSince1970)).jpg"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/course-covers/\(path)")
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("3600", forHTTPHeaderField: "Cache-Control")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = jpegData
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode)
        else {
            self.error = "Не удалось загрузить обложку. Проверь bucket course-covers в Supabase Storage."
            return nil
        }
        let publicURL = baseURL.appendingPathComponent("storage/v1/object/public/course-covers/\(path)").absoluteString
        _ = await updateCourse(id: courseId, fields: ["cover_url": publicURL], accessToken: accessToken)
        return publicURL
    }
}
