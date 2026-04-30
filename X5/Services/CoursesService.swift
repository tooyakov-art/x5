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

    func loadCourses() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let select = "id,title,description,marketing_hook,cover_url,author_name,price,is_free,is_public,course_language,average_rating,students_count,sort_order,categories"
        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/courses"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: select),
            URLQueryItem(name: "is_public", value: "eq.true"),
            URLQueryItem(name: "order", value: "sort_order.asc")
        ]

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
}
