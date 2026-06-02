import Foundation

// MARK: - Models

struct CourseLesson: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let duration: String?
    let order: Int?
    let price: Int?
    let videoUrl: String?
    let youtubeUrl: String?
    let thumbnailUrl: String?
    let isFreePreview: Bool?
    let sellSeparately: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, duration, order, price
        case videoUrl
        case youtubeUrl
        case thumbnailUrl
        case isFreePreview
        case sellSeparately
    }

    var freePreview: Bool { isFreePreview ?? false }

    /// Best playable URL (mp4 / HLS) — falls back to youtube if available.
    /// Validates scheme to https/http only — drops javascript:, data:, file: etc.
    var playableURL: URL? {
        let safe: (String?) -> URL? = { raw in
            guard let s = raw, !s.isEmpty, let url = URL(string: s),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http"
            else { return nil }
            return url
        }
        return safe(videoUrl) ?? safe(youtubeUrl)
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

struct CourseSubmission: Codable, Identifiable, Hashable {
    let id: String
    let authorId: String?
    let authorEmail: String?
    let authorName: String?
    let contact: String?
    let title: String
    let description: String?
    let videoUrl: String?
    let status: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, contact, status
        case authorId = "author_id"
        case authorEmail = "author_email"
        case authorName = "author_name"
        case videoUrl = "video_url"
        case createdAt = "created_at"
    }
}

// MARK: - Service

@MainActor
final class CoursesService: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var submissions: [CourseSubmission] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingSubmissions: Bool = false
    @Published private(set) var error: String?

    private var baseURL: URL { X5Config.supabaseBaseURL }
    private var anonKey: String { X5Config.supabaseAnonKey }

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

    func loadSubmissions(accessToken: String) async {
        isLoadingSubmissions = true
        error = nil
        defer { isLoadingSubmissions = false }

        var components = URLComponents(url: baseURL.appendingPathComponent("rest/v1/course_submissions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "select", value: "id,author_id,author_email,author_name,contact,title,description,video_url,status,created_at"),
            URLQueryItem(name: "order", value: "created_at.desc")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw NSError(domain: "CoursesService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить заявки: \(body)"])
            }
            submissions = try JSONDecoder().decode([CourseSubmission].self, from: data)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func createSubmission(title: String, description: String, contact: String, authorId: String?, authorEmail: String?, authorName: String?, videoURL: String?, accessToken: String) async -> Bool {
        var post = URLRequest(url: baseURL.appendingPathComponent("rest/v1/course_submissions"))
        post.httpMethod = "POST"
        post.setValue(anonKey, forHTTPHeaderField: "apikey")
        post.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        post.setValue("return=representation", forHTTPHeaderField: "Prefer")

        var body: [String: Any] = [
            "title": title,
            "description": description,
            "contact": contact,
            "status": "pending"
        ]
        if let authorId, !authorId.isEmpty { body["author_id"] = authorId }
        if let authorEmail, !authorEmail.isEmpty { body["author_email"] = authorEmail }
        if let authorName, !authorName.isEmpty { body["author_name"] = authorName }
        if let videoURL, !videoURL.isEmpty { body["video_url"] = videoURL }
        post.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: post)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let details = String(data: data, encoding: .utf8) ?? ""
                self.error = "Заявка не отправлена. \(details)"
                return false
            }
            return true
        } catch {
            self.error = "Заявка не отправлена: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func uploadCourseSubmissionVideo(fileURL: URL, accessToken: String) async -> String? {
        error = nil

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { fileURL.stopAccessingSecurityScopedResource() }
        }

        let ext = normalizedVideoExtension(from: fileURL)
        let mime = videoMimeType(for: ext)
        let path = "course-submissions/\(UUID().uuidString)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/videos/\(path)")

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            self.error = "Не удалось прочитать видео."
            return nil
        }

        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.setValue("3600", forHTTPHeaderField: "Cache-Control")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = data

        do {
            let (body, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let details = String(data: body, encoding: .utf8) ?? ""
                self.error = "Видео заявки не загружено. \(details)"
                return nil
            }
        } catch {
            self.error = "Видео заявки не загружено: \(error.localizedDescription)"
            return nil
        }

        return baseURL.appendingPathComponent("storage/v1/object/public/videos/\(path)").absoluteString
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

    /// Uploads a lesson video to the existing public `videos` bucket.
    /// If Storage policy rejects this, the editor still supports direct video URLs.
    @discardableResult
    func uploadLessonVideo(courseId: String, lessonId: String, fileURL: URL, accessToken: String) async -> String? {
        error = nil

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess { fileURL.stopAccessingSecurityScopedResource() }
        }

        let ext = normalizedVideoExtension(from: fileURL)
        let mime = videoMimeType(for: ext)
        let path = "courses/\(courseId)/\(lessonId)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/videos/\(path)")

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            self.error = "Не удалось прочитать выбранный видеофайл."
            return nil
        }

        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.setValue("3600", forHTTPHeaderField: "Cache-Control")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = data

        do {
            let (body, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let details = String(data: body, encoding: .utf8) ?? ""
                self.error = "Видео не загружено. Блокер: Storage bucket `videos` должен разрешать authenticated/developer INSERT/UPDATE в `courses/*`. \(details)"
                return nil
            }
        } catch {
            self.error = "Видео не загружено: \(error.localizedDescription)"
            return nil
        }

        return baseURL.appendingPathComponent("storage/v1/object/public/videos/\(path)").absoluteString
    }

    /// Uploads a JPEG cover for a single lesson video. The returned URL is saved
    /// inside the lesson JSON as `thumbnailUrl` by the course editor.
    @discardableResult
    func uploadLessonThumbnail(courseId: String, lessonId: String, jpegData: Data, accessToken: String) async -> String? {
        error = nil

        let path = "\(courseId)/lessons/\(lessonId)-\(Int(Date().timeIntervalSince1970)).jpg"
        let uploadURL = baseURL.appendingPathComponent("storage/v1/object/course-covers/\(path)")
        var req = URLRequest(url: uploadURL)
        req.httpMethod = "POST"
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        req.setValue("3600", forHTTPHeaderField: "Cache-Control")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        req.httpBody = jpegData

        do {
            let (body, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let details = String(data: body, encoding: .utf8) ?? ""
                self.error = "Обложка урока не загружена. Проверь bucket course-covers в Supabase Storage. \(details)"
                return nil
            }
        } catch {
            self.error = "Обложка урока не загружена: \(error.localizedDescription)"
            return nil
        }

        return baseURL.appendingPathComponent("storage/v1/object/public/course-covers/\(path)").absoluteString
    }

    private func normalizedVideoExtension(from url: URL) -> String {
        let raw = url.pathExtension.lowercased()
        guard !raw.isEmpty else { return "mp4" }
        switch raw {
        case "mov", "m4v", "mp4": return raw
        default: return "mp4"
        }
    }

    private func videoMimeType(for ext: String) -> String {
        switch ext {
        case "mov": return "video/quicktime"
        case "m4v": return "video/x-m4v"
        default: return "video/mp4"
        }
    }
}
